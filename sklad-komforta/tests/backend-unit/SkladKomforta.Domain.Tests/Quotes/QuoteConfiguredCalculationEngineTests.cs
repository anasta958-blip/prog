using System.Text.Json;
using SkladKomforta.Application.Identity;
using SkladKomforta.Application.Onboarding;
using SkladKomforta.Application.Quotes;

namespace SkladKomforta.Domain.Tests.Quotes;

public sealed class QuoteConfiguredCalculationEngineTests
{
    [Fact]
    public void MoneyPipelineUsesConfiguredFieldsAndFixedOperationOrder()
    {
        var position = Position(
            quantity: 2m,
            purchasePrice: 100m,
            basePrice: 100m,
            manualPrice: 120m,
            markup: 10m,
            discount: 5m);
        var pipeline = new MoneyPipelineDraft(
            "equipment", "purchase_price", "base_price", "markup_value",
            "discount_value", "quantity", "line_total", 2, true);

        var result = QuoteConfiguredCalculationEngine.Calculate(
            position, "equipment", [], [pipeline]);

        Assert.Equal(250.80m, result.LineTotal);
        Assert.Equal(120m, result.ManualPrice);
    }

    [Fact]
    public void PipelineExcludedFromTotalsDoesNotFallBackToItsResultField()
    {
        var pipeline = new MoneyPipelineDraft(
            "equipment", "base_price", null, null, null, "quantity",
            "line_total", 2, false);

        var result = QuoteConfiguredCalculationEngine.Calculate(
            Position(quantity: 3m, basePrice: 40m), "equipment", [], [pipeline]);

        Assert.Equal(0m, result.LineTotal);
        Assert.Equal(120m, result.Values["line_total"].GetDecimal());
    }

    [Fact]
    public void AggregateRuleAddsConfiguredMoneyAndQuantity()
    {
        var values = new Dictionary<string, JsonElement>
        {
            ["delivery_price"] = JsonSerializer.SerializeToElement(25m),
        };
        var rule = new CalculationRuleDraft(
            "delivery", "Доставка", "equipment", "variant_calculation", true, null,
            [],
            [new RuleActionDraft(
                "aggregate_money",
                SourceFieldCode: "delivery_price",
                AggregationOperation: "add",
                AggregationTarget: "variant_total",
                MultiplyByQuantity: true,
                QuantityFieldCode: "quantity")]);

        var result = QuoteConfiguredCalculationEngine.Calculate(
            Position(quantity: 2m, basePrice: 100m, values: values),
            "equipment", [rule], []);

        Assert.Equal(250m, result.LineTotal);
    }

    [Fact]
    public void BlockSaveRuleReturnsConfiguredMessage()
    {
        var values = new Dictionary<string, JsonElement>
        {
            ["approved"] = JsonSerializer.SerializeToElement(false),
        };
        var rule = new CalculationRuleDraft(
            "approval", "Проверка", "equipment", "card_saving", true, null,
            [new RuleConditionDraft("approved", "is_false")],
            [new RuleActionDraft("block_save", Message: "Нужно согласование.")]);

        var exception = Assert.Throws<IdentityException>(() =>
            QuoteConfiguredCalculationEngine.Calculate(
                Position(basePrice: 100m, values: values), "equipment", [rule], []));

        Assert.Equal("Нужно согласование.", exception.Message);
    }

    private static SaveQuotePositionRequest Position(
        decimal quantity = 1m,
        decimal? purchasePrice = null,
        decimal basePrice = 0m,
        decimal? manualPrice = null,
        decimal? markup = null,
        decimal? discount = null,
        IReadOnlyDictionary<string, JsonElement>? values = null) =>
        new(
            null, null, "Позиция", null, "шт", quantity, purchasePrice,
            basePrice, manualPrice, markup, discount, false, values);
}
