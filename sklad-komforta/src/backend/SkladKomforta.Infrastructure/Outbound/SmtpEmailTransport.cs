using System.Net;
using System.Net.Sockets;
using MailKit;
using MailKit.Net.Smtp;
using MailKit.Security;
using Microsoft.Extensions.Options;
using MimeKit;
using SkladKomforta.Application.Abstractions.Outbound;
using SkladKomforta.Application.Identity;
using SkladKomforta.Application.Outbound;
using SkladKomforta.Infrastructure.Configuration;

namespace SkladKomforta.Infrastructure.Outbound;

/// <summary>
/// SMTP через MailKit: порт 465 — TLS сразу, остальные — обязательный
/// STARTTLS, пароль не уходит открытым текстом. Сервер задаёт организация,
/// поэтому подключение разрешено только к публичным адресам из списка
/// портов (защита от обращения к внутренней сети сервера).
/// </summary>
internal sealed class SmtpEmailTransport(IOptions<OutboundOptions> options) : IEmailTransport
{
    private static readonly TimeSpan Timeout = TimeSpan.FromSeconds(30);

    /// <inheritdoc />
    public async Task SendAsync(EmailOutboundMessage message, CancellationToken cancellationToken)
    {
        if (!OutboundSettingsValidator.AllowedSmtpPorts.Contains(message.SmtpPort))
            throw Failure("Порт SMTP не разрешён.");

        using var mime = new MimeMessage();
        mime.From.Add(new MailboxAddress(message.SenderName ?? string.Empty, message.Address));
        mime.To.Add(MailboxAddress.Parse(message.Recipient));
        mime.Subject = message.Subject;
        var body = new BodyBuilder { TextBody = message.Body ?? string.Empty };
        if (message.Attachment is { } attachment)
            body.Attachments.Add(attachment.FileName, attachment.Content, ContentType.Parse(attachment.ContentType));
        mime.Body = body.ToMessageBody();

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(Timeout);
        using var client = new SmtpClient { Timeout = (int)Timeout.TotalMilliseconds };
        Socket? socket = null;
        try
        {
            socket = await ConnectSocketAsync(message.SmtpHost, message.SmtpPort, timeout.Token);
            await client.ConnectAsync(
                socket, message.SmtpHost, message.SmtpPort,
                message.SmtpPort == 465 ? SecureSocketOptions.SslOnConnect : SecureSocketOptions.StartTls,
                timeout.Token);
            socket = null; // теперь сокетом владеет SmtpClient
            await client.AuthenticateAsync(message.Address, message.Password, timeout.Token);
            await client.SendAsync(mime, timeout.Token);
            await client.DisconnectAsync(true, timeout.Token);
        }
        catch (AuthenticationException)
        {
            throw Failure("Почта не приняла адрес и пароль приложения. Проверьте их; обычный пароль от почты не подойдёт.");
        }
        catch (SmtpCommandException exception) when (exception.ErrorCode == SmtpErrorCode.RecipientNotAccepted)
        {
            throw Failure("Почтовый сервер не принял адрес получателя.");
        }
        catch (SmtpCommandException exception)
        {
            throw Failure($"Почтовый сервер отклонил письмо: {exception.Message}");
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw Failure("Почтовый сервер не ответил вовремя.");
        }
        catch (Exception exception) when (exception is SocketException or IOException or SslHandshakeException
                                              or SmtpProtocolException or ServiceNotConnectedException)
        {
            throw Failure($"Не удалось подключиться к почтовому серверу {message.SmtpHost}:{message.SmtpPort}.");
        }
        finally
        {
            socket?.Dispose();
        }
    }

    /// <summary>
    /// Подключается к первому разрешённому адресу узла. Проверенный адрес
    /// используется напрямую, поэтому подмена DNS после проверки не сработает.
    /// </summary>
    private async Task<Socket> ConnectSocketAsync(string host, int port, CancellationToken token)
    {
        IPAddress[] addresses;
        try
        {
            addresses = await Dns.GetHostAddressesAsync(host, token);
        }
        catch (SocketException)
        {
            throw Failure($"Почтовый сервер {host} не найден.");
        }

        var allowed = options.Value.AllowPrivateSmtpHosts
            ? addresses
            : addresses.Where(IsPublic).ToArray();
        if (allowed.Length == 0)
            throw Failure("Адрес почтового сервера недоступен для отправки.");

        SocketException? last = null;
        foreach (var address in allowed)
        {
            var socket = new Socket(address.AddressFamily, SocketType.Stream, ProtocolType.Tcp);
            try
            {
                await socket.ConnectAsync(new IPEndPoint(address, port), token);
                return socket;
            }
            catch (SocketException exception)
            {
                last = exception;
                socket.Dispose();
            }
            catch
            {
                socket.Dispose();
                throw;
            }
        }
        throw last!;
    }

    /// <summary>Адрес не относится к локальной, частной или служебной сети.</summary>
    internal static bool IsPublic(IPAddress address)
    {
        if (address.IsIPv4MappedToIPv6) address = address.MapToIPv4();
        if (IPAddress.IsLoopback(address) || address.Equals(IPAddress.Any) || address.Equals(IPAddress.IPv6Any))
            return false;
        if (address.AddressFamily == AddressFamily.InterNetwork)
        {
            var bytes = address.GetAddressBytes();
            return bytes[0] switch
            {
                0 or 10 or 127 => false,
                100 when bytes[1] is >= 64 and <= 127 => false,
                169 when bytes[1] == 254 => false,
                172 when bytes[1] is >= 16 and <= 31 => false,
                192 when bytes[1] == 168 => false,
                >= 224 => false,
                _ => true,
            };
        }
        return !(address.IsIPv6LinkLocal || address.IsIPv6SiteLocal || address.IsIPv6Multicast ||
                 (address.GetAddressBytes()[0] & 0xFE) == 0xFC);
    }

    private static IdentityException Failure(string message) => new(502, "outbound_email_failed", message);
}
