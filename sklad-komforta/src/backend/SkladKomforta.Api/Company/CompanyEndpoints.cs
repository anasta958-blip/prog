using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using SkladKomforta.Api.Authorization;
using SkladKomforta.Application.Company;
using SkladKomforta.Application.Contracts;
using SkladKomforta.Application.Identity;
using SkladKomforta.Application.Onboarding;

namespace SkladKomforta.Api.Company;

/// <summary>REST-граница рабочего пространства «Компания».</summary>
internal static class CompanyEndpoints
{
    public static IEndpointRouteBuilder MapCompanyEndpoints(this IEndpointRouteBuilder endpoints)
    {
        var company = endpoints.MapGroup("/api/v1/company").RequireAuthorization();
        company.MapGet("/profile", async (ICompanyService service, CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.GetAsync(token))))
            .RequireTenantPermission("company.view");
        company.MapPut("/profile", async (
                HttpContext context,
                CompanyProfile profile,
                ICompanyService service,
                CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.UpdateAsync(UserId(context.User), profile, token))))
            .RequireTenantPermission("company.manage");
        company.MapGet("/configuration", async (
                ICompanyService service,
                CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.GetConfigurationAsync(token))))
            .RequireTenantPermission("company.view");
        company.MapGet("/configuration/categories/{categoryClientId}/deletion-impact", async (
                string categoryClientId,
                ICompanyService service,
                CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.GetCategoryDeletionImpactAsync(
                    categoryClientId, token))))
            .RequireTenantPermission("company.manage");
        company.MapPut("/configuration", async (
                HttpContext context,
                UpdateOrganizationConfigurationRequest request,
                ICompanyService service,
                CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.UpdateConfigurationAsync(
                    UserId(context.User), request.Draft,
                    request.DeleteCategoryData ?? [], token))))
            .RequireTenantPermission("company.manage");

        company.MapGet("/lifecycle", async (ICompanyWorkspaceService service, CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.GetLifecycleAsync(token))))
            .RequireTenantPermission("company.view");
        company.MapGet("/audit", async (int? limit, ICompanyWorkspaceService service, CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.GetAuditAsync(limit ?? 200, token))))
            .RequireTenantPermission("company.audit.view");

        company.MapGet("/legal-entities", async (ICompanyWorkspaceService service, CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.GetLegalEntitiesAsync(token))))
            .RequireTenantPermission("company.legal_entities.view");
        company.MapPost("/legal-entities", async (HttpContext context, SaveLegalEntityRequest request, ICompanyWorkspaceService service, CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.CreateLegalEntityAsync(UserId(context.User), request, token))))
            .RequireTenantPermission("company.legal_entities.manage");
        company.MapPut("/legal-entities/{id:guid}", async (HttpContext context, Guid id, SaveLegalEntityRequest request, ICompanyWorkspaceService service, CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.UpdateLegalEntityAsync(UserId(context.User), id, request, token))))
            .RequireTenantPermission("company.legal_entities.manage");
        company.MapDelete("/legal-entities/{id:guid}", async (HttpContext context, Guid id, ICompanyWorkspaceService service, CancellationToken token) =>
            {
                await service.DeleteLegalEntityAsync(UserId(context.User), id, token);
                return Results.Ok(ApiResponse.Success(new { deleted = true }));
            })
            .RequireTenantPermission("company.legal_entities.manage");

        company.MapGet("/clients", async (ICompanyWorkspaceService service, CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.GetClientsAsync(token))))
            .RequireTenantPermission("company.clients.view");
        company.MapPost("/clients", async (HttpContext context, SaveCompanyClientRequest request, ICompanyWorkspaceService service, CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.CreateClientAsync(UserId(context.User), request, token))))
            .RequireTenantPermission("company.clients.manage");
        company.MapPut("/clients/{id:guid}", async (HttpContext context, Guid id, SaveCompanyClientRequest request, ICompanyWorkspaceService service, CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.UpdateClientAsync(UserId(context.User), id, request, token))))
            .RequireTenantPermission("company.clients.manage");
        company.MapDelete("/clients/{id:guid}", async (HttpContext context, Guid id, ICompanyWorkspaceService service, CancellationToken token) =>
            {
                await service.DeleteClientAsync(UserId(context.User), id, token);
                return Results.Ok(ApiResponse.Success(new { deleted = true }));
            })
            .RequireTenantPermission("company.clients.manage");

        company.MapGet("/employees", async (ICompanyWorkspaceService service, CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.GetEmployeesAsync(token))))
            .RequireTenantPermission("company.employees.view");
        company.MapPost("/employees", async (HttpContext context, CreateEmployeeRequest request, ICompanyWorkspaceService service, CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.CreateEmployeeAsync(UserId(context.User), request, token))))
            .RequireTenantPermission("company.employees.manage");
        company.MapPut("/employees/{membershipId:guid}", async (HttpContext context, Guid membershipId, UpdateEmployeeRequest request, ICompanyWorkspaceService service, CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.UpdateEmployeeAsync(UserId(context.User), membershipId, request, token))))
            .RequireTenantPermission("company.employees.manage");
        company.MapDelete("/employees/{membershipId:guid}", async (HttpContext context, Guid membershipId, ICompanyWorkspaceService service, CancellationToken token) =>
            {
                await service.DeleteEmployeeAsync(UserId(context.User), membershipId, token);
                return Results.Ok(ApiResponse.Success(new { deleted = true }));
            })
            .RequireTenantPermission("company.employees.manage");
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
