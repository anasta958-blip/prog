using System.Data.Common;
using System.Globalization;
using Npgsql;
using SkladKomforta.Application.Abstractions.Persistence;
using SkladKomforta.Application.Abstractions.Tenancy;
using SkladKomforta.Application.Authorization;
using SkladKomforta.Application.Identity;

namespace SkladKomforta.Infrastructure.Authorization;

/// <summary>Управляет ролями только в схеме текущей организации.</summary>
internal sealed class PostgresRoleAdministrationService(
    IDatabaseConnectionFactory connectionFactory,
    ITenantContext tenantContext) : IRoleAdministrationService
{
    /// <inheritdoc />
    public async Task<IReadOnlyList<PermissionSummary>> GetPermissionsAsync(CancellationToken cancellationToken)
    {
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandText = "SELECT code, name, group_name FROM permissions WHERE code <> 'system.full_access' ORDER BY group_name, name";
        var result = new List<PermissionSummary>();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            result.Add(new PermissionSummary(reader.GetString(0), reader.GetString(1), reader.GetString(2)));
        }
        return result;
    }

    /// <inheritdoc />
    public async Task<IReadOnlyList<RoleSummary>> GetRolesAsync(CancellationToken cancellationToken)
    {
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        return await ReadRolesAsync(connection, null, cancellationToken);
    }

    /// <inheritdoc />
    public async Task<IReadOnlyList<MemberAccessSummary>> GetMembersAsync(CancellationToken cancellationToken)
    {
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT member.id, member.user_id, users.display_name, member.is_director,
                   member_role.role_id, reporting.supervisor_membership_id
            FROM public.organization_members AS member
            JOIN public.users AS users ON users.id = member.user_id
            LEFT JOIN member_roles AS member_role ON member_role.membership_id = member.id
            LEFT JOIN member_reporting AS reporting ON reporting.membership_id = member.id
            WHERE member.organization_id = @organization_id
              AND member.is_active AND member.deleted_at IS NULL
              AND users.is_active AND users.deleted_at IS NULL
            ORDER BY users.display_name, member_role.role_id
            """;
        AddParameter(command, "organization_id", tenantContext.OrganizationId);
        var members = new List<MemberAccessSummary>();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            members.Add(new MemberAccessSummary(
                reader.GetGuid(0), reader.GetGuid(1), reader.GetString(2), reader.GetBoolean(3),
                reader.IsDBNull(4) ? null : reader.GetGuid(4),
                reader.IsDBNull(5) ? null : reader.GetGuid(5)));
        }
        return members;
    }

    /// <inheritdoc />
    public async Task<RoleSummary> CreateRoleAsync(Guid actorUserId, SaveRoleRequest request, CancellationToken cancellationToken)
    {
        var name = ValidateName(request.Name);
        var visibilityMode = ValidateVisibilityMode(request.CardVisibilityMode);
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        var id = Guid.NewGuid();
        await using (var command = connection.CreateCommand())
        {
            command.Transaction = transaction;
            command.CommandText = "INSERT INTO roles (id, name, is_system, card_visibility_mode) VALUES (@id, @name, false, @visibility_mode)";
            AddParameter(command, "id", id);
            AddParameter(command, "name", name);
            AddParameter(command, "visibility_mode", visibilityMode);
            await ExecuteWithConflictMappingAsync(command, cancellationToken);
        }
        await ReplacePermissionsAsync(connection, transaction, id, request.PermissionCodes, cancellationToken);
        await ReplaceSubordinateRolesAsync(connection, transaction, id, request.SubordinateRoleIds, cancellationToken);
        await ReplaceVisibilityMembersAsync(connection, transaction, id, visibilityMode, request.CardVisibilityMembershipIds, cancellationToken);
        await WriteAuditAsync(connection, transaction, actorUserId, "role", id, "created", null, request, cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return (await ReadRolesAsync(connection, id, cancellationToken)).Single();
    }

    /// <inheritdoc />
    public async Task<RoleSummary> UpdateRoleAsync(Guid actorUserId, Guid roleId, SaveRoleRequest request, CancellationToken cancellationToken)
    {
        var name = ValidateName(request.Name);
        var visibilityMode = ValidateVisibilityMode(request.CardVisibilityMode);
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        var before = (await ReadRolesAsync(connection, roleId, cancellationToken)).SingleOrDefault()
            ?? throw new IdentityException(404, "role_not_found", "Роль не найдена.");
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        await using (var command = connection.CreateCommand())
        {
            command.Transaction = transaction;
            command.CommandText = "UPDATE roles SET name = @name, card_visibility_mode = @visibility_mode, updated_at = now() WHERE id = @id AND NOT is_system AND deleted_at IS NULL";
            AddParameter(command, "name", name);
            AddParameter(command, "visibility_mode", visibilityMode);
            AddParameter(command, "id", roleId);
            if (await ExecuteWithConflictMappingAsync(command, cancellationToken) != 1)
                throw new IdentityException(409, "system_role_readonly", "Системную роль нельзя изменять.");
        }
        await ReplacePermissionsAsync(connection, transaction, roleId, request.PermissionCodes, cancellationToken);
        await ReplaceSubordinateRolesAsync(connection, transaction, roleId, request.SubordinateRoleIds, cancellationToken);
        await ReplaceVisibilityMembersAsync(connection, transaction, roleId, visibilityMode, request.CardVisibilityMembershipIds, cancellationToken);
        await WriteAuditAsync(connection, transaction, actorUserId, "role", roleId, "updated", before, request, cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return (await ReadRolesAsync(connection, roleId, cancellationToken)).Single();
    }

    /// <inheritdoc />
    public async Task DeleteRoleAsync(Guid actorUserId, Guid roleId, CancellationToken cancellationToken)
    {
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        var before = (await ReadRolesAsync(connection, roleId, cancellationToken)).SingleOrDefault()
            ?? throw new IdentityException(404, "role_not_found", "Роль не найдена.");
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        await using (var usage = connection.CreateCommand())
        {
            usage.Transaction = transaction;
            usage.CommandText = "SELECT EXISTS (SELECT 1 FROM member_roles WHERE role_id = @id)";
            AddParameter(usage, "id", roleId);
            if (await usage.ExecuteScalarAsync(cancellationToken) is true)
                throw new IdentityException(409, "role_in_use", "Нельзя удалить роль, назначенную сотрудникам.");
        }
        await using (var hierarchy = connection.CreateCommand())
        {
            hierarchy.Transaction = transaction;
            hierarchy.CommandText = "DELETE FROM role_subordination WHERE supervisor_role_id = @id OR subordinate_role_id = @id";
            AddParameter(hierarchy, "id", roleId);
            await hierarchy.ExecuteNonQueryAsync(cancellationToken);
        }
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = "UPDATE roles SET deleted_at = now(), updated_at = now() WHERE id = @id AND NOT is_system AND deleted_at IS NULL";
        AddParameter(command, "id", roleId);
        if (await command.ExecuteNonQueryAsync(cancellationToken) != 1)
            throw new IdentityException(409, "system_role_readonly", "Системную роль нельзя удалить.");
        await WriteAuditAsync(connection, transaction, actorUserId, "role", roleId, "deleted", before, null, cancellationToken);
        await transaction.CommitAsync(cancellationToken);
    }

    /// <inheritdoc />
    public async Task AssignMemberAccessAsync(Guid actorUserId, Guid membershipId, AssignMemberAccessRequest request, CancellationToken cancellationToken)
    {
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        var before = (await GetMembersAsync(cancellationToken)).SingleOrDefault(member => member.MembershipId == membershipId);
        await EnsureMemberAndRolesExistAsync(connection, transaction, membershipId, [request.RoleId], cancellationToken);
        await EnsureReportingIsValidAsync(connection, transaction, membershipId, request.RoleId, request.SupervisorMembershipId, cancellationToken);
        await using (var delete = connection.CreateCommand())
        {
            delete.Transaction = transaction;
            delete.CommandText = "DELETE FROM member_roles WHERE membership_id = @membership_id";
            AddParameter(delete, "membership_id", membershipId);
            await delete.ExecuteNonQueryAsync(cancellationToken);
        }
        await using (var insert = connection.CreateCommand())
        {
            insert.Transaction = transaction;
            insert.CommandText = "INSERT INTO member_roles (membership_id, role_id) VALUES (@membership_id, @role_id)";
            AddParameter(insert, "membership_id", membershipId);
            AddParameter(insert, "role_id", request.RoleId);
            await insert.ExecuteNonQueryAsync(cancellationToken);
        }
        await using (var reporting = connection.CreateCommand())
        {
            reporting.Transaction = transaction;
            reporting.CommandText = request.SupervisorMembershipId.HasValue
                ? "INSERT INTO member_reporting (membership_id, supervisor_membership_id) VALUES (@membership_id, @supervisor_id) ON CONFLICT (membership_id) DO UPDATE SET supervisor_membership_id = EXCLUDED.supervisor_membership_id"
                : "DELETE FROM member_reporting WHERE membership_id = @membership_id";
            AddParameter(reporting, "membership_id", membershipId);
            if (request.SupervisorMembershipId.HasValue)
                AddParameter(reporting, "supervisor_id", request.SupervisorMembershipId.Value);
            await reporting.ExecuteNonQueryAsync(cancellationToken);
        }
        await WriteAuditAsync(connection, transaction, actorUserId, "employee_access", membershipId, "updated", before, request, cancellationToken);
        await transaction.CommitAsync(cancellationToken);
    }

    private static async Task<IReadOnlyList<RoleSummary>> ReadRolesAsync(DbConnection connection, Guid? roleId, CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        var roleFilter = roleId.HasValue ? "AND role.id = @role_id" : string.Empty;
        command.CommandText = $"""
            SELECT role.id, role.name, role.is_system, permission.code,
                   hierarchy.subordinate_role_id, role.card_visibility_mode,
                   visibility.membership_id
            FROM roles AS role
            LEFT JOIN role_permissions AS role_permission ON role_permission.role_id = role.id
            LEFT JOIN permissions AS permission ON permission.id = role_permission.permission_id
            LEFT JOIN role_subordination AS hierarchy ON hierarchy.supervisor_role_id = role.id
            LEFT JOIN role_card_visibility_members AS visibility ON visibility.role_id = role.id
            WHERE role.deleted_at IS NULL
            {roleFilter}
            ORDER BY role.is_system DESC, role.name, permission.code
            """;
        if (roleId.HasValue) AddParameter(command, "role_id", roleId.Value);
        var roles = new Dictionary<Guid, MutableRole>();
        await using var reader = await command.ExecuteReaderAsync(token);
        while (await reader.ReadAsync(token))
        {
            var id = reader.GetGuid(0);
            if (!roles.TryGetValue(id, out var role))
            {
                role = new MutableRole(
                    id, reader.GetString(1), reader.GetBoolean(2), reader.GetString(5));
                roles.Add(id, role);
            }
            if (!reader.IsDBNull(3) && !role.PermissionCodes.Contains(reader.GetString(3))) role.PermissionCodes.Add(reader.GetString(3));
            if (!reader.IsDBNull(4) && !role.SubordinateRoleIds.Contains(reader.GetGuid(4))) role.SubordinateRoleIds.Add(reader.GetGuid(4));
            if (!reader.IsDBNull(6) && !role.CardVisibilityMembershipIds.Contains(reader.GetGuid(6))) role.CardVisibilityMembershipIds.Add(reader.GetGuid(6));
        }
        return roles.Values.Select(role => role.ToSummary()).ToArray();
    }

    private static async Task ReplaceSubordinateRolesAsync(
        DbConnection connection,
        DbTransaction transaction,
        Guid roleId,
        IReadOnlyList<Guid> requestedRoleIds,
        CancellationToken token)
    {
        var subordinateIds = requestedRoleIds.Distinct().ToArray();
        if (subordinateIds.Contains(roleId))
            throw new IdentityException(400, "role_hierarchy_invalid", "Роль не может подчиняться сама себе.");
        await using (var validate = connection.CreateCommand())
        {
            validate.Transaction = transaction;
            validate.CommandText = "SELECT count(*) FROM roles WHERE id = ANY(@ids) AND NOT is_system AND deleted_at IS NULL";
            AddParameter(validate, "ids", subordinateIds);
            if (Convert.ToInt32(await validate.ExecuteScalarAsync(token), CultureInfo.InvariantCulture) != subordinateIds.Length)
                throw new IdentityException(400, "role_invalid", "Подчинёнными могут быть только пользовательские роли.");
        }
        await using (var delete = connection.CreateCommand())
        {
            delete.Transaction = transaction;
            delete.CommandText = "DELETE FROM role_subordination WHERE supervisor_role_id = @role_id";
            AddParameter(delete, "role_id", roleId);
            await delete.ExecuteNonQueryAsync(token);
        }
        foreach (var subordinateId in subordinateIds)
        {
            await using var cycle = connection.CreateCommand();
            cycle.Transaction = transaction;
            cycle.CommandText = """
                WITH RECURSIVE descendants(id) AS (
                    SELECT subordinate_role_id FROM role_subordination WHERE supervisor_role_id = @subordinate_id
                    UNION
                    SELECT relation.subordinate_role_id
                    FROM role_subordination AS relation
                    JOIN descendants ON descendants.id = relation.supervisor_role_id
                )
                SELECT EXISTS (SELECT 1 FROM descendants WHERE id = @role_id)
                """;
            AddParameter(cycle, "subordinate_id", subordinateId);
            AddParameter(cycle, "role_id", roleId);
            if (await cycle.ExecuteScalarAsync(token) is true)
                throw new IdentityException(409, "role_hierarchy_cycle", "Иерархия ролей не может содержать цикл.");
            await using var insert = connection.CreateCommand();
            insert.Transaction = transaction;
            insert.CommandText = "INSERT INTO role_subordination (supervisor_role_id, subordinate_role_id) VALUES (@role_id, @subordinate_id)";
            AddParameter(insert, "role_id", roleId);
            AddParameter(insert, "subordinate_id", subordinateId);
            await insert.ExecuteNonQueryAsync(token);
        }
    }

    private async Task EnsureReportingIsValidAsync(
        DbConnection connection,
        DbTransaction transaction,
        Guid membershipId,
        Guid roleId,
        Guid? supervisorMembershipId,
        CancellationToken token)
    {
        if (!supervisorMembershipId.HasValue) return;
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            SELECT EXISTS (
                SELECT 1
                FROM public.organization_members AS supervisor
                JOIN member_roles AS supervisor_role ON supervisor_role.membership_id = supervisor.id
                JOIN role_subordination AS relation
                  ON relation.supervisor_role_id = supervisor_role.role_id
                 AND relation.subordinate_role_id = @role_id
                WHERE supervisor.id = @supervisor_id
                  AND supervisor.organization_id = @organization_id
                  AND supervisor.is_active AND supervisor.deleted_at IS NULL
            ), EXISTS (
                WITH RECURSIVE ancestors(id) AS (
                    SELECT supervisor_membership_id FROM member_reporting WHERE membership_id = @supervisor_id
                    UNION
                    SELECT relation.supervisor_membership_id
                    FROM member_reporting AS relation
                    JOIN ancestors ON ancestors.id = relation.membership_id
                )
                SELECT 1 FROM ancestors WHERE id = @membership_id
            )
            """;
        AddParameter(command, "role_id", roleId);
        AddParameter(command, "supervisor_id", supervisorMembershipId.Value);
        AddParameter(command, "organization_id", tenantContext.OrganizationId);
        AddParameter(command, "membership_id", membershipId);
        await using var reader = await command.ExecuteReaderAsync(token);
        await reader.ReadAsync(token);
        if (!reader.GetBoolean(0))
            throw new IdentityException(409, "supervisor_role_invalid", "Роль руководителя не может управлять выбранной ролью сотрудника.");
        if (reader.GetBoolean(1))
            throw new IdentityException(409, "employee_hierarchy_cycle", "Структура сотрудников не может содержать цикл.");
    }

    private static async Task ReplacePermissionsAsync(DbConnection connection, DbTransaction transaction, Guid roleId, IReadOnlyList<string> requestedCodes, CancellationToken token)
    {
        var codes = requestedCodes.Where(code => !string.IsNullOrWhiteSpace(code)).Select(code => code.Trim()).Distinct(StringComparer.Ordinal).ToArray();
        await using (var delete = connection.CreateCommand())
        {
            delete.Transaction = transaction;
            delete.CommandText = "DELETE FROM role_permissions WHERE role_id = @role_id";
            AddParameter(delete, "role_id", roleId);
            await delete.ExecuteNonQueryAsync(token);
        }
        if (codes.Length == 0) return;
        await using var insert = connection.CreateCommand();
        insert.Transaction = transaction;
        insert.CommandText = "INSERT INTO role_permissions (role_id, permission_id) SELECT @role_id, id FROM permissions WHERE code = ANY(@codes) AND code <> 'system.full_access'";
        AddParameter(insert, "role_id", roleId);
        AddParameter(insert, "codes", codes);
        if (await insert.ExecuteNonQueryAsync(token) != codes.Length)
            throw new IdentityException(400, "permission_invalid", "Один или несколько кодов прав не существуют.");
    }

    private async Task ReplaceVisibilityMembersAsync(
        DbConnection connection,
        DbTransaction transaction,
        Guid roleId,
        string visibilityMode,
        IReadOnlyList<Guid>? requestedMembershipIds,
        CancellationToken token)
    {
        var membershipIds = visibilityMode == "specific"
            ? (requestedMembershipIds ?? []).Distinct().ToArray()
            : [];
        if (membershipIds.Length > 0)
        {
            await using var validate = connection.CreateCommand();
            validate.Transaction = transaction;
            validate.CommandText = """
                SELECT count(*)
                FROM public.organization_members
                WHERE id = ANY(@ids) AND organization_id = @organization_id
                  AND is_active AND deleted_at IS NULL
                """;
            AddParameter(validate, "ids", membershipIds);
            AddParameter(validate, "organization_id", tenantContext.OrganizationId);
            if (Convert.ToInt32(await validate.ExecuteScalarAsync(token), CultureInfo.InvariantCulture) != membershipIds.Length)
                throw new IdentityException(400, "card_visibility_member_invalid", "Один или несколько выбранных сотрудников недоступны.");
        }

        await using (var delete = connection.CreateCommand())
        {
            delete.Transaction = transaction;
            delete.CommandText = "DELETE FROM role_card_visibility_members WHERE role_id = @role_id";
            AddParameter(delete, "role_id", roleId);
            await delete.ExecuteNonQueryAsync(token);
        }
        if (membershipIds.Length == 0) return;
        await using var insert = connection.CreateCommand();
        insert.Transaction = transaction;
        insert.CommandText = """
            INSERT INTO role_card_visibility_members (role_id, membership_id)
            SELECT @role_id, unnest(@membership_ids)
            """;
        AddParameter(insert, "role_id", roleId);
        AddParameter(insert, "membership_ids", membershipIds);
        await insert.ExecuteNonQueryAsync(token);
    }

    private async Task EnsureMemberAndRolesExistAsync(DbConnection connection, DbTransaction transaction, Guid membershipId, Guid[] roleIds, CancellationToken token)
    {
        await using var member = connection.CreateCommand();
        member.Transaction = transaction;
        member.CommandText = "SELECT is_director FROM public.organization_members WHERE id = @id AND organization_id = @organization_id AND is_active AND deleted_at IS NULL";
        AddParameter(member, "id", membershipId);
        AddParameter(member, "organization_id", tenantContext.OrganizationId);
        var directorValue = await member.ExecuteScalarAsync(token);
        if (directorValue is null)
            throw new IdentityException(404, "member_not_found", "Сотрудник не найден.");
        if (directorValue is true)
        {
            await using var directorRole = connection.CreateCommand();
            directorRole.Transaction = transaction;
            directorRole.CommandText = "SELECT id FROM roles WHERE name = 'Директор' AND is_system AND deleted_at IS NULL";
            var requiredRoleId = (Guid)(await directorRole.ExecuteScalarAsync(token)
                ?? throw new IdentityException(409, "director_role_missing", "Системная роль директора не найдена."));
            if (!roleIds.Contains(requiredRoleId))
                throw new IdentityException(409, "director_role_required", "У директора нельзя отозвать системную роль директора.");
        }
        if (roleIds.Length == 0) return;
        await using var roles = connection.CreateCommand();
        roles.Transaction = transaction;
        roles.CommandText = "SELECT count(*) FROM roles WHERE id = ANY(@ids) AND deleted_at IS NULL";
        AddParameter(roles, "ids", roleIds);
        if (Convert.ToInt32(await roles.ExecuteScalarAsync(token), CultureInfo.InvariantCulture) != roleIds.Length)
            throw new IdentityException(400, "role_invalid", "Одна или несколько ролей не существуют.");
    }

    private static string ValidateName(string value)
    {
        var name = value.Trim();
        if (name.Length is < 2 or > 100)
            throw new IdentityException(400, "role_name_invalid", "Название роли должно содержать от 2 до 100 символов.");
        return name;
    }

    private static string ValidateVisibilityMode(string value)
    {
        var mode = value.Trim().ToLowerInvariant();
        return mode is "own" or "all" or "subordinates" or "specific"
            ? mode
            : throw new IdentityException(400, "card_visibility_mode_invalid", "Выбран неизвестный режим видимости карточек.");
    }

    private static async Task<int> ExecuteWithConflictMappingAsync(DbCommand command, CancellationToken token)
    {
        try { return await command.ExecuteNonQueryAsync(token); }
        catch (PostgresException exception) when (exception.SqlState == PostgresErrorCodes.UniqueViolation)
        {
            throw new IdentityException(409, "role_name_exists", "Роль с таким названием уже существует.");
        }
    }

    private static async Task WriteAuditAsync(
        DbConnection connection,
        DbTransaction transaction,
        Guid actorUserId,
        string entityType,
        Guid entityId,
        string action,
        object? before,
        object? after,
        CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        var diff = AuditChanges.Serialize(before, after);
        if (diff is null) return;
        command.CommandText = "INSERT INTO audit_log (actor_user_id, entity_type, entity_id, action, diff) VALUES (@actor, @type, @id, @action, CAST(@diff AS jsonb))";
        AddParameter(command, "actor", actorUserId);
        AddParameter(command, "type", entityType);
        AddParameter(command, "id", entityId);
        AddParameter(command, "action", action);
        AddParameter(command, "diff", diff);
        await command.ExecuteNonQueryAsync(token);
    }

    private static void AddParameter(DbCommand command, string name, object value)
    {
        var parameter = command.CreateParameter();
        parameter.ParameterName = name;
        parameter.Value = value;
        command.Parameters.Add(parameter);
    }

    private sealed class MutableRole(Guid id, string name, bool isSystem, string cardVisibilityMode)
    {
        public List<string> PermissionCodes { get; } = [];
        public List<Guid> SubordinateRoleIds { get; } = [];
        public List<Guid> CardVisibilityMembershipIds { get; } = [];
        public RoleSummary ToSummary() => new(
            id, name, isSystem, PermissionCodes, SubordinateRoleIds,
            cardVisibilityMode, CardVisibilityMembershipIds);
    }
}
