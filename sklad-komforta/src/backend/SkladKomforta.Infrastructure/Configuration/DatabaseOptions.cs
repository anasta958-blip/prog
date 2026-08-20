namespace SkladKomforta.Infrastructure.Configuration;

/// <summary>Содержит заменяемую через environment строку подключения PostgreSQL.</summary>
public sealed class DatabaseOptions
{
    /// <summary>Имя секции конфигурации ASP.NET Core.</summary>
    public const string SectionName = "Database";

    /// <summary>Полная строка подключения к общей базе с public и tenant-схемами.</summary>
    public string ConnectionString { get; init; } = string.Empty;
}
