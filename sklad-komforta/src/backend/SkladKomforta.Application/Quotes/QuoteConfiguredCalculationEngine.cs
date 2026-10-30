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
        IReadOnlySet<string>? percentFields = null,
        IReadOnlySet<string>? totalFields = null)
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
        var effectRules = rules.Where(rule => rule.IsEnabled && rule.CategoryClientId == categoryClientId &&
            rule.EventType is "field_changed" or "row_calculation" or "card_saving" or "variant_calculation" &&
            rule.Actions.Any(action => action.ActionType is "exclude_row" or "block_save")).ToArray();
        var activeEffects = values.TryGetValue("_active_effect_rules", out var storedEffects) &&
            storedEffects.ValueKind == JsonValueKind.Array
            ? storedEffects.EnumerateArray().Where(item => item.ValueKind == JsonValueKind.String)
                .Select(item => item.GetString()!).ToHashSet(StringComparer.Ordinal)
            : new HashSet<string>(StringComparer.Ordinal);
        activeEffects.RemoveWhere(id => !effectRules.Any(rule => rule.ClientId == id));
        foreach (var rule in effectRules.Where(rule => rule.EventType != "field_changed"))
        {
            if (rule.Conditions.All(condition => Matches(values, condition))) activeEffects.Add(rule.ClientId);
            else activeEffects.Remove(rule.ClientId);
        }
        if (effectRules.Any(rule => rule.Actions.Any(action => action.ActionType == "exclude_row")) ||
            BooleanValue(values, "_conditional_exclusion") == true)
        {
            if (!values.ContainsKey("_manual_excluded_from_calc"))
                values["_manual_excluded_from_calc"] = JsonSerializer.SerializeToElement(
                    BooleanValue(values, "_conditional_exclusion") != true && position.ExcludeFromTotals);
            exclude = BooleanValue(values, "_manual_excluded_from_calc") == true ||
                effectRules.Any(rule => activeEffects.Contains(rule.ClientId) &&
                    rule.Actions.Any(action => action.ActionType == "exclude_row"));
            values["excluded_from_calc"] = JsonSerializer.SerializeToElement(exclude);
            values["_conditional_exclusion"] = JsonSerializer.SerializeToElement(true);
            values.Remove("_unconditional_excluded_from_calc");
        }
        values["_active_effect_rules"] = JsonSerializer.SerializeToElement(activeEffects);
        foreach (var rule in effectRules.Where(rule => activeEffects.Contains(rule.ClientId)))
            foreach (var action in rule.Actions.Where(action => action.ActionType == "block_save"))
                throw new IdentityException(422, "quote_rule_blocked_save",
                    string.IsNullOrWhiteSpace(action.Message) ? "Сохранение запрещено настроенным правилом." : action.Message.Trim());
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

        foreach (var rule in matchedRules.Where(_ => totalFields is null))
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

        if (!categoryPipelines.Any(pipeline => pipeline.ResultFieldCode == "line_total") && !formulaDefinesLineTotal)
            values["line_total"] = JsonSerializer.SerializeToElement(QuoteCalculationEngine.Calculate(
                position with { Quantity = quantity, ManualPrice = manualPrice, MarkupPercent = markup, DiscountPercent = discount }).LineTotal);
        if (totalFields is not null)
            lineTotal = totalFields.Sum(code => DecimalValue(values, code) ?? 0m);
        lineTotal = decimal.Round(lineTotal, 2, MidpointRounding.AwayFromZero);
        if (lineTotal < 0)
            throw new IdentityException(422, "quote_price_invalid", "Итоговая стоимость позиции не может быть отрицательной.");
        if (totalFields is null && !categoryPipelines.Any(pipeline => pipeline.ResultFieldCode == "line_total") &&
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
        values["name"] = JsonSerializer.SerializeToElement(position.Name);
        values["marking"] = JsonSerializer.SerializeToElement(position.Marking ?? string.Empty);
        values["unit"] = JsonSerializer.SerializeToElement(position.Unit ?? string.Empty);
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
        var comparison = condition.ComparisonFieldCode is not null
            ? values.GetValueOrDefault(condition.ComparisonFieldCode)
            : JsonSerializer.SerializeToElement(condition.ComparisonValue?.Trim());
        var leftIsNumber = TryDecimal(value, out var left);
        var rightIsNumber = TryDecimal(comparison, out var right);
        var numericComparison = leftIsNumber && rightIsNumber;
        return condition.Operator switch
        {
            "is_true" => value.ValueKind == JsonValueKind.True,
            "is_false" => value.ValueKind == JsonValueKind.False,
            "greater_than_zero" => TryDecimal(value, out var number) && number > 0,
            "is_filled" => IsFilled(value),
            "less_than" => numericComparison && left < right,
            "greater_than" => numericComparison && left > right,
            "equals" => condition.ComparisonFieldCode is not null &&
                (value.ValueKind is JsonValueKind.Undefined or JsonValueKind.Null ||
                 comparison.ValueKind is JsonValueKind.Undefined or JsonValueKind.Null) ? false :
                numericComparison ? left == right : StringValue(value).Trim().Equals(
                    StringValue(comparison).Trim(), StringComparison.OrdinalIgnoreCase),
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
