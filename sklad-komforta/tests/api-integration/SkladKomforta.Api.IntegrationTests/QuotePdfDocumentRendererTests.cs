using System.Text;
using System.Text.RegularExpressions;
using SkladKomforta.Application.Quotes;
using SkladKomforta.Infrastructure.Quotes;

namespace SkladKomforta.Api.IntegrationTests;

public sealed class QuotePdfDocumentRendererTests
{
    [Fact]
    public void RenderCreatesReadableMultipageDocumentForRussianPositions()
    {
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
                        null,
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
    }
}
