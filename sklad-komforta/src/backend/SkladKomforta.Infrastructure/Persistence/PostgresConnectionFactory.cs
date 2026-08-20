using System.Data.Common;
using Npgsql;
using SkladKomforta.Application.Abstractions.Persistence;
using SkladKomforta.Application.Abstractions.Tenancy;

namespace SkladKomforta.Infrastructure.Persistence;

/// <summary>
/// Использует общий пул Npgsql, но на каждом tenant-соединении явно задаёт
/// проверенный <c>search_path</c>. При ошибке настройки соединение освобождается.
/// </summary>
internal sealed class PostgresConnectionFactory(
    NpgsqlDataSource dataSource,
    ITenantContext tenantContext) : IDatabaseConnectionFactory
{
    /// <inheritdoc />
    public async ValueTask<DbConnection> OpenPublicConnectionAsync(
        CancellationToken cancellationToken = default) =>
        await dataSource.OpenConnectionAsync(cancellationToken);

    /// <inheritdoc />
    public async ValueTask<DbConnection> OpenTenantConnectionAsync(
        CancellationToken cancellationToken = default)
    {
        var connection = await dataSource.OpenConnectionAsync(cancellationToken);

        try
        {
            await using var command = connection.CreateCommand();
            command.CommandText = $"SET search_path TO {tenantContext.SchemaName.Value}, public";
            await command.ExecuteNonQueryAsync(cancellationToken);
            return connection;
        }
        catch
        {
            await connection.DisposeAsync();
            throw;
        }
    }
}
