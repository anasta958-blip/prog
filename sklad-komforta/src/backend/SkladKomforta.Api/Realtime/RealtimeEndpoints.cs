using System.Net.WebSockets;
using System.Security.Claims;
using System.Text;
using System.Text.Json;
using SkladKomforta.Application.Abstractions.Realtime;
using SkladKomforta.Application.Abstractions.Tenancy;
using SkladKomforta.Application.Contracts;
using SkladKomforta.Application.Identity;
using SkladKomforta.Infrastructure.Realtime;

namespace SkladKomforta.Api.Realtime;

/// <summary>
/// Поток уведомлений об изменениях. Подключение открывается по одноразовому
/// билету, который выдают защищённые endpoint-ы модулей
/// (<c>POST /api/v1/kanbans/realtime-ticket</c> с правом <c>kanban.view</c>,
/// <c>POST /api/v1/catalog/realtime-ticket</c> с правом <c>catalog.view</c>).
/// </summary>
internal static class RealtimeEndpoints
{
    /// <summary>Срок жизни билета: только на время установки соединения.</summary>
    private static readonly TimeSpan TicketLifetime = TimeSpan.FromSeconds(60);

    /// <summary>Интервал служебного сообщения, которое держит соединение через прокси.</summary>
    internal static TimeSpan PingInterval { get; set; } = TimeSpan.FromSeconds(25);

    /// <summary>Как часто перепроверяется, что сессия и членство в организации активны.</summary>
    internal static TimeSpan AccessCheckInterval { get; set; } = TimeSpan.FromSeconds(60);

    /// <summary>Регистрирует WebSocket-endpoint потока уведомлений.</summary>
    public static IEndpointRouteBuilder MapRealtimeEndpoints(this IEndpointRouteBuilder endpoints)
    {
        // Без RequireAuthorization: браузерный WebSocket не передаёт заголовок
        // Authorization. Аутентификацией служит одноразовый билет, выданный
        // endpoint-ом с проверкой прав модуля.
        endpoints.MapGet("/api/v1/realtime", ConnectAsync);
        return endpoints;
    }

    /// <summary>Выдаёт билет на тему для текущего пользователя, сессии и организации.</summary>
    public static async Task<IResult> IssueTicketAsync(
        HttpContext context,
        string topic,
        ITenantContext tenantContext,
        IRealtimeTicketStore tickets,
        CancellationToken token)
    {
        if (!tenantContext.IsResolved)
            throw new IdentityException(403, "tenant_required", "Организация не выбрана.");
        var ticket = await tickets.IssueAsync(
            new RealtimeTicket(
                GuidClaim(context.User, "sub"),
                GuidClaim(context.User, "session_id"),
                tenantContext.OrganizationId,
                topic),
            TicketLifetime,
            token);
        return Results.Ok(ApiResponse.Success(new { ticket, topic }));
    }

    private static async Task ConnectAsync(
        HttpContext context,
        IRealtimeTicketStore tickets,
        RealtimeHub hub,
        IServiceScopeFactory scopes)
    {
        if (!context.WebSockets.IsWebSocketRequest)
        {
            context.Response.StatusCode = StatusCodes.Status400BadRequest;
            return;
        }
        var ticket = await tickets.RedeemAsync(context.Request.Query["ticket"].ToString(), context.RequestAborted);
        if (ticket is null || !RealtimeTopics.IsKnown(ticket.Topic))
        {
            context.Response.StatusCode = StatusCodes.Status401Unauthorized;
            return;
        }

        using var socket = await context.WebSockets.AcceptWebSocketAsync();
        var subscriber = await hub.RegisterAsync(ticket.OrganizationId, ticket.Topic, context.RequestAborted);
        using var lifetime = CancellationTokenSource.CreateLinkedTokenSource(context.RequestAborted);
        var receiving = DrainIncomingAsync(socket, lifetime);
        try
        {
            await SendAsync(socket, Service(ticket.Topic, "ready"), lifetime.Token);
            var accessCheckedAt = DateTimeOffset.UtcNow;
            while (!lifetime.IsCancellationRequested && socket.State == WebSocketState.Open)
            {
                string message;
                using (var wait = CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token))
                {
                    wait.CancelAfter(PingInterval);
                    try
                    {
                        message = await subscriber.Messages.Reader.ReadAsync(wait.Token);
                    }
                    catch (OperationCanceledException) when (!lifetime.IsCancellationRequested)
                    {
                        message = Service(ticket.Topic, "ping");
                    }
                }

                if (DateTimeOffset.UtcNow - accessCheckedAt >= AccessCheckInterval)
                {
                    accessCheckedAt = DateTimeOffset.UtcNow;
                    if (!await IsActiveAsync(scopes, ticket, lifetime.Token))
                    {
                        await socket.CloseOutputAsync(
                            WebSocketCloseStatus.PolicyViolation, "access_revoked", CancellationToken.None);
                        break;
                    }
                }
                await SendAsync(socket, message, lifetime.Token);
            }
        }
        catch (OperationCanceledException)
        {
            // Клиент отключился или сервер останавливается.
        }
        catch (WebSocketException)
        {
            // Соединение оборвано; клиент переподключится сам.
        }
        finally
        {
            hub.Unregister(subscriber);
            await lifetime.CancelAsync();
            await receiving;
        }
    }

    /// <summary>
    /// Читает входящие кадры только ради обнаружения закрытия: клиент ничего не
    /// отправляет, а любые данные от него игнорируются.
    /// </summary>
    private static async Task DrainIncomingAsync(WebSocket socket, CancellationTokenSource lifetime)
    {
        var buffer = new byte[256];
        try
        {
            while (socket.State == WebSocketState.Open)
            {
                var result = await socket.ReceiveAsync(buffer, lifetime.Token);
                if (result.MessageType == WebSocketMessageType.Close) break;
            }
        }
        catch (Exception exception) when (exception is OperationCanceledException or WebSocketException)
        {
        }
        finally
        {
            await lifetime.CancelAsync();
        }
    }

    private static async Task<bool> IsActiveAsync(IServiceScopeFactory scopes, RealtimeTicket ticket, CancellationToken token)
    {
        await using var scope = scopes.CreateAsyncScope();
        var validator = scope.ServiceProvider.GetRequiredService<ITenantAccessValidator>();
        return await validator.IsActiveAsync(ticket.UserId, ticket.SessionId, ticket.OrganizationId, token);
    }

    private static Task SendAsync(WebSocket socket, string message, CancellationToken token) =>
        socket.SendAsync(Encoding.UTF8.GetBytes(message), WebSocketMessageType.Text, true, token);

    private static string Service(string topic, string kind) =>
        JsonSerializer.Serialize(new RealtimeMessage(topic, kind, null, null), RealtimeChannels.JsonOptions);

    private static Guid GuidClaim(ClaimsPrincipal user, string name) =>
        Guid.TryParse(user.FindFirst(name)?.Value, out var value)
            ? value
            : throw new IdentityException(401, "token_invalid", "Токен доступа недействителен.");
}
