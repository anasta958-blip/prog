using System.Data;
using System.Reflection;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Npgsql;
using SkladKomforta.Application.Identity;
using SkladKomforta.Domain.Authentication;
using SkladKomforta.Domain.Tenancy;

namespace SkladKomforta.Infrastructure.Identity;

internal sealed partial class PostgresIdentityService
{
    /// <summary>Ограничивает перебор паролей общей Redis-записью для всех API-реплик.</summary>
    private async Task EnforceLoginRateLimitAsync(string login, string? ipAddress)
    {
        var key = LoginRateLimitKey(login, ipAddress);
        var attempts = await _redis.StringIncrementAsync(key);
        if (attempts == 1)
        {
            await _redis.KeyExpireAsync(key, LoginWindow);
        }

        if (attempts > MaximumLoginAttempts)
        {
            throw Failure(429, "login_rate_limited", "Слишком много попыток входа. Повторите позже.");
        }
    }

    /// <summary>Формирует tenant-safe ключ ограничения без хранения открытого логина.</summary>
    private static string LoginRateLimitKey(string login, string? ipAddress)
    {
        var source = $"{login.ToUpperInvariant()}|{ipAddress ?? "unknown"}";
        return $"identity:login:{Convert.ToHexString(IdentitySecurity.HashToken(source))}";
    }

    /// <summary>Читает только поля пользователя, необходимые текущему шагу входа.</summary>
    private async Task<IdentityUser?> FindUserByLoginAsync(string login, CancellationToken cancellationToken)
    {
        await using var connection = await _dataSource.OpenConnectionAsync(cancellationToken);
        const string sql = """
            SELECT u.id, u.password_hash, u.display_name, u.is_active, u.must_change_password,
                   (t.enabled_at IS NOT NULL) AS totp_enabled
            FROM public.users AS u
            LEFT JOIN public.user_totp_credentials AS t ON t.user_id = u.id
            WHERE u.login = @login AND u.deleted_at IS NULL
            """;
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("login", login);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        return await reader.ReadAsync(cancellationToken)
            ? new IdentityUser(reader.GetGuid(0), reader.GetString(1), reader.GetString(2), reader.GetBoolean(3), reader.GetBoolean(4), reader.GetBoolean(5))
            : null;
    }

    /// <summary>Сохраняет challenge под хешем непрогнозируемого токена на десять минут.</summary>
    private async Task<string> StoreChallengeAsync(AuthenticationChallenge challenge)
    {
        var token = IdentitySecurity.CreateToken(32);
        await _redis.StringSetAsync(ChallengeKey(token), JsonSerializer.Serialize(challenge), ChallengeLifetime);
        return token;
    }

    /// <summary>Читает challenge и гарантирует соответствие ожидаемому шагу state machine.</summary>
    private async Task<(string Key, AuthenticationChallenge Challenge)> RequireChallengeAsync(
        string token,
        AuthenticationStep expectedStep)
    {
        if (string.IsNullOrWhiteSpace(token))
        {
            throw Failure(401, "challenge_invalid", "Срок действия входа истёк. Войдите повторно.");
        }

        var key = ChallengeKey(token);
        var value = await _redis.StringGetAsync(key);
        var challenge = value.HasValue
            ? JsonSerializer.Deserialize<AuthenticationChallenge>(value.ToString())
            : null;
        if (challenge is null || challenge.Step != expectedStep)
        {
            throw Failure(401, "challenge_invalid", "Срок действия входа истёк. Войдите повторно.");
        }

        // A password reset also invalidates a login waiting for its second factor.
        await using var connection = await _dataSource.OpenConnectionAsync();
        await using var command = new NpgsqlCommand(
            "SELECT password_hash FROM public.users WHERE id = @id AND is_active AND deleted_at IS NULL", connection);
        command.Parameters.AddWithValue("id", challenge.UserId);
        var hash = await command.ExecuteScalarAsync() as string;
        if (hash is null || challenge.PasswordVersion != Convert.ToHexString(IdentitySecurity.HashToken(hash)))
        {
            await _redis.KeyDeleteAsync(key);
            throw Failure(401, "challenge_invalid", "Данные входа изменились. Войдите повторно.");
        }
        return (key, challenge);
    }

    /// <summary>Не включает открытый challenge token в Redis key.</summary>
    private static string ChallengeKey(string token) =>
        $"identity:challenge:{Convert.ToHexString(IdentitySecurity.HashToken(token))}";

    /// <summary>Сохраняет подтверждённый секрет и новый одноразовый набор recovery-кодов.</summary>
    private async Task SaveTotpAndRecoveryCodesAsync(
        Guid userId,
        byte[] protectedSecret,
        IReadOnlyList<string> recoveryCodes,
        CancellationToken cancellationToken)
    {
        await using var connection = await _dataSource.OpenConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        const string upsert = """
            INSERT INTO public.user_totp_credentials (user_id, encrypted_secret, enabled_at, updated_at)
            VALUES (@user_id, @secret, now(), now())
            ON CONFLICT (user_id) DO UPDATE
            SET encrypted_secret = EXCLUDED.encrypted_secret, enabled_at = now(), updated_at = now()
            """;
        await using (var command = new NpgsqlCommand(upsert, connection, transaction))
        {
            command.Parameters.AddWithValue("user_id", userId);
            command.Parameters.AddWithValue("secret", protectedSecret);
            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        await using (var delete = new NpgsqlCommand("DELETE FROM public.user_recovery_codes WHERE user_id = @user_id", connection, transaction))
        {
            delete.Parameters.AddWithValue("user_id", userId);
            await delete.ExecuteNonQueryAsync(cancellationToken);
        }

        foreach (var recoveryCode in recoveryCodes)
        {
            await using var insert = new NpgsqlCommand(
                "INSERT INTO public.user_recovery_codes (user_id, code_hash) VALUES (@user_id, @hash)",
                connection,
                transaction);
            insert.Parameters.AddWithValue("user_id", userId);
            insert.Parameters.AddWithValue("hash", IdentitySecurity.HashToken(recoveryCode));
            await insert.ExecuteNonQueryAsync(cancellationToken);
        }

        await transaction.CommitAsync(cancellationToken);
    }

    /// <summary>Читает только зашифрованный TOTP-секрет активной настройки.</summary>
    private async Task<byte[]?> ReadTotpSecretAsync(Guid userId, CancellationToken cancellationToken)
    {
        await using var connection = await _dataSource.OpenConnectionAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            "SELECT encrypted_secret FROM public.user_totp_credentials WHERE user_id = @id AND enabled_at IS NOT NULL",
            connection);
        command.Parameters.AddWithValue("id", userId);
        return await command.ExecuteScalarAsync(cancellationToken) as byte[];
    }

    /// <summary>Автоматически выбирает организацию только при единственном активном членстве.</summary>
    private async Task<Guid?> FindSingleOrganizationAsync(Guid userId, CancellationToken cancellationToken)
    {
        await using var connection = await _dataSource.OpenConnectionAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            """
            SELECT member.organization_id,
                   member.is_active AND organization.is_active
                   AND organization.active_until > now() AS access_active
            FROM public.organization_members AS member
            JOIN public.organizations AS organization ON organization.id = member.organization_id
            WHERE member.user_id = @id AND member.deleted_at IS NULL
              AND organization.deleted_at IS NULL
            ORDER BY member.created_at LIMIT 2
            """,
            connection);
        command.Parameters.AddWithValue("id", userId);
        var organizations = new List<(Guid Id, bool Active)>(2);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            organizations.Add((reader.GetGuid(0), reader.GetBoolean(1)));
        }

        if (organizations.Count == 1 && !organizations[0].Active)
            throw Failure(403, "organization_expired", "Срок действия организации истёк. Обратитесь к администратору сервиса.");
        return organizations.Count == 1 ? organizations[0].Id : null;
    }

    /// <summary>Создаёт долговечную refresh-сессию, сохраняя только хеш токена.</summary>
    private async Task InsertRefreshSessionAsync(
        Guid sessionId,
        Guid userId,
        Guid? organizationId,
        string refreshToken,
        AuthenticationChallenge challenge,
        DateTimeOffset expiresAt,
        CancellationToken cancellationToken)
    {
        await using var connection = await _dataSource.OpenConnectionAsync(cancellationToken);
        const string sql = """
            INSERT INTO public.refresh_sessions
                (id, user_id, organization_id, token_hash, device_type, device_name, ip_address, user_agent, expires_at)
            VALUES (@id, @user_id, @organization_id, @token_hash, @device_type, @device_name, CAST(@ip_address AS inet), @user_agent, @expires_at)
            """;
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("id", sessionId);
        command.Parameters.AddWithValue("user_id", userId);
        command.Parameters.AddWithValue("organization_id", (object?)organizationId ?? DBNull.Value);
        command.Parameters.AddWithValue("token_hash", IdentitySecurity.HashToken(refreshToken));
        command.Parameters.AddWithValue("device_type", (short)challenge.DeviceType);
        command.Parameters.AddWithValue("device_name", (object?)challenge.DeviceName ?? DBNull.Value);
        command.Parameters.AddWithValue("ip_address", (object?)challenge.IpAddress ?? DBNull.Value);
        command.Parameters.AddWithValue("user_agent", (object?)challenge.UserAgent ?? DBNull.Value);
        command.Parameters.AddWithValue("expires_at", expiresAt);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    /// <summary>
    /// Сколько только что заменённый refresh-токен ещё принимается. Ответ с
    /// новой cookie может не дойти до браузера (перезагрузка страницы во время
    /// запроса, одновременный запуск двух вкладок) — без этого окна такой
    /// пользователь получал 401 и входил заново.
    /// </summary>
    private static readonly TimeSpan RotationGracePeriod = TimeSpan.FromSeconds(60);

    /// <inheritdoc />
    public async Task<TokenPair> RefreshAsync(
        RefreshTokenRequest request,
        AuthenticationClientContext client,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.RefreshToken))
        {
            throw Failure(401, "refresh_invalid", "Сессия недействительна.");
        }

        // Одновременные обновления одной сессии сериализуются блокировкой
        // строки; при конфликте SERIALIZABLE запрос повторяется с новым снимком.
        for (var attempt = 1; ; attempt++)
        {
            try
            {
                return await RotateRefreshTokenAsync(request.RefreshToken, client, cancellationToken);
            }
            catch (PostgresException exception) when (
                exception.SqlState == PostgresErrorCodes.SerializationFailure && attempt < 3)
            {
            }
        }
    }

    private async Task<TokenPair> RotateRefreshTokenAsync(
        string refreshToken,
        AuthenticationClientContext client,
        CancellationToken cancellationToken)
    {
        await using var connection = await _dataSource.OpenConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(IsolationLevel.Serializable, cancellationToken);
        const string select = """
            SELECT s.id, s.user_id, s.organization_id, s.device_type, s.device_name,
                   u.display_name, s.revoked_at IS NULL, s.replaced_by
            FROM public.refresh_sessions AS s
            JOIN public.users AS u ON u.id = s.user_id
            LEFT JOIN public.organizations AS organization ON organization.id = s.organization_id
            WHERE s.token_hash = @hash AND s.expires_at > now()
              AND (s.revoked_at IS NULL
                   OR (s.replaced_by IS NOT NULL AND s.revoked_at > now() - @grace))
              AND u.is_active AND u.deleted_at IS NULL
              AND (s.organization_id IS NULL OR (
                    organization.is_active AND organization.deleted_at IS NULL
                    AND organization.active_until > now()))
            FOR UPDATE OF s
            """;
        await using var command = new NpgsqlCommand(select, connection, transaction);
        command.Parameters.AddWithValue("hash", IdentitySecurity.HashToken(refreshToken));
        command.Parameters.AddWithValue("grace", RotationGracePeriod);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            throw Failure(401, "refresh_invalid", "Сессия недействительна.");
        }

        var previousId = reader.GetGuid(0);
        var userId = reader.GetGuid(1);
        Guid? organizationId = reader.IsDBNull(2) ? null : reader.GetGuid(2);
        var deviceType = (DeviceType)reader.GetInt16(3);
        var deviceName = reader.IsDBNull(4) ? null : reader.GetString(4);
        var displayName = reader.GetString(5);
        var active = reader.GetBoolean(6);
        Guid? replacedBy = reader.IsDBNull(7) ? null : reader.GetGuid(7);
        await reader.DisposeAsync();

        // Заменяется действующая сессия. Повтор уже заменённого токена (в окне
        // ожидания) заменяет действующий конец его цепочки: ту пару браузер так
        // и не получил, поэтому она отзывается и не остаётся «висящей».
        Guid? replacedId = previousId;
        if (!active)
        {
            const string tip = """
                WITH RECURSIVE chain AS (
                    SELECT id, replaced_by, revoked_at, 1 AS depth
                    FROM public.refresh_sessions WHERE id = @start
                    UNION ALL
                    SELECT next.id, next.replaced_by, next.revoked_at, chain.depth + 1
                    FROM public.refresh_sessions AS next
                    JOIN chain ON next.id = chain.replaced_by
                    WHERE chain.depth < 20
                )
                SELECT id FROM chain WHERE revoked_at IS NULL LIMIT 1
                """;
            await using var find = new NpgsqlCommand(tip, connection, transaction);
            find.Parameters.AddWithValue("start", replacedBy!.Value);
            replacedId = await find.ExecuteScalarAsync(cancellationToken) as Guid?;
            // Цепочку закрыли выходом или отзывом устройства — повтор старого
            // токена не должен восстанавливать сессию.
            if (replacedId is null)
            {
                throw Failure(401, "refresh_invalid", "Сессия недействительна.");
            }
        }

        var newToken = IdentitySecurity.CreateToken(64);
        var newId = Guid.NewGuid();
        var expiresAt = DateTimeOffset.UtcNow + TokenLifetimePolicy.GetRefreshTokenLifetime(deviceType);
        const string insert = """
            INSERT INTO public.refresh_sessions
                (id, user_id, organization_id, token_hash, device_type, device_name, ip_address, user_agent, expires_at)
            VALUES (@id, @user_id, @organization_id, @hash, @device_type, @device_name, CAST(@ip_address AS inet), @user_agent, @expires_at)
            """;
        await using (var create = new NpgsqlCommand(insert, connection, transaction))
        {
            create.Parameters.AddWithValue("id", newId);
            create.Parameters.AddWithValue("user_id", userId);
            create.Parameters.AddWithValue("organization_id", (object?)organizationId ?? DBNull.Value);
            create.Parameters.AddWithValue("hash", IdentitySecurity.HashToken(newToken));
            create.Parameters.AddWithValue("device_type", (short)deviceType);
            create.Parameters.AddWithValue("device_name", (object?)deviceName ?? DBNull.Value);
            create.Parameters.AddWithValue("ip_address", (object?)client.IpAddress ?? DBNull.Value);
            create.Parameters.AddWithValue("user_agent", (object?)client.UserAgent ?? DBNull.Value);
            create.Parameters.AddWithValue("expires_at", expiresAt);
            await create.ExecuteNonQueryAsync(cancellationToken);
        }

        if (replacedId is { } replaced)
        {
            await using var revoke = new NpgsqlCommand(
                "UPDATE public.refresh_sessions SET revoked_at = now(), replaced_by = @new_id WHERE id = @id",
                connection, transaction);
            revoke.Parameters.AddWithValue("id", replaced);
            revoke.Parameters.AddWithValue("new_id", newId);
            await revoke.ExecuteNonQueryAsync(cancellationToken);
        }

        await transaction.CommitAsync(cancellationToken);
        var access = _accessTokenIssuer.Issue(userId, newId, organizationId, displayName);
        return new TokenPair(access.Value, access.ExpiresAt, newToken, expiresAt, newId, organizationId, deviceType);
    }

    /// <summary>Записывает security event без паролей, токенов и TOTP-секретов.</summary>
    private async Task WriteSecurityAuditAsync(
        Guid? userId,
        Guid? organizationId,
        string eventType,
        AuthenticationClientContext client,
        CancellationToken cancellationToken)
    {
        await using var connection = await _dataSource.OpenConnectionAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            "INSERT INTO public.security_audit_log (user_id, organization_id, event_type, ip_address, user_agent) VALUES (@user_id, @organization_id, @event_type, CAST(@ip AS inet), @agent)",
            connection);
        command.Parameters.AddWithValue("user_id", (object?)userId ?? DBNull.Value);
        command.Parameters.AddWithValue("organization_id", (object?)organizationId ?? DBNull.Value);
        command.Parameters.AddWithValue("event_type", eventType);
        command.Parameters.AddWithValue("ip", (object?)client.IpAddress ?? DBNull.Value);
        command.Parameters.AddWithValue("agent", (object?)client.UserAgent ?? DBNull.Value);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }
}
