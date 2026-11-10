using System.Data.Common;
using Npgsql;

namespace SkladKomforta.Infrastructure.Quotes;

/// <summary>Writes position inserts in bounded batches within the document transaction.</summary>
internal sealed class PostgresPositionInsertBatch(DbConnection connection, DbTransaction transaction)
{
    private const int BatchSize = 100;
    private readonly List<NpgsqlBatchCommand> _commands = [];

    public async Task AddAsync(string sql, CancellationToken token,
        params (string Name, object Value)[] parameters)
    {
        var command = new NpgsqlBatchCommand(sql);
        foreach (var (name, value) in parameters)
            command.Parameters.Add(new NpgsqlParameter(name, value));
        _commands.Add(command);
        if (_commands.Count >= BatchSize) await FlushAsync(token);
    }

    public async Task FlushAsync(CancellationToken token)
    {
        if (_commands.Count == 0) return;
        await using var batch = new NpgsqlBatch(
            (NpgsqlConnection)connection, (NpgsqlTransaction)transaction);
        foreach (var command in _commands) batch.BatchCommands.Add(command);
        await batch.ExecuteNonQueryAsync(token);
        _commands.Clear();
    }
}
