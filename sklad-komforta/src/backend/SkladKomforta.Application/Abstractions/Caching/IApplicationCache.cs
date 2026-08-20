namespace SkladKomforta.Application.Abstractions.Caching;

/// <summary>
/// Минимальный контракт распределённого кэша. Бизнес-слой не зависит от Redis
/// и использует только строковые сериализованные значения с обязательным TTL.
/// </summary>
public interface IApplicationCache
{
    /// <summary>Читает значение либо возвращает <see langword="null" />, если ключ отсутствует.</summary>
    Task<string?> GetStringAsync(string key, CancellationToken cancellationToken = default);

    /// <summary>Сохраняет значение на ограниченный срок без бессрочных записей.</summary>
    Task SetStringAsync(
        string key,
        string value,
        TimeSpan lifetime,
        CancellationToken cancellationToken = default);

    /// <summary>Удаляет ключ; отсутствие ключа не считается ошибкой.</summary>
    Task RemoveAsync(string key, CancellationToken cancellationToken = default);
}
