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
        catalog.MapGet("/items/{itemId:guid}/images", async (
                Guid itemId,
                ICatalogService service,
                CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.GetImagesAsync(itemId, token))))
            .RequireTenantPermission("catalog.view");
        catalog.MapPost("/items/{itemId:guid}/images/uploads", async (
                HttpContext context,
                Guid itemId,
                BeginCatalogImageUploadRequest request,
                ICatalogService service,
                CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.BeginImageUploadAsync(
                    UserId(context.User), itemId, request, token))))
            .RequireTenantPermission("catalog.manage");
        catalog.MapPost("/items/{itemId:guid}/images/{imageId:guid}/confirm", async (
                HttpContext context,
                Guid itemId,
                Guid imageId,
                ICatalogService service,
                CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.ConfirmImageUploadAsync(
                    UserId(context.User), itemId, imageId, token))))
            .RequireTenantPermission("catalog.manage");
        catalog.MapDelete("/items/{itemId:guid}/images/{imageId:guid}", async (
                HttpContext context,
                Guid itemId,
                Guid imageId,
                ICatalogService service,
                CancellationToken token) =>
            {
                await service.DeleteImageAsync(UserId(context.User), itemId, imageId, token);
                return Results.Ok(ApiResponse.Success(new { deleted = true }));
            })
            .RequireTenantPermission("catalog.manage");
        catalog.MapGet("/items/{itemId:guid}/relations", async (
                Guid itemId,
                ICatalogService service,
                CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.GetRelationsAsync(itemId, token))))
            .RequireTenantPermission("catalog.view");
        catalog.MapPut("/items/{itemId:guid}/relations", async (
                HttpContext context,
                Guid itemId,
                IReadOnlyList<SaveCatalogItemRelationRequest> request,
                ICatalogService service,
                CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.ReplaceRelationsAsync(
                    UserId(context.User), itemId, request, token))))
            .RequireTenantPermission("catalog.manage");
        catalog.MapGet("/dependencies/{dependencyId:guid}/candidates", async (
                Guid dependencyId,
                string? search,
                int? limit,
                ICatalogService service,
                CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.SearchRelationCandidatesAsync(
                    dependencyId, search, limit ?? 30, token))))
            .RequireTenantPermission("catalog.view");
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
