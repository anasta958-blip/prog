using System.Data.Common;
using System.Text.Json;
using SkladKomforta.Application.Abstractions.Persistence;
using SkladKomforta.Application.Abstractions.Tenancy;
using SkladKomforta.Application.Identity;
using SkladKomforta.Application.Kanban;
using SkladKomforta.Application.Quotes;

namespace SkladKomforta.Infrastructure.Kanban;

/// <summary>
/// Читает настройки канбанов и управляет универсальными карточками внутри
/// текущей tenant-схемы. Специальные данные КП, ПКП и комплектаций этому
/// сервису не принадлежат.
/// </summary>
internal sealed class PostgresKanbanService(
    IDatabaseConnectionFactory connectionFactory,
    ITenantContext tenantContext,
    IEnumerable<IKanbanColumnEntryHandler> columnEntryHandlers) : IKanbanService
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    /// <summary>Роли пользователя в текущей организации через запятую.</summary>
    private static string RoleOf(string userColumn) => $"""
        (SELECT string_agg(role.name, ', ' ORDER BY role.name)
           FROM public.organization_members AS member
           JOIN member_roles AS member_role ON member_role.membership_id = member.id
           JOIN roles AS role ON role.id = member_role.role_id
          WHERE member.user_id = {userColumn})
        """;

    /// <summary>Общий набор колонок карточки для <see cref="ReadCard"/>.</summary>
    private static readonly string CardColumns = $"""
        card.id, card.card_number, card.workflow_id, card.column_id,
        card.category_id, card.section_id, card.title, card.values::text,
        card.created_by, creator.display_name, card.created_at,
        card.updated_by, updater.display_name, card.updated_at, card.is_archived,
        card.moved_by, mover.display_name, card.moved_at,
        {RoleOf("card.created_by")}, {RoleOf("card.updated_by")}, {RoleOf("card.moved_by")}
        """;

    private const string CardJoins = """
        LEFT JOIN public.users AS creator ON creator.id = card.created_by
        LEFT JOIN public.users AS updater ON updater.id = card.updated_by
        LEFT JOIN public.users AS mover ON mover.id = card.moved_by
        """;

    public async Task<IReadOnlyList<KanbanBoardSummary>> GetBoardsAsync(
        CancellationToken cancellationToken)
    {
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT workflow.id, workflow.code, workflow.name, workflow.sort_order,
                   count(workflow_column.id)::integer, workflow.specialization
            FROM workflows AS workflow
            LEFT JOIN workflow_columns AS workflow_column
                   ON workflow_column.workflow_id = workflow.id
            GROUP BY workflow.id, workflow.code, workflow.name, workflow.sort_order,
                     workflow.specialization
            ORDER BY workflow.sort_order, workflow.name, workflow.id
            """;

        var result = new List<KanbanBoardSummary>();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            result.Add(new KanbanBoardSummary(
                reader.GetGuid(0), reader.GetString(1), reader.GetString(2),
                reader.GetInt32(3), reader.GetInt32(4),
                reader.IsDBNull(5) ? null : reader.GetString(5)));
        }
        return result;
    }

    public async Task<IReadOnlyList<KanbanCardAuthorSummary>> GetCardAuthorsAsync(
        Guid actorUserId,
        CancellationToken cancellationToken)
    {
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        var visibleUserIds = await ReadVisibleUserIdsAsync(
            connection, null, actorUserId, cancellationToken);
        await using var command = connection.CreateCommand();
        var visibilityFilter = visibleUserIds is null
            ? string.Empty
            : "AND member.user_id = ANY(@visible_user_ids)";
        command.CommandText = $"""
            SELECT users.id, users.display_name
            FROM public.organization_members AS member
            JOIN public.users AS users ON users.id = member.user_id
            JOIN member_roles AS member_role ON member_role.membership_id = member.id
            JOIN roles AS role ON role.id = member_role.role_id AND role.deleted_at IS NULL
            WHERE member.is_active AND member.deleted_at IS NULL
              AND users.is_active AND users.deleted_at IS NULL
              {visibilityFilter}
            ORDER BY CASE WHEN users.id = @actor THEN 0 ELSE 1 END,
                     users.display_name, users.id
            """;
        AddParameter(command, "actor", actorUserId);
        if (visibleUserIds is not null)
            AddParameter(command, "visible_user_ids", visibleUserIds);
        var result = new List<KanbanCardAuthorSummary>();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            var userId = reader.GetGuid(0);
            result.Add(new KanbanCardAuthorSummary(
                userId, reader.GetString(1), userId == actorUserId));
        }
        return result;
    }

    public async Task<KanbanBoard> GetBoardAsync(
        Guid boardId,
        CancellationToken cancellationToken)
    {
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        var header = await ReadHeaderAsync(connection, boardId, cancellationToken);
        var categories = await ReadCategoriesAsync(connection, boardId, cancellationToken);
        var layouts = await Company.PostgresDocumentLayoutService.ReadFieldsAsync(connection, boardId, cancellationToken, categories);
        return new KanbanBoard(
            header.Id,
            header.Code,
            header.Name,
            await ReadColumnsAsync(connection, boardId, cancellationToken),
            await ReadTransitionsAsync(connection, boardId, cancellationToken),
            categories.Select(category => layouts.TryGetValue(category.CategoryId, out var fields)
                ? category with { DocumentFields = fields } : category).ToArray(),
            header.Specialization,
            await ReadOrderOptionsAsync(connection, boardId, "object_type", cancellationToken),
            await Company.PostgresDocumentLayoutService.ReadTemplateAsync(connection, boardId, cancellationToken));
    }

    /// <summary>Значения справочника канбана комплектации в заданном порядке.</summary>
    private static async Task<IReadOnlyList<string>> ReadOrderOptionsAsync(
        DbConnection connection,
        Guid boardId,
        string kind,
        CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT value FROM workflow_order_options
             WHERE workflow_id = @workflow_id AND option_kind = @kind
             ORDER BY sort_order, value
            """;
        AddParameter(command, "workflow_id", boardId);
        AddParameter(command, "kind", kind);
        var result = new List<string>();
        await using var reader = await command.ExecuteReaderAsync(token);
        while (await reader.ReadAsync(token)) result.Add(reader.GetString(0));
        return result;
    }

    public async Task<KanbanCardPage> GetCardsAsync(
        Guid actorUserId,
        Guid boardId,
        KanbanCardQuery query,
        CancellationToken cancellationToken)
    {
        var page = Math.Max(1, query.Page);
        var pageSize = Math.Clamp(query.PageSize, 1, 100);
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        var visibleUserIds = await ReadVisibleUserIdsAsync(
            connection, null, actorUserId, cancellationToken);
        if (query.AuthorUserId.HasValue &&
            visibleUserIds is null &&
            !await IsActiveTenantMemberAsync(
                connection, query.AuthorUserId.Value, cancellationToken))
        {
            throw new IdentityException(
                403,
                "kanban_card_author_forbidden",
                "Карточки выбранного пользователя недоступны.");
        }
        var selectedUserIds = ResolveCardAuthorFilter(
            actorUserId, visibleUserIds, query.AuthorUserId, query.IncludeOwn);
        await EnsureColumnAsync(connection, null, boardId, query.ColumnId, cancellationToken);
        // Один фильтр для страницы и для итога столбца. Поиск — подстрока
        // названия (без учёта регистра) или номер карточки («72», «#72», «№72»).
        var search = query.Search?.Trim() ?? string.Empty;
        var searchNumber = long.TryParse(search.TrimStart('#', '№').Trim(), out var number) ? number : -1;
        const string filter = """
            card.workflow_id = @workflow_id
              AND card.column_id = @column_id
              AND card.is_archived = @archived
              AND card.deleted_at IS NULL
              AND card.created_by = ANY(@visible_user_ids)
              AND (@search = ''
                   OR strpos(lower(card.title), lower(@search)) > 0
                   OR card.card_number = @search_number)
            """;
        void AddFilterParameters(DbCommand target)
        {
            AddParameter(target, "workflow_id", boardId);
            AddParameter(target, "column_id", query.ColumnId);
            AddParameter(target, "archived", query.Archived);
            AddParameter(target, "visible_user_ids", selectedUserIds);
            AddParameter(target, "search", search);
            AddParameter(target, "search_number", searchNumber);
        }

        await using var command = connection.CreateCommand();
        command.CommandText = $"""
            SELECT {CardColumns}, count(*) OVER()
            FROM kanban_cards AS card
            {CardJoins}
            WHERE {filter}
            ORDER BY card.sort_order, card.id
            LIMIT @limit OFFSET @offset
            """;
        AddFilterParameters(command);
        AddParameter(command, "limit", pageSize);
        AddParameter(command, "offset", (page - 1) * pageSize);

        var items = new List<KanbanCardSummary>();
        var total = 0;
        await using (var reader = await command.ExecuteReaderAsync(cancellationToken))
        {
            while (await reader.ReadAsync(cancellationToken))
            {
                items.Add(ReadCard(reader));
                total = checked((int)reader.GetInt64(21));
            }
        }

        // Итог столбца считается по всем подходящим карточкам, а не по странице.
        var columnQuoteIds = new List<Guid>();
        await using (var quotes = connection.CreateCommand())
        {
            quotes.CommandText = $"""
                SELECT quote.id
                  FROM kanban_cards AS card
                  JOIN quotes AS quote ON quote.card_id = card.id AND quote.deleted_at IS NULL
                 WHERE {filter}
                """;
            AddFilterParameters(quotes);
            await using var reader = await quotes.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken)) columnQuoteIds.Add(reader.GetGuid(0));
        }
        decimal? selectedTotal = null;
        if (columnQuoteIds.Count > 0)
        {
            var chosen = await ReadSelectionsAsync(connection, [.. columnQuoteIds], cancellationToken);
            selectedTotal = chosen.Values.SelectMany(list => list).Sum(item => item.Total);
        }

        return new KanbanCardPage(
            await WithQuoteSummariesAsync(connection, items, cancellationToken),
            page,
            pageSize,
            total,
            selectedTotal);
    }

    public async Task<KanbanCardSummary> GetCardAsync(
        Guid actorUserId,
        Guid boardId,
        Guid cardId,
        CancellationToken cancellationToken)
    {
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        var card = await ReadVisibleCardAsync(
            connection, null, actorUserId, boardId, cardId, cancellationToken);
        return (await WithQuoteSummariesAsync(connection, [card], cancellationToken))[0];
    }

    public async Task<KanbanCardSummary> CreateCardAsync(
        Guid actorUserId,
        Guid boardId,
        SaveKanbanCardRequest request,
        CancellationToken cancellationToken)
    {
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        await LockBoardMoveAsync(connection, transaction, boardId, cancellationToken);
        await EnsureStandardWorkflowAsync(connection, transaction, boardId, cancellationToken);
        var normalized = await ValidateCardAsync(connection, transaction, boardId, request, cancellationToken);
        var cardId = Guid.NewGuid();
        await using (var workItem = connection.CreateCommand())
        {
            workItem.Transaction = transaction;
            workItem.CommandText = "INSERT INTO work_items (id, created_by) VALUES (@id, @actor)";
            AddParameter(workItem, "id", cardId);
            AddParameter(workItem, "actor", actorUserId);
            await workItem.ExecuteNonQueryAsync(cancellationToken);
        }
        await using (var command = connection.CreateCommand())
        {
            command.Transaction = transaction;
            command.CommandText = """
                INSERT INTO kanban_cards
                    (id, work_item_id, workflow_id, column_id, category_id, section_id, title, values,
                     sort_order, created_by, updated_by)
                VALUES
                    (@id, @id, @workflow_id, @column_id, @category_id, @section_id, @title,
                     CAST(@values AS jsonb) - 'supplier',
                     COALESCE((SELECT max(sort_order) + 1 FROM kanban_cards
                               WHERE workflow_id = @workflow_id
                                 AND column_id = @column_id
                                 AND deleted_at IS NULL), 0),
                     @actor, @actor)
                """;
            AddCardParameters(command, cardId, actorUserId, boardId, normalized);
            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        var created = await ReadCardAsync(connection, transaction, boardId, cardId, cancellationToken);
        await WriteAuditAsync(connection, transaction, actorUserId, cardId, "created", null, created, cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return created;
    }

    public async Task<KanbanCardSummary> UpdateCardAsync(
        Guid actorUserId,
        Guid boardId,
        Guid cardId,
        SaveKanbanCardRequest request,
        CancellationToken cancellationToken)
    {
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        await LockBoardMoveAsync(connection, transaction, boardId, cancellationToken);
        var before = await ReadVisibleCardAsync(connection, transaction, actorUserId, boardId, cardId, cancellationToken);
        if (request.ColumnId != before.ColumnId)
            throw Invalid(
                "kanban_card_move_required",
                "Для смены столбца используйте операцию перемещения карточки.");
        var normalized = await ValidateCardAsync(connection, transaction, boardId, request, cancellationToken);
        await using (var command = connection.CreateCommand())
        {
            command.Transaction = transaction;
            command.CommandText = """
                UPDATE kanban_cards
                SET category_id = @category_id,
                    section_id = @section_id,
                    title = @title,
                    values = CAST(@values AS jsonb) - 'supplier',
                    updated_by = @actor,
                    updated_at = now()
                WHERE id = @id AND workflow_id = @workflow_id AND deleted_at IS NULL
                """;
            AddCardParameters(command, cardId, actorUserId, boardId, normalized);
            if (await command.ExecuteNonQueryAsync(cancellationToken) != 1) throw CardNotFound();
        }

        var updated = await ReadCardAsync(connection, transaction, boardId, cardId, cancellationToken);
        await WriteAuditAsync(connection, transaction, actorUserId, cardId, "updated", before, updated, cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return updated;
    }

    public async Task<KanbanCardSummary> MoveCardAsync(
        Guid actorUserId,
        Guid boardId,
        Guid cardId,
        MoveKanbanCardRequest request,
        CancellationToken cancellationToken)
    {
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        await LockBoardMoveAsync(connection, transaction, boardId, cancellationToken);
        var before = await ReadVisibleCardAsync(connection, transaction, actorUserId, boardId, cardId, cancellationToken);
        await EnsureColumnAsync(connection, transaction, boardId, request.TargetColumnId, cancellationToken);
        if (before.IsArchived)
            throw new IdentityException(409, "kanban_card_archived", "Сначала верните карточку из архива.");
        if (before.ColumnId != request.TargetColumnId)
            await EnsureTransitionAsync(
                connection,
                transaction,
                boardId,
                before.ColumnId,
                request.TargetColumnId,
                cancellationToken);

        // Блокируем обе последовательности в стабильном порядке. Параллельные
        // переносы не смогут получить одинаковые sort_order или потерять карточку.
        await LockColumnsAsync(
            connection,
            transaction,
            boardId,
            before.ColumnId,
            request.TargetColumnId,
            cancellationToken);
        var sourceIds = await ReadOrderedCardIdsAsync(
            connection, transaction, boardId, before.ColumnId, cancellationToken);
        sourceIds.Remove(cardId);
        var targetIds = before.ColumnId == request.TargetColumnId
            ? sourceIds
            : await ReadOrderedCardIdsAsync(
                connection, transaction, boardId, request.TargetColumnId, cancellationToken);
        targetIds.Remove(cardId);
        targetIds.Insert(Math.Clamp(request.TargetIndex, 0, targetIds.Count), cardId);

        if (before.ColumnId != request.TargetColumnId)
            await RewriteSortOrderAsync(connection, transaction, sourceIds, cancellationToken);
        await RewriteSortOrderAsync(connection, transaction, targetIds, cancellationToken);

        await using (var command = connection.CreateCommand())
        {
            command.Transaction = transaction;
            // Перенос между колонками — «Статус изменил»; порядок внутри колонки
            // и правки содержимого его не затрагивают. updated_* остаётся за
            // последним изменением содержимого.
            command.CommandText = """
                UPDATE kanban_cards
                SET column_id = @column_id,
                    moved_by = CASE WHEN column_id <> @column_id THEN @actor ELSE moved_by END,
                    moved_at = CASE WHEN column_id <> @column_id THEN now() ELSE moved_at END
                WHERE id = @id AND workflow_id = @workflow_id AND deleted_at IS NULL
                """;
            AddParameter(command, "column_id", request.TargetColumnId);
            AddParameter(command, "actor", actorUserId);
            AddParameter(command, "id", cardId);
            AddParameter(command, "workflow_id", boardId);
            if (await command.ExecuteNonQueryAsync(cancellationToken) != 1) throw CardNotFound();
        }

        // Столбец-триггер переносит карточку в другой канбан в этой же транзакции:
        // если перенос невозможен, отменяется и перемещение.
        if (before.ColumnId != request.TargetColumnId)
            foreach (var handler in columnEntryHandlers)
                await handler.OnCardEnteredColumnAsync(
                    connection, transaction, actorUserId, boardId, cardId,
                    request.TargetColumnId, cancellationToken);

        var moved = await ReadCardAsync(connection, transaction, boardId, cardId, cancellationToken);
        await WriteAuditAsync(connection, transaction, actorUserId, cardId, "moved", before, moved, cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return moved;
    }

    public async Task<KanbanCardSummary> SetArchivedAsync(
        Guid actorUserId, Guid boardId, Guid cardId, bool archived, CancellationToken cancellationToken)
    {
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        await LockBoardMoveAsync(connection, transaction, boardId, cancellationToken);
        var before = await ReadVisibleCardAsync(connection, transaction, actorUserId, boardId, cardId, cancellationToken);
        if (before.IsArchived == archived)
        {
            await transaction.CommitAsync(cancellationToken);
            return before;
        }
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            UPDATE kanban_cards SET is_archived = @archived,
                updated_by = @actor, updated_at = now(),
                sort_order = CASE WHEN @archived THEN sort_order ELSE
                    COALESCE((SELECT max(other.sort_order) + 1 FROM kanban_cards other
                        WHERE other.workflow_id = @workflow_id AND other.column_id = @column_id
                          AND other.deleted_at IS NULL AND NOT other.is_archived), 0) END
            WHERE id = @id AND workflow_id = @workflow_id AND deleted_at IS NULL
            """;
        AddParameter(command, "archived", archived);
        AddParameter(command, "actor", actorUserId);
        AddParameter(command, "id", cardId);
        AddParameter(command, "workflow_id", boardId);
        AddParameter(command, "column_id", before.ColumnId);
        if (await command.ExecuteNonQueryAsync(cancellationToken) != 1) throw CardNotFound();
        var after = await ReadCardAsync(connection, transaction, boardId, cardId, cancellationToken);
        await WriteAuditAsync(connection, transaction, actorUserId, cardId,
            archived ? "archived" : "restored", before, after, cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return after;
    }

    public async Task DeleteCardAsync(
        Guid actorUserId,
        Guid boardId,
        Guid cardId,
        CancellationToken cancellationToken)
    {
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        await LockBoardMoveAsync(connection, transaction, boardId, cancellationToken);
        var before = await ReadVisibleCardAsync(connection, transaction, actorUserId, boardId, cardId, cancellationToken);
        await using (var specializedDocument = connection.CreateCommand())
        {
            specializedDocument.Transaction = transaction;
            specializedDocument.CommandText = """
                UPDATE quotes
                SET deleted_by = @actor, deleted_at = now(),
                    updated_by = @actor, updated_at = now()
                WHERE card_id = @id
                  AND workflow_id = @workflow_id
                  AND deleted_at IS NULL
                """;
            AddParameter(specializedDocument, "actor", actorUserId);
            AddParameter(specializedDocument, "id", cardId);
            AddParameter(specializedDocument, "workflow_id", boardId);
            await specializedDocument.ExecuteNonQueryAsync(cancellationToken);
        }
        await using (var order = connection.CreateCommand())
        {
            order.Transaction = transaction;
            order.CommandText = """
                UPDATE orders
                SET deleted_by = @actor, deleted_at = now(),
                    updated_by = @actor, updated_at = now()
                WHERE card_id = @id
                  AND workflow_id = @workflow_id
                  AND deleted_at IS NULL
                """;
            AddParameter(order, "actor", actorUserId);
            AddParameter(order, "id", cardId);
            AddParameter(order, "workflow_id", boardId);
            await order.ExecuteNonQueryAsync(cancellationToken);
        }
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            UPDATE kanban_cards
            SET deleted_by = @actor, deleted_at = now(),
                updated_by = @actor, updated_at = now()
            WHERE id = @id AND workflow_id = @workflow_id AND deleted_at IS NULL
            """;
        AddParameter(command, "actor", actorUserId);
        AddParameter(command, "id", cardId);
        AddParameter(command, "workflow_id", boardId);
        if (await command.ExecuteNonQueryAsync(cancellationToken) != 1) throw CardNotFound();
        await WriteAuditAsync(connection, transaction, actorUserId, cardId, "deleted", before, null, cancellationToken);
        await transaction.CommitAsync(cancellationToken);
    }

    private static async Task<KanbanBoardSummary> ReadHeaderAsync(
        DbConnection connection,
        Guid boardId,
        CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.CommandText = "SELECT id, code, name, sort_order, specialization FROM workflows WHERE id = @id";
        AddParameter(command, "id", boardId);
        await using var reader = await command.ExecuteReaderAsync(token);
        if (!await reader.ReadAsync(token)) throw BoardNotFound();
        return new KanbanBoardSummary(
            reader.GetGuid(0), reader.GetString(1), reader.GetString(2), reader.GetInt32(3), 0,
            reader.IsDBNull(4) ? null : reader.GetString(4));
    }

    private static async Task<IReadOnlyList<KanbanColumnSummary>> ReadColumnsAsync(
        DbConnection connection,
        Guid boardId,
        CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT workflow_column.id, workflow_column.name, workflow_column.color,
                   workflow_column.sort_order,
                   COALESCE(
                       array_agg(action.action_kind ORDER BY action.action_kind)
                           FILTER (WHERE action.action_kind IS NOT NULL),
                       ARRAY[]::varchar[]),
                   transfer.target_workflow_id, target_workflow.name,
                   transfer.target_column_id, target_column.name,
                   workflow_column.reorder_from
            FROM workflow_columns AS workflow_column
            LEFT JOIN workflow_column_creation_actions AS action
                   ON action.column_id = workflow_column.id
                  AND action.workflow_id = workflow_column.workflow_id
            LEFT JOIN workflow_column_transfers AS transfer ON transfer.column_id = workflow_column.id
            LEFT JOIN workflows AS target_workflow ON target_workflow.id = transfer.target_workflow_id
            LEFT JOIN workflow_columns AS target_column ON target_column.id = transfer.target_column_id
            WHERE workflow_column.workflow_id = @workflow_id
            GROUP BY workflow_column.id, workflow_column.name, workflow_column.color,
                     workflow_column.sort_order, transfer.target_workflow_id, target_workflow.name,
                     transfer.target_column_id, target_column.name, workflow_column.reorder_from
            ORDER BY workflow_column.sort_order, workflow_column.id
            """;
        AddParameter(command, "workflow_id", boardId);
        var result = new List<KanbanColumnSummary>();
        await using var reader = await command.ExecuteReaderAsync(token);
        while (await reader.ReadAsync(token))
            result.Add(new KanbanColumnSummary(
                reader.GetGuid(0), reader.GetString(1), reader.GetString(2), reader.GetInt32(3),
                reader.GetFieldValue<string[]>(4),
                reader.IsDBNull(5)
                    ? null
                    : new KanbanColumnTransfer(reader.GetGuid(5), reader.GetString(6), reader.GetGuid(7), reader.GetString(8)),
                reader.GetBoolean(9)));
        return result;
    }

    /// <summary>Универсальный endpoint не создаёт пустые карточки специализированных модулей.</summary>
    private static async Task EnsureStandardWorkflowAsync(
        DbConnection connection,
        DbTransaction transaction,
        Guid boardId,
        CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = "SELECT specialization FROM workflows WHERE id = @id FOR UPDATE";
        AddParameter(command, "id", boardId);
        var specialization = await command.ExecuteScalarAsync(token);
        if (specialization is null)
            throw new IdentityException(404, "kanban_board_not_found", "Канбан не найден.");
        if (specialization is not DBNull)
            throw new IdentityException(
                409,
                "specialized_card_create_forbidden",
                "Карточка специализированного канбана создаётся только после сохранения документа.");
    }

    private static async Task<IReadOnlyList<KanbanTransitionSummary>> ReadTransitionsAsync(
        DbConnection connection,
        Guid boardId,
        CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT transition.from_column_id, transition.to_column_id
            FROM workflow_transitions AS transition
            JOIN workflow_columns AS source_column ON source_column.id = transition.from_column_id
            WHERE source_column.workflow_id = @workflow_id
            ORDER BY transition.from_column_id, transition.to_column_id
            """;
        AddParameter(command, "workflow_id", boardId);
        var result = new List<KanbanTransitionSummary>();
        await using var reader = await command.ExecuteReaderAsync(token);
        while (await reader.ReadAsync(token))
            result.Add(new KanbanTransitionSummary(reader.GetGuid(0), reader.GetGuid(1)));
        return result;
    }

    /// <summary>
    /// Возвращает только поля, которые одновременно существуют в категории
    /// каталога и явно выбраны для этого канбана. Так рабочая карточка не имеет
    /// второго независимого набора метаданных.
    /// </summary>
    internal static async Task<IReadOnlyList<KanbanCategorySummary>> ReadCategoriesAsync(
        DbConnection connection,
        Guid boardId,
        CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT category.id, category.name, workflow_category.sort_order,
                   COALESCE((
                     SELECT jsonb_agg(jsonb_build_object(
                         'id', section.id,
                         'name', section.name,
                         'sortOrder', section.sort_order)
                         ORDER BY section.sort_order, section.name)
                     FROM catalog_sections AS section
                     WHERE section.category_id = category.id
                   ), '[]'::jsonb)::text,
                   workflow_field.field_code,
                   COALESCE(category_field.label,
                            CASE workflow_field.field_code WHEN 'shipment_status' THEN 'Статус отгрузки' END,
                            workflow_field.field_code),
                   COALESCE(category_field.field_type,
                            CASE workflow_field.field_code WHEN 'shipment_status' THEN 'dictionary' END,
                            'text'),
                   COALESCE(category_field.is_required, false),
                   workflow_field.sort_order,
                   category_field.dictionary_code,
                   CASE
                     WHEN workflow_field.field_code = 'shipment_status' THEN COALESCE((
                       SELECT jsonb_agg(jsonb_build_object(
                           'id', order_option.id,
                           'value', order_option.value,
                           'sortOrder', order_option.sort_order)
                           ORDER BY order_option.sort_order, order_option.value)
                       FROM workflow_order_options AS order_option
                       WHERE order_option.workflow_id = workflow_category.workflow_id
                         AND order_option.option_kind = 'shipment_status'
                     ), '[]'::jsonb)
                     WHEN workflow_field.field_code = 'group' THEN COALESCE((
                       SELECT jsonb_agg(jsonb_build_object(
                           'id', catalog_group.id,
                           'value', catalog_group.name,
                           'sortOrder', catalog_group.sort_order)
                           ORDER BY catalog_section.sort_order, catalog_group.sort_order, catalog_group.name)
                       FROM catalog_sections AS catalog_section
                       JOIN catalog_groups AS catalog_group ON catalog_group.section_id = catalog_section.id
                       WHERE catalog_section.category_id = category.id
                     ), '[]'::jsonb)
                     ELSE COALESCE((
                       SELECT jsonb_agg(jsonb_build_object(
                           'id', dictionary_item.id,
                           'value', dictionary_item.value,
                           'sortOrder', dictionary_item.sort_order)
                           ORDER BY dictionary_item.sort_order, dictionary_item.value)
                       FROM dictionary_types AS dictionary_type
                       JOIN dictionary_items AS dictionary_item
                         ON dictionary_item.dictionary_type_id = dictionary_type.id
                       WHERE dictionary_type.code = category_field.dictionary_code
                     ), '[]'::jsonb)
                   END::text, workflow_category.supplier_filter_field_code
            FROM workflow_categories AS workflow_category
            JOIN catalog_categories AS category ON category.id = workflow_category.category_id
            LEFT JOIN workflow_category_fields AS workflow_field
              ON workflow_field.workflow_id = workflow_category.workflow_id
             AND workflow_field.category_id = workflow_category.category_id
            LEFT JOIN catalog_category_fields AS category_field
              ON category_field.category_id = workflow_category.category_id
             AND category_field.field_code = workflow_field.field_code
            WHERE workflow_category.workflow_id = @workflow_id
              AND (category_field.field_code IS NOT NULL
                   OR workflow_field.field_code IS NULL
                   OR workflow_field.field_code = 'shipment_status')
            ORDER BY workflow_category.sort_order, category.name, category.id,
                     workflow_field.sort_order, workflow_field.field_code
            """;
        AddParameter(command, "workflow_id", boardId);
        var categories = new Dictionary<Guid, MutableCategory>();
        await using var reader = await command.ExecuteReaderAsync(token);
        while (await reader.ReadAsync(token))
        {
            var categoryId = reader.GetGuid(0);
            if (!categories.TryGetValue(categoryId, out var category))
            {
                category = new MutableCategory(
                    categoryId,
                    reader.GetString(1),
                    reader.GetInt32(2),
                    JsonSerializer.Deserialize<List<KanbanSectionSummary>>(reader.GetString(3), JsonOptions) ?? [],
                    reader.IsDBNull(11) ? null : reader.GetString(11));
                categories.Add(categoryId, category);
            }
            if (reader.IsDBNull(4)) continue;
            category.Fields.Add(new KanbanFieldSummary(
                reader.GetString(4),
                reader.GetString(5),
                reader.GetString(6),
                reader.GetBoolean(7),
                reader.GetInt32(8),
                reader.IsDBNull(9) ? null : reader.GetString(9),
                JsonSerializer.Deserialize<List<KanbanDictionaryOption>>(reader.GetString(10), JsonOptions) ?? []));
        }
        return categories.Values.Select(item => item.ToSummary()).ToArray();
    }

    private static async Task<NormalizedCard> ValidateCardAsync(
        DbConnection connection,
        DbTransaction transaction,
        Guid boardId,
        SaveKanbanCardRequest request,
        CancellationToken token)
    {
        var title = request.Title?.Trim() ?? string.Empty;
        if (title.Length is < 1 or > 200)
            throw Invalid("kanban_card_title_invalid", "Название карточки должно содержать от 1 до 200 символов.");
        await EnsureColumnAsync(connection, transaction, boardId, request.ColumnId, token);
        await EnsureCategoryAsync(connection, transaction, boardId, request.CategoryId, token);
        var sectionId = await ResolveSectionAsync(
            connection, transaction, request.CategoryId, request.SectionId, token);
        var fields = await ReadConfiguredFieldsAsync(connection, transaction, boardId, request.CategoryId, token);
        var source = request.Values ?? new Dictionary<string, JsonElement>();
        var normalized = new Dictionary<string, JsonElement>(StringComparer.Ordinal);
        foreach (var pair in source)
        {
            if (pair.Key == "name") continue;
            if (!fields.TryGetValue(pair.Key, out var field))
                throw Invalid("kanban_card_field_forbidden", $"Поле «{pair.Key}» не разрешено в этой категории канбана.");
            ValidateValue(field, pair.Value);
            if (!IsEmpty(pair.Value)) normalized[pair.Key] = pair.Value.Clone();
        }
        foreach (var field in fields.Values)
        {
            if (field.Code == "name" || !field.IsRequired) continue;
            if (!normalized.TryGetValue(field.Code, out var value) || IsEmpty(value))
                throw Invalid("kanban_card_required_field", $"Заполните поле «{field.Label}».");
        }
        return new NormalizedCard(request.ColumnId, request.CategoryId, sectionId, title, normalized);
    }

    /// <summary>
    /// Автоматически выбирает единственный раздел категории. Для нескольких
    /// разделов требует явный выбор и проверяет принадлежность категории.
    /// </summary>
    private static async Task<Guid?> ResolveSectionAsync(
        DbConnection connection,
        DbTransaction transaction,
        Guid categoryId,
        Guid? requestedSectionId,
        CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            SELECT id
            FROM catalog_sections
            WHERE category_id = @category_id
            ORDER BY sort_order, name, id
            """;
        AddParameter(command, "category_id", categoryId);
        var sectionIds = new List<Guid>();
        await using var reader = await command.ExecuteReaderAsync(token);
        while (await reader.ReadAsync(token)) sectionIds.Add(reader.GetGuid(0));

        if (sectionIds.Count == 0)
        {
            if (requestedSectionId is not null)
                throw Invalid("kanban_section_invalid", "У выбранной категории нет разделов.");
            return null;
        }
        if (requestedSectionId is null)
        {
            if (sectionIds.Count == 1) return sectionIds[0];
            throw Invalid("kanban_section_required", "Выберите раздел карточки.");
        }
        if (!sectionIds.Contains(requestedSectionId.Value))
            throw Invalid("kanban_section_invalid", "Выбранный раздел не принадлежит категории карточки.");
        return requestedSectionId;
    }

    private static async Task<Dictionary<string, ConfiguredField>> ReadConfiguredFieldsAsync(
        DbConnection connection,
        DbTransaction transaction,
        Guid boardId,
        Guid categoryId,
        CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            SELECT workflow_field.field_code,
                   COALESCE(category_field.label, workflow_field.field_code),
                   COALESCE(category_field.field_type, 'text'),
                   COALESCE(category_field.is_required, false)
            FROM workflow_category_fields AS workflow_field
            JOIN catalog_category_fields AS category_field
              ON category_field.category_id = workflow_field.category_id
             AND category_field.field_code = workflow_field.field_code
            WHERE workflow_field.workflow_id = @workflow_id
              AND workflow_field.category_id = @category_id
            """;
        AddParameter(command, "workflow_id", boardId);
        AddParameter(command, "category_id", categoryId);
        var result = new Dictionary<string, ConfiguredField>(StringComparer.Ordinal);
        await using var reader = await command.ExecuteReaderAsync(token);
        while (await reader.ReadAsync(token))
        {
            var field = new ConfiguredField(reader.GetString(0), reader.GetString(1), reader.GetString(2), reader.GetBoolean(3));
            result.Add(field.Code, field);
        }
        return result;
    }

    private static void ValidateValue(ConfiguredField field, JsonElement value)
    {
        if (IsEmpty(value)) return;
        var valid = field.FieldType switch
        {
            "text" or "dictionary" => value.ValueKind == JsonValueKind.String,
            "number" or "money" or "percent" or "calculated_money" => value.ValueKind == JsonValueKind.Number,
            "boolean" => value.ValueKind is JsonValueKind.True or JsonValueKind.False,
            "relation" => value.ValueKind == JsonValueKind.Array,
            _ => false,
        };
        if (!valid)
            throw Invalid("kanban_card_field_type_invalid", $"Поле «{field.Label}» имеет неверный тип значения.");
        if (field.FieldType is "money" or "calculated_money" && value.TryGetDecimal(out var amount) && amount < 0)
            throw Invalid("kanban_card_money_negative", $"Поле «{field.Label}» не может быть отрицательным.");
        if (value.ValueKind == JsonValueKind.String && (value.GetString()?.Length ?? 0) > 4000)
            throw Invalid("kanban_card_field_too_long", $"Поле «{field.Label}» не должно превышать 4000 символов.");
    }

    private static async Task EnsureColumnAsync(
        DbConnection connection,
        DbTransaction? transaction,
        Guid boardId,
        Guid columnId,
        CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = "SELECT EXISTS(SELECT 1 FROM workflow_columns WHERE id = @id AND workflow_id = @workflow_id)";
        AddParameter(command, "id", columnId);
        AddParameter(command, "workflow_id", boardId);
        if (await command.ExecuteScalarAsync(token) is not true)
            throw Invalid("kanban_column_invalid", "Выбранный столбец не принадлежит канбану.");
    }

    private static async Task EnsureCategoryAsync(
        DbConnection connection,
        DbTransaction transaction,
        Guid boardId,
        Guid categoryId,
        CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = "SELECT EXISTS(SELECT 1 FROM workflow_categories WHERE workflow_id = @workflow_id AND category_id = @category_id)";
        AddParameter(command, "workflow_id", boardId);
        AddParameter(command, "category_id", categoryId);
        if (await command.ExecuteScalarAsync(token) is not true)
            throw Invalid("kanban_category_invalid", "Выбранная категория не разрешена в этом канбане.");
    }

    private static async Task EnsureTransitionAsync(
        DbConnection connection,
        DbTransaction transaction,
        Guid boardId,
        Guid sourceColumnId,
        Guid targetColumnId,
        CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            SELECT EXISTS(
                SELECT 1
                FROM workflow_transitions AS transition
                JOIN workflow_columns AS source_column
                  ON source_column.id = transition.from_column_id
                JOIN workflow_columns AS target_column
                  ON target_column.id = transition.to_column_id
                WHERE transition.from_column_id = @source_column_id
                  AND transition.to_column_id = @target_column_id
                  AND source_column.workflow_id = @workflow_id
                  AND target_column.workflow_id = @workflow_id)
            """;
        AddParameter(command, "source_column_id", sourceColumnId);
        AddParameter(command, "target_column_id", targetColumnId);
        AddParameter(command, "workflow_id", boardId);
        if (await command.ExecuteScalarAsync(token) is not true)
            throw Invalid(
                "kanban_transition_forbidden",
                "Переход карточки между выбранными столбцами не разрешён настройками канбана.");
    }

    private static async Task LockColumnsAsync(
        DbConnection connection,
        DbTransaction transaction,
        Guid boardId,
        Guid sourceColumnId,
        Guid targetColumnId,
        CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            SELECT id
            FROM kanban_cards
            WHERE workflow_id = @workflow_id
              AND column_id IN (@source_column_id, @target_column_id)
              AND deleted_at IS NULL
            ORDER BY column_id, id
            FOR UPDATE
            """;
        AddParameter(command, "workflow_id", boardId);
        AddParameter(command, "source_column_id", sourceColumnId);
        AddParameter(command, "target_column_id", targetColumnId);
        await using var reader = await command.ExecuteReaderAsync(token);
        while (await reader.ReadAsync(token)) { }
    }

    private static async Task LockBoardMoveAsync(
        DbConnection connection,
        DbTransaction transaction,
        Guid boardId,
        CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = "SELECT pg_advisory_xact_lock(hashtext(CAST(@workflow_id AS text)))";
        AddParameter(command, "workflow_id", boardId);
        await command.ExecuteNonQueryAsync(token);
    }

    private static async Task<List<Guid>> ReadOrderedCardIdsAsync(
        DbConnection connection,
        DbTransaction transaction,
        Guid boardId,
        Guid columnId,
        CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            SELECT id
            FROM kanban_cards
            WHERE workflow_id = @workflow_id
              AND column_id = @column_id
              AND deleted_at IS NULL
              AND NOT is_archived
            ORDER BY sort_order, id
            """;
        AddParameter(command, "workflow_id", boardId);
        AddParameter(command, "column_id", columnId);
        var result = new List<Guid>();
        await using var reader = await command.ExecuteReaderAsync(token);
        while (await reader.ReadAsync(token)) result.Add(reader.GetGuid(0));
        return result;
    }

    private static async Task RewriteSortOrderAsync(
        DbConnection connection,
        DbTransaction transaction,
        List<Guid> cardIds,
        CancellationToken token)
    {
        if (cardIds.Count == 0) return;
        var sortOrders = Enumerable.Range(0, cardIds.Count)
            .Select(index => (long)index)
            .ToArray();
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            WITH positions AS (
                SELECT id, sort_order
                FROM unnest(CAST(@card_ids AS uuid[]), CAST(@sort_orders AS bigint[]))
                     AS value(id, sort_order)
            )
            UPDATE kanban_cards AS card
            SET sort_order = positions.sort_order
            FROM positions
            WHERE card.id = positions.id
            """;
        AddParameter(command, "card_ids", cardIds.ToArray());
        AddParameter(command, "sort_orders", sortOrders);
        await command.ExecuteNonQueryAsync(token);
    }

    private static async Task<KanbanCardSummary> ReadCardAsync(
        DbConnection connection,
        DbTransaction? transaction,
        Guid boardId,
        Guid cardId,
        CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = $"""
            SELECT {CardColumns}
            FROM kanban_cards AS card
            {CardJoins}
            WHERE card.id = @id AND card.workflow_id = @workflow_id
              AND card.deleted_at IS NULL
            """;
        AddParameter(command, "id", cardId);
        AddParameter(command, "workflow_id", boardId);
        await using var reader = await command.ExecuteReaderAsync(token);
        if (!await reader.ReadAsync(token)) throw CardNotFound();
        return ReadCard(reader);
    }

    private static async Task<KanbanCardSummary> ReadVisibleCardAsync(
        DbConnection connection,
        DbTransaction? transaction,
        Guid actorUserId,
        Guid boardId,
        Guid cardId,
        CancellationToken token)
    {
        var visibleUserIds = await ReadVisibleUserIdsAsync(
            connection, transaction, actorUserId, token);
        var card = await ReadCardAsync(
            connection, transaction, boardId, cardId, token);
        if (visibleUserIds is not null &&
            (!card.CreatedBy.HasValue || !visibleUserIds.Contains(card.CreatedBy.Value)))
        {
            throw CardNotFound();
        }
        return card;
    }

    /// <summary>
    /// Возвращает null для неограниченного просмотра либо список авторов,
    /// карточки которых разрешены текущей ролью. Собственный user id всегда
    /// включается, поэтому пользователь не теряет доступ к созданным им данным.
    /// </summary>
    private static async Task<Guid[]?> ReadVisibleUserIdsAsync(
        DbConnection connection,
        DbTransaction? transaction,
        Guid actorUserId,
        CancellationToken token)
    {
        await using var roleCommand = connection.CreateCommand();
        roleCommand.Transaction = transaction;
        roleCommand.CommandText = """
            SELECT role.card_visibility_mode,
                   coalesce(bool_or(permission.code = 'system.full_access'), false)
            FROM public.organization_members AS member
            JOIN member_roles AS member_role ON member_role.membership_id = member.id
            JOIN roles AS role ON role.id = member_role.role_id AND role.deleted_at IS NULL
            LEFT JOIN role_permissions AS role_permission ON role_permission.role_id = role.id
            LEFT JOIN permissions AS permission ON permission.id = role_permission.permission_id
            WHERE member.user_id = @actor AND member.is_active AND member.deleted_at IS NULL
            GROUP BY role.card_visibility_mode
            """;
        AddParameter(roleCommand, "actor", actorUserId);
        await using var roleReader = await roleCommand.ExecuteReaderAsync(token);
        if (!await roleReader.ReadAsync(token)) return [actorUserId];
        var mode = roleReader.GetString(0);
        var hasFullAccess = roleReader.GetBoolean(1);
        await roleReader.DisposeAsync();
        if (hasFullAccess || mode == "all") return null;
        if (mode == "own") return [actorUserId];

        await using var membersCommand = connection.CreateCommand();
        membersCommand.Transaction = transaction;
        membersCommand.CommandText = mode == "subordinates"
            ? """
                WITH RECURSIVE visible_members(id) AS (
                    SELECT id
                    FROM public.organization_members
                    WHERE user_id = @actor AND is_active AND deleted_at IS NULL
                    UNION
                    SELECT reporting.membership_id
                    FROM member_reporting AS reporting
                    JOIN visible_members AS parent
                      ON reporting.supervisor_membership_id = parent.id
                    JOIN public.organization_members AS child
                      ON child.id = reporting.membership_id
                     AND child.is_active AND child.deleted_at IS NULL
                )
                SELECT DISTINCT member.user_id
                FROM visible_members
                JOIN public.organization_members AS member ON member.id = visible_members.id
                """
            : """
                SELECT DISTINCT member.user_id
                FROM public.organization_members AS actor
                JOIN member_roles AS actor_role ON actor_role.membership_id = actor.id
                JOIN role_card_visibility_members AS visibility
                  ON visibility.role_id = actor_role.role_id
                JOIN public.organization_members AS member
                  ON member.id = visibility.membership_id
                 AND member.organization_id = actor.organization_id
                 AND member.is_active AND member.deleted_at IS NULL
                WHERE actor.user_id = @actor
                UNION SELECT @actor
                """;
        AddParameter(membersCommand, "actor", actorUserId);
        var result = new List<Guid> { actorUserId };
        await using var reader = await membersCommand.ExecuteReaderAsync(token);
        while (await reader.ReadAsync(token))
        {
            var userId = reader.GetGuid(0);
            if (!result.Contains(userId)) result.Add(userId);
        }
        return result.ToArray();
    }

    private static async Task<bool> IsActiveTenantMemberAsync(
        DbConnection connection,
        Guid userId,
        CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT EXISTS (
                SELECT 1
                FROM public.organization_members AS member
                JOIN member_roles AS member_role ON member_role.membership_id = member.id
                JOIN roles AS role ON role.id = member_role.role_id AND role.deleted_at IS NULL
                JOIN public.users AS users ON users.id = member.user_id
                WHERE member.user_id = @user_id
                  AND member.is_active AND member.deleted_at IS NULL
                  AND users.is_active AND users.deleted_at IS NULL
            )
            """;
        AddParameter(command, "user_id", userId);
        return await command.ExecuteScalarAsync(token) is true;
    }

    private static Guid[] ResolveCardAuthorFilter(
        Guid actorUserId,
        Guid[]? roleVisibleUserIds,
        Guid? requestedUserId,
        bool includeOwn)
    {
        if (!requestedUserId.HasValue) return [actorUserId];
        if (roleVisibleUserIds is not null &&
            !roleVisibleUserIds.Contains(requestedUserId.Value))
        {
            throw new IdentityException(
                403,
                "kanban_card_author_forbidden",
                "Карточки выбранного пользователя недоступны.");
        }
        return includeOwn && requestedUserId.Value != actorUserId
            ? [actorUserId, requestedUserId.Value]
            : [requestedUserId.Value];
    }

    private static KanbanCardSummary ReadCard(DbDataReader reader) => new(
        reader.GetGuid(0),
        reader.GetInt64(1),
        reader.GetGuid(2),
        reader.GetGuid(3),
        reader.IsDBNull(4) ? null : reader.GetGuid(4),
        reader.IsDBNull(5) ? null : reader.GetGuid(5),
        reader.GetString(6),
        JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(reader.GetString(7), JsonOptions)
            ?? new Dictionary<string, JsonElement>(),
        reader.IsDBNull(8) ? null : reader.GetGuid(8),
        reader.IsDBNull(9) ? null : reader.GetString(9),
        new DateTimeOffset(reader.GetFieldValue<DateTime>(10)),
        reader.IsDBNull(11) ? null : reader.GetGuid(11),
        reader.IsDBNull(12) ? null : reader.GetString(12),
        new DateTimeOffset(reader.GetFieldValue<DateTime>(13)),
        reader.GetBoolean(14),
        reader.IsDBNull(15) ? null : reader.GetGuid(15),
        reader.IsDBNull(16) ? null : reader.GetString(16),
        reader.IsDBNull(17) ? null : new DateTimeOffset(reader.GetFieldValue<DateTime>(17)),
        reader.IsDBNull(18) ? null : reader.GetString(18),
        reader.IsDBNull(19) ? null : reader.GetString(19),
        reader.IsDBNull(20) ? null : reader.GetString(20));

    /// <summary>
    /// Выбранные варианты (режим «вариант») и все варианты выбранного типа
    /// (режим «тип целиком») с итогом для клиента с НДС, по предложениям.
    /// </summary>
    private static async Task<Dictionary<Guid, List<(int TypeOrder, string TypeName, string? VariantName, decimal Total)>>> ReadSelectionsAsync(
        DbConnection connection,
        Guid[] quoteIds,
        CancellationToken token)
    {
        var selections = new Dictionary<Guid, List<(int TypeOrder, string TypeName, string? VariantName, decimal Total)>>();
        await using (var command = connection.CreateCommand())
        {
            command.CommandText = """
                WITH chosen AS (
                    SELECT type.quote_id, type.id AS type_id, type.name AS type_name,
                           type.sort_order AS type_order, variant.id AS variant_id,
                           variant.name AS variant_name, variant.vat_rate, false AS whole_type
                      FROM quote_proposal_type_selections AS selection
                      JOIN quote_proposal_types AS type ON type.id = selection.proposal_type_id
                      JOIN quote_variants AS variant ON variant.id = selection.variant_id
                      JOIN quotes AS quote ON quote.id = type.quote_id
                     WHERE type.quote_id = ANY(@quote_ids) AND quote.selection_mode = 'variant'
                    UNION ALL
                    SELECT type.quote_id, type.id, type.name, type.sort_order, variant.id,
                           variant.name, variant.vat_rate, true
                      FROM quote_client_type_selections AS selection
                      JOIN quote_proposal_types AS type ON type.id = selection.proposal_type_id
                      JOIN quote_variants AS variant ON variant.proposal_type_id = type.id
                      JOIN quotes AS quote ON quote.id = type.quote_id
                     WHERE type.quote_id = ANY(@quote_ids) AND quote.selection_mode = 'proposal_type'
                )
                SELECT chosen.quote_id, chosen.type_order, chosen.type_name, chosen.variant_name,
                       chosen.whole_type, chosen.vat_rate,
                       COALESCE(sum(position.line_total) FILTER (WHERE NOT position.exclude_from_totals), 0)
                  FROM chosen
                  LEFT JOIN quote_variant_categories AS category ON category.variant_id = chosen.variant_id
                  LEFT JOIN quote_variant_sections AS section ON section.variant_category_id = category.id
                  LEFT JOIN quote_positions AS position ON position.variant_section_id = section.id
                 GROUP BY chosen.quote_id, chosen.type_id, chosen.type_order, chosen.type_name,
                          chosen.variant_id, chosen.variant_name, chosen.whole_type, chosen.vat_rate
                """;
            AddParameter(command, "quote_ids", quoteIds);
            await using var reader = await command.ExecuteReaderAsync(token);
            while (await reader.ReadAsync(token))
            {
                var subtotal = reader.GetDecimal(6);
                decimal? vatRate = reader.IsDBNull(5) ? null : reader.GetDecimal(5);
                var total = subtotal + QuoteVatCalculator.Calculate(subtotal, vatRate);
                var wholeType = reader.GetBoolean(4);
                if (!selections.TryGetValue(reader.GetGuid(0), out var list))
                    selections[reader.GetGuid(0)] = list = [];
                list.Add((reader.GetInt32(1), reader.GetString(2), wholeType ? null : reader.GetString(3), total));
            }
        }
        return selections;
    }

    /// <summary>
    /// Дополняет карточки КП/ПКП сводкой предложения. Три запроса на страницу:
    /// шапки предложений, выбранные варианты с суммами и просмотры ссылок.
    /// </summary>
    private async Task<IReadOnlyList<KanbanCardSummary>> WithQuoteSummariesAsync(
        DbConnection connection,
        List<KanbanCardSummary> cards,
        CancellationToken token)
    {
        if (cards.Count == 0) return cards;
        var withQuotes = await WithQuoteDetailsAsync(connection, cards, token);
        var withOrders = await WithOrderSummariesAsync(connection, withQuotes, token);
        return await WithLinkedCardsAsync(connection, withOrders, token);
    }

    /// <summary>Сводка комплектации: стороны, менеджер, позиции, дозаказ и счета.</summary>
    private static async Task<List<KanbanCardSummary>> WithOrderSummariesAsync(
        DbConnection connection,
        List<KanbanCardSummary> cards,
        CancellationToken token)
    {
        var summaries = new Dictionary<Guid, KanbanOrderSummary>();
        await using (var command = connection.CreateCommand())
        {
            command.CommandText = """
                SELECT orders.card_id, client.name,
                       COALESCE(NULLIF(btrim(company.legal_name), ''), company.name),
                       manager.display_name, orders.object_type,
                       (SELECT count(*)::integer FROM order_positions AS position
                          JOIN order_sections AS section ON section.id = position.order_section_id
                          JOIN order_categories AS category ON category.id = section.order_category_id
                         WHERE category.order_id = orders.id),
                       (SELECT count(*)::integer FROM order_positions AS position
                          JOIN order_sections AS section ON section.id = position.order_section_id
                          JOIN order_categories AS category ON category.id = section.order_category_id
                         WHERE category.order_id = orders.id AND position.is_reorder),
                       (SELECT count(*)::integer FROM order_invoices AS invoice
                         WHERE invoice.order_id = orders.id
                           AND invoice.ready_at IS NOT NULL AND invoice.deleted_at IS NULL),
                       source_card.card_number
                  FROM orders
                  LEFT JOIN clients AS client ON client.id = orders.client_id
                  LEFT JOIN companies AS company ON company.id = orders.executor_company_id
                  LEFT JOIN public.users AS manager ON manager.id = orders.manager_user_id
                  LEFT JOIN quotes AS source_quote ON source_quote.id = orders.source_quote_id
                  LEFT JOIN kanban_cards AS source_card ON source_card.id = source_quote.card_id
                 WHERE orders.card_id = ANY(@card_ids) AND orders.deleted_at IS NULL
                """;
            AddParameter(command, "card_ids", cards.Select(card => card.Id).ToArray());
            await using var reader = await command.ExecuteReaderAsync(token);
            while (await reader.ReadAsync(token))
            {
                summaries[reader.GetGuid(0)] = new KanbanOrderSummary(
                    reader.IsDBNull(1) ? null : reader.GetString(1),
                    reader.IsDBNull(2) ? null : reader.GetString(2),
                    reader.IsDBNull(3) ? null : reader.GetString(3),
                    reader.IsDBNull(4) ? null : reader.GetString(4),
                    reader.GetInt32(5), reader.GetInt32(6), reader.GetInt32(7),
                    reader.IsDBNull(8) ? null : reader.GetInt64(8));
            }
        }
        return summaries.Count == 0
            ? cards
            : cards.Select(card => summaries.TryGetValue(card.Id, out var order) ? card with { Order = order } : card).ToList();
    }

    /// <summary>
    /// Связанные карточки того же рабочего объекта в других канбанах — только
    /// для карточек, стоящих в столбце-триггере переноса.
    /// </summary>
    private static async Task<IReadOnlyList<KanbanCardSummary>> WithLinkedCardsAsync(
        DbConnection connection,
        List<KanbanCardSummary> cards,
        CancellationToken token)
    {
        var links = new Dictionary<Guid, List<KanbanLinkedCard>>();
        await using (var command = connection.CreateCommand())
        {
            command.CommandText = """
                SELECT card.id, other.workflow_id, workflow.name, workflow.specialization,
                       other.id, other.card_number, other_column.name
                  FROM kanban_cards AS card
                  JOIN workflow_column_transfers AS transfer ON transfer.column_id = card.column_id
                  JOIN kanban_cards AS other
                    ON other.work_item_id = card.work_item_id
                   AND other.id <> card.id
                   AND other.deleted_at IS NULL
                  JOIN workflows AS workflow ON workflow.id = other.workflow_id
                  JOIN workflow_columns AS other_column ON other_column.id = other.column_id
                 WHERE card.id = ANY(@card_ids)
                 ORDER BY workflow.sort_order, other.card_number
                """;
            AddParameter(command, "card_ids", cards.Select(card => card.Id).ToArray());
            await using var reader = await command.ExecuteReaderAsync(token);
            while (await reader.ReadAsync(token))
            {
                var cardId = reader.GetGuid(0);
                if (!links.TryGetValue(cardId, out var list)) links[cardId] = list = [];
                list.Add(new KanbanLinkedCard(
                    reader.GetGuid(1), reader.GetString(2),
                    reader.IsDBNull(3) ? null : reader.GetString(3),
                    reader.GetGuid(4), reader.GetInt64(5), reader.GetString(6)));
            }
        }
        return links.Count == 0
            ? cards
            : cards.Select(card => links.TryGetValue(card.Id, out var list) ? card with { LinkedCards = list } : card).ToArray();
    }

    /// <summary>Сводка КП/ПКП: стороны, выбор с суммой и просмотры ссылки.</summary>
    private async Task<List<KanbanCardSummary>> WithQuoteDetailsAsync(
        DbConnection connection,
        List<KanbanCardSummary> cards,
        CancellationToken token)
    {
        var cardIds = cards.Select(card => card.Id).ToArray();
        var headers = new Dictionary<Guid, (Guid QuoteId, string Kind, string? Client, string? Executor, string Mode)>();
        await using (var command = connection.CreateCommand())
        {
            command.CommandText = """
                SELECT quote.card_id, quote.id, quote.quote_kind, client.name,
                       COALESCE(NULLIF(btrim(company.legal_name), ''), company.name),
                       quote.selection_mode
                  FROM quotes AS quote
                  LEFT JOIN clients AS client ON client.id = quote.client_id
                  LEFT JOIN companies AS company ON company.id = quote.executor_company_id
                 WHERE quote.card_id = ANY(@card_ids) AND quote.deleted_at IS NULL
                """;
            AddParameter(command, "card_ids", cardIds);
            await using var reader = await command.ExecuteReaderAsync(token);
            while (await reader.ReadAsync(token))
            {
                headers[reader.GetGuid(0)] = (
                    reader.GetGuid(1), reader.GetString(2),
                    reader.IsDBNull(3) ? null : reader.GetString(3),
                    reader.IsDBNull(4) ? null : reader.GetString(4),
                    reader.GetString(5));
            }
        }
        if (headers.Count == 0) return cards;
        var quoteIds = headers.Values.Select(header => header.QuoteId).ToArray();

        var selections = await ReadSelectionsAsync(connection, quoteIds, token);

        var views = new Dictionary<Guid, (int Count, DateTimeOffset? LastAt)>();
        await using (var command = connection.CreateCommand())
        {
            command.CommandText = """
                SELECT quote_id, COALESCE(sum(access_count), 0)::integer, max(last_accessed_at)
                  FROM public.quote_client_access_links
                 WHERE organization_id = @organization_id AND quote_id = ANY(@quote_ids)
                 GROUP BY quote_id
                """;
            AddParameter(command, "organization_id", tenantContext.OrganizationId);
            AddParameter(command, "quote_ids", quoteIds);
            await using var reader = await command.ExecuteReaderAsync(token);
            while (await reader.ReadAsync(token))
            {
                views[reader.GetGuid(0)] = (
                    reader.GetInt32(1),
                    reader.IsDBNull(2) ? null : new DateTimeOffset(reader.GetFieldValue<DateTime>(2)));
            }
        }

        return cards.Select(card =>
        {
            if (!headers.TryGetValue(card.Id, out var header)) return card;
            var chosen = selections.GetValueOrDefault(header.QuoteId) ?? [];
            // Тип целиком суммирует свои варианты в одну строку.
            var summary = chosen
                .GroupBy(item => (item.TypeOrder, item.TypeName, item.VariantName))
                .OrderBy(group => group.Key.TypeOrder)
                .Select(group => new KanbanQuoteSelection(
                    group.Key.TypeName, group.Key.VariantName, group.Sum(item => item.Total)))
                .ToArray();
            var view = views.GetValueOrDefault(header.QuoteId);
            return card with
            {
                Quote = new KanbanQuoteSummary(
                    header.Kind, header.Client, header.Executor, header.Mode,
                    summary, view.Count, view.LastAt),
            };
        }).ToList();
    }

    private static async Task WriteAuditAsync(
        DbConnection connection,
        DbTransaction transaction,
        Guid actor,
        Guid cardId,
        string action,
        KanbanCardSummary? before,
        KanbanCardSummary? after,
        CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            INSERT INTO audit_log (actor_user_id, entity_type, entity_id, action, diff)
            VALUES (@actor, 'kanban_card', @card_id, @action, CAST(@diff AS jsonb))
            """;
        AddParameter(command, "actor", actor);
        AddParameter(command, "card_id", cardId);
        AddParameter(command, "action", action);
        var diff = AuditChanges.Serialize(before, after);
        if (diff is null) return;
        AddParameter(command, "diff", diff);
        await command.ExecuteNonQueryAsync(token);
    }

    private static void AddCardParameters(
        DbCommand command,
        Guid cardId,
        Guid actor,
        Guid boardId,
        NormalizedCard card)
    {
        AddParameter(command, "id", cardId);
        AddParameter(command, "actor", actor);
        AddParameter(command, "workflow_id", boardId);
        AddParameter(command, "column_id", card.ColumnId);
        AddParameter(command, "category_id", card.CategoryId);
        AddParameter(command, "section_id", card.SectionId ?? (object)DBNull.Value);
        AddParameter(command, "title", card.Title);
        AddParameter(command, "values", JsonSerializer.Serialize(card.Values, JsonOptions));
    }

    private static bool IsEmpty(JsonElement value) =>
        value.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined ||
        value.ValueKind == JsonValueKind.String && string.IsNullOrWhiteSpace(value.GetString());

    private static IdentityException BoardNotFound() =>
        new(404, "kanban_not_found", "Канбан не найден.");

    private static IdentityException CardNotFound() =>
        new(404, "kanban_card_not_found", "Карточка канбана не найдена.");

    private static IdentityException Invalid(string code, string message) => new(400, code, message);

    private static void AddParameter(DbCommand command, string name, object value)
    {
        var parameter = command.CreateParameter();
        parameter.ParameterName = name;
        parameter.Value = value;
        command.Parameters.Add(parameter);
    }

    private sealed record ConfiguredField(string Code, string Label, string FieldType, bool IsRequired);

    private sealed record NormalizedCard(
        Guid ColumnId,
        Guid CategoryId,
        Guid? SectionId,
        string Title,
        IReadOnlyDictionary<string, JsonElement> Values);

    private sealed class MutableCategory(
        Guid id,
        string name,
        int sortOrder,
        IReadOnlyList<KanbanSectionSummary> sections,
        string? supplierFilterFieldCode)
    {
        public List<KanbanFieldSummary> Fields { get; } = [];
        public KanbanCategorySummary ToSummary() => new(id, name, sortOrder, sections, Fields, supplierFilterFieldCode);
    }
}
