using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using SkladKomforta.Application.Abstractions.Outbound;
using SkladKomforta.Application.Identity;

namespace SkladKomforta.Infrastructure.Outbound;

/// <summary>
/// Telegram Bot API: <c>sendDocument</c> для файла, <c>sendMessage</c> для
/// проверки. Токен входит в адрес запроса, поэтому именованный клиент
/// регистрируется без журналирования HTTP (см. <c>DependencyInjection</c>).
/// </summary>
internal sealed class TelegramBotTransport(IHttpClientFactory httpClientFactory) : ITelegramTransport
{
    public const string ClientName = "telegram-bot";
    public static readonly Uri BaseAddress = new("https://api.telegram.org/");

    /// <inheritdoc />
    public async Task SendAsync(TelegramOutboundMessage message, CancellationToken cancellationToken)
    {
        using var content = new MultipartFormDataContent
        {
            // Имя файла в заголовке части — UTF-8 (кириллица), как ждёт Telegram.
            HeaderEncodingSelector = (_, _) => Encoding.UTF8,
        };
        content.Add(new StringContent(message.ChatId), "chat_id");
        if (message.TopicId is { } topic)
            content.Add(new StringContent(topic.ToString(CultureInfo.InvariantCulture)), "message_thread_id");

        string method;
        if (message.Attachment is { } attachment)
        {
            method = "sendDocument";
            if (!string.IsNullOrEmpty(message.Text)) content.Add(new StringContent(message.Text), "caption");
            var file = new ByteArrayContent(attachment.Content);
            file.Headers.ContentType = new MediaTypeHeaderValue(attachment.ContentType);
            file.Headers.TryAddWithoutValidation(
                "Content-Disposition",
                $"form-data; name=\"document\"; filename=\"{attachment.FileName.Replace("\"", "'", StringComparison.Ordinal)}\"");
            content.Add(file);
        }
        else
        {
            method = "sendMessage";
            content.Add(new StringContent(message.Text ?? string.Empty), "text");
        }

        var client = httpClientFactory.CreateClient(ClientName);
        HttpResponseMessage response;
        try
        {
            response = await client.PostAsync(MethodUri(message.BotToken, method), content, cancellationToken);
        }
        catch (HttpRequestException)
        {
            throw Failure("Не удалось связаться с Telegram. Проверьте доступ сервера к api.telegram.org.");
        }
        catch (TaskCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw Failure("Telegram не ответил вовремя. Повторите отправку.");
        }

        using (response)
        {
            if (response.IsSuccessStatusCode) return;
            var description = await DescriptionAsync(response, cancellationToken);
            throw Failure(Explain(response.StatusCode, description));
        }
    }

    /// <summary>
    /// Абсолютный адрес метода Bot API. Относительный адрес нельзя: токен
    /// <c>123456:AA…</c> содержит двоеточие, и <c>bot123456:</c> читается как
    /// схема URI.
    /// </summary>
    internal static Uri MethodUri(string botToken, string method) =>
        new($"{BaseAddress.AbsoluteUri}bot{botToken}/{method}", UriKind.Absolute);

    /// <summary>Понятный текст ошибки Bot API.</summary>
    internal static string Explain(HttpStatusCode status, string? description)
    {
        var text = description?.ToLowerInvariant() ?? string.Empty;
        if (status == HttpStatusCode.Unauthorized || text.Contains("unauthorized", StringComparison.Ordinal))
            return "Telegram не принял токен бота. Проверьте токен в настройках.";
        if (text.Contains("message thread not found", StringComparison.Ordinal) ||
            text.Contains("topic", StringComparison.Ordinal) && text.Contains("not found", StringComparison.Ordinal))
            return "Топик не найден в группе. Проверьте ID топика.";
        if (text.Contains("chat not found", StringComparison.Ordinal))
            return "Группа не найдена. Проверьте ID группы и что бот добавлен в неё.";
        if (status == HttpStatusCode.Forbidden || text.Contains("not enough rights", StringComparison.Ordinal))
            return "Бот не может писать в группу: добавьте его в группу и разрешите отправку сообщений.";
        if (status == HttpStatusCode.TooManyRequests)
            return "Telegram временно ограничил отправку. Повторите через минуту.";
        if (status == HttpStatusCode.RequestEntityTooLarge || text.Contains("too big", StringComparison.Ordinal))
            return "Файл слишком большой для Telegram.";
        return string.IsNullOrWhiteSpace(description)
            ? "Telegram отклонил отправку."
            : $"Telegram отклонил отправку: {description}";
    }

    private static async Task<string?> DescriptionAsync(HttpResponseMessage response, CancellationToken token)
    {
        try
        {
            await using var stream = await response.Content.ReadAsStreamAsync(token);
            using var json = await JsonDocument.ParseAsync(stream, cancellationToken: token);
            return json.RootElement.TryGetProperty("description", out var description) &&
                   description.ValueKind == JsonValueKind.String
                ? description.GetString()
                : null;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private static IdentityException Failure(string message) => new(502, "outbound_telegram_failed", message);
}
