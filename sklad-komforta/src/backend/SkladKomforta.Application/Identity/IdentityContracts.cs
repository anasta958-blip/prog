using SkladKomforta.Domain.Authentication;

namespace SkladKomforta.Application.Identity;

/// <summary>Определяет следующий обязательный шаг защищённого входа.</summary>
public enum AuthenticationStep
{
    /// <summary>Одноразовый пароль директора необходимо заменить.</summary>
    ChangePassword = 1,

    /// <summary>Пользователь должен впервые подключить приложение-аутентификатор.</summary>
    SetupTotp = 2,

    /// <summary>Пользователь должен подтвердить вход действующим TOTP-кодом.</summary>
    VerifyTotp = 3,

    /// <summary>Аутентификация завершена и выданы access/refresh-токены.</summary>
    Completed = 4,
}

/// <summary>Запрос первого шага входа без сведений, вычисляемых сервером.</summary>
public sealed record LoginRequest(
    string Login,
    string Password,
    DeviceType DeviceType,
    string? DeviceName);

/// <summary>Запрос обязательной смены одноразового пароля.</summary>
public sealed record ChangeInitialPasswordRequest(
    string ChallengeToken,
    string NewPassword);

/// <summary>Запрос шага, защищённого шестизначным TOTP-кодом.</summary>
public sealed record TotpVerificationRequest(string ChallengeToken, string Code);

/// <summary>Одноразовая замена TOTP-кода заранее сохранённым recovery-кодом.</summary>
public sealed record RecoveryCodeVerificationRequest(string ChallengeToken, string RecoveryCode);

/// <summary>Запрос ротации refresh-токена; старый токен после успеха недействителен.</summary>
public sealed record RefreshTokenRequest(string RefreshToken);

/// <summary>Запрос создания первой организации директора.</summary>
public sealed record CreateOrganizationRequest(string Name);

/// <summary>Запрос одноразового административного создания первого директора.</summary>
public sealed record BootstrapDirectorRequest(string Login, string DisplayName, string TemporaryPassword);

/// <summary>Метаданные запроса, которые нельзя принимать из JSON клиента.</summary>
public sealed record AuthenticationClientContext(string? IpAddress, string? UserAgent);

/// <summary>Результат промежуточного или завершённого шага входа.</summary>
public sealed record AuthenticationResult(
    AuthenticationStep Step,
    string? ChallengeToken,
    TokenPair? Tokens,
    bool OnboardingRequired,
    IReadOnlyList<string>? RecoveryCodes = null);

/// <summary>Данные первичной настройки TOTP без хранения открытого секрета в базе.</summary>
public sealed record TotpSetupResult(string Secret, string OtpAuthUri);

/// <summary>Короткоживущий access-токен и ротируемая refresh-сессия.</summary>
public sealed record TokenPair(
    string AccessToken,
    DateTimeOffset AccessTokenExpiresAt,
    string? RefreshToken,
    DateTimeOffset RefreshTokenExpiresAt,
    Guid SessionId,
    Guid? OrganizationId,
    DeviceType DeviceType);

/// <summary>Безопасное представление активного устройства без токена и его хеша.</summary>
public sealed record DeviceSession(
    Guid Id,
    DeviceType DeviceType,
    string? DeviceName,
    string? IpAddress,
    DateTimeOffset CreatedAt,
    DateTimeOffset LastSeenAt,
    DateTimeOffset ExpiresAt,
    bool IsCurrent);

/// <summary>Созданная организация и новый access-токен с tenant claim.</summary>
public sealed record OrganizationOnboardingResult(
    Guid OrganizationId,
    string Name,
    string AccessToken,
    DateTimeOffset AccessTokenExpiresAt);

/// <summary>Стабильная прикладная ошибка, которую API преобразует в единый ответ.</summary>
public sealed class IdentityException : Exception
{
    /// <summary>Создаёт ошибку с HTTP-статусом и машинным кодом.</summary>
    public IdentityException(int statusCode, string code, string message) : base(message)
    {
        StatusCode = statusCode;
        Code = code;
    }

    /// <summary>Рекомендуемый HTTP-статус ответа.</summary>
    public int StatusCode { get; }

    /// <summary>Стабильный машинный код для Flutter-клиента.</summary>
    public string Code { get; }
}
