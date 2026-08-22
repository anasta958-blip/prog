using Amazon;
using Amazon.Runtime;
using Amazon.S3;
using Amazon.S3.Model;
using Microsoft.Extensions.Options;
using SkladKomforta.Application.Abstractions.Files;
using SkladKomforta.Infrastructure.Configuration;

namespace SkladKomforta.Infrastructure.Files;

/// <summary>
/// Реализует закрытое объектное хранилище через S3 API. Отдельный signer нужен,
/// потому что host является частью SigV4: внутренний container-host нельзя просто
/// заменить на публичный адрес после создания подписи.
/// </summary>
internal sealed class S3ObjectStorage : IObjectStorage, IDisposable
{
    private readonly IAmazonS3 _client;
    private readonly ObjectStorageOptions _options;
    private readonly AmazonS3Client _presignClient;

    /// <summary>Создаёт storage adapter и отдельный клиент только для подписания URL.</summary>
    public S3ObjectStorage(
        IAmazonS3 client,
        IOptions<ObjectStorageOptions> options)
    {
        _client = client;
        _options = options.Value;
        _presignClient = CreatePresignClient(_options);
    }

    /// <inheritdoc />
    public Task<string> CreateUploadUrlAsync(
        string objectKey,
        string contentType,
        TimeSpan lifetime,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return _presignClient.GetPreSignedURLAsync(new GetPreSignedUrlRequest
        {
            BucketName = _options.Bucket,
            Key = NormalizeObjectKey(objectKey),
            Verb = HttpVerb.PUT,
            Protocol = ResolvePresignedProtocol(_options),
            ContentType = contentType,
            Expires = DateTime.UtcNow.Add(lifetime),
        });
    }

    /// <inheritdoc />
    public Task<string> CreateDownloadUrlAsync(
        string objectKey,
        TimeSpan lifetime,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return _presignClient.GetPreSignedURLAsync(new GetPreSignedUrlRequest
        {
            BucketName = _options.Bucket,
            Key = NormalizeObjectKey(objectKey),
            Verb = HttpVerb.GET,
            Protocol = ResolvePresignedProtocol(_options),
            Expires = DateTime.UtcNow.Add(lifetime),
        });
    }

    /// <inheritdoc />
    public async Task<StoredObjectMetadata?> GetMetadataAsync(
        string objectKey,
        CancellationToken cancellationToken = default)
    {
        try
        {
            var response = await _client.GetObjectMetadataAsync(
                _options.Bucket,
                NormalizeObjectKey(objectKey),
                cancellationToken);
            return new StoredObjectMetadata(response.ContentLength, response.Headers.ContentType ?? string.Empty);
        }
        catch (AmazonS3Exception exception) when (exception.StatusCode == System.Net.HttpStatusCode.NotFound)
        {
            return null;
        }
    }

    /// <inheritdoc />
    public async Task DeleteAsync(string objectKey, CancellationToken cancellationToken = default) =>
        await _client.DeleteObjectAsync(
            _options.Bucket,
            NormalizeObjectKey(objectKey),
            cancellationToken);

    /// <summary>Освобождает созданный внутри adapter-а signer client.</summary>
    public void Dispose() => _presignClient.Dispose();

    /// <summary>Создаёт signer с публичным endpoint, но теми же ключами и регионом.</summary>
    private static AmazonS3Client CreatePresignClient(ObjectStorageOptions options)
    {
        var serviceUrl = string.IsNullOrWhiteSpace(options.PublicUrl)
            ? options.ServiceUrl
            : options.PublicUrl;
        var config = new AmazonS3Config
        {
            ForcePathStyle = options.ForcePathStyle,
            RegionEndpoint = RegionEndpoint.GetBySystemName(options.Region),
        };

        if (!string.IsNullOrWhiteSpace(serviceUrl))
        {
            config.ServiceURL = serviceUrl;
            config.AuthenticationRegion = options.Region;
        }

        return new AmazonS3Client(
            new BasicAWSCredentials(options.AccessKey, options.SecretKey),
            config);
    }

    /// <summary>
    /// Сохраняет протокол публичного endpoint-а в подписанной ссылке. AWS SDK
    /// иначе использует HTTPS по умолчанию даже для локального HTTP MinIO.
    /// </summary>
    private static Protocol ResolvePresignedProtocol(ObjectStorageOptions options)
    {
        var serviceUrl = string.IsNullOrWhiteSpace(options.PublicUrl)
            ? options.ServiceUrl
            : options.PublicUrl;
        return Uri.TryCreate(serviceUrl, UriKind.Absolute, out var uri) &&
               uri.Scheme.Equals(Uri.UriSchemeHttp, StringComparison.OrdinalIgnoreCase)
            ? Protocol.HTTP
            : Protocol.HTTPS;
    }

    /// <summary>Нормализует разделители и отклоняет пустые ключи и обход каталога.</summary>
    private static string NormalizeObjectKey(string objectKey)
    {
        var normalized = objectKey.Replace('\\', '/').Trim('/');
        if (string.IsNullOrWhiteSpace(normalized) || normalized.Contains("..", StringComparison.Ordinal))
        {
            throw new ArgumentException("Недопустимый ключ объекта.", nameof(objectKey));
        }

        return normalized;
    }
}
