namespace SkladKomforta.Domain.Authentication;

/// <summary>
/// Определяет семейство клиентского устройства. Значения сохраняются в базе
/// и используются политикой срока действия refresh-токена.
/// </summary>
public enum DeviceType
{
    /// <summary>Браузерный клиент с более короткой refresh-сессией.</summary>
    Web = 1,

    /// <summary>Настольное приложение Windows.</summary>
    Windows = 2,

    /// <summary>Мобильное приложение Android.</summary>
    Android = 3,

    /// <summary>Мобильное приложение iOS.</summary>
    Ios = 4,

    /// <summary>Настольное приложение macOS.</summary>
    MacOs = 5,
}
