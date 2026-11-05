using System.Globalization;
using System.Text.Json;
using MigraDoc.DocumentObjectModel;
using MigraDoc.DocumentObjectModel.Tables;
using MigraDoc.Rendering;
using SkladKomforta.Application.Company;
using SkladKomforta.Application.Kanban;
using SkladKomforta.Application.Orders;
using SkladKomforta.Infrastructure.Quotes;
using SkladKomforta.Infrastructure.Company;

namespace SkladKomforta.Infrastructure.Orders;

/// <summary>
/// PDF сохранённой комплектации. Данные берутся только с сервера, поэтому
/// печать соответствует последней сохранённой версии.
/// </summary>
internal sealed class OrderPdfService(
    IOrderService orderService,
    ICompanyWorkspaceService companyService,
    IKanbanService kanbanService,
    IDocumentLayoutService layouts) : IOrderPdfService
{
    /// <inheritdoc />
    public async Task<OrderPdfFile> GenerateAsync(
        Guid actorUserId, Guid boardId, Guid cardId, CancellationToken cancellationToken)
    {
        var order = await orderService.GetAsync(actorUserId, boardId, cardId, cancellationToken);
        var clientsTask = companyService.GetClientsAsync(cancellationToken);
        var companiesTask = companyService.GetLegalEntitiesAsync(cancellationToken);
        var employeesTask = companyService.GetEmployeesAsync(cancellationToken);
        var cardTask = kanbanService.GetCardAsync(actorUserId, boardId, cardId, cancellationToken);
        var boardTask = kanbanService.GetBoardAsync(boardId, cancellationToken);
        await Task.WhenAll(clientsTask, companiesTask, employeesTask, cardTask, boardTask);

        var employees = employeesTask.Result;
        var executor = companiesTask.Result.FirstOrDefault(item => item.Id == order.ExecutorCompanyId);
        var template = await layouts.GetTemplateAsync(boardId, cancellationToken);
        var fields = await layouts.GetFieldsAsync(boardId, cancellationToken);
        var content = template is not null ? DocumentCanvasPdfRenderer.Render(order.Title,
            [DocumentCanvasBuilder.Order(template, order, clientsTask.Result.FirstOrDefault(c => c.Id == order.ClientId), executor, fields)]) : OrderPdfDocumentRenderer.Render(
            order,
            boardTask.Result,
            clientsTask.Result.FirstOrDefault(item => item.Id == order.ClientId)?.Name,
            executor?.LegalName ?? executor?.Name,
            employees.FirstOrDefault(item => item.UserId == order.ManagerUserId)?.DisplayName,
            employees.FirstOrDefault(item => item.UserId == order.SalesHeadUserId)?.DisplayName,
            cardTask.Result.Number,
            fields);

        var invalid = Path.GetInvalidFileNameChars().ToHashSet();
        var title = new string(order.Title.Where(character => !invalid.Contains(character)).ToArray()).Trim();
        if (title.Length > 80) title = title[..80].Trim();
        return new OrderPdfFile(title.Length == 0 ? "Комплектация.pdf" : $"Комплектация - {title}.pdf", content);
    }
}

/// <summary>
/// Рендерер комплектации без доступа к данным (тестируется без PostgreSQL).
/// Колонки: №, наименование, маркировка, количество, единица и поля канбана
/// комплектации, назначенные категории. Дозаказ помечается в строке.
/// </summary>
internal static class OrderPdfDocumentRenderer
{
    private static readonly CultureInfo RussianCulture = CultureInfo.GetCultureInfo("ru-RU");
    private static readonly Color PaperText = Color.FromRgb(23, 32, 51);
    private static readonly Color PaperMuted = Color.FromRgb(94, 107, 126);
    private static readonly Color PaperBorder = Color.FromRgb(216, 222, 232);
    private static readonly Color PaperHeader = Color.FromRgb(240, 244, 249);
    private static readonly Color ReorderShade = Color.FromRgb(255, 244, 222);
    private static readonly HashSet<string> SystemFields =
        new(StringComparer.Ordinal) { "name", "marking", "quantity", "unit" };

    private static readonly string[] FixedLabels = ["№", "Наименование", "Маркировка / размер", "Кол-во", "Ед."];
    private const double PortraitWidthMm = 182;
    private const double LandscapeWidthMm = 269;

    public static byte[] Render(
        OrderDetails order,
        KanbanBoard board,
        string? clientName,
        string? executorName,
        string? managerName,
        string? salesHeadName,
        long? cardNumber,
        IReadOnlyDictionary<Guid, IReadOnlyList<KanbanFieldSummary>>? layouts = null)
    {
        QuotePdfFontResolver.EnsureRegistered();
        var document = BuildDocument(order, board, clientName, executorName, managerName, salesHeadName, cardNumber, layouts);
        var renderer = new PdfDocumentRenderer { Document = document };
        renderer.RenderDocument();
        using var output = new MemoryStream();
        renderer.PdfDocument.Save(output, closeStream: false);
        return output.ToArray();
    }

    private static Document BuildDocument(
        OrderDetails order,
        KanbanBoard board,
        string? clientName,
        string? executorName,
        string? managerName,
        string? salesHeadName,
        long? cardNumber,
        IReadOnlyDictionary<Guid, IReadOnlyList<KanbanFieldSummary>>? layouts)
    {
        var fieldsByCategory = board.Categories.ToDictionary(
            category => category.CategoryId,
            category => category.Fields
                .Where(field => !SystemFields.Contains(field.Code))
                .OrderBy(field => field.SortOrder)
                .ToArray());
        var maxExtra = order.Categories
            .Select(category => category.CatalogCategoryId is { } id && fieldsByCategory.TryGetValue(id, out var fields)
                ? fields.Length
                : 0)
            .DefaultIfEmpty(0)
            .Max();
        var landscape = maxExtra > 2;
        var contentWidth = landscape ? LandscapeWidthMm : PortraitWidthMm;

        var document = new Document();
        document.Info.Title = order.Title;
        document.Info.Subject = "Комплектация";
        var normal = document.Styles[StyleNames.Normal]!;
        normal.Font.Name = "QuoteSans";
        normal.Font.Size = Unit.FromPoint(9);
        normal.Font.Color = PaperText;

        var section = document.AddSection();
        section.PageSetup.PageFormat = PageFormat.A4;
        section.PageSetup.Orientation = landscape ? Orientation.Landscape : Orientation.Portrait;
        section.PageSetup.TopMargin = Unit.FromMillimeter(14);
        section.PageSetup.BottomMargin = Unit.FromMillimeter(15);
        section.PageSetup.LeftMargin = Unit.FromMillimeter(14);
        section.PageSetup.RightMargin = Unit.FromMillimeter(14);
        var footer = section.Footers.Primary.AddParagraph();
        footer.Format.Alignment = ParagraphAlignment.Right;
        footer.Format.Font.Size = Unit.FromPoint(7.5);
        footer.Format.Font.Color = PaperMuted;
        footer.AddText("Страница ");
        footer.AddPageField();
        footer.AddText(" из ");
        footer.AddNumPagesField();

        AddText(section, "КОМПЛЕКТАЦИЯ", size: 8, bold: true, color: PaperMuted).Format.SpaceAfter = Unit.FromMillimeter(2);
        AddText(section, order.Title.Trim(), size: 20, bold: true);
        var subtitle = new List<string>();
        if (cardNumber is { } number) subtitle.Add($"№ {number}");
        if (Text(order.ObjectType) is { } objectType) subtitle.Add(objectType);
        if (order.SourceQuote is { } source) subtitle.Add($"из КП № {source.CardNumber}");
        if (subtitle.Count > 0)
            AddText(section, string.Join(" · ", subtitle), color: PaperMuted).Format.SpaceBefore = Unit.FromMillimeter(1);

        var entries = new[]
        {
            ("ЗАКАЗЧИК", clientName), ("ИСПОЛНИТЕЛЬ", executorName),
            ("МЕНЕДЖЕР", managerName), ("РОП", salesHeadName),
        };
        var meta = CreateTable(section, Enumerable.Repeat(contentWidth / entries.Length, entries.Length));
        meta.LeftPadding = Unit.Zero;
        var labels = meta.AddRow();
        labels.TopPadding = Unit.FromMillimeter(6);
        var values = meta.AddRow();
        for (var index = 0; index < entries.Length; index++)
        {
            FillCell(labels.Cells[index], entries[index].Item1, size: 7, bold: true, color: PaperMuted);
            FillCell(values.Cells[index], Text(entries[index].Item2) ?? "Не указан", bold: true);
        }

        foreach (var category in order.Categories.OrderBy(item => item.SortOrder))
        {
            var extra = category.CatalogCategoryId is { } id && fieldsByCategory.TryGetValue(id, out var fields)
                ? fields
                : [];
            foreach (var orderSection in category.Sections.OrderBy(item => item.SortOrder))
                AddSectionTable(section, category.Name, orderSection, extra, contentWidth,
                    category.CatalogCategoryId is { } categoryId && layouts is not null && layouts.TryGetValue(categoryId, out var selected) ? selected : null);
        }

        if (order.Categories.Count == 0)
            AddText(section, "Позиции не добавлены.", color: PaperMuted).Format.SpaceBefore = Unit.FromMillimeter(6);
        return document;
    }

    private static void AddSectionTable(
        Section section,
        string categoryName,
        OrderSectionDetails orderSection,
        KanbanFieldSummary[] extra,
        double contentWidth,
        IReadOnlyList<KanbanFieldSummary>? selected)
    {
        var title = string.Equals(orderSection.Name.Trim(), categoryName.Trim(), StringComparison.OrdinalIgnoreCase)
            ? categoryName
            : $"{categoryName} · {orderSection.Name}";
        var heading = AddText(section, title, size: 9.5, bold: true);
        heading.Format.SpaceBefore = Unit.FromMillimeter(5);
        heading.Format.SpaceAfter = Unit.FromMillimeter(2);
        heading.Format.KeepWithNext = true;

        if (selected is not null)
        {
            if (selected.Count == 0) return;
            var selectedTable = CreateTable(section, Enumerable.Repeat(contentWidth / selected.Count, selected.Count));
            selectedTable.Borders.Visible = true;
            selectedTable.Borders.Color = PaperBorder;
            var selectedHeader = selectedTable.AddRow();
            selectedHeader.HeadingFormat = true;
            selectedHeader.Shading.Color = PaperHeader;
            for (var i = 0; i < selected.Count; i++) FillCell(selectedHeader.Cells[i], selected[i].Label, size: 7.5, bold: true);
            foreach (var position in orderSection.Positions.OrderBy(item => item.SortOrder))
            {
                var row = selectedTable.AddRow();
                if (position.IsReorder) row.Shading.Color = ReorderShade;
                for (var i = 0; i < selected.Count; i++) FillCell(row.Cells[i], DocumentFieldValue.Order(selected[i], position), size: 7.5);
            }
            return;
        }

        double[] fixedWeights = [8, 52, 34, 16, 12];
        var extraWeight = extra.Length == 0 ? 0 : Math.Max(18, 60.0 / extra.Length);
        var weights = fixedWeights.Concat(Enumerable.Repeat(extraWeight, extra.Length)).ToArray();
        var totalWeight = weights.Sum();
        var table = CreateTable(section, weights.Select(weight => contentWidth * weight / totalWeight));
        table.Borders.Visible = true;
        table.Borders.Width = Unit.FromPoint(0.5);
        table.Borders.Color = PaperBorder;
        table.TopPadding = Unit.FromMillimeter(1.6);
        table.BottomPadding = Unit.FromMillimeter(1.6);

        var labels = FixedLabels
            .Concat(extra.Select(field => field.Label)).ToArray();
        var header = table.AddRow();
        header.HeadingFormat = true;
        header.Shading.Color = PaperHeader;
        for (var index = 0; index < labels.Length; index++)
            FillCell(header.Cells[index], labels[index], size: 7.5, bold: true);

        var number = 1;
        foreach (var position in orderSection.Positions.OrderBy(item => item.SortOrder))
        {
            var row = table.AddRow();
            if (position.IsReorder) row.Shading.Color = ReorderShade;
            var cells = new List<string>
            {
                number++.ToString(RussianCulture),
                position.IsReorder ? $"{position.Name} (дозаказ)" : position.Name,
                position.Marking,
                position.Quantity.ToString("0.##", RussianCulture),
                position.Unit,
            };
            cells.AddRange(extra.Select(field =>
                position.Values.TryGetValue(field.Code, out var value) ? Format(value) : string.Empty));
            for (var index = 0; index < cells.Count; index++)
                FillCell(row.Cells[index], cells[index], size: 7.5);
        }

        if (orderSection.Positions.Count == 0)
        {
            var empty = table.AddRow();
            empty.Cells[0].MergeRight = labels.Length - 1;
            FillCell(empty.Cells[0], "Позиции не добавлены", size: 7.5, color: PaperMuted);
        }
    }

    /// <summary>Значение поля позиции в печатном виде.</summary>
    internal static string Format(JsonElement value) => value.ValueKind switch
    {
        JsonValueKind.String => value.GetString() ?? string.Empty,
        JsonValueKind.Number => value.TryGetDecimal(out var number)
            ? number.ToString("0.##", RussianCulture)
            : value.GetRawText(),
        JsonValueKind.True => "Да",
        JsonValueKind.False => "Нет",
        JsonValueKind.Array => string.Join(", ", value.EnumerateArray().Select(Format).Where(item => item.Length > 0)),
        _ => string.Empty,
    };

    private static Table CreateTable(Section section, IEnumerable<double> columnWidthsMm)
    {
        var table = section.AddTable();
        table.Borders.Visible = false;
        table.LeftPadding = Unit.FromMillimeter(1.5);
        table.RightPadding = Unit.FromMillimeter(1.5);
        foreach (var width in columnWidthsMm) table.AddColumn(Unit.FromMillimeter(width));
        return table;
    }

    private static void FillCell(Cell cell, string value, double size = 9, bool bold = false, Color? color = null)
    {
        cell.VerticalAlignment = VerticalAlignment.Center;
        var paragraph = cell.AddParagraph(value);
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

    private static string? Text(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
