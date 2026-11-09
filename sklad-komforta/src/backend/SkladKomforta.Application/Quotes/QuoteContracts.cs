using System.Text.Json;

namespace SkladKomforta.Application.Quotes;

/// <summary>
/// Строковые значения специализации канбана. NULL намеренно не представлен
/// константой: отсутствие значения означает обычный универсальный канбан.
/// </summary>
public static class WorkflowSpecializationCodes
{
    public const string Quote = "quote";
    public const string Prequote = "prequote";
    public const string QuoteAndPrequote = "quote_and_prequote";
    public const string Order = "order";
}

/// <summary>Вид предложения, хранимого в специализированной карточке канбана.</summary>
public static class QuoteKindCodes
{
    public const string Quote = "quote";
    public const string Prequote = "prequote";
}

/// <summary>Действия создания, которые можно назначить столбцу специализированного канбана.</summary>
public static class WorkflowCreationActionCodes
{
    public const string Quote = "quote";
    public const string Prequote = "prequote";
    public const string Order = "order";
}

/// <summary>Одна позиция варианта с типизированными расчётными и динамическими полями.</summary>
public sealed record QuotePositionDetails(
    Guid Id,
    Guid? CatalogItemId,
    string Name,
    string Marking,
    string Unit,
    decimal Quantity,
    decimal? PurchasePrice,
    decimal BasePrice,
    decimal? ManualPrice,
    decimal? MarkupPercent,
    decimal? DiscountPercent,
    decimal LineTotal,
    bool ExcludeFromTotals,
    IReadOnlyDictionary<string, JsonElement> Values,
    int SortOrder);

/// <summary>Раздел варианта, содержащий позиции и снимок названия из каталога.</summary>
public sealed record QuoteSectionDetails(
    Guid Id,
    Guid? CatalogSectionId,
    string Name,
    decimal? MarkupPercent,
    decimal? DiscountPercent,
    int SortOrder,
    IReadOnlyList<QuotePositionDetails> Positions);

/// <summary>Категория варианта с независимым порядком разделов.</summary>
public sealed record QuoteCategoryDetails(
    Guid Id,
    Guid? CatalogCategoryId,
    string Name,
    int SortOrder,
    IReadOnlyList<QuoteSectionDetails> Sections);

/// <summary>Вариант внутри одного типа предложения.</summary>
public sealed record QuoteVariantDetails(
    Guid Id,
    string Name,
    string? Subtitle,
    decimal? VatRate,
    int SortOrder,
    IReadOnlyList<QuoteCategoryDetails> Categories);

/// <summary>Тип предложения и выбранный клиентом вариант внутри него.</summary>
public sealed record QuoteProposalTypeDetails(
    Guid Id,
    string Name,
    int SortOrder,
    Guid? SelectedVariantId,
    IReadOnlyList<QuoteVariantDetails> Variants,
    bool SelectedByClient = false);

/// <summary>
/// Полная специализированная часть КП/ПКП. Статус и колонка остаются в
/// универсальной карточке канбана и намеренно не дублируются здесь.
/// </summary>
/// <param name="ManagerUserId">Менеджер — создатель карточки; меняется только с правом <c>quotes.manager.change</c>.</param>
/// <param name="SalesHeadUserId">РОП — руководитель менеджера по структуре сотрудников.</param>
/// <param name="CanChangeManager">У текущего пользователя есть право менять менеджера и РОП.</param>
public sealed record QuoteDetails(
    Guid Id,
    Guid WorkflowId,
    Guid CardId,
    string QuoteKind,
    string Title,
    Guid ClientId,
    Guid ExecutorCompanyId,
    Guid? ManagerUserId,
    Guid? SalesHeadUserId,
    string SelectionMode,
    string? AdditionalInformation,
    IReadOnlyList<QuoteProposalTypeDetails> ProposalTypes,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt,
    Guid? ClientSelectedProposalTypeId = null,
    DateTimeOffset? ClientSelectionSubmittedAt = null,
    bool CanChangeManager = false,
    string? CalculationVersion = null,
    string? CurrentCalculationVersion = null);

/// <summary>Разница сохранённого и нового итога одного варианта.</summary>
public sealed record QuoteCalculationChange(
    Guid VariantId, string ProposalTypeName, string VariantName,
    decimal SavedTotal, decimal NewTotal, int ChangedPositions);

/// <summary>Предпросмотр пересчёта без изменения сохранённого предложения.</summary>
public sealed record QuoteCalculationPreview(
    string CurrentCalculationVersion, DateTimeOffset QuoteUpdatedAt,
    IReadOnlyList<QuoteCalculationChange> Changes);

/// <summary>Подтверждение конкретного предпросмотра пересчёта.</summary>
public sealed record ApplyQuoteCalculationRequest(
    string CurrentCalculationVersion, DateTimeOffset QuoteUpdatedAt);

/// <summary>Данные одной позиции при атомарном сохранении предложения.</summary>
public sealed record SaveQuotePositionRequest(
    Guid? Id,
    Guid? CatalogItemId,
    string Name,
    string? Marking,
    string? Unit,
    decimal Quantity,
    decimal? PurchasePrice,
    decimal BasePrice,
    decimal? ManualPrice,
    decimal? MarkupPercent,
    decimal? DiscountPercent,
    bool ExcludeFromTotals,
    IReadOnlyDictionary<string, JsonElement>? Values);

/// <summary>Данные раздела и упорядоченные позиции внутри него.</summary>
public sealed record SaveQuoteSectionRequest(
    Guid? Id,
    Guid? CatalogSectionId,
    string Name,
    decimal? MarkupPercent,
    decimal? DiscountPercent,
    IReadOnlyList<SaveQuotePositionRequest> Positions);

/// <summary>Данные категории и упорядоченные разделы варианта.</summary>
public sealed record SaveQuoteCategoryRequest(
    Guid? Id,
    Guid? CatalogCategoryId,
    string Name,
    IReadOnlyList<SaveQuoteSectionRequest> Sections);

/// <summary>Данные варианта, включая ставку НДС и его наполнение.</summary>
public sealed record SaveQuoteVariantRequest(
    Guid? Id,
    string Name,
    string? Subtitle,
    decimal? VatRate,
    IReadOnlyList<SaveQuoteCategoryRequest> Categories);

/// <summary>
/// Данные типа предложения. Выбранный вариант должен ссылаться на идентификатор
/// варианта из этого же массива; для нового выбранного варианта клиент задаёт UUID.
/// </summary>
public sealed record SaveQuoteProposalTypeRequest(
    Guid? Id,
    string Name,
    Guid? SelectedVariantId,
    IReadOnlyList<SaveQuoteVariantRequest> Variants);

/// <summary>
/// Полная команда создания или замены КП/ПКП, связанного с карточкой канбана.
/// Сервер не принимает готовые суммы строк и всегда пересчитывает их сам.
/// Менеджер и РОП при создании назначаются сервером (создатель и его
/// руководитель), а при сохранении применяются только с правом
/// <c>quotes.manager.change</c>.
/// </summary>
public sealed record SaveQuoteRequest(
    string QuoteKind,
    string Title,
    Guid ClientId,
    Guid ExecutorCompanyId,
    Guid? ManagerUserId,
    Guid? SalesHeadUserId,
    string SelectionMode,
    string? AdditionalInformation,
    IReadOnlyList<SaveQuoteProposalTypeRequest> ProposalTypes);

/// <summary>Атомарная команда создания карточки и связанного с ней КП/ПКП.</summary>
public sealed record CreateQuoteRequest(
    Guid ColumnId,
    SaveQuoteRequest Quote);

/// <summary>Use case-контракт специализированных данных карточки КП/ПКП.</summary>
public interface IQuoteService
{
    Task<QuoteDetails> CreateAsync(
        Guid actorUserId,
        Guid boardId,
        CreateQuoteRequest request,
        CancellationToken cancellationToken);

    Task<QuoteDetails> GetAsync(
        Guid actorUserId,
        Guid boardId,
        Guid cardId,
        CancellationToken cancellationToken);

    Task<QuoteDetails> SaveAsync(
        Guid actorUserId,
        Guid boardId,
        Guid cardId,
        SaveQuoteRequest request,
        CancellationToken cancellationToken);

    /// <summary>Считает разницу по действующим правилам, не меняя документ.</summary>
    Task<QuoteCalculationPreview> PreviewCalculationAsync(
        Guid actorUserId, Guid boardId, Guid cardId, CancellationToken cancellationToken);

    /// <summary>Атомарно применяет подтверждённый пересчёт к сохранённому документу.</summary>
    Task<QuoteDetails> ApplyCalculationAsync(
        Guid actorUserId, Guid boardId, Guid cardId,
        ApplyQuoteCalculationRequest request, CancellationToken cancellationToken);
}

/// <summary>Готовый официальный PDF предложения и безопасное имя файла.</summary>
public sealed record QuotePdfFile(
    string FileName,
    byte[] Content);

/// <summary>
/// Формирует печатную версию сохранённого КП/ПКП. Реализация повторно проверяет
/// доступ пользователя к карточке через <see cref="IQuoteService"/>.
/// </summary>
public interface IQuotePdfService
{
    /// <summary>Формирует PDF сохранённого предложения.</summary>
    /// <param name="proposalTypeId">Тип, открытый в редакторе; см. <see cref="QuotePrintSelection.Apply"/>.</param>
    /// <param name="variantId">
    /// Печатаемый вариант. Если не указаны ни тип, ни вариант, печатается весь документ.
    /// </param>
    Task<QuotePdfFile> GenerateAsync(
        Guid actorUserId,
        Guid boardId,
        Guid cardId,
        Guid? proposalTypeId,
        Guid? variantId,
        CancellationToken cancellationToken);
}
