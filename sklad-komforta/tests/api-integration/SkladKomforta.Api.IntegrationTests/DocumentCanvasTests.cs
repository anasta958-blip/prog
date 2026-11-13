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
        Assert.Throws<IdentityException>(() => Template(Block() with { Fields = ["unknown_field"] }).Validate());
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
    public void PartyProfilesSelectActualTypeAndPreserveFieldOrder()
    {
        var template = Template(Block("client") with
        {
            PartyFieldsByType = new Dictionary<string, IReadOnlyList<string>>
            {
                ["person"] = ["phone", "name"],
                ["ip"] = ["ogrn", "name"],
                ["ooo"] = ["name", "kpp"]
            }
        });
        template.Validate();
        var restored = System.Text.Json.JsonSerializer.Deserialize<DocumentTemplate>(
            System.Text.Json.JsonSerializer.Serialize(template))!;
        foreach (var type in new[] { "person", "ip", "ooo" })
        {
            var party = DocumentCanvasBuilder.Party(new
            {
                CompanyType = type, Name = "Тест", Phone = "123", Ogrn = "456", Kpp = "789",
                PassportNumber = "private passport"
            });
            var content = DocumentCanvasBuilder.Parties(restored, party, new Dictionary<string, string?>());
            string[] expected = type switch
            {
                "person" => ["Телефон: 123", "ФИО: Тест"],
                "ip" => ["ОГРНИП: 456", "Название ИП: Тест"],
                _ => ["Название компании: Тест", "КПП: 789"]
            };
            Assert.Equal(expected, content.Blocks.Single().Lines);
            Assert.DoesNotContain("private passport", System.Text.Json.JsonSerializer.Serialize(content));
        }
    }

    [Theory]
    [InlineData("client", "person", "inn")]
    [InlineData("client", "ip", "kpp")]
    [InlineData("executor", "person", "name")]
    [InlineData("executor", "ooo", "passport_number")]
    public void PartyProfilesRejectFieldsOfOtherTypes(string kind, string type, string field)
    {
        Assert.Throws<IdentityException>(() => Template(Block(kind) with
        {
            PartyFieldsByType = new Dictionary<string, IReadOnlyList<string>> { [type] = [field] }
        }).Validate());
    }

    [Fact]
    public void PartyHeaderAndVariantBodyDoNotDuplicatePartyDetails()
    {
        var template = Template() with { Blocks = [
            Block("client") with { Fields = ["name"] },
            Block("executor") with { Fields = ["name"] },
            Block("table"),
            Block("totals")
        ] };
        var client = new Dictionary<string, string?> { ["name"] = "Заказчик" };
        var executor = new Dictionary<string, string?> { ["name"] = "Исполнитель" };
        var header = DocumentCanvasBuilder.Parties(template, client, executor);
        var body = DocumentCanvasBuilder.WithoutParties(DocumentCanvasBuilder.Build(template,
            client, executor, [new("Категория", ["Наименование"], [1], [["Товар"]])], ["Итого: 100 ₽"]));

        Assert.Equal(["client", "executor"], header.Template.Blocks.Select(block => block.Kind));
        Assert.Equal(["table", "totals"], body.Template.Blocks.Select(block => block.Kind));
        Assert.Contains(header.Blocks.SelectMany(block => block.Lines), line => line.Contains("Заказчик", StringComparison.Ordinal));
        Assert.DoesNotContain(body.Blocks.SelectMany(block => block.Lines), line => line.Contains("Заказчик", StringComparison.Ordinal));
        Assert.DoesNotContain(body.Blocks.SelectMany(block => block.Lines), line => line.Contains("Исполнитель", StringComparison.Ordinal));
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
        var rows = DocumentCanvasPdfRenderer.PartyRows(lines, 2);
        Assert.Equal(2, rows[0].Cells.Count);
        Assert.Equal(lines, rows.SelectMany(r => r.Cells));
        Assert.All(rows, row => Assert.Equal([1.0, 1.0], row.Widths));
        Assert.Equal(4, DocumentCanvasPdfRenderer.PartyRows(lines, 1).Count);
        var grid = DocumentCanvasPdfRenderer.PartyRows(lines, 3);
        Assert.Equal([lines[3], "", ""], grid[1].Cells);
        Assert.Equal([1.0, 1.0, 1.0], grid[1].Widths);
        Assert.Throws<IdentityException>(() => Template(Block() with { FieldColumns = 0 }).Validate());
        var template = Template(Block("client") with { FieldColumns = 3, Fields = ["inn", "kpp"] });
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

    [Fact]
    public void ConsecutiveVariantsSharePageWithConfiguredTableTotalsGap()
    {
        var template = Template() with
        {
            Blocks =
            [
                Block("client") with { Y = 30, Height = 100, Fields = ["name"] },
                Block("table") with { Y = 180, Height = 400 },
                Block("totals") with { Y = 800, Height = 100 },
            ],
        };
        var client = new Dictionary<string, string?> { ["name"] = "Заказчик" };
        var parties = DocumentCanvasBuilder.Parties(template, client, new Dictionary<string, string?>());
        var body = DocumentCanvasBuilder.WithoutParties(DocumentCanvasBuilder.Build(template,
            client, new Dictionary<string, string?>(),
            [new DocumentCanvasTable("Оборудование / Монтаж", ["Название", "Цена"], [3, 1],
                [["Кондиционер", "100 ₽"]])], ["Итого: 100 ₽"]));

        var bytes = DocumentCanvasPdfRenderer.RenderParts("КП", [
            new DocumentCanvasPdfPart(parties),
            new DocumentCanvasPdfPart(body, "Оборудование", "Первый", true),
            new DocumentCanvasPdfPart(body, "Оборудование", "Второй"),
        ]);

        using var stream = new MemoryStream(bytes);
        using var pdf = PdfReader.Open(stream, PdfDocumentOpenMode.Import);
        Assert.Equal(1, pdf.PageCount);
    }

    [Fact]
    public void DeliberatelyLargeTableTotalsGapRemainsInGenericPdf()
    {
        var template = Template() with
        {
            Blocks =
            [
                Block("table") with { Y = 30, Height = 100 },
                Block("totals") with { Y = 850, Height = 100 },
            ],
        };
        var content = DocumentCanvasBuilder.Build(template,
            new Dictionary<string, string?>(), new Dictionary<string, string?>(),
            [new DocumentCanvasTable("Оборудование", ["Название"], [1], [["Товар"]])],
            ["Итого: 100 ₽"]);
        var bytes = DocumentCanvasPdfRenderer.Render("Комплектация", [content, content]);

        using var stream = new MemoryStream(bytes);
        using var pdf = PdfReader.Open(stream, PdfDocumentOpenMode.Import);
        Assert.Equal(2, pdf.PageCount);
    }
}
