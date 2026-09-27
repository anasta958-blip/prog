import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_models.dart';
import 'package:sklad_komforta_app/features/onboarding/onboarding_models.dart';
import 'package:sklad_komforta_app/features/quotes/quote_configured_calculation.dart';
import 'package:sklad_komforta_app/features/quotes/quote_models.dart';

void main() {
  test(
    'сводки согласованы с разделами после конвейеров и денежной агрегации',
    () {
      final position = _position(
        basePrice: 100,
        quantity: 2,
        purchasePrice: 40,
        values: {'extra': 15},
      );
      final document = _document(position);
      final type = document.proposalTypes.single;
      final variant = type.variants.single..vatRate = 20;
      final config = _configuration(
        pipelines: [
          MoneyPipelineDraft(
            categoryClientId: 'equipment',
            basePriceFieldCode: 'base_price',
            quantityFieldCode: 'quantity',
            resultFieldCode: 'included',
            includeResultInTotals: true,
          ),
          MoneyPipelineDraft(
            categoryClientId: 'equipment',
            basePriceFieldCode: 'base_price',
            quantityFieldCode: 'quantity',
            resultFieldCode: 'display_only',
            includeResultInTotals: false,
          ),
        ],
        rules: [
          CalculationRuleDraft(
            clientId: 'extra',
            name: 'Доплата',
            categoryClientId: 'equipment',
            eventType: 'row_calculation',
            isEnabled: true,
            actions: [
              RuleActionDraft(
                actionType: 'aggregate_money',
                sourceFieldCode: 'extra',
                aggregationOperation: 'add',
                aggregationTarget: 'variant_total',
                multiplyByQuantity: true,
                quantityFieldCode: 'quantity',
              ),
            ],
          ),
        ],
      );
      final engine = QuoteConfiguredCalculationEngine(config);
      for (var run = 0; run < 3; run++) {
        engine.calculateDocument(document);
        expect(position.values['display_only'], 200);
        expect(variant.categories.single.sections.single.clientTotal, 230);
        expect(variant.categories.single.clientTotal, 230);
        expect(variant.systemSummary.subtotal, 230);
        expect(variant.systemSummary.purchase, 80);
        expect(variant.systemSummary.margin, 150);
        expect(variant.systemSummary.vat, 46);
        expect(variant.systemSummary.total, 276);
        expect(type.systemSummary.total, 276);
      }
      position.excludeFromTotals = true;
      engine.calculateDocument(document);
      expect(variant.systemSummary.total, 0);
      expect(type.systemSummary.total, 0);
    },
  );
  test(
    'отсутствующее значение указывает название поля, а цикл отклоняется',
    () {
      final missing = _configuration(
        fields: [
          const CatalogField(
            code: 'custom_missing',
            label: 'Исходная стоимость',
            fieldType: 'money',
            isRequired: true,
            isVisible: true,
            sortOrder: 0,
          ),
        ],
        pipelines: [
          MoneyPipelineDraft(
            categoryClientId: 'equipment',
            basePriceFieldCode: 'custom_missing',
            resultFieldCode: 'result',
          ),
        ],
      );
      expect(
        () => QuoteConfiguredCalculationEngine(
          missing,
        ).calculateDocument(_document(_position())),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('«Исходная стоимость»'),
          ),
        ),
      );
      final cyclic = _configuration(
        pipelines: [
          MoneyPipelineDraft(
            categoryClientId: 'equipment',
            basePriceFieldCode: 'b',
            resultFieldCode: 'a',
          ),
          MoneyPipelineDraft(
            categoryClientId: 'equipment',
            basePriceFieldCode: 'a',
            resultFieldCode: 'b',
          ),
        ],
      );
      expect(
        () => QuoteConfiguredCalculationEngine(
          cyclic,
        ).calculateDocument(_document(_position(values: {'a': 1, 'b': 2}))),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('Циклическая зависимость'),
          ),
        ),
      );
    },
  );
  test('формула читает свежий результат конвейера и передаёт следующему', () {
    for (final stale in [false, true]) {
      final position = _position(
        basePrice: 100,
        quantity: 2,
        values: {'discount': 10, if (stale) 'subtotal': 1},
      );
      final config = _configuration(
        fields: [
          const CatalogField(
            code: 'discount',
            label: 'Скидка',
            fieldType: 'percent',
            isVisible: true,
            isRequired: false,
            sortOrder: 0,
          ),
        ],
        rules: [
          CalculationRuleDraft(
            clientId: 'r',
            name: 'Скидка',
            categoryClientId: 'equipment',
            eventType: 'row_calculation',
            isEnabled: true,
            actions: [
              RuleActionDraft(
                actionType: 'calculate_field',
                targetFieldCode: 'discount_amount',
                formula: FormulaDraft(
                  tokens: [
                    FormulaTokenDraft(
                      tokenType: 'field',
                      fieldCode: 'subtotal',
                    ),
                    FormulaTokenDraft(
                      tokenType: 'operator',
                      operator: 'multiply',
                    ),
                    FormulaTokenDraft(
                      tokenType: 'field',
                      fieldCode: 'discount',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
        pipelines: [
          MoneyPipelineDraft(
            categoryClientId: 'equipment',
            basePriceFieldCode: 'discount_amount',
            resultFieldCode: 'final',
            includeResultInTotals: false,
          ),
          MoneyPipelineDraft(
            categoryClientId: 'equipment',
            basePriceFieldCode: 'base_price',
            quantityFieldCode: 'quantity',
            resultFieldCode: 'subtotal',
          ),
        ],
      );
      QuoteConfiguredCalculationEngine(
        config,
      ).calculateDocument(_document(position));
      expect(position.values['subtotal'], 200);
      expect(position.values['discount_amount'], 20);
      expect(position.values['final'], 20);
      expect(position.basePrice, 100);
    }
  });
  test('процент в формуле является долей, а число остаётся числом', () {
    for (final percent in <dynamic>[null, '', '  ', 0.0, 2.5, 22.0, 100.0]) {
      final expected = percent is num ? percent : 0.0;
      final position = _position(
        basePrice: 1000,
        values: {'discount': percent},
      );
      final config = _configuration(
        fields: [
          const CatalogField(
            code: 'discount',
            label: 'Скидка',
            fieldType: 'percent',
            isVisible: true,
            isRequired: false,
            sortOrder: 0,
          ),
        ],
        rules: [
          CalculationRuleDraft(
            clientId: 'r',
            name: 'Сумма скидки',
            categoryClientId: 'equipment',
            eventType: 'row_calculation',
            isEnabled: true,
            actions: [
              RuleActionDraft(
                actionType: 'calculate_field',
                targetFieldCode: 'result',
                formula: FormulaDraft(
                  tokens: [
                    FormulaTokenDraft(
                      tokenType: 'field',
                      fieldCode: 'base_price',
                    ),
                    FormulaTokenDraft(
                      tokenType: 'operator',
                      operator: 'multiply',
                    ),
                    FormulaTokenDraft(
                      tokenType: 'field',
                      fieldCode: 'discount',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      );
      QuoteConfiguredCalculationEngine(
        config,
      ).calculateDocument(_document(position));
      expect(position.values['result'], 10 * expected);
      expect(position.values['discount'], expected);
      position.values.remove('discount');
      QuoteConfiguredCalculationEngine(
        config,
      ).calculateDocument(_document(position));
      expect(position.values['result'], 0);
      expect(position.values['discount'], 0);
    }
  });
  test('сводка учитывает результат конвейера без изменения системной цены', () {
    final position = _position(
      quantity: 2,
      basePrice: 4100,
      purchasePrice: 100,
      values: {'minimal_price': 1},
    );
    final document = _document(position);
    final variant = document.proposalTypes.single.variants.single..vatRate = 1;
    final engine = QuoteConfiguredCalculationEngine(
      _configuration(
        pipelines: [
          MoneyPipelineDraft(
            categoryClientId: 'equipment',
            basePriceFieldCode: 'base_price',
            manualPriceFieldCode: 'minimal_price',
            quantityFieldCode: 'quantity',
            resultFieldCode: 'base_price',
          ),
        ],
      ),
    );
    for (var run = 0; run < 3; run++) {
      engine.calculateDocument(document);
      expect(position.lineTotal, 2);
      expect(position.basePrice, 4100);
      expect(position.manualPrice, isNull);
      expect(variant.systemSummary.subtotal, 2);
      expect(variant.systemSummary.vat, 0.02);
      expect(variant.systemSummary.total, 2.02);
      expect(variant.systemSummary.margin, -198);
      expect(document.proposalTypes.single.systemSummary.subtotal, 2);
    }
    position.manualPrice = 4200;
    engine.calculateDocument(document);
    expect(variant.systemSummary.subtotal, 2);
    position.excludeFromTotals = true;
    expect(variant.systemSummary.subtotal, 0);
  });
  test(
    'событийное правило выполняется только для изменённого поля и строки',
    () {
      final position = _position(quantity: 1, basePrice: 100);
      final document = _document(position);
      final engine = QuoteConfiguredCalculationEngine(
        _configuration(
          rules: [
            CalculationRuleDraft(
              clientId: 'quantity-note',
              name: 'Количество в примечание',
              categoryClientId: 'equipment',
              eventType: 'field_changed',
              eventFieldCode: 'quantity',
              isEnabled: true,
              conditions: [],
              actions: [
                RuleActionDraft(
                  actionType: 'set_field',
                  sourceFieldCode: 'quantity',
                  targetFieldCode: 'note',
                ),
              ],
            ),
            CalculationRuleDraft(
              clientId: 'exclude',
              name: 'Исключить',
              categoryClientId: 'equipment',
              eventType: 'field_changed',
              eventFieldCode: 'flag',
              isEnabled: true,
              conditions: [
                RuleConditionDraft(fieldCode: 'flag', operator: 'is_true'),
              ],
              actions: [RuleActionDraft(actionType: 'exclude_row')],
            ),
          ],
          pipelines: [
            MoneyPipelineDraft(
              categoryClientId: 'equipment',
              basePriceFieldCode: 'base_price',
              quantityFieldCode: 'quantity',
              resultFieldCode: 'custom_total',
            ),
          ],
        ),
      );
      engine.calculateDocument(document);
      expect(position.values['note'], isNull);
      position.quantity = 3;
      engine.calculateDocument(
        document,
        changedPosition: position,
        changedFieldCode: 'quantity',
      );
      expect(position.values['note'], 3);
      expect(position.values['custom_total'], 300);
      expect(position.excludeFromTotals, isFalse);
      position.values['flag'] = true;
      engine.calculateDocument(
        document,
        changedPosition: position,
        changedFieldCode: 'flag',
      );
      expect(position.excludeFromTotals, isTrue);
      position.values['flag'] = false;
      engine.calculateDocument(
        document,
        changedPosition: position,
        changedFieldCode: 'flag',
      );
      expect(position.excludeFromTotals, isFalse);
      expect(document.proposalTypes.single.clientTotal, 300);
      position.values['_manual_excluded_from_calc'] = true;
      engine.calculateDocument(document);
      expect(position.excludeFromTotals, isTrue);
    },
  );
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
    expect(document.proposalTypes.single.systemSummary.subtotal, 250.80);
    expect(
      document.proposalTypes.single.variants.single.systemSummary.subtotal,
      250.80,
    );
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
    expect(document.proposalTypes.single.systemSummary.subtotal, 0);
    expect(
      document.proposalTypes.single.variants.single.systemSummary.subtotal,
      0,
    );
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
  List<CatalogField> fields = const [],
  List<CalculationRuleDraft> rules = const [],
  List<MoneyPipelineDraft> pipelines = const [],
}) => CatalogConfiguration(
  categories: [
    CatalogCategory(
      id: 'd3cf13c8-0e34-4d4e-b8bb-21f2848e2312',
      clientId: 'equipment',
      name: 'Оборудование',
      sortOrder: 0,
      fields: fields,
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
