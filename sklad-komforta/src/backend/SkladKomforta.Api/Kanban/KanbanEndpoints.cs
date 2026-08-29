using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using SkladKomforta.Api.Authorization;
using SkladKomforta.Application.Contracts;
using SkladKomforta.Application.Kanban;

namespace SkladKomforta.Api.Kanban;

/// <summary>REST endpoints рабочего пространства настроенных канбанов.</summary>
internal static class KanbanEndpoints
{
    public static IEndpointRouteBuilder MapKanbanEndpoints(this IEndpointRouteBuilder endpoints)
    {
        var kanbans = endpoints.MapGroup("/api/v1/kanbans").RequireAuthorization();
        kanbans.MapGet("/", async (IKanbanService service, CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.GetBoardsAsync(token))))
            .RequireTenantPermission("kanban.view");
        kanbans.MapGet("/{boardId:guid}", async (
                Guid boardId,
                IKanbanService service,
                CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.GetBoardAsync(boardId, token))))
            .RequireTenantPermission("kanban.view");
        kanbans.MapGet("/{boardId:guid}/cards", async (
                HttpContext context,
                Guid boardId,
                Guid columnId,
                int? page,
                int? pageSize,
                IKanbanService service,
                CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.GetCardsAsync(
                    UserId(context.User),
                    boardId,
                    new KanbanCardQuery(columnId, page ?? 1, pageSize ?? 20),
                    token))))
            .RequireTenantPermission("kanban.view");
        kanbans.MapGet("/{boardId:guid}/cards/{cardId:guid}", async (
                HttpContext context,
                Guid boardId,
                Guid cardId,
                IKanbanService service,
                CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.GetCardAsync(
                    UserId(context.User), boardId, cardId, token))))
            .RequireTenantPermission("kanban.view");
        kanbans.MapPost("/{boardId:guid}/cards", async (
                HttpContext context,
                Guid boardId,
                SaveKanbanCardRequest request,
                IKanbanService service,
                CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.CreateCardAsync(
                    UserId(context.User), boardId, request, token))))
            .RequireTenantPermission("kanban.cards.create");
        kanbans.MapPut("/{boardId:guid}/cards/{cardId:guid}", async (
                HttpContext context,
                Guid boardId,
                Guid cardId,
                SaveKanbanCardRequest request,
                IKanbanService service,
                CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.UpdateCardAsync(
                    UserId(context.User), boardId, cardId, request, token))))
            .RequireTenantPermission("kanban.cards.edit");
        kanbans.MapPost("/{boardId:guid}/cards/{cardId:guid}/move", async (
                HttpContext context,
                Guid boardId,
                Guid cardId,
                MoveKanbanCardRequest request,
                IKanbanService service,
                CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.MoveCardAsync(
                    UserId(context.User), boardId, cardId, request, token))))
            .RequireTenantPermission("kanban.cards.move");
        kanbans.MapDelete("/{boardId:guid}/cards/{cardId:guid}", async (
                HttpContext context,
                Guid boardId,
                Guid cardId,
                IKanbanService service,
                CancellationToken token) =>
            {
                await service.DeleteCardAsync(UserId(context.User), boardId, cardId, token);
                return Results.Ok(ApiResponse.Success(new { deleted = true }));
            })
            .RequireTenantPermission("kanban.cards.delete");
        return endpoints;
    }

    private static Guid UserId(ClaimsPrincipal user)
    {
        var value = user.FindFirst(JwtRegisteredClaimNames.Sub)?.Value ??
                    user.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        return Guid.TryParse(value, out var id)
            ? id
            : throw new SkladKomforta.Application.Identity.IdentityException(
                401, "token_invalid", "Токен доступа недействителен.");
    }
}
