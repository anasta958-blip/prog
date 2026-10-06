namespace SkladKomforta.Application.Identity;

/// <summary>
/// Описывает полный сценарий авторизации независимо от PostgreSQL, Redis и JWT.
/// API передаёт только проверенные DTO и серверный контекст соединения.
/// </summary>
public interface IIdentityService
{
    /// <summary>Проверяет логин и пароль и создаёт ограниченный challenge следующего шага.</summary>
    Task<AuthenticationResult> BeginLoginAsync(LoginRequest request, AuthenticationClientContext client, CancellationToken cancellationToken);

    /// <summary>Заменяет одноразовый пароль и переводит challenge к настройке TOTP.</summary>
    Task<AuthenticationResult> ChangeInitialPasswordAsync(ChangeInitialPasswordRequest request, CancellationToken cancellationToken);

    /// <summary>Возвращает или создаёт секрет для ещё не завершённой настройки TOTP.</summary>
    Task<TotpSetupResult> BeginTotpSetupAsync(string challengeToken, CancellationToken cancellationToken);

    /// <summary>Подтверждает новый TOTP, сохраняет зашифрованный секрет и завершает вход.</summary>
    Task<AuthenticationResult> ConfirmTotpAsync(TotpVerificationRequest request, CancellationToken cancellationToken);

    /// <summary>Проверяет TOTP существующего пользователя и завершает вход.</summary>
    Task<AuthenticationResult> VerifyTotpAsync(TotpVerificationRequest request, CancellationToken cancellationToken);

    /// <summary>Атомарно расходует recovery-код и завершает вход только один раз.</summary>
    Task<AuthenticationResult> VerifyRecoveryCodeAsync(RecoveryCodeVerificationRequest request, CancellationToken cancellationToken);

    /// <summary>Атомарно отзывает использованный refresh-токен и выдаёт новую пару.</summary>
    Task<TokenPair> RefreshAsync(RefreshTokenRequest request, AuthenticationClientContext client, CancellationToken cancellationToken);

    /// <summary>Создаёт организацию, tenant-схему и роль директора одной транзакцией.</summary>
    Task<OrganizationOnboardingResult> CreateOrganizationAsync(Guid userId, Guid sessionId, CreateOrganizationRequest request, CancellationToken cancellationToken);

    /// <summary>Возвращает активные сессии текущего пользователя.</summary>
    Task<IReadOnlyList<DeviceSession>> GetSessionsAsync(Guid userId, Guid currentSessionId, CancellationToken cancellationToken);

    /// <summary>Отзывает конкретную сессию, принадлежащую текущему пользователю.</summary>
    Task RevokeSessionAsync(Guid userId, Guid sessionId, CancellationToken cancellationToken);

    /// <summary>Отзывает все сессии пользователя, кроме выполняющей запрос.</summary>
    Task RevokeOtherSessionsAsync(Guid userId, Guid currentSessionId, CancellationToken cancellationToken);

    /// <summary>
    /// Создаёт директора новой организации (закрытый bootstrap-endpoint с
    /// секретным токеном). Директоров может быть несколько; каждый создаёт свою
    /// организацию. Занятый логин — 409 <c>bootstrap_login_taken</c>.
    /// </summary>
    Task<Guid> BootstrapDirectorAsync(BootstrapDirectorRequest request, CancellationToken cancellationToken);
}
