namespace SkladKomforta.Api.Authorization;

/// <summary>Метаданные endpoint-а с требуемым tenant-разрешением.</summary>
internal sealed record TenantPermissionMetadata(string Code);

/// <summary>Добавляет проверяемое middleware разрешение к route handler.</summary>
internal static class TenantPermissionRouteExtensions
{
    /// <summary>Помечает endpoint одним стабильным кодом разрешения.</summary>
    public static RouteHandlerBuilder RequireTenantPermission(this RouteHandlerBuilder builder, string code) =>
        builder.WithMetadata(new TenantPermissionMetadata(code));
}
