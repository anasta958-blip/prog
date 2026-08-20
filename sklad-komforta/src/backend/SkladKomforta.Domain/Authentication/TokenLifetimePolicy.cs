namespace SkladKomforta.Domain.Authentication;

/// <summary>
/// Содержит единые сроки JWT-сессий для всех API-клиентов, чтобы endpoint-ы
/// авторизации не дублировали и не рассинхронизировали значения.
/// </summary>
public static class TokenLifetimePolicy
{
    /// <summary>Срок действия короткоживущего access-токена для любого устройства.</summary>
    public static readonly TimeSpan AccessTokenLifetime = TimeSpan.FromMinutes(15);

    /// <summary>
    /// Возвращает срок refresh-сессии: семь дней для Web и тридцать дней для
    /// защищённого хранилища нативных Windows, macOS, Android и iOS клиентов.
    /// </summary>
    /// <param name="deviceType">Тип устройства, зафиксированный при входе.</param>
    /// <returns>Разрешённая продолжительность refresh-сессии.</returns>
    public static TimeSpan GetRefreshTokenLifetime(DeviceType deviceType) =>
        deviceType == DeviceType.Web ? TimeSpan.FromDays(7) : TimeSpan.FromDays(30);
}
