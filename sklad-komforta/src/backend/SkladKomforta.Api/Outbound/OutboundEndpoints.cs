using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using SkladKomforta.Api.Authorization;
using SkladKomforta.Application.Contracts;
using SkladKomforta.Application.Identity;
using SkladKomforta.Application.Outbound;

namespace SkladKomforta.Api.Outbound;

/// <summary>
/// HTTP-граница внешней отправки: настройки (право
/// <c>outbound.settings.manage</c>) и отправка документа карточки (право
/// <c>documents.send</c>).
/// </summary>
internal static class OutboundEndpoints
{
    private const string ManagePermission = "outbound.settings.manage";
    private const string SendPermission = "documents.send";

    /// <summary>Подключает настройки, проверку, готовность каналов и отправку.</summary>
    public static IEndpointRouteBuilder MapOutboundEndpoints(this IEndpointRouteBuilder endpoints)
    {
        var settings = endpoints.MapGroup("/api/v1/company/outbound").RequireAuthorization();

        settings.MapGet("/", async (IOutboundSettingsService service, CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.GetAsync(token))))
            .RequireTenantPermission(ManagePermission);

        settings.MapPut("/", async (
                HttpContext context, SaveOutboundSettingsRequest request,
                IOutboundSettingsService service, CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.SaveAsync(UserId(context.User), request, token))))
            .RequireTenantPermission(ManagePermission);

        // Проверка ничего не меняет, но изменяющим методом: она отправляет сообщение.
        settings.MapPost("/test/{channel}", async (
                string channel, IOutboundSettingsService service, CancellationToken token) =>
                Results.Ok(ApiResponse.Success(new { destination = await service.TestAsync(channel, token) })))
            .RequireTenantPermission(ManagePermission);

        // Отправка не меняет данные канбана, поэтому вне /api/v1/kanbans: иначе
        // каждый отправленный файл рассылал бы сигнал обновления всем канбанам.
        var delivery = endpoints.MapGroup("/api/v1/outbound").RequireAuthorization();

        delivery.MapGet("/channels", async (IOutboundSettingsService service, CancellationToken token) =>
                Results.Ok(ApiResponse.Success(await service.GetChannelsAsync(token))))
            .RequireTenantPermission(SendPermission);

        delivery.MapPost("/kanbans/{boardId:guid}/cards/{cardId:guid}/send", async (
                HttpContext context, Guid boardId, Guid cardId, SendDocumentRequest request,
                IDocumentDeliveryService service, CancellationToken token) =>
                Results.Ok(ApiResponse.Success(
                    await service.SendAsync(UserId(context.User), boardId, cardId, request, token))))
            .RequireTenantPermission(SendPermission);

        return endpoints;
    }

    /// <summary>Извлекает UUID только из уже проверенного JWT.</summary>
    private static Guid UserId(ClaimsPrincipal user)
    {
        var value = user.FindFirst(JwtRegisteredClaimNames.Sub)?.Value ??
                    user.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        return Guid.TryParse(value, out var id)
            ? id
            : throw new IdentityException(401, "token_invalid", "Токен доступа недействителен.");
    }
}
