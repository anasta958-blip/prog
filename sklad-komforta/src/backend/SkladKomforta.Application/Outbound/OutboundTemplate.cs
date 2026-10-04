using System.Globalization;
using System.Text;

namespace SkladKomforta.Application.Outbound;

/// <summary>Данные документа для подстановки в шаблоны темы, подписи и текста.</summary>
/// <param name="DocumentKind">«КП», «ПКП» или «Комплектация».</param>
/// <param name="CardNumber">Номер карточки.</param>
/// <param name="Title">Название карточки (адрес объекта).</param>
/// <param name="ClientName">Заказчик; пустая строка, если не найден.</param>
/// <param name="Date">Дата отправки.</param>
public sealed record OutboundTemplateValues(
    string DocumentKind,
    long CardNumber,
    string Title,
    string? ClientName,
    DateOnly Date);

/// <summary>
/// Подстановки <c>{документ}</c>, <c>{номер}</c>, <c>{название}</c>,
/// <c>{заказчик}</c>, <c>{дата}</c> в шаблонах внешней отправки. Неизвестные
/// слова в фигурных скобках остаются как есть.
/// </summary>
public static class OutboundTemplate
{
    /// <summary>Шаблон темы письма и подписи в Telegram по умолчанию.</summary>
    public const string DefaultTemplate = "{документ} №{номер} — {название}";

    /// <summary>Поддерживаемые подстановки.</summary>
    public static readonly IReadOnlyList<string> Placeholders =
        ["{документ}", "{номер}", "{название}", "{заказчик}", "{дата}"];

    private static readonly CultureInfo Russian = CultureInfo.GetCultureInfo("ru-RU");

    /// <summary>Заменяет подстановки значениями документа.</summary>
    public static string Render(string? template, OutboundTemplateValues values)
    {
        if (string.IsNullOrEmpty(template)) return string.Empty;
        return new StringBuilder(template)
            .Replace("{документ}", values.DocumentKind)
            .Replace("{номер}", values.CardNumber.ToString(CultureInfo.InvariantCulture))
            .Replace("{название}", values.Title)
            .Replace("{заказчик}", values.ClientName ?? string.Empty)
            .Replace("{дата}", FormatDate(values.Date))
            .ToString()
            .Trim();
    }

    /// <summary>Дата в виде <c>03.10.2026</c>.</summary>
    public static string FormatDate(DateOnly date) => date.ToString("dd.MM.yyyy", Russian);

    /// <summary>
    /// Имя файла «название карточки — дата.pdf» без недопустимых для файловых
    /// систем символов; пустое название заменяется видом документа.
    /// </summary>
    public static string FileName(OutboundTemplateValues values)
    {
        var invalid = new HashSet<char>(Path.GetInvalidFileNameChars()) { '/', '\\', ':', '*', '?', '"', '<', '>', '|' };
        var title = new string(values.Title.Where(character => !invalid.Contains(character) && !char.IsControl(character))
            .ToArray()).Trim().TrimEnd('.');
        if (title.Length > 100) title = title[..100].Trim();
        if (title.Length == 0) title = values.DocumentKind;
        return $"{title} — {FormatDate(values.Date)}.pdf";
    }
}
