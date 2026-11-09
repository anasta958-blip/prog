using PdfSharp.Drawing;
using PdfSharp.Pdf;
using SkladKomforta.Application.Company;
using SkladKomforta.Infrastructure.Quotes;

namespace SkladKomforta.Infrastructure.Company;

internal sealed record DocumentCanvasPdfPart(DocumentCanvasContent Content,
    string? TypeName = null, string? VariantName = null, bool Selected = false);

internal static class DocumentCanvasPdfRenderer
{
    public static byte[] Render(string title, IReadOnlyList<DocumentCanvasContent> documents) =>
        RenderParts(title, documents.Select(content => new DocumentCanvasPdfPart(content)).ToArray());

    public static byte[] RenderParts(string title, IReadOnlyList<DocumentCanvasPdfPart> parts)
    {
        QuotePdfFontResolver.EnsureRegistered();
        using var pdf = new PdfDocument();
        pdf.Info.Title = title;
        var pages = new List<XGraphics>();
        try
        {
            var cursor = 0.0;
            string? lastType = null;
            foreach (var part in parts)
                cursor = AddDocument(pdf, pages, part, cursor, ref lastType);
        }
        finally { foreach (var graphics in pages) graphics.Dispose(); }
        if (pdf.PageCount == 0) pdf.AddPage();
        using var output = new MemoryStream();
        pdf.Save(output, false);
        return output.ToArray();
    }

    private static double AddDocument(PdfDocument pdf, List<XGraphics> pages,
        DocumentCanvasPdfPart part, double startOffset, ref string? lastType)
    {
        var content = part.Content;
        var template = content.Template;
        var pageHeight = template.Height - template.Margin * 2;
        XGraphics Graphics(int page)
        {
            while (pages.Count <= page)
            {
                var sheet = pdf.AddPage();
                sheet.Width = XUnit.FromPoint(template.Width * .75);
                sheet.Height = XUnit.FromPoint(template.Height * .75);
                var graphics = XGraphics.FromPdfPage(sheet);
                graphics.ScaleTransform(.75);
                if (template.Margin >= 16)
                {
                    var footerFont = new XFont("QuoteSans", 8);
                    var caption = pdf.Info.Title;
                    while (caption.Length > 0 && graphics.MeasureString(caption, footerFont).Width > template.Width - template.Margin * 2 - 50)
                        caption = caption[..^1];
                    graphics.DrawString($"{caption} · {pdf.PageCount}", footerFont, XBrushes.Gray,
                        new XPoint(template.Margin, template.Height - 13), XStringFormats.TopLeft);
                }
                pages.Add(graphics);
            }
            return pages[page];
        }

        var cursorBase = startOffset;
        void Heading(string label, XColor background, XColor foreground,
            double fontSize, double gap, double followingSpace)
        {
            var font = new XFont("QuoteSans", fontSize, XFontStyleEx.Bold);
            var width = template.Width - template.Margin * 2;
            var lines = Wrap(Graphics((int)(cursorBase / pageHeight)), label, font, width - 24);
            var height = lines.Count * (fontSize * 1.3) + 14;
            cursorBase += gap;
            if (cursorBase % pageHeight + height + followingSpace > pageHeight)
                cursorBase = (Math.Floor(cursorBase / pageHeight) + 1) * pageHeight;
            var page = (int)(cursorBase / pageHeight);
            var graphics = Graphics(page);
            var y = template.Margin + cursorBase % pageHeight;
            graphics.DrawRectangle(new XSolidBrush(background), template.Margin, y, width, height);
            graphics.DrawRectangle(new XSolidBrush(XColor.FromArgb(54, 105, 171)),
                template.Margin, y, 4, height);
            for (var i = 0; i < lines.Count; i++)
                graphics.DrawString(lines[i], font, new XSolidBrush(foreground),
                    new XPoint(template.Margin + 12, y + 7 + i * fontSize * 1.3), XStringFormats.TopLeft);
            cursorBase += height;
        }

        if (part.TypeName is { } typeName && lastType != typeName)
        {
            Heading($"Тип: {typeName}", XColor.FromArgb(36, 58, 86), XColors.White, 13, 14, 75);
            lastType = typeName;
        }
        if (part.VariantName is { } variantName)
            Heading($"Вариант: {variantName}" + (part.Selected ? "  ·  ВЫБРАН" : ""),
                part.Selected ? XColor.FromArgb(210, 228, 252) : XColor.FromArgb(225, 233, 243),
                XColor.FromArgb(23, 32, 51), 11, 5, 35);

        var completed = new List<(DocumentBlock Block, double End, double ActualEnd)>();
        Graphics(0);
        var top = part.VariantName is null || template.Blocks.Count == 0
            ? template.Margin : template.Blocks.Min(block => block.Y);
        var orderedBlocks = template.Blocks.OrderBy(block => block.Y).ThenBy(block => block.X);
        foreach (var block in orderedBlocks)
            {
                var data = content.Blocks.FirstOrDefault(b => b.Id == block.Id);
                if (data is null) continue;
                var start = cursorBase + block.Y - top;
                var predecessors = completed.Where(p => p.Block.Y + p.Block.Height <= block.Y + .01
                    && p.Block.X < block.X + block.Width && p.Block.X + p.Block.Width > block.X)
                    .ToArray();
                var nearestBottom = predecessors.Length == 0 ? double.NegativeInfinity
                    : predecessors.Max(prior => prior.Block.Y + prior.Block.Height);
                var nearest = predecessors.Where(prior =>
                    prior.Block.Y + prior.Block.Height >= nearestBottom - .01).ToArray();
                var afterTable = block.Kind == "totals" &&
                    nearest.Any(prior => prior.Block.Kind == "table");
                if (afterTable) start = double.NegativeInfinity;
                foreach (var prior in afterTable ? nearest : predecessors)
                {
                    var gap = block.Y - (prior.Block.Y + prior.Block.Height);
                    // Сохраняем зазор, заданный расположением блоков в конструкторе.
                    // Пустую часть прямоугольника таблицы при печати не резервируем.
                    var end = afterTable ? prior.ActualEnd : prior.End;
                    start = Math.Max(start, end + gap);
                }
                var cursor = start + block.Padding;
                var width = block.Width - block.Padding * 2;
                var font = new XFont(template.FontFamily == "serif" ? "QuoteSerif" : "QuoteSans", block.FontSize);
                var bold = new XFont(template.FontFamily == "serif" ? "QuoteSerif" : "QuoteSans", block.FontSize, XFontStyleEx.Bold);
                var lineHeight = block.FontSize * template.LineHeight;
                var pen = new XPen(XColor.FromArgb(216, 222, 232), .6);
                DocumentCanvasTable? activeTable = null;

                void Row(IReadOnlyList<string> cells, IReadOnlyList<double> weights, bool heading, bool border,
                    XColor? background = null, XColor? foreground = null)
                {
                    if (cells.Count == 0) return;
                    var selectedFont = heading ? bold : font;
                    var sum = weights.Sum();
                    var widths = weights.Select(w => width * w / sum).ToArray();
                    var lines = cells.Select((text, i) => Wrap(Graphics((int)(cursor / pageHeight)), text, selectedFont, Math.Max(1, widths[i] - 8))).ToArray();
                    var count = lines.Max(l => l.Count);
                    var offset = 0;
                    while (offset < count)
                    {
                        var page = (int)(cursor / pageHeight);
                        var local = cursor % pageHeight;
                        var capacity = (int)((pageHeight - local - 8) / lineHeight);
                        if (capacity < 1)
                        {
                            cursor = (page + 1) * pageHeight;
                            if (border && !heading && activeTable is not null)
                            {
                                var headerHeight = activeTable.Columns.Select((text, i) =>
                                    Wrap(Graphics(page + 1), text, bold, Math.Max(1, widths[i] - 8)).Count).Max() * lineHeight + 8;
                                if (headerHeight < pageHeight / 3) Row(activeTable.Columns, activeTable.Widths, true, true);
                            }
                            continue;
                        }
                        var take = Math.Min(capacity, count - offset);
                        var height = take * lineHeight + 8;
                        var graphics = Graphics(page);
                        var x = block.X + block.Padding;
                        var y = template.Margin + local;
                        for (var column = 0; column < cells.Count; column++)
                        {
                            if (background is { } fill) graphics.DrawRectangle(new XSolidBrush(fill), x, y, widths[column], height);
                            if (heading && border) graphics.DrawRectangle(new XSolidBrush(XColor.FromArgb(240, 244, 249)), x, y, widths[column], height);
                            if (border) graphics.DrawRectangle(pen, x, y, widths[column], height);
                            for (var line = 0; line < take && offset + line < lines[column].Count; line++)
                            {
                                var text = lines[column][offset + line];
                                var measured = graphics.MeasureString(text, selectedFont).Width;
                                var left = column == cells.Count - 1 && cells.Count > 1 && background is not null
                                    ? widths[column] - measured - 4
                                    : block.Align switch { "right" => widths[column] - measured - 4, "center" => (widths[column] - measured) / 2, _ => 4 };
                                graphics.DrawString(text, selectedFont,
                                    foreground is { } ink ? new XSolidBrush(ink) : XBrushes.Black,
                                    new XPoint(x + Math.Max(4, left), y + 4 + line * lineHeight), XStringFormats.TopLeft);
                            }
                            x += widths[column];
                        }
                        cursor += height;
                        offset += take;
                    }
                }

                if (data.Title.Length > 0) Row([data.Title], [1], true, false);
                foreach (var row in PartyRows(data.Lines,
                    block.Kind is "client" or "executor" ? block.EffectiveFieldColumns : 1))
                    Row(row.Cells, row.Widths, false, false);
                string? lastCategory = null;
                foreach (var table in data.Tables)
                {
                    activeTable = table;
                    if (block.Kind == "table" && (table.CategoryTotal is not null || table.SectionTotal is not null))
                    {
                        var separator = table.Title.IndexOf(" / ", StringComparison.Ordinal);
                        var categoryName = separator < 0 ? table.Title : table.Title[..separator];
                        var sectionName = separator < 0 ? "Позиции" : table.Title[(separator + 3)..];
                        if (sectionName == categoryName) sectionName = "Позиции";
                        var categoryKey = table.CategoryId?.ToString() ?? categoryName;
                        if (lastCategory != categoryKey)
                        {
                            if (lastCategory is not null) cursor += 8;
                            var total = table.CategoryTotal is { } categoryTotal ? DocumentCanvasBuilder.Money(categoryTotal) : null;
                            Row(total is null ? [categoryName] : [categoryName, total],
                                total is null ? [1] : [3, 1], true, false,
                                XColor.FromArgb(36, 58, 86), XColors.White);
                            lastCategory = categoryKey;
                        }
                        cursor += 5;
                        var sectionTotal = table.SectionTotal is { } amount ? DocumentCanvasBuilder.Money(amount) : null;
                        Row(sectionTotal is null ? [sectionName] : [sectionName, sectionTotal],
                            sectionTotal is null ? [1] : [3, 1], true, false,
                            XColor.FromArgb(223, 232, 243));
                    }
                    else Row([table.Title], [1], true, false);
                    Row(table.Columns, table.Widths, true, true);
                    foreach (var row in table.Rows) Row(row, table.Widths, false, true);
                    cursor += 12;
                }
                completed.Add((block, Math.Max(start + block.Height, cursor + block.Padding),
                    cursor + block.Padding));
            }
        return completed.Count == 0 ? cursorBase : Math.Max(cursorBase, completed.Max(item => item.ActualEnd)) + 12;
    }

    internal static IReadOnlyList<(IReadOnlyList<string> Cells, IReadOnlyList<double> Widths)> PartyRows(
        IReadOnlyList<string> lines, int columns)
    {
        var rows = new List<(IReadOnlyList<string>, IReadOnlyList<double>)>();
        for (var start = 0; start < lines.Count; start += columns)
        {
            rows.Add((Enumerable.Range(0, columns)
                .Select(i => start + i < lines.Count ? lines[start + i] : "").ToArray(),
                Enumerable.Repeat(1.0, columns).ToArray()));
        }
        return rows;
    }

    private static List<string> Wrap(XGraphics graphics, string text, XFont font, double width)
    {
        var result = new List<string>();
        foreach (var paragraph in text.Replace("\r", "").Split('\n'))
        {
            var line = "";
            foreach (var word in paragraph.Split(' '))
            {
                var candidate = line.Length == 0 ? word : line + " " + word;
                if (graphics.MeasureString(candidate, font).Width <= width) { line = candidate; continue; }
                if (line.Length > 0) { result.Add(line); line = ""; }
                foreach (var rune in word.EnumerateRunes())
                {
                    if (line.Length > 0 && graphics.MeasureString(line + rune, font).Width > width) { result.Add(line); line = ""; }
                    line += rune;
                }
            }
            result.Add(line);
        }
        return result;
    }
}
