using SkladKomforta.Application.Abstractions.Tenancy;

namespace SkladKomforta.Api.Middleware;

/// <summary>
/// Извлекает UUID организации только из уже проверенного JWT. Middleware не
/// принимает имя схемы от клиента и очищает scoped-контекст даже при исключении.
/// </summary>
internal sealed class TenantResolutionMiddleware(RequestDelegate next)
{
    private const string OrganizationClaim = "organization_id";

    /// <summary>Определяет tenant для авторизованного запроса и гарантированно очищает контекст.</summary>
    public async Task InvokeAsync(HttpContext context, ITenantContext tenantContext)
    {
        var claimValue = context.User.FindFirst(OrganizationClaim)?.Value;
        if (context.User.Identity?.IsAuthenticated == true &&
            Guid.TryParse(claimValue, out var organizationId))
        {
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
}
