using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.JsonWebTokens;
using SkladKomforta.Application.Contracts;
using SkladKomforta.Application.Identity;
using SkladKomforta.Application.Company;
using SkladKomforta.Infrastructure.Configuration;
using SkladKomforta.Domain.Authentication;

namespace SkladKomforta.Api.Identity;

/// <summary>Сопоставляет тонкие REST endpoint-ы Identity с единым application service.</summary>
internal static class IdentityEndpoints
{
    /// <summary>Регистрирует публичные auth и защищённые session/onboarding маршруты API v1.</summary>
    public static IEndpointRouteBuilder MapIdentityEndpoints(this IEndpointRouteBuilder endpoints)
    {
        var auth = endpoints.MapGroup("/api/v1/auth");
        auth.MapPost("/bootstrap/director", BootstrapDirectorAsync);
        auth.MapPost("/login", BeginLoginAsync);
        auth.MapPost("/initial-password", ChangeInitialPasswordAsync);
        auth.MapPost("/totp/setup", BeginTotpSetupAsync);
        auth.MapPost("/totp/confirm", ConfirmTotpAsync);
        auth.MapPost("/totp/verify", VerifyTotpAsync);
        auth.MapPost("/recovery/verify", VerifyRecoveryCodeAsync);
        auth.MapPost("/refresh", RefreshAsync);

        var identity = endpoints.MapGroup("/api/v1/identity").RequireAuthorization();
        identity.MapPost("/organization", CreateOrganizationAsync);
        // До первого сохранения мастера у пользователя ещё нет tenant-схемы.
        identity.MapGet("/registry-lookup", async (string? inn, ICompanyRegistryLookup registry, CancellationToken token) =>
            Results.Ok(ApiResponse.Success(await registry.FindByInnAsync(inn ?? string.Empty, token))));
        identity.MapGet("/sessions", GetSessionsAsync);
        identity.MapDelete("/sessions/{sessionId:guid}", RevokeSessionAsync);
        identity.MapDelete("/sessions", RevokeOtherSessionsAsync);
        identity.MapPost("/logout", LogoutAsync);
        return endpoints;
    }

    private static async Task<IResult> BootstrapDirectorAsync(
        HttpContext context,
        BootstrapDirectorRequest request,
        IIdentityService service,
        IOptions<SecurityOptions> options,
        CancellationToken cancellationToken)
    {
        var supplied = context.Request.Headers["X-Bootstrap-Token"].ToString();
        if (!FixedTimeEquals(supplied, options.Value.BootstrapToken))
        {
            throw new IdentityException(404, "not_found", "Ресурс не найден.");
        }

        var id = await service.BootstrapDirectorAsync(request, cancellationToken);
        return Results.Ok(ApiResponse.Success(new { userId = id }));
    }

    private static async Task<IResult> BeginLoginAsync(HttpContext context, LoginRequest request, IIdentityService service, CancellationToken token) =>
        Results.Ok(ApiResponse.Success(await service.BeginLoginAsync(request, Client(context), token)));

    private static async Task<IResult> ChangeInitialPasswordAsync(ChangeInitialPasswordRequest request, IIdentityService service, CancellationToken token) =>
        Results.Ok(ApiResponse.Success(await service.ChangeInitialPasswordAsync(request, token)));

    private static async Task<IResult> BeginTotpSetupAsync(TotpChallengeRequest request, IIdentityService service, CancellationToken token) =>
        Results.Ok(ApiResponse.Success(await service.BeginTotpSetupAsync(request.ChallengeToken, token)));

    private static async Task<IResult> ConfirmTotpAsync(HttpContext context, TotpVerificationRequest request, IIdentityService service, CancellationToken token) =>
        AuthenticationResponse(context, await service.ConfirmTotpAsync(request, token));

    private static async Task<IResult> VerifyTotpAsync(HttpContext context, TotpVerificationRequest request, IIdentityService service, CancellationToken token) =>
        AuthenticationResponse(context, await service.VerifyTotpAsync(request, token));

    private static async Task<IResult> VerifyRecoveryCodeAsync(HttpContext context, RecoveryCodeVerificationRequest request, IIdentityService service, CancellationToken token) =>
        AuthenticationResponse(context, await service.VerifyRecoveryCodeAsync(request, token));

    private static async Task<IResult> RefreshAsync(HttpContext context, RefreshTokenRequest request, IIdentityService service, CancellationToken token)
    {
        var supplied = string.IsNullOrWhiteSpace(request.RefreshToken)
            ? context.Request.Cookies[RefreshCookieName]
            : request.RefreshToken;
        var pair = await service.RefreshAsync(new RefreshTokenRequest(supplied ?? string.Empty), Client(context), token);
        return TokenResponse(context, pair);
    }

    private static async Task<IResult> CreateOrganizationAsync(HttpContext context, CreateOrganizationRequest request, IIdentityService service, CancellationToken token) =>
        Results.Ok(ApiResponse.Success(await service.CreateOrganizationAsync(UserId(context.User), SessionId(context.User), request, token)));

    private static async Task<IResult> GetSessionsAsync(HttpContext context, IIdentityService service, CancellationToken token) =>
        Results.Ok(ApiResponse.Success(await service.GetSessionsAsync(UserId(context.User), SessionId(context.User), token)));

    private static async Task<IResult> RevokeSessionAsync(HttpContext context, Guid sessionId, IIdentityService service, CancellationToken token)
    {
        await service.RevokeSessionAsync(UserId(context.User), sessionId, token);
        return Results.Ok(ApiResponse.Success(new { revoked = true }));
    }

    private static async Task<IResult> RevokeOtherSessionsAsync(HttpContext context, IIdentityService service, CancellationToken token)
    {
        await service.RevokeOtherSessionsAsync(UserId(context.User), SessionId(context.User), token);
        return Results.Ok(ApiResponse.Success(new { revoked = true }));
    }

    private static async Task<IResult> LogoutAsync(HttpContext context, IIdentityService service, CancellationToken token)
    {
        await service.RevokeSessionAsync(UserId(context.User), SessionId(context.User), token);
        context.Response.Cookies.Delete(RefreshCookieName, new CookieOptions { Path = "/api/v1/auth" });
        return Results.Ok(ApiResponse.Success(new { loggedOut = true }));
    }

    private static AuthenticationClientContext Client(HttpContext context) =>
        new(context.Connection.RemoteIpAddress?.ToString(), context.Request.Headers.UserAgent.ToString());

    private static Guid UserId(ClaimsPrincipal user) => ParseClaim(user, ClaimTypes.NameIdentifier, JwtRegisteredClaimNames.Sub);

    private static Guid SessionId(ClaimsPrincipal user) => ParseClaim(user, "session_id");

    private static Guid ParseClaim(ClaimsPrincipal user, params string[] names)
    {
        var value = names.Select(name => user.FindFirst(name)?.Value).FirstOrDefault(candidate => candidate is not null);
        return Guid.TryParse(value, out var id)
            ? id
            : throw new IdentityException(401, "token_invalid", "Токен доступа недействителен.");
    }

    private static bool FixedTimeEquals(string supplied, string expected)
    {
        var left = Encoding.UTF8.GetBytes(supplied);
        var right = Encoding.UTF8.GetBytes(expected);
        return left.Length == right.Length && CryptographicOperations.FixedTimeEquals(left, right);
    }

    private const string RefreshCookieName = "sk_refresh";

    private static IResult AuthenticationResponse(HttpContext context, AuthenticationResult result)
    {
        if (result.Tokens is null)
        {
            return Results.Ok(ApiResponse.Success(result));
        }

        var safeTokens = PrepareTokens(context, result.Tokens);
        return Results.Ok(ApiResponse.Success(result with { Tokens = safeTokens }));
    }

    private static IResult TokenResponse(HttpContext context, TokenPair tokens) =>
        Results.Ok(ApiResponse.Success(PrepareTokens(context, tokens)));

    private static TokenPair PrepareTokens(HttpContext context, TokenPair tokens)
    {
        if (tokens.DeviceType != DeviceType.Web || tokens.RefreshToken is null)
        {
            return tokens;
        }

        context.Response.Cookies.Append(
            RefreshCookieName,
            tokens.RefreshToken,
            new CookieOptions
            {
                HttpOnly = true,
                Secure = context.Request.IsHttps,
                SameSite = SameSiteMode.Strict,
                Expires = tokens.RefreshTokenExpiresAt,
                Path = "/api/v1/auth",
            });
        return tokens with { RefreshToken = null };
    }

    private sealed record TotpChallengeRequest(string ChallengeToken);
}
