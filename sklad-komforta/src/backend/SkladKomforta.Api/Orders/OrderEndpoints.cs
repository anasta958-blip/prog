using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using SkladKomforta.Api.Authorization;
using SkladKomforta.Application.Contracts;
using SkladKomforta.Application.Identity;
using SkladKomforta.Application.Orders;

namespace SkladKomforta.Api.Orders;

/// <summary>HTTP-граница комплектации: документ карточки, печать и PDF-счета.</summary>
internal static class OrderEndpoints
{
    /// <summary>
    /// Подключает создание, чтение, сохранение и печать комплектации карточки,
    /// а также счета. Перемещение и статус остаются в endpoint-ах канбана.
    /// </summary>
    public static IEndpointRouteBuilder MapOrderEndpoints(this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapPost("/api/v1/kanbans/{boardId:guid}/orders", async (
                HttpContext context,
                Guid boardId,
                CreateOrderRequest request,
                IOrderService service,
                CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.CreateAsync(UserId(context.User), boardId, request, token))))
            .RequireAuthorization()
            .RequireTenantPermission("orders.manage");

        var order = endpoints
            .MapGroup("/api/v1/kanbans/{boardId:guid}/cards/{cardId:guid}/order")
            .RequireAuthorization();

        order.MapGet("/", async (
                HttpContext context, Guid boardId, Guid cardId, IOrderService service, CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.GetAsync(UserId(context.User), boardId, cardId, token))))
            .RequireTenantPermission("orders.view");

        order.MapPut("/", async (
                HttpContext context, Guid boardId, Guid cardId, SaveOrderRequest request,
                IOrderService service, CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.SaveAsync(UserId(context.User), boardId, cardId, request, token))))
            .RequireTenantPermission("orders.manage");

        order.MapGet("/calculation-preview", async (
                HttpContext context, Guid boardId, Guid cardId,
                IOrderService service, CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.PreviewCalculationAsync(
                    UserId(context.User), boardId, cardId, token))))
            .RequireTenantPermission("orders.manage");

        order.MapPost("/apply-calculation", async (
                HttpContext context, Guid boardId, Guid cardId,
                ApplyOrderCalculationRequest request,
                IOrderService service, CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.ApplyCalculationAsync(
                    UserId(context.User), boardId, cardId, request, token))))
            .RequireTenantPermission("orders.manage");

        order.MapGet("/pdf", async (
                HttpContext context, Guid boardId, Guid cardId, IOrderPdfService service, CancellationToken token) =>
            {
                var file = await service.GenerateAsync(UserId(context.User), boardId, cardId, token);
                return Results.File(file.Content, "application/pdf", file.FileName, enableRangeProcessing: false);
            })
            .RequireTenantPermission("orders.view");

        order.MapGet("/invoices", async (
                HttpContext context, Guid boardId, Guid cardId, IOrderService service, CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.GetInvoicesAsync(UserId(context.User), boardId, cardId, token))))
            .RequireTenantPermission("orders.view");

        order.MapPost("/invoices/uploads", async (
                HttpContext context, Guid boardId, Guid cardId, BeginOrderInvoiceUploadRequest request,
                IOrderService service, CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.BeginInvoiceUploadAsync(
                    UserId(context.User), boardId, cardId, request, token))))
            .RequireTenantPermission("orders.invoices.manage");

        order.MapPost("/invoices/{invoiceId:guid}/confirm", async (
                HttpContext context, Guid boardId, Guid cardId, Guid invoiceId,
                IOrderService service, CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.ConfirmInvoiceUploadAsync(
                    UserId(context.User), boardId, cardId, invoiceId, token))))
            .RequireTenantPermission("orders.invoices.manage");

        order.MapDelete("/invoices/{invoiceId:guid}", async (
                HttpContext context, Guid boardId, Guid cardId, Guid invoiceId,
                IOrderService service, CancellationToken token) =>
            {
                await service.DeleteInvoiceAsync(UserId(context.User), boardId, cardId, invoiceId, token);
                return Results.Ok(ApiResponse.Success(new { deleted = true }));
            })
            .RequireTenantPermission("orders.invoices.manage");

        return endpoints;
    }

    /// <summary>Извлекает UUID пользователя только из уже проверенного JWT.</summary>
    private static Guid UserId(ClaimsPrincipal user)
    {
        var value = user.FindFirst(JwtRegisteredClaimNames.Sub)?.Value ??
                    user.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        return Guid.TryParse(value, out var id)
            ? id
            : throw new IdentityException(401, "token_invalid", "Токен доступа недействителен.");
    }
}
