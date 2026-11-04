using System.Data.Common;
using System.Text.Json;
using SkladKomforta.Application.Abstractions.Persistence;
using SkladKomforta.Application.Company;
using SkladKomforta.Application.Identity;
using SkladKomforta.Application.Kanban;
using SkladKomforta.Infrastructure.Kanban;

namespace SkladKomforta.Infrastructure.Company;

internal sealed class PostgresDocumentLayoutService(IDatabaseConnectionFactory factory) : IDocumentLayoutService
{
    public async Task<IReadOnlyList<DocumentLayoutBoard>> GetAsync(CancellationToken token)
    {
        await using var connection = await factory.OpenTenantConnectionAsync(token);
        var boards = new List<(Guid Id, string Name, string Kind)>();
        await using (var command = connection.CreateCommand())
        {
            command.CommandText = "SELECT id, name, specialization FROM workflows WHERE specialization IN ('quote', 'quote_and_prequote', 'order') ORDER BY sort_order, name";
            await using var reader = await command.ExecuteReaderAsync(token);
            while (await reader.ReadAsync(token)) boards.Add((reader.GetGuid(0), reader.GetString(1), reader.GetString(2)));
        }
        var result = new List<DocumentLayoutBoard>();
        foreach (var board in boards)
        {
            var categories = await PostgresKanbanService.ReadCategoriesAsync(connection, board.Id, token);
            var selected = await ReadSelectionsAsync(connection, board.Id, token);
            result.Add(new(board.Id, board.Name, board.Kind, categories.Select(category => new DocumentLayoutCategory(
                category.CategoryId, category.Name, category.Fields,
                selected.TryGetValue(category.CategoryId, out var codes)
                    ? codes.Where(code => category.Fields.Any(field => field.Code == code)).ToArray() : null)).ToArray()));
        }
        return result;
    }

    public async Task SaveAsync(Guid actorId, Guid workflowId, SaveDocumentLayout request, CancellationToken token)
    {
        var board = (await GetAsync(token)).FirstOrDefault(item => item.WorkflowId == workflowId)
            ?? throw new IdentityException(404, "document_layout_board_missing", "Канбан не найден.");
        if (request.Categories is null || request.Categories.Select(item => item.CategoryId).Distinct().Count() != request.Categories.Count)
            throw new IdentityException(400, "document_layout_invalid", "Категории не должны повторяться.");
        foreach (var item in request.Categories)
        {
            var category = board.Categories.FirstOrDefault(category => category.CategoryId == item.CategoryId);
            if (category is null || item.FieldCodes is { } codes &&
                (codes.Count != codes.Distinct(StringComparer.Ordinal).Count() ||
                 codes.Any(code => !category.Fields.Any(field => field.Code == code))))
                throw new IdentityException(400, "document_layout_fields_invalid", "Выбраны поля, недоступные для категории в этом канбане.");
        }
        await using var connection = await factory.OpenTenantConnectionAsync(token);
        await using var transaction = await connection.BeginTransactionAsync(token);
        foreach (var item in request.Categories)
        {
            await using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText = item.FieldCodes is null
                ? "DELETE FROM document_layouts WHERE workflow_id = @workflow AND category_id = @category"
                : "INSERT INTO document_layouts (workflow_id, category_id, field_codes) VALUES (@workflow, @category, CAST(@fields AS jsonb)) ON CONFLICT (workflow_id, category_id) DO UPDATE SET field_codes = EXCLUDED.field_codes, updated_at = now()";
            Add(command, "workflow", workflowId);
            Add(command, "category", item.CategoryId);
            if (item.FieldCodes is not null) Add(command, "fields", JsonSerializer.Serialize(item.FieldCodes));
            await command.ExecuteNonQueryAsync(token);
        }
        await using (var audit = connection.CreateCommand())
        {
            audit.Transaction = transaction;
            audit.CommandText = "INSERT INTO audit_log (actor_user_id, entity_type, entity_id, action) VALUES (@actor, 'document_layout', @workflow, 'updated')";
            Add(audit, "actor", actorId);
            Add(audit, "workflow", workflowId);
            await audit.ExecuteNonQueryAsync(token);
        }
        await transaction.CommitAsync(token);
    }

    public async Task<IReadOnlyDictionary<Guid, IReadOnlyList<KanbanFieldSummary>>> GetFieldsAsync(Guid workflowId, CancellationToken token)
    {
        await using var connection = await factory.OpenTenantConnectionAsync(token);
        return await ReadFieldsAsync(connection, workflowId, token);
    }

    internal static async Task<IReadOnlyDictionary<Guid, IReadOnlyList<KanbanFieldSummary>>> ReadFieldsAsync(
        DbConnection connection, Guid workflowId, CancellationToken token, IReadOnlyList<KanbanCategorySummary>? categories = null)
    {
        var selected = await ReadSelectionsAsync(connection, workflowId, token);
        if (selected.Count == 0) return new Dictionary<Guid, IReadOnlyList<KanbanFieldSummary>>();
        categories ??= await PostgresKanbanService.ReadCategoriesAsync(connection, workflowId, token);
        return selected.ToDictionary(pair => pair.Key, pair => (IReadOnlyList<KanbanFieldSummary>)pair.Value
            .Select(code => categories.FirstOrDefault(category => category.CategoryId == pair.Key)?.Fields.FirstOrDefault(field => field.Code == code))
            .OfType<KanbanFieldSummary>().ToArray());
    }

    private static async Task<Dictionary<Guid, string[]>> ReadSelectionsAsync(DbConnection connection, Guid workflowId, CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.CommandText = "SELECT category_id, field_codes::text FROM document_layouts WHERE workflow_id = @workflow";
        Add(command, "workflow", workflowId);
        var result = new Dictionary<Guid, string[]>();
        await using var reader = await command.ExecuteReaderAsync(token);
        while (await reader.ReadAsync(token)) result.Add(reader.GetGuid(0), JsonSerializer.Deserialize<string[]>(reader.GetString(1)) ?? []);
        return result;
    }

    private static void Add(DbCommand command, string name, object value)
    {
        var parameter = command.CreateParameter();
        parameter.ParameterName = name;
        parameter.Value = value;
        command.Parameters.Add(parameter);
    }
}
