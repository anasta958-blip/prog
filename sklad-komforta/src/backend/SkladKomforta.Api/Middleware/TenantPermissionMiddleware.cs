using System.Security.Claims;
using SkladKomforta.Api.Authorization;
using SkladKomforta.Application.Abstractions.Tenancy;
using SkladKomforta.Application.Authorization;
using SkladKomforta.Application.Identity;

namespace SkladKomforta.Api.Middleware;

/// <summary>Централизованно применяет permission metadata защищённого endpoint-а.</summary>
internal sealed class TenantPermissionMiddleware(RequestDelegate next)
{
    /// <summary>Пропускает endpoint без metadata либо проверяет эффективные роли.</summary>
    public async Task InvokeAsync(
        HttpContext context,
        ITenantContext tenantContext,
        ITenantPermissionEvaluator evaluator)
    {
        var requirement = context.GetEndpoint()?.Metadata.GetMetadata<TenantPermissionMetadata>();
        if (requirement is not null && context.User.Identity?.IsAuthenticated == true)
        {
            if (!tenantContext.IsResolved)
                throw new IdentityException(403, "tenant_required", "Организация не выбрана.");

            var userId = Guid.TryParse(context.User.FindFirst(JwtSubjectClaim)?.Value, out var parsed)
                ? parsed
                : throw new IdentityException(401, "token_invalid", "Токен доступа недействителен.");
            if (!await evaluator.HasPermissionAsync(userId, tenantContext.OrganizationId, requirement.Code, context.RequestAborted))
                throw new IdentityException(403, "permission_denied", "Недостаточно прав для выполнения действия.");
        }

        await next(context);
    }

    private const string JwtSubjectClaim = "sub";
}
