using System.Globalization;
using System.Text.Json;
using SkladKomforta.Application.Kanban;
using SkladKomforta.Application.Orders;
using SkladKomforta.Application.Quotes;

namespace SkladKomforta.Application.Company;

/// <summary>Only explicitly selected values reach the public renderer.</summary>
public sealed record DocumentCanvasContent(DocumentTemplate Template, IReadOnlyList<DocumentCanvasBlock> Blocks, string? Caption = null);
public sealed record DocumentCanvasBlock(string Id, string Title, IReadOnlyList<string> Lines,
    IReadOnlyList<DocumentCanvasTable> Tables);
public sealed record DocumentCanvasTable(string Title, IReadOnlyList<string> Columns,
    IReadOnlyList<double> Widths, IReadOnlyList<IReadOnlyList<string>> Rows, Guid? CategoryId = null,
    decimal? SectionTotal = null, decimal? CategoryTotal = null);

public static class DocumentCanvasBuilder
{
    private static bool IsParty(DocumentBlock block) => block.Kind is "client" or "executor";

    private static DocumentCanvasContent Filter(DocumentCanvasContent content, Func<DocumentBlock, bool> include)
    {
        var blocks = content.Template.Blocks.Where(include).ToArray();
        var ids = blocks.Select(block => block.Id).ToHashSet();
        return content with
        {
            Template = content.Template with { Blocks = blocks },
            Blocks = content.Blocks.Where(block => ids.Contains(block.Id)).ToArray()
        };
    }

    public static DocumentCanvasContent Parties(DocumentTemplate template,
        IReadOnlyDictionary<string, string?> client, IReadOnlyDictionary<string, string?> executor) =>
        Filter(Build(template, client, executor, [], []), IsParty);

    public static DocumentCanvasContent WithoutParties(DocumentCanvasContent content) =>
        Filter(content, block => !IsParty(block));

    private static readonly CultureInfo Russian = CultureInfo.GetCultureInfo("ru-RU");
    private static readonly JsonSerializerOptions JsonOptions = new() { PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower };
    public static string Money(decimal value) => value.ToString("N2", Russian) + " ₽";
    private static readonly Dictionary<string, string> Labels = new()
    {
        ["name"] = "Название", ["legal_name"] = "Юридическое название", ["inn"] = "ИНН", ["kpp"] = "КПП",
        ["ogrn"] = "ОГРН", ["address"] = "Адрес", ["phone"] = "Телефон", ["email"] = "Электронная почта",
        ["bank_name"] = "Банк", ["bank_bik"] = "БИК", ["bank_account"] = "Расчётный счёт", ["corr_account"] = "Корреспондентский счёт",
        ["company_type"] = "Тип компании", ["company_name"] = "Компания заказчика", ["contact_name"] = "Контактное лицо",
        ["object_type"] = "Тип объекта", ["object_address"] = "Адрес объекта", ["recipient_name"] = "Получатель",
        ["website"] = "Сайт", ["director_name"] = "Руководитель", ["signatory_name"] = "Подписант", ["signatory_title"] = "Должность подписанта"
    };

    public static DocumentCanvasContent Build(DocumentTemplate template,
        IReadOnlyDictionary<string, string?> client, IReadOnlyDictionary<string, string?> executor,
        IReadOnlyList<DocumentCanvasTable> tables, IReadOnlyList<string> totals, string? caption = null) => new(template,
        template.Blocks.Select(block => new DocumentCanvasBlock(block.Id, block.Kind switch
        { "client" => "Заказчик", "executor" => "Исполнитель", "totals" => "Итоги", _ => "" },
            block.Kind is "client" or "executor"
                ? block.Fields.Where(Labels.ContainsKey).Select(code => $"{Labels[code]}: {(block.Kind == "client" ? client : executor).GetValueOrDefault(code) ?? "—"}").ToArray()
                : block.Kind == "totals" ? totals : [],
            block.Kind == "table" ? tables.OrderBy(t => block.CategoryRank(t.CategoryId)).ToArray() : [])).ToArray(), caption);

    public static IReadOnlyDictionary<string, string?> Party(object? value)
    {
        if (value is null) return new Dictionary<string, string?>();
        var json = JsonSerializer.SerializeToElement(value, JsonOptions);
        return JsonParty(json);
    }

    public static IReadOnlyDictionary<string, string?> JsonParty(JsonElement json) => DocumentTemplate.PartyFields.ToDictionary(
        code => code, code => json.ValueKind == JsonValueKind.Object && json.TryGetProperty(code, out var item) && item.ValueKind == JsonValueKind.String
            ? item.GetString() : null);

    public static double[] Widths(DocumentTemplate template, Guid? categoryId, IEnumerable<string> codes)
    {
        var block = template.Blocks.FirstOrDefault(b => b.Kind == "table");
        return codes.Select(code => block?.ColumnWidths.GetValueOrDefault($"{categoryId}/{code}") ?? 1).Select(v => v > 0 ? v : 1).ToArray();
    }

    public static DocumentCanvasContent Quote(DocumentTemplate template, QuoteVariantDetails variant,
        CompanyClient? client, LegalEntity? executor, IReadOnlyDictionary<Guid, IReadOnlyList<KanbanFieldSummary>> fields)
    {
        var tables = new List<DocumentCanvasTable>();
        foreach (var category in variant.Categories.OrderBy(c => c.SortOrder))
        {
            // A visual template is fail-closed: never fall back to hidden legacy columns.
            var selected = category.CatalogCategoryId is { } id ? fields.GetValueOrDefault(id) : null;
            if (selected is null || selected.Count == 0) continue;
            var categoryTotal = category.Sections.SelectMany(s => s.Positions)
                .Where(p => !p.ExcludeFromTotals).Sum(p => p.LineTotal);
            foreach (var section in category.Sections.OrderBy(s => s.SortOrder))
                tables.Add(new($"{category.Name} / {section.Name}", selected.Select(f => f.Label).ToArray(),
                    Widths(template, category.CatalogCategoryId, selected.Select(f => f.Code)),
                    section.Positions.OrderBy(p => p.SortOrder).Select(p => (IReadOnlyList<string>)selected.Select(f => DocumentFieldValue.Quote(f, p)).ToArray()).ToArray(), category.CatalogCategoryId,
                    section.Positions.Where(p => !p.ExcludeFromTotals).Sum(p => p.LineTotal), categoryTotal));
        }
        var subtotal = variant.Categories.SelectMany(c => c.Sections).SelectMany(s => s.Positions).Where(p => !p.ExcludeFromTotals).Sum(p => p.LineTotal);
        var vat = QuoteVatCalculator.Calculate(subtotal, variant.VatRate);
        return Build(template, Party(client), Party(executor), tables, Totals(subtotal, vat), variant.Name);
    }

    public static string[] Totals(decimal subtotal, decimal vat) =>
        [$"НДС: {Money(vat)}", $"Сумма без НДС: {Money(subtotal)}", $"Итого для клиента: {Money(subtotal + vat)}"];

    public static DocumentCanvasContent Order(DocumentTemplate template, OrderDetails order,
        CompanyClient? client, LegalEntity? executor, IReadOnlyDictionary<Guid, IReadOnlyList<KanbanFieldSummary>> fields)
    {
        var tables = new List<DocumentCanvasTable>();
        foreach (var category in order.Categories.OrderBy(c => c.SortOrder))
        {
            var selected = category.CatalogCategoryId is { } id ? fields.GetValueOrDefault(id) : null;
            if (selected is null || selected.Count == 0) continue;
            foreach (var section in category.Sections.OrderBy(s => s.SortOrder))
                tables.Add(new($"{category.Name} / {section.Name}", selected.Select(f => f.Label).ToArray(),
                    Widths(template, category.CatalogCategoryId, selected.Select(f => f.Code)),
                    section.Positions.OrderBy(p => p.SortOrder).Select(p => (IReadOnlyList<string>)selected.Select(f => DocumentFieldValue.Order(f, p)).ToArray()).ToArray(), category.CatalogCategoryId));
        }
        return Build(template, Party(client), Party(executor), tables,
            [$"Позиций: {order.Categories.SelectMany(c => c.Sections).Sum(s => s.Positions.Count)}"], order.Title);
    }
}
