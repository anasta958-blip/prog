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
