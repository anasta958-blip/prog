using System.Text.Json;
using SkladKomforta.Application.Company;
using SkladKomforta.Application.Kanban;
using SkladKomforta.Application.Quotes;

namespace SkladKomforta.Api.IntegrationTests;

public sealed class DocumentLayoutTests
{
    [Fact]
    public void ConfiguredClientSectionDoesNotLeakHiddenPositionValues()
    {
        var position = new QuoteClientPosition(Guid.NewGuid(), "secret name", "secret marking", "secret unit",
            7m, 13m, 91m, ["Public note"]);
        var section = QuoteClientSection.Configured(Guid.NewGuid(), "Category", [position], [new("custom_note", "Note")]);
        var json = JsonSerializer.Serialize(section);
        Assert.DoesNotContain("secret", json, StringComparison.Ordinal);
        Assert.Equal(91m, section.Total);
        Assert.Equal(0m, section.Positions[0].UnitPrice);
        Assert.Equal("Public note", section.Positions[0].Cells![0]);
        Assert.Equal("custom_note", section.Columns![0].Code);
    }

    [Fact]
    public void EmptySelectionDoesNotFallBackToLegacyFields()
    {
        var section = QuoteClientSection.Configured(Guid.NewGuid(), "Category", [], []);
        Assert.Empty(section.Columns!);
        Assert.Empty(section.Positions);
        Assert.Equal(0m, section.Total);
    }

    [Fact]
    public void FieldValuesRespectTypesAndDictionaryLabels()
    {
        var id = Guid.NewGuid();
        var field = new KanbanFieldSummary("custom_vendor", "Vendor", "dictionary", false, 0, "vendors",
            [new KanbanDictionaryOption(id, "Поставщик", 0)]);
        Assert.Equal("Поставщик", DocumentFieldValue.Format(field, JsonSerializer.SerializeToElement(id.ToString())));
        Assert.Equal("Не выбрано", DocumentFieldValue.Format(field, default));
        Assert.Equal("Да", DocumentFieldValue.Format(field with { FieldType = "boolean" }, JsonSerializer.SerializeToElement(true)));
        Assert.Equal("10,50 ₽", DocumentFieldValue.Format(field with { FieldType = "money" }, JsonSerializer.SerializeToElement(10.5m)));
    }
}
