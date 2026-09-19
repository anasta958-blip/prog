import 'dart:math' as math;

import 'package:sklad_komforta_app/features/catalog/catalog_models.dart';
import 'package:sklad_komforta_app/features/onboarding/onboarding_models.dart';
import 'package:sklad_komforta_app/features/quotes/quote_models.dart';

/// Executes the safe calculation configuration downloaded from the tenant.
/// It mirrors the backend evaluator so the editor updates immediately while
/// the backend remains authoritative when the document is saved.
final class QuoteConfiguredCalculationEngine {
  const QuoteConfiguredCalculationEngine(this.configuration);

  final CatalogConfiguration configuration;

  void calculateDocument(QuoteDraft document) {
    for (final type in document.proposalTypes) {
      for (final variant in type.variants) {
        for (final category in variant.categories) {
          final configuredCategory = configuration.categories
              .where((item) => item.id == category.catalogCategoryId)
              .firstOrNull;
          for (final section in category.sections) {
            for (final position in section.positions) {
              _calculatePosition(configuredCategory?.clientId, position);
            }
          }
        }
      }
    }
  }

  String? validateForSave(QuoteDraft document) {
    for (final type in document.proposalTypes) {
      for (final variant in type.variants) {
        for (final category in variant.categories) {
          final categoryClientId = configuration.categories
              .where((item) => item.id == category.catalogCategoryId)
              .firstOrNull
              ?.clientId;
          if (categoryClientId == null) continue;
          for (final position in category.sections.expand(
            (item) => item.positions,
          )) {
            final values = _valuesOf(position);
            for (final rule in _rulesFor(categoryClientId)) {
              if (!_matchesAll(values, rule.conditions)) continue;
              for (final action in rule.actions) {
                if (action.actionType == 'block_save') {
                  final message = action.message?.trim() ?? '';
                  return message.isEmpty
                      ? 'Сохранение запрещено настроенным правилом.'
                      : message;
                }
              }
            }
          }
        }
      }
    }
    return null;
  }

  /// Проверяет условия правила по текущим значениям строки. Метод используется
  /// контроллером только для действий, которым требуется доступ к API каталога.
  bool matchesRule(QuotePositionDraft position, CalculationRuleDraft rule) =>
      _matchesAll(_valuesOf(position), rule.conditions);

  void _calculatePosition(
    String? categoryClientId,
    QuotePositionDraft position,
  ) {
    position.configuredLineTotal = null;
    position.hiddenFieldCodes.clear();
    if (categoryClientId == null) return;
    final values = _valuesOf(position);
    final rules = _rulesFor(categoryClientId).toList(growable: false);
    var formulaDefinesLineTotal = false;
    for (final rule in rules) {
      if (!_matchesAll(values, rule.conditions)) continue;
      for (final action in rule.actions) {
        switch (action.actionType) {
          case 'exclude_row':
            position.excludeFromTotals = true;
            values['excluded_from_calc'] = true;
            break;
          case 'set_field':
            final sourceCode = action.sourceFieldCode;
            values[action.targetFieldCode!] = sourceCode != null
                ? values[sourceCode]
                : _parseConstant(action.constantValue);
            break;
          case 'calculate_field':
            final formula = action.formula;
            if (formula != null) {
              values[action.targetFieldCode!] = _formula(formula, values);
              formulaDefinesLineTotal =
                  action.targetFieldCode == 'line_total' ||
                  formulaDefinesLineTotal;
            }
            break;
          case 'set_field_visibility':
            final fieldCode = action.targetFieldCode;
            if (fieldCode != null) {
              if (action.booleanValue == false) {
                position.hiddenFieldCodes.add(fieldCode);
              } else {
                position.hiddenFieldCodes.remove(fieldCode);
              }
            }
            break;
        }
      }
    }

    final pipelines = configuration.moneyPipelines
        .where((item) => item.categoryClientId == categoryClientId)
        .toList(growable: false);
    double? total = pipelines.isEmpty ? null : 0;
    for (final pipeline in pipelines) {
      final source =
          _number(values[pipeline.manualPriceFieldCode]) ??
          _requiredNumber(values, pipeline.basePriceFieldCode);
      final markup = _number(values[pipeline.markupFieldCode]) ?? 0;
      final discount = _number(values[pipeline.discountFieldCode]) ?? 0;
      final quantity = _number(values[pipeline.quantityFieldCode]) ?? 1;
      final price = source * (1 + markup / 100) * (1 - discount / 100);
      final lineTotal = _round(price * quantity, pipeline.decimalPlaces);
      values[pipeline.resultFieldCode] = lineTotal;
      if (pipeline.includeResultInTotals) total = (total ?? 0) + lineTotal;
    }
    if (total == null &&
        formulaDefinesLineTotal &&
        values['line_total'] is num) {
      total = _number(values['line_total']);
    }

    for (final rule in rules) {
      if (!_matchesAll(values, rule.conditions)) continue;
      for (final action in rule.actions) {
        if (action.actionType != 'aggregate_money') continue;
        var amount = _number(values[action.sourceFieldCode]) ?? 0;
        if (action.multiplyByQuantity) {
          amount *= _number(values[action.quantityFieldCode]) ?? 1;
        }
        total ??= position.legacyLineTotal;
        total += action.aggregationOperation == 'subtract' ? -amount : amount;
      }
    }

    position
      ..quantity = _number(values['quantity']) ?? position.quantity
      ..purchasePrice =
          _number(values['purchase_price']) ?? position.purchasePrice
      ..manualPrice = _effectiveManualPrice(values, position)
      ..markupPercent =
          _number(values['markup_value']) ?? position.markupPercent
      ..discountPercent =
          _number(values['discount_value']) ?? position.discountPercent
      ..excludeFromTotals = values['excluded_from_calc'] is bool
          ? values['excluded_from_calc'] as bool
          : position.excludeFromTotals
      ..configuredLineTotal = total == null ? null : _round(total, 2);
    if ((position.configuredLineTotal ?? 0) < 0) {
      throw const FormatException(
        'Итоговая стоимость позиции не может быть отрицательной.',
      );
    }
    position.values
      ..clear()
      ..addAll(values);
  }

  Iterable<CalculationRuleDraft> _rulesFor(String categoryClientId) =>
      configuration.rules.where(
        (rule) =>
            rule.isEnabled &&
            rule.categoryClientId == categoryClientId &&
            const {
              'field_changed',
              'row_calculation',
              'card_saving',
              'variant_calculation',
            }.contains(rule.eventType),
      );

  Map<String, dynamic> _valuesOf(QuotePositionDraft position) =>
      Map<String, dynamic>.from(position.values)
        ..['quantity'] = position.quantity
        ..['purchase_price'] = position.purchasePrice
        ..['base_price'] = position.manualPrice ?? position.basePrice
        ..['markup_value'] = position.markupPercent
        ..['discount_value'] = position.discountPercent
        ..['excluded_from_calc'] = position.excludeFromTotals;

  static double? _effectiveManualPrice(
    Map<String, dynamic> values,
    QuotePositionDraft position,
  ) {
    final effective = _number(values['base_price']);
    if (effective == null) return position.manualPrice;
    return position.manualPrice != null || effective != position.basePrice
        ? effective
        : null;
  }

  static bool _matchesAll(
    Map<String, dynamic> values,
    List<RuleConditionDraft> conditions,
  ) => conditions.every((condition) {
    final value = values[condition.fieldCode];
    return switch (condition.operator) {
      'is_true' => value == true,
      'is_false' => value == false,
      'greater_than_zero' => (_number(value) ?? 0) > 0,
      'is_filled' =>
        value != null &&
            (value is! String || value.trim().isNotEmpty) &&
            (value is! Iterable || value.isNotEmpty),
      'equals' =>
        (value?.toString() ?? '').trim().toLowerCase() ==
            (condition.comparisonValue ?? '').trim().toLowerCase(),
      _ => false,
    };
  });

  static dynamic _parseConstant(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.toLowerCase() == 'true') return true;
    if (normalized.toLowerCase() == 'false') return false;
    return double.tryParse(normalized.replaceAll(',', '.')) ?? normalized;
  }

  static double _formula(FormulaDraft formula, Map<String, dynamic> values) {
    final output = <FormulaTokenDraft>[];
    final operators = <FormulaTokenDraft>[];
    const priorities = {'add': 1, 'subtract': 1, 'multiply': 2, 'divide': 2};
    for (final token in formula.tokens) {
      if (token.tokenType == 'field' || token.tokenType == 'constant') {
        output.add(token);
      } else if (token.tokenType == 'open_group') {
        operators.add(token);
      } else if (token.tokenType == 'close_group') {
        while (operators.isNotEmpty &&
            operators.last.tokenType != 'open_group') {
          output.add(operators.removeLast());
        }
        if (operators.isNotEmpty) operators.removeLast();
      } else if (token.tokenType == 'operator') {
        while (operators.isNotEmpty &&
            operators.last.tokenType == 'operator' &&
            priorities[operators.last.operator]! >=
                priorities[token.operator]!) {
          output.add(operators.removeLast());
        }
        operators.add(token);
      }
    }
    while (operators.isNotEmpty) {
      output.add(operators.removeLast());
    }

    final stack = <double>[];
    for (final token in output) {
      if (token.tokenType == 'field') {
        stack.add(_requiredNumber(values, token.fieldCode!));
      } else if (token.tokenType == 'constant') {
        stack.add(token.constantValue!.toDouble());
      } else {
        final right = stack.removeLast();
        final left = stack.removeLast();
        stack.add(switch (token.operator) {
          'add' => left + right,
          'subtract' => left - right,
          'multiply' => left * right,
          'divide' => left / right,
          _ => throw const FormatException('Неизвестная операция формулы.'),
        });
      }
    }
    return _round(stack.single, formula.decimalPlaces);
  }

  static double _requiredNumber(Map<String, dynamic> values, String code) =>
      _number(values[code]) ??
      (throw FormatException('Для расчёта не заполнено поле «$code».'));

  static double? _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value?.toString() ?? '').replaceAll(',', '.'));
  }

  static double _round(double value, int places) {
    final factor = math.pow(10, places).toDouble();
    return (value * factor).round() / factor;
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
