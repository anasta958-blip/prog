using System.Text;
using System.Text.RegularExpressions;
using SkladKomforta.Application.Quotes;
using SkladKomforta.Application.Kanban;
using MigraDoc.DocumentObjectModel;
using MigraDoc.DocumentObjectModel.Tables;
using SkladKomforta.Infrastructure.Quotes;

namespace SkladKomforta.Api.IntegrationTests;

public sealed class QuotePdfDocumentRendererTests
{
    [Fact]
    public void RenderCreatesReadableMultipageDocumentForRussianPositions()
    {
        var categoryId = Guid.NewGuid();
        var positions = Enumerable.Range(1, 80)
            .Select(index => new QuotePositionDetails(
                Guid.NewGuid(),
                null,
                $"Позиция {index}",
                $"М-{index}",
                "шт",
                1m,
                50m,
                100m,
                null,
                null,
                null,
                100m,
                false,
                new Dictionary<string, System.Text.Json.JsonElement>(),
                index - 1))
            .ToArray();
        var quote = new QuoteDetails(
            Guid.NewGuid(),
            Guid.NewGuid(),
            Guid.NewGuid(),
            QuoteKindCodes.Quote,
            "Поставка оборудования",
            Guid.NewGuid(),
            Guid.NewGuid(),
            null,
            null,
            "variant",
            "Дополнительная информация",
            [new QuoteProposalTypeDetails(
                Guid.NewGuid(),
                "Основное предложение",
                0,
                null,
                [new QuoteVariantDetails(
                    Guid.NewGuid(),
                    "Оптимальный",
                    null,
                    20m,
                    0,
                    [new QuoteCategoryDetails(
                        Guid.NewGuid(),
                        categoryId,
                        "Оборудование",
                        0,
                        [new QuoteSectionDetails(
                            Guid.NewGuid(),
                            null,
                            "Вентиляция",
                            null,
                            null,
                            0,
                            positions)])])])],
            DateTimeOffset.UtcNow,
            DateTimeOffset.UtcNow);

        var bytes = QuotePdfDocumentRenderer.Render(quote, null, null, null, null);

        var pdfStructure = Encoding.ASCII.GetString(bytes);
        Assert.StartsWith("%PDF", pdfStructure);
        Assert.True(Regex.Count(pdfStructure, @"/Type\s*/Page\b") > 1);

        var selected = new Dictionary<Guid, IReadOnlyList<KanbanFieldSummary>> {
            [categoryId] = [
                new("marking", "Метка", "text", false, 0, null, []),
                new("quantity", "Количество", "number", false, 1, null, [])
            ]
        };
        var document = QuotePdfDocumentRenderer.BuildDocument(quote, null, null, null, null, null, selected);
        static string CellText(Cell cell) => string.Concat(cell.Elements.OfType<Paragraph>()
            .SelectMany(paragraph => paragraph.Elements.OfType<Text>()).Select(text => text.Content));
        var table = document.Sections[0].Elements.OfType<Table>()
            .Single(item => item.Rows.Count > 0 && CellText(item.Rows[0].Cells[0]) == "Метка");
        Assert.Equal(2, table.Columns.Count);
        Assert.Equal("Количество", CellText(table.Rows[0].Cells[1]));
        Assert.Equal("М-1", CellText(table.Rows[1].Cells[0]));
        Assert.Equal("1", CellText(table.Rows[1].Cells[1]));
        Assert.StartsWith("%PDF", Encoding.ASCII.GetString(QuotePdfDocumentRenderer.Render(quote, null, null, null, null, null, selected)));
        selected[categoryId] = [];
        Assert.StartsWith("%PDF", Encoding.ASCII.GetString(QuotePdfDocumentRenderer.Render(quote, null, null, null, null, null, selected)));
    }
}
