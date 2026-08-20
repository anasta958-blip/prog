using Microsoft.Extensions.Diagnostics.HealthChecks;
using StackExchange.Redis;

namespace SkladKomforta.Infrastructure.Health;

/// <summary>Проверяет доступность Redis командой PING через общий multiplexer.</summary>
internal sealed class RedisHealthCheck(IConnectionMultiplexer connection) : IHealthCheck
{
    /// <inheritdoc />
    public async Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context,
        CancellationToken cancellationToken = default)
    {
        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            await connection.GetDatabase().PingAsync();
            return HealthCheckResult.Healthy();
        }
        catch (Exception exception)
        {
            return HealthCheckResult.Unhealthy("Redis is unavailable.", exception);
        }
    }
}
