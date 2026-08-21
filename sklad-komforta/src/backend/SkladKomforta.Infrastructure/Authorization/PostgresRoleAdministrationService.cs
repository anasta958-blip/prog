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
            SELECT member.id, member.user_id, users.display_name, member.is_director, member_role.role_id
            FROM public.organization_members AS member
            JOIN public.users AS users ON users.id = member.user_id
            LEFT JOIN member_roles AS member_role ON member_role.membership_id = member.id
            WHERE member.organization_id = @organization_id
              AND member.is_active AND member.deleted_at IS NULL
              AND users.is_active AND users.deleted_at IS NULL
            ORDER BY users.display_name, member_role.role_id
            """;
        AddParameter(command, "organization_id", tenantContext.OrganizationId);
        var members = new Dictionary<Guid, MutableMember>();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            var id = reader.GetGuid(0);
            if (!members.TryGetValue(id, out var member))
            {
                member = new MutableMember(id, reader.GetGuid(1), reader.GetString(2), reader.GetBoolean(3));
                members.Add(id, member);
            }
            if (!reader.IsDBNull(4)) member.RoleIds.Add(reader.GetGuid(4));
        }
        return members.Values.Select(member => member.ToSummary()).ToArray();
    }

    /// <inheritdoc />
    public async Task<RoleSummary> CreateRoleAsync(SaveRoleRequest request, CancellationToken cancellationToken)
    {
        var name = ValidateName(request.Name);
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        var id = Guid.NewGuid();
        await using (var command = connection.CreateCommand())
        {
            command.Transaction = transaction;
            command.CommandText = "INSERT INTO roles (id, name, is_system) VALUES (@id, @name, false)";
            AddParameter(command, "id", id);
            AddParameter(command, "name", name);
            await ExecuteWithConflictMappingAsync(command, cancellationToken);
        }
        await ReplacePermissionsAsync(connection, transaction, id, request.PermissionCodes, cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return (await ReadRolesAsync(connection, id, cancellationToken)).Single();
    }

    /// <inheritdoc />
    public async Task<RoleSummary> UpdateRoleAsync(Guid roleId, SaveRoleRequest request, CancellationToken cancellationToken)
    {
        var name = ValidateName(request.Name);
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        await using (var command = connection.CreateCommand())
        {
            command.Transaction = transaction;
            command.CommandText = "UPDATE roles SET name = @name, updated_at = now() WHERE id = @id AND NOT is_system AND deleted_at IS NULL";
            AddParameter(command, "name", name);
            AddParameter(command, "id", roleId);
            if (await ExecuteWithConflictMappingAsync(command, cancellationToken) != 1)
                throw new IdentityException(409, "system_role_readonly", "Системную роль нельзя изменять.");
        }
        await ReplacePermissionsAsync(connection, transaction, roleId, request.PermissionCodes, cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return (await ReadRolesAsync(connection, roleId, cancellationToken)).Single();
    }

    /// <inheritdoc />
    public async Task DeleteRoleAsync(Guid roleId, CancellationToken cancellationToken)
    {
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandText = "UPDATE roles SET deleted_at = now(), updated_at = now() WHERE id = @id AND NOT is_system AND deleted_at IS NULL";
        AddParameter(command, "id", roleId);
        if (await command.ExecuteNonQueryAsync(cancellationToken) != 1)
            throw new IdentityException(409, "system_role_readonly", "Системную роль нельзя удалить.");
    }

    /// <inheritdoc />
    public async Task AssignMemberRolesAsync(Guid membershipId, AssignMemberRolesRequest request, CancellationToken cancellationToken)
    {
        var roleIds = request.RoleIds.Distinct().ToArray();
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        await EnsureMemberAndRolesExistAsync(connection, transaction, membershipId, roleIds, cancellationToken);
        await using (var delete = connection.CreateCommand())
        {
            delete.Transaction = transaction;
            delete.CommandText = "DELETE FROM member_roles WHERE membership_id = @membership_id";
            AddParameter(delete, "membership_id", membershipId);
            await delete.ExecuteNonQueryAsync(cancellationToken);
        }
        foreach (var roleId in roleIds)
        {
            await using var insert = connection.CreateCommand();
            insert.Transaction = transaction;
            insert.CommandText = "INSERT INTO member_roles (membership_id, role_id) VALUES (@membership_id, @role_id)";
            AddParameter(insert, "membership_id", membershipId);
            AddParameter(insert, "role_id", roleId);
            await insert.ExecuteNonQueryAsync(cancellationToken);
        }
        await transaction.CommitAsync(cancellationToken);
    }

    private static async Task<IReadOnlyList<RoleSummary>> ReadRolesAsync(DbConnection connection, Guid? roleId, CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        var roleFilter = roleId.HasValue ? "AND role.id = @role_id" : string.Empty;
        command.CommandText = $"""
            SELECT role.id, role.name, role.is_system, permission.code
            FROM roles AS role
            LEFT JOIN role_permissions AS role_permission ON role_permission.role_id = role.id
            LEFT JOIN permissions AS permission ON permission.id = role_permission.permission_id
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
                role = new MutableRole(id, reader.GetString(1), reader.GetBoolean(2));
                roles.Add(id, role);
            }
            if (!reader.IsDBNull(3)) role.PermissionCodes.Add(reader.GetString(3));
        }
        return roles.Values.Select(role => role.ToSummary()).ToArray();
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

    private static async Task<int> ExecuteWithConflictMappingAsync(DbCommand command, CancellationToken token)
    {
        try { return await command.ExecuteNonQueryAsync(token); }
        catch (PostgresException exception) when (exception.SqlState == PostgresErrorCodes.UniqueViolation)
        {
            throw new IdentityException(409, "role_name_exists", "Роль с таким названием уже существует.");
        }
    }

    private static void AddParameter(DbCommand command, string name, object value)
    {
        var parameter = command.CreateParameter();
        parameter.ParameterName = name;
        parameter.Value = value;
        command.Parameters.Add(parameter);
    }

    private sealed class MutableRole(Guid id, string name, bool isSystem)
    {
        public List<string> PermissionCodes { get; } = [];
        public RoleSummary ToSummary() => new(id, name, isSystem, PermissionCodes);
    }

    private sealed class MutableMember(Guid membershipId, Guid userId, string displayName, bool isDirector)
    {
        public List<Guid> RoleIds { get; } = [];
        public MemberAccessSummary ToSummary() => new(membershipId, userId, displayName, isDirector, RoleIds);
    }
}
