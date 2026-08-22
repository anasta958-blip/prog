namespace SkladKomforta.Application.Abstractions.Files;

/// <summary>Проверенные метаданные закрытого объекта после прямой загрузки.</summary>
public sealed record StoredObjectMetadata(long ByteSize, string ContentType);

/// <summary>
/// Абстрагирует закрытое S3-совместимое хранилище. Клиент получает только
/// короткоживущие подписанные ссылки после отдельной проверки прав в use case.
/// </summary>
public interface IObjectStorage
{
    /// <summary>Создаёт временный URL для загрузки объекта заданного MIME-типа.</summary>
    Task<string> CreateUploadUrlAsync(
        string objectKey,
        string contentType,
        TimeSpan lifetime,
        CancellationToken cancellationToken = default);

    /// <summary>Создаёт временный URL для чтения непубличного объекта.</summary>
    Task<string> CreateDownloadUrlAsync(
        string objectKey,
        TimeSpan lifetime,
        CancellationToken cancellationToken = default);

    /// <summary>Читает размер и MIME объекта перед подтверждением загрузки.</summary>
    Task<StoredObjectMetadata?> GetMetadataAsync(
        string objectKey,
        CancellationToken cancellationToken = default);

    /// <summary>Физически удаляет объект после завершения политики мягкого удаления.</summary>
    Task DeleteAsync(string objectKey, CancellationToken cancellationToken = default);
}
