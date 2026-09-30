using SkladKomforta.Application.Abstractions.Realtime;
using SkladKomforta.Application.Abstractions.Tenancy;

namespace SkladKomforta.Api.Realtime;

/// <summary>
/// После успешного изменяющего запроса к канбанам, КП или каталогу публикует
/// сигнал «данные изменились» для остальных пользователей организации.
/// Одно место вместо вызовов в каждом сервисе: новый изменяющий endpoint
/// этих модулей получает уведомления автоматически.
/// </summary>
internal sealed class RealtimeChangeMiddleware(RequestDelegate next)
{
    /// <summary>Выполняет запрос и при успехе отправляет сигнал.</summary>
    public async Task InvokeAsync(HttpContext context, ITenantContext tenantContext, IRealtimeNotifier notifier)
    {
        await next(context);

        if (HttpMethods.IsGet(context.Request.Method) ||
            HttpMethods.IsHead(context.Request.Method) ||
            HttpMethods.IsOptions(context.Request.Method) ||
            context.Response.StatusCode is < 200 or >= 300 ||
            !tenantContext.IsResolved)
            return;

        foreach (var change in Describe(context, tenantContext.OrganizationId))
            await notifier.PublishAsync(change, CancellationToken.None);
    }

    /// <summary>Определяет затронутые темы по маршруту запроса.</summary>
    internal static IEnumerable<RealtimeChange> Describe(HttpContext context, Guid organizationId)
    {
        var path = context.Request.Path;
        if (path.Value?.EndsWith("/realtime-ticket", StringComparison.Ordinal) == true) yield break;

        if (path.StartsWithSegments("/api/v1/kanbans"))
        {
            yield return new RealtimeChange(
                organizationId,
                RealtimeTopics.Kanban,
                RealtimeChange.Changed,
                RouteGuid(context, "boardId"),
                RouteGuid(context, "cardId"));
        }
        else if (path.StartsWithSegments("/api/v1/catalog"))
        {
            yield return new RealtimeChange(
                organizationId,
                RealtimeTopics.Catalog,
                RealtimeChange.Changed,
                EntityId: RouteGuid(context, "itemId"));
        }
        else if (path.StartsWithSegments("/api/v1/company/configuration"))
        {
            // Настройки меняют структуру канбанов и каталога.
            yield return new RealtimeChange(organizationId, RealtimeTopics.Kanban, RealtimeChange.Configuration);
            yield return new RealtimeChange(organizationId, RealtimeTopics.Catalog, RealtimeChange.Configuration);
            yield return Company(organizationId, "configuration", null);
        }
        else if (path.StartsWithSegments("/api/v1/company/profile"))
        {
            yield return Company(organizationId, "profile", null);
        }
        else if (path.StartsWithSegments("/api/v1/company/legal-entities"))
        {
            yield return Company(organizationId, "legal_entities", RouteGuid(context, "id"));
        }
        else if (path.StartsWithSegments("/api/v1/company/clients"))
        {
            yield return Company(organizationId, "clients", RouteGuid(context, "id"));
        }
        else if (path.StartsWithSegments("/api/v1/company/employees"))
        {
            yield return Company(organizationId, "employees", RouteGuid(context, "membershipId"));
        }
        else if (path.StartsWithSegments("/api/v1/settings/access"))
        {
            // Роли и назначения меняют и список сотрудников (их роли).
            yield return Company(organizationId, "access", RouteGuid(context, "roleId") ?? RouteGuid(context, "membershipId"));
        }
    }

    private static RealtimeChange Company(Guid organizationId, string section, Guid? entityId) =>
        new(organizationId, RealtimeTopics.Company, RealtimeChange.Changed, EntityId: entityId, Section: section);

    private static Guid? RouteGuid(HttpContext context, string name) =>
        Guid.TryParse(context.GetRouteValue(name)?.ToString(), out var value) ? value : null;
}
