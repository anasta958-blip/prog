import 'dart:math' as math;

import 'package:sklad_komforta_app/features/catalog/catalog_models.dart';
import 'package:sklad_komforta_app/features/onboarding/onboarding_models.dart';
import 'package:sklad_komforta_app/features/quotes/quote_models.dart';

/// Missing inputs are expected while a document row is being filled in.
final class MissingCalculationValueException extends FormatException {
  const MissingCalculationValueException(super.message);
}

/// Executes the safe calculation configuration downloaded from the tenant.
/// It mirrors the backend evaluator so the editor updates immediately while
/// the backend remains authoritative when the document is saved.
final class QuoteConfiguredCalculationEngine {
  const QuoteConfiguredCalculationEngine(this.configuration);

  final CatalogConfiguration configuration;

  void calculateDocument(
    QuoteDraft document, {
    QuotePositionDraft? changedPosition,
    String? changedFieldCode,
    bool saving = false,
    QuoteVariantDraft? consumedVariant,
    void Function(QuoteVariantDraft variant, double total)?
    onVariantTotalChanged,
  }) {
    for (final type in document.proposalTypes) {
      for (final variant in type.variants) {
        final previousTotal = variant.lastRuleTotal;
        for (final category in variant.categories) {
          final configuredCategory = configuration.categories
              .where((item) => item.id == category.catalogCategoryId)
              .firstOrNull;
          for (final section in category.sections) {
            for (final position in section.positions) {
              try {
                _calculatePosition(
                  configuredCategory?.clientId,
                  position,
                  changedFieldCode: identical(position, changedPosition)
                      ? changedFieldCode
                      : null,
                  saving: saving,
                );
              } on FormatException catch (error) {
                var message = error.message;
                for (final field
                    in configuredCategory?.fields ?? <CatalogField>[]) {
                  message = message.replaceAll(
                    '«${field.code}»',
                    '«${field.label}»',
                  );
                }
                final details = 'Позиция «${position.name}»: $message';
                if (error is MissingCalculationValueException) {
                  throw MissingCalculationValueException(details);
                }
                throw FormatException(details);
              }
            }
          }
        }
        final total = variant.totalWithVat;
        if (previousTotal != null &&
            total != previousTotal &&
            !identical(variant, consumedVariant)) {
          for (final category in variant.categories) {
            final clientId = configuration.categories
                .where((item) => item.id == category.catalogCategoryId)
                .firstOrNull
                ?.clientId;
            if (clientId == null ||
                !_rulesFor(
                  clientId,
                ).any((rule) => rule.eventType == 'variant_calculation')) {
              continue;
            }
            for (final position in category.sections.expand(
              (item) => item.positions,
            )) {
              final before = _valuesOf(position);
              _calculatePosition(
                clientId,
                position,
                variantTotal: total,
                variantEvent: true,
              );
              // Recalculate dependent row formulas after an event changes their inputs.
              // Do not re-run row actions for purely visual variant events.
              final after = _valuesOf(position);
              if (after.entries.any(
                (entry) =>
                    !entry.key.startsWith('_') &&
                    before[entry.key] != entry.value,
              )) {
                _calculatePosition(clientId, position);
              }
            }
          }
          // Consume changes produced by the event itself; never recursively fire it.
          variant.lastRuleTotal = variant.totalWithVat;
          onVariantTotalChanged?.call(variant, total);
        } else {
          variant.lastRuleTotal = total;
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
              if (rule.eventType == 'field_changed' ||
                  rule.eventType == 'variant_calculation') {
                if (!_effectRuleIds(values).contains(rule.clientId)) continue;
              } else if (!_matchesAll(values, rule.conditions)) {
                continue;
              }
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
  bool matchesRule(
    QuotePositionDraft position,
    CalculationRuleDraft rule, {
    double? variantTotal,
  }) => _matchesAll({
    ..._valuesOf(position),
    'variant_total': ?variantTotal,
  }, rule.conditions);

  void _calculatePosition(
    String? categoryClientId,
    QuotePositionDraft position, {
    String? changedFieldCode,
    bool saving = false,
    double? variantTotal,
    bool variantEvent = false,
  }) {
    position.configuredLineTotal = null;
    position.hiddenFieldCodes.clear();
    position.fieldHighlights.clear();
    if (categoryClientId == null) {
      position.activatedHighlightRuleIds.clear();
      return;
    }
    final categoryFields = configuration.categories
        .where((category) => category.clientId == categoryClientId)
        .expand((category) => category.fields)
        .toList();
    final fieldTotalsConfigured = categoryFields.any(
      (field) => field.totalMode != null,
    );
    final values = _valuesOf(position);
    if (variantTotal != null) values['variant_total'] = variantTotal;
    final percentFields = configuration.categories
        .where((category) => category.clientId == categoryClientId)
        .expand((category) => category.fields)
        .where((field) => field.fieldType == 'percent')
        .map((field) => field.code)
        .toSet();
    for (final code in percentFields) {
      final value = values[code];
      if (value == null || (value is String && value.trim().isEmpty)) {
        values[code] = 0.0;
      }
    }
    final rules = _rulesFor(categoryClientId)
        .where(
          (rule) => (variantEvent
              ? rule.eventType == 'variant_calculation'
              : rule.eventType == 'row_calculation' ||
                    (saving && rule.eventType == 'card_saving') ||
                    (rule.eventType == 'field_changed' &&
                        changedFieldCode != null &&
                        (rule.eventFieldCode == null ||
                            rule.eventFieldCode == changedFieldCode))),
        )
        .toList(growable: false);
    final effectRules = _rulesFor(categoryClientId)
        .where(
          (rule) => rule.actions.any(
            (action) =>
                action.actionType == 'exclude_row' ||
                action.actionType == 'block_save',
          ),
        )
        .toList();
    final activeEffects = _effectRuleIds(values);
    activeEffects.removeWhere(
      (id) => !effectRules.any((rule) => rule.clientId == id),
    );
    for (final rule in effectRules.where(rules.contains)) {
      if (_matchesAll(values, rule.conditions)) {
        activeEffects.add(rule.clientId);
      } else {
        activeEffects.remove(rule.clientId);
      }
    }
    if (effectRules.any(
          (rule) =>
              rule.actions.any((action) => action.actionType == 'exclude_row'),
        ) ||
        values['_conditional_exclusion'] == true) {
      values['_manual_excluded_from_calc'] ??=
          values['_conditional_exclusion'] == true
          ? false
          : position.excludeFromTotals;
      values['excluded_from_calc'] =
          values['_manual_excluded_from_calc'] == true ||
          effectRules.any(
            (rule) =>
                activeEffects.contains(rule.clientId) &&
                rule.actions.any(
                  (action) => action.actionType == 'exclude_row',
                ),
          );
      values['_conditional_exclusion'] = true;
      values.remove('_unconditional_excluded_from_calc');
    }
    values['_active_effect_rules'] = activeEffects.toList();
    var formulaDefinesLineTotal =
        (variantEvent && position.ruleDefinesLineTotal) ||
        (values['_event_line_total'] == true &&
            _rulesFor(categoryClientId).any(
              (rule) =>
                  const {
                    'field_changed',
                    'variant_calculation',
                  }.contains(rule.eventType) &&
                  rule.actions.any(
                    (action) =>
                        action.targetFieldCode == 'line_total' &&
                        const {
                          'set_field',
                          'calculate_field',
                        }.contains(action.actionType),
                  ),
            ));
    final calculations =
        <({String target, Set<String> inputs, void Function() run})>[];
    final systemInputs = Map<String, dynamic>.from(values);
    for (final rule in rules) {
      if (!_matchesAll(values, rule.conditions)) continue;
      for (final action in rule.actions) {
        switch (action.actionType) {
          case 'exclude_row':
            break;
          case 'set_field':
            final sourceCode = action.sourceFieldCode;
            calculations.add((
              target: action.targetFieldCode!,
              inputs: {
                if (sourceCode != null && sourceCode != action.targetFieldCode)
                  sourceCode,
              },
              run: () {
                values[action.targetFieldCode!] = sourceCode != null
                    ? values[sourceCode]
                    : _parseConstant(action.constantValue);
                systemInputs[action.targetFieldCode!] =
                    values[action.targetFieldCode!];
                if (action.targetFieldCode == 'line_total') {
                  formulaDefinesLineTotal = true;
                  if (rule.eventType == 'variant_calculation' ||
                      rule.eventType == 'field_changed') {
                    values['_event_line_total'] = true;
                  }
                }
              },
            ));
            break;
          case 'calculate_field':
            final formula = action.formula;
            if (formula != null) {
              calculations.add((
                target: action.targetFieldCode!,
                inputs: formula.tokens
                    .where((token) => token.tokenType == 'field')
                    .map((token) => token.fieldCode!)
                    .toSet(),
                run: () {
                  values[action.targetFieldCode!] = _formula(
                    formula,
                    values,
                    percentFields,
                  );
                  systemInputs[action.targetFieldCode!] =
                      values[action.targetFieldCode!];
                  formulaDefinesLineTotal =
                      action.targetFieldCode == 'line_total' ||
                      formulaDefinesLineTotal;
                  if (action.targetFieldCode == 'line_total' &&
                      (rule.eventType == 'variant_calculation' ||
                          rule.eventType == 'field_changed')) {
                    values['_event_line_total'] = true;
                  }
                },
              ));
            }
            break;
          case 'set_field_visibility':
            break;
        }
      }
    }

    // Pipeline outputs must not become the next calculation's system inputs.
    systemInputs.addAll(values);
    final pipelines = configuration.moneyPipelines
        .where((item) => item.categoryClientId == categoryClientId)
        .toList(growable: false);
    double? total = pipelines.isEmpty ? null : 0;
    for (final pipeline in pipelines) {
      calculations.add((
        target: pipeline.resultFieldCode,
        inputs: {
          pipeline.basePriceFieldCode,
          if (pipeline.manualPriceFieldCode != null)
            pipeline.manualPriceFieldCode!,
          if (pipeline.markupFieldCode != null) pipeline.markupFieldCode!,
          if (pipeline.discountFieldCode != null) pipeline.discountFieldCode!,
          if (pipeline.quantityFieldCode != null) pipeline.quantityFieldCode!,
        }..remove(pipeline.resultFieldCode),
        run: () {
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
        },
      ));
    }
    while (calculations.isNotEmpty) {
      final index = calculations.indexWhere(
        (job) =>
            !calculations.any((writer) => job.inputs.contains(writer.target)),
      );
      if (index < 0) {
        throw const FormatException(
          'Циклическая зависимость между формулами и конвейерами. Проверьте исходные поля и поля результата.',
        );
      }
      calculations.removeAt(index).run();
    }
    if (total == null &&
        formulaDefinesLineTotal &&
        values['line_total'] is num) {
      total = _number(values['line_total']);
    }

    for (final rule in rules.where((_) => !fieldTotalsConfigured)) {
      if (!_matchesAll(values, rule.conditions)) continue;
      for (final action in rule.actions) {
        if (action.actionType != 'aggregate_money') continue;
        var amount = _number(values[action.sourceFieldCode]) ?? 0;
        if (action.multiplyByQuantity) {
          amount *= _number(values[action.quantityFieldCode]) ?? 1;
        }
        total ??= position.legacyLineTotal;
        total =
            total! +
            (action.aggregationOperation == 'subtract' ? -amount : amount);
      }
    }

    position
      ..quantity = _number(systemInputs['quantity']) ?? position.quantity
      ..purchasePrice =
          _number(systemInputs['purchase_price']) ?? position.purchasePrice
      ..manualPrice = _effectiveManualPrice(systemInputs, position)
      ..markupPercent =
          _number(systemInputs['markup_value']) ?? position.markupPercent
      ..discountPercent =
          _number(systemInputs['discount_value']) ?? position.discountPercent
      ..excludeFromTotals = values['excluded_from_calc'] is bool
          ? values['excluded_from_calc'] as bool
          : position.excludeFromTotals
      ..configuredLineTotal = total == null ? null : _round(total!, 2);
    if (fieldTotalsConfigured) {
      if (!formulaDefinesLineTotal &&
          !pipelines.any(
            (pipeline) => pipeline.resultFieldCode == 'line_total',
          )) {
        values['line_total'] = position.legacyLineTotal;
      }
      position.configuredLineTotal = _round(
        categoryFields
            .where(
              (field) =>
                  field.totalMode == 'total' || field.totalMode == 'separate',
            )
            .fold(
              0.0,
              (sum, field) => sum + (_number(values[field.code]) ?? 0),
            ),
        2,
      );
    }
    if ((position.configuredLineTotal ?? 0) < 0) {
      throw const FormatException(
        'Итоговая стоимость позиции не может быть отрицательной.',
      );
    }
    position.ruleDefinesLineTotal = formulaDefinesLineTotal;
    values.remove('variant_total');
    position.values
      ..clear()
      ..addAll(values);
    // An event activates a highlight; unrelated recalculations must not activate it.
    final visibilityRules = _rulesFor(categoryClientId)
        .where(
          (rule) => rule.actions.any(
            (action) => action.actionType == 'set_field_visibility',
          ),
        )
        .toList();
    position.activatedVisibilityRuleIds.removeWhere(
      (id) => !visibilityRules.any((rule) => rule.clientId == id),
    );
    for (final rule in visibilityRules) {
      if (rules.contains(rule)) {
        if (_matchesAll({
          ...values,
          'variant_total': ?variantTotal,
        }, rule.conditions)) {
          position.activatedVisibilityRuleIds.add(rule.clientId);
        } else {
          position.activatedVisibilityRuleIds.remove(rule.clientId);
        }
      }
      if (!position.activatedVisibilityRuleIds.contains(rule.clientId)) {
        continue;
      }
      for (final action in rule.actions.where(
        (action) =>
            action.actionType == 'set_field_visibility' &&
            action.targetFieldCode != null,
      )) {
        if (action.booleanValue == false) {
          position.hiddenFieldCodes.add(action.targetFieldCode!);
        } else {
          position.hiddenFieldCodes.remove(action.targetFieldCode!);
        }
      }
    }
    final highlightRules = _rulesFor(categoryClientId)
        .where(
          (rule) => rule.actions.any(
            (action) => action.actionType == 'highlight_field',
          ),
        )
        .toList();
    final eligibleIds = highlightRules.map((rule) => rule.clientId).toSet();
    position.activatedHighlightRuleIds.removeWhere(
      (id) => !eligibleIds.contains(id),
    );
    for (final rule in highlightRules) {
      if (rules.contains(rule)) {
        if (_matchesAll({
          ...values,
          'variant_total': ?variantTotal,
        }, rule.conditions)) {
          position.activatedHighlightRuleIds.add(rule.clientId);
        } else {
          position.activatedHighlightRuleIds.remove(rule.clientId);
        }
      }
      if (!position.activatedHighlightRuleIds.contains(rule.clientId)) continue;
      for (final action in rule.actions) {
        if (action.actionType != 'highlight_field' ||
            action.targetFieldCode == null) {
          continue;
        }
        final color = action.highlightColor ?? '';
        if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(color)) continue;
        position.fieldHighlights[action.targetFieldCode!] = (
          color: color,
          message: action.message?.trim() ?? '',
        );
      }
    }
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

  static Set<String> _effectRuleIds(Map<String, dynamic> values) =>
      values['_active_effect_rules'] is List
      ? (values['_active_effect_rules'] as List).whereType<String>().toSet()
      : <String>{};

  Map<String, dynamic> _valuesOf(QuotePositionDraft position) =>
      Map<String, dynamic>.from(position.values)
        ..['name'] = position.name
        ..['marking'] = position.marking
        ..['unit'] = position.unit
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
    final comparison = condition.comparisonFieldCode != null
        ? values[condition.comparisonFieldCode]
        : condition.comparisonValue;
    final left = _number(value);
    final right = _number(comparison);
    return switch (condition.operator) {
      'is_true' => value == true,
      'is_false' => value == false,
      'greater_than_zero' => (_number(value) ?? 0) > 0,
      'is_filled' =>
        value != null &&
            (value is! String || value.trim().isNotEmpty) &&
            (value is! Iterable || value.isNotEmpty),
      'less_than' => left != null && right != null && left < right,
      'greater_than' => left != null && right != null && left > right,
      'equals' =>
        condition.comparisonFieldCode != null &&
                (value == null || comparison == null)
            ? false
            : left != null && right != null
            ? left == right
            : (value?.toString() ?? '').trim().toLowerCase() ==
                  (comparison?.toString() ?? '').trim().toLowerCase(),
      _ => false,
    };
  });

  static dynamic _parseConstant(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.toLowerCase() == 'true') return true;
    if (normalized.toLowerCase() == 'false') return false;
    return double.tryParse(normalized.replaceAll(',', '.')) ?? normalized;
  }

  static double _formula(
    FormulaDraft formula,
    Map<String, dynamic> values,
    Set<String> percentFields,
  ) {
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
        final value = _requiredNumber(values, token.fieldCode!);
        stack.add(
          percentFields.contains(token.fieldCode) ? value / 100 : value,
        );
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
      (throw MissingCalculationValueException(
        'Для расчёта не заполнено поле «$code».',
      ));

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
