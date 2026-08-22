using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using SkladKomforta.Api.Authorization;
using SkladKomforta.Application.Catalog;
using SkladKomforta.Application.Contracts;
using SkladKomforta.Application.Identity;

namespace SkladKomforta.Api.Catalog;

/// <summary>Тонкие REST endpoint-ы рабочего tenant-каталога.</summary>
internal static class CatalogEndpoints
{
    /// <summary>Регистрирует конфигурацию, страницы и CRUD карточек с tenant-правами.</summary>
    public static IEndpointRouteBuilder MapCatalogEndpoints(this IEndpointRouteBuilder endpoints)
    {
        var catalog = endpoints.MapGroup("/api/v1/catalog").RequireAuthorization();
        catalog.MapGet("/configuration", async (ICatalogService service, CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.GetConfigurationAsync(token))))
            .RequireTenantPermission("catalog.view");
        catalog.MapGet("/items", async (
                Guid? categoryId,
                Guid? sectionId,
                string? status,
                string? search,
                int? page,
                int? pageSize,
                ICatalogService service,
                CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.GetItemsAsync(
                    new CatalogItemQuery(categoryId, sectionId, status, search, page ?? 1, pageSize ?? 50), token))))
            .RequireTenantPermission("catalog.view");
        catalog.MapGet("/items/{itemId:guid}", async (
                Guid itemId,
                ICatalogService service,
                CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.GetItemAsync(itemId, token))))
            .RequireTenantPermission("catalog.view");
        catalog.MapPost("/items", async (
                HttpContext context,
                SaveCatalogItemRequest request,
                ICatalogService service,
                CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.CreateItemAsync(UserId(context.User), request, token))))
            .RequireTenantPermission("catalog.manage");
        catalog.MapPut("/items/{itemId:guid}", async (
                HttpContext context,
                Guid itemId,
                SaveCatalogItemRequest request,
                ICatalogService service,
                CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.UpdateItemAsync(UserId(context.User), itemId, request, token))))
            .RequireTenantPermission("catalog.manage");
        catalog.MapDelete("/items/{itemId:guid}", async (
                HttpContext context,
                Guid itemId,
                ICatalogService service,
                CancellationToken token) =>
            {
                await service.DeleteItemAsync(UserId(context.User), itemId, token);
                return Results.Ok(ApiResponse.Success(new { deleted = true }));
            })
            .RequireTenantPermission("catalog.manage");
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
