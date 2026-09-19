import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_models.dart';
import 'package:sklad_komforta_app/features/onboarding/onboarding_models.dart';
import 'package:sklad_komforta_app/features/quotes/quote_configured_calculation.dart';
import 'package:sklad_komforta_app/features/quotes/quote_models.dart';

void main() {
  test('настроенный денежный конвейер пересчитывает строку и сводку', () {
    final position = _position(
      quantity: 2,
      purchasePrice: 100,
      basePrice: 100,
      manualPrice: 120,
      markup: 10,
      discount: 5,
    );
    final document = _document(position);
    final configuration = _configuration(
      pipelines: [
        MoneyPipelineDraft(
          categoryClientId: 'equipment',
          basePriceFieldCode: 'purchase_price',
          manualPriceFieldCode: 'base_price',
          markupFieldCode: 'markup_value',
          discountFieldCode: 'discount_value',
          quantityFieldCode: 'quantity',
          resultFieldCode: 'line_total',
        ),
      ],
    );

    QuoteConfiguredCalculationEngine(configuration).calculateDocument(document);

    expect(position.lineTotal, 250.80);
    expect(document.proposalTypes.single.clientTotal, 250.80);
  });

  test('результат конвейера можно исключить из итогов', () {
    final position = _position(quantity: 3, basePrice: 40);
    final document = _document(position);
    final configuration = _configuration(
      pipelines: [
        MoneyPipelineDraft(
          categoryClientId: 'equipment',
          basePriceFieldCode: 'base_price',
          quantityFieldCode: 'quantity',
          resultFieldCode: 'line_total',
          includeResultInTotals: false,
        ),
      ],
    );

    QuoteConfiguredCalculationEngine(configuration).calculateDocument(document);

    expect(position.values['line_total'], 120);
    expect(position.lineTotal, 0);
    expect(document.proposalTypes.single.clientTotal, 0);
  });

  test('правило запрета сохранения возвращает заданное сообщение', () {
    final position = _position(basePrice: 100, values: {'approved': false});
    final document = _document(position);
    final configuration = _configuration(
      rules: [
        CalculationRuleDraft(
          clientId: 'approval',
          name: 'Проверка согласования',
          categoryClientId: 'equipment',
          eventType: 'card_saving',
          isEnabled: true,
          conditions: [
            RuleConditionDraft(fieldCode: 'approved', operator: 'is_false'),
          ],
          actions: [
            RuleActionDraft(
              actionType: 'block_save',
              message: 'Нужно согласование.',
            ),
          ],
        ),
      ],
    );

    final message = QuoteConfiguredCalculationEngine(
      configuration,
    ).validateForSave(document);

    expect(message, 'Нужно согласование.');
  });

  test('правило видимости скрывает и повторно показывает поле строки', () {
    final position = _position(values: {'show_note': false});
    final document = _document(position);
    final hideRule = CalculationRuleDraft(
      clientId: 'hide-note',
      name: 'Скрыть примечание',
      categoryClientId: 'equipment',
      eventType: 'row_calculation',
      isEnabled: true,
      conditions: [
        RuleConditionDraft(fieldCode: 'show_note', operator: 'is_false'),
      ],
      actions: [
        RuleActionDraft(
          actionType: 'set_field_visibility',
          targetFieldCode: 'note',
          booleanValue: false,
        ),
      ],
    );
    final engine = QuoteConfiguredCalculationEngine(
      _configuration(rules: [hideRule]),
    );

    engine.calculateDocument(document);
    expect(position.hiddenFieldCodes, contains('note'));

    position.values['show_note'] = true;
    engine.calculateDocument(document);
    expect(position.hiddenFieldCodes, isNot(contains('note')));
  });
}

CatalogConfiguration _configuration({
  List<CalculationRuleDraft> rules = const [],
  List<MoneyPipelineDraft> pipelines = const [],
}) => CatalogConfiguration(
  categories: const [
    CatalogCategory(
      id: 'd3cf13c8-0e34-4d4e-b8bb-21f2848e2312',
      clientId: 'equipment',
      name: 'Оборудование',
      sortOrder: 0,
      fields: [],
      sections: [],
    ),
  ],
  dictionaries: const [],
  rules: rules,
  moneyPipelines: pipelines,
);

QuoteDraft _document(QuotePositionDraft position) => QuoteDraft(
  kind: QuoteKind.quote,
  title: 'Тестовое КП',
  clientId: 'client',
  executorCompanyId: 'company',
  selectionMode: 'variant',
  proposalTypes: [
    QuoteProposalTypeDraft(
      id: 'type',
      name: 'Основное предложение',
      selectedVariantId: 'variant',
      variants: [
        QuoteVariantDraft(
          id: 'variant',
          name: 'Бюджетный',
          categories: [
            QuoteCategoryDraft(
              id: 'category',
              catalogCategoryId: 'd3cf13c8-0e34-4d4e-b8bb-21f2848e2312',
              name: 'Оборудование',
              sections: [
                QuoteSectionDraft(
                  id: 'section',
                  name: 'Вентиляция',
                  positions: [position],
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);

QuotePositionDraft _position({
  double quantity = 1,
  double? purchasePrice,
  double basePrice = 0,
  double? manualPrice,
  double? markup,
  double? discount,
  Map<String, dynamic>? values,
}) => QuotePositionDraft(
  id: 'position',
  name: 'Позиция',
  marking: '',
  unit: 'шт',
  quantity: quantity,
  purchasePrice: purchasePrice,
  basePrice: basePrice,
  manualPrice: manualPrice,
  markupPercent: markup,
  discountPercent: discount,
  values: values ?? <String, dynamic>{},
);
