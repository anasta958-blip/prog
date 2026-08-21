namespace SkladKomforta.Application.Authorization;

/// <summary>Разрешение, доступное для назначения tenant-роли.</summary>
public sealed record PermissionSummary(string Code, string Name, string GroupName);

/// <summary>Роль организации вместе с текущим набором кодов разрешений.</summary>
public sealed record RoleSummary(Guid Id, string Name, bool IsSystem, IReadOnlyList<string> PermissionCodes);

/// <summary>Сотрудник организации и назначенные ему роли.</summary>
public sealed record MemberAccessSummary(Guid MembershipId, Guid UserId, string DisplayName, bool IsDirector, IReadOnlyList<Guid> RoleIds);

/// <summary>Данные создаваемой или изменяемой роли.</summary>
public sealed record SaveRoleRequest(string Name, IReadOnlyList<string> PermissionCodes);

/// <summary>Полная замена набора ролей одного сотрудника.</summary>
public sealed record AssignMemberRolesRequest(IReadOnlyList<Guid> RoleIds);

/// <summary>Контракт настройки ролей внутри уже проверенного tenant-контекста.</summary>
public interface IRoleAdministrationService
{
    Task<IReadOnlyList<PermissionSummary>> GetPermissionsAsync(CancellationToken cancellationToken);
    Task<IReadOnlyList<RoleSummary>> GetRolesAsync(CancellationToken cancellationToken);
    Task<IReadOnlyList<MemberAccessSummary>> GetMembersAsync(CancellationToken cancellationToken);
    Task<RoleSummary> CreateRoleAsync(SaveRoleRequest request, CancellationToken cancellationToken);
    Task<RoleSummary> UpdateRoleAsync(Guid roleId, SaveRoleRequest request, CancellationToken cancellationToken);
    Task DeleteRoleAsync(Guid roleId, CancellationToken cancellationToken);
    Task AssignMemberRolesAsync(Guid membershipId, AssignMemberRolesRequest request, CancellationToken cancellationToken);
}

/// <summary>Проверяет одно разрешение пользователя в текущей организации.</summary>
public interface ITenantPermissionEvaluator
{
    Task<bool> HasPermissionAsync(Guid userId, Guid organizationId, string permissionCode, CancellationToken cancellationToken);
}
