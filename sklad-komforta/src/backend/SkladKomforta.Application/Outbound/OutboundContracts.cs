namespace SkladKomforta.Application.Outbound;

/// <summary>Способ внешней отправки документа.</summary>
public static class OutboundChannel
{
    /// <summary>Telegram-группа (при необходимости — её топик).</summary>
    public const string Telegram = "telegram";

    /// <summary>Письмо через SMTP почтового ящика организации.</summary>
    public const string Email = "email";
}

/// <summary>Топик Telegram-группы из справочника настроек.</summary>
/// <param name="TopicId">Идентификатор топика (<c>message_thread_id</c>).</param>
/// <param name="Name">Понятное название для выбора при отправке.</param>
public sealed record OutboundTelegramTopic(long TopicId, string Name);

/// <summary>Настройки Telegram без секретов.</summary>
/// <param name="HasBotToken">Токен бота сохранён; сам токен клиенту не отдаётся.</param>
/// <param name="ChatId">Идентификатор группы (<c>-100…</c>) или <c>@имя</c>.</param>
/// <param name="UsesTopics">Группа с топиками.</param>
/// <param name="DefaultTopicId">Топик по умолчанию; при нём отправка идёт всегда в него.</param>
/// <param name="Topics">Справочник топиков для выбора при отправке.</param>
/// <param name="CaptionTemplate">Шаблон подписи к файлу; пустой — файл без подписи.</param>
public sealed record OutboundTelegramSettings(
    bool HasBotToken,
    string? ChatId,
    bool UsesTopics,
    long? DefaultTopicId,
    IReadOnlyList<OutboundTelegramTopic> Topics,
    string CaptionTemplate);

/// <summary>Настройки почты без пароля.</summary>
/// <param name="Address">Адрес, с которого отправляются письма (он же логин SMTP).</param>
/// <param name="HasPassword">Пароль приложения сохранён; сам пароль клиенту не отдаётся.</param>
/// <param name="SenderName">Имя отправителя («от кого»).</param>
/// <param name="SmtpHost">Сервер SMTP; для Gmail, Яндекса и Mail.ru не нужен.</param>
/// <param name="SmtpPort">Порт SMTP; для Gmail, Яндекса и Mail.ru не нужен.</param>
/// <param name="SubjectTemplate">Шаблон темы письма.</param>
/// <param name="BodyTemplate">Необязательный шаблон текста письма.</param>
/// <param name="DefaultRecipient">Получатель по умолчанию; без него адрес вводят при отправке.</param>
/// <param name="DetectedSmtpServer">Сервер, определённый по домену адреса, например <c>smtp.gmail.com:465</c>.</param>
public sealed record OutboundEmailSettings(
    string? Address,
    bool HasPassword,
    string? SenderName,
    string? SmtpHost,
    int? SmtpPort,
    string SubjectTemplate,
    string? BodyTemplate,
    string? DefaultRecipient,
    string? DetectedSmtpServer);

/// <summary>Настройки внешней отправки организации.</summary>
public sealed record OutboundSettings(
    OutboundTelegramSettings Telegram,
    OutboundEmailSettings Email,
    DateTimeOffset UpdatedAt);

/// <summary>Изменение настроек Telegram.</summary>
/// <param name="BotToken">Новый токен; пустой — оставить сохранённый.</param>
/// <param name="ClearBotToken">Удалить сохранённый токен.</param>
public sealed record SaveOutboundTelegramRequest(
    string? BotToken,
    bool ClearBotToken,
    string? ChatId,
    bool UsesTopics,
    long? DefaultTopicId,
    IReadOnlyList<OutboundTelegramTopic>? Topics,
    string? CaptionTemplate);

/// <summary>Изменение настроек почты.</summary>
/// <param name="Password">Новый пароль приложения; пустой — оставить сохранённый.</param>
/// <param name="ClearPassword">Удалить сохранённый пароль.</param>
public sealed record SaveOutboundEmailRequest(
    string? Address,
    string? Password,
    bool ClearPassword,
    string? SenderName,
    string? SmtpHost,
    int? SmtpPort,
    string? SubjectTemplate,
    string? BodyTemplate,
    string? DefaultRecipient);

/// <summary>Полная замена настроек внешней отправки.</summary>
public sealed record SaveOutboundSettingsRequest(
    SaveOutboundTelegramRequest Telegram,
    SaveOutboundEmailRequest Email);

/// <summary>
/// Готовность способов отправки для кнопок в редакторах и меню карточки.
/// </summary>
/// <param name="TelegramReady">Telegram настроен и в него можно отправлять.</param>
/// <param name="TelegramTopicRequired">Топик по умолчанию не задан — его выбирают из <paramref name="Topics"/>.</param>
/// <param name="EmailReady">Почта настроена.</param>
/// <param name="EmailRecipientRequired">Получатель по умолчанию не задан — адрес вводят при отправке.</param>
public sealed record OutboundChannels(
    bool TelegramReady,
    bool TelegramTopicRequired,
    IReadOnlyList<OutboundTelegramTopic> Topics,
    bool EmailReady,
    bool EmailRecipientRequired);

/// <summary>Отправка PDF карточки КП, ПКП или комплектации.</summary>
/// <param name="Channel"><see cref="OutboundChannel.Telegram"/> или <see cref="OutboundChannel.Email"/>.</param>
/// <param name="TopicId">Топик из справочника; учитывается, только если топик по умолчанию не задан.</param>
/// <param name="Recipient">Адрес получателя; учитывается, только если получатель по умолчанию не задан.</param>
/// <param name="ProposalTypeId">Для КП/ПКП — тип, как при печати.</param>
/// <param name="VariantId">Для КП/ПКП — вариант, как при печати.</param>
/// <param name="ClientDate">Дата у пользователя для имени файла и <c>{дата}</c>; без неё — дата сервера (UTC).</param>
public sealed record SendDocumentRequest(
    string Channel,
    long? TopicId = null,
    string? Recipient = null,
    Guid? ProposalTypeId = null,
    Guid? VariantId = null,
    DateOnly? ClientDate = null);

/// <summary>Результат отправки.</summary>
/// <param name="Destination">Куда ушёл документ: адрес или название топика/группы.</param>
public sealed record SendDocumentResult(string Channel, string Destination, string FileName);

/// <summary>Настройки внешней отправки: чтение, сохранение и проверка.</summary>
public interface IOutboundSettingsService
{
    /// <summary>Настройки без секретов.</summary>
    Task<OutboundSettings> GetAsync(CancellationToken cancellationToken);

    /// <summary>Проверяет и сохраняет настройки; секреты шифруются.</summary>
    Task<OutboundSettings> SaveAsync(Guid actorUserId, SaveOutboundSettingsRequest request, CancellationToken cancellationToken);

    /// <summary>
    /// Отправляет тестовое сообщение сохранённым способом: в Telegram — в топик
    /// по умолчанию или группу, на почту — получателю по умолчанию или себе.
    /// </summary>
    /// <returns>Куда ушло сообщение.</returns>
    Task<string> TestAsync(string channel, CancellationToken cancellationToken);

    /// <summary>Готовность способов отправки для интерфейса.</summary>
    Task<OutboundChannels> GetChannelsAsync(CancellationToken cancellationToken);
}

/// <summary>Отправка PDF документа карточки во внешний канал.</summary>
public interface IDocumentDeliveryService
{
    /// <summary>
    /// Формирует PDF так же, как печать, и отправляет его. Пользователь должен
    /// иметь право просмотра документа (<c>quotes.view</c> или <c>orders.view</c>).
    /// </summary>
    Task<SendDocumentResult> SendAsync(
        Guid actorUserId,
        Guid boardId,
        Guid cardId,
        SendDocumentRequest request,
        CancellationToken cancellationToken);
}
