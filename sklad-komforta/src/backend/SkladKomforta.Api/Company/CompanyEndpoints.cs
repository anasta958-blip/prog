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
        company.MapPut("/configuration", async (
                HttpContext context,
                OrganizationOnboardingDraft draft,
                ICompanyService service,
                CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.UpdateConfigurationAsync(
                    UserId(context.User), draft, token))))
            .RequireTenantPermission("company.manage");
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
