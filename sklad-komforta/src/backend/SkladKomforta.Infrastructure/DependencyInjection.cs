using Amazon;
using Amazon.Runtime;
using Amazon.S3;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using Npgsql;
using StackExchange.Redis;
using SkladKomforta.Application.Abstractions.Caching;
using SkladKomforta.Application.Abstractions.Files;
using SkladKomforta.Application.Abstractions.Persistence;
using SkladKomforta.Application.Abstractions.Tenancy;
using SkladKomforta.Infrastructure.Caching;
using SkladKomforta.Infrastructure.Catalog;
using SkladKomforta.Infrastructure.Authorization;
using SkladKomforta.Infrastructure.Configuration;
using SkladKomforta.Infrastructure.Files;
using SkladKomforta.Infrastructure.Health;
using SkladKomforta.Infrastructure.Identity;
using SkladKomforta.Infrastructure.Persistence;
using SkladKomforta.Infrastructure.Onboarding;
using SkladKomforta.Infrastructure.Tenancy;

namespace SkladKomforta.Infrastructure;

/// <summary>
/// Единая точка подключения infrastructure adapter-ов. Здесь проверяется
/// конфигурация и задаётся lifetime каждого потокобезопасного или scoped-сервиса.
/// </summary>
public static class DependencyInjection
{
    /// <summary>
    /// Регистрирует PostgreSQL pool, Redis multiplexer, S3 clients, tenant context,
    /// прикладные adapter-ы и readiness checks.
    /// </summary>
    /// <param name="services">Коллекция DI текущего host.</param>
    /// <param name="configuration">Объединённая JSON/environment конфигурация.</param>
    /// <returns>Исходная коллекция для последовательной регистрации сервисов.</returns>
    public static IServiceCollection AddInfrastructure(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        services.AddOptions<DatabaseOptions>()
            .Bind(configuration.GetSection(DatabaseOptions.SectionName))
            .Validate(options => !string.IsNullOrWhiteSpace(options.ConnectionString),
                "Database:ConnectionString is required.")
            .ValidateOnStart();

        services.AddOptions<RedisOptions>()
            .Bind(configuration.GetSection(RedisOptions.SectionName))
            .Validate(options => !string.IsNullOrWhiteSpace(options.ConnectionString),
                "Redis:ConnectionString is required.")
            .ValidateOnStart();

        services.AddOptions<ObjectStorageOptions>()
            .Bind(configuration.GetSection(ObjectStorageOptions.SectionName))
            .Validate(options => !string.IsNullOrWhiteSpace(options.Bucket),
                "ObjectStorage:Bucket is required.")
            .ValidateOnStart();

        services.AddSingleton(provider =>
        {
            var options = provider.GetRequiredService<IOptions<DatabaseOptions>>().Value;
            return NpgsqlDataSource.Create(options.ConnectionString);
        });
        services.AddSingleton<IConnectionMultiplexer>(provider =>
        {
            var options = provider.GetRequiredService<IOptions<RedisOptions>>().Value;
            return ConnectionMultiplexer.Connect(options.ConnectionString);
        });
        services.AddSingleton<IAmazonS3>(provider =>
        {
            var options = provider.GetRequiredService<IOptions<ObjectStorageOptions>>().Value;
            var config = new AmazonS3Config
            {
                ForcePathStyle = options.ForcePathStyle,
                RegionEndpoint = RegionEndpoint.GetBySystemName(options.Region),
            };

            if (!string.IsNullOrWhiteSpace(options.ServiceUrl))
            {
                config.ServiceURL = options.ServiceUrl;
                config.AuthenticationRegion = options.Region;
            }

            return new AmazonS3Client(
                new BasicAWSCredentials(options.AccessKey, options.SecretKey),
                config);
        });

        services.AddScoped<ITenantContext, TenantContext>();
        services.AddScoped<IDatabaseConnectionFactory, PostgresConnectionFactory>();
        services.AddSingleton<IApplicationCache, RedisApplicationCache>();
        services.AddSingleton<IObjectStorage, S3ObjectStorage>();
        services.AddHealthChecks()
            .AddCheck<PostgresHealthCheck>("postgres", tags: ["ready"])
            .AddCheck<RedisHealthCheck>("redis", tags: ["ready"])
            .AddCheck<ObjectStorageHealthCheck>("object-storage", tags: ["ready"]);

        return services;
    }

    /// <summary>
    /// Подключает Identity и tenant-авторизацию для HTTP API. Регистрация отделена
    /// от общей инфраструктуры, потому что фоновые процессы не выпускают JWT и не
    /// должны зависеть от API-реализации <c>IAccessTokenIssuer</c>.
    /// </summary>
    /// <param name="services">Коллекция DI API.</param>
    /// <param name="configuration">Конфигурация JWT, TOTP и bootstrap-доступа.</param>
    /// <returns>Исходная коллекция для последовательной регистрации сервисов.</returns>
    public static IServiceCollection AddIdentityInfrastructure(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        services.AddOptions<JwtOptions>()
            .Bind(configuration.GetSection(JwtOptions.SectionName))
            .Validate(options => options.SigningKey.Length >= 32,
                "Jwt:SigningKey must contain at least 32 characters.")
            .ValidateOnStart();

        services.AddOptions<SecurityOptions>()
            .Bind(configuration.GetSection(SecurityOptions.SectionName))
            .Validate(options => TryDecode32ByteKey(options.TotpEncryptionKey),
                "Security:TotpEncryptionKey must be a Base64-encoded 32-byte key.")
            .Validate(options => options.BootstrapToken.Length >= 24,
                "Security:BootstrapToken must contain at least 24 characters.")
            .ValidateOnStart();

        services.AddScoped<SkladKomforta.Application.Identity.IIdentityService, PostgresIdentityService>();
        services.AddScoped<SkladKomforta.Application.Identity.ITenantAccessValidator, PostgresTenantAccessValidator>();
        services.AddScoped<SkladKomforta.Application.Authorization.ITenantPermissionEvaluator, PostgresTenantPermissionEvaluator>();
        services.AddScoped<SkladKomforta.Application.Authorization.IRoleAdministrationService, PostgresRoleAdministrationService>();
        services.AddScoped<SkladKomforta.Application.Onboarding.IOrganizationOnboardingService, PostgresOrganizationOnboardingService>();
        services.AddScoped<SkladKomforta.Application.Catalog.ICatalogService, PostgresCatalogService>();
        services.AddScoped<SkladKomforta.Application.Company.ICompanyService, Company.PostgresCompanyService>();

        return services;
    }

    /// <summary>Проверяет AES-ключ без выброса FormatException во время options validation.</summary>
    private static bool TryDecode32ByteKey(string value)
    {
        try
        {
            return Convert.FromBase64String(value).Length == 32;
        }
        catch (FormatException)
        {
            return false;
        }
    }
}
