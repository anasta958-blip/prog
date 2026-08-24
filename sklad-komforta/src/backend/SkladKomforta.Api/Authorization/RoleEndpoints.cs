using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using SkladKomforta.Application.Authorization;
using SkladKomforta.Application.Contracts;
using SkladKomforta.Application.Identity;

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
            .RequireTenantPermission("company.access.view");
        roles.MapGet("/roles", async (IRoleAdministrationService service, CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.GetRolesAsync(token))))
            .RequireTenantPermission("company.access.view");
        roles.MapGet("/members", async (IRoleAdministrationService service, CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.GetMembersAsync(token))))
            .RequireTenantPermission("company.access.view");
        roles.MapPost("/roles", async (HttpContext context, SaveRoleRequest request, IRoleAdministrationService service, CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.CreateRoleAsync(
                    UserId(context.User), request, token))))
            .RequireTenantPermission("company.access.manage");
        roles.MapPut("/roles/{roleId:guid}", async (HttpContext context, Guid roleId, SaveRoleRequest request, IRoleAdministrationService service, CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.UpdateRoleAsync(UserId(context.User), roleId, request, token))))
            .RequireTenantPermission("company.access.manage");
        roles.MapDelete("/roles/{roleId:guid}", async (HttpContext context, Guid roleId, IRoleAdministrationService service, CancellationToken token) =>
            {
                await service.DeleteRoleAsync(UserId(context.User), roleId, token);
                return Results.Ok(ApiResponse.Success(new { deleted = true }));
            })
            .RequireTenantPermission("company.access.manage");
        roles.MapPut("/members/{membershipId:guid}/access", async (HttpContext context, Guid membershipId, AssignMemberAccessRequest request, IRoleAdministrationService service, CancellationToken token) =>
            {
                await service.AssignMemberAccessAsync(UserId(context.User), membershipId, request, token);
                return Results.Ok(ApiResponse.Success(new { updated = true }));
            })
            .RequireTenantPermission("company.access.manage");
        return endpoints;
    }

    private static Guid UserId(ClaimsPrincipal user)
    {
        var value = user.FindFirst(JwtRegisteredClaimNames.Sub)?.Value ??
                    user.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        return Guid.TryParse(value, out var id)
            ? id
            : throw new IdentityException(401, "token_invalid", "Токен доступа недействителен.");
    }
}
