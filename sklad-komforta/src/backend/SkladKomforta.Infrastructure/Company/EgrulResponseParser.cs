using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;
using SkladKomforta.Application.Company;

namespace SkladKomforta.Infrastructure.Company;

/// <summary>
/// Разбор ответов egrul.nalog.ru без сетевой логики. Формат неофициальный,
/// поэтому каждый шаг терпим к отсутствующим полям и не бросает исключений.
/// </summary>
internal static partial class EgrulResponseParser
{
    /// <summary>
    /// Выбирает из <c>search-result</c> строку с точным совпадением ИНН.
    /// </summary>
    /// <param name="json">Тело ответа <c>/search-result/{token}</c>.</param>
    /// <param name="inn">Запрошенный ИНН.</param>
    /// <returns>Реквизиты без адреса и токен выписки либо <see langword="null" />.</returns>
    public static (CompanyRegistryRecord Record, string? ExtractToken)? ParseSearchResult(string json, string inn)
    {
        using var document = JsonDocument.Parse(json);
        if (!document.RootElement.TryGetProperty("rows", out var rows) || rows.ValueKind != JsonValueKind.Array)
        {
            return null;
        }

        foreach (var row in rows.EnumerateArray())
        {
            if (Text(row, "i") != inn)
            {
                continue;
            }

            var isIndividual = Text(row, "k") == "fl" || inn.Length == 12;
            var fullName = Text(row, "n") ?? string.Empty;
            string? directorName;
            string? directorTitle;
            string shortName;
            string legalName;
            if (isIndividual)
            {
                legalName = ToTitleCase(fullName);
                shortName = $"ИП {legalName}";
                directorName = legalName;
                directorTitle = "Индивидуальный предприниматель";
            }
            else
            {
                legalName = fullName;
                shortName = Text(row, "c") ?? fullName;
                (directorTitle, directorName) = SplitDirector(Text(row, "g"));
            }

            if (string.IsNullOrWhiteSpace(legalName))
            {
                return null;
            }

            var record = new CompanyRegistryRecord(
                isIndividual ? "ip" : "ooo",
                shortName,
                legalName,
                inn,
                isIndividual ? null : Text(row, "p"),
                Text(row, "o"),
                null,
                null,
                directorName,
                directorTitle);
            return (record, Text(row, "t"));
        }

        return null;
    }

    /// <summary>
    /// Находит адрес юридического лица в тексте первой страницы выписки.
    /// Значение начинается с шестизначного индекса после подписи «Адрес юридического
    /// лица» и продолжается до строки с ГРН. Разные извлекатели текста размещают
    /// индекс в строке подписи или отдельной строкой ниже, поэтому поддержаны оба варианта.
    /// </summary>
    /// <param name="pageText">Текст первой страницы PDF с сохранёнными переводами строк.</param>
    /// <returns>Адрес либо <see langword="null" />, если блок адреса не распознан.</returns>
    public static string? ParseAddress(string pageText)
    {
        const string label = "Адрес юридического лица";
        const int searchWindow = 600;
        var labelIndex = pageText.IndexOf(label, StringComparison.Ordinal);
        if (labelIndex < 0)
        {
            return null;
        }

        var tail = pageText[(labelIndex + label.Length)..].Replace("\r", string.Empty, StringComparison.Ordinal);
        var postal = PostalCode().Match(tail[..Math.Min(tail.Length, searchWindow)]);
        if (!postal.Success)
        {
            return null;
        }

        var lines = tail[postal.Index..].Split('\n');
        var parts = new List<string> { lines[0].Trim() };
        foreach (var raw in lines.Skip(1))
        {
            var line = raw.Trim();
            if (line.Length == 0 || AddressTerminator().IsMatch(line))
            {
                break;
            }

            parts.Add(line);
        }

        return WhiteSpace().Replace(string.Join(' ', parts), " ").Trim();
    }

    /// <summary>
    /// Находит e-mail в разделе «Адрес электронной почты» выписки ЕГРЮЛ или ЕГРИП.
    /// Реестр хранит его заглавными буквами, поэтому результат приводится к нижнему регистру.
    /// </summary>
    /// <param name="extractText">Текст первых страниц выписки.</param>
    /// <returns>E-mail либо <see langword="null" />, если раздел отсутствует.</returns>
    public static string? ParseEmail(string extractText)
    {
        const string sectionLabel = "Адрес электронной почты";
        const string fieldLabel = "E-mail";
        const int maxLabelDistance = 100;
        const int maxValueLines = 4;
        var sectionIndex = extractText.IndexOf(sectionLabel, StringComparison.Ordinal);
        var fieldIndex = sectionIndex < 0 ? -1 : extractText.IndexOf(fieldLabel, sectionIndex, StringComparison.Ordinal);
        if (fieldIndex < 0 || fieldIndex - sectionIndex > maxLabelDistance)
        {
            return null;
        }

        // Длинный адрес в ячейке таблицы переносится на несколько строк, в том числе
        // после дефиса («YANDEX-» / «TEAM.RU»). Пробелов в e-mail нет, поэтому строки
        // значения склеиваются без разделителя до строки ГРН.
        var value = new System.Text.StringBuilder();
        var lines = extractText[(fieldIndex + fieldLabel.Length)..]
            .Replace("\r", string.Empty, StringComparison.Ordinal)
            .Split('\n');
        var valueLines = 0;
        foreach (var raw in lines)
        {
            var line = raw.Trim();
            if (line.Length == 0)
            {
                if (value.Length > 0)
                {
                    break;
                }

                continue;
            }

            if (AddressTerminator().IsMatch(line) || ++valueLines > maxValueLines)
            {
                break;
            }

            value.Append(WhiteSpace().Replace(line, string.Empty));
        }

        var match = Email().Match(value.ToString());
        return match.Success ? match.Value.ToLowerInvariant() : null;
    }

    /// <summary>Разделяет «ГЕНЕРАЛЬНЫЙ ДИРЕКТОР: Иванов Иван Иванович» на должность и ФИО.</summary>
    private static (string? Title, string? Name) SplitDirector(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return (null, null);
        }

        var separator = value.IndexOf(':', StringComparison.Ordinal);
        if (separator < 0)
        {
            return (null, ToTitleCase(value.Trim()));
        }

        var title = value[..separator].Trim();
        var name = value[(separator + 1)..].Trim();
        return (
            title.Length == 0 ? null : char.ToUpper(title[0], CultureInfo.GetCultureInfo("ru-RU")) +
                                       title[1..].ToLower(CultureInfo.GetCultureInfo("ru-RU")),
            name.Length == 0 ? null : ToTitleCase(name));
    }

    /// <summary>ЕГРЮЛ хранит ФИО ИП заглавными буквами; в документах нужен обычный регистр.</summary>
    private static string ToTitleCase(string value)
    {
        var culture = CultureInfo.GetCultureInfo("ru-RU");
        return value.Any(char.IsLower) ? value : culture.TextInfo.ToTitleCase(value.ToLower(culture));
    }

    private static string? Text(JsonElement row, string property) =>
        row.TryGetProperty(property, out var value) && value.ValueKind == JsonValueKind.String &&
        !string.IsNullOrWhiteSpace(value.GetString())
            ? value.GetString()!.Trim()
            : null;

    [GeneratedRegex(@"(?<!\d)\d{6},")]
    private static partial Regex PostalCode();

    /// <summary>Следующая строка таблицы: «6 ГРН и дата…» или сам ГРН из 13 цифр.</summary>
    [GeneratedRegex(@"ГРН|^\d{13}(\s|$)")]
    private static partial Regex AddressTerminator();

    [GeneratedRegex(@"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}")]
    private static partial Regex Email();

    [GeneratedRegex(@"\s+")]
    private static partial Regex WhiteSpace();
}
