using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using SkladKomforta.Application.Contracts;
using SkladKomforta.Application.Identity;
using SkladKomforta.Application.Onboarding;

namespace SkladKomforta.Api.Onboarding;

/// <summary>HTTP-граница восьмишаговой первичной настройки организации.</summary>
internal static class OnboardingEndpoints
{
    /// <summary>Регистрирует загрузку, сохранение черновика и финальную активацию.</summary>
    public static IEndpointRouteBuilder MapOnboardingEndpoints(this IEndpointRouteBuilder endpoints)
    {
        var group = endpoints.MapGroup("/api/v1/onboarding").RequireAuthorization();
        group.MapGet("/", GetAsync);
        group.MapPost("/draft", SaveAsync);
        group.MapPost("/activate", ActivateAsync);
        return endpoints;
    }

    private static async Task<IResult> GetAsync(
        HttpContext context,
        IOrganizationOnboardingService service,
        CancellationToken token) =>
        Results.Ok(ApiResponse.Success(await service.GetAsync(UserId(context.User), token)));

    private static async Task<IResult> SaveAsync(
        HttpContext context,
        OrganizationOnboardingDraft draft,
        IOrganizationOnboardingService service,
        CancellationToken token) =>
        Results.Ok(ApiResponse.Success(await service.SaveAsync(UserId(context.User), draft, token)));

    private static async Task<IResult> ActivateAsync(
        HttpContext context,
        IOrganizationOnboardingService service,
        CancellationToken token) =>
        Results.Ok(ApiResponse.Success(await service.ActivateAsync(UserId(context.User), token)));

    /// <summary>Извлекает UUID только из уже проверенного JWT.</summary>
    private static Guid UserId(ClaimsPrincipal user)
    {
        var value = user.FindFirst(JwtRegisteredClaimNames.Sub)?.Value ??
                    user.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        return Guid.TryParse(value, out var id)
            ? id
            : throw new IdentityException(401, "token_invalid", "Токен доступа недействителен.");
    }
}
