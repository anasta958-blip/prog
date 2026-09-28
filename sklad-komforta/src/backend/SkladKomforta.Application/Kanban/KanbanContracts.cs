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

/// <summary>Столбец рабочего канбана в порядке, заданном настройками организации.</summary>
public sealed record KanbanColumnSummary(
    Guid Id,
    string Name,
    string Color,
    int SortOrder,
    IReadOnlyList<string> CreationActions);

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
    IReadOnlyList<KanbanFieldSummary> Fields);

/// <summary>
/// Материализованная конфигурация рабочего пространства. Специальное содержимое
/// КП, ПКП и комплектаций намеренно не входит в универсальный контракт.
/// </summary>
public sealed record KanbanBoard(
    Guid Id,
    string Code,
    string Name,
    IReadOnlyList<KanbanColumnSummary> Columns,
    IReadOnlyList<KanbanTransitionSummary> Transitions,
    IReadOnlyList<KanbanCategorySummary> Categories,
    string? Specialization = null);

/// <summary>Одна универсальная карточка рабочего канбана.</summary>
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
    bool IsArchived = false);

/// <summary>Страница карточек одного столбца и полное количество в нём.</summary>
public sealed record KanbanCardPage(
    IReadOnlyList<KanbanCardSummary> Items,
    int Page,
    int PageSize,
    int Total);

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
    bool Archived = false);

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
