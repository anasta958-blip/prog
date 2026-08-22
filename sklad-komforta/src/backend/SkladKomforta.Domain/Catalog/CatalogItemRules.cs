using System.Globalization;
using System.Text;

namespace SkladKomforta.Domain.Catalog;

/// <summary>Чистые правила идентичности и денежных значений карточки каталога.</summary>
public static class CatalogItemRules
{
    /// <summary>
    /// Нормализует текст для сравнения уникальности без изменения отображаемого
    /// значения: убирает крайние и повторяющиеся пробелы и приводит к нижнему регистру.
    /// </summary>
    public static string NormalizeIdentityPart(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return string.Empty;
        var result = new StringBuilder(value.Length);
        var previousWasWhitespace = false;
        foreach (var symbol in value.Trim())
        {
            if (char.IsWhiteSpace(symbol))
            {
                if (!previousWasWhitespace) result.Append(' ');
                previousWasWhitespace = true;
                continue;
            }

            result.Append(char.ToLower(symbol, CultureInfo.InvariantCulture));
            previousWasWhitespace = false;
        }
        return result.ToString();
    }

    /// <summary>Проверяет цену каталога: указанное значение обязано быть больше нуля.</summary>
    public static bool IsValidPrice(decimal value) => value > 0m;
}
