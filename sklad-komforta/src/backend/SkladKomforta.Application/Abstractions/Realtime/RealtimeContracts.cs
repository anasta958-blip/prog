namespace SkladKomforta.Application.Abstractions.Realtime;

/// <summary>Темы уведомлений, на которые подписывается клиент.</summary>
public static class RealtimeTopics
{
    /// <summary>Карточки канбанов, КП/ПКП и действия клиента по ссылке.</summary>
    public const string Kanban = "kanban";

    /// <summary>Товары каталога, их изображения и связи.</summary>
    public const string Catalog = "catalog";

    /// <summary>
    /// Пространство «Компания»: настройки и профиль, юридические лица, клиенты,
    /// сотрудники, роли и права. Раздел передаётся в <see cref="RealtimeChange.Section"/>.
    /// </summary>
    public const string Company = "company";

    /// <summary>Проверяет, что тема входит в поддерживаемый набор.</summary>
    public static bool IsKnown(string? topic) => topic is Kanban or Catalog or Company;
}

/// <summary>
/// Сигнал «данные изменились». Не содержит самих данных: клиент перечитывает
/// их обычными защищёнными запросами, поэтому права проверяются как обычно.
/// </summary>
/// <param name="OrganizationId">Организация, пользователям которой адресован сигнал.</param>
/// <param name="Topic">Тема из <see cref="RealtimeTopics"/>.</param>
/// <param name="Kind">
/// Вид изменения: <c>changed</c> — изменились записи; <c>configuration</c> —
/// изменилась структура (канбаны, категории, поля), нужно перечитать её целиком.
/// </param>
/// <param name="BoardId">Канбан, если изменение относится к конкретному канбану.</param>
/// <param name="EntityId">Карточка, товар или запись раздела, если изменение относится к одной записи.</param>
/// <param name="Section">
/// Раздел темы <see cref="RealtimeTopics.Company"/>: <c>configuration</c>, <c>profile</c>,
/// <c>legal_entities</c>, <c>clients</c>, <c>employees</c>, <c>access</c>.
/// </param>
public sealed record RealtimeChange(
    Guid OrganizationId,
    string Topic,
    string Kind,
    Guid? BoardId = null,
    Guid? EntityId = null,
    string? Section = null)
{
    /// <summary>Изменились записи.</summary>
    public const string Changed = "changed";

    /// <summary>Изменилась структура модуля.</summary>
    public const string Configuration = "configuration";
}

/// <summary>
/// Публикует сигналы изменений всем экземплярам API. Ошибка доставки не должна
/// отменять уже сохранённое изменение, поэтому реализация не бросает исключений.
/// </summary>
public interface IRealtimeNotifier
{
    /// <summary>Отправляет сигнал; при недоступности шины только пишет в журнал.</summary>
    Task PublishAsync(RealtimeChange change, CancellationToken cancellationToken = default);
}

/// <summary>Владелец одноразового билета на подключение к потоку уведомлений.</summary>
/// <param name="UserId">Пользователь.</param>
/// <param name="SessionId">Сессия, активность которой перепроверяется во время подключения.</param>
/// <param name="OrganizationId">Организация.</param>
/// <param name="Topic">Разрешённая тема.</param>
public sealed record RealtimeTicket(Guid UserId, Guid SessionId, Guid OrganizationId, string Topic);

/// <summary>
/// Одноразовые короткоживущие билеты для WebSocket: браузер не может передать
/// заголовок Authorization при подключении, а токен доступа в URL попал бы в журналы.
/// </summary>
public interface IRealtimeTicketStore
{
    /// <summary>Выдаёт билет, действующий <paramref name="lifetime"/> и только один раз.</summary>
    Task<string> IssueAsync(RealtimeTicket ticket, TimeSpan lifetime, CancellationToken cancellationToken = default);

    /// <summary>Атомарно погашает билет; повторное или просроченное использование даёт <see langword="null"/>.</summary>
    Task<RealtimeTicket?> RedeemAsync(string ticket, CancellationToken cancellationToken = default);
}
