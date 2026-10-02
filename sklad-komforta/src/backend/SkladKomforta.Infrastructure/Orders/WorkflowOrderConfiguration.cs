using System.Data.Common;
using SkladKomforta.Application.Onboarding;

namespace SkladKomforta.Infrastructure.Orders;

/// <summary>
/// Материализует настройки канбанов, относящиеся к переносу КП ↔ комплектация:
/// столбцы-триггеры, столбец начала дозаказа и справочники канбана комплектации.
/// Вызывается после записи всех канбанов, потому что триггер ссылается на
/// столбец другого канбана.
/// </summary>
internal static class WorkflowOrderConfiguration
{
    /// <summary>Перезаписывает настройки всех переданных канбанов.</summary>
    /// <param name="workflowIds">Код канбана → его идентификатор.</param>
    /// <param name="columnIds">Код канбана → (клиентский идентификатор столбца → идентификатор).</param>
    public static async Task SaveAsync(
        DbConnection connection,
        DbTransaction transaction,
        IReadOnlyList<WorkflowDraft> workflows,
        IReadOnlyDictionary<string, Guid> workflowIds,
        IReadOnlyDictionary<string, Dictionary<string, Guid>> columnIds,
        CancellationToken token)
    {
        foreach (var workflow in workflows)
        {
            var workflowId = workflowIds[workflow.Code.Trim()];
            await ExecuteAsync(connection, transaction,
                "UPDATE workflow_columns SET reorder_from = false WHERE workflow_id = @id AND reorder_from",
                token, ("id", workflowId));
            await ExecuteAsync(connection, transaction,
                "DELETE FROM workflow_column_transfers WHERE column_id IN (SELECT id FROM workflow_columns WHERE workflow_id = @id)",
                token, ("id", workflowId));
            await ExecuteAsync(connection, transaction,
                "DELETE FROM workflow_order_options WHERE workflow_id = @id",
                token, ("id", workflowId));
        }

        foreach (var workflow in workflows)
        {
            var workflowId = workflowIds[workflow.Code.Trim()];
            var columns = columnIds[workflow.Code.Trim()];
            foreach (var column in workflow.Columns)
            {
                var columnId = columns[column.ClientId];
                if (column.ReorderFrom)
                    await ExecuteAsync(connection, transaction,
                        "UPDATE workflow_columns SET reorder_from = true WHERE id = @id",
                        token, ("id", columnId));
                if (column.TransferTo is { } transfer)
                {
                    var targetCode = transfer.WorkflowCode.Trim();
                    await ExecuteAsync(connection, transaction, """
                        INSERT INTO workflow_column_transfers (column_id, target_workflow_id, target_column_id)
                        VALUES (@column_id, @target_workflow_id, @target_column_id)
                        """, token,
                        ("column_id", columnId),
                        ("target_workflow_id", workflowIds[targetCode]),
                        ("target_column_id", columnIds[targetCode][transfer.ColumnClientId]));
                }
            }

            var settings = workflow.OrderSettings;
            await SaveOptionsAsync(connection, transaction, workflowId, "object_type", settings?.ObjectTypes, token);
            await SaveOptionsAsync(connection, transaction, workflowId, "shipment_status", settings?.ShipmentStatuses, token);
        }
    }

    private static async Task SaveOptionsAsync(
        DbConnection connection,
        DbTransaction transaction,
        Guid workflowId,
        string kind,
        IReadOnlyList<string>? values,
        CancellationToken token)
    {
        var items = values ?? [];
        for (var index = 0; index < items.Count; index++)
            await ExecuteAsync(connection, transaction, """
                INSERT INTO workflow_order_options (workflow_id, option_kind, value, sort_order)
                VALUES (@workflow_id, @kind, @value, @sort)
                """, token,
                ("workflow_id", workflowId), ("kind", kind),
                ("value", items[index].Trim()), ("sort", index));
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
        foreach (var (name, value) in parameters)
        {
            var parameter = command.CreateParameter();
            parameter.ParameterName = name;
            parameter.Value = value;
            command.Parameters.Add(parameter);
        }
        await command.ExecuteNonQueryAsync(token);
    }
}
