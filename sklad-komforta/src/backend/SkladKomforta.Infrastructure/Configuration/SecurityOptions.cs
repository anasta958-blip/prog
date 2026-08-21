namespace SkladKomforta.Infrastructure.Configuration;

/// <summary>Секреты безопасности, которые production получает только из secret storage.</summary>
public sealed class SecurityOptions
{
    /// <summary>Имя секции конфигурации ASP.NET Core.</summary>
    public const string SectionName = "Security";

    /// <summary>Base64-представление 32-байтового AES-ключа шифрования TOTP.</summary>
    public string TotpEncryptionKey { get; init; } = string.Empty;

    /// <summary>Одноразовый секрет административного создания первого директора.</summary>
    public string BootstrapToken { get; init; } = string.Empty;
}
