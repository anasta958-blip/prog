using Amazon.S3;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.Extensions.Options;
using SkladKomforta.Infrastructure.Configuration;

namespace SkladKomforta.Infrastructure.Health;

/// <summary>Проверяет доступность настроенного bucket без чтения пользовательских файлов.</summary>
internal sealed class ObjectStorageHealthCheck(
    IAmazonS3 client,
    IOptions<ObjectStorageOptions> options) : IHealthCheck
{
    /// <inheritdoc />
    public async Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context,
        CancellationToken cancellationToken = default)
    {
        try
        {
            await client.GetBucketLocationAsync(options.Value.Bucket, cancellationToken);
            return HealthCheckResult.Healthy();
        }
        catch (Exception exception)
        {
            return HealthCheckResult.Unhealthy("Object storage is unavailable.", exception);
        }
    }
}
