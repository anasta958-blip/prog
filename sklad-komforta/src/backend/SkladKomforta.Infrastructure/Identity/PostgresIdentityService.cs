using System.Globalization;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.Options;
using Npgsql;
using StackExchange.Redis;
using SkladKomforta.Application.Identity;
using SkladKomforta.Domain.Authentication;
using SkladKomforta.Infrastructure.Configuration;

namespace SkladKomforta.Infrastructure.Identity;

/// <summary>
/// Реализует Identity use cases через PostgreSQL и Redis. Экземпляр stateless:
/// все данные продолжения входа находятся в Redis, а долговечные сессии и
/// учётные данные — в PostgreSQL, поэтому сервис безопасно масштабируется.
/// </summary>
internal sealed partial class PostgresIdentityService : IIdentityService
{
    private static readonly TimeSpan ChallengeLifetime = TimeSpan.FromMinutes(10);
    private static readonly TimeSpan LoginWindow = TimeSpan.FromMinutes(15);
    private const long MaximumLoginAttempts = 5;

    private readonly NpgsqlDataSource _dataSource;
    private readonly IDatabase _redis;
    private readonly IAccessTokenIssuer _accessTokenIssuer;
    private readonly PasswordHasher<string> _passwordHasher = new();
    private readonly byte[] _totpEncryptionKey;

    /// <summary>Создаёт stateless Identity service из общих подключений и настроек.</summary>
    public PostgresIdentityService(
        NpgsqlDataSource dataSource,
        IConnectionMultiplexer redis,
        IAccessTokenIssuer accessTokenIssuer,
        IOptions<SecurityOptions> securityOptions)
    {
        _dataSource = dataSource;
        _redis = redis.GetDatabase();
        _accessTokenIssuer = accessTokenIssuer;
        _totpEncryptionKey = Convert.FromBase64String(securityOptions.Value.TotpEncryptionKey);
    }

    /// <inheritdoc />
    public async Task<AuthenticationResult> BeginLoginAsync(
        LoginRequest request,
        AuthenticationClientContext client,
        CancellationToken cancellationToken)
    {
        var normalizedLogin = request.Login.Trim();
        if (normalizedLogin.Length == 0 || request.Password.Length == 0)
        {
            throw Failure(400, "invalid_credentials", "Введите логин и пароль.");
        }

        await EnforceLoginRateLimitAsync(normalizedLogin, client.IpAddress);
        var user = await FindUserByLoginAsync(normalizedLogin, cancellationToken);
        if (user is null || !user.IsActive || !VerifyPassword(user, request.Password))
        {
            await WriteSecurityAuditAsync(null, null, "login_failed", client, cancellationToken);
            throw Failure(401, "invalid_credentials", "Неверный логин или пароль.");
        }

        await _redis.KeyDeleteAsync(LoginRateLimitKey(normalizedLogin, client.IpAddress));
        var step = user.MustChangePassword
            ? AuthenticationStep.ChangePassword
            : user.TotpEnabled
                ? AuthenticationStep.VerifyTotp
                : AuthenticationStep.SetupTotp;
        var challenge = new AuthenticationChallenge(
            user.Id,
            user.DisplayName,
            step,
            request.DeviceType,
            NormalizeOptional(request.DeviceName, 120),
            client.IpAddress,
            client.UserAgent,
            null);
        var token = await StoreChallengeAsync(challenge);
        await WriteSecurityAuditAsync(user.Id, null, "password_verified", client, cancellationToken);
        return new AuthenticationResult(step, token, null, false);
    }

    /// <inheritdoc />
    public async Task<AuthenticationResult> ChangeInitialPasswordAsync(
        ChangeInitialPasswordRequest request,
        CancellationToken cancellationToken)
    {
        var validation = PasswordPolicy.Validate(request.NewPassword);
        if (!validation.IsValid)
        {
            throw Failure(400, validation.ErrorCode!, validation.ErrorMessage!);
        }

        var (key, challenge) = await RequireChallengeAsync(request.ChallengeToken, AuthenticationStep.ChangePassword);
        var hash = _passwordHasher.HashPassword(challenge.UserId.ToString("N"), request.NewPassword);
        await using var connection = await _dataSource.OpenConnectionAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            "UPDATE public.users SET password_hash = @hash, must_change_password = false, updated_at = now() WHERE id = @id AND deleted_at IS NULL",
            connection);
        command.Parameters.AddWithValue("hash", hash);
        command.Parameters.AddWithValue("id", challenge.UserId);
        if (await command.ExecuteNonQueryAsync(cancellationToken) != 1)
        {
            throw Failure(401, "challenge_invalid", "Срок действия входа истёк. Войдите повторно.");
        }

        await _redis.KeyDeleteAsync(key);
        var next = challenge with { Step = AuthenticationStep.SetupTotp };
        var nextToken = await StoreChallengeAsync(next);
        return new AuthenticationResult(AuthenticationStep.SetupTotp, nextToken, null, false);
    }

    /// <inheritdoc />
    public async Task<TotpSetupResult> BeginTotpSetupAsync(string challengeToken, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var (key, challenge) = await RequireChallengeAsync(challengeToken, AuthenticationStep.SetupTotp);
        byte[] secret;
        if (challenge.ProtectedTotpSecret is null)
        {
            secret = System.Security.Cryptography.RandomNumberGenerator.GetBytes(20);
            challenge = challenge with
            {
                ProtectedTotpSecret = Convert.ToBase64String(
                    IdentitySecurity.ProtectSecret(secret, _totpEncryptionKey)),
            };
            await _redis.StringSetAsync(key, JsonSerializer.Serialize(challenge), ChallengeLifetime);
        }
        else
        {
            secret = IdentitySecurity.UnprotectSecret(
                Convert.FromBase64String(challenge.ProtectedTotpSecret),
                _totpEncryptionKey);
        }

        var base32 = IdentitySecurity.ToBase32(secret);
        var issuer = Uri.EscapeDataString("Склад Комфорта");
        var account = Uri.EscapeDataString(challenge.DisplayName);
        var uri = $"otpauth://totp/{issuer}:{account}?secret={base32}&issuer={issuer}&digits=6&period=30";
        return new TotpSetupResult(base32, uri);
    }

    /// <inheritdoc />
    public async Task<AuthenticationResult> ConfirmTotpAsync(
        TotpVerificationRequest request,
        CancellationToken cancellationToken)
    {
        var (key, challenge) = await RequireChallengeAsync(request.ChallengeToken, AuthenticationStep.SetupTotp);
        if (challenge.ProtectedTotpSecret is null)
        {
            throw Failure(409, "totp_setup_not_started", "Сначала откройте настройку двухфакторной защиты.");
        }

        var protectedSecret = Convert.FromBase64String(challenge.ProtectedTotpSecret);
        var secret = IdentitySecurity.UnprotectSecret(protectedSecret, _totpEncryptionKey);
        if (!TotpCode.Verify(secret, request.Code, DateTimeOffset.UtcNow))
        {
            throw Failure(401, "totp_invalid", "Неверный или устаревший код подтверждения.");
        }

        var recoveryCodes = Enumerable.Range(0, 10)
            .Select(_ => IdentitySecurity.CreateToken(9).ToUpperInvariant())
            .ToArray();
        await SaveTotpAndRecoveryCodesAsync(challenge.UserId, protectedSecret, recoveryCodes, cancellationToken);
        var completed = await CompleteLoginAsync(challenge, cancellationToken);
        await _redis.KeyDeleteAsync(key);
        return completed with { RecoveryCodes = recoveryCodes };
    }

    /// <inheritdoc />
    public async Task<AuthenticationResult> VerifyTotpAsync(
        TotpVerificationRequest request,
        CancellationToken cancellationToken)
    {
        var (key, challenge) = await RequireChallengeAsync(request.ChallengeToken, AuthenticationStep.VerifyTotp);
        var protectedSecret = await ReadTotpSecretAsync(challenge.UserId, cancellationToken);
        if (protectedSecret is null ||
            !TotpCode.Verify(
                IdentitySecurity.UnprotectSecret(protectedSecret, _totpEncryptionKey),
                request.Code,
                DateTimeOffset.UtcNow))
        {
            throw Failure(401, "totp_invalid", "Неверный или устаревший код подтверждения.");
        }

        var completed = await CompleteLoginAsync(challenge, cancellationToken);
        await _redis.KeyDeleteAsync(key);
        return completed;
    }

    /// <inheritdoc />
    public async Task<AuthenticationResult> VerifyRecoveryCodeAsync(
        RecoveryCodeVerificationRequest request,
        CancellationToken cancellationToken)
    {
        var (key, challenge) = await RequireChallengeAsync(request.ChallengeToken, AuthenticationStep.VerifyTotp);
        var code = request.RecoveryCode.Trim().ToUpperInvariant();
        if (code.Length < 8)
        {
            throw Failure(401, "recovery_code_invalid", "Резервный код недействителен или уже использован.");
        }

        await using var connection = await _dataSource.OpenConnectionAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            "UPDATE public.user_recovery_codes SET used_at = now() WHERE user_id = @user_id AND code_hash = @hash AND used_at IS NULL RETURNING id",
            connection);
        command.Parameters.AddWithValue("user_id", challenge.UserId);
        command.Parameters.AddWithValue("hash", IdentitySecurity.HashToken(code));
        if (await command.ExecuteScalarAsync(cancellationToken) is null)
        {
            throw Failure(401, "recovery_code_invalid", "Резервный код недействителен или уже использован.");
        }

        var completed = await CompleteLoginAsync(challenge, cancellationToken);
        await _redis.KeyDeleteAsync(key);
        return completed;
    }

    /// <summary>Проверяет пароль с автоматическим распознаванием формата ASP.NET Identity.</summary>
    private bool VerifyPassword(IdentityUser user, string password) =>
        _passwordHasher.VerifyHashedPassword(user.Id.ToString("N"), user.PasswordHash, password) !=
        PasswordVerificationResult.Failed;

    /// <summary>Создаёт refresh-сессию и access-токен после завершения второго фактора.</summary>
    private async Task<AuthenticationResult> CompleteLoginAsync(
        AuthenticationChallenge challenge,
        CancellationToken cancellationToken)
    {
        var organizationId = await FindSingleOrganizationAsync(challenge.UserId, cancellationToken);
        var refreshToken = IdentitySecurity.CreateToken(64);
        var sessionId = Guid.NewGuid();
        var refreshExpiresAt = DateTimeOffset.UtcNow + TokenLifetimePolicy.GetRefreshTokenLifetime(challenge.DeviceType);
        await InsertRefreshSessionAsync(sessionId, challenge.UserId, organizationId, refreshToken, challenge, refreshExpiresAt, cancellationToken);
        var access = _accessTokenIssuer.Issue(challenge.UserId, sessionId, organizationId, challenge.DisplayName);
        var pair = new TokenPair(access.Value, access.ExpiresAt, refreshToken, refreshExpiresAt, sessionId, organizationId, challenge.DeviceType);
        return new AuthenticationResult(AuthenticationStep.Completed, null, pair, organizationId is null);
    }

    /// <summary>Возвращает прикладную ошибку без утечки внутренних исключений.</summary>
    private static IdentityException Failure(int status, string code, string message) => new(status, code, message);

    /// <summary>Обрезает необязательное клиентское значение до безопасной длины.</summary>
    private static string? NormalizeOptional(string? value, int maximumLength)
    {
        var normalized = value?.Trim();
        return string.IsNullOrEmpty(normalized) ? null : normalized[..Math.Min(normalized.Length, maximumLength)];
    }

    private sealed record IdentityUser(
        Guid Id,
        string PasswordHash,
        string DisplayName,
        bool IsActive,
        bool MustChangePassword,
        bool TotpEnabled);

    private sealed record AuthenticationChallenge(
        Guid UserId,
        string DisplayName,
        AuthenticationStep Step,
        DeviceType DeviceType,
        string? DeviceName,
        string? IpAddress,
        string? UserAgent,
        string? ProtectedTotpSecret);
}
