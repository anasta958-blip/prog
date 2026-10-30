using System.Text.Json;
using SkladKomforta.Application.Onboarding;
using SkladKomforta.Application.Quotes;

namespace SkladKomforta.Api.IntegrationTests;

public sealed class QuoteConfiguredCalculationEngineTests
{
    [Fact]
    public void FieldTotalsReplaceLegacyPipelineAndAggregateParticipation()
    {
        var values = new Dictionary<string, JsonElement> { ["extra"] = JsonSerializer.SerializeToElement(15m) };
        var row = new SaveQuotePositionRequest(null, null, "Item", "", "", 2m, 40m, 100m, null, null, null, false, values);
        var pipeline = new MoneyPipelineDraft("equipment", "base_price", null, null, null, "quantity", "computed", 2, false);
        var rule = new CalculationRuleDraft("old", "Old total", "equipment", "row_calculation", true, null, [],
            [new RuleActionDraft("aggregate_money", SourceFieldCode: "extra", AggregationOperation: "add", MultiplyByQuantity: true, QuantityFieldCode: "quantity")]);
        for (var run = 0; run < 3; run++)
        {
            var result = QuoteConfiguredCalculationEngine.Calculate(row, "equipment", [rule], [pipeline],
                totalFields: new HashSet<string> { "computed", "extra" });
            Assert.Equal(215m, result.LineTotal);
            Assert.Equal(200m, result.Values["computed"].GetDecimal());
            Assert.Equal(200m, result.Values["line_total"].GetDecimal());
            row = row with { Values = result.Values };
        }
        Assert.Equal(0m, QuoteConfiguredCalculationEngine.Calculate(row, "equipment", [rule], [pipeline],
            totalFields: new HashSet<string>()).LineTotal);
        Assert.Equal(215m, QuoteConfiguredCalculationEngine.Calculate(row, "equipment", [rule], [],
            totalFields: new HashSet<string> { "line_total", "extra" }).LineTotal);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void FormulaUsesFreshPipelineOutputAndFeedsAnotherPipeline(bool stale)
    {
        var values = new Dictionary<string, JsonElement> { ["discount"] = JsonSerializer.SerializeToElement(10m) };
        if (stale) values["subtotal"] = JsonSerializer.SerializeToElement(1m);
        var position = new SaveQuotePositionRequest(null, null, "Item", "", "", 2m, null, 100m, null, null, null, false, values);
        var formula = new FormulaDraft([
            new FormulaTokenDraft("field", FieldCode: "subtotal"),
            new FormulaTokenDraft("operator", Operator: "multiply"),
            new FormulaTokenDraft("field", FieldCode: "discount")]);
        var rule = new CalculationRuleDraft("r", "Discount", "equipment", "row_calculation", true, null, [],
            [new RuleActionDraft("calculate_field", TargetFieldCode: "discount_amount", Formula: formula)]);
        var first = new MoneyPipelineDraft("equipment", "base_price", null, null, null, "quantity", "subtotal", 2, true, "first");
        var last = new MoneyPipelineDraft("equipment", "discount_amount", null, null, null, null, "final", 2, false, "last");
        var result = QuoteConfiguredCalculationEngine.Calculate(position, "equipment", [rule], [last, first], new HashSet<string> { "discount" });
        Assert.Equal(200m, result.Values["subtotal"].GetDecimal());
        Assert.Equal(20m, result.Values["discount_amount"].GetDecimal());
        Assert.Equal(20m, result.Values["final"].GetDecimal());
        Assert.Equal(100m, result.BasePrice);
    }

    [Theory]
    [InlineData("22", 22)]
    [InlineData("0", 0)]
    [InlineData("null", 0)]
    [InlineData("\"\"", 0)]
    [InlineData("\"  \"", 0)]
    [InlineData(null, 0)]
    public void SavedFormulaUsesPercentageMetadataWithoutChangingStoredRate(string? json, int expected)
    {
        var values = new Dictionary<string, JsonElement>();
        if (json is not null) values["discount"] = JsonSerializer.Deserialize<JsonElement>(json);
        var position = new SaveQuotePositionRequest(null, null, "Item", "", "", 1m,
            null, 1000m, null, null, null, false,
            values);
        var formula = new FormulaDraft([
            new FormulaTokenDraft("field", FieldCode: "base_price"),
            new FormulaTokenDraft("operator", Operator: "multiply"),
            new FormulaTokenDraft("field", FieldCode: "discount")]);
        var rule = new CalculationRuleDraft("discount", "Discount", "equipment", "row_calculation", true, null, [],
            [new RuleActionDraft("calculate_field", TargetFieldCode: "discount_amount", Formula: formula)]);
        var result = QuoteConfiguredCalculationEngine.Calculate(position, "equipment", [rule], [],
            new HashSet<string> { "discount" });
        Assert.Equal(expected * 10m, result.Values["discount_amount"].GetDecimal());
        Assert.Equal(expected, result.Values["discount"].GetDecimal());
    }

    [Fact]
    public void PipelineOutputDoesNotReplaceSystemPrice()
    {
        var position = new SaveQuotePositionRequest(null, null, "Item", "", "", 2m,
            100m, 4100m, null, null, null, false,
            new Dictionary<string, JsonElement> { ["minimal_price"] = JsonSerializer.SerializeToElement(1m) });
        var pipeline = new MoneyPipelineDraft("equipment", "base_price", "minimal_price", null, null,
            "quantity", "base_price", 2, true, "total");
        var result = QuoteConfiguredCalculationEngine.Calculate(position, "equipment", [], [pipeline]);
        Assert.Equal(2m, result.LineTotal);
        Assert.Equal(4100m, result.BasePrice);
        Assert.Null(result.ManualPrice);
        Assert.Equal(2m, result.Quantity);
    }

    [Theory]
    [InlineData(false, false, false)]
    [InlineData(true, false, true)]
    [InlineData(false, true, true)]
    [InlineData(true, true, true)]
    public void ConditionalExclusionIsReversibleAndCombinesRules(bool first, bool second, bool expected)
    {
        var position = new SaveQuotePositionRequest(null, null, "Item", "", "", 1m,
            null, 100m, null, null, null, true,
            new Dictionary<string, JsonElement> {
                ["first"] = JsonSerializer.SerializeToElement(first),
                ["second"] = JsonSerializer.SerializeToElement(second),
            });
        CalculationRuleDraft Rule(string code) => new(code, code, "equipment", "field_changed", true, code,
            [new RuleConditionDraft(code, "is_true")], [new RuleActionDraft("exclude_row")]);
        var result = QuoteConfiguredCalculationEngine.Calculate(position, "equipment", [Rule("first"), Rule("second")], []);
        Assert.Equal(expected, result.ExcludeFromTotals);
        position = position with { ExcludeFromTotals = result.ExcludeFromTotals, Values = result.Values };
        var reloaded = QuoteConfiguredCalculationEngine.Calculate(position, "equipment", [Rule("first"), Rule("second")], []);
        Assert.Equal(expected, reloaded.ExcludeFromTotals);
    }

    [Fact]
    public void SavingDoesNotReplayUnrelatedFieldChangeActions()
    {
        var position = new SaveQuotePositionRequest(
            null, null, "Item", "", "", 3m, 100m, 1300m,
            null, null, null, false,
            new Dictionary<string, JsonElement> { ["note"] = JsonSerializer.SerializeToElement("kept") });
        var rule = new CalculationRuleDraft("flag", "Exclude", "equipment", "field_changed", true, "flag", [],
            [new RuleActionDraft("exclude_row")]);
        var pipeline = new MoneyPipelineDraft("equipment", "base_price", null, null, null,
            "quantity", "custom_total", 2, true, "total");

        var result = QuoteConfiguredCalculationEngine.Calculate(position, "equipment", [rule], [pipeline]);

        Assert.False(result.ExcludeFromTotals);
        Assert.Equal(3900m, result.LineTotal);
        Assert.Equal(3900m, result.Values["custom_total"].GetDecimal());
        Assert.Equal("kept", result.Values["note"].GetString());
    }
}
