using System.Text.Json;
using SkladKomforta.Application.Onboarding;
using SkladKomforta.Infrastructure.Orders;

namespace SkladKomforta.Api.IntegrationTests;

public sealed class OrderTransferRowTests
{
    private static OrderTransferHandler.TransferRow Row(decimal quantity) => new(
        Guid.Empty, "Оборудование", null, "Раздел", null, "Труба", "D-12", "м", quantity,
        new Dictionary<string, JsonElement>
        {
            ["base_price"] = JsonSerializer.SerializeToElement(100m),
            ["line_total"] = JsonSerializer.SerializeToElement(quantity * 100m),
        }, string.Empty);

    [Fact]
    public void DifferentQuantitiesAndTotalsHaveSameKeyAndAreSummed()
    {
        var first = Row(2.5m);
        var second = Row(4m);
        first = first with { LegacyKeys = [OrderTransferHandler.KeyOf(first, includeTotal: true)] };
        second = second with { LegacyKeys = [OrderTransferHandler.KeyOf(second, includeTotal: true)] };
        Assert.Equal(OrderTransferHandler.KeyOf(first), OrderTransferHandler.KeyOf(second));
        var merged = OrderTransferHandler.MergeRows(first, second);
        Assert.Equal(6.5m, merged.Quantity);
        Assert.Equal(650m, merged.Values["line_total"].GetDecimal());
        Assert.Equal(OrderTransferHandler.KeyOf(first), OrderTransferHandler.KeyOf(merged));
        Assert.Equal(250m, first.Values["line_total"].GetDecimal());
        Assert.Equal(2, merged.LegacyKeys.Count);
    }

    [Fact]
    public void CatalogIdentityAndNumericScaleDoNotSplitIdenticalProducts()
    {
        var first = Row(2) with { CatalogItemId = Guid.NewGuid() };
        var values = Row(3).Values.ToDictionary(item => item.Key, item => item.Value);
        values["base_price"] = JsonSerializer.Deserialize<JsonElement>("100.00");
        var second = Row(3) with { CatalogItemId = Guid.NewGuid(), Values = values };

        Assert.Equal(OrderTransferHandler.KeyOf(first), OrderTransferHandler.KeyOf(second));
        Assert.NotEqual(OrderTransferHandler.KeyOf(first, legacy: true),
            OrderTransferHandler.KeyOf(second, legacy: true));
        var merged = OrderTransferHandler.MergeRows(first, second);
        Assert.Equal(5m, merged.Quantity);
        Assert.Equal(500m, merged.Values["line_total"].GetDecimal());
    }

    [Fact]
    public void CustomFieldsIncludingCalculatedTotalsDoNotAffectIdentity()
    {
        var first = Row(2);
        var values = Row(3).Values.ToDictionary(item => item.Key, item => item.Value);
        values["custom_total"] = JsonSerializer.SerializeToElement(300m);
        values["custom_supplier"] = JsonSerializer.SerializeToElement("Other supplier");
        var second = Row(3) with { Values = values };
        Assert.Equal(OrderTransferHandler.KeyOf(first), OrderTransferHandler.KeyOf(second));
        Assert.Equal(5m, OrderTransferHandler.MergeRows(first, second).Quantity);
        values["group"] = JsonSerializer.SerializeToElement("Other group");
        Assert.NotEqual(OrderTransferHandler.KeyOf(first), OrderTransferHandler.KeyOf(second));
    }

    [Fact]
    public void MergedQuantityRecalculatesPipelineAndOnlyCalculationRules()
    {
        var first = Row(2);
        var values = first.Values.ToDictionary(item => item.Key, item => item.Value);
        values["custom_price"] = JsonSerializer.SerializeToElement(5m);
        values["custom_total"] = JsonSerializer.SerializeToElement(10m);
        first = first with { CalculationInputs = values };
        var merged = OrderTransferHandler.MergeRows(first, Row(3));
        var rules = new[]
        {
            new CalculationRuleDraft("calc", "Calculation", "equipment", "row_calculation", true, null, [],
                [new RuleActionDraft("set_field", "custom_result", SourceFieldCode: "custom_total")]),
            new CalculationRuleDraft("change", "Change", "equipment", "field_change", true, null, [],
                [new RuleActionDraft("set_field", "custom_price", ConstantValue: "999")]),
            new CalculationRuleDraft("save", "Save", "equipment", "card_saving", true, null, [],
                [new RuleActionDraft("block_save", Message: "Must not run")]),
        };
        var result = OrderTransferHandler.RecalculateRow(merged, "equipment", rules,
            [new MoneyPipelineDraft("equipment", "custom_price", null, null, null, "quantity", "custom_total", 2, true)],
            null, new HashSet<string> { "custom_total", "custom_result", "line_total" });
        Assert.Equal(5m, result.Quantity);
        Assert.Equal(25m, result.Values["custom_total"].GetDecimal());
        Assert.Equal(25m, result.Values["custom_result"].GetDecimal());
        Assert.Equal(25m, result.Values["line_total"].GetDecimal());
        Assert.DoesNotContain("custom_price", result.Values.Keys);
        Assert.Equal(merged.Key, result.Key);
        Assert.Equal(10m, values["custom_total"].GetDecimal());
    }

    [Fact]
    public void OtherFieldDifferencesRemainSeparate()
    {
        var first = Row(2);
        var values = Row(4).Values.ToDictionary(item => item.Key, item => item.Value);
        values["base_price"] = JsonSerializer.SerializeToElement(200m);
        Assert.NotEqual(OrderTransferHandler.KeyOf(first),
            OrderTransferHandler.KeyOf(Row(4) with { Values = values }));
        Assert.NotEqual(OrderTransferHandler.KeyOf(first),
            OrderTransferHandler.KeyOf(Row(4) with { Marking = "D-16" }));
    }
}
