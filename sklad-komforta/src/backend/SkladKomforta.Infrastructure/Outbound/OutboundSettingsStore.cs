using System.Data.Common;
using System.Text;
using Microsoft.Extensions.Options;
using SkladKomforta.Application.Outbound;
using SkladKomforta.Infrastructure.Configuration;
using SkladKomforta.Infrastructure.Identity;

namespace SkladKomforta.Infrastructure.Outbound;

/// <summary>
/// Шифрует токен бота и пароль почты AES-GCM ключом, выведенным из
/// <c>Security:TotpEncryptionKey</c> с отдельным назначением.
/// </summary>
internal sealed class OutboundSecretProtector(IOptions<SecurityOptions> options)
{
    private const string Purpose = "outbound-delivery";

    private readonly byte[] _key = IdentitySecurity.DeriveKey(
        Convert.FromBase64String(options.Value.TotpEncryptionKey), Purpose);

    public byte[] Protect(string value) => IdentitySecurity.ProtectSecret(Encoding.UTF8.GetBytes(value), _key);

    public string Unprotect(byte[] value) => Encoding.UTF8.GetString(IdentitySecurity.UnprotectSecret(value, _key));
}

/// <summary>Строка <c>outbound_settings</c> с ещё зашифрованными секретами.</summary>
internal sealed record OutboundState(
    byte[]? BotToken,
    string? ChatId,
    bool UsesTopics,
    long? DefaultTopicId,
    string CaptionTemplate,
    string? Address,
    byte[]? Password,
    string? SenderName,
    string? SmtpHost,
    int? SmtpPort,
    string SubjectTemplate,
    string? BodyTemplate,
    string? DefaultRecipient,
    DateTimeOffset UpdatedAt,
    IReadOnlyList<OutboundTelegramTopic> Topics)
{
    /// <summary>Сервер SMTP: по домену адреса или из настроек.</summary>
    public SmtpServer? Smtp =>
        SmtpServerPresets.Detect(Address) ??
        (SmtpHost is not null && SmtpPort is not null ? new SmtpServer(SmtpHost, SmtpPort.Value) : null);

    public bool TelegramReady =>
        BotToken is not null && ChatId is not null &&
        (!UsesTopics || DefaultTopicId is not null || Topics.Count > 0);

    public bool TelegramTopicRequired => UsesTopics && DefaultTopicId is null;

    public bool EmailReady => Address is not null && Password is not null && Smtp is not null;

    public OutboundSettings ToSettings() => new(
        new OutboundTelegramSettings(
            BotToken is not null, ChatId, UsesTopics, DefaultTopicId, Topics, CaptionTemplate),
        new OutboundEmailSettings(
            Address, Password is not null, SenderName, SmtpHost, SmtpPort, SubjectTemplate, BodyTemplate,
            DefaultRecipient, SmtpServerPresets.Detect(Address)?.ToString()),
        UpdatedAt);

    public OutboundChannels ToChannels() => new(
        TelegramReady, TelegramTopicRequired, UsesTopics ? Topics : [], EmailReady, DefaultRecipient is null);
}

/// <summary>Чтение настроек внешней отправки из tenant-схемы.</summary>
internal static class OutboundSettingsStore
{
    public static async Task<OutboundState> ReadAsync(
        DbConnection connection, DbTransaction? transaction, CancellationToken token)
    {
        await using (var ensure = connection.CreateCommand())
        {
            // Строка создаётся миграцией; защищает от её случайного удаления.
            ensure.Transaction = transaction;
            ensure.CommandText = "INSERT INTO outbound_settings (id) VALUES (1) ON CONFLICT DO NOTHING";
            await ensure.ExecuteNonQueryAsync(token);
        }

        var topics = new List<OutboundTelegramTopic>();
        await using (var command = connection.CreateCommand())
        {
            command.Transaction = transaction;
            command.CommandText = "SELECT topic_id, name FROM outbound_telegram_topics ORDER BY sort_order, name";
            await using var reader = await command.ExecuteReaderAsync(token);
            while (await reader.ReadAsync(token))
                topics.Add(new OutboundTelegramTopic(reader.GetInt64(0), reader.GetString(1)));
        }

        await using (var command = connection.CreateCommand())
        {
            command.Transaction = transaction;
            command.CommandText = """
                SELECT telegram_bot_token, telegram_chat_id, telegram_uses_topics, telegram_default_topic_id,
                       telegram_caption_template, email_address, email_password, email_sender_name,
                       email_smtp_host, email_smtp_port, email_subject_template, email_body_template,
                       email_default_recipient, updated_at
                FROM outbound_settings
                WHERE id = 1
                """;
            await using var reader = await command.ExecuteReaderAsync(token);
            if (!await reader.ReadAsync(token))
                throw new InvalidOperationException("Строка outbound_settings не найдена.");
            return new OutboundState(
                reader.IsDBNull(0) ? null : reader.GetFieldValue<byte[]>(0),
                reader.IsDBNull(1) ? null : reader.GetString(1),
                reader.GetBoolean(2),
                reader.IsDBNull(3) ? null : reader.GetInt64(3),
                reader.GetString(4),
                reader.IsDBNull(5) ? null : reader.GetString(5),
                reader.IsDBNull(6) ? null : reader.GetFieldValue<byte[]>(6),
                reader.IsDBNull(7) ? null : reader.GetString(7),
                reader.IsDBNull(8) ? null : reader.GetString(8),
                reader.IsDBNull(9) ? null : reader.GetInt32(9),
                reader.GetString(10),
                reader.IsDBNull(11) ? null : reader.GetString(11),
                reader.IsDBNull(12) ? null : reader.GetString(12),
                new DateTimeOffset(reader.GetFieldValue<DateTime>(13)),
                topics);
        }
    }
}
