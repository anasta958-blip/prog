using System.Globalization;
using System.Text.Json;
using SkladKomforta.Application.Identity;
using SkladKomforta.Application.Onboarding;

namespace SkladKomforta.Application.Quotes;

/// <summary>
/// Applies tenant-defined row rules and money pipelines to a quote position.
/// The engine is deterministic and does not execute tenant-provided source code.
/// </summary>
public static class QuoteConfiguredCalculationEngine
{
    public static QuoteConfiguredCalculationResult Calculate(
        SaveQuotePositionRequest position,
        string categoryClientId,
        IReadOnlyList<CalculationRuleDraft> rules,
        IReadOnlyList<MoneyPipelineDraft> pipelines,
        IReadOnlySet<string>? percentFields = null)
    {
        var values = new Dictionary<string, JsonElement>(
            position.Values ?? new Dictionary<string, JsonElement>(),
            StringComparer.Ordinal);
        SetSystemValues(values, position);
        foreach (var code in percentFields ?? new HashSet<string>())
        {
            if (!values.TryGetValue(code, out var value) ||
                value.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined ||
                (value.ValueKind == JsonValueKind.String && string.IsNullOrWhiteSpace(value.GetString())))
            {
                values[code] = JsonSerializer.SerializeToElement(0m);
            }
        }

        var exclude = position.ExcludeFromTotals;
        var conditionalExclusions = rules.Where(rule => rule.IsEnabled &&
            rule.CategoryClientId == categoryClientId && rule.Conditions.Count > 0 &&
            rule.Actions.Any(action => action.ActionType == "exclude_row")).ToArray();
        if (conditionalExclusions.Length > 0 || BooleanValue(values, "_conditional_exclusion") == true)
        {
            exclude = BooleanValue(values, "_manual_excluded_from_calc") == true ||
                BooleanValue(values, "_unconditional_excluded_from_calc") == true ||
                conditionalExclusions.Any(rule => rule.Conditions.All(condition => Matches(values, condition)));
            values["excluded_from_calc"] = JsonSerializer.SerializeToElement(exclude);
            values["_conditional_exclusion"] = JsonSerializer.SerializeToElement(true);
        }
        var formulaDefinesLineTotal = false;
        var calculations = new List<(string Target, HashSet<string> Inputs, Action Run)>();
        var systemInputs = new Dictionary<string, JsonElement>(values, StringComparer.Ordinal);
        var matchedRules = rules.Where(rule =>
            rule.IsEnabled &&
            rule.CategoryClientId == categoryClientId &&
            // Field-change actions have already produced the submitted values.
            // Saving is not another change event for every field in the document.
            rule.EventType is "row_calculation" or "card_saving" or "variant_calculation");
        foreach (var rule in matchedRules)
        {
            if (!rule.Conditions.All(condition => Matches(values, condition))) continue;
            foreach (var action in rule.Actions)
            {
                switch (action.ActionType)
                {
                    case "exclude_row":
                        if (rule.Conditions.Count == 0)
                            values["_unconditional_excluded_from_calc"] = JsonSerializer.SerializeToElement(true);
                        exclude = true;
                        values["excluded_from_calc"] = JsonSerializer.SerializeToElement(true);
                        break;
                    case "set_field":
                        calculations.Add((action.TargetFieldCode!,
                            action.SourceFieldCode is not null && action.SourceFieldCode != action.TargetFieldCode
                                ? new HashSet<string> { action.SourceFieldCode } : new HashSet<string>(), () => {
                            ApplySetField(values, action);
                            if (values.TryGetValue(action.TargetFieldCode!, out var copied))
                                systemInputs[action.TargetFieldCode!] = copied;
                        }));
                        break;
                    case "calculate_field" when action.Formula is not null:
                        calculations.Add((action.TargetFieldCode!, action.Formula.Tokens
                            .Where(token => token.TokenType == "field").Select(token => token.FieldCode!).ToHashSet(StringComparer.Ordinal), () => {
                        values[action.TargetFieldCode!] = JsonSerializer.SerializeToElement(
                            RuleCalculationEngine.CalculateFormula(action.Formula, NumericValues(values), percentFields));
                        systemInputs[action.TargetFieldCode!] = values[action.TargetFieldCode!];
                        formulaDefinesLineTotal |= action.TargetFieldCode == "line_total";
                        }));
                        break;
                    case "block_save":
                        throw new IdentityException(
                            422,
                            "quote_rule_blocked_save",
                            string.IsNullOrWhiteSpace(action.Message)
                                ? "Сохранение запрещено настроенным правилом."
                                : action.Message.Trim());
                }
            }
        }

        foreach (var entry in values) systemInputs[entry.Key] = entry.Value;
        var categoryPipelines = pipelines
            .Where(pipeline => pipeline.CategoryClientId == categoryClientId)
            .ToArray();
        decimal? configuredTotal = categoryPipelines.Length > 0 ? 0m : null;
        foreach (var pipeline in categoryPipelines)
        {
            var inputs = new[] { pipeline.BasePriceFieldCode, pipeline.ManualPriceFieldCode,
                pipeline.MarkupFieldCode, pipeline.DiscountFieldCode, pipeline.QuantityFieldCode }
                .Where(code => !string.IsNullOrWhiteSpace(code) && code != pipeline.ResultFieldCode)
                .Select(code => code!).ToHashSet(StringComparer.Ordinal);
            calculations.Add((pipeline.ResultFieldCode, inputs, () => {
            var result = RuleCalculationEngine.CalculateMoneyPipeline(pipeline, NumericValues(values));
            values[pipeline.ResultFieldCode] = JsonSerializer.SerializeToElement(result.LineTotal);
            if (pipeline.IncludeResultInTotals)
                configuredTotal = (configuredTotal ?? 0m) + result.LineTotal;
            }));
        }
        while (calculations.Count > 0)
        {
            var index = calculations.FindIndex(job => !calculations.Any(writer => job.Inputs.Contains(writer.Target)));
            if (index < 0)
                throw new IdentityException(422, "calculation_dependency_cycle",
                    "Циклическая зависимость между формулами и конвейерами. Проверьте исходные поля и поля результата.");
            var job = calculations[index];
            calculations.RemoveAt(index);
            job.Run();
        }

        if (configuredTotal is null && formulaDefinesLineTotal &&
            values.TryGetValue("line_total", out var formulaTotal) &&
            TryDecimal(formulaTotal, out var calculatedByRule))
            configuredTotal = calculatedByRule;

        var quantity = DecimalValue(systemInputs, "quantity") ?? position.Quantity;
        var purchasePrice = DecimalValue(systemInputs, "purchase_price") ?? position.PurchasePrice;
        var effectivePrice = DecimalValue(systemInputs, "base_price") ?? position.ManualPrice ?? position.BasePrice;
        decimal? manualPrice = position.ManualPrice.HasValue || effectivePrice != position.BasePrice
            ? effectivePrice
            : null;
        var markup = DecimalValue(systemInputs, "markup_value") ?? position.MarkupPercent;
        var discount = DecimalValue(systemInputs, "discount_value") ?? position.DiscountPercent;
        exclude = BooleanValue(values, "excluded_from_calc") ?? exclude;

        var lineTotal = configuredTotal ?? QuoteCalculationEngine.Calculate(
            position with
            {
                Quantity = quantity,
                PurchasePrice = purchasePrice,
                ManualPrice = manualPrice,
                MarkupPercent = markup,
                DiscountPercent = discount,
                ExcludeFromTotals = exclude,
            }).LineTotal;

        foreach (var rule in matchedRules)
        {
            if (!rule.Conditions.All(condition => Matches(values, condition))) continue;
            foreach (var action in rule.Actions.Where(item => item.ActionType == "aggregate_money"))
            {
                var amount = DecimalValue(values, action.SourceFieldCode) ?? 0m;
                if (action.MultiplyByQuantity)
                    amount *= DecimalValue(values, action.QuantityFieldCode) ?? 1m;
                lineTotal += action.AggregationOperation == "subtract" ? -amount : amount;
            }
        }

        lineTotal = decimal.Round(lineTotal, 2, MidpointRounding.AwayFromZero);
        if (lineTotal < 0)
            throw new IdentityException(422, "quote_price_invalid", "Итоговая стоимость позиции не может быть отрицательной.");
        if (!categoryPipelines.Any(pipeline => pipeline.ResultFieldCode == "line_total") &&
            !formulaDefinesLineTotal)
            values["line_total"] = JsonSerializer.SerializeToElement(lineTotal);
        return new QuoteConfiguredCalculationResult(
            quantity, purchasePrice, position.BasePrice, manualPrice, markup, discount,
            lineTotal, exclude, values);
    }

    private static void SetSystemValues(
        Dictionary<string, JsonElement> values,
        SaveQuotePositionRequest position)
    {
        values["quantity"] = JsonSerializer.SerializeToElement(position.Quantity);
        values["base_price"] = JsonSerializer.SerializeToElement(position.ManualPrice ?? position.BasePrice);
        SetNullable(values, "purchase_price", position.PurchasePrice);
        SetNullable(values, "markup_value", position.MarkupPercent);
        SetNullable(values, "discount_value", position.DiscountPercent);
        values["excluded_from_calc"] = JsonSerializer.SerializeToElement(position.ExcludeFromTotals);
    }

    private static void SetNullable(
        Dictionary<string, JsonElement> values,
        string code,
        decimal? value)
    {
        if (value.HasValue) values[code] = JsonSerializer.SerializeToElement(value.Value);
        else values.Remove(code);
    }

    private static void ApplySetField(
        Dictionary<string, JsonElement> values,
        RuleActionDraft action)
    {
        if (!string.IsNullOrWhiteSpace(action.SourceFieldCode) &&
            values.TryGetValue(action.SourceFieldCode, out var source))
        {
            values[action.TargetFieldCode!] = source.Clone();
            return;
        }
        values[action.TargetFieldCode!] = ParseConstant(action.ConstantValue);
    }

    private static JsonElement ParseConstant(string? value)
    {
        var normalized = value?.Trim() ?? string.Empty;
        if (bool.TryParse(normalized, out var boolean))
            return JsonSerializer.SerializeToElement(boolean);
        if (decimal.TryParse(normalized.Replace(',', '.'), NumberStyles.Number,
                CultureInfo.InvariantCulture, out var number))
            return JsonSerializer.SerializeToElement(number);
        return JsonSerializer.SerializeToElement(normalized);
    }

    private static bool Matches(
        Dictionary<string, JsonElement> values,
        RuleConditionDraft condition)
    {
        values.TryGetValue(condition.FieldCode, out var value);
        return condition.Operator switch
        {
            "is_true" => value.ValueKind == JsonValueKind.True,
            "is_false" => value.ValueKind == JsonValueKind.False,
            "greater_than_zero" => TryDecimal(value, out var number) && number > 0,
            "is_filled" => IsFilled(value),
            "equals" => StringValue(value).Equals(
                condition.ComparisonValue?.Trim() ?? string.Empty,
                StringComparison.OrdinalIgnoreCase),
            _ => false,
        };
    }

    private static bool IsFilled(JsonElement value) => value.ValueKind switch
    {
        JsonValueKind.Undefined or JsonValueKind.Null => false,
        JsonValueKind.String => !string.IsNullOrWhiteSpace(value.GetString()),
        JsonValueKind.Array => value.GetArrayLength() > 0,
        _ => true,
    };

    private static Dictionary<string, decimal?> NumericValues(
        Dictionary<string, JsonElement> values) =>
        values.ToDictionary(
            pair => pair.Key,
            pair => TryDecimal(pair.Value, out var number) ? (decimal?)number : null,
            StringComparer.Ordinal);

    private static decimal? DecimalValue(
        Dictionary<string, JsonElement> values,
        string? code) =>
        !string.IsNullOrWhiteSpace(code) && values.TryGetValue(code, out var value) &&
        TryDecimal(value, out var number)
            ? number
            : null;

    private static bool? BooleanValue(
        Dictionary<string, JsonElement> values,
        string code) =>
        values.TryGetValue(code, out var value)
            ? value.ValueKind switch
            {
                JsonValueKind.True => true,
                JsonValueKind.False => false,
                _ => null,
            }
            : null;

    private static bool TryDecimal(JsonElement value, out decimal number)
    {
        if (value.ValueKind == JsonValueKind.Number && value.TryGetDecimal(out number)) return true;
        if (value.ValueKind == JsonValueKind.String &&
            decimal.TryParse((value.GetString() ?? string.Empty).Replace(',', '.'),
                NumberStyles.Number, CultureInfo.InvariantCulture, out number)) return true;
        number = 0;
        return false;
    }

    private static string StringValue(JsonElement value) => value.ValueKind switch
    {
        JsonValueKind.String => value.GetString() ?? string.Empty,
        JsonValueKind.True => "true",
        JsonValueKind.False => "false",
        JsonValueKind.Number => value.GetRawText(),
        _ => string.Empty,
    };
}

public sealed record QuoteConfiguredCalculationResult(
    decimal Quantity,
    decimal? PurchasePrice,
    decimal BasePrice,
    decimal? ManualPrice,
    decimal? MarkupPercent,
    decimal? DiscountPercent,
    decimal LineTotal,
    bool ExcludeFromTotals,
    IReadOnlyDictionary<string, JsonElement> Values);
