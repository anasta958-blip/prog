namespace SkladKomforta.Infrastructure.Configuration;

/// <summary>
/// Настраивает S3-совместимое хранилище. Внутренний URL используется backend,
/// публичный URL входит в подпись и должен быть доступен конечному клиенту.
/// </summary>
public sealed class ObjectStorageOptions
{
    /// <summary>Имя секции конфигурации ASP.NET Core.</summary>
    public const string SectionName = "ObjectStorage";

    /// <summary>Сетевой адрес S3, доступный контейнерам API и Worker.</summary>
    public string ServiceUrl { get; init; } = string.Empty;

    /// <summary>Адрес S3, который будет подписан и возвращён клиентскому приложению.</summary>
    public string PublicUrl { get; init; } = string.Empty;

    /// <summary>AWS-регион или совместимое значение региона MinIO.</summary>
    public string Region { get; init; } = "us-east-1";

    /// <summary>Закрытый bucket приложения.</summary>
    public string Bucket { get; init; } = string.Empty;

    /// <summary>Идентификатор доступа; в production поступает из secret storage.</summary>
    public string AccessKey { get; init; } = string.Empty;

    /// <summary>Секрет доступа; не должен попадать в клиент или журнал.</summary>
    public string SecretKey { get; init; } = string.Empty;

    /// <summary>Включает path-style адреса, необходимые локальному MinIO.</summary>
    public bool ForcePathStyle { get; init; }
}
