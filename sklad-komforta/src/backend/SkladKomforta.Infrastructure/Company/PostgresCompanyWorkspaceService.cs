using System.Data.Common;
using System.Globalization;
using System.Net.Mail;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Npgsql;
using SkladKomforta.Application.Abstractions.Persistence;
using SkladKomforta.Application.Abstractions.Tenancy;
using SkladKomforta.Application.Company;
using SkladKomforta.Application.Identity;
using SkladKomforta.Domain.Authentication;

namespace SkladKomforta.Infrastructure.Company;

/// <summary>
/// Реализует рабочие разделы пространства «Компания». Все tenant-таблицы и
/// public identity-таблицы изменяются в одной PostgreSQL-транзакции.
/// </summary>
internal sealed class PostgresCompanyWorkspaceService(
    IDatabaseConnectionFactory connectionFactory,
    ITenantContext tenantContext) : ICompanyWorkspaceService
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private readonly PasswordHasher<string> _passwordHasher = new();

    /// <inheritdoc />
    public async Task<OrganizationLifecycle> GetLifecycleAsync(CancellationToken cancellationToken)
    {
        await using var connection = await connectionFactory.OpenPublicConnectionAsync(cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandText = "SELECT active_until, NOT is_active OR active_until <= now() FROM public.organizations WHERE id = @id AND deleted_at IS NULL";
        Add(command, "id", tenantContext.OrganizationId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken)) throw NotFound("organization_not_found", "Организация не найдена.");
        return new OrganizationLifecycle(reader.GetFieldValue<DateTimeOffset>(0), reader.GetBoolean(1));
    }

    /// <inheritdoc />
    public async Task<IReadOnlyList<CompanyAuditEntry>> GetAuditAsync(int limit, CancellationToken cancellationToken)
    {
        var safeLimit = Math.Clamp(limit, 1, 500);
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT audit.id, audit.actor_user_id, actor.display_name,
                   audit.entity_type, audit.entity_id, audit.action, audit.created_at,
                   COALESCE(audit.diff, '{}'::jsonb)
            FROM audit_log AS audit
            LEFT JOIN public.users AS actor ON actor.id = audit.actor_user_id
            ORDER BY audit.created_at DESC, audit.id DESC
            LIMIT @limit
            """;
        Add(command, "limit", safeLimit);
        var result = new List<CompanyAuditEntry>();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            result.Add(new CompanyAuditEntry(
                reader.GetInt64(0),
                reader.IsDBNull(1) ? null : reader.GetGuid(1),
                Text(reader, 2),
                reader.GetString(3),
                reader.IsDBNull(4) ? null : reader.GetGuid(4),
                reader.GetString(5),
                reader.GetFieldValue<DateTimeOffset>(6),
                JsonSerializer.Deserialize<JsonElement>(reader.GetString(7), JsonOptions)));
        }
        return result;
    }

    /// <inheritdoc />
    public async Task<IReadOnlyList<LegalEntity>> GetLegalEntitiesAsync(CancellationToken cancellationToken)
    {
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        return await ReadLegalEntitiesAsync(connection, null, cancellationToken);
    }

    /// <inheritdoc />
    public async Task<LegalEntity> CreateLegalEntityAsync(Guid actorUserId, SaveLegalEntityRequest request, CancellationToken cancellationToken)
    {
        ValidateLegalEntity(request);
        var id = Guid.NewGuid();
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        if (request.IsDefault) await ClearDefaultCompanyAsync(connection, transaction, cancellationToken);
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            INSERT INTO companies
                (id, name, company_type, legal_name, inn, kpp, ogrn, address, phone, email, details, is_default, created_by)
            VALUES
                (@id, @name, @type, @legal_name, @inn, @kpp, @ogrn, @address, @phone, @email, CAST(@details AS jsonb),
                 @is_default OR NOT EXISTS (SELECT 1 FROM companies WHERE deleted_at IS NULL), @actor)
            """;
        BindLegalEntity(command, id, actorUserId, request);
        await command.ExecuteNonQueryAsync(cancellationToken);
        await WriteAuditAsync(connection, transaction, actorUserId, "legal_entity", id, "created", null, request, cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return (await ReadLegalEntitiesAsync(connection, id, cancellationToken)).Single();
    }

    /// <inheritdoc />
    public async Task<LegalEntity> UpdateLegalEntityAsync(Guid actorUserId, Guid id, SaveLegalEntityRequest request, CancellationToken cancellationToken)
    {
        ValidateLegalEntity(request);
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        var before = (await ReadLegalEntitiesAsync(connection, id, cancellationToken)).SingleOrDefault()
            ?? throw NotFound("legal_entity_not_found", "Юридическое лицо не найдено.");
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        if (request.IsDefault) await ClearDefaultCompanyAsync(connection, transaction, cancellationToken);
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            UPDATE companies SET name = @name, company_type = @type, legal_name = @legal_name,
                inn = @inn, kpp = @kpp, ogrn = @ogrn, address = @address, phone = @phone,
                email = @email, details = details || CAST(@details AS jsonb),
                is_default = @is_default, updated_at = now()
            WHERE id = @id AND deleted_at IS NULL
            """;
        BindLegalEntity(command, id, actorUserId, request);
        if (await command.ExecuteNonQueryAsync(cancellationToken) != 1) throw NotFound("legal_entity_not_found", "Юридическое лицо не найдено.");
        await EnsureDefaultCompanyAsync(connection, transaction, cancellationToken);
        await WriteAuditAsync(connection, transaction, actorUserId, "legal_entity", id, "updated", before, request, cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return (await ReadLegalEntitiesAsync(connection, id, cancellationToken)).Single();
    }

    /// <inheritdoc />
    public async Task DeleteLegalEntityAsync(Guid actorUserId, Guid id, CancellationToken cancellationToken)
    {
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        var before = (await ReadLegalEntitiesAsync(connection, id, cancellationToken)).SingleOrDefault()
            ?? throw NotFound("legal_entity_not_found", "Юридическое лицо не найдено.");
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = "UPDATE companies SET deleted_at = now(), is_default = false, updated_at = now() WHERE id = @id AND deleted_at IS NULL";
        Add(command, "id", id);
        await command.ExecuteNonQueryAsync(cancellationToken);
        await EnsureDefaultCompanyAsync(connection, transaction, cancellationToken);
        await WriteAuditAsync(connection, transaction, actorUserId, "legal_entity", id, "deleted", before, null, cancellationToken);
        await transaction.CommitAsync(cancellationToken);
    }

    /// <inheritdoc />
    public async Task<IReadOnlyList<CompanyClient>> GetClientsAsync(CancellationToken cancellationToken)
    {
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        return await ReadClientsAsync(connection, null, cancellationToken);
    }

    /// <inheritdoc />
    public async Task<CompanyClient> CreateClientAsync(Guid actorUserId, SaveCompanyClientRequest request, CancellationToken cancellationToken)
    {
        var name = Required(request.Name, 2, 200, "client_name_invalid", "Название клиента должно содержать от 2 до 200 символов.");
        ValidateClient(request);
        var id = Guid.NewGuid();
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            INSERT INTO clients (id, name, company_name, contact_name, phone, email, address, details, created_by)
            VALUES (@id, @name, @company, @contact, @phone, @email, @address, CAST(@details AS jsonb), @actor)
            """;
        BindClient(command, id, actorUserId, request with { Name = name });
        await command.ExecuteNonQueryAsync(cancellationToken);
        await WriteAuditAsync(connection, transaction, actorUserId, "client", id, "created", null, request, cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return (await ReadClientsAsync(connection, id, cancellationToken)).Single();
    }

    /// <inheritdoc />
    public async Task<CompanyClient> UpdateClientAsync(Guid actorUserId, Guid id, SaveCompanyClientRequest request, CancellationToken cancellationToken)
    {
        var name = Required(request.Name, 2, 200, "client_name_invalid", "Название клиента должно содержать от 2 до 200 символов.");
        ValidateClient(request);
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        var before = (await ReadClientsAsync(connection, id, cancellationToken)).SingleOrDefault()
            ?? throw NotFound("client_not_found", "Клиент не найден.");
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            UPDATE clients SET name = @name, company_name = @company, contact_name = @contact,
                phone = @phone, email = @email, address = @address,
                details = details || CAST(@details AS jsonb), updated_at = now()
            WHERE id = @id AND deleted_at IS NULL
            """;
        BindClient(command, id, actorUserId, request with { Name = name });
        if (await command.ExecuteNonQueryAsync(cancellationToken) != 1) throw NotFound("client_not_found", "Клиент не найден.");
        await WriteAuditAsync(connection, transaction, actorUserId, "client", id, "updated", before, request, cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return (await ReadClientsAsync(connection, id, cancellationToken)).Single();
    }

    /// <inheritdoc />
    public async Task DeleteClientAsync(Guid actorUserId, Guid id, CancellationToken cancellationToken)
    {
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        var before = (await ReadClientsAsync(connection, id, cancellationToken)).SingleOrDefault()
            ?? throw NotFound("client_not_found", "Клиент не найден.");
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = "UPDATE clients SET deleted_at = now(), updated_at = now() WHERE id = @id AND deleted_at IS NULL";
        Add(command, "id", id);
        await command.ExecuteNonQueryAsync(cancellationToken);
        await WriteAuditAsync(connection, transaction, actorUserId, "client", id, "deleted", before, null, cancellationToken);
        await transaction.CommitAsync(cancellationToken);
    }

    /// <inheritdoc />
    public async Task<IReadOnlyList<EmployeeSummary>> GetEmployeesAsync(CancellationToken cancellationToken)
    {
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        return await ReadEmployeesAsync(connection, null, cancellationToken);
    }

    /// <inheritdoc />
    public async Task<EmployeeSummary> CreateEmployeeAsync(Guid actorUserId, CreateEmployeeRequest request, CancellationToken cancellationToken)
    {
        var login = Required(request.Login, 3, 100, "employee_login_invalid", "Логин должен содержать от 3 до 100 символов.");
        var name = Required(request.DisplayName, 2, 200, "employee_name_invalid", "Имя сотрудника должно содержать от 2 до 200 символов.");
        var password = PasswordPolicy.Validate(request.TemporaryPassword);
        if (!password.IsValid) throw new IdentityException(400, password.ErrorCode!, password.ErrorMessage!);
        var userId = Guid.NewGuid();
        var membershipId = Guid.NewGuid();
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        await ValidateRoleAndSupervisorAsync(connection, transaction, request.RoleId, request.SupervisorMembershipId, null, cancellationToken);
        try
        {
            await using (var user = connection.CreateCommand())
            {
                user.Transaction = transaction;
                user.CommandText = "INSERT INTO public.users (id, login, password_hash, display_name, must_change_password) VALUES (@id, @login, @hash, @name, true)";
                Add(user, "id", userId); Add(user, "login", login);
                Add(user, "hash", _passwordHasher.HashPassword(userId.ToString("N"), request.TemporaryPassword));
                Add(user, "name", name);
                await user.ExecuteNonQueryAsync(cancellationToken);
            }
            await using (var member = connection.CreateCommand())
            {
                member.Transaction = transaction;
                member.CommandText = "INSERT INTO public.organization_members (id, organization_id, user_id, created_by) VALUES (@id, @organization_id, @user_id, @actor)";
                Add(member, "id", membershipId); Add(member, "organization_id", tenantContext.OrganizationId);
                Add(member, "user_id", userId); Add(member, "actor", actorUserId);
                await member.ExecuteNonQueryAsync(cancellationToken);
            }
            await SaveEmployeeTenantDataAsync(connection, transaction, membershipId, actorUserId, request.RoleId, request.SupervisorMembershipId, request.Email, request.Phone, request.Telegram, cancellationToken);
            await WriteAuditAsync(connection, transaction, actorUserId, "employee", membershipId, "created", null, new { userId, login, name, request.RoleId, request.SupervisorMembershipId }, cancellationToken);
            await transaction.CommitAsync(cancellationToken);
        }
        catch (PostgresException exception) when (exception.SqlState == PostgresErrorCodes.UniqueViolation)
        {
            throw new IdentityException(409, "employee_login_exists", "Пользователь с таким логином уже существует.");
        }
        return (await ReadEmployeesAsync(connection, membershipId, cancellationToken)).Single();
    }

    /// <inheritdoc />
    public async Task<EmployeeSummary> UpdateEmployeeAsync(Guid actorUserId, Guid membershipId, UpdateEmployeeRequest request, CancellationToken cancellationToken)
    {
        var name = Required(request.DisplayName, 2, 200, "employee_name_invalid", "Имя сотрудника должно содержать от 2 до 200 символов.");
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        var before = (await ReadEmployeesAsync(connection, membershipId, cancellationToken)).SingleOrDefault()
            ?? throw NotFound("employee_not_found", "Сотрудник не найден.");
        if (before.IsDirector && (!request.IsActive || request.RoleId != before.RoleId))
            throw new IdentityException(409, "director_protected", "Директора нельзя отключить или лишить системной роли.");
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        await ValidateRoleAndSupervisorAsync(connection, transaction, request.RoleId, request.SupervisorMembershipId, membershipId, cancellationToken);
        await using (var user = connection.CreateCommand())
        {
            user.Transaction = transaction;
            user.CommandText = """
                UPDATE public.users AS users SET display_name = @name, is_active = @active, updated_at = now()
                FROM public.organization_members AS member
                WHERE member.id = @membership_id AND member.organization_id = @organization_id
                  AND users.id = member.user_id AND member.deleted_at IS NULL
                """;
            Add(user, "name", name); Add(user, "active", request.IsActive);
            Add(user, "membership_id", membershipId); Add(user, "organization_id", tenantContext.OrganizationId);
            if (await user.ExecuteNonQueryAsync(cancellationToken) != 1) throw NotFound("employee_not_found", "Сотрудник не найден.");
        }
        await using (var member = connection.CreateCommand())
        {
            member.Transaction = transaction;
            member.CommandText = "UPDATE public.organization_members SET is_active = @active, updated_at = now() WHERE id = @id AND organization_id = @organization_id";
            Add(member, "active", request.IsActive); Add(member, "id", membershipId); Add(member, "organization_id", tenantContext.OrganizationId);
            await member.ExecuteNonQueryAsync(cancellationToken);
        }
        await SaveEmployeeTenantDataAsync(connection, transaction, membershipId, actorUserId, request.RoleId, request.SupervisorMembershipId, request.Email, request.Phone, request.Telegram, cancellationToken);
        await WriteAuditAsync(connection, transaction, actorUserId, "employee", membershipId, "updated", before, request, cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return (await ReadEmployeesAsync(connection, membershipId, cancellationToken)).Single();
    }

    /// <inheritdoc />
    public async Task DeleteEmployeeAsync(Guid actorUserId, Guid membershipId, CancellationToken cancellationToken)
    {
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        var before = (await ReadEmployeesAsync(connection, membershipId, cancellationToken)).SingleOrDefault()
            ?? throw NotFound("employee_not_found", "Сотрудник не найден.");
        if (before.IsDirector) throw new IdentityException(409, "director_protected", "Директора нельзя удалить.");
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        await using (var reports = connection.CreateCommand())
        {
            reports.Transaction = transaction;
            reports.CommandText = "DELETE FROM member_reporting WHERE membership_id = @id OR supervisor_membership_id = @id";
            Add(reports, "id", membershipId); await reports.ExecuteNonQueryAsync(cancellationToken);
        }
        await using (var member = connection.CreateCommand())
        {
            member.Transaction = transaction;
            member.CommandText = "UPDATE public.organization_members SET is_active = false, deleted_at = now(), updated_at = now() WHERE id = @id AND organization_id = @organization_id";
            Add(member, "id", membershipId); Add(member, "organization_id", tenantContext.OrganizationId);
            await member.ExecuteNonQueryAsync(cancellationToken);
        }
        await using (var user = connection.CreateCommand())
        {
            user.Transaction = transaction;
            user.CommandText = "UPDATE public.users SET is_active = false, deleted_at = now(), updated_at = now() WHERE id = @user_id";
            Add(user, "user_id", before.UserId); await user.ExecuteNonQueryAsync(cancellationToken);
        }
        await using (var sessions = connection.CreateCommand())
        {
            sessions.Transaction = transaction;
            sessions.CommandText = "UPDATE public.refresh_sessions SET revoked_at = now() WHERE user_id = @user_id AND revoked_at IS NULL";
            Add(sessions, "user_id", before.UserId); await sessions.ExecuteNonQueryAsync(cancellationToken);
        }
        await WriteAuditAsync(connection, transaction, actorUserId, "employee", membershipId, "deleted", before, null, cancellationToken);
        await transaction.CommitAsync(cancellationToken);
    }

    private static async Task<IReadOnlyList<LegalEntity>> ReadLegalEntitiesAsync(DbConnection connection, Guid? id, CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.CommandText = "SELECT id, name, company_type, legal_name, inn, kpp, ogrn, address, phone, email, details, is_default FROM companies WHERE deleted_at IS NULL AND (CAST(@id AS uuid) IS NULL OR id = CAST(@id AS uuid)) ORDER BY is_default DESC, name";
        Add(command, "id", (object?)id ?? DBNull.Value);
        var result = new List<LegalEntity>();
        await using var reader = await command.ExecuteReaderAsync(token);
        while (await reader.ReadAsync(token))
        {
            var details = ReadDetails<LegalEntityDetails>(reader, 10);
            result.Add(new LegalEntity(
                reader.GetGuid(0), reader.GetString(1), reader.GetString(2), Text(reader, 3), Text(reader, 4), Text(reader, 5),
                Text(reader, 6), Text(reader, 7), Text(reader, 8), Text(reader, 9), details.Website, details.DirectorName,
                details.SignatoryName, details.SignatoryTitle, details.BankName, details.BankBik, details.BankAccount,
                details.CorrAccount, details.IntroDefault, details.FooterDefault, reader.GetBoolean(11)));
        }
        return result;
    }

    private static async Task<IReadOnlyList<CompanyClient>> ReadClientsAsync(DbConnection connection, Guid? id, CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.CommandText = "SELECT id, name, company_name, contact_name, phone, email, address, details FROM clients WHERE deleted_at IS NULL AND (CAST(@id AS uuid) IS NULL OR id = CAST(@id AS uuid)) ORDER BY name";
        Add(command, "id", (object?)id ?? DBNull.Value);
        var result = new List<CompanyClient>();
        await using var reader = await command.ExecuteReaderAsync(token);
        while (await reader.ReadAsync(token))
        {
            var details = ReadDetails<ClientDetails>(reader, 7);
            result.Add(new CompanyClient(
                reader.GetGuid(0), reader.GetString(1), details.CompanyType, Text(reader, 2), details.LegalName,
                details.Inn, details.Kpp, details.Ogrn, Text(reader, 3), Text(reader, 4), Text(reader, 5), Text(reader, 6),
                details.ObjectType, details.ObjectAddress, details.RecipientName, details.Salutation, details.ProposalTitle, details.IntroText,
                details.BankName, details.BankBik, details.BankAccount, details.CorrAccount, details.PassportSeries,
                details.PassportNumber, details.PassportIssuedBy, details.Note));
        }
        return result;
    }

    private async Task<IReadOnlyList<EmployeeSummary>> ReadEmployeesAsync(DbConnection connection, Guid? membershipId, CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT member.id, users.id, users.login::text, users.display_name, role.id, role.name,
                   reporting.supervisor_membership_id, member.is_director,
                   member.is_active AND users.is_active, profile.email, profile.phone, profile.telegram,
                   member.created_by, member.created_at, organization.active_until
            FROM public.organization_members AS member
            JOIN public.users AS users ON users.id = member.user_id
            JOIN public.organizations AS organization ON organization.id = member.organization_id
            JOIN member_roles AS member_role ON member_role.membership_id = member.id
            JOIN roles AS role ON role.id = member_role.role_id
            LEFT JOIN member_reporting AS reporting ON reporting.membership_id = member.id
            LEFT JOIN employee_profiles AS profile ON profile.membership_id = member.id
            WHERE member.organization_id = @organization_id AND member.deleted_at IS NULL
              AND users.deleted_at IS NULL
              AND (CAST(@membership_id AS uuid) IS NULL OR member.id = CAST(@membership_id AS uuid))
            ORDER BY member.is_director DESC, users.display_name
            """;
        Add(command, "organization_id", tenantContext.OrganizationId);
        Add(command, "membership_id", (object?)membershipId ?? DBNull.Value);
        var result = new List<EmployeeSummary>();
        await using var reader = await command.ExecuteReaderAsync(token);
        while (await reader.ReadAsync(token)) result.Add(new EmployeeSummary(
            reader.GetGuid(0), reader.GetGuid(1), reader.GetString(2), reader.GetString(3), reader.GetGuid(4), reader.GetString(5),
            reader.IsDBNull(6) ? null : reader.GetGuid(6), reader.GetBoolean(7), reader.GetBoolean(8), Text(reader, 9), Text(reader, 10), Text(reader, 11),
            reader.IsDBNull(12) ? null : reader.GetGuid(12), reader.GetFieldValue<DateTimeOffset>(13), reader.GetFieldValue<DateTimeOffset>(14)));
        return result;
    }

    private async Task ValidateRoleAndSupervisorAsync(DbConnection connection, DbTransaction transaction, Guid roleId, Guid? supervisorId, Guid? employeeId, CancellationToken token)
    {
        await using var role = connection.CreateCommand();
        role.Transaction = transaction;
        role.CommandText = "SELECT EXISTS (SELECT 1 FROM roles WHERE id = @id AND deleted_at IS NULL)";
        Add(role, "id", roleId);
        if (await role.ExecuteScalarAsync(token) is not true) throw new IdentityException(400, "role_invalid", "Выбранная роль не существует.");
        if (!supervisorId.HasValue) return;
        if (supervisorId == employeeId) throw new IdentityException(409, "employee_hierarchy_cycle", "Сотрудник не может быть своим руководителем.");
        await using var supervisor = connection.CreateCommand();
        supervisor.Transaction = transaction;
        supervisor.CommandText = """
            SELECT EXISTS (
                SELECT 1 FROM public.organization_members AS member
                JOIN member_roles AS member_role ON member_role.membership_id = member.id
                JOIN role_subordination AS relation ON relation.supervisor_role_id = member_role.role_id
                WHERE member.id = @supervisor_id AND member.organization_id = @organization_id
                  AND member.is_active AND member.deleted_at IS NULL
                  AND relation.subordinate_role_id = @role_id
            )
            """;
        Add(supervisor, "supervisor_id", supervisorId.Value); Add(supervisor, "organization_id", tenantContext.OrganizationId); Add(supervisor, "role_id", roleId);
        if (await supervisor.ExecuteScalarAsync(token) is not true)
            throw new IdentityException(409, "supervisor_role_invalid", "Роль выбранного руководителя не допускает эту роль сотрудника.");
        if (employeeId.HasValue)
        {
            await using var cycle = connection.CreateCommand();
            cycle.Transaction = transaction;
            cycle.CommandText = """
                WITH RECURSIVE ancestors(id) AS (
                    SELECT supervisor_membership_id FROM member_reporting WHERE membership_id = @supervisor_id
                    UNION
                    SELECT relation.supervisor_membership_id FROM member_reporting AS relation JOIN ancestors ON ancestors.id = relation.membership_id
                )
                SELECT EXISTS (SELECT 1 FROM ancestors WHERE id = @employee_id)
                """;
            Add(cycle, "supervisor_id", supervisorId.Value); Add(cycle, "employee_id", employeeId.Value);
            if (await cycle.ExecuteScalarAsync(token) is true) throw new IdentityException(409, "employee_hierarchy_cycle", "Структура сотрудников не может содержать цикл.");
        }
    }

    private static async Task SaveEmployeeTenantDataAsync(DbConnection connection, DbTransaction transaction, Guid membershipId, Guid actorUserId, Guid roleId, Guid? supervisorId, string? email, string? phone, string? telegram, CancellationToken token)
    {
        await using (var role = connection.CreateCommand())
        {
            role.Transaction = transaction;
            role.CommandText = "INSERT INTO member_roles (membership_id, role_id) VALUES (@member, @role) ON CONFLICT (membership_id) DO UPDATE SET role_id = EXCLUDED.role_id";
            Add(role, "member", membershipId); Add(role, "role", roleId); await role.ExecuteNonQueryAsync(token);
        }
        await using (var reporting = connection.CreateCommand())
        {
            reporting.Transaction = transaction;
            reporting.CommandText = supervisorId.HasValue
                ? "INSERT INTO member_reporting (membership_id, supervisor_membership_id) VALUES (@member, @supervisor) ON CONFLICT (membership_id) DO UPDATE SET supervisor_membership_id = EXCLUDED.supervisor_membership_id"
                : "DELETE FROM member_reporting WHERE membership_id = @member";
            Add(reporting, "member", membershipId);
            if (supervisorId.HasValue) Add(reporting, "supervisor", supervisorId.Value);
            await reporting.ExecuteNonQueryAsync(token);
        }
        await using var profile = connection.CreateCommand();
        profile.Transaction = transaction;
        profile.CommandText = """
            INSERT INTO employee_profiles (membership_id, email, phone, telegram, created_by)
            VALUES (@member, @email, @phone, @telegram, @actor)
            ON CONFLICT (membership_id) DO UPDATE SET email = EXCLUDED.email, phone = EXCLUDED.phone,
                telegram = EXCLUDED.telegram, updated_at = now()
            """;
        Add(profile, "member", membershipId); Add(profile, "email", Db(email)); Add(profile, "phone", Db(phone));
        Add(profile, "telegram", Db(telegram)); Add(profile, "actor", actorUserId); await profile.ExecuteNonQueryAsync(token);
    }

    private static async Task ClearDefaultCompanyAsync(DbConnection connection, DbTransaction transaction, CancellationToken token)
    {
        await using var command = connection.CreateCommand(); command.Transaction = transaction;
        command.CommandText = "UPDATE companies SET is_default = false WHERE is_default AND deleted_at IS NULL";
        await command.ExecuteNonQueryAsync(token);
    }

    private static async Task EnsureDefaultCompanyAsync(DbConnection connection, DbTransaction transaction, CancellationToken token)
    {
        await using var command = connection.CreateCommand(); command.Transaction = transaction;
        command.CommandText = "UPDATE companies SET is_default = true WHERE id = (SELECT id FROM companies WHERE deleted_at IS NULL ORDER BY created_at LIMIT 1) AND NOT EXISTS (SELECT 1 FROM companies WHERE is_default AND deleted_at IS NULL)";
        await command.ExecuteNonQueryAsync(token);
    }

    private static void ValidateLegalEntity(SaveLegalEntityRequest request)
    {
        Required(request.Name, 2, 200, "legal_entity_name_invalid", "Название должно содержать от 2 до 200 символов.");
        var companyType = Required(request.CompanyType, 2, 20, "company_type_invalid", "Выберите тип компании.").ToLowerInvariant();
        if (companyType is not ("ooo" or "ооо" or "ip" or "ип"))
            throw new IdentityException(400, "company_type_invalid", "Допустимые типы компании: ООО или ИП.");
        var isIp = companyType is "ip" or "ип";
        Required(request.LegalName ?? string.Empty, 2, 300, "legal_name_invalid", isIp
            ? "Укажите ФИО индивидуального предпринимателя."
            : "Укажите юридическое название организации.");
        RequiredDigits(request.Inn, isIp ? [12] : [10], isIp
            ? "ИНН ИП должен содержать 12 цифр."
            : "ИНН организации должен содержать 10 цифр.");
        if (!isIp) RequiredDigits(request.Kpp, [9], "КПП должен содержать 9 цифр.");
        RequiredDigits(request.Ogrn, isIp ? [15] : [13], isIp
            ? "ОГРНИП должен содержать 15 цифр."
            : "ОГРН должен содержать 13 цифр.");
        RequiredPhone(request.Phone);
        Email(request.Email);
        Website(request.Website);
        Required(request.DirectorName ?? string.Empty, 2, 300, "director_name_invalid", "Укажите директора.");
        Required(request.SignatoryName ?? string.Empty, 2, 300, "signatory_name_invalid", "Укажите подписанта.");
        Required(request.SignatoryTitle ?? string.Empty, 2, 200, "signatory_title_invalid", "Укажите должность подписанта.");
        Required(request.BankName ?? string.Empty, 2, 300, "bank_name_invalid", "Укажите банк.");
        RequiredDigits(request.BankBik, [9], "БИК должен содержать 9 цифр.");
        RequiredDigits(request.BankAccount, [20], "Расчётный счёт должен содержать 20 цифр.");
        RequiredDigits(request.CorrAccount, [20], "Корреспондентский счёт должен содержать 20 цифр.");
    }

    private static void BindLegalEntity(DbCommand command, Guid id, Guid actor, SaveLegalEntityRequest request)
    {
        Add(command, "id", id); Add(command, "actor", actor); Add(command, "name", request.Name.Trim());
        Add(command, "type", request.CompanyType.Trim()); Add(command, "legal_name", Db(request.LegalName));
        Add(command, "inn", Db(request.Inn)); Add(command, "kpp", Db(request.Kpp)); Add(command, "ogrn", Db(request.Ogrn));
        Add(command, "address", Db(request.Address)); Add(command, "phone", Db(request.Phone)); Add(command, "email", Db(request.Email));
        Add(command, "details", JsonSerializer.Serialize(new LegalEntityDetails
        {
            Website = request.Website, DirectorName = request.DirectorName, SignatoryName = request.SignatoryName,
            SignatoryTitle = request.SignatoryTitle, BankName = request.BankName, BankBik = request.BankBik,
            BankAccount = request.BankAccount, CorrAccount = request.CorrAccount,
            IntroDefault = request.IntroDefault, FooterDefault = request.FooterDefault,
        }, JsonOptions));
        Add(command, "is_default", request.IsDefault);
    }

    private static void BindClient(DbCommand command, Guid id, Guid actor, SaveCompanyClientRequest request)
    {
        Add(command, "id", id); Add(command, "actor", actor); Add(command, "name", request.Name.Trim());
        Add(command, "company", Db(request.CompanyName)); Add(command, "contact", Db(request.ContactName));
        Add(command, "phone", Db(request.Phone)); Add(command, "email", Db(request.Email)); Add(command, "address", Db(request.Address));
        Add(command, "details", JsonSerializer.Serialize(new ClientDetails
        {
            CompanyType = NormalizePartyType(request.CompanyType), LegalName = request.LegalName, Inn = request.Inn,
            Kpp = request.Kpp, Ogrn = request.Ogrn, ObjectType = request.ObjectType, ObjectAddress = request.ObjectAddress,
            RecipientName = request.RecipientName,
            Salutation = request.Salutation, ProposalTitle = request.ProposalTitle, IntroText = request.IntroText,
            BankName = request.BankName, BankBik = request.BankBik, BankAccount = request.BankAccount,
            CorrAccount = request.CorrAccount, PassportSeries = request.PassportSeries,
            PassportNumber = request.PassportNumber, PassportIssuedBy = request.PassportIssuedBy, Note = request.Note,
        }, JsonOptions));
    }

    private static void ValidateClient(SaveCompanyClientRequest request)
    {
        var type = NormalizePartyType(request.CompanyType);
        Required(request.CompanyName ?? string.Empty, 2, 300, "client_party_name_invalid", type == "person"
            ? "Укажите ФИО клиента."
            : "Укажите название клиента.");
        RequiredPhone(request.Phone);
        Email(request.Email);
        if (type == "person")
        {
            RequiredDigits(request.PassportSeries, [4], "Серия паспорта должна содержать 4 цифры.");
            RequiredDigits(request.PassportNumber, [6], "Номер паспорта должен содержать 6 цифр.");
            Required(request.PassportIssuedBy ?? string.Empty, 2, 500, "passport_issuer_invalid", "Укажите, кем выдан паспорт.");
            return;
        }
        Required(request.LegalName ?? string.Empty, 2, 300, "client_legal_name_invalid", "Укажите юридическое название клиента.");
        RequiredDigits(request.Inn, type == "ip" ? [12] : [10], type == "ip" ? "ИНН ИП должен содержать 12 цифр." : "ИНН организации должен содержать 10 цифр.");
        RequiredDigits(request.Ogrn, type == "ip" ? [15] : [13], type == "ip" ? "ОГРНИП должен содержать 15 цифр." : "ОГРН должен содержать 13 цифр.");
        if (type != "ip") RequiredDigits(request.Kpp, [9], "КПП должен содержать 9 цифр.");
        Required(request.BankName ?? string.Empty, 2, 300, "client_bank_name_invalid", "Укажите банк клиента.");
        RequiredDigits(request.BankBik, [9], "БИК должен содержать 9 цифр.");
        RequiredDigits(request.BankAccount, [20], "Расчётный счёт должен содержать 20 цифр.");
        RequiredDigits(request.CorrAccount, [20], "Корреспондентский счёт должен содержать 20 цифр.");
    }

    private static string NormalizePartyType(string? value) => value?.Trim().ToLowerInvariant() switch
    {
        "ип" or "ip" => "ip",
        "физлицо" or "физическое лицо" or "person" => "person",
        _ => "ooo",
    };

    private static T ReadDetails<T>(DbDataReader reader, int ordinal) where T : new()
    {
        if (reader.IsDBNull(ordinal)) return new T();
        try
        {
            return JsonSerializer.Deserialize<T>(reader.GetString(ordinal), JsonOptions) ?? new T();
        }
        catch (JsonException)
        {
            return new T();
        }
    }

    private sealed class LegalEntityDetails
    {
        public string? Website { get; init; }
        public string? DirectorName { get; init; }
        public string? SignatoryName { get; init; }
        public string? SignatoryTitle { get; init; }
        public string? BankName { get; init; }
        public string? BankBik { get; init; }
        public string? BankAccount { get; init; }
        public string? CorrAccount { get; init; }
        public string? IntroDefault { get; init; }
        public string? FooterDefault { get; init; }
    }

    private sealed class ClientDetails
    {
        public string CompanyType { get; init; } = "person";
        public string? LegalName { get; init; }
        public string? Inn { get; init; }
        public string? Kpp { get; init; }
        public string? Ogrn { get; init; }
        public string? ObjectType { get; init; }
        public string? ObjectAddress { get; init; }
        public string? RecipientName { get; init; }
        public string? Salutation { get; init; }
        public string? ProposalTitle { get; init; }
        public string? IntroText { get; init; }
        public string? BankName { get; init; }
        public string? BankBik { get; init; }
        public string? BankAccount { get; init; }
        public string? CorrAccount { get; init; }
        public string? PassportSeries { get; init; }
        public string? PassportNumber { get; init; }
        public string? PassportIssuedBy { get; init; }
        public string? Note { get; init; }
    }

    private static async Task WriteAuditAsync(DbConnection connection, DbTransaction transaction, Guid actor, string entityType, Guid entityId, string action, object? before, object? after, CancellationToken token)
    {
        await using var command = connection.CreateCommand(); command.Transaction = transaction;
        command.CommandText = "INSERT INTO audit_log (actor_user_id, entity_type, entity_id, action, diff) VALUES (@actor, @type, @id, @action, CAST(@diff AS jsonb))";
        Add(command, "actor", actor); Add(command, "type", entityType); Add(command, "id", entityId); Add(command, "action", action);
        Add(command, "diff", JsonSerializer.Serialize(new { before, after }, JsonOptions)); await command.ExecuteNonQueryAsync(token);
    }

    private static string Required(string value, int minimum, int maximum, string code, string message)
    {
        var normalized = value.Trim();
        if (normalized.Length < minimum || normalized.Length > maximum) throw new IdentityException(400, code, message);
        return normalized;
    }

    private static void Digits(string? value, int[] lengths, string message)
    {
        var normalized = value?.Trim();
        if (string.IsNullOrEmpty(normalized)) return;
        if (!normalized.All(char.IsDigit) || !lengths.Contains(normalized.Length)) throw new IdentityException(400, "company_requisite_invalid", message);
    }

    private static void RequiredDigits(string? value, int[] lengths, string message)
    {
        if (string.IsNullOrWhiteSpace(value))
            throw new IdentityException(400, "company_requisite_required", message);
        Digits(value, lengths, message);
    }

    private static void Phone(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return;
        var digits = new string(value.Where(char.IsDigit).ToArray());
        if (digits.Length != 11 || digits[0] is not ('7' or '8'))
            throw new IdentityException(400, "phone_invalid", "Телефон должен соответствовать формату +7 (999) 123-45-67.");
    }

    private static void RequiredPhone(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
            throw new IdentityException(400, "phone_required", "Укажите телефон.");
        Phone(value);
    }

    private static void Email(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return;
        var normalized = value.Trim();
        if (normalized.Length > 254 || !MailAddress.TryCreate(normalized, out var address) || address.Address != normalized)
            throw new IdentityException(400, "email_invalid", "Введите корректный email.");
    }

    private static void Website(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return;
        if (!Uri.TryCreate(value.Trim(), UriKind.Absolute, out var uri) ||
            uri.Scheme is not ("http" or "https") || string.IsNullOrWhiteSpace(uri.Host))
            throw new IdentityException(400, "website_invalid", "Адрес сайта должен начинаться с http:// или https://.");
    }

    private static string? Text(DbDataReader reader, int ordinal) => reader.IsDBNull(ordinal) ? null : reader.GetString(ordinal);
    private static object Db(string? value) => string.IsNullOrWhiteSpace(value) ? DBNull.Value : value.Trim();
    private static IdentityException NotFound(string code, string message) => new(404, code, message);
    private static void Add(DbCommand command, string name, object value)
    {
        var parameter = command.CreateParameter(); parameter.ParameterName = name; parameter.Value = value; command.Parameters.Add(parameter);
    }
}
