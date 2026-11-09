using System.Data.Common;
using System.Globalization;
using System.Text.Json;
using Npgsql;
using SkladKomforta.Application.Abstractions.Files;
using SkladKomforta.Application.Abstractions.Persistence;
using SkladKomforta.Application.Abstractions.Tenancy;
using SkladKomforta.Application.Authorization;
using SkladKomforta.Application.Identity;
using SkladKomforta.Application.Kanban;
using SkladKomforta.Application.Orders;
using SkladKomforta.Application.Quotes;
using SkladKomforta.Infrastructure.Quotes;
using static SkladKomforta.Infrastructure.Orders.OrderStore;

namespace SkladKomforta.Infrastructure.Orders;

/// <summary>
/// Комплектация карточки канбана: полная замена дерева одной транзакцией.
/// Признаки дозаказа и переноса из КП хранятся сервером и не приходят из
/// редактора, поэтому сохраняются при каждом сохранении.
/// </summary>
internal sealed class PostgresOrderService(
    IDatabaseConnectionFactory connectionFactory,
    IKanbanService kanbanService,
    ITenantContext tenantContext,
    ITenantPermissionEvaluator permissions,
    IObjectStorage objectStorage) : IOrderService
{
    private const string ManagerChangePermission = "orders.manager.change";
    private const string InvoicesPermission = "orders.invoices.manage";
    private const long MaxInvoiceByteSize = 20 * 1024 * 1024;
    private static readonly TimeSpan LinkLifetime = TimeSpan.FromMinutes(5);

    /// <inheritdoc />
    public async Task<OrderDetails> GetAsync(Guid actorUserId, Guid boardId, Guid cardId, CancellationToken cancellationToken)
    {
        await kanbanService.GetCardAsync(actorUserId, boardId, cardId, cancellationToken);
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        var (canChange, canInvoices) = await CapabilitiesAsync(actorUserId, cancellationToken);
        var result = await ReadAsync(connection, null, boardId, cardId, canChange, canInvoices, cancellationToken)
               ?? throw new IdentityException(404, "order_not_found", "Комплектация для этой карточки ещё не создана.");
        var runtime = await PostgresQuoteService.ReadCalculationConfigurationAsync(connection, null, cancellationToken);
        return result with { CurrentCalculationVersion = PostgresQuoteService.CalculationVersion(runtime) };
    }

    /// <inheritdoc />
    public async Task<OrderDetails> CreateAsync(
        Guid actorUserId, Guid boardId, CreateOrderRequest request, CancellationToken cancellationToken)
    {
        OrderRequestValidator.Validate(request.Order);
        var (canChange, canInvoices) = await CapabilitiesAsync(actorUserId, cancellationToken);
        try
        {
            await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
            await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
            var cardId = await CreateCardAsync(connection, transaction, actorUserId, boardId, request, cancellationToken);
            await EnsureReferencesAsync(connection, transaction, boardId, request.Order, null, cancellationToken);
            var runtime = await PostgresQuoteService.ReadCalculationConfigurationAsync(connection, transaction, cancellationToken);
            var version = PostgresQuoteService.CalculationVersion(runtime);

            // Менеджер — создатель карточки, РОП — его руководитель по структуре.
            var salesHead = await SupervisorOfAsync(
                connection, transaction, tenantContext.OrganizationId, actorUserId, cancellationToken);
            var orderId = Guid.NewGuid();
            await ExecuteAsync(connection, transaction, """
                INSERT INTO orders
                    (id, workflow_id, card_id, title, object_type, client_id, executor_company_id,
                     manager_user_id, sales_head_user_id, calculation_version, created_by, updated_by)
                VALUES
                    (@id, @workflow_id, @card_id, @title, @object_type, @client_id, @executor_id,
                     @manager_id, @sales_head_id, @version, @actor, @actor)
                """, cancellationToken,
                ("id", orderId), ("workflow_id", boardId), ("card_id", cardId),
                ("title", request.Order.Title.Trim()), ("object_type", Db(TrimToNull(request.Order.ObjectType))),
                ("client_id", request.Order.ClientId), ("executor_id", request.Order.ExecutorCompanyId),
                ("manager_id", actorUserId), ("sales_head_id", Db(salesHead)),
                ("version", version), ("actor", actorUserId));

            var reorder = await IsReorderColumnAsync(connection, transaction, boardId, request.ColumnId, cancellationToken);
            await ReplaceTreeAsync(connection, transaction, actorUserId, boardId, orderId,
                request.Order.Categories, new Dictionary<Guid, PositionState>(), reorder, cancellationToken);
            var created = await ReadAsync(connection, transaction, boardId, cardId, canChange, canInvoices, cancellationToken)
                          ?? throw new InvalidOperationException("Созданная комплектация не найдена в текущей транзакции.");
            await WriteAuditAsync(connection, transaction, actorUserId, orderId, "created",
                null, AuditSnapshot(created), cancellationToken);
            await transaction.CommitAsync(cancellationToken);
            return created with { CurrentCalculationVersion = version };
        }
        catch (PostgresException exception)
        {
            throw Translate(exception);
        }
    }

    /// <inheritdoc />
    public async Task<OrderDetails> SaveAsync(
        Guid actorUserId, Guid boardId, Guid cardId, SaveOrderRequest request, CancellationToken cancellationToken)
    {
        OrderRequestValidator.Validate(request);
        var card = await kanbanService.GetCardAsync(actorUserId, boardId, cardId, cancellationToken);
        var (canChange, canInvoices) = await CapabilitiesAsync(actorUserId, cancellationToken);
        try
        {
            await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
            await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
            await LockOrderCardAsync(connection, transaction, boardId, cardId, cancellationToken);
            var before = await ReadAsync(connection, transaction, boardId, cardId, canChange, canInvoices, cancellationToken)
                         ?? throw new IdentityException(404, "order_not_found", "Комплектация для этой карточки ещё не создана.");
            var runtime = await PostgresQuoteService.ReadCalculationConfigurationAsync(connection, transaction, cancellationToken);
            var version = PostgresQuoteService.CalculationVersion(runtime);
            if (before.CalculationVersion != version)
                throw new IdentityException(409, "order_calculation_outdated",
                    "Расчётные правила изменились. Сначала проверьте и примените новый расчёт.");
            await EnsureReferencesAsync(connection, transaction, boardId, request, canChange ? request : null, cancellationToken);

            // Без права менеджер и РОП остаются прежними, что бы ни прислал клиент.
            var manager = canChange ? request.ManagerUserId : before.ManagerUserId;
            var salesHead = canChange ? request.SalesHeadUserId : before.SalesHeadUserId;
            await ExecuteAsync(connection, transaction, """
                UPDATE orders
                   SET title = @title, object_type = @object_type, client_id = @client_id,
                       executor_company_id = @executor_id, manager_user_id = @manager_id,
                       sales_head_user_id = @sales_head_id, calculation_version = @version,
                       updated_by = @actor, updated_at = now()
                 WHERE id = @id
                """, cancellationToken,
                ("id", before.Id), ("title", request.Title.Trim()),
                ("object_type", Db(TrimToNull(request.ObjectType))), ("client_id", request.ClientId),
                ("executor_id", request.ExecutorCompanyId), ("manager_id", Db(manager)),
                ("sales_head_id", Db(salesHead)), ("version", version), ("actor", actorUserId));
            await ExecuteAsync(connection, transaction, """
                UPDATE kanban_cards SET title = @title, updated_by = @actor, updated_at = now()
                 WHERE id = @card_id AND workflow_id = @workflow_id AND deleted_at IS NULL
                """, cancellationToken,
                ("title", request.Title.Trim()), ("actor", actorUserId),
                ("card_id", cardId), ("workflow_id", boardId));

            var states = await ReadPositionStateAsync(connection, transaction, before.Id, cancellationToken);
            var reorder = await IsReorderColumnAsync(connection, transaction, boardId, card.ColumnId, cancellationToken);
            await ReplaceTreeAsync(connection, transaction, actorUserId, boardId, before.Id,
                request.Categories, states, reorder, cancellationToken);
            var after = await ReadAsync(connection, transaction, boardId, cardId, canChange, canInvoices, cancellationToken)
                        ?? throw new InvalidOperationException("Сохранённая комплектация не найдена в текущей транзакции.");
            await WriteAuditAsync(connection, transaction, actorUserId, before.Id, "updated",
                AuditSnapshot(before), AuditSnapshot(after), cancellationToken);
            await transaction.CommitAsync(cancellationToken);
            return after with { CurrentCalculationVersion = version };
        }
        catch (PostgresException exception)
        {
            throw Translate(exception);
        }
    }

    public async Task<OrderCalculationPreview> PreviewCalculationAsync(
        Guid actorUserId, Guid boardId, Guid cardId, CancellationToken cancellationToken)
    {
        await kanbanService.GetCardAsync(actorUserId, boardId, cardId, cancellationToken);
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        var order = await ReadAsync(connection, null, boardId, cardId, false, false, cancellationToken)
            ?? throw new IdentityException(404, "order_not_found", "Комплектация не найдена.");
        var runtime = await PostgresQuoteService.ReadCalculationConfigurationAsync(connection, null, cancellationToken);
        var boardFields = await ReadBoardFieldsAsync(connection, null, boardId, cancellationToken);
        return CalculatePreview(order, runtime, boardFields).Preview;
    }

    public async Task<OrderDetails> ApplyCalculationAsync(
        Guid actorUserId, Guid boardId, Guid cardId,
        ApplyOrderCalculationRequest request, CancellationToken cancellationToken)
    {
        await kanbanService.GetCardAsync(actorUserId, boardId, cardId, cancellationToken);
        var (canChange, canInvoices) = await CapabilitiesAsync(actorUserId, cancellationToken);
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        await LockOrderCardAsync(connection, transaction, boardId, cardId, cancellationToken);
        var before = await ReadAsync(connection, transaction, boardId, cardId, canChange, canInvoices, cancellationToken)
            ?? throw new IdentityException(404, "order_not_found", "Комплектация не найдена.");
        var runtime = await PostgresQuoteService.ReadCalculationConfigurationAsync(connection, transaction, cancellationToken);
        var version = PostgresQuoteService.CalculationVersion(runtime);
        if (request.CurrentCalculationVersion != version || request.OrderUpdatedAt != before.UpdatedAt)
            throw new IdentityException(409, "order_calculation_preview_outdated",
                "Комплектация или правила изменились. Откройте сравнение ещё раз.");
        var boardFields = await ReadBoardFieldsAsync(connection, transaction, boardId, cancellationToken);
        var calculated = CalculatePreview(before, runtime, boardFields);
        foreach (var position in calculated.Positions)
            await ExecuteAsync(connection, transaction, """
                UPDATE order_positions
                   SET quantity = @quantity, values = CAST(@values AS jsonb),
                       updated_by = @actor, updated_at = now()
                 WHERE id = @id
                """, cancellationToken,
                ("id", position.Id), ("quantity", position.Quantity),
                ("values", JsonSerializer.Serialize(position.Values, JsonOptions)), ("actor", actorUserId));
        await ExecuteAsync(connection, transaction, """
            UPDATE orders SET calculation_version = @version,
                              updated_by = @actor, updated_at = now()
             WHERE id = @id
            """, cancellationToken, ("id", before.Id), ("version", version), ("actor", actorUserId));
        var after = await ReadAsync(connection, transaction, boardId, cardId, canChange, canInvoices, cancellationToken)
            ?? throw new InvalidOperationException("Пересчитанная комплектация не найдена.");
        await WriteAuditAsync(connection, transaction, actorUserId, before.Id,
            "calculation_applied", AuditSnapshot(before), AuditSnapshot(after), cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return after with { CurrentCalculationVersion = version };
    }

    private static (OrderCalculationPreview Preview,
        IReadOnlyList<(Guid Id, decimal Quantity, IReadOnlyDictionary<string, JsonElement> Values)> Positions)
        CalculatePreview(OrderDetails order, PostgresQuoteService.QuoteCalculationConfiguration runtime,
            IReadOnlyDictionary<Guid, HashSet<string>> boardFields)
    {
        var version = PostgresQuoteService.CalculationVersion(runtime);
        var changes = new List<OrderCalculationFieldChange>();
        var positions = new List<(Guid, decimal, IReadOnlyDictionary<string, JsonElement>)>();
        var changedPositions = 0;
        foreach (var category in order.Categories)
            foreach (var section in category.Sections)
                foreach (var position in section.Positions)
                {
                    var categoryCode = category.CatalogCategoryId is { } categoryId
                        ? runtime.CategoryClientIds.GetValueOrDefault(categoryId) : null;
                    var values = position.Values;
                    var basePrice = Numeric(values, "base_price") ?? 0m;
                    var input = new SaveQuotePositionRequest(position.Id, position.CatalogItemId,
                        position.Name, position.Marking, position.Unit, position.Quantity,
                        Numeric(values, "purchase_price"), basePrice, null,
                        Numeric(values, "markup_value"), Numeric(values, "discount_value"),
                        values.TryGetValue("excluded_from_calc", out var excluded) && excluded.ValueKind == JsonValueKind.True,
                        values);
                    var result = categoryCode is null ? null : QuoteConfiguredCalculationEngine.Calculate(
                        input, categoryCode, runtime.Rules, runtime.Pipelines,
                        runtime.PercentFields.GetValueOrDefault(categoryCode),
                        runtime.TotalFields?.GetValueOrDefault(categoryCode));
                    var allowed = category.CatalogCategoryId is { } catalogId
                        ? boardFields.GetValueOrDefault(catalogId) : null;
                    IReadOnlyDictionary<string, JsonElement> newValues = result is null
                        ? values
                        : result.Values
                            .Where(item => values.ContainsKey(item.Key) || (allowed?.Contains(item.Key) ?? false))
                            .ToDictionary(item => item.Key, item => item.Value, StringComparer.Ordinal);
                    var newQuantity = result?.Quantity ?? position.Quantity;
                    positions.Add((position.Id, newQuantity, newValues));
                    var positionChanged = newQuantity != position.Quantity;
                    if (positionChanged)
                        changes.Add(new OrderCalculationFieldChange(position.Id, position.Name,
                            "quantity", position.Quantity.ToString(CultureInfo.InvariantCulture),
                            newQuantity.ToString(CultureInfo.InvariantCulture)));
                    foreach (var code in values.Keys.Union(newValues.Keys).OrderBy(code => code))
                    {
                        // Новые системные значения сами по себе не считаются изменением документа.
                        if (!values.ContainsKey(code) &&
                            code is ("name" or "marking" or "unit" or "quantity" or
                                "base_price" or "purchase_price" or "markup_value" or
                                "discount_value" or "excluded_from_calc" or "line_total")) continue;
                        var oldValue = values.GetValueOrDefault(code);
                        var newValue = newValues.GetValueOrDefault(code);
                        var oldText = values.ContainsKey(code) ? oldValue.ToString() : null;
                        var newText = newValues.ContainsKey(code) ? newValue.ToString() : null;
                        if (oldText == newText) continue;
                        changes.Add(new OrderCalculationFieldChange(position.Id, position.Name, code, oldText, newText));
                        positionChanged = true;
                    }
                    if (positionChanged) changedPositions++;
                }
        return (new OrderCalculationPreview(version, order.UpdatedAt, changedPositions, changes), positions);
    }

    private static decimal? Numeric(IReadOnlyDictionary<string, JsonElement> values, string code) =>
        values.TryGetValue(code, out var value) && value.ValueKind == JsonValueKind.Number &&
        value.TryGetDecimal(out var number) ? number : null;

    /// <inheritdoc />
    public async Task<IReadOnlyList<OrderInvoiceSummary>> GetInvoicesAsync(
        Guid actorUserId, Guid boardId, Guid cardId, CancellationToken cancellationToken)
    {
        await kanbanService.GetCardAsync(actorUserId, boardId, cardId, cancellationToken);
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        var orderId = await RequireOrderIdAsync(connection, null, boardId, cardId, cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT invoice.id, invoice.file_name, invoice.byte_size, invoice.ready_at,
                   uploader.display_name, invoice.object_key
              FROM order_invoices AS invoice
              LEFT JOIN public.users AS uploader ON uploader.id = invoice.created_by
             WHERE invoice.order_id = @order_id
               AND invoice.ready_at IS NOT NULL AND invoice.deleted_at IS NULL
             ORDER BY invoice.ready_at, invoice.id
            """;
        Add(command, "order_id", orderId);
        var rows = new List<(Guid Id, string Name, long Size, DateTimeOffset At, string? By, string Key)>();
        await using (var reader = await command.ExecuteReaderAsync(cancellationToken))
        {
            while (await reader.ReadAsync(cancellationToken))
                rows.Add((reader.GetGuid(0), reader.GetString(1), reader.GetInt64(2),
                    new DateTimeOffset(reader.GetFieldValue<DateTime>(3)),
                    reader.IsDBNull(4) ? null : reader.GetString(4), reader.GetString(5)));
        }
        var result = new List<OrderInvoiceSummary>(rows.Count);
        foreach (var row in rows)
            result.Add(new OrderInvoiceSummary(row.Id, row.Name, row.Size, row.At, row.By,
                await objectStorage.CreateDownloadUrlAsync(row.Key, LinkLifetime, cancellationToken)));
        return result;
    }

    /// <inheritdoc />
    public async Task<OrderInvoiceUploadTicket> BeginInvoiceUploadAsync(
        Guid actorUserId, Guid boardId, Guid cardId, BeginOrderInvoiceUploadRequest request, CancellationToken cancellationToken)
    {
        var fileName = Path.GetFileName(request.FileName?.Trim() ?? string.Empty);
        if (fileName.Length is < 1 or > 180)
            throw new IdentityException(400, "order_invoice_name_invalid", "Имя файла счёта должно содержать от 1 до 180 символов.");
        if (!string.Equals(request.ContentType?.Trim(), "application/pdf", StringComparison.OrdinalIgnoreCase))
            throw new IdentityException(400, "order_invoice_type_invalid", "Счёт должен быть в формате PDF.");
        if (request.ByteSize is < 1 or > MaxInvoiceByteSize)
            throw new IdentityException(400, "order_invoice_size_invalid", "Размер счёта не должен превышать 20 МБ.");

        await kanbanService.GetCardAsync(actorUserId, boardId, cardId, cancellationToken);
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        var orderId = await RequireOrderIdAsync(connection, null, boardId, cardId, cancellationToken);
        var invoiceId = Guid.NewGuid();
        var objectKey = $"orders/{orderId:N}/{invoiceId:N}.pdf";
        await ExecuteAsync(connection, null, """
            INSERT INTO order_invoices (id, order_id, object_key, file_name, content_type, byte_size, created_by)
            VALUES (@id, @order_id, @object_key, @file_name, 'application/pdf', @byte_size, @actor)
            """, cancellationToken,
            ("id", invoiceId), ("order_id", orderId), ("object_key", objectKey),
            ("file_name", fileName), ("byte_size", request.ByteSize), ("actor", actorUserId));
        return new OrderInvoiceUploadTicket(
            invoiceId,
            await objectStorage.CreateUploadUrlAsync(objectKey, "application/pdf", LinkLifetime, cancellationToken),
            DateTimeOffset.UtcNow.Add(LinkLifetime));
    }

    /// <inheritdoc />
    public async Task<OrderInvoiceSummary> ConfirmInvoiceUploadAsync(
        Guid actorUserId, Guid boardId, Guid cardId, Guid invoiceId, CancellationToken cancellationToken)
    {
        await kanbanService.GetCardAsync(actorUserId, boardId, cardId, cancellationToken);
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        var orderId = await RequireOrderIdAsync(connection, transaction, boardId, cardId, cancellationToken);
        var invoice = await ReadInvoiceAsync(connection, transaction, orderId, invoiceId, cancellationToken);
        var metadata = await objectStorage.GetMetadataAsync(invoice.ObjectKey, cancellationToken);
        if (metadata is null || metadata.ByteSize != invoice.ByteSize ||
            !string.Equals(metadata.ContentType, "application/pdf", StringComparison.OrdinalIgnoreCase))
            throw new IdentityException(400, "order_invoice_upload_invalid", "Загруженный файл не соответствует выбранному счёту.");
        await ExecuteAsync(connection, transaction,
            "UPDATE order_invoices SET ready_at = COALESCE(ready_at, now()) WHERE id = @id",
            cancellationToken, ("id", invoiceId));
        await WriteAuditAsync(connection, transaction, actorUserId, orderId, "invoice_added",
            null, new { Invoice = invoice.FileName }, cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return (await GetInvoicesAsync(actorUserId, boardId, cardId, cancellationToken))
            .First(item => item.Id == invoiceId);
    }

    /// <inheritdoc />
    public async Task DeleteInvoiceAsync(
        Guid actorUserId, Guid boardId, Guid cardId, Guid invoiceId, CancellationToken cancellationToken)
    {
        await kanbanService.GetCardAsync(actorUserId, boardId, cardId, cancellationToken);
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        var orderId = await RequireOrderIdAsync(connection, transaction, boardId, cardId, cancellationToken);
        var invoice = await ReadInvoiceAsync(connection, transaction, orderId, invoiceId, cancellationToken);
        await ExecuteAsync(connection, transaction,
            "UPDATE order_invoices SET deleted_at = now(), deleted_by = @actor WHERE id = @id",
            cancellationToken, ("id", invoiceId), ("actor", actorUserId));
        if (invoice.IsReady)
            await WriteAuditAsync(connection, transaction, actorUserId, orderId, "invoice_deleted",
                new { Invoice = invoice.FileName }, null, cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        await objectStorage.DeleteAsync(invoice.ObjectKey, cancellationToken);
    }

    private async Task<(bool CanChangeManager, bool CanManageInvoices)> CapabilitiesAsync(
        Guid actorUserId, CancellationToken token) =>
        (await permissions.HasPermissionAsync(actorUserId, tenantContext.OrganizationId, ManagerChangePermission, token),
         await permissions.HasPermissionAsync(actorUserId, tenantContext.OrganizationId, InvoicesPermission, token));

    /// <summary>Создаёт рабочий объект и карточку в столбце с действием «Создать комплектацию».</summary>
    private static async Task<Guid> CreateCardAsync(
        DbConnection connection,
        DbTransaction transaction,
        Guid actorUserId,
        Guid boardId,
        CreateOrderRequest request,
        CancellationToken token)
    {
        await using (var command = connection.CreateCommand())
        {
            command.Transaction = transaction;
            command.CommandText = """
                SELECT workflow.specialization,
                       EXISTS (
                           SELECT 1 FROM workflow_column_creation_actions AS action
                            WHERE action.workflow_id = workflow.id
                              AND action.column_id = @column_id
                              AND action.action_kind = 'order')
                  FROM workflows AS workflow
                 WHERE workflow.id = @workflow_id
                 FOR UPDATE
                """;
            Add(command, "workflow_id", boardId);
            Add(command, "column_id", request.ColumnId);
            await using var reader = await command.ExecuteReaderAsync(token);
            if (!await reader.ReadAsync(token))
                throw new IdentityException(404, "kanban_board_not_found", "Канбан не найден.");
            var isOrderBoard = !reader.IsDBNull(0) && reader.GetString(0) == WorkflowSpecializationCodes.Order;
            if (!isOrderBoard || !reader.GetBoolean(1))
                throw new IdentityException(409, "order_creation_column_invalid",
                    "В выбранном столбце нельзя создать комплектацию.");
        }

        var cardId = Guid.NewGuid();
        await ExecuteAsync(connection, transaction,
            "INSERT INTO work_items (id, created_by) VALUES (@id, @actor)",
            token, ("id", cardId), ("actor", actorUserId));
        await ExecuteAsync(connection, transaction, """
            INSERT INTO kanban_cards
                (id, work_item_id, workflow_id, column_id, category_id, title, values,
                 sort_order, created_by, updated_by)
            VALUES
                (@id, @id, @workflow_id, @column_id, NULL, @title, '{}'::jsonb,
                 COALESCE((SELECT min(sort_order) - 1 FROM kanban_cards
                           WHERE workflow_id = @workflow_id AND column_id = @column_id
                             AND deleted_at IS NULL), 0),
                 @actor, @actor)
            """, token,
            ("id", cardId), ("workflow_id", boardId), ("column_id", request.ColumnId),
            ("title", request.Order.Title.Trim()), ("actor", actorUserId));
        return cardId;
    }

    /// <summary>Блокирует карточку и проверяет, что это карточка канбана комплектации.</summary>
    private static async Task LockOrderCardAsync(
        DbConnection connection, DbTransaction transaction, Guid boardId, Guid cardId, CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            SELECT workflow.specialization
              FROM kanban_cards AS card
              JOIN workflows AS workflow ON workflow.id = card.workflow_id
             WHERE card.id = @card_id AND card.workflow_id = @workflow_id AND card.deleted_at IS NULL
             FOR UPDATE OF card
            """;
        Add(command, "card_id", cardId);
        Add(command, "workflow_id", boardId);
        var specialization = await command.ExecuteScalarAsync(token);
        if (specialization is null)
            throw new IdentityException(404, "kanban_card_not_found", "Карточка канбана не найдена.");
        if (specialization is not string code || code != WorkflowSpecializationCodes.Order)
            throw new IdentityException(409, "order_workflow_incompatible", "Комплектация есть только у карточек канбана комплектации.");
    }

    /// <summary>
    /// Проверяет заказчика, исполнителя, тип объекта, категории и разделы канбана
    /// и, если передан <paramref name="employees"/>, выбранных менеджера и РОП.
    /// </summary>
    private static async Task EnsureReferencesAsync(
        DbConnection connection,
        DbTransaction transaction,
        Guid boardId,
        SaveOrderRequest request,
        SaveOrderRequest? employees,
        CancellationToken token)
    {
        if (!await ExistsAsync(connection, transaction,
                "SELECT EXISTS (SELECT 1 FROM clients WHERE id = @id AND deleted_at IS NULL)", request.ClientId, token))
            throw new IdentityException(400, "order_client_invalid", "Выбранный заказчик не найден.");
        if (!await ExistsAsync(connection, transaction,
                "SELECT EXISTS (SELECT 1 FROM companies WHERE id = @id AND deleted_at IS NULL)", request.ExecutorCompanyId, token))
            throw new IdentityException(400, "order_executor_invalid", "Выбранный исполнитель не найден.");

        if (TrimToNull(request.ObjectType) is { } objectType &&
            !(await ReadObjectTypesAsync(connection, transaction, boardId, token)).Contains(objectType))
            throw new IdentityException(400, "order_object_type_invalid",
                $"Тип объекта «{objectType}» не настроен в канбане комплектации.");

        if (employees is not null)
        {
            foreach (var userId in new[] { employees.ManagerUserId, employees.SalesHeadUserId }
                         .Where(item => item.HasValue).Select(item => item!.Value).Distinct())
            {
                if (!await ExistsAsync(connection, transaction, """
                        SELECT EXISTS (
                            SELECT 1 FROM public.organization_members AS member
                              JOIN public.users AS users ON users.id = member.user_id
                              JOIN member_roles AS member_role ON member_role.membership_id = member.id
                             WHERE member.user_id = @id
                               AND member.is_active AND member.deleted_at IS NULL
                               AND users.is_active AND users.deleted_at IS NULL)
                        """, userId, token))
                    throw new IdentityException(400, "order_employee_invalid", "Выбранный сотрудник недоступен.");
            }
        }

        var boardFields = await ReadBoardFieldsAsync(connection, transaction, boardId, token);
        foreach (var category in request.Categories ?? [])
        {
            if (category.CatalogCategoryId is not { } categoryId) continue;
            if (!boardFields.ContainsKey(categoryId))
                throw new IdentityException(400, "order_category_invalid",
                    $"Категория «{category.Name.Trim()}» не доступна в канбане комплектации.");
            foreach (var section in category.Sections ?? [])
            {
                if (section.CatalogSectionId is not { } sectionId) continue;
                await using var command = connection.CreateCommand();
                command.Transaction = transaction;
                command.CommandText =
                    "SELECT EXISTS (SELECT 1 FROM catalog_sections WHERE id = @section_id AND category_id = @category_id)";
                Add(command, "section_id", sectionId);
                Add(command, "category_id", categoryId);
                if (await command.ExecuteScalarAsync(token) is not true)
                    throw new IdentityException(400, "order_section_invalid",
                        $"Раздел «{section.Name.Trim()}» не принадлежит категории «{category.Name.Trim()}».");
            }
        }
    }

    /// <summary>
    /// Заменяет дерево позиций. Значения полей фильтруются по полям, назначенным
    /// канбану; признаки дозаказа и переноса существующих позиций сохраняются,
    /// новые позиции становятся дозаказом, если карточка в столбце дозаказа.
    /// </summary>
    private static async Task ReplaceTreeAsync(
        DbConnection connection,
        DbTransaction transaction,
        Guid actorUserId,
        Guid boardId,
        Guid orderId,
        IReadOnlyList<SaveOrderCategoryRequest>? categories,
        IReadOnlyDictionary<Guid, PositionState> states,
        bool reorder,
        CancellationToken token)
    {
        var boardFields = await ReadBoardFieldsAsync(connection, transaction, boardId, token);
        await ExecuteAsync(connection, transaction,
            "DELETE FROM order_categories WHERE order_id = @order_id", token, ("order_id", orderId));
        var categoryList = categories ?? [];
        for (var categoryIndex = 0; categoryIndex < categoryList.Count; categoryIndex++)
        {
            var category = categoryList[categoryIndex];
            var categoryId = category.Id ?? Guid.NewGuid();
            await ExecuteAsync(connection, transaction, """
                INSERT INTO order_categories (id, order_id, catalog_category_id, name_snapshot, sort_order)
                VALUES (@id, @order_id, @catalog_category_id, @name, @sort)
                """, token,
                ("id", categoryId), ("order_id", orderId),
                ("catalog_category_id", Db(category.CatalogCategoryId)),
                ("name", category.Name.Trim()), ("sort", categoryIndex));
            var allowed = category.CatalogCategoryId is { } catalogCategoryId
                ? boardFields.GetValueOrDefault(catalogCategoryId)
                : null;

            var sections = category.Sections ?? [];
            for (var sectionIndex = 0; sectionIndex < sections.Count; sectionIndex++)
            {
                var section = sections[sectionIndex];
                var sectionId = section.Id ?? Guid.NewGuid();
                await ExecuteAsync(connection, transaction, """
                    INSERT INTO order_sections (id, order_category_id, catalog_section_id, name_snapshot, sort_order)
                    VALUES (@id, @category_id, @catalog_section_id, @name, @sort)
                    """, token,
                    ("id", sectionId), ("category_id", categoryId),
                    ("catalog_section_id", Db(section.CatalogSectionId)),
                    ("name", section.Name.Trim()), ("sort", sectionIndex));

                var positions = section.Positions ?? [];
                for (var positionIndex = 0; positionIndex < positions.Count; positionIndex++)
                {
                    var position = positions[positionIndex];
                    var positionId = position.Id ?? Guid.NewGuid();
                    var state = states.GetValueOrDefault(positionId) ?? new PositionState(reorder, null, null);
                    var values = (position.Values ?? new Dictionary<string, JsonElement>())
                        .Where(item => item.Key != "supplier" && (allowed is null || allowed.Contains(item.Key)))
                        .ToDictionary(item => item.Key, item => item.Value, StringComparer.Ordinal);
                    var catalogItemId = await Catalog.DocumentCatalogItems.ResolveAsync(
                        connection, transaction, actorUserId, position.CatalogItemId,
                        category.CatalogCategoryId, section.CatalogSectionId,
                        position.Name, position.Marking, position.Unit, position.Values, null, token);
                    await ExecuteAsync(connection, transaction, """
                        INSERT INTO order_positions
                            (id, order_section_id, catalog_item_id, name_snapshot, marking_snapshot,
                             unit_snapshot, quantity, is_reorder, source_key, source_quantity,
                             values, sort_order, created_by, updated_by)
                        VALUES
                            (@id, @section_id, @catalog_item_id, @name, @marking,
                             @unit, @quantity, @is_reorder, @source_key, @source_quantity,
                             CAST(@values AS jsonb), @sort, @actor, @actor)
                        """, token,
                        ("id", positionId), ("section_id", sectionId),
                        ("catalog_item_id", Db(catalogItemId)), ("name", position.Name.Trim()),
                        ("marking", position.Marking?.Trim() ?? string.Empty),
                        ("unit", position.Unit?.Trim() ?? string.Empty),
                        ("quantity", position.Quantity), ("is_reorder", state.IsReorder),
                        ("source_key", Db(state.SourceKey)), ("source_quantity", Db(state.SourceQuantity)),
                        ("values", JsonSerializer.Serialize(values, JsonOptions)),
                        ("sort", positionIndex), ("actor", actorUserId));
                }
            }
        }
    }

    private static async Task<Guid> RequireOrderIdAsync(
        DbConnection connection, DbTransaction? transaction, Guid boardId, Guid cardId, CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            SELECT id FROM orders
             WHERE workflow_id = @workflow_id AND card_id = @card_id AND deleted_at IS NULL
            """;
        Add(command, "workflow_id", boardId);
        Add(command, "card_id", cardId);
        return await command.ExecuteScalarAsync(token) as Guid?
               ?? throw new IdentityException(404, "order_not_found", "Комплектация для этой карточки ещё не создана.");
    }

    private static async Task<InvoiceRow> ReadInvoiceAsync(
        DbConnection connection, DbTransaction transaction, Guid orderId, Guid invoiceId, CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            SELECT object_key, file_name, byte_size, ready_at IS NOT NULL
              FROM order_invoices
             WHERE id = @id AND order_id = @order_id AND deleted_at IS NULL
             FOR UPDATE
            """;
        Add(command, "id", invoiceId);
        Add(command, "order_id", orderId);
        await using var reader = await command.ExecuteReaderAsync(token);
        if (!await reader.ReadAsync(token))
            throw new IdentityException(404, "order_invoice_not_found", "Счёт не найден.");
        return new InvoiceRow(reader.GetString(0), reader.GetString(1), reader.GetInt64(2), reader.GetBoolean(3));
    }

    private static async Task<bool> ExistsAsync(
        DbConnection connection, DbTransaction transaction, string sql, Guid id, CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = sql;
        Add(command, "id", id);
        return await command.ExecuteScalarAsync(token) is true;
    }

    private static IdentityException Translate(PostgresException exception) => exception.SqlState switch
    {
        PostgresErrorCodes.ForeignKeyViolation => new IdentityException(
            400, "order_reference_invalid", "Комплектация ссылается на удалённый или недоступный объект."),
        PostgresErrorCodes.UniqueViolation => new IdentityException(
            409, "order_entity_conflict",
            "В категории уже есть такой раздел, или идентификатор элемента используется в другом документе."),
        PostgresErrorCodes.CheckViolation => new IdentityException(
            400, "order_value_invalid", "Комплектация содержит недопустимое значение."),
        _ => new IdentityException(500, "order_save_failed", "Не удалось сохранить комплектацию."),
    };

    private static string? TrimToNull(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    private sealed record InvoiceRow(string ObjectKey, string FileName, long ByteSize, bool IsReady);
}
