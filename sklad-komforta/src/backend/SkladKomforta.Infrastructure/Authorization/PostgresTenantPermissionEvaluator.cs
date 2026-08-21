using Npgsql;
using SkladKomforta.Application.Authorization;
using SkladKomforta.Domain.Tenancy;

namespace SkladKomforta.Infrastructure.Authorization;

/// <summary>Вычисляет эффективное разрешение через роли tenant-схемы.</summary>
internal sealed class PostgresTenantPermissionEvaluator(NpgsqlDataSource dataSource) : ITenantPermissionEvaluator
{
    /// <inheritdoc />
    public async Task<bool> HasPermissionAsync(
        Guid userId,
        Guid organizationId,
        string permissionCode,
        CancellationToken cancellationToken)
    {
        var schema = TenantSchemaName.Create(organizationId).Value;
        var sql = $"""
            SELECT EXISTS (
                SELECT 1
                FROM public.organization_members AS member
                JOIN {schema}.member_roles AS member_role ON member_role.membership_id = member.id
                JOIN {schema}.roles AS role ON role.id = member_role.role_id AND role.deleted_at IS NULL
                JOIN {schema}.role_permissions AS role_permission ON role_permission.role_id = role.id
                JOIN {schema}.permissions AS permission ON permission.id = role_permission.permission_id
                WHERE member.user_id = @user_id
                  AND member.organization_id = @organization_id
                  AND member.is_active
                  AND member.deleted_at IS NULL
                  AND permission.code IN ('system.full_access', @permission_code)
            )
            """;
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("user_id", userId);
        command.Parameters.AddWithValue("organization_id", organizationId);
        command.Parameters.AddWithValue("permission_code", permissionCode);
        return await command.ExecuteScalarAsync(cancellationToken) is true;
    }
}
