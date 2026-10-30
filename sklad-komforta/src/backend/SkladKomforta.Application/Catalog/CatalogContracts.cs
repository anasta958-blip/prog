using System.Text.Json;
using SkladKomforta.Application.Onboarding;

namespace SkladKomforta.Application.Catalog;

/// <summary>Настроенное поле карточки одной категории.</summary>
public sealed record CatalogFieldSummary(
    string Code,
    string Label,
    string FieldType,
    bool IsVisible,
    bool IsRequired,
    int SortOrder,
    string? DictionaryCode,
    string? TotalMode = null);

/// <summary>Группа внутри раздела каталога.</summary>
public sealed record CatalogGroupSummary(Guid Id, string Name, int SortOrder);

/// <summary>Раздел категории вместе с доступными группами.</summary>
public sealed record CatalogSectionSummary(
    Guid Id,
    string Name,
    int SortOrder,
    IReadOnlyList<CatalogGroupSummary> Groups);

/// <summary>Категория и её материализованная onboarding-конфигурация.</summary>
public sealed record CatalogCategorySummary(
    Guid Id,
    string ClientId,
    string Name,
    int SortOrder,
    IReadOnlyList<CatalogFieldSummary> Fields,
    IReadOnlyList<CatalogSectionSummary> Sections);

/// <summary>Значение пользовательского справочника.</summary>
public sealed record CatalogDictionaryItemSummary(Guid Id, string Value, int SortOrder);

/// <summary>Справочник tenant-а, доступный полям типа dictionary.</summary>
public sealed record CatalogDictionarySummary(
    Guid Id,
    string Code,
    string Name,
    int SortOrder,
    IReadOnlyList<CatalogDictionaryItemSummary> Items);

/// <summary>Разрешённое направление связи между двумя категориями.</summary>
public sealed record CatalogDependencySummary(
    Guid Id,
    string ClientId,
    Guid SourceCategoryId,
    Guid TargetCategoryId,
    string TargetFieldCode,
    int SortOrder);

/// <summary>Полная конфигурация, необходимая клиенту для построения каталога.</summary>
public sealed record CatalogConfiguration(
    IReadOnlyList<CatalogCategorySummary> Categories,
    IReadOnlyList<CatalogDictionarySummary> Dictionaries,
    IReadOnlyList<CatalogDependencySummary> Dependencies,
    IReadOnlyList<CalculationRuleDraft> Rules,
    IReadOnlyList<MoneyPipelineDraft> MoneyPipelines);

/// <summary>Карточка каталога с системными и настроенными значениями.</summary>
public sealed record CatalogItemSummary(
    Guid Id,
    Guid CategoryId,
    Guid? SectionId,
    Guid? GroupId,
    string Name,
    string Marking,
    string Status,
    IReadOnlyDictionary<string, JsonElement> Values,
    Guid? CreatedBy,
    DateTimeOffset CreatedAt,
    Guid? UpdatedBy,
    DateTimeOffset UpdatedAt,
    string? ThumbnailUrl = null);

/// <summary>Одна страница каталога и общее количество найденных карточек.</summary>
public sealed record CatalogItemPage(
    IReadOnlyList<CatalogItemSummary> Items,
    int Page,
    int PageSize,
    int Total);

/// <summary>Готовое изображение карточки с временной ссылкой для просмотра.</summary>
public sealed record CatalogItemImageSummary(
    Guid Id,
    string FileName,
    string ContentType,
    long ByteSize,
    int SortOrder,
    string DownloadUrl);

/// <summary>Проверяемые метаданные файла до выдачи ссылки на загрузку.</summary>
public sealed record BeginCatalogImageUploadRequest(
    string FileName,
    string ContentType,
    long ByteSize);

/// <summary>Короткоживущая ссылка для прямой загрузки изображения в S3.</summary>
public sealed record CatalogImageUploadTicket(
    Guid ImageId,
    string UploadUrl,
    DateTimeOffset ExpiresAt);

/// <summary>Карточка, которую можно выбрать как зависимую позицию.</summary>
public sealed record CatalogRelationCandidate(
    Guid Id,
    string Name,
    string Marking,
    string Status);

/// <summary>Сохранённая зависимая позиция целевой карточки.</summary>
public sealed record CatalogItemRelationSummary(
    Guid DependencyId,
    Guid SourceItemId,
    string SourceName,
    string SourceMarking,
    int SortOrder,
    Guid? SourceCategoryId = null,
    Guid? SourceSectionId = null,
    Guid? SourceGroupId = null,
    IReadOnlyDictionary<string, JsonElement>? SourceValues = null);

/// <summary>Одна строка полной замены зависимых позиций карточки.</summary>
public sealed record SaveCatalogItemRelationRequest(
    Guid DependencyId,
    Guid SourceItemId);

/// <summary>Готовый XLSX-файл, возвращаемый HTTP endpoint-ом без промежуточного файла на сервере.</summary>
public sealed record CatalogSpreadsheetFile(
    string FileName,
    string ContentType,
    byte[] Content);

/// <summary>Результат атомарного импорта проверенной книги каталога.</summary>
public sealed record CatalogImportResult(
    int TotalRows,
    int Created,
    int Updated);

/// <summary>Одна строка XLSX вместе с координатой для понятной ошибки импорта.</summary>
public sealed record CatalogImportRow(
    string SheetName,
    int RowNumber,
    Guid? ItemId,
    SaveCatalogItemRequest Item,
    IReadOnlyList<SaveCatalogItemRelationRequest> Relations);

/// <summary>Доступные массовые изменения выбранных карточек.</summary>
public sealed record CatalogBulkRequest(
    IReadOnlyList<Guid> ItemIds,
    string Action,
    string? Status = null,
    Guid? DependencyId = null,
    Guid? SourceItemId = null);

/// <summary>Количество запрошенных и фактически изменённых карточек.</summary>
public sealed record CatalogBulkResult(int Requested, int Affected);

/// <summary>Фильтры серверной страницы каталога.</summary>
public sealed record CatalogItemQuery(
    Guid? CategoryId,
    Guid? SectionId,
    string? Status,
    string? Search,
    int Page = 1,
    int PageSize = 50,
    Guid? GroupId = null,
    string? Sort = null);

/// <summary>Данные создания или полной замены редактируемой карточки.</summary>
public sealed record SaveCatalogItemRequest(
    Guid CategoryId,
    Guid? SectionId,
    Guid? GroupId,
    string Name,
    string? Marking,
    string Status,
    IReadOnlyDictionary<string, JsonElement>? Values);

/// <summary>Use case-контракт каталога в пределах уже проверенного tenant-а.</summary>
public interface ICatalogService
{
    Task<CatalogConfiguration> GetConfigurationAsync(CancellationToken cancellationToken);
    Task<CatalogItemPage> GetItemsAsync(CatalogItemQuery query, CancellationToken cancellationToken);
    Task<CatalogItemSummary> GetItemAsync(Guid itemId, CancellationToken cancellationToken);
    Task<CatalogItemSummary> CreateItemAsync(Guid actorUserId, SaveCatalogItemRequest request, CancellationToken cancellationToken);
    Task<CatalogItemSummary> UpdateItemAsync(Guid actorUserId, Guid itemId, SaveCatalogItemRequest request, CancellationToken cancellationToken);
    Task DeleteItemAsync(Guid actorUserId, Guid itemId, CancellationToken cancellationToken);
    Task<IReadOnlyList<CatalogItemImageSummary>> GetImagesAsync(Guid itemId, CancellationToken cancellationToken);
    Task<CatalogImageUploadTicket> BeginImageUploadAsync(Guid actorUserId, Guid itemId, BeginCatalogImageUploadRequest request, CancellationToken cancellationToken);
    Task<CatalogItemImageSummary> ConfirmImageUploadAsync(Guid actorUserId, Guid itemId, Guid imageId, CancellationToken cancellationToken);
    Task DeleteImageAsync(Guid actorUserId, Guid itemId, Guid imageId, CancellationToken cancellationToken);
    Task<IReadOnlyList<CatalogItemRelationSummary>> GetRelationsAsync(Guid itemId, CancellationToken cancellationToken);
    Task<IReadOnlyList<CatalogRelationCandidate>> SearchRelationCandidatesAsync(Guid dependencyId, string? search, int limit, CancellationToken cancellationToken);
    Task<IReadOnlyList<CatalogItemRelationSummary>> ReplaceRelationsAsync(Guid actorUserId, Guid itemId, IReadOnlyList<SaveCatalogItemRelationRequest> relations, CancellationToken cancellationToken);
    Task<IReadOnlyList<CatalogItemSummary>> GetItemsForExportAsync(CatalogItemQuery query, CancellationToken cancellationToken);
    Task<IReadOnlyDictionary<Guid, IReadOnlyList<CatalogItemRelationSummary>>> GetRelationsForExportAsync(
        IReadOnlyList<Guid> itemIds,
        CancellationToken cancellationToken);
    Task<CatalogImportResult> ImportItemsAsync(Guid actorUserId, IReadOnlyList<CatalogImportRow> rows, CancellationToken cancellationToken);
    Task<CatalogBulkResult> ApplyBulkAsync(Guid actorUserId, CatalogBulkRequest request, CancellationToken cancellationToken);
}

/// <summary>Преобразует tenant-каталог в пользовательские XLSX-книги и обратно.</summary>
public interface ICatalogSpreadsheetService
{
    Task<CatalogSpreadsheetFile> CreateTemplateAsync(Guid? categoryId, CancellationToken cancellationToken);
    Task<CatalogSpreadsheetFile> ExportAsync(CatalogItemQuery query, CancellationToken cancellationToken);
    Task<CatalogImportResult> ImportAsync(Guid actorUserId, Stream content, CancellationToken cancellationToken);
}
