using System.Text.Json;

namespace SkladKomforta.Application.Catalog;

/// <summary>Настроенное поле карточки одной категории.</summary>
public sealed record CatalogFieldSummary(
    string Code,
    string Label,
    string FieldType,
    bool IsVisible,
    bool IsRequired,
    int SortOrder,
    string? DictionaryCode);

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

/// <summary>Полная конфигурация, необходимая клиенту для построения каталога.</summary>
public sealed record CatalogConfiguration(
    IReadOnlyList<CatalogCategorySummary> Categories,
    IReadOnlyList<CatalogDictionarySummary> Dictionaries);

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

/// <summary>Фильтры серверной страницы каталога.</summary>
public sealed record CatalogItemQuery(
    Guid? CategoryId,
    Guid? SectionId,
    string? Status,
    string? Search,
    int Page = 1,
    int PageSize = 50);

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
}
