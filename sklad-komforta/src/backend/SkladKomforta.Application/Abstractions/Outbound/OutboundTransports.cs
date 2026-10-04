namespace SkladKomforta.Application.Abstractions.Outbound;

/// <summary>Файл, прикладываемый к сообщению.</summary>
public sealed record OutboundAttachment(string FileName, string ContentType, byte[] Content);

/// <summary>Сообщение в Telegram-группу через Bot API.</summary>
/// <param name="BotToken">Расшифрованный токен; не логируется.</param>
/// <param name="ChatId">Идентификатор группы или <c>@имя</c>.</param>
/// <param name="TopicId">Топик группы; <c>null</c> — общий чат.</param>
/// <param name="Text">Подпись к файлу или текст сообщения без файла.</param>
/// <param name="Attachment">Файл; без него отправляется только текст.</param>
public sealed record TelegramOutboundMessage(
    string BotToken,
    string ChatId,
    long? TopicId,
    string? Text,
    OutboundAttachment? Attachment);

/// <summary>Отправка в Telegram (в тестах подменяется).</summary>
public interface ITelegramTransport
{
    /// <summary>
    /// Отправляет сообщение. Ошибка Bot API — <c>IdentityException</c> 502 с
    /// понятным текстом (неверный токен, группа или топик не найдены).
    /// </summary>
    Task SendAsync(TelegramOutboundMessage message, CancellationToken cancellationToken);
}

/// <summary>Письмо через SMTP почтового ящика организации.</summary>
/// <param name="Password">Расшифрованный пароль приложения; не логируется.</param>
public sealed record EmailOutboundMessage(
    string SmtpHost,
    int SmtpPort,
    string Address,
    string Password,
    string? SenderName,
    string Recipient,
    string Subject,
    string? Body,
    OutboundAttachment? Attachment);

/// <summary>Отправка письма (в тестах подменяется).</summary>
public interface IEmailTransport
{
    /// <summary>
    /// Отправляет письмо. Ошибка входа или соединения — <c>IdentityException</c>
    /// 502 с понятным текстом.
    /// </summary>
    Task SendAsync(EmailOutboundMessage message, CancellationToken cancellationToken);
}
