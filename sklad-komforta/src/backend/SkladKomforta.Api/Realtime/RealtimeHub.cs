using System.Collections.Concurrent;
using System.Text.Json;
using System.Threading.Channels;
using StackExchange.Redis;
using SkladKomforta.Infrastructure.Realtime;

namespace SkladKomforta.Api.Realtime;

/// <summary>Одно WebSocket-подключение: организация, тема и очередь исходящих сообщений.</summary>
internal sealed class RealtimeSubscriber(Guid organizationId, string topic)
{
    public Guid Id { get; } = Guid.NewGuid();
    public Guid OrganizationId { get; } = organizationId;
    public string Topic { get; } = topic;

    /// <summary>
    /// Ограниченная очередь: медленный клиент теряет старые сигналы, но не
    /// копит память. Потеря безопасна — клиент всё равно перечитывает данные.
    /// </summary>
    public Channel<string> Messages { get; } = Channel.CreateBounded<string>(
        new BoundedChannelOptions(64)
        {
            FullMode = BoundedChannelFullMode.DropOldest,
            SingleReader = true,
        });
}

/// <summary>
/// Раздаёт сигналы из Redis pub/sub подключённым клиентам этого экземпляра API.
/// Одна подписка на шаблон каналов обслуживает все организации.
/// </summary>
internal sealed class RealtimeHub(IConnectionMultiplexer redis) : IDisposable
{
    private readonly ConcurrentDictionary<Guid, ConcurrentDictionary<Guid, RealtimeSubscriber>> _organizations = new();
    private readonly SemaphoreSlim _subscribeGate = new(1, 1);
    private volatile bool _subscribed;

    /// <summary>Число активных подключений (для диагностики и тестов).</summary>
    public int ConnectionCount => _organizations.Values.Sum(item => item.Count);

    /// <summary>Регистрирует подключение; при первом подключении подписывается на Redis.</summary>
    public async Task<RealtimeSubscriber> RegisterAsync(Guid organizationId, string topic, CancellationToken cancellationToken)
    {
        await EnsureSubscribedAsync(cancellationToken);
        var subscriber = new RealtimeSubscriber(organizationId, topic);
        _organizations.GetOrAdd(organizationId, _ => new()).TryAdd(subscriber.Id, subscriber);
        return subscriber;
    }

    /// <summary>Удаляет подключение и завершает его очередь.</summary>
    public void Unregister(RealtimeSubscriber subscriber)
    {
        if (_organizations.TryGetValue(subscriber.OrganizationId, out var subscribers))
            subscribers.TryRemove(subscriber.Id, out _);
        subscriber.Messages.Writer.TryComplete();
    }

    /// <summary>Передаёт сообщение подключениям организации с совпадающей темой.</summary>
    internal void Dispatch(Guid organizationId, string message)
    {
        if (!_organizations.TryGetValue(organizationId, out var subscribers) || subscribers.IsEmpty) return;
        string? topic;
        try
        {
            using var document = JsonDocument.Parse(message);
            topic = document.RootElement.TryGetProperty("topic", out var value) ? value.GetString() : null;
        }
        catch (JsonException)
        {
            return;
        }
        foreach (var subscriber in subscribers.Values)
        {
            if (subscriber.Topic == topic) subscriber.Messages.Writer.TryWrite(message);
        }
    }

    /// <inheritdoc />
    public void Dispose() => _subscribeGate.Dispose();

    private async Task EnsureSubscribedAsync(CancellationToken cancellationToken)
    {
        if (_subscribed) return;
        await _subscribeGate.WaitAsync(cancellationToken);
        try
        {
            if (_subscribed) return;
            // Multiplexer сам восстанавливает подписку после переподключения к Redis.
            await redis.GetSubscriber().SubscribeAsync(RealtimeChannels.AllOrganizations, (channel, value) =>
            {
                if (RealtimeChannels.TryParseOrganization(channel.ToString(), out var organizationId) && value.HasValue)
                    Dispatch(organizationId, value.ToString());
            });
            _subscribed = true;
        }
        finally
        {
            _subscribeGate.Release();
        }
    }
}
