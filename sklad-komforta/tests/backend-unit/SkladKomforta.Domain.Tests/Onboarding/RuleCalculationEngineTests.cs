using SkladKomforta.Application.Onboarding;

namespace SkladKomforta.Domain.Tests.Onboarding;

public sealed class RuleCalculationEngineTests
{
    [Fact]
    public void MoneyPipelineUsesFixedOperationOrder()
    {
        var pipeline = new MoneyPipelineDraft(
            "equipment",
            "base_price",
            "manual_price",
            "markup",
            "discount",
            "quantity",
            "line_total",
            2,
            true);
        var values = new Dictionary<string, decimal?>
        {
            ["base_price"] = 100m,
            ["manual_price"] = 120m,
            ["markup"] = 10m,
            ["discount"] = 5m,
            ["quantity"] = 2m,
        };

        var result = RuleCalculationEngine.CalculateMoneyPipeline(pipeline, values);

        Assert.Equal(125.40m, result.UnitPrice);
        Assert.Equal(250.80m, result.LineTotal);
    }

    [Fact]
    public void FormulaUsesFieldsConstantsParenthesesAndOperatorPriority()
    {
        var formula = new FormulaDraft(
        [
            new FormulaTokenDraft("field", FieldCode: "price"),
            new FormulaTokenDraft("operator", Operator: "multiply"),
            new FormulaTokenDraft("open_group"),
            new FormulaTokenDraft("constant", ConstantValue: 1m),
            new FormulaTokenDraft("operator", Operator: "subtract"),
            new FormulaTokenDraft("field", FieldCode: "discount"),
            new FormulaTokenDraft("operator", Operator: "divide"),
            new FormulaTokenDraft("constant", ConstantValue: 100m),
            new FormulaTokenDraft("close_group"),
            new FormulaTokenDraft("operator", Operator: "multiply"),
            new FormulaTokenDraft("field", FieldCode: "quantity"),
        ], 2);

        var result = RuleCalculationEngine.CalculateFormula(
            formula,
            new Dictionary<string, decimal?>
            {
                ["price"] = 100m,
                ["discount"] = 10m,
                ["quantity"] = 2m,
            });

        Assert.Equal(180m, result);
    }
}
