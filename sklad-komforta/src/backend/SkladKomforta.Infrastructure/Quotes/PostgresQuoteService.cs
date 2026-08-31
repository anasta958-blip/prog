using System.Data.Common;
using System.Text.Json;
using Npgsql;
using SkladKomforta.Application.Abstractions.Persistence;
using SkladKomforta.Application.Identity;
using SkladKomforta.Application.Kanban;
using SkladKomforta.Application.Quotes;

namespace SkladKomforta.Infrastructure.Quotes;

/// <summary>
/// Хранит специализированные данные КП/ПКП отдельно от универсальной карточки
/// канбана. Полная замена дерева выполняется одной транзакцией и не оставляет
/// частично сохранённых типов, вариантов или позиций.
/// </summary>
internal sealed class PostgresQuoteService(
    IDatabaseConnectionFactory connectionFactory,
    IKanbanService kanbanService) : IQuoteService
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    /// <inheritdoc />
    public async Task<QuoteDetails> GetAsync(
        Guid actorUserId,
        Guid boardId,
        Guid cardId,
        CancellationToken cancellationToken)
    {
        await kanbanService.GetCardAsync(actorUserId, boardId, cardId, cancellationToken);
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        return await ReadQuoteAsync(connection, null, boardId, cardId, cancellationToken)
            ?? throw new IdentityException(404, "quote_not_found", "КП или ПКП для этой карточки ещё не создано.");
    }

    /// <inheritdoc />
    public async Task<QuoteDetails> SaveAsync(
        Guid actorUserId,
        Guid boardId,
        Guid cardId,
        SaveQuoteRequest request,
        CancellationToken cancellationToken)
    {
        QuoteRequestValidator.Validate(request);
        await kanbanService.GetCardAsync(actorUserId, boardId, cardId, cancellationToken);

        try
        {
            await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
            await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
            await EnsureCompatibleCardAsync(
                connection, transaction, boardId, cardId, request.QuoteKind, cancellationToken);
            await EnsureTenantReferencesAsync(connection, transaction, request, cancellationToken);

            var before = await ReadQuoteAsync(connection, transaction, boardId, cardId, cancellationToken);
            var quoteId = await UpsertHeaderAsync(
                connection, transaction, actorUserId, boardId, cardId,
                before?.Id ?? Guid.NewGuid(), request, cancellationToken);
            await ReplaceProposalTreeAsync(
                connection, transaction, actorUserId, quoteId, request.ProposalTypes, cancellationToken);

            var after = await ReadQuoteAsync(connection, transaction, boardId, cardId, cancellationToken)
                ?? throw new InvalidOperationException("Сохранённое предложение не найдено в текущей транзакции.");
            await WriteAuditAsync(
                connection, transaction, actorUserId, quoteId,
                before is null ? "created" : "updated", before, after, cancellationToken);
            await transaction.CommitAsync(cancellationToken);
            return after;
        }
        catch (PostgresException exception) when (exception.SqlState == PostgresErrorCodes.ForeignKeyViolation)
        {
            throw new IdentityException(
                400, "quote_reference_invalid",
                "Предложение ссылается на удалённый или недоступный объект.");
        }
        catch (PostgresException exception) when (exception.SqlState == PostgresErrorCodes.UniqueViolation)
        {
            throw new IdentityException(
                409, "quote_entity_conflict",
                "Идентификатор элемента предложения уже используется в другом документе.");
        }
        catch (PostgresException exception) when (exception.SqlState == PostgresErrorCodes.CheckViolation)
        {
            throw new IdentityException(
                409, "quote_workflow_incompatible",
                "Тип предложения несовместим с выбранным канбаном или содержит недопустимое значение.");
        }
    }

    /// <summary>Блокирует карточку и повторно проверяет её тип непосредственно перед записью.</summary>
    private static async Task EnsureCompatibleCardAsync(
        DbConnection connection,
        DbTransaction transaction,
        Guid boardId,
        Guid cardId,
        string quoteKind,
        CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            SELECT workflow.specialization
            FROM kanban_cards AS card
            JOIN workflows AS workflow ON workflow.id = card.workflow_id
            WHERE card.id = @card_id
              AND card.workflow_id = @workflow_id
              AND card.deleted_at IS NULL
            FOR UPDATE OF card, workflow
            """;
        Add(command, "card_id", cardId);
        Add(command, "workflow_id", boardId);
        await using var reader = await command.ExecuteReaderAsync(token);
        if (!await reader.ReadAsync(token))
            throw new IdentityException(404, "kanban_card_not_found", "Карточка канбана не найдена.");
        var specialization = reader.IsDBNull(0) ? null : reader.GetString(0);

        var compatible = quoteKind switch
        {
            QuoteKindCodes.Quote => specialization is
                WorkflowSpecializationCodes.Quote or WorkflowSpecializationCodes.QuoteAndPrequote,
            QuoteKindCodes.Prequote => specialization == WorkflowSpecializationCodes.QuoteAndPrequote,
            _ => false,
        };
        if (!compatible)
            throw new IdentityException(
                409, "quote_workflow_incompatible",
                quoteKind == QuoteKindCodes.Prequote
                    ? "ПКП можно создать только в канбане типа «КП + ПКП»."
                    : "КП можно создать только в канбане типа «КП» или «КП + ПКП»."
            );
    }

    /// <summary>Проверяет, что заказчик, исполнитель, сотрудники и каталог принадлежат tenant-у.</summary>
    private static async Task EnsureTenantReferencesAsync(
        DbConnection connection,
        DbTransaction transaction,
        SaveQuoteRequest request,
        CancellationToken token)
    {
        if (!await ExistsAsync(connection, transaction,
                "SELECT EXISTS (SELECT 1 FROM clients WHERE id = @id AND deleted_at IS NULL)",
                request.ClientId, token))
            throw new IdentityException(400, "quote_client_invalid", "Выбранный заказчик не найден.");
        if (!await ExistsAsync(connection, transaction,
                "SELECT EXISTS (SELECT 1 FROM companies WHERE id = @id AND deleted_at IS NULL)",
                request.ExecutorCompanyId, token))
            throw new IdentityException(400, "quote_executor_invalid", "Выбранный исполнитель не найден.");

        foreach (var userId in new[] { request.ManagerUserId, request.SalesHeadUserId }
                     .Where(item => item.HasValue).Select(item => item!.Value).Distinct())
        {
            if (!await ExistsAsync(connection, transaction, """
                    SELECT EXISTS (
                        SELECT 1
                        FROM public.organization_members AS member
                        JOIN public.users AS users ON users.id = member.user_id
                        JOIN member_roles AS member_role ON member_role.membership_id = member.id
                        WHERE member.user_id = @id
                          AND member.is_active AND member.deleted_at IS NULL
                          AND users.is_active AND users.deleted_at IS NULL)
                    """, userId, token))
                throw new IdentityException(400, "quote_employee_invalid", "Выбранный сотрудник недоступен.");
        }

        var categoryIds = request.ProposalTypes
            .SelectMany(type => type.Variants)
            .SelectMany(variant => variant.Categories)
            .Where(category => category.CatalogCategoryId.HasValue)
            .Select(category => category.CatalogCategoryId!.Value)
            .Distinct().ToArray();
        await EnsureIdsExistAsync(connection, transaction, "catalog_categories", categoryIds, token);

        var sectionPairs = request.ProposalTypes
            .SelectMany(type => type.Variants)
            .SelectMany(variant => variant.Categories)
            .SelectMany(category => category.Sections
                .Where(section => section.CatalogSectionId.HasValue)
                .Select(section => (SectionId: section.CatalogSectionId!.Value,
                    CategoryId: category.CatalogCategoryId)))
            .ToArray();
        foreach (var pair in sectionPairs)
        {
            if (!pair.CategoryId.HasValue || !await ExistsPairAsync(
                    connection, transaction, pair.SectionId, pair.CategoryId.Value, token))
                throw new IdentityException(
                    400, "quote_catalog_section_invalid",
                    "Раздел предложения не принадлежит выбранной категории каталога.");
        }

        var itemIds = request.ProposalTypes
            .SelectMany(type => type.Variants)
            .SelectMany(variant => variant.Categories)
            .SelectMany(category => category.Sections)
            .SelectMany(section => section.Positions)
            .Where(position => position.CatalogItemId.HasValue)
            .Select(position => position.CatalogItemId!.Value)
            .Distinct().ToArray();
        await EnsureIdsExistAsync(connection, transaction, "catalog_items", itemIds, token, "deleted_at IS NULL");
    }

    private static async Task<bool> ExistsAsync(
        DbConnection connection,
        DbTransaction transaction,
        string sql,
        Guid id,
        CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = sql;
        Add(command, "id", id);
        return await command.ExecuteScalarAsync(token) is true;
    }

    private static async Task<bool> ExistsPairAsync(
        DbConnection connection,
        DbTransaction transaction,
        Guid sectionId,
        Guid categoryId,
        CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = "SELECT EXISTS (SELECT 1 FROM catalog_sections WHERE id = @section_id AND category_id = @category_id)";
        Add(command, "section_id", sectionId);
        Add(command, "category_id", categoryId);
        return await command.ExecuteScalarAsync(token) is true;
    }

    private static async Task EnsureIdsExistAsync(
        DbConnection connection,
        DbTransaction transaction,
        string table,
        Guid[] ids,
        CancellationToken token,
        string? extraCondition = null)
    {
        if (ids.Length == 0) return;
        var allowedTable = table is "catalog_categories" or "catalog_items"
            ? table
            : throw new InvalidOperationException("Недопустимая таблица проверки ссылок.");
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = $"SELECT count(*) FROM {allowedTable} WHERE id = ANY(@ids)" +
                              (extraCondition is null ? string.Empty : $" AND {extraCondition}");
        Add(command, "ids", ids);
        var count = checked((int)(long)(await command.ExecuteScalarAsync(token)
            ?? throw new InvalidOperationException("PostgreSQL не вернул количество ссылок.")));
        if (count != ids.Length)
            throw new IdentityException(
                400, "quote_catalog_reference_invalid",
                "Один или несколько объектов каталога удалены или недоступны.");
    }

    /// <summary>Создаёт или обновляет шапку и синхронизирует название карточки канбана.</summary>
    private static async Task<Guid> UpsertHeaderAsync(
        DbConnection connection,
        DbTransaction transaction,
        Guid actorUserId,
        Guid boardId,
        Guid cardId,
        Guid quoteId,
        SaveQuoteRequest request,
        CancellationToken token)
    {
        await using (var command = connection.CreateCommand())
        {
            command.Transaction = transaction;
            command.CommandText = """
                INSERT INTO quotes
                    (id, workflow_id, card_id, quote_kind, title, client_id,
                     executor_company_id, manager_user_id, sales_head_user_id,
                     selection_mode, additional_information, created_by, updated_by)
                VALUES
                    (@id, @workflow_id, @card_id, @kind, @title, @client_id,
                     @executor_id, @manager_id, @sales_head_id,
                     @selection_mode, @additional_information, @actor, @actor)
                ON CONFLICT (card_id) DO UPDATE SET
                    quote_kind = EXCLUDED.quote_kind,
                    title = EXCLUDED.title,
                    client_id = EXCLUDED.client_id,
                    executor_company_id = EXCLUDED.executor_company_id,
                    manager_user_id = EXCLUDED.manager_user_id,
                    sales_head_user_id = EXCLUDED.sales_head_user_id,
                    selection_mode = EXCLUDED.selection_mode,
                    additional_information = EXCLUDED.additional_information,
                    updated_by = EXCLUDED.updated_by,
                    updated_at = now(),
                    deleted_by = NULL,
                    deleted_at = NULL
                RETURNING id
                """;
            Add(command, "id", quoteId);
            Add(command, "workflow_id", boardId);
            Add(command, "card_id", cardId);
            Add(command, "kind", request.QuoteKind);
            Add(command, "title", request.Title.Trim());
            Add(command, "client_id", request.ClientId);
            Add(command, "executor_id", request.ExecutorCompanyId);
            Add(command, "manager_id", Db(request.ManagerUserId));
            Add(command, "sales_head_id", Db(request.SalesHeadUserId));
            Add(command, "selection_mode", request.SelectionMode);
            Add(command, "additional_information", Db(TrimToNull(request.AdditionalInformation)));
            Add(command, "actor", actorUserId);
            quoteId = (Guid)(await command.ExecuteScalarAsync(token)
                ?? throw new InvalidOperationException("PostgreSQL не вернул идентификатор предложения."));
        }

        await using var card = connection.CreateCommand();
        card.Transaction = transaction;
        card.CommandText = """
            UPDATE kanban_cards
            SET title = @title, updated_by = @actor, updated_at = now()
            WHERE id = @card_id AND workflow_id = @workflow_id AND deleted_at IS NULL
            """;
        Add(card, "title", request.Title.Trim());
        Add(card, "actor", actorUserId);
        Add(card, "card_id", cardId);
        Add(card, "workflow_id", boardId);
        if (await card.ExecuteNonQueryAsync(token) != 1)
            throw new IdentityException(404, "kanban_card_not_found", "Карточка канбана не найдена.");
        return quoteId;
    }

    /// <summary>Полностью заменяет дочернее дерево, сохраняя переданные клиентом UUID.</summary>
    private static async Task ReplaceProposalTreeAsync(
        DbConnection connection,
        DbTransaction transaction,
        Guid actorUserId,
        Guid quoteId,
        IReadOnlyList<SaveQuoteProposalTypeRequest> proposalTypes,
        CancellationToken token)
    {
        await ExecuteAsync(connection, transaction,
            "DELETE FROM quote_proposal_types WHERE quote_id = @quote_id",
            token, ("quote_id", quoteId));

        for (var typeIndex = 0; typeIndex < proposalTypes.Count; typeIndex++)
        {
            var type = proposalTypes[typeIndex];
            var typeId = type.Id ?? Guid.NewGuid();
            await ExecuteAsync(connection, transaction, """
                INSERT INTO quote_proposal_types (id, quote_id, name, sort_order)
                VALUES (@id, @quote_id, @name, @sort_order)
                """, token,
                ("id", typeId), ("quote_id", quoteId),
                ("name", type.Name.Trim()), ("sort_order", typeIndex));

            for (var variantIndex = 0; variantIndex < type.Variants.Count; variantIndex++)
            {
                var variant = type.Variants[variantIndex];
                var variantId = variant.Id ?? Guid.NewGuid();
                await ExecuteAsync(connection, transaction, """
                    INSERT INTO quote_variants
                        (id, proposal_type_id, name, subtitle, vat_rate, sort_order)
                    VALUES (@id, @type_id, @name, @subtitle, @vat_rate, @sort_order)
                    """, token,
                    ("id", variantId), ("type_id", typeId), ("name", variant.Name.Trim()),
                    ("subtitle", Db(TrimToNull(variant.Subtitle))), ("vat_rate", Db(variant.VatRate)),
                    ("sort_order", variantIndex));

                for (var categoryIndex = 0; categoryIndex < variant.Categories.Count; categoryIndex++)
                {
                    var category = variant.Categories[categoryIndex];
                    var categoryId = category.Id ?? Guid.NewGuid();
                    await ExecuteAsync(connection, transaction, """
                        INSERT INTO quote_variant_categories
                            (id, variant_id, catalog_category_id, name_snapshot, sort_order)
                        VALUES (@id, @variant_id, @catalog_category_id, @name, @sort_order)
                        """, token,
                        ("id", categoryId), ("variant_id", variantId),
                        ("catalog_category_id", Db(category.CatalogCategoryId)),
                        ("name", category.Name.Trim()), ("sort_order", categoryIndex));

                    for (var sectionIndex = 0; sectionIndex < category.Sections.Count; sectionIndex++)
                    {
                        var section = category.Sections[sectionIndex];
                        var sectionId = section.Id ?? Guid.NewGuid();
                        await ExecuteAsync(connection, transaction, """
                            INSERT INTO quote_variant_sections
                                (id, variant_category_id, catalog_section_id, name_snapshot,
                                 markup_percent, discount_percent, sort_order)
                            VALUES
                                (@id, @category_id, @catalog_section_id, @name,
                                 @markup_percent, @discount_percent, @sort_order)
                            """, token,
                            ("id", sectionId), ("category_id", categoryId),
                            ("catalog_section_id", Db(section.CatalogSectionId)),
                            ("name", section.Name.Trim()), ("markup_percent", Db(section.MarkupPercent)),
                            ("discount_percent", Db(section.DiscountPercent)), ("sort_order", sectionIndex));

                        for (var positionIndex = 0; positionIndex < section.Positions.Count; positionIndex++)
                        {
                            var position = section.Positions[positionIndex];
                            var calculation = QuoteCalculationEngine.Calculate(position);
                            await ExecuteAsync(connection, transaction, """
                                INSERT INTO quote_positions
                                    (id, variant_section_id, catalog_item_id, name_snapshot,
                                     marking_snapshot, unit_snapshot, quantity, purchase_price,
                                     base_price, manual_price, markup_percent, discount_percent,
                                     line_total, exclude_from_totals, values, sort_order,
                                     created_by, updated_by)
                                VALUES
                                    (@id, @section_id, @catalog_item_id, @name,
                                     @marking, @unit, @quantity, @purchase_price,
                                     @base_price, @manual_price, @markup_percent, @discount_percent,
                                     @line_total, @exclude, CAST(@values AS jsonb), @sort_order,
                                     @actor, @actor)
                                """, token,
                                ("id", position.Id ?? Guid.NewGuid()), ("section_id", sectionId),
                                ("catalog_item_id", Db(position.CatalogItemId)), ("name", position.Name.Trim()),
                                ("marking", position.Marking?.Trim() ?? string.Empty),
                                ("unit", position.Unit?.Trim() ?? string.Empty), ("quantity", position.Quantity),
                                ("purchase_price", Db(position.PurchasePrice)), ("base_price", position.BasePrice),
                                ("manual_price", Db(position.ManualPrice)), ("markup_percent", Db(position.MarkupPercent)),
                                ("discount_percent", Db(position.DiscountPercent)), ("line_total", calculation.LineTotal),
                                ("exclude", position.ExcludeFromTotals),
                                ("values", JsonSerializer.Serialize(position.Values ?? new Dictionary<string, JsonElement>(), JsonOptions)),
                                ("sort_order", positionIndex), ("actor", actorUserId));
                        }
                    }
                }
            }

            if (type.SelectedVariantId.HasValue)
            {
                await ExecuteAsync(connection, transaction, """
                    INSERT INTO quote_proposal_type_selections
                        (proposal_type_id, variant_id, selected_by)
                    VALUES (@type_id, @variant_id, @actor)
                    """, token,
                    ("type_id", typeId), ("variant_id", type.SelectedVariantId.Value),
                    ("actor", actorUserId));
            }
        }
    }

    private static async Task ExecuteAsync(
        DbConnection connection,
        DbTransaction transaction,
        string sql,
        CancellationToken token,
        params (string Name, object Value)[] parameters)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = sql;
        foreach (var parameter in parameters) Add(command, parameter.Name, parameter.Value);
        await command.ExecuteNonQueryAsync(token);
    }

    private static async Task WriteAuditAsync(
        DbConnection connection,
        DbTransaction transaction,
        Guid actorUserId,
        Guid quoteId,
        string action,
        QuoteDetails? before,
        QuoteDetails after,
        CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            INSERT INTO audit_log (actor_user_id, entity_type, entity_id, action, diff)
            VALUES (@actor, 'quote', @quote_id, @action, CAST(@diff AS jsonb))
            """;
        Add(command, "actor", actorUserId);
        Add(command, "quote_id", quoteId);
        Add(command, "action", action);
        Add(command, "diff", JsonSerializer.Serialize(new
        {
            before = before is null ? null : AuditSnapshot(before),
            after = AuditSnapshot(after),
        }, JsonOptions));
        await command.ExecuteNonQueryAsync(token);
    }

    /// <summary>Оставляет в аудите шапку и цены, не копируя весь динамический JSON.</summary>
    private static object AuditSnapshot(QuoteDetails quote) => new
    {
        quote.QuoteKind,
        quote.Title,
        quote.ClientId,
        quote.ExecutorCompanyId,
        quote.ManagerUserId,
        quote.SalesHeadUserId,
        quote.SelectionMode,
        ProposalTypes = quote.ProposalTypes.Select(type => new
        {
            type.Id,
            type.Name,
            type.SelectedVariantId,
            Variants = type.Variants.Select(variant => new
            {
                variant.Id,
                variant.Name,
                variant.VatRate,
                Positions = variant.Categories.SelectMany(category => category.Sections)
                    .SelectMany(section => section.Positions)
                    .Select(position => new
                    {
                        position.Id,
                        position.CatalogItemId,
                        position.Quantity,
                        position.PurchasePrice,
                        position.BasePrice,
                        position.ManualPrice,
                        position.MarkupPercent,
                        position.DiscountPercent,
                        position.LineTotal,
                        position.ExcludeFromTotals,
                    }),
            }),
        }),
    };

    private static object Db(object? value) => value ?? DBNull.Value;

    private static string? TrimToNull(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    private static void Add(DbCommand command, string name, object value)
    {
        var parameter = command.CreateParameter();
        parameter.ParameterName = name;
        parameter.Value = value;
        command.Parameters.Add(parameter);
    }

    private static DateTimeOffset ReadTimestamp(DbDataReader reader, int ordinal) =>
        new(reader.GetFieldValue<DateTime>(ordinal));

    /// <summary>Собирает нормализованное дерево из отдельных таблиц без SELECT *.</summary>
    private static async Task<QuoteDetails?> ReadQuoteAsync(
        DbConnection connection,
        DbTransaction? transaction,
        Guid boardId,
        Guid cardId,
        CancellationToken token)
    {
        QuoteHeader? header;
        await using (var command = connection.CreateCommand())
        {
            command.Transaction = transaction;
            command.CommandText = """
                SELECT id, workflow_id, card_id, quote_kind, title, client_id,
                       executor_company_id, manager_user_id, sales_head_user_id,
                       selection_mode, additional_information, created_at, updated_at
                FROM quotes
                WHERE workflow_id = @workflow_id AND card_id = @card_id AND deleted_at IS NULL
                """;
            Add(command, "workflow_id", boardId);
            Add(command, "card_id", cardId);
            await using var reader = await command.ExecuteReaderAsync(token);
            if (!await reader.ReadAsync(token)) return null;
            header = new QuoteHeader(
                reader.GetGuid(0), reader.GetGuid(1), reader.GetGuid(2), reader.GetString(3),
                reader.GetString(4), reader.GetGuid(5), reader.GetGuid(6),
                reader.IsDBNull(7) ? null : reader.GetGuid(7),
                reader.IsDBNull(8) ? null : reader.GetGuid(8), reader.GetString(9),
                reader.IsDBNull(10) ? null : reader.GetString(10),
                ReadTimestamp(reader, 11), ReadTimestamp(reader, 12));
        }

        var types = new List<MutableType>();
        var typesById = new Dictionary<Guid, MutableType>();
        await using (var command = connection.CreateCommand())
        {
            command.Transaction = transaction;
            command.CommandText = """
                SELECT proposal_type.id, proposal_type.name, proposal_type.sort_order,
                       selection.variant_id
                FROM quote_proposal_types AS proposal_type
                LEFT JOIN quote_proposal_type_selections AS selection
                       ON selection.proposal_type_id = proposal_type.id
                WHERE proposal_type.quote_id = @quote_id
                ORDER BY proposal_type.sort_order, proposal_type.id
                """;
            Add(command, "quote_id", header.Id);
            await using var reader = await command.ExecuteReaderAsync(token);
            while (await reader.ReadAsync(token))
            {
                var item = new MutableType(
                    reader.GetGuid(0), reader.GetString(1), reader.GetInt32(2),
                    reader.IsDBNull(3) ? null : reader.GetGuid(3));
                types.Add(item);
                typesById[item.Id] = item;
            }
        }

        var variantsById = new Dictionary<Guid, MutableVariant>();
        await using (var command = connection.CreateCommand())
        {
            command.Transaction = transaction;
            command.CommandText = """
                SELECT variant.id, variant.proposal_type_id, variant.name, variant.subtitle,
                       variant.vat_rate, variant.sort_order
                FROM quote_variants AS variant
                JOIN quote_proposal_types AS proposal_type ON proposal_type.id = variant.proposal_type_id
                WHERE proposal_type.quote_id = @quote_id
                ORDER BY proposal_type.sort_order, variant.sort_order, variant.id
                """;
            Add(command, "quote_id", header.Id);
            await using var reader = await command.ExecuteReaderAsync(token);
            while (await reader.ReadAsync(token))
            {
                var item = new MutableVariant(
                    reader.GetGuid(0), reader.GetString(2),
                    reader.IsDBNull(3) ? null : reader.GetString(3),
                    reader.IsDBNull(4) ? null : reader.GetDecimal(4), reader.GetInt32(5));
                typesById[reader.GetGuid(1)].Variants.Add(item);
                variantsById[item.Id] = item;
            }
        }

        var categoriesById = new Dictionary<Guid, MutableCategory>();
        await using (var command = connection.CreateCommand())
        {
            command.Transaction = transaction;
            command.CommandText = """
                SELECT category.id, category.variant_id, category.catalog_category_id,
                       category.name_snapshot, category.sort_order
                FROM quote_variant_categories AS category
                JOIN quote_variants AS variant ON variant.id = category.variant_id
                JOIN quote_proposal_types AS proposal_type ON proposal_type.id = variant.proposal_type_id
                WHERE proposal_type.quote_id = @quote_id
                ORDER BY proposal_type.sort_order, variant.sort_order, category.sort_order, category.id
                """;
            Add(command, "quote_id", header.Id);
            await using var reader = await command.ExecuteReaderAsync(token);
            while (await reader.ReadAsync(token))
            {
                var item = new MutableCategory(
                    reader.GetGuid(0), reader.IsDBNull(2) ? null : reader.GetGuid(2),
                    reader.GetString(3), reader.GetInt32(4));
                variantsById[reader.GetGuid(1)].Categories.Add(item);
                categoriesById[item.Id] = item;
            }
        }

        var sectionsById = new Dictionary<Guid, MutableSection>();
        await using (var command = connection.CreateCommand())
        {
            command.Transaction = transaction;
            command.CommandText = """
                SELECT section.id, section.variant_category_id, section.catalog_section_id,
                       section.name_snapshot, section.markup_percent,
                       section.discount_percent, section.sort_order
                FROM quote_variant_sections AS section
                JOIN quote_variant_categories AS category ON category.id = section.variant_category_id
                JOIN quote_variants AS variant ON variant.id = category.variant_id
                JOIN quote_proposal_types AS proposal_type ON proposal_type.id = variant.proposal_type_id
                WHERE proposal_type.quote_id = @quote_id
                ORDER BY proposal_type.sort_order, variant.sort_order, category.sort_order,
                         section.sort_order, section.id
                """;
            Add(command, "quote_id", header.Id);
            await using var reader = await command.ExecuteReaderAsync(token);
            while (await reader.ReadAsync(token))
            {
                var item = new MutableSection(
                    reader.GetGuid(0), reader.IsDBNull(2) ? null : reader.GetGuid(2),
                    reader.GetString(3), reader.IsDBNull(4) ? null : reader.GetDecimal(4),
                    reader.IsDBNull(5) ? null : reader.GetDecimal(5), reader.GetInt32(6));
                categoriesById[reader.GetGuid(1)].Sections.Add(item);
                sectionsById[item.Id] = item;
            }
        }

        await using (var command = connection.CreateCommand())
        {
            command.Transaction = transaction;
            command.CommandText = """
                SELECT position.id, position.variant_section_id, position.catalog_item_id,
                       position.name_snapshot, position.marking_snapshot, position.unit_snapshot,
                       position.quantity, position.purchase_price, position.base_price,
                       position.manual_price, position.markup_percent, position.discount_percent,
                       position.line_total, position.exclude_from_totals, position.values::text,
                       position.sort_order
                FROM quote_positions AS position
                JOIN quote_variant_sections AS section ON section.id = position.variant_section_id
                JOIN quote_variant_categories AS category ON category.id = section.variant_category_id
                JOIN quote_variants AS variant ON variant.id = category.variant_id
                JOIN quote_proposal_types AS proposal_type ON proposal_type.id = variant.proposal_type_id
                WHERE proposal_type.quote_id = @quote_id
                ORDER BY proposal_type.sort_order, variant.sort_order, category.sort_order,
                         section.sort_order, position.sort_order, position.id
                """;
            Add(command, "quote_id", header.Id);
            await using var reader = await command.ExecuteReaderAsync(token);
            while (await reader.ReadAsync(token))
            {
                var values = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(
                    reader.GetString(14), JsonOptions) ?? new Dictionary<string, JsonElement>();
                sectionsById[reader.GetGuid(1)].Positions.Add(new QuotePositionDetails(
                    reader.GetGuid(0), reader.IsDBNull(2) ? null : reader.GetGuid(2),
                    reader.GetString(3), reader.GetString(4), reader.GetString(5),
                    reader.GetDecimal(6), reader.IsDBNull(7) ? null : reader.GetDecimal(7),
                    reader.GetDecimal(8), reader.IsDBNull(9) ? null : reader.GetDecimal(9),
                    reader.IsDBNull(10) ? null : reader.GetDecimal(10),
                    reader.IsDBNull(11) ? null : reader.GetDecimal(11), reader.GetDecimal(12),
                    reader.GetBoolean(13), values, reader.GetInt32(15)));
            }
        }

        return new QuoteDetails(
            header.Id, header.WorkflowId, header.CardId, header.QuoteKind, header.Title,
            header.ClientId, header.ExecutorCompanyId, header.ManagerUserId,
            header.SalesHeadUserId, header.SelectionMode, header.AdditionalInformation,
            types.Select(type => type.ToDetails()).ToArray(), header.CreatedAt, header.UpdatedAt);
    }

    private sealed record QuoteHeader(
        Guid Id, Guid WorkflowId, Guid CardId, string QuoteKind, string Title,
        Guid ClientId, Guid ExecutorCompanyId, Guid? ManagerUserId, Guid? SalesHeadUserId,
        string SelectionMode, string? AdditionalInformation,
        DateTimeOffset CreatedAt, DateTimeOffset UpdatedAt);

    private sealed class MutableType(Guid id, string name, int sortOrder, Guid? selectedVariantId)
    {
        public Guid Id { get; } = id;
        public List<MutableVariant> Variants { get; } = [];
        public QuoteProposalTypeDetails ToDetails() =>
            new(Id, name, sortOrder, selectedVariantId, Variants.Select(item => item.ToDetails()).ToArray());
    }

    private sealed class MutableVariant(Guid id, string name, string? subtitle, decimal? vatRate, int sortOrder)
    {
        public Guid Id { get; } = id;
        public List<MutableCategory> Categories { get; } = [];
        public QuoteVariantDetails ToDetails() =>
            new(Id, name, subtitle, vatRate, sortOrder, Categories.Select(item => item.ToDetails()).ToArray());
    }

    private sealed class MutableCategory(Guid id, Guid? catalogCategoryId, string name, int sortOrder)
    {
        public Guid Id { get; } = id;
        public List<MutableSection> Sections { get; } = [];
        public QuoteCategoryDetails ToDetails() =>
            new(Id, catalogCategoryId, name, sortOrder, Sections.Select(item => item.ToDetails()).ToArray());
    }

    private sealed class MutableSection(
        Guid id, Guid? catalogSectionId, string name,
        decimal? markupPercent, decimal? discountPercent, int sortOrder)
    {
        public Guid Id { get; } = id;
        public List<QuotePositionDetails> Positions { get; } = [];
        public QuoteSectionDetails ToDetails() =>
            new(Id, catalogSectionId, name, markupPercent, discountPercent, sortOrder, Positions);
    }
}
