namespace SkladKomforta.Infrastructure.Configuration;

/// <summary>Параметры проверки JWT, общие для API и будущего token service.</summary>
public sealed class JwtOptions
{
    /// <summary>Имя секции конфигурации ASP.NET Core.</summary>
    public const string SectionName = "Jwt";

    /// <summary>Ожидаемый издатель токена.</summary>
    public string Issuer { get; init; } = string.Empty;

    /// <summary>Ожидаемая аудитория токена.</summary>
    public string Audience { get; init; } = string.Empty;

    /// <summary>Development-ключ подписи; production получает ключ из secret storage.</summary>
    public string SigningKey { get; init; } = string.Empty;
}
