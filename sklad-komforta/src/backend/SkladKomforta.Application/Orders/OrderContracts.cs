using System.Text.Json;

namespace SkladKomforta.Application.Orders;

/// <summary>
/// Позиция комплектации. Цен нет: системные поля — наименование, маркировка,
/// единица и количество, остальные настраиваемые поля канбана лежат в
/// <paramref name="Values"/> (код поля → значение), как в КП.
/// </summary>
/// <param name="IsReorder">Дозаказ: позиция добавлена, когда карточка уже стояла в столбце дозаказа или правее.</param>
/// <param name="FromQuote">Строка перенесена из КП и синхронизируется при повторном переносе.</param>
public sealed record OrderPositionDetails(
    Guid Id,
    Guid? CatalogItemId,
    string Name,
    string Marking,
    string Unit,
    decimal Quantity,
    bool IsReorder,
    bool FromQuote,
    IReadOnlyDictionary<string, JsonElement> Values,
    int SortOrder);

/// <summary>Раздел комплектации со снимком названия раздела каталога.</summary>
public sealed record OrderSectionDetails(
    Guid Id,
    Guid? CatalogSectionId,
    string Name,
    int SortOrder,
    IReadOnlyList<OrderPositionDetails> Positions);

/// <summary>Категория комплектации с упорядоченными разделами.</summary>
public sealed record OrderCategoryDetails(
    Guid Id,
    Guid? CatalogCategoryId,
    string Name,
    int SortOrder,
    IReadOnlyList<OrderSectionDetails> Sections);

/// <summary>Исходное КП комплектации, созданной переносом.</summary>
public sealed record OrderSourceQuote(Guid QuoteId, Guid BoardId, Guid CardId, int CardNumber, string Title);

/// <summary>
/// Комплектация карточки канбана. Статус и столбец остаются в карточке.
/// </summary>
/// <param name="Title">Адрес объекта; совпадает с названием карточки.</param>
/// <param name="CanChangeManager">У текущего пользователя есть право менять менеджера и РОП.</param>
/// <param name="CanManageInvoices">У текущего пользователя есть право загружать и удалять счета.</param>
public sealed record OrderDetails(
    Guid Id,
    Guid WorkflowId,
    Guid CardId,
    string Title,
    string? ObjectType,
    Guid ClientId,
    Guid ExecutorCompanyId,
    Guid? ManagerUserId,
    Guid? SalesHeadUserId,
    OrderSourceQuote? SourceQuote,
    IReadOnlyList<OrderCategoryDetails> Categories,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt,
    bool CanChangeManager,
    bool CanManageInvoices);

/// <summary>Позиция при сохранении; новая позиция получает UUID на клиенте или сервере.</summary>
public sealed record SaveOrderPositionRequest(
    Guid? Id,
    Guid? CatalogItemId,
    string Name,
    string? Marking,
    string? Unit,
    decimal Quantity,
    IReadOnlyDictionary<string, JsonElement>? Values);

/// <summary>Раздел при сохранении.</summary>
public sealed record SaveOrderSectionRequest(
    Guid? Id,
    Guid? CatalogSectionId,
    string Name,
    IReadOnlyList<SaveOrderPositionRequest> Positions);

/// <summary>Категория при сохранении.</summary>
public sealed record SaveOrderCategoryRequest(
    Guid? Id,
    Guid? CatalogCategoryId,
    string Name,
    IReadOnlyList<SaveOrderSectionRequest> Sections);

/// <summary>
/// Полная замена комплектации. Менеджер и РОП применяются, только если у
/// пользователя есть право <c>orders.manager.change</c>; иначе остаются прежними.
/// </summary>
public sealed record SaveOrderRequest(
    string Title,
    string? ObjectType,
    Guid ClientId,
    Guid ExecutorCompanyId,
    Guid? ManagerUserId,
    Guid? SalesHeadUserId,
    IReadOnlyList<SaveOrderCategoryRequest> Categories);

/// <summary>Создание карточки комплектации кнопкой «Создать комплектацию».</summary>
public sealed record CreateOrderRequest(Guid ColumnId, SaveOrderRequest Order);

/// <summary>Загруженный PDF-счёт с короткоживущей ссылкой на скачивание.</summary>
public sealed record OrderInvoiceSummary(
    Guid Id,
    string FileName,
    long ByteSize,
    DateTimeOffset UploadedAt,
    string? UploadedByName,
    string DownloadUrl);

/// <summary>Запрос на загрузку счёта: только PDF до 20 МБ.</summary>
public sealed record BeginOrderInvoiceUploadRequest(string FileName, string ContentType, long ByteSize);

/// <summary>Подписанная ссылка для прямой загрузки файла в хранилище.</summary>
public sealed record OrderInvoiceUploadTicket(Guid InvoiceId, string UploadUrl, DateTimeOffset ExpiresAt);

/// <summary>Готовый PDF комплектации.</summary>
public sealed record OrderPdfFile(string FileName, byte[] Content);

/// <summary>Use case-контракт комплектации, связанной с карточкой канбана.</summary>
public interface IOrderService
{
    /// <summary>Создаёт карточку и комплектацию; менеджер — создатель, РОП — его руководитель.</summary>
    Task<OrderDetails> CreateAsync(Guid actorUserId, Guid boardId, CreateOrderRequest request, CancellationToken cancellationToken);

    /// <summary>Читает комплектацию карточки после проверки доступа к карточке.</summary>
    Task<OrderDetails> GetAsync(Guid actorUserId, Guid boardId, Guid cardId, CancellationToken cancellationToken);

    /// <summary>Атомарно заменяет шапку и дерево позиций.</summary>
    Task<OrderDetails> SaveAsync(Guid actorUserId, Guid boardId, Guid cardId, SaveOrderRequest request, CancellationToken cancellationToken);

    /// <summary>Возвращает загруженные счета со ссылками на скачивание.</summary>
    Task<IReadOnlyList<OrderInvoiceSummary>> GetInvoicesAsync(Guid actorUserId, Guid boardId, Guid cardId, CancellationToken cancellationToken);

    /// <summary>Резервирует счёт и выдаёт ссылку для загрузки PDF.</summary>
    Task<OrderInvoiceUploadTicket> BeginInvoiceUploadAsync(
        Guid actorUserId, Guid boardId, Guid cardId, BeginOrderInvoiceUploadRequest request, CancellationToken cancellationToken);

    /// <summary>Проверяет загруженный файл и делает счёт видимым.</summary>
    Task<OrderInvoiceSummary> ConfirmInvoiceUploadAsync(
        Guid actorUserId, Guid boardId, Guid cardId, Guid invoiceId, CancellationToken cancellationToken);

    /// <summary>Удаляет счёт и его файл.</summary>
    Task DeleteInvoiceAsync(Guid actorUserId, Guid boardId, Guid cardId, Guid invoiceId, CancellationToken cancellationToken);
}

/// <summary>Печатная форма комплектации.</summary>
public interface IOrderPdfService
{
    /// <summary>Формирует PDF сохранённой комплектации.</summary>
    Task<OrderPdfFile> GenerateAsync(Guid actorUserId, Guid boardId, Guid cardId, CancellationToken cancellationToken);
}
