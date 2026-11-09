using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using SkladKomforta.Api.Authorization;
using SkladKomforta.Application.Contracts;
using SkladKomforta.Application.Identity;
using SkladKomforta.Application.Quotes;

namespace SkladKomforta.Api.Quotes;

/// <summary>REST endpoints специализированного содержимого карточек КП/ПКП.</summary>
internal static class QuoteEndpoints
{
    /// <summary>
    /// Подключает чтение и атомарное сохранение предложения к конкретной карточке.
    /// Статус и перемещение карточки остаются в универсальных kanban endpoint-ах.
    /// </summary>
    public static IEndpointRouteBuilder MapQuoteEndpoints(this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapPost("/api/v1/kanbans/{boardId:guid}/quotes", async (
                HttpContext context,
                Guid boardId,
                CreateQuoteRequest request,
                IQuoteService service,
                CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.CreateAsync(
                    UserId(context.User), boardId, request, token))))
            .RequireAuthorization()
            .RequireTenantPermission("quotes.manage");

        var quotes = endpoints
            .MapGroup("/api/v1/kanbans/{boardId:guid}/cards/{cardId:guid}/quote")
            .RequireAuthorization();

        quotes.MapGet("/", async (
                HttpContext context,
                Guid boardId,
                Guid cardId,
                IQuoteService service,
                CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.GetAsync(
                    UserId(context.User), boardId, cardId, token))))
            .RequireTenantPermission("quotes.view");

        quotes.MapGet("/pdf", async (
                HttpContext context,
                Guid boardId,
                Guid cardId,
                Guid? proposalTypeId,
                Guid? variantId,
                IQuotePdfService service,
                CancellationToken token) =>
            {
                var file = await service.GenerateAsync(
                    UserId(context.User), boardId, cardId, proposalTypeId, variantId, token);
                return Results.File(
                    file.Content,
                    "application/pdf",
                    file.FileName,
                    enableRangeProcessing: false);
            })
            .RequireTenantPermission("quotes.view");

        quotes.MapPost("/client-access", async (
                HttpContext context,
                Guid boardId,
                Guid cardId,
                CreateQuoteClientAccessRequest request,
                IQuoteClientAccessService service,
                CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.CreateAsync(
                    UserId(context.User), boardId, cardId, request, token))))
            .RequireTenantPermission("quotes.manage");

        quotes.MapPost("/client-access/extend", async (
                HttpContext context, Guid boardId, Guid cardId,
                ExtendQuoteClientAccessRequest request, IQuoteClientAccessService service, CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.ExtendAsync(UserId(context.User), boardId, cardId, request, token))))
            .RequireTenantPermission("quotes.manage");

        quotes.MapGet("/client-access", async (
                HttpContext context,
                Guid boardId,
                Guid cardId,
                IQuoteClientAccessService service,
                CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.GetStatusAsync(
                    UserId(context.User), boardId, cardId, token))))
            .RequireTenantPermission("quotes.manage");

        quotes.MapDelete("/client-access", async (
                HttpContext context,
                Guid boardId,
                Guid cardId,
                IQuoteClientAccessService service,
                CancellationToken token) =>
            {
                await service.RevokeAsync(UserId(context.User), boardId, cardId, token);
                return Results.Ok(ApiResponse.Success(new { revoked = true }));
            })
            .RequireTenantPermission("quotes.manage");

        quotes.MapPut("/", async (
                HttpContext context,
                Guid boardId,
                Guid cardId,
                SaveQuoteRequest request,
                IQuoteService service,
                CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.SaveAsync(
                    UserId(context.User), boardId, cardId, request, token))))
            .RequireTenantPermission("quotes.manage");

        quotes.MapGet("/calculation-preview", async (
                HttpContext context, Guid boardId, Guid cardId,
                IQuoteService service, CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.PreviewCalculationAsync(
                    UserId(context.User), boardId, cardId, token))))
            .RequireTenantPermission("quotes.manage");

        quotes.MapPost("/apply-calculation", async (
                HttpContext context, Guid boardId, Guid cardId,
                ApplyQuoteCalculationRequest request,
                IQuoteService service, CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.ApplyCalculationAsync(
                    UserId(context.User), boardId, cardId, request, token))))
            .RequireTenantPermission("quotes.manage");

        var client = endpoints.MapGroup("/api/v1/client/quotes");
        client.MapPost("/login", async (
                HttpContext context,
                QuoteClientLoginRequest request,
                IQuoteClientAccessService service,
                CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.LoginAsync(
                    request, context.Connection.RemoteIpAddress?.ToString(), token))));
        client.MapGet("/current", async (
                HttpContext context,
                IQuoteClientAccessService service,
                CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.GetAsync(ClientSession(context), token))));
        client.MapPut("/current/selection", async (
                HttpContext context,
                SubmitQuoteClientSelectionRequest request,
                IQuoteClientAccessService service,
                CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.SubmitSelectionAsync(
                    ClientSession(context), request, token))));

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

    private static string ClientSession(HttpContext context)
    {
        var value = context.Request.Headers["X-Quote-Client-Session"].ToString();
        return string.IsNullOrWhiteSpace(value)
            ? throw new IdentityException(401, "quote_client_session_invalid", "Введите пароль для доступа к предложению.")
            : value;
    }
}
