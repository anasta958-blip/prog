using System.Reflection;
using Microsoft.AspNetCore.Identity;
using Npgsql;
using SkladKomforta.Application.Identity;
using SkladKomforta.Domain.Authentication;
using SkladKomforta.Domain.Tenancy;

namespace SkladKomforta.Infrastructure.Identity;

internal sealed partial class PostgresIdentityService
{
    /// <inheritdoc />
    public async Task<Guid> BootstrapDirectorAsync(
        BootstrapDirectorRequest request,
        CancellationToken cancellationToken)
    {
        var validation = PasswordPolicy.Validate(request.TemporaryPassword);
        if (!validation.IsValid)
        {
            throw Failure(400, validation.ErrorCode!, validation.ErrorMessage!);
        }

        var login = request.Login.Trim();
        var displayName = request.DisplayName.Trim();
        if (login.Length is < 3 or > 100 || displayName.Length is < 2 or > 200)
        {
            throw Failure(400, "bootstrap_data_invalid", "Проверьте логин и имя директора.");
        }

        await using var connection = await _dataSource.OpenConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        // Директоров может быть несколько: каждый затем создаёт свою изолированную
        // организацию. Логин уникален во всей системе (citext, без учёта регистра).
        await using (var check = new NpgsqlCommand(
                         "SELECT EXISTS (SELECT 1 FROM public.users WHERE login = @login)", connection, transaction))
        {
            check.Parameters.AddWithValue("login", login);
            if (await check.ExecuteScalarAsync(cancellationToken) is true)
            {
                throw LoginTaken();
            }
        }

        var userId = Guid.NewGuid();
        var passwordHash = _passwordHasher.HashPassword(userId.ToString("N"), request.TemporaryPassword);
        await using var insert = new NpgsqlCommand(
            "INSERT INTO public.users (id, login, password_hash, display_name, must_change_password) VALUES (@id, @login, @hash, @name, true)",
            connection,
            transaction);
        insert.Parameters.AddWithValue("id", userId);
        insert.Parameters.AddWithValue("login", login);
        insert.Parameters.AddWithValue("hash", passwordHash);
        insert.Parameters.AddWithValue("name", displayName);
        try
        {
            await insert.ExecuteNonQueryAsync(cancellationToken);
        }
        catch (PostgresException exception) when (exception.SqlState == PostgresErrorCodes.UniqueViolation)
        {
            // Тот же логин создан параллельным запросом между проверкой и вставкой.
            throw LoginTaken();
        }
        await transaction.CommitAsync(cancellationToken);
        return userId;
    }

    private static IdentityException LoginTaken() =>
        Failure(409, "bootstrap_login_taken", "Этот логин уже занят. Выберите другой.");

    /// <inheritdoc />
    public async Task<OrganizationOnboardingResult> CreateOrganizationAsync(
        Guid userId,
        Guid sessionId,
        CreateOrganizationRequest request,
        CancellationToken cancellationToken)
    {
        var name = request.Name.Trim();
        if (name.Length is < 2 or > 200)
        {
            throw Failure(400, "organization_name_invalid", "Название организации должно содержать от 2 до 200 символов.");
        }

        var organizationId = Guid.NewGuid();
        var schema = TenantSchemaName.Create(organizationId);
        await using var connection = await _dataSource.OpenConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        await using (var membershipCheck = new NpgsqlCommand(
            "SELECT EXISTS (SELECT 1 FROM public.organization_members WHERE user_id = @user_id AND deleted_at IS NULL)",
            connection,
            transaction))
        {
            membershipCheck.Parameters.AddWithValue("user_id", userId);
            if (await membershipCheck.ExecuteScalarAsync(cancellationToken) is true)
            {
                throw Failure(409, "onboarding_completed", "Организация уже создана.");
            }
        }

        await using (var organization = new NpgsqlCommand(
            "INSERT INTO public.organizations (id, name, schema_name) VALUES (@id, @name, @schema)",
            connection,
            transaction))
        {
            organization.Parameters.AddWithValue("id", organizationId);
            organization.Parameters.AddWithValue("name", name);
            organization.Parameters.AddWithValue("schema", schema.Value);
            await organization.ExecuteNonQueryAsync(cancellationToken);
        }

        var membershipId = Guid.NewGuid();
        await using (var membership = new NpgsqlCommand(
            "INSERT INTO public.organization_members (id, organization_id, user_id, is_director) VALUES (@id, @organization_id, @user_id, true)",
            connection,
            transaction))
        {
            membership.Parameters.AddWithValue("id", membershipId);
            membership.Parameters.AddWithValue("organization_id", organizationId);
            membership.Parameters.AddWithValue("user_id", userId);
            await membership.ExecuteNonQueryAsync(cancellationToken);
        }

        foreach (var migration in ReadTenantMigrations())
        {
            var sql = migration.Sql.Replace("__TENANT_SCHEMA__", schema.Value, StringComparison.Ordinal);
            await using var migrate = new NpgsqlCommand(sql, connection, transaction);
            await migrate.ExecuteNonQueryAsync(cancellationToken);
            await using var version = new NpgsqlCommand(
                "INSERT INTO public.tenant_migrations (organization_id, version) VALUES (@organization_id, @version)",
                connection,
                transaction);
            version.Parameters.AddWithValue("organization_id", organizationId);
            version.Parameters.AddWithValue("version", migration.Version);
            await version.ExecuteNonQueryAsync(cancellationToken);
        }

        await using (var role = new NpgsqlCommand(
            $"INSERT INTO {schema.Value}.member_roles (membership_id, role_id) SELECT @membership_id, id FROM {schema.Value}.roles WHERE name = 'Директор'",
            connection,
            transaction))
        {
            role.Parameters.AddWithValue("membership_id", membershipId);
            await role.ExecuteNonQueryAsync(cancellationToken);
        }

        await using (var session = new NpgsqlCommand(
            "UPDATE public.refresh_sessions SET organization_id = @organization_id, last_seen_at = now() WHERE id = @session_id AND user_id = @user_id AND revoked_at IS NULL",
            connection,
            transaction))
        {
            session.Parameters.AddWithValue("organization_id", organizationId);
            session.Parameters.AddWithValue("session_id", sessionId);
            session.Parameters.AddWithValue("user_id", userId);
            if (await session.ExecuteNonQueryAsync(cancellationToken) != 1)
            {
                throw Failure(401, "session_invalid", "Текущая сессия недействительна.");
            }
        }

        await transaction.CommitAsync(cancellationToken);
        var displayName = await ReadDisplayNameAsync(userId, cancellationToken);
        var access = _accessTokenIssuer.Issue(userId, sessionId, organizationId, displayName);
        return new OrganizationOnboardingResult(organizationId, name, access.Value, access.ExpiresAt);
    }

    /// <inheritdoc />
    public async Task<IReadOnlyList<DeviceSession>> GetSessionsAsync(
        Guid userId,
        Guid currentSessionId,
        CancellationToken cancellationToken)
    {
        await using var connection = await _dataSource.OpenConnectionAsync(cancellationToken);
        const string sql = """
            SELECT id, device_type, device_name, host(ip_address), created_at, last_seen_at, expires_at
            FROM public.refresh_sessions
            WHERE user_id = @user_id AND revoked_at IS NULL AND expires_at > now()
            ORDER BY last_seen_at DESC
            """;
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("user_id", userId);
        var sessions = new List<DeviceSession>();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            var id = reader.GetGuid(0);
            sessions.Add(new DeviceSession(
                id,
                (DeviceType)reader.GetInt16(1),
                reader.IsDBNull(2) ? null : reader.GetString(2),
                reader.IsDBNull(3) ? null : reader.GetString(3),
                new DateTimeOffset(reader.GetFieldValue<DateTime>(4)),
                new DateTimeOffset(reader.GetFieldValue<DateTime>(5)),
                new DateTimeOffset(reader.GetFieldValue<DateTime>(6)),
                id == currentSessionId));
        }

        return sessions;
    }

    /// <inheritdoc />
    public async Task RevokeSessionAsync(Guid userId, Guid sessionId, CancellationToken cancellationToken)
    {
        await using var connection = await _dataSource.OpenConnectionAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            "UPDATE public.refresh_sessions SET revoked_at = now() WHERE id = @id AND user_id = @user_id AND revoked_at IS NULL",
            connection);
        command.Parameters.AddWithValue("id", sessionId);
        command.Parameters.AddWithValue("user_id", userId);
        if (await command.ExecuteNonQueryAsync(cancellationToken) != 1)
        {
            throw Failure(404, "session_not_found", "Сессия не найдена.");
        }
    }

    /// <inheritdoc />
    public async Task RevokeOtherSessionsAsync(Guid userId, Guid currentSessionId, CancellationToken cancellationToken)
    {
        await using var connection = await _dataSource.OpenConnectionAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            "UPDATE public.refresh_sessions SET revoked_at = now() WHERE user_id = @user_id AND id <> @current_id AND revoked_at IS NULL",
            connection);
        command.Parameters.AddWithValue("user_id", userId);
        command.Parameters.AddWithValue("current_id", currentSessionId);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    /// <summary>Читает tenant SQL из embedded resources, сохраняя числовой порядок файлов.</summary>
    private static TenantMigration[] ReadTenantMigrations()
    {
        var assembly = typeof(PostgresIdentityService).Assembly;
        return assembly.GetManifestResourceNames()
            .Where(name => name.Contains("migrations.tenant", StringComparison.OrdinalIgnoreCase) && name.EndsWith(".sql", StringComparison.OrdinalIgnoreCase))
            .OrderBy(name => name, StringComparer.Ordinal)
            .Select(name =>
            {
                using var stream = assembly.GetManifestResourceStream(name)
                    ?? throw new InvalidOperationException($"Не найден ресурс миграции {name}.");
                using var reader = new StreamReader(stream);
                var version = Path.GetFileNameWithoutExtension(name[(name.LastIndexOf("tenant", StringComparison.OrdinalIgnoreCase) + 7)..]);
                return new TenantMigration(version, reader.ReadToEnd());
            })
            .ToArray();
    }

    /// <summary>Получает отображаемое имя только после успешной транзакции onboarding.</summary>
    private async Task<string> ReadDisplayNameAsync(Guid userId, CancellationToken cancellationToken)
    {
        await using var connection = await _dataSource.OpenConnectionAsync(cancellationToken);
        await using var command = new NpgsqlCommand("SELECT display_name FROM public.users WHERE id = @id", connection);
        command.Parameters.AddWithValue("id", userId);
        return (string)(await command.ExecuteScalarAsync(cancellationToken)
            ?? throw Failure(401, "user_inactive", "Пользователь недоступен."));
    }

    private sealed record TenantMigration(string Version, string Sql);
}
