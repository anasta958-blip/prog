using System.Text.Json;

namespace SkladKomforta.Application.Kanban;

/// <summary>Краткое описание одного доступного канбана организации.</summary>
public sealed record KanbanBoardSummary(
    Guid Id,
    string Code,
    string Name,
    int SortOrder,
    int ColumnCount,
    string? Specialization);

/// <summary>Цель переноса из столбца-триггера в другой канбан.</summary>
public sealed record KanbanColumnTransfer(
    Guid BoardId,
    string BoardName,
    Guid ColumnId,
    string ColumnName);

/// <summary>Столбец рабочего канбана в порядке, заданном настройками организации.</summary>
/// <param name="TransferTo">Если задан, попадание карточки в столбец переносит её в другой канбан.</param>
/// <param name="ReorderFrom">Канбан комплектации: с этого столбца новые позиции — дозаказ.</param>
public sealed record KanbanColumnSummary(
    Guid Id,
    string Name,
    string Color,
    int SortOrder,
    IReadOnlyList<string> CreationActions,
    KanbanColumnTransfer? TransferTo = null,
    bool ReorderFrom = false);

/// <summary>Разрешённое направленное перемещение между двумя столбцами.</summary>
public sealed record KanbanTransitionSummary(Guid FromColumnId, Guid ToColumnId);

/// <summary>Значение справочника, разрешённое для динамического поля карточки.</summary>
public sealed record KanbanDictionaryOption(Guid Id, string Value, int SortOrder);

/// <summary>Раздел каталога, доступный для выбранной категории карточки.</summary>
public sealed record KanbanSectionSummary(Guid Id, string Name, int SortOrder);

/// <summary>Метаданные поля карточки в конкретной категории канбана.</summary>
public sealed record KanbanFieldSummary(
    string Code,
    string Label,
    string FieldType,
    bool IsRequired,
    int SortOrder,
    string? DictionaryCode,
    IReadOnlyList<KanbanDictionaryOption> Options);

/// <summary>Категория, разрешённая в канбане, и настроенные поля карточки.</summary>
public sealed record KanbanCategorySummary(
    Guid CategoryId,
    string Name,
    int SortOrder,
    IReadOnlyList<KanbanSectionSummary> Sections,
    IReadOnlyList<KanbanFieldSummary> Fields,
    string? SupplierFilterFieldCode = null);

/// <summary>
/// Материализованная конфигурация рабочего пространства. Специальное содержимое
/// КП, ПКП и комплектаций намеренно не входит в универсальный контракт.
/// </summary>
/// <param name="ObjectTypes">Канбан комплектации: справочник типов объекта.</param>
public sealed record KanbanBoard(
    Guid Id,
    string Code,
    string Name,
    IReadOnlyList<KanbanColumnSummary> Columns,
    IReadOnlyList<KanbanTransitionSummary> Transitions,
    IReadOnlyList<KanbanCategorySummary> Categories,
    string? Specialization = null,
    IReadOnlyList<string>? ObjectTypes = null);

/// <summary>Одна универсальная карточка рабочего канбана.</summary>
/// <param name="UpdatedBy">Кто последним изменил содержимое карточки (не перенос).</param>
/// <param name="MovedBy">Кто последним перенёс карточку в другую колонку.</param>
/// <param name="CreatedByRole">Роли создателя в организации через запятую.</param>
/// <param name="Quote">Сводка КП/ПКП для карточек специализированных канбанов.</param>
/// <param name="Order">Сводка комплектации для карточек канбана комплектации.</param>
/// <param name="LinkedCards">
/// Карточки того же рабочего объекта в других канбанах (КП ↔ комплектация).
/// Заполняется, только пока карточка стоит в столбце-триггере переноса.
/// </param>
public sealed record KanbanCardSummary(
    Guid Id,
    long Number,
    Guid WorkflowId,
    Guid ColumnId,
    Guid? CategoryId,
    Guid? SectionId,
    string Title,
    IReadOnlyDictionary<string, JsonElement> Values,
    Guid? CreatedBy,
    string? CreatedByName,
    DateTimeOffset CreatedAt,
    Guid? UpdatedBy,
    string? UpdatedByName,
    DateTimeOffset UpdatedAt,
    bool IsArchived = false,
    Guid? MovedBy = null,
    string? MovedByName = null,
    DateTimeOffset? MovedAt = null,
    string? CreatedByRole = null,
    string? UpdatedByRole = null,
    string? MovedByRole = null,
    KanbanQuoteSummary? Quote = null,
    KanbanOrderSummary? Order = null,
    IReadOnlyList<KanbanLinkedCard>? LinkedCards = null);

/// <summary>Сводка комплектации для карточки канбана.</summary>
/// <param name="PositionCount">Число позиций.</param>
/// <param name="ReorderCount">Из них дозаказ.</param>
/// <param name="InvoiceCount">Загруженные счета.</param>
/// <param name="SourceQuoteNumber">Номер карточки исходного КП, если комплектация создана переносом.</param>
public sealed record KanbanOrderSummary(
    string? ClientName,
    string? ExecutorName,
    string? ManagerName,
    string? ObjectType,
    int PositionCount,
    int ReorderCount,
    int InvoiceCount,
    long? SourceQuoteNumber);

/// <summary>Карточка того же рабочего объекта в другом канбане.</summary>
public sealed record KanbanLinkedCard(
    Guid BoardId,
    string BoardName,
    string? Specialization,
    Guid CardId,
    long CardNumber,
    string ColumnName);

/// <summary>
/// Сводка предложения для карточки канбана: стороны, выбор и просмотры ссылки.
/// </summary>
/// <param name="QuoteKind"><c>quote</c> или <c>prequote</c>.</param>
/// <param name="ExecutorName">Юридическое название исполнителя (иначе краткое).</param>
/// <param name="SelectionMode"><c>variant</c> или <c>proposal_type</c>.</param>
/// <param name="Selections">Выбранные варианты либо выбранный тип целиком; пусто — ничего не выбрано.</param>
/// <param name="LinkViews">Сколько раз клиент входил по ссылкам этого предложения.</param>
/// <param name="LastViewedAt">Последний вход клиента по ссылке.</param>
public sealed record KanbanQuoteSummary(
    string QuoteKind,
    string? ClientName,
    string? ExecutorName,
    string SelectionMode,
    IReadOnlyList<KanbanQuoteSelection> Selections,
    int LinkViews,
    DateTimeOffset? LastViewedAt);

/// <summary>
/// Выбранное в предложении: вариант типа (<paramref name="VariantName"/> задан)
/// либо тип целиком. Сумма — итог для клиента с НДС.
/// </summary>
public sealed record KanbanQuoteSelection(
    string ProposalTypeName,
    string? VariantName,
    decimal Total);

/// <summary>Страница карточек одного столбца и полное количество в нём.</summary>
/// <param name="SelectedTotal">
/// Сумма выбранных вариантов и типов (с НДС) по всем карточкам столбца с учётом
/// фильтров, а не только текущей страницы; <see langword="null" />, если в столбце нет КП/ПКП.
/// </param>
public sealed record KanbanCardPage(
    IReadOnlyList<KanbanCardSummary> Items,
    int Page,
    int PageSize,
    int Total,
    decimal? SelectedTotal = null);

/// <summary>Автор карточек, доступный текущему пользователю для фильтрации.</summary>
public sealed record KanbanCardAuthorSummary(
    Guid UserId,
    string DisplayName,
    bool IsCurrentUser);

/// <summary>Фильтры серверной страницы карточек.</summary>
public sealed record KanbanCardQuery(
    Guid ColumnId,
    int Page = 1,
    int PageSize = 20,
    Guid? AuthorUserId = null,
    bool IncludeOwn = true,
    bool Archived = false,
    string? Search = null);

public sealed record ArchiveKanbanCardRequest(bool Archived);

/// <summary>Данные создания или полной замены универсальной карточки.</summary>
public sealed record SaveKanbanCardRequest(
    Guid ColumnId,
    Guid CategoryId,
    Guid? SectionId,
    string Title,
    IReadOnlyDictionary<string, JsonElement>? Values);

/// <summary>
/// Отдельная команда перемещения карточки. Индекс задаётся относительно полного
/// списка целевого столбца, а не только открытой страницы.
/// </summary>
public sealed record MoveKanbanCardRequest(Guid TargetColumnId, int TargetIndex);

/// <summary>Читает настроенные канбаны текущей tenant-схемы.</summary>
public interface IKanbanService
{
    Task<IReadOnlyList<KanbanBoardSummary>> GetBoardsAsync(CancellationToken cancellationToken);
    Task<IReadOnlyList<KanbanCardAuthorSummary>> GetCardAuthorsAsync(Guid actorUserId, CancellationToken cancellationToken);
    Task<KanbanBoard> GetBoardAsync(Guid boardId, CancellationToken cancellationToken);
    Task<KanbanCardPage> GetCardsAsync(Guid actorUserId, Guid boardId, KanbanCardQuery query, CancellationToken cancellationToken);
    Task<KanbanCardSummary> GetCardAsync(Guid actorUserId, Guid boardId, Guid cardId, CancellationToken cancellationToken);
    Task<KanbanCardSummary> CreateCardAsync(Guid actorUserId, Guid boardId, SaveKanbanCardRequest request, CancellationToken cancellationToken);
    Task<KanbanCardSummary> UpdateCardAsync(Guid actorUserId, Guid boardId, Guid cardId, SaveKanbanCardRequest request, CancellationToken cancellationToken);
    Task<KanbanCardSummary> MoveCardAsync(Guid actorUserId, Guid boardId, Guid cardId, MoveKanbanCardRequest request, CancellationToken cancellationToken);
    Task DeleteCardAsync(Guid actorUserId, Guid boardId, Guid cardId, CancellationToken cancellationToken);
    Task<KanbanCardSummary> SetArchivedAsync(Guid actorUserId, Guid boardId, Guid cardId, bool archived, CancellationToken cancellationToken);
}
