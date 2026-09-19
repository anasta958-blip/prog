using System.Globalization;
using MigraDoc.DocumentObjectModel;
using MigraDoc.DocumentObjectModel.Tables;
using MigraDoc.Rendering;
using PdfSharp.Fonts;
using SkladKomforta.Application.Company;
using SkladKomforta.Application.Quotes;

namespace SkladKomforta.Infrastructure.Quotes;

/// <summary>
/// Собирает официальный PDF из сохранённого дерева предложения. Сервис не
/// принимает данные из UI, поэтому печать всегда соответствует серверной версии.
/// </summary>
internal sealed class QuotePdfService(
    IQuoteService quoteService,
    ICompanyWorkspaceService companyService) : IQuotePdfService
{
    public async Task<QuotePdfFile> GenerateAsync(
        Guid actorUserId,
        Guid boardId,
        Guid cardId,
        CancellationToken cancellationToken)
    {
        var quote = await quoteService.GetAsync(actorUserId, boardId, cardId, cancellationToken);
        var clientsTask = companyService.GetClientsAsync(cancellationToken);
        var companiesTask = companyService.GetLegalEntitiesAsync(cancellationToken);
        var employeesTask = companyService.GetEmployeesAsync(cancellationToken);
        await Task.WhenAll(clientsTask, companiesTask, employeesTask);

        var client = clientsTask.Result.FirstOrDefault(item => item.Id == quote.ClientId);
        var executor = companiesTask.Result.FirstOrDefault(item => item.Id == quote.ExecutorCompanyId);
        var employees = employeesTask.Result;
        var manager = employees.FirstOrDefault(item => item.UserId == quote.ManagerUserId)?.DisplayName;
        var salesHead = employees.FirstOrDefault(item => item.UserId == quote.SalesHeadUserId)?.DisplayName;

        var content = QuotePdfDocumentRenderer.Render(
            quote,
            client,
            executor,
            manager,
            salesHead);
        return new QuotePdfFile(BuildFileName(quote), content);
    }

    private static string BuildFileName(QuoteDetails quote)
    {
        var kind = quote.QuoteKind == QuoteKindCodes.Prequote ? "ПКП" : "КП";
        var invalid = Path.GetInvalidFileNameChars().ToHashSet();
        var title = new string(quote.Title.Where(character => !invalid.Contains(character)).ToArray()).Trim();
        if (title.Length > 80) title = title[..80].Trim();
        return string.IsNullOrWhiteSpace(title) ? $"{kind}.pdf" : $"{kind} - {title}.pdf";
    }
}

/// <summary>
/// Stateless-рендерер отделён от доступа к данным, чтобы формат PDF можно было
/// тестировать без PostgreSQL и HTTP.
/// </summary>
internal static class QuotePdfDocumentRenderer
{
    private static readonly CultureInfo RussianCulture = CultureInfo.GetCultureInfo("ru-RU");
    private const string FontFamily = "QuoteSans";

    public static byte[] Render(
        QuoteDetails quote,
        CompanyClient? client,
        LegalEntity? executor,
        string? managerName,
        string? salesHeadName)
    {
        QuotePdfFontResolver.EnsureRegistered();
        var document = BuildDocument(quote, client, executor, managerName, salesHeadName);
        var renderer = new PdfDocumentRenderer { Document = document };
        renderer.RenderDocument();
        using var output = new MemoryStream();
        renderer.PdfDocument.Save(output, closeStream: false);
        return output.ToArray();
    }

    private static Document BuildDocument(
        QuoteDetails quote,
        CompanyClient? client,
        LegalEntity? executor,
        string? managerName,
        string? salesHeadName)
    {
        var document = new Document();
        document.Info.Title = quote.Title;
        document.Info.Subject = quote.QuoteKind == QuoteKindCodes.Prequote
            ? "Предварительное коммерческое предложение"
            : "Коммерческое предложение";
        var normal = document.Styles[StyleNames.Normal]!;
        normal.Font.Name = FontFamily;
        normal.Font.Size = Unit.FromPoint(9);
        normal.Font.Color = Colors.Black;

        var section = document.AddSection();
        section.PageSetup.PageFormat = PageFormat.A4;
        section.PageSetup.Orientation = Orientation.Portrait;
        section.PageSetup.TopMargin = Unit.FromMillimeter(14);
        section.PageSetup.BottomMargin = Unit.FromMillimeter(15);
        section.PageSetup.LeftMargin = Unit.FromMillimeter(14);
        section.PageSetup.RightMargin = Unit.FromMillimeter(14);

        AddFooter(section);
        AddHeading(section, document.Info.Subject, 16, Unit.FromMillimeter(2));
        AddHeading(section, quote.Title, 13, Unit.FromMillimeter(5));
        AddPartyTable(section, client, executor, managerName, salesHeadName);

        if (!string.IsNullOrWhiteSpace(quote.AdditionalInformation))
        {
            AddHeading(section, "Дополнительная информация", 11, Unit.FromMillimeter(2));
            var information = section.AddParagraph(quote.AdditionalInformation.Trim());
            information.Format.SpaceAfter = Unit.FromMillimeter(5);
        }

        foreach (var proposalType in quote.ProposalTypes.OrderBy(item => item.SortOrder))
        {
            AddHeading(section, proposalType.Name, 13, Unit.FromMillimeter(3));
            foreach (var variant in proposalType.Variants.OrderBy(item => item.SortOrder))
            {
                AddVariant(section, variant, proposalType.SelectedVariantId == variant.Id);
            }
        }

        return document;
    }

    private static void AddFooter(Section section)
    {
        var footer = section.Footers.Primary.AddParagraph();
        footer.Format.Alignment = ParagraphAlignment.Right;
        footer.Format.Font.Size = Unit.FromPoint(8);
        footer.AddText("Страница ");
        footer.AddPageField();
        footer.AddText(" из ");
        footer.AddNumPagesField();
    }

    private static void AddPartyTable(
        Section section,
        CompanyClient? client,
        LegalEntity? executor,
        string? managerName,
        string? salesHeadName)
    {
        var table = section.AddTable();
        table.Borders.Width = Unit.FromPoint(0.5);
        table.Borders.Color = Color.FromRgb(190, 197, 207);
        table.AddColumn(Unit.FromCentimeter(3.4));
        table.AddColumn(Unit.FromCentimeter(5.2));
        table.AddColumn(Unit.FromCentimeter(3.4));
        table.AddColumn(Unit.FromCentimeter(5.2));

        AddLabelValueRow(table, "Заказчик", client?.Name, "Исполнитель", executor?.Name);
        AddLabelValueRow(table, "Контакт", client?.ContactName, "ИНН", executor?.Inn);
        AddLabelValueRow(table, "Менеджер", managerName, "РОП", salesHeadName);
        table.Rows.LeftIndent = Unit.Zero;
        table.Format.SpaceAfter = Unit.FromMillimeter(5);
    }

    private static void AddLabelValueRow(
        Table table,
        string firstLabel,
        string? firstValue,
        string secondLabel,
        string? secondValue)
    {
        var row = table.AddRow();
        SetCell(row.Cells[0], firstLabel, bold: true, shaded: true);
        SetCell(row.Cells[1], Display(firstValue));
        SetCell(row.Cells[2], secondLabel, bold: true, shaded: true);
        SetCell(row.Cells[3], Display(secondValue));
    }

    private static void AddVariant(Section section, QuoteVariantDetails variant, bool selected)
    {
        var title = selected ? $"{variant.Name} · выбран" : variant.Name;
        AddHeading(section, title, 11, Unit.FromMillimeter(2));
        if (!string.IsNullOrWhiteSpace(variant.Subtitle))
        {
            var subtitle = section.AddParagraph(variant.Subtitle.Trim());
            subtitle.Format.Font.Italic = true;
            subtitle.Format.SpaceAfter = Unit.FromMillimeter(2);
        }

        foreach (var category in variant.Categories.OrderBy(item => item.SortOrder))
        {
            AddHeading(section, category.Name, 10, Unit.FromMillimeter(1));
            foreach (var quoteSection in category.Sections.OrderBy(item => item.SortOrder))
            {
                AddHeading(section, quoteSection.Name, 9, Unit.FromMillimeter(1));
                AddPositionsTable(section, quoteSection.Positions.OrderBy(item => item.SortOrder));
            }
        }

        var included = variant.Categories
            .SelectMany(category => category.Sections)
            .SelectMany(item => item.Positions)
            .Where(item => !item.ExcludeFromTotals)
            .ToArray();
        var clientTotal = included.Sum(item => item.LineTotal);
        var summary = section.AddTable();
        summary.AddColumn(Unit.FromCentimeter(9.5));
        summary.AddColumn(Unit.FromCentimeter(7.7));
        summary.Borders.Top.Width = Unit.FromPoint(0.8);
        AddSummaryRow(summary, "Итого для клиента", Money(clientTotal));
        if (variant.VatRate is { } rate)
        {
            var vat = clientTotal == 0 ? 0 : clientTotal * rate / (100 + rate);
            AddSummaryRow(summary, $"В том числе НДС {Number(rate)}%", Money(vat));
        }
        else
        {
            AddSummaryRow(summary, "НДС", "Без НДС");
        }
        summary.Format.SpaceAfter = Unit.FromMillimeter(5);
    }

    private static void AddPositionsTable(
        Section section,
        IEnumerable<QuotePositionDetails> positions)
    {
        var items = positions.ToArray();
        if (items.Length == 0) return;

        var table = section.AddTable();
        table.Borders.Width = Unit.FromPoint(0.4);
        table.Borders.Color = Color.FromRgb(190, 197, 207);
        foreach (var width in new[] { 0.8, 4.0, 2.4, 1.3, 1.2, 2.2, 1.6, 2.4, 1.3 })
        {
            table.AddColumn(Unit.FromCentimeter(width));
        }

        var header = table.AddRow();
        header.HeadingFormat = true;
        header.Format.Font.Bold = true;
        header.Shading.Color = Color.FromRgb(236, 239, 243);
        var labels = new[] { "№", "Наименование", "Маркировка", "Кол-во", "Ед.", "Цена", "Скидка", "Сумма", "Учёт" };
        for (var index = 0; index < labels.Length; index++) SetCell(header.Cells[index], labels[index], bold: true);

        var number = 1;
        foreach (var position in items)
        {
            var row = table.AddRow();
            SetCell(row.Cells[0], number++.ToString(RussianCulture));
            SetCell(row.Cells[1], position.Name);
            SetCell(row.Cells[2], Display(position.Marking));
            SetCell(row.Cells[3], Number(position.Quantity));
            SetCell(row.Cells[4], Display(position.Unit));
            SetCell(row.Cells[5], Money(position.ManualPrice ?? position.BasePrice));
            SetCell(row.Cells[6], position.DiscountPercent is { } discount ? $"{Number(discount)}%" : "—");
            SetCell(row.Cells[7], Money(position.LineTotal));
            SetCell(row.Cells[8], position.ExcludeFromTotals ? "Нет" : "Да");
        }
        table.Format.SpaceAfter = Unit.FromMillimeter(3);
    }

    private static void AddSummaryRow(Table table, string label, string value)
    {
        var row = table.AddRow();
        SetCell(row.Cells[0], label, bold: true);
        SetCell(row.Cells[1], value, bold: true, alignment: ParagraphAlignment.Right);
    }

    private static void SetCell(
        Cell cell,
        string value,
        bool bold = false,
        bool shaded = false,
        ParagraphAlignment alignment = ParagraphAlignment.Left)
    {
        cell.VerticalAlignment = VerticalAlignment.Center;
        cell.Format.LeftIndent = Unit.FromMillimeter(1);
        cell.Format.RightIndent = Unit.FromMillimeter(1);
        cell.Format.Alignment = alignment;
        cell.Format.Font.Bold = bold;
        if (shaded) cell.Shading.Color = Color.FromRgb(244, 246, 248);
        cell.AddParagraph(value);
    }

    private static void AddHeading(Section section, string text, double size, Unit spaceAfter)
    {
        var heading = section.AddParagraph(text);
        heading.Format.Font.Bold = true;
        heading.Format.Font.Size = Unit.FromPoint(size);
        heading.Format.SpaceAfter = spaceAfter;
        heading.Format.KeepWithNext = true;
    }

    private static string Display(string? value) => string.IsNullOrWhiteSpace(value) ? "—" : value.Trim();
    private static string Number(decimal value) => value.ToString("0.##", RussianCulture);
    private static string Money(decimal value) => $"{value.ToString("N2", RussianCulture)} ₽";
}

/// <summary>
/// Встраивает кириллицу одинаково на Windows и Linux. В production-образе
/// DejaVu Sans устанавливается Dockerfile-ом; на Windows используется системный Arial.
/// </summary>
internal sealed class QuotePdfFontResolver : IFontResolver
{
    private const string RegularFace = "QuoteSans-Regular";
    private const string BoldFace = "QuoteSans-Bold";
    private static readonly object Sync = new();
    private static bool _registered;

    public static void EnsureRegistered()
    {
        if (_registered) return;
        lock (Sync)
        {
            if (_registered) return;
            GlobalFontSettings.FontResolver = new QuotePdfFontResolver();
            _registered = true;
        }
    }

    public FontResolverInfo ResolveTypeface(string familyName, bool isBold, bool isItalic) =>
        new(isBold ? BoldFace : RegularFace);

    public byte[]? GetFont(string faceName)
    {
        var bold = faceName == BoldFace;
        var path = ResolveFontPath(bold);
        return path == null ? null : File.ReadAllBytes(path);
    }

    private static string? ResolveFontPath(bool bold)
    {
        var candidates = OperatingSystem.IsWindows()
            ? new[]
            {
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Fonts), bold ? "arialbd.ttf" : "arial.ttf"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Fonts), bold ? "DejaVuSans-Bold.ttf" : "DejaVuSans.ttf")
            }
            : new[]
            {
                bold
                    ? "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
                    : "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
            };
        return candidates.FirstOrDefault(File.Exists);
    }
}
