namespace SkladKomforta.Application.Outbound;

/// <summary>SMTP-сервер и порт.</summary>
public sealed record SmtpServer(string Host, int Port)
{
    /// <inheritdoc />
    public override string ToString() => $"{Host}:{Port}";
}

/// <summary>
/// Известные почтовые сервисы, для которых сервер SMTP определяется по домену
/// адреса: Gmail, Яндекс и Mail.ru (порт 465, TLS). Для остальных адресов
/// сервер и порт задаются в настройках.
/// </summary>
public static class SmtpServerPresets
{
    private static readonly SmtpServer Gmail = new("smtp.gmail.com", 465);
    private static readonly SmtpServer Yandex = new("smtp.yandex.ru", 465);
    private static readonly SmtpServer MailRu = new("smtp.mail.ru", 465);

    private static readonly Dictionary<string, SmtpServer> ByDomain = new(StringComparer.OrdinalIgnoreCase)
    {
        ["gmail.com"] = Gmail,
        ["googlemail.com"] = Gmail,
        ["yandex.ru"] = Yandex,
        ["ya.ru"] = Yandex,
        ["yandex.com"] = Yandex,
        ["yandex.by"] = Yandex,
        ["yandex.kz"] = Yandex,
        ["narod.ru"] = Yandex,
        ["mail.ru"] = MailRu,
        ["inbox.ru"] = MailRu,
        ["list.ru"] = MailRu,
        ["bk.ru"] = MailRu,
        ["internet.ru"] = MailRu,
    };

    /// <summary>Сервер по домену адреса или <c>null</c>, если домен неизвестен.</summary>
    public static SmtpServer? Detect(string? address)
    {
        var at = address?.LastIndexOf('@') ?? -1;
        if (address is null || at < 0) return null;
        return ByDomain.GetValueOrDefault(address[(at + 1)..].Trim());
    }
}
