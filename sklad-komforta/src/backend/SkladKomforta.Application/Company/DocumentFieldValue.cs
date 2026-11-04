using System.Globalization;
using System.Text.Json;
using SkladKomforta.Application.Kanban;
using SkladKomforta.Application.Quotes;
using SkladKomforta.Application.Orders;

namespace SkladKomforta.Application.Company;

public static class DocumentFieldValue
{
    private static readonly CultureInfo Russian = CultureInfo.GetCultureInfo("ru-RU");

    public static string Quote(KanbanFieldSummary field, QuotePositionDetails row) => Format(field, field.Code switch
    {
        "name" => JsonSerializer.SerializeToElement(row.Name),
        "marking" => JsonSerializer.SerializeToElement(row.Marking),
        "unit" => JsonSerializer.SerializeToElement(row.Unit),
        "quantity" => JsonSerializer.SerializeToElement(row.Quantity),
        "excluded_from_calc" => JsonSerializer.SerializeToElement(row.ExcludeFromTotals),
        "base_price" => JsonSerializer.SerializeToElement(row.ManualPrice ?? row.BasePrice),
        "purchase_price" => JsonSerializer.SerializeToElement(row.PurchasePrice),
        "markup_value" => JsonSerializer.SerializeToElement(row.MarkupPercent),
        "discount_value" => JsonSerializer.SerializeToElement(row.DiscountPercent),
        "line_total" => JsonSerializer.SerializeToElement(row.LineTotal),
        _ => row.Values.TryGetValue(field.Code, out var value) ? value : default,
    });

    public static string Order(KanbanFieldSummary field, OrderPositionDetails row) => Format(field, field.Code switch
    {
        "name" => JsonSerializer.SerializeToElement(row.IsReorder ? $"{row.Name} (дозаказ)" : row.Name),
        "marking" => JsonSerializer.SerializeToElement(row.Marking),
        "unit" => JsonSerializer.SerializeToElement(row.Unit),
        "quantity" => JsonSerializer.SerializeToElement(row.Quantity),
        _ => row.Values.TryGetValue(field.Code, out var value) ? value : default,
    });

    public static string Format(KanbanFieldSummary field, JsonElement value)
    {
        if (value.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined ||
            value.ValueKind == JsonValueKind.String && string.IsNullOrWhiteSpace(value.GetString()))
            return field.FieldType == "dictionary" ? "Не выбрано" : string.Empty;
        if (value.ValueKind == JsonValueKind.Array)
            return string.Join(", ", value.EnumerateArray().Select(item => Format(field, item)));
        if (value.ValueKind is JsonValueKind.True or JsonValueKind.False) return value.GetBoolean() ? "Да" : "Нет";
        if (value.ValueKind == JsonValueKind.Number && value.TryGetDecimal(out var number))
            return field.FieldType switch {
                "money" or "calculated_money" => number.ToString("N2", Russian) + " ₽",
                "percent" => number.ToString("0.##", Russian) + "%",
                _ => number.ToString("0.##", Russian),
            };
        if (value.ValueKind != JsonValueKind.String) return string.Empty;
        var text = value.GetString() ?? string.Empty;
        return field.Options.FirstOrDefault(option => option.Id.ToString() == text)?.Value ?? text;
    }
}
