namespace SkladKomforta.Infrastructure.Configuration;

/// <summary>Содержит адрес, пароль и параметры подключения к Redis.</summary>
public sealed class RedisOptions
{
    /// <summary>Имя секции конфигурации ASP.NET Core.</summary>
    public const string SectionName = "Redis";

    /// <summary>Строка StackExchange.Redis, заменяемая без изменения кода.</summary>
    public string ConnectionString { get; init; } = string.Empty;
}
