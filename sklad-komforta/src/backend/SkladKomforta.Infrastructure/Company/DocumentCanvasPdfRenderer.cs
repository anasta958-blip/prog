using PdfSharp.Drawing;
using PdfSharp.Pdf;
using SkladKomforta.Application.Company;
using SkladKomforta.Infrastructure.Quotes;

namespace SkladKomforta.Infrastructure.Company;

internal static class DocumentCanvasPdfRenderer
{
    public static byte[] Render(string title, IReadOnlyList<DocumentCanvasContent> documents)
    {
        QuotePdfFontResolver.EnsureRegistered();
        using var pdf = new PdfDocument();
        pdf.Info.Title = title;
        foreach (var content in documents) AddDocument(pdf, content);
        if (pdf.PageCount == 0) pdf.AddPage();
        using var output = new MemoryStream();
        pdf.Save(output, false);
        return output.ToArray();
    }

    private static void AddDocument(PdfDocument pdf, DocumentCanvasContent content)
    {
        var template = content.Template;
        var pageHeight = template.Height - template.Margin * 2;
        var pages = new List<XGraphics>();
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
                    var caption = content.Caption ?? pdf.Info.Title;
                    while (caption.Length > 0 && graphics.MeasureString(caption, footerFont).Width > template.Width - template.Margin * 2 - 50)
                        caption = caption[..^1];
                    graphics.DrawString($"{caption} · {pdf.PageCount}", footerFont, XBrushes.Gray,
                        new XPoint(template.Margin, template.Height - 13), XStringFormats.TopLeft);
                }
                pages.Add(graphics);
            }
            return pages[page];
        }

        var completed = new List<(DocumentBlock Block, double End)>();
        Graphics(0);
        try
        {
            foreach (var block in template.Blocks.OrderBy(b => b.Y).ThenBy(b => b.X))
            {
                var data = content.Blocks.FirstOrDefault(b => b.Id == block.Id);
                if (data is null) continue;
                var start = block.Y - template.Margin;
                foreach (var prior in completed.Where(p => p.Block.Y + p.Block.Height <= block.Y + .01
                    && p.Block.X < block.X + block.Width && p.Block.X + p.Block.Width > block.X))
                    start = Math.Max(start, prior.End + block.Y - (prior.Block.Y + prior.Block.Height));
                var cursor = start + block.Padding;
                var width = block.Width - block.Padding * 2;
                var font = new XFont(template.FontFamily == "serif" ? "QuoteSerif" : "QuoteSans", block.FontSize);
                var bold = new XFont(template.FontFamily == "serif" ? "QuoteSerif" : "QuoteSans", block.FontSize, XFontStyleEx.Bold);
                var lineHeight = block.FontSize * template.LineHeight;
                var pen = new XPen(XColor.FromArgb(216, 222, 232), .6);
                DocumentCanvasTable? activeTable = null;

                void Row(IReadOnlyList<string> cells, IReadOnlyList<double> weights, bool heading, bool border)
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
                            if (heading && border) graphics.DrawRectangle(new XSolidBrush(XColor.FromArgb(240, 244, 249)), x, y, widths[column], height);
                            if (border) graphics.DrawRectangle(pen, x, y, widths[column], height);
                            for (var line = 0; line < take && offset + line < lines[column].Count; line++)
                            {
                                var text = lines[column][offset + line];
                                var measured = graphics.MeasureString(text, selectedFont).Width;
                                var left = block.Align switch { "right" => widths[column] - measured - 4, "center" => (widths[column] - measured) / 2, _ => 4 };
                                graphics.DrawString(text, selectedFont, XBrushes.Black,
                                    new XPoint(x + Math.Max(4, left), y + 4 + line * lineHeight), XStringFormats.TopLeft);
                            }
                            x += widths[column];
                        }
                        cursor += height;
                        offset += take;
                    }
                }

                if (data.Title.Length > 0) Row([data.Title], [1], true, false);
                foreach (var line in data.Lines) Row([line], [1], false, false);
                foreach (var table in data.Tables)
                {
                    activeTable = table;
                    Row([table.Title], [1], true, false);
                    Row(table.Columns, table.Widths, true, true);
                    foreach (var row in table.Rows) Row(row, table.Widths, false, true);
                    cursor += 12;
                }
                completed.Add((block, Math.Max(start + block.Height, cursor + block.Padding)));
            }
        }
        finally { foreach (var graphics in pages) graphics.Dispose(); }
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
