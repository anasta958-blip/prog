namespace SkladKomforta.Infrastructure.Configuration;

/// <summary>Ограничения внешней отправки документов.</summary>
public sealed class OutboundOptions
{
    /// <summary>Имя секции конфигурации ASP.NET Core.</summary>
    public const string SectionName = "Outbound";

    /// <summary>
    /// Разрешает SMTP-серверы в частных и локальных сетях (например, тестовый
    /// Mailpit). По умолчанию выключено: адрес сервера задаёт организация, и
    /// обращение к внутренней сети сервера должно быть невозможно.
    /// </summary>
    public bool AllowPrivateSmtpHosts { get; init; }
}
