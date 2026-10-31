using System.Text.Json;
using SkladKomforta.Application.Onboarding;
using SkladKomforta.Application.Quotes;

namespace SkladKomforta.Api.IntegrationTests;

public sealed class QuoteConfiguredCalculationEngineTests
{
    [Theory]
    [InlineData("exclude_row", false)]
    [InlineData("exclude_row", true)]
    [InlineData("block_save", false)]
    [InlineData("block_save", true)]
    public void SaveRespectsVariantEffectsWithoutReevaluatingTheirConditions(string actionType, bool fired)
    {
        var rule = new CalculationRuleDraft("variant", "Variant", "equipment", "variant_calculation", true, null,
            [new RuleConditionDraft("variant_total", "greater_than", "10")],
            [new RuleActionDraft(actionType, Message: "Blocked")]);
        var activeIds = new List<string>();
        if (fired) activeIds.Add("variant");
        var values = new Dictionary<string, JsonElement> {
            ["_active_effect_rules"] = JsonSerializer.SerializeToElement(activeIds)
        };
        var row = new SaveQuotePositionRequest(null, null, "Item", "", "", 1m, null, 10m, null, null, null, false, values);
        if (fired && actionType == "block_save")
            Assert.Throws<SkladKomforta.Application.Identity.IdentityException>(() =>
                QuoteConfiguredCalculationEngine.Calculate(row, "equipment", [rule], []));
        else
            Assert.Equal(fired && actionType == "exclude_row",
                QuoteConfiguredCalculationEngine.Calculate(row, "equipment", [rule], []).ExcludeFromTotals);
    }

    [Fact]
    public void SavingDoesNotRepeatVariantEventActions()
    {
        var rule = new CalculationRuleDraft("variant", "Variant", "equipment", "variant_calculation", true, null,
            [], [new RuleActionDraft("set_field", TargetFieldCode: "base_price", ConstantValue: "99")]);
        var row = new SaveQuotePositionRequest(null, null, "Item", "", "", 1m,
            null, 10m, null, null, null, false, null);
        var result = QuoteConfiguredCalculationEngine.Calculate(row, "equipment", [rule], []);
        Assert.Equal(10m, result.LineTotal);
    }

    [Theory]
    [InlineData("name")]
    [InlineData("marking")]
    [InlineData("unit")]
    public void TextConditionsUseCurrentPositionFieldsInsteadOfStaleValues(string field)
    {
        var values = new Dictionary<string, JsonElement> {
            [field] = JsonSerializer.SerializeToElement("old"),
            ["technical_note"] = JsonSerializer.SerializeToElement("пробка")
        };
        var row = new SaveQuotePositionRequest(null, null, "пробка", "пробка", "пробка", 1m,
            null, 10m, null, null, null, false, values);
        var rule = new CalculationRuleDraft("text", "Text", "equipment", "row_calculation", true, null,
            [new RuleConditionDraft("technical_note", "equals", ComparisonFieldCode: field)],
            [new RuleActionDraft("set_field", TargetFieldCode: "result", ConstantValue: "matched")]);
        var result = QuoteConfiguredCalculationEngine.Calculate(row, "equipment", [rule], []);
        Assert.Equal("пробка", result.Values[field].GetString());
        Assert.Equal("matched", result.Values["result"].GetString());
        var nextValues = result.Values.ToDictionary(pair => pair.Key, pair => pair.Value);
        nextValues.Remove("result");
        row = row with { Name = "new", Marking = "new", Unit = "new", Values = nextValues };
        var updated = QuoteConfiguredCalculationEngine.Calculate(row, "equipment", [rule], []);
        Assert.Equal("new", updated.Values[field].GetString());
        Assert.False(updated.Values.ContainsKey("result"));
        row = row with { Marking = null, Unit = null, Name = "" };
        Assert.Equal("", QuoteConfiguredCalculationEngine.Calculate(row, "equipment", [], []).Values[field].GetString());
    }

    [Theory]
    [InlineData("exclude_row", false)]
    [InlineData("exclude_row", true)]
    [InlineData("block_save", false)]
    [InlineData("block_save", true)]
    public void SaveDoesNotInventFieldEvents(string actionType, bool fired)
    {
        var rule = new CalculationRuleDraft("event", "Event", "equipment", "field_changed", true, "base_price",
            [new RuleConditionDraft("base_price", "less_than", "20")],
            [new RuleActionDraft(actionType, Message: "Blocked")]);
        var activeIds = new List<string>();
        if (fired) activeIds.Add("event");
        var values = new Dictionary<string, JsonElement> {
            ["_active_effect_rules"] = JsonSerializer.SerializeToElement(activeIds)
        };
        var row = new SaveQuotePositionRequest(null, null, "Item", "", "", 1m, null, 10m, null, null, null, false, values);
        if (fired && actionType == "block_save")
        {
            Assert.Throws<SkladKomforta.Application.Identity.IdentityException>(() =>
                QuoteConfiguredCalculationEngine.Calculate(row, "equipment", [rule], []));
        }
        else
        {
            var result = QuoteConfiguredCalculationEngine.Calculate(row, "equipment", [rule], []);
            Assert.Equal(fired && actionType == "exclude_row", result.ExcludeFromTotals);
        }
    }

    [Theory]
    [InlineData("less_than", "11", true)]
    [InlineData("less_than", "10", false)]
    [InlineData("greater_than", "9,5", true)]
    [InlineData("greater_than", "10", false)]
    [InlineData("equals", "10.0", true)]
    [InlineData("equals", "11", false)]
    [InlineData("less_than", "", false)]
    public void ConditionsCompareFieldsAndConstants(string operation, string operand, bool expected)
    {
        foreach (var useField in new[] { false, true })
        {
            var values = new Dictionary<string, JsonElement> { ["other"] = JsonSerializer.SerializeToElement(operand) };
            var row = new SaveQuotePositionRequest(null, null, "Item", "", "", 1m, null, 10m, null, null, null, false, values);
            var condition = new RuleConditionDraft("base_price", operation,
                useField ? null : operand, useField ? "other" : null);
            var rule = new CalculationRuleDraft("r", "Comparison", "equipment", "row_calculation", true, null,
                [condition], [new RuleActionDraft("exclude_row")]);
            Assert.Equal(expected, QuoteConfiguredCalculationEngine.Calculate(row, "equipment", [rule], []).ExcludeFromTotals);
        }
    }

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
            null, 100m, null, null, null, false,
            new Dictionary<string, JsonElement> {
                ["first"] = JsonSerializer.SerializeToElement(first),
                ["second"] = JsonSerializer.SerializeToElement(second),
            });
        CalculationRuleDraft Rule(string code) => new(code, code, "equipment", "row_calculation", true, null,
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
