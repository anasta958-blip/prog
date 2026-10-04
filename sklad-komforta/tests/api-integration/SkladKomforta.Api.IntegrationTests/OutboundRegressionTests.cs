using System.Collections.Concurrent;
using System.Net;
using System.Net.Http.Json;
using System.Text.Json.Nodes;
using Microsoft.Extensions.DependencyInjection;
using SkladKomforta.Application.Abstractions.Outbound;

namespace SkladKomforta.Api.IntegrationTests;

public sealed partial class DatabaseRegressionTests
{
    private const string OutboundBotToken = "123456789:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsawQ";
    private const string OutboundPassword = "app-password-16x";

    /// <summary>
    /// Внешняя отправка на живой базе с подменёнными Telegram и SMTP: секреты
    /// не возвращаются и не попадают в аудит, топик и получатель выбираются по
    /// правилам настроек, файл и тексты собираются из шаблонов.
    /// </summary>
    [DatabaseFact]
    public async Task OutboundDeliveryAgainstRealDatabase()
    {
        await using var database = await RegressionDatabase.CreateAsync();
        var telegram = new RecordingTelegramTransport();
        var mail = new RecordingEmailTransport();
        await using var factory = new RegressionFactory(database.ConnectionString, services =>
        {
            services.AddSingleton<ITelegramTransport>(telegram);
            services.AddSingleton<IEmailTransport>(mail);
        });
        using var staff = factory.CreateClient();
        await SignInDirectorAsync(staff, OrderDraft());

        var executor = Text(await Send(staff, HttpMethod.Post, "/company/legal-entities", new
        {
            name = "Исполнитель", companyType = "ООО", legalName = "ООО Исполнитель",
            inn = "7707083893", kpp = "773601001", ogrn = "1027700132195", phone = "+79991234567",
            directorName = "Иванов Иван", signatoryName = "Иванов Иван", signatoryTitle = "Директор",
            bankName = "Тестовый банк", bankBik = "044525225", bankAccount = "40702810900000000001",
            corrAccount = "30101810400000000225", vatRates = new decimal?[] { 20 }, isDefault = true,
        }), "id");
        var client = Text(await Send(staff, HttpMethod.Post, "/company/clients", new
        {
            name = "Петров Пётр", companyName = "Петров Пётр", companyType = "person", phone = "+79990000000",
            passportSeries = "1234", passportNumber = "123456", passportIssuedBy = "Тестовый отдел",
        }), "id");
        var boards = (await Send(staff, HttpMethod.Get, "/kanbans/")).AsArray();
        var sales = Text(boards.Single(item => Text(item!, "code") == "sales")!, "id");
        var orders = Text(boards.Single(item => Text(item!, "code") == "orders")!, "id");
        string Column(JsonNode board, string name) =>
            Text(board["columns"]!.AsArray().Single(item => Text(item!, "name") == name)!, "id");
        var compose = Column(await Send(staff, HttpMethod.Get, $"/kanbans/{orders}"), "Составление");
        var start = Column(await Send(staff, HttpMethod.Get, $"/kanbans/{sales}"), "Подготовка");

        // По умолчанию ничего не настроено, шаблоны заполнены.
        var initial = await Send(staff, HttpMethod.Get, "/company/outbound");
        Assert.False(initial["telegram"]!["hasBotToken"]!.GetValue<bool>());
        Assert.Equal("{документ} №{номер} — {название}", Text(initial["telegram"]!, "captionTemplate"));
        Assert.Equal("{документ} №{номер} — {название}", Text(initial["email"]!, "subjectTemplate"));
        var channels = await Send(staff, HttpMethod.Get, "/outbound/channels");
        Assert.False(channels["telegramReady"]!.GetValue<bool>());
        Assert.False(channels["emailReady"]!.GetValue<bool>());

        // Неверные значения отклоняются.
        await Send(staff, HttpMethod.Put, "/company/outbound",
            OutboundSettings(botToken: "не-токен"), HttpStatusCode.BadRequest);
        await Send(staff, HttpMethod.Put, "/company/outbound",
            OutboundSettings(address: "office@company-example.ru"), HttpStatusCode.BadRequest);
        await Send(staff, HttpMethod.Put, "/company/outbound",
            OutboundSettings(address: "office@company-example.ru", smtpHost: "smtp.company-example.ru", smtpPort: 8080),
            HttpStatusCode.BadRequest);

        // Секреты принимаются только на запись.
        using (var response = await staff.PutAsJsonAsync("/api/v1/company/outbound",
                   OutboundSettings(botToken: OutboundBotToken, password: OutboundPassword)))
        {
            var raw = await response.Content.ReadAsStringAsync();
            Assert.Equal(HttpStatusCode.OK, response.StatusCode);
            Assert.DoesNotContain(OutboundBotToken, raw, StringComparison.Ordinal);
            Assert.DoesNotContain(OutboundPassword, raw, StringComparison.Ordinal);
        }
        var settings = await Send(staff, HttpMethod.Get, "/company/outbound");
        Assert.True(settings["telegram"]!["hasBotToken"]!.GetValue<bool>());
        Assert.True(settings["email"]!["hasPassword"]!.GetValue<bool>());
        Assert.Equal("smtp.gmail.com:465", Text(settings["email"]!, "detectedSmtpServer"));
        Assert.Equal(2, settings["telegram"]!["topics"]!.AsArray().Count);
        using (var audit = await staff.GetAsync("/api/v1/company/audit"))
        {
            var raw = await audit.Content.ReadAsStringAsync();
            Assert.Contains("outbound_settings", raw, StringComparison.Ordinal);
            Assert.DoesNotContain(OutboundBotToken, raw, StringComparison.Ordinal);
            Assert.DoesNotContain(OutboundPassword, raw, StringComparison.Ordinal);
        }

        channels = await Send(staff, HttpMethod.Get, "/outbound/channels");
        Assert.True(channels["telegramReady"]!.GetValue<bool>());
        Assert.True(channels["telegramTopicRequired"]!.GetValue<bool>());
        Assert.True(channels["emailReady"]!.GetValue<bool>());
        Assert.True(channels["emailRecipientRequired"]!.GetValue<bool>());

        // Комплектация в Telegram: без топика нельзя, топик — только из справочника.
        var order = await Send(staff, HttpMethod.Post, $"/kanbans/{orders}/orders", new
        {
            columnId = compose,
            order = new
            {
                title = "Склад: Заводская/5", objectType = "Квартира", clientId = client, executorCompanyId = executor,
                categories = Array.Empty<object>(),
            },
        });
        var orderCard = Text(order, "cardId");
        var orderNumber = (await Send(staff, HttpMethod.Get, $"/kanbans/{orders}/cards/{orderCard}"))["number"]!
            .GetValue<long>();
        var sendOrder = $"/outbound/kanbans/{orders}/cards/{orderCard}/send";
        await Send(staff, HttpMethod.Post, sendOrder, new { channel = "telegram" }, HttpStatusCode.BadRequest);
        await Send(staff, HttpMethod.Post, sendOrder, new { channel = "telegram", topicId = 99 }, HttpStatusCode.BadRequest);
        var sent = await Send(staff, HttpMethod.Post, sendOrder,
            new { channel = "telegram", topicId = 7, clientDate = "2026-10-03" });
        Assert.Equal("топик «Монтаж»", Text(sent, "destination"));
        Assert.Equal("Склад Заводская5 — 03.10.2026.pdf", Text(sent, "fileName"));
        var message = telegram.Messages.Last();
        Assert.Equal(OutboundBotToken, message.BotToken);
        Assert.Equal("-1001234567890", message.ChatId);
        Assert.Equal(7, message.TopicId);
        Assert.Equal($"Комплектация №{orderNumber} — Склад: Заводская/5", message.Text);
        Assert.Equal("%PDF", System.Text.Encoding.ASCII.GetString(message.Attachment!.Content, 0, 4));

        // Комплектация на почту: адрес обязателен и проверяется.
        await Send(staff, HttpMethod.Post, sendOrder, new { channel = "email" }, HttpStatusCode.BadRequest);
        await Send(staff, HttpMethod.Post, sendOrder, new { channel = "email", recipient = "не адрес" }, HttpStatusCode.BadRequest);
        await Send(staff, HttpMethod.Post, sendOrder,
            new { channel = "email", recipient = "client@example.com", clientDate = "2026-10-03" });
        var letter = mail.Messages.Last();
        Assert.Equal(("smtp.gmail.com", 465), (letter.SmtpHost, letter.SmtpPort));
        Assert.Equal(("sender@gmail.com", OutboundPassword), (letter.Address, letter.Password));
        Assert.Equal("Склад Комфорта", letter.SenderName);
        Assert.Equal("client@example.com", letter.Recipient);
        Assert.Equal($"Комплектация №{orderNumber} для Петров Пётр", letter.Subject);
        Assert.Equal("Добрый день! Направляем документ от 03.10.2026.", letter.Body);
        Assert.Equal("Склад Заводская5 — 03.10.2026.pdf", letter.Attachment!.FileName);

        // КП: вид документа в шаблоне — «КП».
        var quoteCard = Text(await Send(staff, HttpMethod.Post, $"/kanbans/{sales}/quotes", new
        {
            columnId = start,
            quote = new
            {
                quoteKind = "quote", title = "Лесная, 5", clientId = client, executorCompanyId = executor,
                selectionMode = "variant", proposalTypes = Array.Empty<object>(),
            },
        }), "cardId");
        await Send(staff, HttpMethod.Post, $"/outbound/kanbans/{sales}/cards/{quoteCard}/send",
            new { channel = "email", recipient = "client@example.com" });
        Assert.StartsWith("КП №", mail.Messages.Last().Subject, StringComparison.Ordinal);

        // Проверка: в Telegram — первый топик (по умолчанию не задан), на почту — себе.
        var test = await Send(staff, HttpMethod.Post, "/company/outbound/test/telegram");
        Assert.Equal("топик «Снабжение»", Text(test, "destination"));
        Assert.Equal(5, telegram.Messages.Last().TopicId);
        Assert.Null(telegram.Messages.Last().Attachment);
        await Send(staff, HttpMethod.Post, "/company/outbound/test/email");
        Assert.Equal("sender@gmail.com", mail.Messages.Last().Recipient);

        // С топиком и получателем по умолчанию отправка идёт всегда в них.
        await Send(staff, HttpMethod.Put, "/company/outbound",
            OutboundSettings(defaultTopicId: 5, recipient: "boss@example.com"));
        channels = await Send(staff, HttpMethod.Get, "/outbound/channels");
        Assert.False(channels["telegramTopicRequired"]!.GetValue<bool>());
        Assert.False(channels["emailRecipientRequired"]!.GetValue<bool>());
        await Send(staff, HttpMethod.Post, sendOrder, new { channel = "telegram", topicId = 7 });
        Assert.Equal(5, telegram.Messages.Last().TopicId);
        await Send(staff, HttpMethod.Post, sendOrder, new { channel = "email", recipient = "other@example.com" });
        Assert.Equal("boss@example.com", mail.Messages.Last().Recipient);

        // Новый адрес почты без пароля сбрасывает старый пароль; удалённый токен
        // выключает Telegram.
        await Send(staff, HttpMethod.Put, "/company/outbound",
            OutboundSettings(address: "sender@yandex.ru", clearBotToken: true));
        settings = await Send(staff, HttpMethod.Get, "/company/outbound");
        Assert.False(settings["email"]!["hasPassword"]!.GetValue<bool>());
        Assert.False(settings["telegram"]!["hasBotToken"]!.GetValue<bool>());
        await Send(staff, HttpMethod.Post, sendOrder, new { channel = "telegram" }, HttpStatusCode.Conflict);
        await Send(staff, HttpMethod.Post, sendOrder, new { channel = "email" }, HttpStatusCode.Conflict);
    }

    private static object OutboundSettings(
        string? botToken = null,
        bool clearBotToken = false,
        long? defaultTopicId = null,
        string address = "sender@gmail.com",
        string? password = null,
        string? recipient = null,
        string? smtpHost = null,
        int? smtpPort = null) => new
    {
        telegram = new
        {
            botToken, clearBotToken, chatId = "-1001234567890", usesTopics = true, defaultTopicId,
            topics = new[] { new { topicId = 5L, name = "Снабжение" }, new { topicId = 7L, name = "Монтаж" } },
            captionTemplate = "{документ} №{номер} — {название}",
        },
        email = new
        {
            address, password, clearPassword = false, senderName = "Склад Комфорта", smtpHost, smtpPort,
            subjectTemplate = "{документ} №{номер} для {заказчик}",
            bodyTemplate = "Добрый день! Направляем документ от {дата}.",
            defaultRecipient = recipient,
        },
    };
}

/// <summary>Telegram без сети: запоминает отправленные сообщения.</summary>
internal sealed class RecordingTelegramTransport : ITelegramTransport
{
    public ConcurrentQueue<TelegramOutboundMessage> Messages { get; } = new();

    public Task SendAsync(TelegramOutboundMessage message, CancellationToken cancellationToken)
    {
        Messages.Enqueue(message);
        return Task.CompletedTask;
    }
}

/// <summary>SMTP без сети: запоминает отправленные письма.</summary>
internal sealed class RecordingEmailTransport : IEmailTransport
{
    public ConcurrentQueue<EmailOutboundMessage> Messages { get; } = new();

    public Task SendAsync(EmailOutboundMessage message, CancellationToken cancellationToken)
    {
        Messages.Enqueue(message);
        return Task.CompletedTask;
    }
}
