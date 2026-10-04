using System.Data.Common;
using SkladKomforta.Application.Abstractions.Outbound;
using SkladKomforta.Application.Abstractions.Persistence;
using SkladKomforta.Application.Abstractions.Tenancy;
using SkladKomforta.Application.Identity;
using SkladKomforta.Application.Outbound;
using static SkladKomforta.Infrastructure.Orders.OrderStore;

namespace SkladKomforta.Infrastructure.Outbound;

/// <summary>
/// Настройки внешней отправки организации. Секреты принимаются только на
/// запись: в ответах — лишь признаки «сохранён».
/// </summary>
internal sealed class PostgresOutboundSettingsService(
    IDatabaseConnectionFactory connectionFactory,
    ITenantContext tenantContext,
    OutboundSecretProtector protector,
    ITelegramTransport telegram,
    IEmailTransport email) : IOutboundSettingsService
{
    /// <inheritdoc />
    public async Task<OutboundSettings> GetAsync(CancellationToken cancellationToken)
    {
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        return (await OutboundSettingsStore.ReadAsync(connection, null, cancellationToken)).ToSettings();
    }

    /// <inheritdoc />
    public async Task<OutboundChannels> GetChannelsAsync(CancellationToken cancellationToken)
    {
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        return (await OutboundSettingsStore.ReadAsync(connection, null, cancellationToken)).ToChannels();
    }

    /// <inheritdoc />
    public async Task<OutboundSettings> SaveAsync(
        Guid actorUserId, SaveOutboundSettingsRequest request, CancellationToken cancellationToken)
    {
        var normalized = OutboundSettingsValidator.Validate(request);
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        var before = await OutboundSettingsStore.ReadAsync(connection, transaction, cancellationToken);

        var token = normalized.BotToken is not null
            ? protector.Protect(normalized.BotToken)
            : normalized.ClearBotToken ? null : before.BotToken;
        // Пароль привязан к адресу: при смене адреса старый пароль не годится.
        var addressChanged = !string.Equals(before.Address, normalized.Address, StringComparison.OrdinalIgnoreCase);
        var password = normalized.Password is not null
            ? protector.Protect(normalized.Password)
            : normalized.ClearPassword || addressChanged ? null : before.Password;

        await ExecuteAsync(connection, transaction, """
            UPDATE outbound_settings
            SET telegram_bot_token = @token,
                telegram_chat_id = @chat_id,
                telegram_uses_topics = @uses_topics,
                telegram_default_topic_id = @default_topic,
                telegram_caption_template = @caption,
                email_address = @address,
                email_password = @password,
                email_sender_name = @sender_name,
                email_smtp_host = @smtp_host,
                email_smtp_port = @smtp_port,
                email_subject_template = @subject,
                email_body_template = @body,
                email_default_recipient = @recipient,
                updated_by = @actor,
                updated_at = now()
            WHERE id = 1
            """, cancellationToken,
            ("token", Db(token)), ("chat_id", Db(normalized.ChatId)), ("uses_topics", normalized.UsesTopics),
            ("default_topic", Db(normalized.DefaultTopicId)), ("caption", normalized.CaptionTemplate),
            ("address", Db(normalized.Address)), ("password", Db(password)),
            ("sender_name", Db(normalized.SenderName)), ("smtp_host", Db(normalized.SmtpHost)),
            ("smtp_port", Db(normalized.SmtpPort)), ("subject", normalized.SubjectTemplate),
            ("body", Db(normalized.BodyTemplate)), ("recipient", Db(normalized.DefaultRecipient)),
            ("actor", actorUserId));

        await ExecuteAsync(connection, transaction, "DELETE FROM outbound_telegram_topics", cancellationToken);
        for (var index = 0; index < normalized.Topics.Count; index++)
        {
            var topic = normalized.Topics[index];
            await ExecuteAsync(connection, transaction, """
                INSERT INTO outbound_telegram_topics (topic_id, name, sort_order)
                VALUES (@topic_id, @name, @sort_order)
                """, cancellationToken,
                ("topic_id", topic.TopicId), ("name", topic.Name), ("sort_order", index));
        }

        var after = await OutboundSettingsStore.ReadAsync(connection, transaction, cancellationToken);
        await WriteAuditAsync(connection, transaction, actorUserId, before, after, cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return after.ToSettings();
    }

    /// <inheritdoc />
    public async Task<string> TestAsync(string channel, CancellationToken cancellationToken)
    {
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        var state = await OutboundSettingsStore.ReadAsync(connection, null, cancellationToken);
        await connection.CloseAsync();
        switch (channel)
        {
            case OutboundChannel.Telegram:
            {
                if (state.BotToken is null || state.ChatId is null)
                    throw NotConfigured("Сохраните токен бота и ID группы, затем проверьте отправку.");
                var topic = state.UsesTopics ? state.DefaultTopicId ?? (state.Topics.Count > 0 ? state.Topics[0].TopicId : null) : null;
                await telegram.SendAsync(new TelegramOutboundMessage(
                    protector.Unprotect(state.BotToken), state.ChatId, topic,
                    "Проверка отправки из «Склад Комфорта»: документы будут приходить сюда.", null), cancellationToken);
                return TelegramDestination(state, topic);
            }
            case OutboundChannel.Email:
            {
                if (!state.EmailReady)
                    throw NotConfigured("Сохраните адрес почты и пароль приложения, затем проверьте отправку.");
                var recipient = state.DefaultRecipient ?? state.Address!;
                var smtp = state.Smtp!;
                await email.SendAsync(new EmailOutboundMessage(
                    smtp.Host, smtp.Port, state.Address!, protector.Unprotect(state.Password!), state.SenderName,
                    recipient, "Проверка отправки «Склад Комфорта»",
                    "Это тестовое письмо: почта для отправки документов настроена верно.", null), cancellationToken);
                return recipient;
            }
            default:
                throw new IdentityException(400, "outbound_channel_invalid", "Неизвестный способ отправки.");
        }
    }

    /// <summary>Название места в группе для сообщений: топик из справочника или ID.</summary>
    internal static string TelegramDestination(OutboundState state, long? topicId)
    {
        if (topicId is null) return "группа Telegram";
        var topic = state.Topics.FirstOrDefault(item => item.TopicId == topicId);
        return topic is null ? $"топик {topicId}" : $"топик «{topic.Name}»";
    }

    private static IdentityException NotConfigured(string message) =>
        new(409, "outbound_not_configured", message);

    private async Task WriteAuditAsync(
        DbConnection connection, DbTransaction transaction, Guid actorUserId,
        OutboundState before, OutboundState after, CancellationToken token)
    {
        var diff = AuditChanges.Serialize(before.ToSettings(), after.ToSettings());
        // Замена секрета при прочих равных — тоже изменение, но без значений.
        if (diff is null &&
            (!SameSecret(before.BotToken, after.BotToken) || !SameSecret(before.Password, after.Password)))
        {
            diff = AuditChanges.Serialize(
                new { secretsReplaced = false }, new { secretsReplaced = true });
        }
        if (diff is null) return;
        await ExecuteAsync(connection, transaction, """
            INSERT INTO audit_log (actor_user_id, entity_type, entity_id, action, diff)
            VALUES (@actor, 'outbound_settings', @organization_id, 'updated', CAST(@diff AS jsonb))
            """, token,
            ("actor", actorUserId), ("organization_id", tenantContext.OrganizationId), ("diff", diff));
    }

    private static bool SameSecret(byte[]? left, byte[]? right) =>
        left is null ? right is null : right is not null && left.AsSpan().SequenceEqual(right);
}
