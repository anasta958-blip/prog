using StackExchange.Redis;
using SkladKomforta.Application.Abstractions.Caching;

namespace SkladKomforta.Infrastructure.Caching;

/// <summary>Реализует application cache через один потокобезопасный Redis multiplexer.</summary>
internal sealed class RedisApplicationCache(IConnectionMultiplexer connection) : IApplicationCache
{
    private readonly IDatabase _database = connection.GetDatabase();

    /// <inheritdoc />
    public async Task<string?> GetStringAsync(
        string key,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var value = await _database.StringGetAsync(key);
        return value.HasValue ? value.ToString() : null;
    }

    /// <inheritdoc />
    public async Task SetStringAsync(
        string key,
        string value,
        TimeSpan lifetime,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        await _database.StringSetAsync(key, value, lifetime);
    }

    /// <inheritdoc />
    public async Task RemoveAsync(string key, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        await _database.KeyDeleteAsync(key);
    }
}
