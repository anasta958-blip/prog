using SkladKomforta.Application.Identity;

namespace SkladKomforta.Application.Onboarding;

/// <summary>Результат фиксированного денежного конвейера одной строки.</summary>
public sealed record MoneyPipelineResult(decimal UnitPrice, decimal LineTotal);

/// <summary>
/// Выполняет только заранее разрешённые арифметические операции. Движок не
/// компилирует и не запускает пользовательский JavaScript, Dart или C#.
/// </summary>
public static class RuleCalculationEngine
{
    private static readonly Dictionary<string, int> Priorities =
        new Dictionary<string, int>(StringComparer.Ordinal)
        {
            ["add"] = 1,
            ["subtract"] = 1,
            ["multiply"] = 2,
            ["divide"] = 2,
        };

    /// <summary>
    /// Выполняет неизменяемый порядок: базовая или ручная цена, наценка,
    /// скидка, количество, округление.
    /// </summary>
    public static MoneyPipelineResult CalculateMoneyPipeline(
        MoneyPipelineDraft pipeline,
        IReadOnlyDictionary<string, decimal?> values)
    {
        var basePrice = ValueOf(values, pipeline.BasePriceFieldCode);
        var price = OptionalValueOf(values, pipeline.ManualPriceFieldCode) ?? basePrice;
        var markup = OptionalValueOf(values, pipeline.MarkupFieldCode) ?? 0m;
        var discount = OptionalValueOf(values, pipeline.DiscountFieldCode) ?? 0m;
        var quantity = OptionalValueOf(values, pipeline.QuantityFieldCode) ?? 1m;

        price *= 1m + markup / 100m;
        price *= 1m - discount / 100m;
        var roundedUnitPrice = decimal.Round(price, pipeline.DecimalPlaces, MidpointRounding.AwayFromZero);
        var total = decimal.Round(price * quantity, pipeline.DecimalPlaces, MidpointRounding.AwayFromZero);
        return new MoneyPipelineResult(roundedUnitPrice, total);
    }

    /// <summary>Вычисляет структурированную формулу с обычным приоритетом операций и скобками.</summary>
    public static decimal CalculateFormula(
        FormulaDraft formula,
        IReadOnlyDictionary<string, decimal?> values,
        IReadOnlySet<string>? percentFields = null)
    {
        var output = new List<FormulaTokenDraft>();
        var operators = new Stack<FormulaTokenDraft>();
        foreach (var token in formula.Tokens)
        {
            if (token.TokenType is "field" or "constant")
            {
                output.Add(token);
                continue;
            }

            if (token.TokenType == "open_group")
            {
                operators.Push(token);
                continue;
            }

            if (token.TokenType == "close_group")
            {
                while (operators.Count > 0 && operators.Peek().TokenType != "open_group")
                    output.Add(operators.Pop());
                if (operators.Count == 0) InvalidFormula("В формуле отсутствует открывающая скобка.");
                operators.Pop();
                continue;
            }

            if (token.TokenType != "operator" || token.Operator is null || !Priorities.ContainsKey(token.Operator))
                InvalidFormula("Формула содержит неизвестную операцию.");
            while (operators.Count > 0 && operators.Peek().TokenType == "operator" &&
                   Priorities[operators.Peek().Operator!] >= Priorities[token.Operator])
                output.Add(operators.Pop());
            operators.Push(token);
        }

        while (operators.Count > 0)
        {
            if (operators.Peek().TokenType == "open_group")
                InvalidFormula("В формуле отсутствует закрывающая скобка.");
            output.Add(operators.Pop());
        }

        var stack = new Stack<decimal>();
        foreach (var token in output)
        {
            if (token.TokenType == "field")
            {
                var value = ValueOf(values, token.FieldCode);
                stack.Push(percentFields?.Contains(token.FieldCode!) == true ? value / 100m : value);
                continue;
            }
            if (token.TokenType == "constant" && token.ConstantValue is not null)
            {
                stack.Push(token.ConstantValue.Value);
                continue;
            }
            if (stack.Count < 2) InvalidFormula("Формула содержит недостаточно операндов.");
            var right = stack.Pop();
            var left = stack.Pop();
            stack.Push(token.Operator switch
            {
                "add" => left + right,
                "subtract" => left - right,
                "multiply" => left * right,
                "divide" when right != 0m => left / right,
                "divide" => throw new IdentityException(422, "formula_division_by_zero", "В формуле произошло деление на ноль."),
                _ => throw new IdentityException(400, "formula_invalid", "Формула содержит неизвестную операцию."),
            });
        }

        if (stack.Count != 1) InvalidFormula("Формула содержит лишние операнды.");
        return decimal.Round(stack.Pop(), formula.DecimalPlaces, MidpointRounding.AwayFromZero);
    }

    private static decimal ValueOf(IReadOnlyDictionary<string, decimal?> values, string? fieldCode)
    {
        if (string.IsNullOrWhiteSpace(fieldCode) || !values.TryGetValue(fieldCode, out var value) || value is null)
            throw new IdentityException(422, "calculation_value_missing", $"Для расчёта не заполнено поле «{fieldCode}».");
        return value.Value;
    }

    private static decimal? OptionalValueOf(
        IReadOnlyDictionary<string, decimal?> values,
        string? fieldCode) =>
        string.IsNullOrWhiteSpace(fieldCode) || !values.TryGetValue(fieldCode, out var value)
            ? null
            : value;

    [System.Diagnostics.CodeAnalysis.DoesNotReturn]
    private static void InvalidFormula(string message) =>
        throw new IdentityException(400, "formula_invalid", message);
}
