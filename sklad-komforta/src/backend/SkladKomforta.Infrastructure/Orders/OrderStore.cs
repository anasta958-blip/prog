using System.Data.Common;
using System.Text.Json;
using SkladKomforta.Application.Orders;

namespace SkladKomforta.Infrastructure.Orders;

/// <summary>
/// Общие операции с комплектацией для сервиса редактора и переноса из КП:
/// чтение дерева, РОП по структуре, признак дозаказа, поля канбана и аудит.
/// </summary>
internal static class OrderStore
{
    public static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    /// <summary>Сохраняемое сервером состояние позиции, которого нет в запросе редактора.</summary>
    public sealed record PositionState(bool IsReorder, string? SourceKey, decimal? SourceQuantity);

    /// <summary>
    /// РОП — руководитель сотрудника по структуре «Сотрудники и структура»;
    /// <see langword="null"/>, если руководителя нет или он неактивен.
    /// </summary>
    public static async Task<Guid?> SupervisorOfAsync(
        DbConnection connection,
        DbTransaction? transaction,
        Guid organizationId,
        Guid? userId,
        CancellationToken token)
    {
        if (!userId.HasValue) return null;
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            SELECT supervisor.user_id
              FROM public.organization_members AS member
              JOIN member_reporting AS reporting ON reporting.membership_id = member.id
              JOIN public.organization_members AS supervisor
                ON supervisor.id = reporting.supervisor_membership_id
             WHERE member.organization_id = @organization_id
               AND member.user_id = @user_id
               AND member.deleted_at IS NULL
               AND supervisor.is_active AND supervisor.deleted_at IS NULL
             LIMIT 1
            """;
        Add(command, "organization_id", organizationId);
        Add(command, "user_id", userId.Value);
        return await command.ExecuteScalarAsync(token) as Guid?;
    }

    /// <summary>
    /// Стоит ли карточка в столбце дозаказа или правее. Без настроенного столбца
    /// дозаказа позиции дозаказом не считаются.
    /// </summary>
    public static async Task<bool> IsReorderColumnAsync(
        DbConnection connection,
        DbTransaction? transaction,
        Guid boardId,
        Guid columnId,
        CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            SELECT EXISTS (
                SELECT 1
                  FROM workflow_columns AS current_column
                  JOIN workflow_columns AS reorder_column
                    ON reorder_column.workflow_id = current_column.workflow_id
                   AND reorder_column.reorder_from
                 WHERE current_column.id = @column_id
                   AND current_column.workflow_id = @workflow_id
                   AND current_column.sort_order >= reorder_column.sort_order)
            """;
        Add(command, "workflow_id", boardId);
        Add(command, "column_id", columnId);
        return await command.ExecuteScalarAsync(token) is true;
    }

    /// <summary>Категории канбана (категория каталога → коды полей, назначенных канбану).</summary>
    public static async Task<Dictionary<Guid, HashSet<string>>> ReadBoardFieldsAsync(
        DbConnection connection,
        DbTransaction? transaction,
        Guid boardId,
        CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            SELECT workflow_category.category_id, workflow_field.field_code
              FROM workflow_categories AS workflow_category
              LEFT JOIN workflow_category_fields AS workflow_field
                ON workflow_field.workflow_id = workflow_category.workflow_id
               AND workflow_field.category_id = workflow_category.category_id
             WHERE workflow_category.workflow_id = @workflow_id
            """;
        Add(command, "workflow_id", boardId);
        var result = new Dictionary<Guid, HashSet<string>>();
        await using var reader = await command.ExecuteReaderAsync(token);
        while (await reader.ReadAsync(token))
        {
            var categoryId = reader.GetGuid(0);
            if (!result.TryGetValue(categoryId, out var fields))
                result[categoryId] = fields = new HashSet<string>(StringComparer.Ordinal);
            if (!reader.IsDBNull(1)) fields.Add(reader.GetString(1));
        }
        return result;
    }

    /// <summary>Значения справочника «Тип объекта» канбана комплектации.</summary>
    public static async Task<HashSet<string>> ReadObjectTypesAsync(
        DbConnection connection,
        DbTransaction? transaction,
        Guid boardId,
        CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            SELECT value FROM workflow_order_options
             WHERE workflow_id = @workflow_id AND option_kind = 'object_type'
            """;
        Add(command, "workflow_id", boardId);
        var result = new HashSet<string>(StringComparer.Ordinal);
        await using var reader = await command.ExecuteReaderAsync(token);
        while (await reader.ReadAsync(token)) result.Add(reader.GetString(0));
        return result;
    }

    /// <summary>Состояние позиций, которое сохраняется при замене дерева редактором.</summary>
    public static async Task<Dictionary<Guid, PositionState>> ReadPositionStateAsync(
        DbConnection connection,
        DbTransaction? transaction,
        Guid orderId,
        CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            SELECT position.id, position.is_reorder, position.source_key, position.source_quantity
              FROM order_positions AS position
              JOIN order_sections AS section ON section.id = position.order_section_id
              JOIN order_categories AS category ON category.id = section.order_category_id
             WHERE category.order_id = @order_id
            """;
        Add(command, "order_id", orderId);
        var result = new Dictionary<Guid, PositionState>();
        await using var reader = await command.ExecuteReaderAsync(token);
        while (await reader.ReadAsync(token))
            result[reader.GetGuid(0)] = new PositionState(
                reader.GetBoolean(1),
                reader.IsDBNull(2) ? null : reader.GetString(2),
                reader.IsDBNull(3) ? null : reader.GetDecimal(3));
        return result;
    }

    /// <summary>Собирает комплектацию карточки из нормализованных таблиц.</summary>
    public static async Task<OrderDetails?> ReadAsync(
        DbConnection connection,
        DbTransaction? transaction,
        Guid boardId,
        Guid cardId,
        bool canChangeManager,
        bool canManageInvoices,
        CancellationToken token)
    {
        Header header;
        await using (var command = connection.CreateCommand())
        {
            command.Transaction = transaction;
            command.CommandText = """
                SELECT orders.id, orders.workflow_id, orders.card_id, orders.title, orders.object_type,
                       orders.client_id, orders.executor_company_id, orders.manager_user_id,
                       orders.sales_head_user_id, orders.created_at, orders.updated_at,
                       quote.id, quote.workflow_id, quote.card_id, quote_card.card_number, quote.title
                  FROM orders
                  LEFT JOIN quotes AS quote
                    ON quote.id = orders.source_quote_id AND quote.deleted_at IS NULL
                  LEFT JOIN kanban_cards AS quote_card
                    ON quote_card.id = quote.card_id AND quote_card.deleted_at IS NULL
                 WHERE orders.workflow_id = @workflow_id
                   AND orders.card_id = @card_id
                   AND orders.deleted_at IS NULL
                """;
            Add(command, "workflow_id", boardId);
            Add(command, "card_id", cardId);
            await using var reader = await command.ExecuteReaderAsync(token);
            if (!await reader.ReadAsync(token)) return null;
            header = new Header(
                reader.GetGuid(0), reader.GetGuid(1), reader.GetGuid(2), reader.GetString(3),
                reader.IsDBNull(4) ? null : reader.GetString(4),
                reader.GetGuid(5), reader.GetGuid(6),
                reader.IsDBNull(7) ? null : reader.GetGuid(7),
                reader.IsDBNull(8) ? null : reader.GetGuid(8),
                Timestamp(reader, 9), Timestamp(reader, 10),
                reader.IsDBNull(11) || reader.IsDBNull(14)
                    ? null
                    : new OrderSourceQuote(
                        reader.GetGuid(11), reader.GetGuid(12), reader.GetGuid(13),
                        checked((int)reader.GetInt64(14)), reader.GetString(15)));
        }

        var categories = new List<MutableCategory>();
        var categoriesById = new Dictionary<Guid, MutableCategory>();
        await using (var command = connection.CreateCommand())
        {
            command.Transaction = transaction;
            command.CommandText = """
                SELECT id, catalog_category_id, name_snapshot, sort_order
                  FROM order_categories
                 WHERE order_id = @order_id
                 ORDER BY sort_order, id
                """;
            Add(command, "order_id", header.Id);
            await using var reader = await command.ExecuteReaderAsync(token);
            while (await reader.ReadAsync(token))
            {
                var item = new MutableCategory(
                    reader.GetGuid(0), reader.IsDBNull(1) ? null : reader.GetGuid(1),
                    reader.GetString(2), reader.GetInt32(3));
                categories.Add(item);
                categoriesById[item.Id] = item;
            }
        }

        var sectionsById = new Dictionary<Guid, MutableSection>();
        await using (var command = connection.CreateCommand())
        {
            command.Transaction = transaction;
            command.CommandText = """
                SELECT section.id, section.order_category_id, section.catalog_section_id,
                       section.name_snapshot, section.sort_order
                  FROM order_sections AS section
                  JOIN order_categories AS category ON category.id = section.order_category_id
                 WHERE category.order_id = @order_id
                 ORDER BY category.sort_order, section.sort_order, section.id
                """;
            Add(command, "order_id", header.Id);
            await using var reader = await command.ExecuteReaderAsync(token);
            while (await reader.ReadAsync(token))
            {
                var item = new MutableSection(
                    reader.GetGuid(0), reader.IsDBNull(2) ? null : reader.GetGuid(2),
                    reader.GetString(3), reader.GetInt32(4));
                categoriesById[reader.GetGuid(1)].Sections.Add(item);
                sectionsById[item.Id] = item;
            }
        }

        await using (var command = connection.CreateCommand())
        {
            command.Transaction = transaction;
            command.CommandText = """
                SELECT position.id, position.order_section_id, position.catalog_item_id,
                       position.name_snapshot, position.marking_snapshot, position.unit_snapshot,
                       position.quantity, position.is_reorder, position.source_key IS NOT NULL,
                       position.values::text, position.sort_order
                  FROM order_positions AS position
                  JOIN order_sections AS section ON section.id = position.order_section_id
                  JOIN order_categories AS category ON category.id = section.order_category_id
                 WHERE category.order_id = @order_id
                 ORDER BY category.sort_order, section.sort_order, position.sort_order, position.id
                """;
            Add(command, "order_id", header.Id);
            await using var reader = await command.ExecuteReaderAsync(token);
            while (await reader.ReadAsync(token))
            {
                var values = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(
                    reader.GetString(9), JsonOptions) ?? new Dictionary<string, JsonElement>();
                sectionsById[reader.GetGuid(1)].Positions.Add(new OrderPositionDetails(
                    reader.GetGuid(0), reader.IsDBNull(2) ? null : reader.GetGuid(2),
                    reader.GetString(3), reader.GetString(4), reader.GetString(5),
                    reader.GetDecimal(6), reader.GetBoolean(7), reader.GetBoolean(8),
                    values, reader.GetInt32(10)));
            }
        }

        return new OrderDetails(
            header.Id, header.WorkflowId, header.CardId, header.Title, header.ObjectType,
            header.ClientId, header.ExecutorCompanyId, header.ManagerUserId, header.SalesHeadUserId,
            header.SourceQuote, categories.Select(item => item.ToDetails()).ToArray(),
            header.CreatedAt, header.UpdatedAt, canChangeManager, canManageInvoices);
    }

    /// <summary>Пишет изменение комплектации в журнал аудита (без пустых diff).</summary>
    public static async Task WriteAuditAsync(
        DbConnection connection,
        DbTransaction transaction,
        Guid actorUserId,
        Guid orderId,
        string action,
        object? before,
        object? after,
        CancellationToken token)
    {
        var diff = AuditChanges.Serialize(before, after);
        if (diff is null) return;
        await ExecuteAsync(connection, transaction, """
            INSERT INTO audit_log (actor_user_id, entity_type, entity_id, action, diff)
            VALUES (@actor, 'order', @order_id, @action, CAST(@diff AS jsonb))
            """, token,
            ("actor", actorUserId), ("order_id", orderId), ("action", action), ("diff", diff));
    }

    /// <summary>Бизнес-данные комплектации для аудита, без технических меток.</summary>
    public static object AuditSnapshot(OrderDetails order) => new
    {
        order.Title,
        order.ObjectType,
        order.ClientId,
        order.ExecutorCompanyId,
        order.ManagerUserId,
        order.SalesHeadUserId,
        Categories = order.Categories.Select(category => new
        {
            category.Name,
            Sections = category.Sections.Select(section => new
            {
                section.Name,
                Positions = section.Positions.Select(position => new
                {
                    position.Name,
                    position.Marking,
                    position.Unit,
                    position.Quantity,
                    position.IsReorder,
                    position.Values,
                }),
            }),
        }),
    };

    public static async Task ExecuteAsync(
        DbConnection connection,
        DbTransaction? transaction,
        string sql,
        CancellationToken token,
        params (string Name, object Value)[] parameters)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = sql;
        foreach (var (name, value) in parameters) Add(command, name, value);
        await command.ExecuteNonQueryAsync(token);
    }

    public static void Add(DbCommand command, string name, object value)
    {
        var parameter = command.CreateParameter();
        parameter.ParameterName = name;
        parameter.Value = value;
        command.Parameters.Add(parameter);
    }

    public static object Db(object? value) => value ?? DBNull.Value;

    private static DateTimeOffset Timestamp(DbDataReader reader, int ordinal) =>
        new(reader.GetFieldValue<DateTime>(ordinal));

    private sealed record Header(
        Guid Id, Guid WorkflowId, Guid CardId, string Title, string? ObjectType,
        Guid ClientId, Guid ExecutorCompanyId, Guid? ManagerUserId, Guid? SalesHeadUserId,
        DateTimeOffset CreatedAt, DateTimeOffset UpdatedAt, OrderSourceQuote? SourceQuote);

    private sealed class MutableCategory(Guid id, Guid? catalogCategoryId, string name, int sortOrder)
    {
        public Guid Id { get; } = id;
        public List<MutableSection> Sections { get; } = [];
        public OrderCategoryDetails ToDetails() =>
            new(Id, catalogCategoryId, name, sortOrder, Sections.Select(item => item.ToDetails()).ToArray());
    }

    private sealed class MutableSection(Guid id, Guid? catalogSectionId, string name, int sortOrder)
    {
        public Guid Id { get; } = id;
        public List<OrderPositionDetails> Positions { get; } = [];
        public OrderSectionDetails ToDetails() => new(Id, catalogSectionId, name, sortOrder, Positions);
    }
}
