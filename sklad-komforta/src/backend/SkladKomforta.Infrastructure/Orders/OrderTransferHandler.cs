using System.Data.Common;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using SkladKomforta.Application.Identity;
using SkladKomforta.Application.Onboarding;
using SkladKomforta.Application.Quotes;
using SkladKomforta.Infrastructure.Kanban;
using SkladKomforta.Infrastructure.Quotes;
using static SkladKomforta.Infrastructure.Orders.OrderStore;

namespace SkladKomforta.Infrastructure.Orders;

/// <summary>
/// Перенос по столбцам-триггерам. КП/ПКП → комплектация: создаёт комплектацию
/// из выбранных вариантов (или типа) либо синхронизирует уже созданную и
/// перемещает её карточку. Комплектация → КП: только перемещает карточку КП.
/// Связь карточек — общий <c>work_item_id</c>.
/// </summary>
internal sealed class OrderTransferHandler : IKanbanColumnEntryHandler
{
    /// <summary>Системные поля строки хранятся в колонках, а не в значениях.</summary>
    private static readonly HashSet<string> SystemFieldCodes =
        new(StringComparer.Ordinal) { "name", "marking", "quantity", "unit" };

    /// <inheritdoc />
    public async Task OnCardEnteredColumnAsync(
        DbConnection connection,
        DbTransaction transaction,
        Guid actorUserId,
        Guid boardId,
        Guid cardId,
        Guid columnId,
        CancellationToken cancellationToken)
    {
        Guid targetBoardId;
        Guid targetColumnId;
        string? sourceSpecialization;
        string? targetSpecialization;
        await using (var command = connection.CreateCommand())
        {
            command.Transaction = transaction;
            command.CommandText = """
                SELECT transfer.target_workflow_id, transfer.target_column_id,
                       source_workflow.specialization, target_workflow.specialization
                  FROM workflow_column_transfers AS transfer
                  JOIN workflow_columns AS source_column ON source_column.id = transfer.column_id
                  JOIN workflows AS source_workflow ON source_workflow.id = source_column.workflow_id
                  JOIN workflows AS target_workflow ON target_workflow.id = transfer.target_workflow_id
                 WHERE transfer.column_id = @column_id AND source_column.workflow_id = @workflow_id
                """;
            Add(command, "column_id", columnId);
            Add(command, "workflow_id", boardId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken)) return;
            targetBoardId = reader.GetGuid(0);
            targetColumnId = reader.GetGuid(1);
            sourceSpecialization = reader.IsDBNull(2) ? null : reader.GetString(2);
            targetSpecialization = reader.IsDBNull(3) ? null : reader.GetString(3);
        }

        var sourceIsQuote = sourceSpecialization is WorkflowSpecializationCodes.Quote
            or WorkflowSpecializationCodes.QuoteAndPrequote;
        if (sourceIsQuote && targetSpecialization == WorkflowSpecializationCodes.Order)
            await TransferQuoteAsync(connection, transaction, actorUserId, cardId,
                targetBoardId, targetColumnId, cancellationToken);
        else if (sourceSpecialization == WorkflowSpecializationCodes.Order &&
                 targetSpecialization is WorkflowSpecializationCodes.Quote or WorkflowSpecializationCodes.QuoteAndPrequote)
            await MoveLinkedCardAsync(connection, transaction, actorUserId,
                await WorkItemOfAsync(connection, transaction, cardId, cancellationToken),
                targetBoardId, targetColumnId, cancellationToken);
    }

    /// <summary>Создаёт или синхронизирует комплектацию по выбранному в КП.</summary>
    private static async Task TransferQuoteAsync(
        DbConnection connection,
        DbTransaction transaction,
        Guid actorUserId,
        Guid quoteCardId,
        Guid targetBoardId,
        Guid targetColumnId,
        CancellationToken token)
    {
        var quote = await ReadQuoteAsync(connection, transaction, quoteCardId, token)
                    ?? throw new IdentityException(409, "order_transfer_quote_missing",
                        "У карточки нет сохранённого КП — переносить в комплектацию нечего.");
        var boardFields = await ReadBoardFieldsAsync(connection, transaction, targetBoardId, token);
        var rows = await ReadChosenRowsAsync(connection, transaction, quote, boardFields, token);

        var existing = await ReadLinkedOrderAsync(connection, transaction, quote.WorkItemId, targetBoardId, token);
        if (existing is null)
        {
            await CreateOrderAsync(connection, transaction, actorUserId, quote, rows,
                targetBoardId, targetColumnId, token);
            return;
        }

        var before = await ReadAsync(connection, transaction, targetBoardId, existing.CardId, false, false, token);
        var reorder = await IsReorderColumnAsync(connection, transaction, targetBoardId, existing.ColumnId, token);
        var orderId = existing.OrderId ?? await InsertHeaderAsync(
            connection, transaction, actorUserId, quote, targetBoardId, existing.CardId, token);
        await SyncPositionsAsync(connection, transaction, actorUserId, orderId, rows, reorder, token);
        await ExecuteAsync(connection, transaction, """
            UPDATE orders SET source_quote_id = COALESCE(source_quote_id, @quote_id),
                              updated_by = @actor, updated_at = now()
             WHERE id = @id
            """, token, ("id", orderId), ("quote_id", quote.Id), ("actor", actorUserId));
        await MoveLinkedCardAsync(connection, transaction, actorUserId, quote.WorkItemId,
            targetBoardId, targetColumnId, token);
        var after = await ReadAsync(connection, transaction, targetBoardId, existing.CardId, false, false, token);
        await WriteAuditAsync(connection, transaction, actorUserId, orderId, "synced_from_quote",
            before is null ? null : AuditSnapshot(before), after is null ? null : AuditSnapshot(after), token);
    }

    /// <summary>Первый перенос: новая карточка комплектации с тем же рабочим объектом.</summary>
    private static async Task CreateOrderAsync(
        DbConnection connection,
        DbTransaction transaction,
        Guid actorUserId,
        QuoteHeader quote,
        IReadOnlyList<TransferRow> rows,
        Guid targetBoardId,
        Guid targetColumnId,
        CancellationToken token)
    {
        var cardId = Guid.NewGuid();
        await ExecuteAsync(connection, transaction, """
            INSERT INTO kanban_cards
                (id, work_item_id, workflow_id, column_id, category_id, title, values,
                 sort_order, created_by, updated_by)
            VALUES
                (@id, @work_item_id, @workflow_id, @column_id, NULL, @title, '{}'::jsonb,
                 COALESCE((SELECT min(sort_order) - 1 FROM kanban_cards
                           WHERE workflow_id = @workflow_id AND column_id = @column_id
                             AND deleted_at IS NULL), 0),
                 @actor, @actor)
            """, token,
            ("id", cardId), ("work_item_id", quote.WorkItemId), ("workflow_id", targetBoardId),
            ("column_id", targetColumnId), ("title", quote.Title), ("actor", actorUserId));
        var orderId = await InsertHeaderAsync(connection, transaction, actorUserId, quote, targetBoardId, cardId, token);
        var reorder = await IsReorderColumnAsync(connection, transaction, targetBoardId, targetColumnId, token);
        await SyncPositionsAsync(connection, transaction, actorUserId, orderId, rows, reorder, token);
        var created = await ReadAsync(connection, transaction, targetBoardId, cardId, false, false, token);
        await WriteAuditAsync(connection, transaction, actorUserId, orderId, "created_from_quote",
            null, created is null ? null : AuditSnapshot(created), token);
    }

    /// <summary>Шапка из КП: адрес = название КП; стороны, менеджер и РОП — из КП.</summary>
    private static async Task<Guid> InsertHeaderAsync(
        DbConnection connection,
        DbTransaction transaction,
        Guid actorUserId,
        QuoteHeader quote,
        Guid boardId,
        Guid cardId,
        CancellationToken token)
    {
        var orderId = Guid.NewGuid();
        await ExecuteAsync(connection, transaction, """
            INSERT INTO orders
                (id, workflow_id, card_id, title, client_id, executor_company_id,
                 manager_user_id, sales_head_user_id, source_quote_id, created_by, updated_by)
            VALUES
                (@id, @workflow_id, @card_id, @title, @client_id, @executor_id,
                 @manager_id, @sales_head_id, @quote_id, @actor, @actor)
            """, token,
            ("id", orderId), ("workflow_id", boardId), ("card_id", cardId), ("title", quote.Title),
            ("client_id", quote.ClientId), ("executor_id", quote.ExecutorCompanyId),
            ("manager_id", Db(quote.ManagerUserId)), ("sales_head_id", Db(quote.SalesHeadUserId)),
            ("quote_id", quote.Id), ("actor", actorUserId));
        return orderId;
    }

    /// <summary>
    /// Приводит строки, перенесённые из КП, к новому выбору: новые добавляет,
    /// изменившееся в КП количество обновляет, исчезнувшие удаляет. Строки,
    /// добавленные в комплектации вручную, и заполненные поля не трогает.
    /// </summary>
    private static async Task SyncPositionsAsync(
        DbConnection connection,
        DbTransaction transaction,
        Guid actorUserId,
        Guid orderId,
        IReadOnlyList<TransferRow> rows,
        bool reorder,
        CancellationToken token)
    {
        var runtime = await PostgresQuoteService.ReadCalculationConfigurationAsync(connection, transaction, token);
        var existing = new Dictionary<string, (Guid Id, decimal? SourceQuantity, decimal Quantity, IReadOnlyDictionary<string, JsonElement> Values)>(StringComparer.Ordinal);
        await using (var command = connection.CreateCommand())
        {
            command.Transaction = transaction;
            command.CommandText = """
                SELECT position.id, position.source_key, position.source_quantity, position.quantity, position.values::text
                  FROM order_positions AS position
                  JOIN order_sections AS section ON section.id = position.order_section_id
                  JOIN order_categories AS category ON category.id = section.order_category_id
                 WHERE category.order_id = @order_id AND position.source_key IS NOT NULL
                """;
            Add(command, "order_id", orderId);
            await using var reader = await command.ExecuteReaderAsync(token);
            while (await reader.ReadAsync(token))
                existing[reader.GetString(1)] = (reader.GetGuid(0), reader.IsDBNull(2) ? null : reader.GetDecimal(2),
                    reader.GetDecimal(3), JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(reader.GetString(4), JsonOptions)!);
        }

        // Сохраняем поля существующей строки при переходе со старого ключа,
        // в котором расчётная сумма ещё участвовала в сравнении.
        foreach (var row in rows.Where(row => !existing.ContainsKey(row.Key)))
        {
            var legacyKey = row.LegacyKeys.FirstOrDefault(existing.ContainsKey);
            if (legacyKey is null) continue;
            var current = existing[legacyKey];
            await ExecuteAsync(connection, transaction,
                "UPDATE order_positions SET source_key = @key WHERE id = @id", token,
                ("key", row.Key), ("id", current.Id));
            existing.Remove(legacyKey);
            // Пересчитываем количество и сумму объединённой строки.
            existing[row.Key] = (current.Id, null, current.Quantity, current.Values);
        }

        var wanted = rows.Select(row => row.Key).ToHashSet(StringComparer.Ordinal);
        foreach (var (_, position) in existing.Where(item => !wanted.Contains(item.Key)))
            await ExecuteAsync(connection, transaction,
                "DELETE FROM order_positions WHERE id = @id", token, ("id", position.Id));

        foreach (var row in rows)
        {
            if (existing.TryGetValue(row.Key, out var current))
            {
                var quantity = current.SourceQuantity != row.Quantity ? row.Quantity : current.Quantity;
                var recalculated = row with { Quantity = quantity };
                if (runtime.CategoryClientIds.TryGetValue(row.CatalogCategoryId, out var category))
                {
                    var inputs = (row.CalculationInputs ?? row.Values).ToDictionary(item => item.Key, item => item.Value);
                    foreach (var item in current.Values) inputs[item.Key] = item.Value;
                    recalculated = RecalculateRow(row with { Quantity = quantity, CalculationInputs = inputs }, category,
                        runtime.Rules, runtime.Pipelines, runtime.PercentFields.GetValueOrDefault(category),
                        row.Values.Keys.ToHashSet(StringComparer.Ordinal), runtime.TotalFields?.GetValueOrDefault(category));
                }
                await ExecuteAsync(connection, transaction, """
                    UPDATE order_positions
                       SET quantity = @quantity, source_quantity = @source_quantity,
                           values = values || CAST(@totals AS jsonb),
                           updated_by = @actor, updated_at = now()
                     WHERE id = @id
                    """, token, ("id", current.Id), ("quantity", recalculated.Quantity), ("source_quantity", row.Quantity), ("actor", actorUserId),
                    ("totals", JsonSerializer.Serialize(recalculated.Values.Where(item => recalculated.CalculatedFields.Contains(item.Key))
                        .ToDictionary(item => item.Key, item => item.Value), JsonOptions)));
                continue;
            }

            var sectionId = await EnsureSectionAsync(connection, transaction, orderId, row, token);
            await ExecuteAsync(connection, transaction, """
                INSERT INTO order_positions
                    (order_section_id, catalog_item_id, name_snapshot, marking_snapshot, unit_snapshot,
                     quantity, is_reorder, source_key, source_quantity, values, sort_order,
                     created_by, updated_by)
                VALUES
                    (@section_id, @catalog_item_id, @name, @marking, @unit,
                     @quantity, @is_reorder, @source_key, @quantity, CAST(@values AS jsonb),
                     COALESCE((SELECT max(sort_order) + 1 FROM order_positions
                               WHERE order_section_id = @section_id), 0),
                     @actor, @actor)
                """, token,
                ("section_id", sectionId), ("catalog_item_id", Db(row.CatalogItemId)),
                ("name", row.Name), ("marking", row.Marking), ("unit", row.Unit),
                ("quantity", row.Quantity), ("is_reorder", reorder), ("source_key", row.Key),
                ("values", JsonSerializer.Serialize(row.Values, JsonOptions)), ("actor", actorUserId));
        }
    }

    /// <summary>Находит или создаёт категорию и раздел комплектации для строки из КП.</summary>
    private static async Task<Guid> EnsureSectionAsync(
        DbConnection connection, DbTransaction transaction, Guid orderId, TransferRow row, CancellationToken token)
    {
        Guid categoryId;
        await using (var command = connection.CreateCommand())
        {
            command.Transaction = transaction;
            command.CommandText = """
                SELECT id FROM order_categories
                 WHERE order_id = @order_id AND catalog_category_id = @catalog_category_id
                """;
            Add(command, "order_id", orderId);
            Add(command, "catalog_category_id", row.CatalogCategoryId);
            categoryId = await command.ExecuteScalarAsync(token) as Guid? ?? Guid.Empty;
        }
        if (categoryId == Guid.Empty)
        {
            categoryId = Guid.NewGuid();
            await ExecuteAsync(connection, transaction, """
                INSERT INTO order_categories (id, order_id, catalog_category_id, name_snapshot, sort_order)
                VALUES (@id, @order_id, @catalog_category_id, @name,
                        COALESCE((SELECT max(sort_order) + 1 FROM order_categories WHERE order_id = @order_id), 0))
                """, token,
                ("id", categoryId), ("order_id", orderId),
                ("catalog_category_id", row.CatalogCategoryId), ("name", row.CategoryName));
        }

        await using (var command = connection.CreateCommand())
        {
            command.Transaction = transaction;
            command.CommandText = """
                SELECT id FROM order_sections
                 WHERE order_category_id = @category_id
                   AND catalog_section_id IS NOT DISTINCT FROM @catalog_section_id
                 ORDER BY sort_order
                 LIMIT 1
                """;
            Add(command, "category_id", categoryId);
            var parameter = command.CreateParameter();
            parameter.ParameterName = "catalog_section_id";
            parameter.Value = Db(row.CatalogSectionId);
            parameter.DbType = System.Data.DbType.Guid;
            command.Parameters.Add(parameter);
            if (await command.ExecuteScalarAsync(token) is Guid sectionId) return sectionId;
        }

        var newSectionId = Guid.NewGuid();
        await ExecuteAsync(connection, transaction, """
            INSERT INTO order_sections (id, order_category_id, catalog_section_id, name_snapshot, sort_order)
            VALUES (@id, @category_id, @catalog_section_id, @name,
                    COALESCE((SELECT max(sort_order) + 1 FROM order_sections WHERE order_category_id = @category_id), 0))
            """, token,
            ("id", newSectionId), ("category_id", categoryId),
            ("catalog_section_id", Db(row.CatalogSectionId)), ("name", row.SectionName));
        return newSectionId;
    }

    /// <summary>
    /// Позиции выбранных вариантов (или всех вариантов выбранного типа) одним
    /// списком: только категории канбана комплектации и назначенные ему поля.
    /// Строки, совпадающие по всем переносимым полям, суммируются.
    /// </summary>
    private static async Task<IReadOnlyList<TransferRow>> ReadChosenRowsAsync(
        DbConnection connection,
        DbTransaction transaction,
        QuoteHeader quote,
        Dictionary<Guid, HashSet<string>> boardFields,
        CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            WITH chosen AS (
                SELECT selection.variant_id
                  FROM quote_proposal_type_selections AS selection
                  JOIN quote_proposal_types AS proposal_type ON proposal_type.id = selection.proposal_type_id
                 WHERE proposal_type.quote_id = @quote_id AND @mode = 'variant'
                UNION
                SELECT variant.id
                  FROM quote_client_type_selections AS selection
                  JOIN quote_variants AS variant ON variant.proposal_type_id = selection.proposal_type_id
                 WHERE selection.quote_id = @quote_id AND @mode = 'proposal_type'
            )
            SELECT category.catalog_category_id, category.name_snapshot,
                   section.catalog_section_id, section.name_snapshot,
                   position.catalog_item_id, position.name_snapshot, position.marking_snapshot,
                   position.unit_snapshot, position.quantity, position.values::text
              FROM quote_positions AS position
              JOIN quote_variant_sections AS section ON section.id = position.variant_section_id
              JOIN quote_variant_categories AS category ON category.id = section.variant_category_id
              JOIN quote_variants AS variant ON variant.id = category.variant_id
              JOIN quote_proposal_types AS proposal_type ON proposal_type.id = variant.proposal_type_id
             WHERE variant.id IN (SELECT variant_id FROM chosen)
             ORDER BY proposal_type.sort_order, variant.sort_order, category.sort_order,
                      section.sort_order, position.sort_order, position.id
            """;
        Add(command, "quote_id", quote.Id);
        Add(command, "mode", quote.SelectionMode);

        var rows = new List<TransferRow>();
        var byKey = new Dictionary<string, int>(StringComparer.Ordinal);
        var anyChosen = await ChosenExistsAsync(connection, transaction, quote, token);
        await using (var reader = await command.ExecuteReaderAsync(token))
        {
            while (await reader.ReadAsync(token))
            {
                if (reader.IsDBNull(0)) continue;
                var categoryId = reader.GetGuid(0);
                if (!boardFields.TryGetValue(categoryId, out var allowed)) continue;
                var inputs = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(reader.GetString(9), JsonOptions)
                             ?? new Dictionary<string, JsonElement>();
                var values = inputs
                    .Where(item => allowed.Contains(item.Key) && !SystemFieldCodes.Contains(item.Key))
                    .OrderBy(item => item.Key, StringComparer.Ordinal)
                    .ToDictionary(item => item.Key, item => item.Value, StringComparer.Ordinal);
                var row = new TransferRow(
                    categoryId, reader.GetString(1),
                    reader.IsDBNull(2) ? null : reader.GetGuid(2), reader.GetString(3),
                    reader.IsDBNull(4) ? null : reader.GetGuid(4),
                    reader.GetString(5), reader.GetString(6), reader.GetString(7),
                    reader.GetDecimal(8), values, string.Empty);
                row = row with
                {
                    Key = KeyOf(row),
                    CalculationInputs = inputs,
                    LegacyKeys = [KeyOf(row, includeTotal: true), KeyOf(row, legacy: true), KeyOf(row, allFields: true)],
                };
                if (byKey.TryGetValue(row.Key, out var index))
                    rows[index] = MergeRows(rows[index], row);
                else
                {
                    byKey[row.Key] = rows.Count;
                    rows.Add(row);
                }
            }
        }

        if (!anyChosen)
            throw new IdentityException(409, "order_transfer_selection_missing",
                "В КП ещё не выбран вариант или тип — переносить в комплектацию нечего.");
        if (rows.Count == 0)
            throw new IdentityException(409, "order_transfer_empty",
                "В выбранном в КП нет позиций категорий, доступных канбану комплектации.");
        var runtime = await PostgresQuoteService.ReadCalculationConfigurationAsync(connection, transaction, token);
        return rows.Select(row => runtime.CategoryClientIds.TryGetValue(row.CatalogCategoryId, out var category)
            ? RecalculateRow(row, category, runtime.Rules, runtime.Pipelines,
                runtime.PercentFields.GetValueOrDefault(category), boardFields[row.CatalogCategoryId], runtime.TotalFields?.GetValueOrDefault(category))
            : row).ToArray();
    }

    internal static TransferRow RecalculateRow(
        TransferRow row, string category, IReadOnlyList<CalculationRuleDraft> rules,
        IReadOnlyList<MoneyPipelineDraft> pipelines, IReadOnlySet<string>? percentFields,
        IReadOnlySet<string> allowed, IReadOnlySet<string>? totalFields = null)
    {
        var inputs = row.CalculationInputs ?? row.Values;
        decimal? Number(string code) => inputs.TryGetValue(code, out var value)
            && value.ValueKind == JsonValueKind.Number && value.TryGetDecimal(out var number) ? number : null;
        var calculationRules = rules.Where(rule => rule.EventType is "row_calculation" or "variant_calculation").ToArray();
        var calculatedFields = calculationRules.Where(rule => rule.IsEnabled && rule.CategoryClientId == category)
            .SelectMany(rule => rule.Actions)
            .Where(action => action.ActionType is "calculate_field" or "set_field")
            .Select(action => action.TargetFieldCode!)
            .Concat(pipelines.Where(pipeline => pipeline.CategoryClientId == category).Select(pipeline => pipeline.ResultFieldCode))
            .Append("line_total").Append("excluded_from_calc").ToHashSet(StringComparer.Ordinal);
        var result = QuoteConfiguredCalculationEngine.Calculate(new SaveQuotePositionRequest(
            null, row.CatalogItemId, row.Name, row.Marking, row.Unit, row.Quantity,
            Number("purchase_price"), Number("base_price") ?? 0m, null,
            Number("markup_value"), Number("discount_value"),
            inputs.TryGetValue("excluded_from_calc", out var excluded) && excluded.ValueKind == JsonValueKind.True,
            inputs), category, calculationRules, pipelines, percentFields, totalFields);
        return row with
        {
            Quantity = result.Quantity,
            Values = result.Values.Where(item => allowed.Contains(item.Key) && !SystemFieldCodes.Contains(item.Key))
                .ToDictionary(item => item.Key, item => item.Value, StringComparer.Ordinal),
            CalculatedFields = calculatedFields,
        };
    }

    private static async Task<bool> ChosenExistsAsync(
        DbConnection connection, DbTransaction transaction, QuoteHeader quote, CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = quote.SelectionMode == "proposal_type"
            ? "SELECT EXISTS (SELECT 1 FROM quote_client_type_selections WHERE quote_id = @quote_id)"
            : """
              SELECT EXISTS (
                  SELECT 1 FROM quote_proposal_type_selections AS selection
                    JOIN quote_proposal_types AS proposal_type ON proposal_type.id = selection.proposal_type_id
                   WHERE proposal_type.quote_id = @quote_id)
              """;
        Add(command, "quote_id", quote.Id);
        return await command.ExecuteScalarAsync(token) is true;
    }

    /// <summary>Отпечаток строки без количества и зависящей от него суммы.</summary>
    internal static string KeyOf(TransferRow row, bool includeTotal = false, bool legacy = false, bool allFields = false)
    {
        var preserveRepresentation = includeTotal || legacy;
        var canonical = JsonSerializer.Serialize(new object?[]
        {
            row.CatalogCategoryId, row.CatalogSectionId, preserveRepresentation ? row.CatalogItemId : null,
            row.Name.Trim(), row.Marking.Trim(), row.Unit.Trim(),
            row.Values.Where(item => includeTotal || item.Key is not "quantity" and not "line_total")
                .Where(item => preserveRepresentation || allFields || OnboardingFieldRegistry.IsSystemField(item.Key))
                .OrderBy(item => item.Key, StringComparer.Ordinal)
                .ToDictionary(item => item.Key,
                    item => preserveRepresentation ? item.Value : NormalizeKeyValue(item.Value),
                    StringComparer.Ordinal),
        }, JsonOptions);
        return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(canonical)));
    }

    private static JsonElement NormalizeKeyValue(JsonElement value) => value.ValueKind switch
    {
        JsonValueKind.Number when value.TryGetDecimal(out var number) =>
            JsonSerializer.Deserialize<JsonElement>(number.ToString("G29", System.Globalization.CultureInfo.InvariantCulture)),
        JsonValueKind.Object => JsonSerializer.SerializeToElement(value.EnumerateObject()
            .OrderBy(property => property.Name, StringComparer.Ordinal)
            .ToDictionary(property => property.Name, property => NormalizeKeyValue(property.Value))),
        JsonValueKind.Array => JsonSerializer.SerializeToElement(value.EnumerateArray().Select(NormalizeKeyValue)),
        _ => value,
    };

    internal static TransferRow MergeRows(TransferRow first, TransferRow second)
    {
        var values = first.Values.ToDictionary(item => item.Key, item => item.Value, StringComparer.Ordinal);
        // Сумма зависит от количества и не определяет идентичность позиции.
        if (first.Values.TryGetValue("line_total", out var firstTotal)
            && second.Values.TryGetValue("line_total", out var secondTotal)
            && firstTotal.ValueKind == JsonValueKind.Number && secondTotal.ValueKind == JsonValueKind.Number
            && firstTotal.TryGetDecimal(out var left) && secondTotal.TryGetDecimal(out var right))
            values["line_total"] = JsonSerializer.SerializeToElement(left + right);
        return first with
        {
            Quantity = first.Quantity + second.Quantity,
            Values = values,
            LegacyKeys = first.LegacyKeys.Concat(second.LegacyKeys).Distinct().ToArray(),
        };
    }

    /// <summary>Перемещает карточку того же рабочего объекта в указанный столбец другого канбана.</summary>
    private static async Task MoveLinkedCardAsync(
        DbConnection connection,
        DbTransaction transaction,
        Guid actorUserId,
        Guid workItemId,
        Guid targetBoardId,
        Guid targetColumnId,
        CancellationToken token)
    {
        Guid cardId;
        Guid columnId;
        await using (var command = connection.CreateCommand())
        {
            command.Transaction = transaction;
            command.CommandText = """
                SELECT id, column_id FROM kanban_cards
                 WHERE work_item_id = @work_item_id AND workflow_id = @workflow_id AND deleted_at IS NULL
                 ORDER BY created_at
                 LIMIT 1
                 FOR UPDATE
                """;
            Add(command, "work_item_id", workItemId);
            Add(command, "workflow_id", targetBoardId);
            await using var reader = await command.ExecuteReaderAsync(token);
            if (!await reader.ReadAsync(token)) return;
            cardId = reader.GetGuid(0);
            columnId = reader.GetGuid(1);
        }
        if (columnId == targetColumnId) return;

        await ExecuteAsync(connection, transaction, """
            UPDATE kanban_cards
               SET column_id = @column_id,
                   is_archived = false,
                   sort_order = COALESCE((SELECT max(other.sort_order) + 1 FROM kanban_cards AS other
                                          WHERE other.workflow_id = @workflow_id
                                            AND other.column_id = @column_id
                                            AND other.deleted_at IS NULL), 0),
                   moved_by = @actor, moved_at = now()
             WHERE id = @id
            """, token,
            ("id", cardId), ("workflow_id", targetBoardId), ("column_id", targetColumnId), ("actor", actorUserId));
        var diff = AuditChanges.Serialize(new { ColumnId = columnId }, new { ColumnId = targetColumnId });
        if (diff is not null)
            await ExecuteAsync(connection, transaction, """
                INSERT INTO audit_log (actor_user_id, entity_type, entity_id, action, diff)
                VALUES (@actor, 'kanban_card', @card_id, 'moved_by_transfer', CAST(@diff AS jsonb))
                """, token, ("actor", actorUserId), ("card_id", cardId), ("diff", diff));
    }

    private static async Task<Guid> WorkItemOfAsync(
        DbConnection connection, DbTransaction transaction, Guid cardId, CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = "SELECT work_item_id FROM kanban_cards WHERE id = @id";
        Add(command, "id", cardId);
        return (Guid)(await command.ExecuteScalarAsync(token)
                      ?? throw new InvalidOperationException("Карточка без рабочего объекта."));
    }

    private static async Task<QuoteHeader?> ReadQuoteAsync(
        DbConnection connection, DbTransaction transaction, Guid cardId, CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            SELECT quote.id, card.work_item_id, quote.title, quote.client_id, quote.executor_company_id,
                   quote.manager_user_id, quote.sales_head_user_id, quote.selection_mode
              FROM quotes AS quote
              JOIN kanban_cards AS card ON card.id = quote.card_id
             WHERE quote.card_id = @card_id AND quote.deleted_at IS NULL
            """;
        Add(command, "card_id", cardId);
        await using var reader = await command.ExecuteReaderAsync(token);
        if (!await reader.ReadAsync(token)) return null;
        return new QuoteHeader(
            reader.GetGuid(0), reader.GetGuid(1), reader.GetString(2), reader.GetGuid(3), reader.GetGuid(4),
            reader.IsDBNull(5) ? null : reader.GetGuid(5), reader.IsDBNull(6) ? null : reader.GetGuid(6),
            reader.GetString(7));
    }

    private static async Task<LinkedOrder?> ReadLinkedOrderAsync(
        DbConnection connection, DbTransaction transaction, Guid workItemId, Guid boardId, CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            SELECT card.id, card.column_id, orders.id
              FROM kanban_cards AS card
              LEFT JOIN orders ON orders.card_id = card.id AND orders.deleted_at IS NULL
             WHERE card.work_item_id = @work_item_id AND card.workflow_id = @workflow_id
               AND card.deleted_at IS NULL
             ORDER BY card.created_at
             LIMIT 1
            """;
        Add(command, "work_item_id", workItemId);
        Add(command, "workflow_id", boardId);
        await using var reader = await command.ExecuteReaderAsync(token);
        if (!await reader.ReadAsync(token)) return null;
        return new LinkedOrder(reader.GetGuid(0), reader.GetGuid(1), reader.IsDBNull(2) ? null : reader.GetGuid(2));
    }

    private sealed record QuoteHeader(
        Guid Id, Guid WorkItemId, string Title, Guid ClientId, Guid ExecutorCompanyId,
        Guid? ManagerUserId, Guid? SalesHeadUserId, string SelectionMode);

    private sealed record LinkedOrder(Guid CardId, Guid ColumnId, Guid? OrderId);

    internal sealed record TransferRow(
        Guid CatalogCategoryId,
        string CategoryName,
        Guid? CatalogSectionId,
        string SectionName,
        Guid? CatalogItemId,
        string Name,
        string Marking,
        string Unit,
        decimal Quantity,
        IReadOnlyDictionary<string, JsonElement> Values,
        string Key)
    {
        public IReadOnlyList<string> LegacyKeys { get; init; } = [];
        public IReadOnlyDictionary<string, JsonElement>? CalculationInputs { get; init; }
        public IReadOnlySet<string> CalculatedFields { get; init; } = new HashSet<string> { "line_total" };
    }
}
