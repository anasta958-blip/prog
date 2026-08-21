using SkladKomforta.Application.Abstractions.Tenancy;
using SkladKomforta.Application.Identity;

namespace SkladKomforta.Api.Middleware;

/// <summary>
/// Извлекает UUID организации только из уже проверенного JWT. Middleware не
/// принимает имя схемы от клиента и очищает scoped-контекст даже при исключении.
/// </summary>
internal sealed class TenantResolutionMiddleware(RequestDelegate next)
{
    private const string OrganizationClaim = "organization_id";

    /// <summary>Определяет tenant для авторизованного запроса и гарантированно очищает контекст.</summary>
    public async Task InvokeAsync(
        HttpContext context,
        ITenantContext tenantContext,
        ITenantAccessValidator accessValidator)
    {
        var claimValue = context.User.FindFirst(OrganizationClaim)?.Value;
        if (context.User.Identity?.IsAuthenticated == true &&
            Guid.TryParse(claimValue, out var organizationId))
        {
            var userId = ParseGuidClaim(context.User, "sub");
            var sessionId = ParseGuidClaim(context.User, "session_id");
            if (!await accessValidator.IsActiveAsync(userId, sessionId, organizationId, context.RequestAborted))
            {
                throw new IdentityException(403, "tenant_access_denied", "Доступ к организации отозван.");
            }

            tenantContext.Resolve(organizationId);
        }

        try
        {
            await next(context);
        }
        finally
        {
            tenantContext.Clear();
        }
    }

    /// <summary>Извлекает только UUID из уже проверенного набора JWT claims.</summary>
    private static Guid ParseGuidClaim(System.Security.Claims.ClaimsPrincipal user, string name) =>
        Guid.TryParse(user.FindFirst(name)?.Value, out var value)
            ? value
            : throw new IdentityException(401, "token_invalid", "Токен доступа недействителен.");
}
