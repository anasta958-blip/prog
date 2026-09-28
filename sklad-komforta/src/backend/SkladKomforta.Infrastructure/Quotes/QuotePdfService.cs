using System.Globalization;
using MigraDoc.DocumentObjectModel;
using MigraDoc.DocumentObjectModel.Tables;
using MigraDoc.Rendering;
using PdfSharp.Fonts;
using SkladKomforta.Application.Company;
using SkladKomforta.Application.Kanban;
using SkladKomforta.Application.Quotes;

namespace SkladKomforta.Infrastructure.Quotes;

/// <summary>
/// Собирает официальный PDF из сохранённого дерева предложения. Сервис не
/// принимает данные из UI, поэтому печать всегда соответствует серверной версии.
/// </summary>
internal sealed class QuotePdfService(
    IQuoteService quoteService,
    ICompanyWorkspaceService companyService,
    IKanbanService kanbanService) : IQuotePdfService
{
    public async Task<QuotePdfFile> GenerateAsync(
        Guid actorUserId,
        Guid boardId,
        Guid cardId,
        Guid? proposalTypeId,
        Guid? variantId,
        CancellationToken cancellationToken)
    {
        var quote = QuotePrintSelection.Apply(
            await quoteService.GetAsync(actorUserId, boardId, cardId, cancellationToken),
            proposalTypeId,
            variantId);
        var clientsTask = companyService.GetClientsAsync(cancellationToken);
        var companiesTask = companyService.GetLegalEntitiesAsync(cancellationToken);
        var employeesTask = companyService.GetEmployeesAsync(cancellationToken);
        var cardTask = kanbanService.GetCardAsync(actorUserId, boardId, cardId, cancellationToken);
        await Task.WhenAll(clientsTask, companiesTask, employeesTask, cardTask);

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
            salesHead,
            cardTask.Result.Number);
        // Для печати одного варианта или одного типа в имя файла добавляются их названия.
        var printedType = variantId is null && proposalTypeId is null ? null : quote.ProposalTypes[0];
        var printedVariant = variantId is null ? null : printedType!.Variants[0];
        return new QuotePdfFile(BuildFileName(quote, printedType, printedVariant), content);
    }

    /// <summary>
    /// «КП - Название.pdf»; при печати части документа к имени добавляются тип и
    /// вариант, чтобы файлы не перезаписывали друг друга.
    /// </summary>
    private static string BuildFileName(
        QuoteDetails quote,
        QuoteProposalTypeDetails? printedType,
        QuoteVariantDetails? printedVariant)
    {
        var kind = quote.QuoteKind == QuoteKindCodes.Prequote ? "ПКП" : "КП";
        var invalid = Path.GetInvalidFileNameChars().ToHashSet();
        string Clean(string value, int limit)
        {
            var text = new string(value.Where(character => !invalid.Contains(character)).ToArray()).Trim();
            return text.Length > limit ? text[..limit].Trim() : text;
        }

        var parts = new List<string> { kind };
        var title = Clean(quote.Title, 80);
        if (title.Length > 0) parts.Add(title);
        if (printedType is not null)
        {
            parts.AddRange(new[] { Clean(printedType.Name, 40), Clean(printedVariant?.Name ?? string.Empty, 40) }
                .Where(part => part.Length > 0));
        }

        return string.Join(" - ", parts) + ".pdf";
    }
}

/// <summary>
/// Stateless-рендерер отделён от доступа к данным, чтобы формат PDF можно было
/// тестировать без PostgreSQL и HTTP. Макет повторяет экран предпросмотра Flutter
/// (<c>quote_preview_page.dart</c>): при изменении одного нужно обновлять и другой.
/// </summary>
internal static class QuotePdfDocumentRenderer
{
    private static readonly CultureInfo RussianCulture = CultureInfo.GetCultureInfo("ru-RU");
    private const string FontFamily = "QuoteSans";

    // Палитра и размеры предпросмотра: _paperText, _paperMuted, _paperBorder, _paperHeader.
    private static readonly Color PaperText = Color.FromRgb(23, 32, 51);
    private static readonly Color PaperMuted = Color.FromRgb(94, 107, 126);
    private static readonly Color PaperBorder = Color.FromRgb(216, 222, 232);
    private static readonly Color PaperHeader = Color.FromRgb(240, 244, 249);
    private static readonly Color TypeSubtitle = Color.FromRgb(206, 215, 229);
    private static readonly Color SelectedVariant = Color.FromRgb(232, 241, 255);
    private static readonly Color RegularVariant = Color.FromRgb(248, 250, 252);
    private static readonly Color SelectedLabel = Color.FromRgb(35, 104, 196);

    /// <summary>Ширина области печати A4 при полях 14 мм.</summary>
    private const double ContentWidthMm = 182;

    /// <summary>Внутренний отступ содержимого варианта, как padding 15 в предпросмотре.</summary>
    private const double VariantInsetMm = 4;

    /// <summary>Пропорции колонок таблицы предпросмотра (38, 205, 145, 70, 65, 100, 75, 105).</summary>
    private static readonly double[] PositionColumnWeights = [38, 205, 145, 70, 65, 100, 75, 105];

    private static readonly string[] PositionColumnLabels =
        ["№", "Наименование", "Маркировка / размер", "Кол-во", "Ед.", "Цена", "Скидка", "Сумма"];

    public static byte[] Render(
        QuoteDetails quote,
        CompanyClient? client,
        LegalEntity? executor,
        string? managerName,
        string? salesHeadName,
        long? cardNumber = null)
    {
        QuotePdfFontResolver.EnsureRegistered();
        var document = BuildDocument(quote, client, executor, managerName, salesHeadName, cardNumber);
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
        string? salesHeadName,
        long? cardNumber)
    {
        var document = new Document();
        var isPrequote = quote.QuoteKind == QuoteKindCodes.Prequote;
        document.Info.Title = quote.Title;
        document.Info.Subject = isPrequote
            ? "Предварительное коммерческое предложение"
            : "Коммерческое предложение";
        var normal = document.Styles[StyleNames.Normal]!;
        normal.Font.Name = FontFamily;
        normal.Font.Size = Unit.FromPoint(9);
        normal.Font.Color = PaperText;
        normal.ParagraphFormat.LineSpacingRule = LineSpacingRule.Multiple;
        normal.ParagraphFormat.LineSpacing = 1.15;

        var section = document.AddSection();
        section.PageSetup.PageFormat = PageFormat.A4;
        section.PageSetup.Orientation = Orientation.Portrait;
        section.PageSetup.TopMargin = Unit.FromMillimeter(14);
        section.PageSetup.BottomMargin = Unit.FromMillimeter(15);
        section.PageSetup.LeftMargin = Unit.FromMillimeter(14);
        section.PageSetup.RightMargin = Unit.FromMillimeter(14);
        AddFooter(section);

        var kind = AddText(section, isPrequote ? "ПРЕДВАРИТЕЛЬНОЕ КОММЕРЧЕСКОЕ ПРЕДЛОЖЕНИЕ" : "КОММЕРЧЕСКОЕ ПРЕДЛОЖЕНИЕ",
            size: 8, bold: true, color: PaperMuted);
        kind.Format.SpaceAfter = Unit.FromMillimeter(2);
        var title = AddText(section, string.IsNullOrWhiteSpace(quote.Title) ? "Без названия" : quote.Title.Trim(),
            size: 22, bold: true);
        title.Format.LineSpacing = 1;
        if (cardNumber is { } number)
        {
            AddText(section, $"№ {number}", size: 9, color: PaperMuted).Format.SpaceBefore = Unit.FromMillimeter(1);
        }

        AddMetadata(section, client?.Name, executor?.LegalName ?? executor?.Name, managerName, salesHeadName);

        if (Text(client?.Salutation) is { } salutation)
        {
            AddText(section, salutation).Format.SpaceBefore = Unit.FromMillimeter(6);
        }

        if (Text(client?.IntroText) is { } intro)
        {
            AddText(section, intro).Format.SpaceBefore = Unit.FromMillimeter(3);
        }

        section.AddParagraph().Format.SpaceAfter = Unit.FromMillimeter(4);
        foreach (var proposalType in quote.ProposalTypes.OrderBy(item => item.SortOrder))
        {
            AddProposalType(section, proposalType, quote.SelectionMode);
        }

        if (Text(quote.AdditionalInformation) is { } information)
        {
            var divider = section.AddParagraph();
            divider.Format.Borders.Top.Width = Unit.FromPoint(0.6);
            divider.Format.Borders.Top.Color = PaperBorder;
            divider.Format.SpaceBefore = Unit.FromMillimeter(4);
            divider.Format.SpaceAfter = Unit.FromMillimeter(4);
            AddText(section, "Дополнительная информация", size: 12, bold: true).Format.SpaceAfter = Unit.FromMillimeter(2);
            AddText(section, information);
        }

        if (Text(executor?.FooterDefault) is { } footer)
        {
            AddText(section, footer, color: PaperMuted).Format.SpaceBefore = Unit.FromMillimeter(8);
        }

        return document;
    }

    private static void AddFooter(Section section)
    {
        var footer = section.Footers.Primary.AddParagraph();
        footer.Format.Alignment = ParagraphAlignment.Right;
        footer.Format.Font.Size = Unit.FromPoint(7.5);
        footer.Format.Font.Color = PaperMuted;
        footer.AddText("Страница ");
        footer.AddPageField();
        footer.AddText(" из ");
        footer.AddNumPagesField();
    }

    /// <summary>Четыре колонки «ЗАКАЗЧИК / ИСПОЛНИТЕЛЬ / МЕНЕДЖЕР / РОП» без рамок.</summary>
    private static void AddMetadata(
        Section section,
        string? clientName,
        string? executorName,
        string? managerName,
        string? salesHeadName)
    {
        var entries = new[]
        {
            ("ЗАКАЗЧИК", clientName),
            ("ИСПОЛНИТЕЛЬ", executorName),
            ("МЕНЕДЖЕР", managerName),
            ("РОП", salesHeadName),
        };
        var table = CreateTable(section, Enumerable.Repeat(ContentWidthMm / entries.Length, entries.Length));
        table.LeftPadding = Unit.Zero;
        var labels = table.AddRow();
        labels.TopPadding = Unit.FromMillimeter(7);
        var values = table.AddRow();
        values.TopPadding = Unit.FromMillimeter(1);
        for (var index = 0; index < entries.Length; index++)
        {
            FillCell(labels.Cells[index], entries[index].Item1, size: 7, bold: true, color: PaperMuted);
            FillCell(values.Cells[index], Text(entries[index].Item2) ?? "Не указан", bold: true);
            labels.Cells[index].Format.LeftIndent = Unit.Zero;
            values.Cells[index].Format.LeftIndent = Unit.Zero;
        }
    }

    private static void AddProposalType(Section section, QuoteProposalTypeDetails proposalType, string selectionMode)
    {
        var bar = AddBar(section, PaperText, 3.2);
        bar.AddFormattedText(proposalType.Name, new Font { Size = Unit.FromPoint(13), Bold = true, Color = Colors.White });
        bar.AddTab();
        bar.AddFormattedText(
            selectionMode == "proposal_type" ? "Выбирается тип целиком" : "Выбирается один вариант",
            new Font { Size = Unit.FromPoint(7.5), Color = TypeSubtitle });

        var variants = proposalType.Variants.OrderBy(item => item.SortOrder).ToArray();
        foreach (var variant in variants)
        {
            AddVariant(section, variant, proposalType.SelectedVariantId == variant.Id);
        }

        // При печати одного варианта сводка типа совпала бы с итогом варианта.
        if (variants.Length > 1)
        {
            var clientTotal = variants.Sum(ClientTotal);
            var vat = variants.Sum(variant => QuoteVatCalculator.Calculate(ClientTotal(variant), variant.VatRate));
            AddSummary(section, "Сводка типа", clientTotal, $"НДС: {Money(vat)}", clientTotal + vat);
        }

        section.AddParagraph().Format.SpaceAfter = Unit.FromMillimeter(6);
    }

    private static void AddVariant(Section section, QuoteVariantDetails variant, bool selected)
    {
        var bar = AddBar(section, selected ? SelectedVariant : RegularVariant, 2.8);
        bar.AddFormattedText(variant.Name, new Font { Size = Unit.FromPoint(11.5), Bold = true });
        if (selected)
        {
            bar.AddTab();
            bar.AddFormattedText("ВЫБРАН", new Font { Size = Unit.FromPoint(7), Bold = true, Color = SelectedLabel });
        }

        if (Text(variant.Subtitle) is { } subtitle)
        {
            bar.AddLineBreak();
            bar.AddFormattedText(subtitle, new Font { Color = PaperMuted });
        }

        foreach (var category in variant.Categories.OrderBy(item => item.SortOrder))
        {
            foreach (var quoteSection in category.Sections.OrderBy(item => item.SortOrder))
            {
                AddPositionsTable(section, category.Name, quoteSection);
            }
        }

        var clientTotal = ClientTotal(variant);
        var vat = QuoteVatCalculator.Calculate(clientTotal, variant.VatRate);
        AddSummary(
            section,
            "Итого по варианту",
            clientTotal,
            variant.VatRate is { } rate ? $"НДС {Number(rate)}%: {Money(vat)}" : "Без НДС",
            clientTotal + vat);
    }

    private static void AddPositionsTable(Section section, string categoryName, QuoteSectionDetails quoteSection)
    {
        var heading = AddText(section, $"{categoryName} · {quoteSection.Name}", size: 9.5, bold: true);
        heading.Format.LeftIndent = Unit.FromMillimeter(VariantInsetMm);
        // Сумма раздела прижата к правому краю таблицы позиций; табуляция
        // отсчитывается от левого поля страницы, а таблица сдвинута на отступ.
        heading.Format.TabStops.AddTabStop(
            Unit.FromMillimeter(ContentWidthMm - VariantInsetMm),
            TabAlignment.Right);
        heading.AddTab();
        heading.AddText(Money(quoteSection.Positions.Where(item => !item.ExcludeFromTotals).Sum(item => item.LineTotal)));
        heading.Format.SpaceBefore = Unit.FromMillimeter(4);
        heading.Format.SpaceAfter = Unit.FromMillimeter(2);
        heading.Format.KeepWithNext = true;

        var width = ContentWidthMm - VariantInsetMm * 2;
        var totalWeight = PositionColumnWeights.Sum();
        var table = CreateTable(section, PositionColumnWeights.Select(weight => width * weight / totalWeight));
        table.Rows.LeftIndent = Unit.FromMillimeter(VariantInsetMm);
        table.Borders.Visible = true;
        table.Borders.Width = Unit.FromPoint(0.5);
        table.Borders.Color = PaperBorder;
        table.TopPadding = Unit.FromMillimeter(2);
        table.BottomPadding = Unit.FromMillimeter(2);

        var header = table.AddRow();
        header.HeadingFormat = true;
        header.Shading.Color = PaperHeader;
        for (var index = 0; index < PositionColumnLabels.Length; index++)
        {
            FillCell(header.Cells[index], PositionColumnLabels[index], size: 7.5, bold: true);
        }

        var columnWidths = table.Columns.Cast<Column>().Select(column => column.Width.Millimeter).ToArray();

        var number = 1;
        foreach (var position in quoteSection.Positions.OrderBy(item => item.SortOrder))
        {
            var row = table.AddRow();
            string[] values =
            [
                number++.ToString(RussianCulture),
                position.Name,
                position.Marking,
                Number(position.Quantity),
                position.Unit,
                Money(UnitPrice(position)),
                $"{Number(position.DiscountPercent ?? 0)}%",
                position.ExcludeFromTotals ? "Не учитывается" : Money(position.LineTotal),
            ];
            for (var index = 0; index < values.Length; index++)
            {
                FillCell(row.Cells[index], BreakLongWords(values[index], columnWidths[index] - 4, 7.5), size: 7.5);
            }
        }

        if (quoteSection.Positions.Count == 0)
        {
            var empty = table.AddRow();
            empty.Cells[0].MergeRight = PositionColumnLabels.Length - 1;
            FillCell(empty.Cells[0], "Позиции не добавлены", size: 7.5, color: PaperMuted);
        }
    }

    /// <summary>Серая строка итогов, выровненная вправо, как в предпросмотре.</summary>
    private static void AddSummary(Section section, string title, decimal clientTotal, string vatText, decimal total)
    {
        const string gap = "\u2003\u2003";
        var bar = AddBar(section, PaperHeader, 3.2);
        bar.Format.SpaceBefore = Unit.FromMillimeter(3);
        bar.Format.Alignment = ParagraphAlignment.Right;
        bar.Format.Borders.Bottom.Width = Unit.FromPoint(0.5);
        bar.Format.Borders.Bottom.Color = PaperBorder;
        bar.AddFormattedText(title, TextFormat.Bold);
        bar.AddText($"{gap}Сумма без НДС: {Money(clientTotal)}{gap}{vatText}{gap}Итого: {Money(total)}");
    }

    /// <summary>
    /// Залитая плашка на всю ширину: одна строка без швов между ячейками. Правая
    /// табуляция прижимает второй текст к правому краю, как Row/Expanded во Flutter.
    /// </summary>
    private static Paragraph AddBar(Section section, Color background, double verticalPaddingMm)
    {
        var paragraph = section.AddParagraph();
        paragraph.Format.Shading.Color = background;
        var padding = Unit.FromMillimeter(verticalPaddingMm);
        var side = Unit.FromMillimeter(VariantInsetMm);
        paragraph.Format.Borders.DistanceFromTop = padding;
        paragraph.Format.Borders.DistanceFromBottom = padding;
        paragraph.Format.Borders.DistanceFromLeft = side;
        paragraph.Format.Borders.DistanceFromRight = side;
        paragraph.Format.LeftIndent = side;
        paragraph.Format.RightIndent = side;
        paragraph.Format.KeepWithNext = true;
        paragraph.Format.TabStops.AddTabStop(
            Unit.FromMillimeter(ContentWidthMm - VariantInsetMm * 2),
            TabAlignment.Right);
        return paragraph;
    }

    /// <summary>
    /// MigraDoc не переносит слово, которое шире колонки, и оно залезает в соседнюю.
    /// Такие слова режутся по оценочной ширине символа, как делает Flutter.
    /// </summary>
    private static string BreakLongWords(string value, double widthMm, double fontSizePt)
    {
        const double averageCharWidthEm = 0.58;
        var maxChars = Math.Max(3, (int)(widthMm / (fontSizePt * averageCharWidthEm * 0.3528)));
        return string.Join(' ', value.Split(' ').Select(word =>
            word.Length <= maxChars
                ? word
                : string.Join('\n', word.Chunk(maxChars).Select(chunk => new string(chunk)))));
    }

    private static Table CreateTable(Section section, IEnumerable<double> columnWidthsMm)
    {
        var table = section.AddTable();
        table.Borders.Visible = false;
        table.LeftPadding = Unit.FromMillimeter(2);
        table.RightPadding = Unit.FromMillimeter(2);
        foreach (var width in columnWidthsMm)
        {
            table.AddColumn(Unit.FromMillimeter(width));
        }

        return table;
    }

    private static void FillCell(
        Cell cell,
        string value,
        double size = 9,
        bool bold = false,
        Color? color = null,
        ParagraphAlignment alignment = ParagraphAlignment.Left)
    {
        cell.VerticalAlignment = VerticalAlignment.Center;
        var paragraph = cell.AddParagraph();
        var lines = value.Split('\n');
        for (var index = 0; index < lines.Length; index++)
        {
            if (index > 0) paragraph.AddLineBreak();
            paragraph.AddText(lines[index]);
        }

        paragraph.Format.Alignment = alignment;
        paragraph.Format.Font.Size = Unit.FromPoint(size);
        paragraph.Format.Font.Bold = bold;
        paragraph.Format.Font.Color = color ?? PaperText;
    }

    private static Paragraph AddText(Section section, string text, double size = 9, bool bold = false, Color? color = null)
    {
        var paragraph = section.AddParagraph(text);
        paragraph.Format.Font.Size = Unit.FromPoint(size);
        paragraph.Format.Font.Bold = bold;
        paragraph.Format.Font.Color = color ?? PaperText;
        return paragraph;
    }

    /// <summary>
    /// Цена за единицу для клиента: базовая или ручная цена с наценкой и скидкой —
    /// тот же порядок, что в <see cref="QuoteCalculationEngine"/> и в предпросмотре.
    /// </summary>
    private static decimal UnitPrice(QuotePositionDetails position)
    {
        var price = position.ManualPrice ?? position.BasePrice;
        price *= 1m + (position.MarkupPercent ?? 0m) / 100m;
        price *= 1m - (position.DiscountPercent ?? 0m) / 100m;
        return decimal.Round(price, 2, MidpointRounding.AwayFromZero);
    }

    private static decimal ClientTotal(QuoteVariantDetails variant) => variant.Categories
        .SelectMany(category => category.Sections)
        .SelectMany(item => item.Positions)
        .Where(item => !item.ExcludeFromTotals)
        .Sum(item => item.LineTotal);

    private static string? Text(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();
    private static string Number(decimal value) => value.ToString("0.##", RussianCulture);
    private static string Money(decimal value) => $"{value.ToString("N2", RussianCulture)} ₽";
}

/// <summary>
/// Встраивает кириллицу одинаково на Windows и Linux. В production-образе
/// Noto Sans устанавливается Dockerfile-ом (пакет fonts-noto-core); на Windows
/// используется системный Arial. DejaVu Sans не подходит: у него кириллические
/// буквы «Ы», «Й», «Ё» собраны из составных глифов, и при встраивании подмножества
/// шрифта PDFsharp теряет их части — в PDF получается «ВЬ БРАН» вместо «ВЫБРАН».
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
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Fonts), bold ? "NotoSans-Bold.ttf" : "NotoSans-Regular.ttf")
            }
            : new[]
            {
                bold
                    ? "/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf"
                    : "/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf"
            };
        return candidates.FirstOrDefault(File.Exists);
    }
}
