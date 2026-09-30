using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.Extensions.Logging;
using StackExchange.Redis;
using SkladKomforta.Application.Abstractions.Realtime;

namespace SkladKomforta.Infrastructure.Realtime;

/// <summary>Имена каналов и формат сообщений Redis pub/sub для уведомлений.</summary>
public static class RealtimeChannels
{
    /// <summary>Префикс каналов; организация дописывается в конце.</summary>
    public const string Prefix = "realtime:org:";

    /// <summary>Шаблон подписки на каналы всех организаций.</summary>
    public static readonly RedisChannel AllOrganizations = RedisChannel.Pattern(Prefix + "*");

    /// <summary>Канал одной организации.</summary>
    public static RedisChannel ForOrganization(Guid organizationId) =>
        RedisChannel.Literal(Prefix + organizationId.ToString("N"));

    /// <summary>Извлекает организацию из имени канала.</summary>
    public static bool TryParseOrganization(string? channel, out Guid organizationId)
    {
        organizationId = Guid.Empty;
        return channel is not null &&
               channel.StartsWith(Prefix, StringComparison.Ordinal) &&
               Guid.TryParseExact(channel[Prefix.Length..], "N", out organizationId);
    }

    /// <summary>Сериализация в camelCase: этот же JSON без изменений уходит клиенту.</summary>
    public static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
}

/// <summary>
/// Сообщение, доставляемое клиенту. Организация в него не входит: она уже
/// определяется каналом и подключением.
/// </summary>
public sealed record RealtimeMessage(string Topic, string Kind, Guid? BoardId, Guid? EntityId, string? Section = null);

/// <summary>Публикует сигналы изменений через Redis pub/sub всем экземплярам API.</summary>
internal sealed class RedisRealtimeNotifier(
    IConnectionMultiplexer connection,
    ILogger<RedisRealtimeNotifier> logger) : IRealtimeNotifier
{
    private static readonly Action<ILogger, string, Exception?> LogPublishFailure =
        LoggerMessage.Define<string>(
            LogLevel.Warning,
            new EventId(3101, nameof(LogPublishFailure)),
            "Не удалось отправить уведомление об изменении темы {Topic}.");

    /// <inheritdoc />
    public async Task PublishAsync(RealtimeChange change, CancellationToken cancellationToken = default)
    {
        try
        {
            var message = JsonSerializer.Serialize(
                new RealtimeMessage(change.Topic, change.Kind, change.BoardId, change.EntityId, change.Section),
                RealtimeChannels.JsonOptions);
            await connection.GetSubscriber().PublishAsync(
                RealtimeChannels.ForOrganization(change.OrganizationId), message);
        }
        catch (Exception exception) when (exception is RedisException or TimeoutException or ObjectDisposedException)
        {
            // Изменение уже сохранено; клиенты увидят его при следующей загрузке.
            LogPublishFailure(logger, change.Topic, exception);
        }
    }
}

/// <summary>Хранит одноразовые билеты подключения в Redis под хешем билета.</summary>
internal sealed class RedisRealtimeTicketStore(IConnectionMultiplexer connection) : IRealtimeTicketStore
{
    private readonly IDatabase _database = connection.GetDatabase();

    /// <inheritdoc />
    public async Task<string> IssueAsync(RealtimeTicket ticket, TimeSpan lifetime, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var value = WebEncoders.Base64UrlEncode(RandomNumberGenerator.GetBytes(32));
        await _database.StringSetAsync(Key(value), JsonSerializer.Serialize(ticket, RealtimeChannels.JsonOptions), lifetime);
        return value;
    }

    /// <inheritdoc />
    public async Task<RealtimeTicket?> RedeemAsync(string ticket, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (string.IsNullOrWhiteSpace(ticket) || ticket.Length > 128) return null;
        var stored = await _database.StringGetDeleteAsync(Key(ticket));
        return stored.HasValue
            ? JsonSerializer.Deserialize<RealtimeTicket>(stored.ToString(), RealtimeChannels.JsonOptions)
            : null;
    }

    /// <summary>В Redis хранится только хеш: утечка ключей не раскрывает билеты.</summary>
    private static string Key(string ticket) =>
        $"realtime:ticket:{Convert.ToHexString(SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(ticket)))}";
}
