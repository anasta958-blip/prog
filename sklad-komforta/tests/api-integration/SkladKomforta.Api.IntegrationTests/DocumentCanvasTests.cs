using PdfSharp.Pdf.IO;
using SkladKomforta.Application.Company;
using SkladKomforta.Application.Identity;
using SkladKomforta.Infrastructure.Company;

namespace SkladKomforta.Api.IntegrationTests;

public sealed class DocumentCanvasTests
{
    private static DocumentBlock Block(string kind = "table") => new(kind, kind, 30, 30, 734, 200, 12, 10, "left", ["name"], new Dictionary<string, double>());
    private static DocumentTemplate Template(DocumentBlock? block = null) => new(false, 30, 12, 1.35, "sans", [block ?? Block()]);

    [Fact]
    public void ValidatesBoundsKindsAndPartyFields()
    {
        Template().Validate();
        Assert.Throws<IdentityException>(() => Template(Block() with { X = -1 }).Validate());
        Assert.Throws<IdentityException>(() => Template(Block() with { Width = double.NaN }).Validate());
        Assert.Throws<IdentityException>(() => Template(Block() with { Fields = ["passport_number"] }).Validate());
        Assert.Throws<IdentityException>(() => (Template() with { Blocks = [Block(), Block()] }).Validate());
        Assert.Throws<IdentityException>(() => Template(Block() with { ColumnWidths = new Dictionary<string, double> { ["price"] = 0 } }).Validate());
    }

    [Fact]
    public void ProjectionOnlyContainsSelectedPartyFieldsAndPresentBlocks()
    {
        var template = Template(Block("client") with { Fields = ["inn", "name"] });
        var content = DocumentCanvasBuilder.Build(template,
            new Dictionary<string, string?> { ["name"] = "Заказчик", ["inn"] = "123", ["bank_account"] = "secret" },
            new Dictionary<string, string?>(), [new("secret table", ["secret"], [1], [["secret"]])], ["secret total"]);
        Assert.Equal(["ИНН: 123", "Название: Заказчик"], content.Blocks[0].Lines);
        Assert.Empty(content.Blocks[0].Tables);
        Assert.DoesNotContain("secret", System.Text.Json.JsonSerializer.Serialize(content), StringComparison.Ordinal);
    }

    [Fact]
    public void CategoryOrderKeepsSectionsStableAndAppendsNewCategories()
    {
        var first = Guid.NewGuid();
        var second = Guid.NewGuid();
        var template = Template(Block() with { CategoryOrder = [second, first] });
        template.Validate();
        DocumentCanvasTable Table(string title, Guid? id) => new(title, ["Название"], [1], [], id);
        var content = DocumentCanvasBuilder.Build(template, new Dictionary<string, string?>(),
            new Dictionary<string, string?>(),
            [Table("A", first), Table("B1", second), Table("B2", second), Table("New", Guid.NewGuid())], []);
        Assert.Equal(["B1", "B2", "A", "New"], content.Blocks.Single().Tables.Select(t => t.Title));
        Assert.Throws<IdentityException>(() => Template(Block() with { CategoryOrder = [first, first] }).Validate());
    }

    [Fact]
    public void PartyFieldsFlowAcrossWidthAndWrapWithoutLosingValues()
    {
        string[] lines = ["ИНН: 123", "КПП: 456", new string('Ж', 100), "Телефон: 123"];
        var rows = DocumentCanvasPdfRenderer.PartyRows(lines, 220, s => s.Length * 8, true);
        Assert.Equal(2, rows[0].Cells.Count);
        Assert.Equal(lines, rows.SelectMany(r => r.Cells));
        Assert.All(rows, row => Assert.True(row.Widths.Sum() <= 220));
        Assert.Equal(4, DocumentCanvasPdfRenderer.PartyRows(lines, 220, s => s.Length * 8, false).Count);
        var template = Template(Block("client") with { FlowFields = true, Fields = ["inn", "kpp"] });
        var content = DocumentCanvasBuilder.Build(template,
            new Dictionary<string, string?> { ["inn"] = "123", ["kpp"] = "456" }, new Dictionary<string, string?>(), [], []);
        Assert.True(DocumentCanvasPdfRenderer.Render("Реквизиты", [content]).Length > 1000);
    }

    [Theory]
    [InlineData(false, "sans")]
    [InlineData(true, "serif")]
    public void PdfPaginatesLongCyrillicTables(bool landscape, string font)
    {
        var template = Template() with { Landscape = landscape, FontFamily = font };
        var rows = Enumerable.Range(1, 160).Select(i => (IReadOnlyList<string>)
            [$"Позиция {i}. Длинное описание оборудования для проверки переноса строк в документе", $"{i},00 ₽"]).ToArray();
        var content = DocumentCanvasBuilder.Build(template, new Dictionary<string, string?>(), new Dictionary<string, string?>(),
            [new("Оборудование / Вентиляторы", ["Наименование", "Цена"], [3, 1], rows)], []);
        var bytes = DocumentCanvasPdfRenderer.Render("Проверка конструктора", [content]);
        using var stream = new MemoryStream(bytes);
        using var pdf = PdfReader.Open(stream, PdfDocumentOpenMode.Import);
        Assert.True(pdf.PageCount > 1);
        Assert.True(bytes.Length > 10000);
        if (Environment.GetEnvironmentVariable("SKLAD_DOCUMENT_TEST_OUTPUT") is { Length: > 0 } output)
        {
            Directory.CreateDirectory(output);
            File.WriteAllBytes(Path.Combine(output, $"canvas-{font}.pdf"), bytes);
        }
    }
}
