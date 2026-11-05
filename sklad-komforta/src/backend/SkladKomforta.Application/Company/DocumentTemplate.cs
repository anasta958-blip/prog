using SkladKomforta.Application.Identity;

namespace SkladKomforta.Application.Company;

public sealed record DocumentTemplate(bool Landscape, double Margin, double FontSize,
    double LineHeight, string FontFamily, IReadOnlyList<DocumentBlock> Blocks)
{
    public double Width => Landscape ? 1123 : 794;
    public double Height => Landscape ? 794 : 1123;

    public void Validate()
    {
        static bool Between(double n, double min, double max) => double.IsFinite(n) && n >= min && n <= max;
        if (!Between(Margin, 0, 100) || !Between(FontSize, 8, 36) || !Between(LineHeight, 1, 2)
            || FontFamily is not ("sans" or "serif") || Blocks is null || Blocks.Count > 4
            || Blocks.Any(b => b is null) || Blocks.Select(b => b.Id).Distinct().Count() != Blocks.Count
            || Blocks.Select(b => b.Kind).Distinct().Count() != Blocks.Count)
            throw Invalid();
        foreach (var b in Blocks)
        {
            if (string.IsNullOrWhiteSpace(b.Id) || b.Id.Length > 80 || b.Kind is not ("client" or "executor" or "table" or "totals")
                || !Between(b.Width, 100, Width - Margin * 2) || !Between(b.Height, 60, Height - Margin * 2)
                || !Between(b.X, Margin, Width - Margin - b.Width + .01)
                || !Between(b.Y, Margin, Height - Margin - b.Height + .01)
                || !Between(b.FontSize, 8, 36) || !Between(b.Padding, 0, 24) || b.Align is not ("left" or "center" or "right")
                || b.Fields is null || b.Fields.Count > PartyFields.Count
                || b.Fields.Distinct().Count() != b.Fields.Count || b.Fields.Any(f => !PartyFields.Contains(f))
                || b.ColumnWidths is null || b.ColumnWidths.Count > 1000
                || b.ColumnWidths.Any(p => p.Key.Length > 200 || !Between(p.Value, .2, 20))
                || b.CategoryOrder is { } order && (order.Count > 1000 || order.Distinct().Count() != order.Count)) throw Invalid();
        }
    }

    public static readonly IReadOnlySet<string> PartyFields = new HashSet<string>(StringComparer.Ordinal)
    { "name", "legal_name", "inn", "kpp", "ogrn", "address", "phone", "email", "bank_name", "bank_bik", "bank_account", "corr_account",
      "company_type", "company_name", "contact_name", "object_type", "object_address", "recipient_name",
      "website", "director_name", "signatory_name", "signatory_title" };
    private static IdentityException Invalid() => new(400, "document_template_invalid", "Некорректные параметры макета документа.");
}

public sealed record DocumentBlock(string Id, string Kind, double X, double Y, double Width,
    double Height, double FontSize, double Padding, string Align, IReadOnlyList<string> Fields,
    IReadOnlyDictionary<string, double> ColumnWidths, bool FlowFields = false,
    IReadOnlyList<Guid>? CategoryOrder = null)
{
    public int CategoryRank(Guid? id) => CategoryOrder is null ? 0 :
        CategoryOrder.Select((value, index) => (value, index)).Where(p => p.value == id)
            .Select(p => p.index).DefaultIfEmpty(CategoryOrder.Count).First();
}
