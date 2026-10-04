using System.Net;
using SkladKomforta.Application.Identity;
using SkladKomforta.Application.Outbound;
using SkladKomforta.Infrastructure.Outbound;

namespace SkladKomforta.Api.IntegrationTests;

public sealed class OutboundTests
{
    private static readonly OutboundTemplateValues Values =
        new("КП", 15, "Лесная, 5", "Петров И. И.", new DateOnly(2026, 10, 3));

    private static SaveOutboundSettingsRequest Request(
        SaveOutboundTelegramRequest? telegram = null, SaveOutboundEmailRequest? email = null) => new(
        telegram ?? new SaveOutboundTelegramRequest(null, false, null, false, null, [], null),
        email ?? new SaveOutboundEmailRequest(null, null, false, null, null, null, null, null, null));

    [Fact]
    public void TemplateReplacesPlaceholdersAndKeepsUnknownWords()
    {
        Assert.Equal("КП №15 — Лесная, 5", OutboundTemplate.Render(OutboundTemplate.DefaultTemplate, Values));
        Assert.Equal(
            "Счёт по объекту Лесная, 5 для Петров И. И. от 03.10.2026 {прочее}",
            OutboundTemplate.Render("Счёт по объекту {название} для {заказчик} от {дата} {прочее}", Values));
        Assert.Equal("Комплектация №15 для", OutboundTemplate.Render(
            "Комплектация №{номер} для {заказчик}", Values with { ClientName = null }));
        Assert.Equal(string.Empty, OutboundTemplate.Render("", Values));
    }

    [Fact]
    public void FileNameIsTitleAndDateWithoutForbiddenCharacters()
    {
        Assert.Equal("Лесная, 5 — 03.10.2026.pdf", OutboundTemplate.FileName(Values));
        Assert.Equal("Склад Заводская5 — 03.10.2026.pdf",
            OutboundTemplate.FileName(Values with { Title = "Склад: Заводская/5" }));
        Assert.Equal("КП — 03.10.2026.pdf", OutboundTemplate.FileName(Values with { Title = "  ?*  " }));
    }

    [Theory]
    [InlineData("user@gmail.com", "smtp.gmail.com:465")]
    [InlineData("User@Yandex.RU", "smtp.yandex.ru:465")]
    [InlineData("user@bk.ru", "smtp.mail.ru:465")]
    [InlineData("user@company.ru", null)]
    [InlineData(null, null)]
    public void SmtpServerIsDetectedForKnownDomains(string? address, string? expected) =>
        Assert.Equal(expected, SmtpServerPresets.Detect(address)?.ToString());

    [Fact]
    public void ValidatorNormalizesAndRejectsInvalidSettings()
    {
        var normalized = OutboundSettingsValidator.Validate(Request(
            new SaveOutboundTelegramRequest(
                " 123456789:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsawQ ", false, " -1001234567890 ", true, 5,
                [new OutboundTelegramTopic(5, " Снабжение ")], null),
            new SaveOutboundEmailRequest(
                "sender@gmail.com", "secret", false, "Склад", "ignored.example.com", 25, " ", null, null)));
        Assert.Equal("123456789:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsawQ", normalized.BotToken);
        Assert.Equal("-1001234567890", normalized.ChatId);
        Assert.Equal("Снабжение", normalized.Topics.Single().Name);
        Assert.Equal(OutboundTemplate.DefaultTemplate, normalized.CaptionTemplate);
        Assert.Equal(OutboundTemplate.DefaultTemplate, normalized.SubjectTemplate);
        // Для Gmail сервер определяется сам, присланные значения не хранятся.
        Assert.Null(normalized.SmtpHost);

        // Пустая подпись разрешена: в Telegram уйдёт только файл.
        Assert.Equal(string.Empty, OutboundSettingsValidator.Validate(Request(
            new SaveOutboundTelegramRequest(null, false, null, false, null, [], ""))).CaptionTemplate);

        void Rejects(SaveOutboundSettingsRequest request) =>
            Assert.Equal("outbound_settings_invalid",
                Assert.Throws<IdentityException>(() => OutboundSettingsValidator.Validate(request)).Code);
        Rejects(Request(new SaveOutboundTelegramRequest("token", false, null, false, null, [], null)));
        Rejects(Request(new SaveOutboundTelegramRequest(null, false, "group", false, null, [], null)));
        Rejects(Request(new SaveOutboundTelegramRequest(null, false, null, true, null,
            [new OutboundTelegramTopic(5, "А"), new OutboundTelegramTopic(5, "Б")], null)));
        Rejects(Request(email: new SaveOutboundEmailRequest("не адрес", null, false, null, null, null, null, null, null)));
        Rejects(Request(email: new SaveOutboundEmailRequest("a@company.ru", null, false, null, null, null, null, null, null)));
        Rejects(Request(email: new SaveOutboundEmailRequest(
            "a@company.ru", null, false, null, "smtp.company.ru", 6379, null, null, null)));
        Rejects(Request(email: new SaveOutboundEmailRequest(
            "a@company.ru", null, false, null, "localhost", 587, null, null, null)));
    }

    [Fact]
    public void TelegramMethodUriKeepsTokenWithColonInPath()
    {
        var uri = TelegramBotTransport.MethodUri("123456789:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsawQ", "sendDocument");
        Assert.Equal("api.telegram.org", uri.Host);
        Assert.Equal("/bot123456789:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsawQ/sendDocument", uri.AbsolutePath);
    }

    [Theory]
    [InlineData(HttpStatusCode.Unauthorized, "Unauthorized", "токен")]
    [InlineData(HttpStatusCode.BadRequest, "Bad Request: chat not found", "Группа не найдена")]
    [InlineData(HttpStatusCode.BadRequest, "Bad Request: message thread not found", "Топик не найден")]
    [InlineData(HttpStatusCode.Forbidden, "Forbidden: bot is not a member of the supergroup chat", "Бот не может писать")]
    [InlineData(HttpStatusCode.TooManyRequests, "Too Many Requests: retry after 5", "через минуту")]
    public void TelegramErrorsAreExplained(HttpStatusCode status, string description, string expected) =>
        Assert.Contains(expected, TelegramBotTransport.Explain(status, description), StringComparison.Ordinal);

    [Theory]
    [InlineData("8.8.8.8", true)]
    [InlineData("2a00:1450:4010:c05::6c", true)]
    [InlineData("127.0.0.1", false)]
    [InlineData("10.1.2.3", false)]
    [InlineData("172.18.0.5", false)]
    [InlineData("192.168.1.10", false)]
    [InlineData("169.254.169.254", false)]
    [InlineData("100.64.0.1", false)]
    [InlineData("::1", false)]
    [InlineData("fd00::1", false)]
    [InlineData("::ffff:10.0.0.1", false)]
    public void SmtpConnectsOnlyToPublicAddresses(string address, bool expected) =>
        Assert.Equal(expected, SmtpEmailTransport.IsPublic(IPAddress.Parse(address)));
}
