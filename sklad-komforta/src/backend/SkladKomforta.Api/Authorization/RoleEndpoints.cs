using SkladKomforta.Application.Authorization;
using SkladKomforta.Application.Contracts;

namespace SkladKomforta.Api.Authorization;

/// <summary>Тонкие REST endpoint-ы настройки tenant-ролей.</summary>
internal static class RoleEndpoints
{
    /// <summary>Регистрирует просмотр и изменение ролей с permission metadata.</summary>
    public static IEndpointRouteBuilder MapRoleEndpoints(this IEndpointRouteBuilder endpoints)
    {
        var roles = endpoints.MapGroup("/api/v1/settings/access").RequireAuthorization();
        roles.MapGet("/permissions", async (IRoleAdministrationService service, CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.GetPermissionsAsync(token))))
            .RequireTenantPermission("settings.roles.view");
        roles.MapGet("/roles", async (IRoleAdministrationService service, CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.GetRolesAsync(token))))
            .RequireTenantPermission("settings.roles.view");
        roles.MapGet("/members", async (IRoleAdministrationService service, CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.GetMembersAsync(token))))
            .RequireTenantPermission("settings.members.view");
        roles.MapPost("/roles", async (SaveRoleRequest request, IRoleAdministrationService service, CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.CreateRoleAsync(request, token))))
            .RequireTenantPermission("settings.roles.manage");
        roles.MapPut("/roles/{roleId:guid}", async (Guid roleId, SaveRoleRequest request, IRoleAdministrationService service, CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.UpdateRoleAsync(roleId, request, token))))
            .RequireTenantPermission("settings.roles.manage");
        roles.MapDelete("/roles/{roleId:guid}", async (Guid roleId, IRoleAdministrationService service, CancellationToken token) =>
            {
                await service.DeleteRoleAsync(roleId, token);
                return Results.Ok(ApiResponse.Success(new { deleted = true }));
            })
            .RequireTenantPermission("settings.roles.manage");
        roles.MapPut("/members/{membershipId:guid}/roles", async (Guid membershipId, AssignMemberRolesRequest request, IRoleAdministrationService service, CancellationToken token) =>
            {
                await service.AssignMemberRolesAsync(membershipId, request, token);
                return Results.Ok(ApiResponse.Success(new { updated = true }));
            })
            .RequireTenantPermission("settings.members.manage");
        return endpoints;
    }
}
