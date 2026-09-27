using System.Text.Json;
using Microsoft.Extensions.Logging;
using SkladKomforta.Application.Abstractions.Caching;
using SkladKomforta.Application.Company;
using SkladKomforta.Application.Identity;
using SkladKomforta.Domain.Company;
using UglyToad.PdfPig;
using UglyToad.PdfPig.DocumentLayoutAnalysis.TextExtractor;

namespace SkladKomforta.Infrastructure.Company;

/// <summary>
/// Поиск по публичному сервису ФНС egrul.nalog.ru — тем же способом, что и в
/// прежней PHP-версии. Основные реквизиты берутся из JSON поиска, адрес и e-mail —
/// из первых страниц PDF-выписки. Если выписку получить не удалось, эти поля пустые,
/// а остальные реквизиты всё равно возвращаются.
/// </summary>
internal sealed class EgrulCompanyRegistryLookup(
    HttpClient http,
    IApplicationCache cache,
    ILogger<EgrulCompanyRegistryLookup> logger) : ICompanyRegistryLookup
{
    /// <summary>Базовый адрес сервиса; задаётся при регистрации typed HttpClient.</summary>
    internal static readonly Uri BaseAddress = new("https://egrul.nalog.ru/");

    private static readonly TimeSpan CacheLifetime = TimeSpan.FromHours(24);
    private static readonly TimeSpan ExtractPollDelay = TimeSpan.FromMilliseconds(500);
    private const int ExtractPollAttempts = 16;
    private const int ExtractPagesToRead = 2;

    private static readonly Action<ILogger, string, Exception?> LogRegistryFailure =
        LoggerMessage.Define<string>(
            LogLevel.Warning,
            new EventId(2201, nameof(LogRegistryFailure)),
            "Поиск по ИНН в ЕГРЮЛ: {Reason}.");

    /// <inheritdoc />
    public async Task<CompanyRegistryRecord> FindByInnAsync(string inn, CancellationToken cancellationToken)
    {
        var normalized = new string((inn ?? string.Empty).Where(char.IsAsciiDigit).ToArray());
        if (!TaxpayerNumber.IsValid(normalized))
        {
            throw new IdentityException(400, "inn_invalid", "ИНН указан неверно: проверьте количество цифр и контрольное число.");
        }

        // Версия в ключе отделяет записи прежнего формата без e-mail.
        var cacheKey = $"registry:egrul:v2:{normalized}";
        var cached = await cache.GetStringAsync(cacheKey, cancellationToken);
        if (cached is not null)
        {
            return JsonSerializer.Deserialize<CompanyRegistryRecord>(cached)!;
        }

        (CompanyRegistryRecord Record, string? ExtractToken)? found;
        try
        {
            found = await SearchAsync(normalized, cancellationToken);
        }
        catch (Exception exception) when (exception is HttpRequestException or JsonException or TaskCanceledException &&
                                          !cancellationToken.IsCancellationRequested)
        {
            LogRegistryFailure(logger, "поиск завершился ошибкой", exception);
            throw Unavailable();
        }

        if (found is null)
        {
            throw new IdentityException(404, "registry_not_found", "В ЕГРЮЛ/ЕГРИП нет записи с таким ИНН.");
        }

        var record = found.Value.Record;
        if (found.Value.ExtractToken is { } extractToken)
        {
            var extract = await TryReadExtractAsync(extractToken, cancellationToken);
            record = record with
            {
                // У ИП в выписке только адрес инспекции ФНС, он не является адресом предпринимателя.
                Address = record.CompanyType == "ooo" ? extract.Address : null,
                Email = extract.Email,
            };
        }

        await cache.SetStringAsync(cacheKey, JsonSerializer.Serialize(record), CacheLifetime, cancellationToken);
        return record;
    }

    private async Task<(CompanyRegistryRecord Record, string? ExtractToken)?> SearchAsync(
        string inn,
        CancellationToken cancellationToken)
    {
        using var form = new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["query"] = inn,
            ["page"] = string.Empty,
            ["region"] = string.Empty,
            ["PreventChromeAutocomplete"] = string.Empty,
        });
        using var searchResponse = await http.PostAsync(string.Empty, form, cancellationToken);
        searchResponse.EnsureSuccessStatusCode();
        using var search = JsonDocument.Parse(await searchResponse.Content.ReadAsStringAsync(cancellationToken));
        if (search.RootElement.TryGetProperty("captchaRequired", out var captcha) && captcha.ValueKind == JsonValueKind.True)
        {
            LogRegistryFailure(logger, "сервис запросил капчу", null);
            throw Unavailable();
        }

        var token = search.RootElement.TryGetProperty("t", out var t) ? t.GetString() : null;
        if (string.IsNullOrEmpty(token))
        {
            throw Unavailable();
        }

        var result = await http.GetStringAsync($"search-result/{Uri.EscapeDataString(token)}", cancellationToken);
        return EgrulResponseParser.ParseSearchResult(result, inn);
    }

    /// <summary>
    /// Заказывает PDF-выписку, дожидается готовности и читает адрес и e-mail с первых страниц.
    /// Любая ошибка этого необязательного шага только записывается в лог.
    /// </summary>
    private async Task<(string? Address, string? Email)> TryReadExtractAsync(
        string extractToken,
        CancellationToken cancellationToken)
    {
        var escaped = Uri.EscapeDataString(extractToken);
        try
        {
            using (var request = await http.GetAsync($"vyp-request/{escaped}", cancellationToken))
            {
                request.EnsureSuccessStatusCode();
            }

            var ready = false;
            for (var attempt = 0; attempt < ExtractPollAttempts && !ready; attempt++)
            {
                await Task.Delay(ExtractPollDelay, cancellationToken);
                using var status = JsonDocument.Parse(
                    await http.GetStringAsync($"vyp-status/{escaped}", cancellationToken));
                ready = status.RootElement.TryGetProperty("status", out var value) && value.GetString() == "ready";
            }

            if (!ready)
            {
                LogRegistryFailure(logger, "выписка не готова вовремя, адрес и e-mail не заполнены", null);
                return (null, null);
            }

            var pdf = await http.GetByteArrayAsync($"vyp-download/{escaped}", cancellationToken);
            using var document = PdfDocument.Open(pdf);
            // Оба раздела находятся в начале выписки; остальные страницы (ОКВЭД, история) не нужны.
            var text = string.Join('\n', Enumerable.Range(1, Math.Min(ExtractPagesToRead, document.NumberOfPages))
                .Select(page => ContentOrderTextExtractor.GetText(document.GetPage(page))));
            return (EgrulResponseParser.ParseAddress(text), EgrulResponseParser.ParseEmail(text));
        }
        catch (Exception exception) when (!cancellationToken.IsCancellationRequested)
        {
            LogRegistryFailure(logger, "не удалось прочитать выписку, адрес и e-mail не заполнены", exception);
            return (null, null);
        }
    }

    private static IdentityException Unavailable() =>
        new(503, "registry_unavailable", "Сервис ФНС временно недоступен. Повторите попытку позже или заполните реквизиты вручную.");
}
