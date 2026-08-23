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
        catalog.MapGet("/template.xlsx", async (
                Guid? categoryId,
                ICatalogSpreadsheetService service,
                CancellationToken token) =>
            {
                var file = await service.CreateTemplateAsync(categoryId, token);
                return Results.File(file.Content, file.ContentType, file.FileName);
            })
            .RequireTenantPermission("catalog.view");
        catalog.MapGet("/export.xlsx", async (
                Guid? categoryId,
                Guid? sectionId,
                string? status,
                string? search,
                ICatalogSpreadsheetService service,
                CancellationToken token) =>
            {
                var file = await service.ExportAsync(
                    new CatalogItemQuery(categoryId, sectionId, status, search), token);
                return Results.File(file.Content, file.ContentType, file.FileName);
            })
            .RequireTenantPermission("catalog.view");
        catalog.MapPost("/import.xlsx", async (
                HttpContext context,
                ICatalogSpreadsheetService service,
                CancellationToken token) =>
            {
                const long maxFileSize = 10 * 1024 * 1024;
                if (!context.Request.HasFormContentType)
                    throw new IdentityException(400, "catalog_import_file_missing", "Передайте XLSX-файл в поле file.");
                var form = await context.Request.ReadFormAsync(token);
                var file = form.Files.GetFile("file");
                if (file is null || file.Length == 0 || file.Length > maxFileSize ||
                    !file.FileName.EndsWith(".xlsx", StringComparison.OrdinalIgnoreCase))
                    throw new IdentityException(400, "catalog_import_file_invalid", "Выберите XLSX-файл размером не более 10 МБ.");
                await using var stream = file.OpenReadStream();
                return Results.Ok(ApiResponse.Success(await service.ImportAsync(
                    UserId(context.User), stream, token)));
            })
            .DisableAntiforgery()
            .RequireTenantPermission("catalog.manage");
        catalog.MapPost("/items/bulk", async (
                HttpContext context,
                CatalogBulkRequest request,
                ICatalogService service,
                CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.ApplyBulkAsync(
                    UserId(context.User), request, token))))
            .RequireTenantPermission("catalog.manage");
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
