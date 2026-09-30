using System.Net.WebSockets;
using System.Text;
using System.Text.Json.Nodes;
using System.Threading.Channels;
using Microsoft.AspNetCore.Mvc.Testing;

namespace SkladKomforta.Api.IntegrationTests;

/// <summary>Тестовое подключение к потоку уведомлений через in-memory сервер.</summary>
internal sealed class RealtimeListener : IAsyncDisposable
{
    private static readonly TimeSpan WaitTimeout = TimeSpan.FromSeconds(10);

    private readonly WebSocket _socket;
    private readonly Channel<JsonNode> _messages = Channel.CreateUnbounded<JsonNode>();
    private readonly CancellationTokenSource _stop = new();
    private readonly Task _receiving;

    private RealtimeListener(WebSocket socket)
    {
        _socket = socket;
        _receiving = ReceiveAsync();
    }

    /// <summary>Подключается по билету и ждёт служебное сообщение готовности.</summary>
    public static async Task<RealtimeListener> ConnectAsync<TEntryPoint>(
        WebApplicationFactory<TEntryPoint> factory,
        string ticket)
        where TEntryPoint : class
    {
        var socket = await factory.Server.CreateWebSocketClient().ConnectAsync(Uri(factory, ticket), CancellationToken.None);
        var listener = new RealtimeListener(socket);
        await listener.WaitAsync(message => (string?)message["kind"] == "ready");
        return listener;
    }

    /// <summary>Проверяет, что сервер не принимает подключение по этому билету.</summary>
    public static async Task ExpectRejectedAsync<TEntryPoint>(
        WebApplicationFactory<TEntryPoint> factory,
        string ticket)
        where TEntryPoint : class
    {
        await Assert.ThrowsAnyAsync<Exception>(() =>
            factory.Server.CreateWebSocketClient().ConnectAsync(Uri(factory, ticket), CancellationToken.None));
    }

    /// <summary>Ждёт первое сообщение, удовлетворяющее условию; остальные пропускает.</summary>
    public async Task<JsonNode> WaitAsync(Func<JsonNode, bool> predicate)
    {
        using var timeout = new CancellationTokenSource(WaitTimeout);
        while (true)
        {
            var message = await _messages.Reader.ReadAsync(timeout.Token);
            if (predicate(message)) return message;
        }
    }

    public async ValueTask DisposeAsync()
    {
        await _stop.CancelAsync();
        try
        {
            await _receiving;
        }
        catch (OperationCanceledException)
        {
        }
        _socket.Dispose();
        _stop.Dispose();
    }

    private static Uri Uri<TEntryPoint>(WebApplicationFactory<TEntryPoint> factory, string ticket)
        where TEntryPoint : class =>
        new UriBuilder(factory.Server.BaseAddress)
        {
            Scheme = "ws",
            Path = "/api/v1/realtime",
            Query = "ticket=" + System.Uri.EscapeDataString(ticket),
        }.Uri;

    private async Task ReceiveAsync()
    {
        var buffer = new byte[4096];
        try
        {
            while (_socket.State == WebSocketState.Open)
            {
                var result = await _socket.ReceiveAsync(buffer, _stop.Token);
                if (result.MessageType == WebSocketMessageType.Close) break;
                _messages.Writer.TryWrite(JsonNode.Parse(Encoding.UTF8.GetString(buffer, 0, result.Count))!);
            }
        }
        catch (Exception exception) when (exception is OperationCanceledException or WebSocketException)
        {
        }
        finally
        {
            _messages.Writer.TryComplete();
        }
    }
}
