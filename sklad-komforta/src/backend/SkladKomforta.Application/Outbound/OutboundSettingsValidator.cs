using System.Net.Mail;
using System.Text.RegularExpressions;
using SkladKomforta.Application.Identity;

namespace SkladKomforta.Application.Outbound;

/// <summary>Нормализованные настройки после проверки запроса.</summary>
public sealed record NormalizedOutboundSettings(
    string? BotToken,
    bool ClearBotToken,
    string? ChatId,
    bool UsesTopics,
    long? DefaultTopicId,
    IReadOnlyList<OutboundTelegramTopic> Topics,
    string CaptionTemplate,
    string? Address,
    string? Password,
    bool ClearPassword,
    string? SenderName,
    string? SmtpHost,
    int? SmtpPort,
    string SubjectTemplate,
    string? BodyTemplate,
    string? DefaultRecipient);

/// <summary>Проверка настроек внешней отправки до записи в базу.</summary>
public static partial class OutboundSettingsValidator
{
    /// <summary>Порты SMTP, к которым сервер разрешает подключаться.</summary>
    public static readonly IReadOnlySet<int> AllowedSmtpPorts = new HashSet<int> { 25, 465, 587, 2525 };

    private const int MaxTopics = 100;

    /// <summary>Проверяет и нормализует запрос; ошибка — 400 с понятным текстом.</summary>
    public static NormalizedOutboundSettings Validate(SaveOutboundSettingsRequest request)
    {
        var telegram = request.Telegram ?? throw Invalid("Не переданы настройки Telegram.");
        var email = request.Email ?? throw Invalid("Не переданы настройки почты.");

        var token = Trim(telegram.BotToken);
        if (token is not null && !BotTokenPattern().IsMatch(token))
            throw Invalid("Токен бота имеет неверный формат. Скопируйте его из @BotFather целиком.");

        var chatId = Trim(telegram.ChatId);
        if (chatId is not null && !long.TryParse(chatId, out _) && !ChatUsernamePattern().IsMatch(chatId))
            throw Invalid("ID группы — число (например, -1001234567890) или @имя группы.");

        var topics = (telegram.Topics ?? [])
            .Select(topic => new OutboundTelegramTopic(topic.TopicId, (topic.Name ?? string.Empty).Trim()))
            .ToList();
        if (topics.Count > MaxTopics) throw Invalid($"Топиков может быть не больше {MaxTopics}.");
        if (topics.Any(topic => topic.TopicId <= 0))
            throw Invalid("ID топика — положительное число.");
        if (topics.Any(topic => topic.Name.Length is 0 or > 120))
            throw Invalid("Укажите название каждого топика (до 120 символов).");
        if (topics.Select(topic => topic.TopicId).Distinct().Count() != topics.Count)
            throw Invalid("ID топиков в справочнике повторяются.");
        if (telegram.DefaultTopicId is <= 0)
            throw Invalid("ID топика по умолчанию — положительное число.");

        var caption = telegram.CaptionTemplate?.Trim() ?? OutboundTemplate.DefaultTemplate;
        if (caption.Length > 1024) throw Invalid("Подпись в Telegram — не длиннее 1024 символов.");

        var address = Trim(email.Address);
        if (address is not null && !IsEmail(address))
            throw Invalid("Адрес почты указан неверно.");
        var recipient = Trim(email.DefaultRecipient);
        if (recipient is not null && !IsEmail(recipient))
            throw Invalid("Адрес получателя по умолчанию указан неверно.");

        var senderName = Trim(email.SenderName);
        if (senderName is { Length: > 200 }) throw Invalid("Имя отправителя — не длиннее 200 символов.");
        if (senderName is not null && senderName.Any(char.IsControl))
            throw Invalid("Имя отправителя содержит недопустимые символы.");

        var password = string.IsNullOrEmpty(email.Password) ? null : email.Password;
        if (password is { Length: > 256 }) throw Invalid("Пароль приложения слишком длинный.");

        string? host = null;
        int? port = null;
        if (address is not null && SmtpServerPresets.Detect(address) is null)
        {
            host = Trim(email.SmtpHost);
            port = email.SmtpPort;
            if (host is null || port is null)
                throw Invalid("Для этой почты укажите сервер SMTP и порт.");
            if (host.Length > 255 || !HostPattern().IsMatch(host))
                throw Invalid("Сервер SMTP указан неверно.");
            if (!AllowedSmtpPorts.Contains(port.Value))
                throw Invalid("Порт SMTP: 465, 587, 25 или 2525.");
        }

        var subject = email.SubjectTemplate?.Trim();
        if (string.IsNullOrEmpty(subject)) subject = OutboundTemplate.DefaultTemplate;
        if (subject.Length > 500) throw Invalid("Тема письма — не длиннее 500 символов.");
        var body = Trim(email.BodyTemplate);
        if (body is { Length: > 10000 }) throw Invalid("Текст письма — не длиннее 10 000 символов.");

        return new NormalizedOutboundSettings(
            token, telegram.ClearBotToken && token is null, chatId, telegram.UsesTopics,
            telegram.DefaultTopicId, topics, caption,
            address, password, email.ClearPassword && password is null, senderName, host, port,
            subject, body, recipient);
    }

    /// <summary>Проверяет адрес получателя, введённый при отправке.</summary>
    public static bool IsEmail(string? value) =>
        value is { Length: <= 320 } &&
        MailAddress.TryCreate(value, out var parsed) &&
        string.Equals(parsed.Address, value, StringComparison.OrdinalIgnoreCase) &&
        parsed.Host.Contains('.', StringComparison.Ordinal);

    private static string? Trim(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    private static IdentityException Invalid(string message) =>
        new(400, "outbound_settings_invalid", message);

    [GeneratedRegex(@"^\d{5,15}:[A-Za-z0-9_-]{30,64}$")]
    private static partial Regex BotTokenPattern();

    [GeneratedRegex("^@[A-Za-z][A-Za-z0-9_]{4,31}$")]
    private static partial Regex ChatUsernamePattern();

    [GeneratedRegex(@"^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$")]
    private static partial Regex HostPattern();
}
