import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/core/models/workflow_specialization.dart';
import 'package:sklad_komforta_app/features/onboarding/onboarding_field_registry.dart';
import 'package:sklad_komforta_app/features/onboarding/onboarding_models.dart';

void main() {
  for (final copied in [false, true]) {
    test('category change preserves rule structure (copied: $copied)', () {
      final source = CalculationRuleDraft(
        clientId: 'rule',
        name: 'Правило',
        categoryClientId: 'old',
        eventType: 'field_changed',
        eventFieldCode: 'price',
        isEnabled: false,
        conditions: [
          RuleConditionDraft(
            fieldCode: 'price',
            operator: 'less_than',
            comparisonFieldCode: 'cost',
          ),
          RuleConditionDraft(
            fieldCode: 'quantity',
            operator: 'equals',
            comparisonValue: '10',
          ),
        ],
        actions: [
          RuleActionDraft(
            actionType: 'highlight_field',
            targetFieldCode: 'price',
            highlightColor: '#EF4444',
            message: 'Проверка',
          ),
          RuleActionDraft(
            actionType: 'calculate_field',
            targetFieldCode: 'result',
            sourceFieldCode: 'cost',
            quantityFieldCode: 'quantity',
            dependencyClientId: 'relation',
            multiplyByQuantity: true,
            formula: FormulaDraft(
              decimalPlaces: 3,
              tokens: [
                FormulaTokenDraft(tokenType: 'field', fieldCode: 'cost'),
                FormulaTokenDraft(tokenType: 'operator', operator: '*'),
                FormulaTokenDraft(tokenType: 'constant', constantValue: 10),
              ],
            ),
          ),
        ],
      );
      final before = source.toJson();
      final rule = copied
          ? source.copy(clientId: 'copy', name: 'Копия')
          : source;
      rule.changeCategory('old');
      expect(rule.eventFieldCode, 'price');
      rule.changeCategory('new');
      expect(rule.categoryClientId, 'new');
      expect(rule.eventType, 'field_changed');
      expect(rule.eventFieldCode, isNull);
      expect(rule.isEnabled, isFalse);
      expect(rule.conditions.map((item) => item.operator), [
        'less_than',
        'equals',
      ]);
      expect(rule.conditions.map((item) => item.fieldCode), ['', '']);
      expect(rule.conditions.first.comparisonFieldCode, '');
      expect(rule.conditions.last.comparisonFieldCode, isNull);
      expect(rule.conditions.last.comparisonValue, '10');
      expect(rule.actions.map((item) => item.actionType), [
        'highlight_field',
        'calculate_field',
      ]);
      expect(rule.actions.first.message, 'Проверка');
      expect(rule.actions.first.highlightColor, '#EF4444');
      expect(rule.actions.first.targetFieldCode, isNull);
      final action = rule.actions.last;
      expect(action.targetFieldCode, isNull);
      expect(action.sourceFieldCode, isNull);
      expect(action.quantityFieldCode, isNull);
      expect(action.dependencyClientId, isNull);
      expect(action.multiplyByQuantity, isTrue);
      expect(action.formula!.decimalPlaces, 3);
      expect(action.formula!.tokens.first.fieldCode, isNull);
      expect(action.formula!.tokens[1].operator, '*');
      expect(action.formula!.tokens.last.constantValue, 10);
      expect(
        CalculationRuleDraft.fromJson(rule.toJson()).toJson(),
        rule.toJson(),
      );
      if (copied) expect(source.toJson(), before);
    });
  }

  test('rule copy preserves settings and owns all nested mutable data', () {
    final source = CalculationRuleDraft(
      clientId: 'original',
      name: 'Правило',
      categoryClientId: 'category',
      eventType: 'field_changed',
      eventFieldCode: 'price',
      isEnabled: false,
      conditions: [
        RuleConditionDraft(
          fieldCode: 'price',
          operator: 'equals',
          comparisonFieldCode: 'cost',
        ),
      ],
      actions: [
        RuleActionDraft(
          actionType: 'set_field',
          targetFieldCode: 'result',
          highlightColor: '#EF4444',
          message: 'Сообщение',
          formula: FormulaDraft(
            tokens: [
              FormulaTokenDraft(tokenType: 'constant', constantValue: 10),
            ],
          ),
        ),
      ],
    );
    final before = source.toJson();
    final copy = source.copy(clientId: 'copy', name: 'Правило (копия)');
    expect(copy.toJson(), {
      ...before,
      'clientId': 'copy',
      'name': 'Правило (копия)',
    });
    copy.conditions.first.comparisonFieldCode = 'other';
    copy.actions.first.formula!.tokens.first.constantValue = 20;
    copy.actions.first.message = 'Изменено';
    copy.conditions.clear();
    expect(source.toJson(), before);
    expect(
      CalculationRuleDraft.fromJson(copy.toJson()).toJson(),
      copy.toJson(),
    );
  });
  test('field total mode survives serialization including legacy null', () {
    for (final mode in [null, 'none', 'total', 'separate', 'separate_only']) {
      final field = CatalogFieldDraft(
        fieldCode: 'custom_amount',
        fieldType: 'money',
        isVisible: true,
        isRequired: false,
        totalMode: mode,
      );
      expect(CatalogFieldDraft.fromJson(field.toJson()).totalMode, mode);
    }
  });
  test(
    'источник поставщика сохраняется по коду, явное отключение не заменяется',
    () {
      final category = WorkflowCategoryDraft(
        categoryClientId: 'equipment',
        fieldCodes: ['custom_vendor'],
        supplierFilterFieldCode: 'custom_vendor',
      );
      expect(
        WorkflowCategoryDraft.fromJson(
          category.toJson(),
        ).supplierFilterFieldCode,
        'custom_vendor',
      );
      category.supplierFilterFieldCode = null;
      expect(
        WorkflowCategoryDraft.fromJson(
          category.toJson(),
        ).supplierFilterFieldCode,
        isNull,
      );
      expect(
        WorkflowCategoryDraft.fromJson({
          'categoryClientId': 'equipment',
          'fieldCodes': ['supplier'],
        }).supplierFilterFieldCode,
        isNull,
      );
    },
  );
  test('supplier отсутствует в реестре системных полей', () {
    expect(onboardingFieldByCode.containsKey('supplier'), isFalse);
  });
  test('занятые поля объединяют записи правил и конвейеров по категории', () {
    final draft = OrganizationOnboardingDraft.initial();
    final action = RuleActionDraft(
      actionType: 'set_field',
      targetFieldCode: 'total',
    );
    final pipeline = MoneyPipelineDraft(
      categoryClientId: 'a',
      basePriceFieldCode: 'price',
      resultFieldCode: 'amount',
    );
    draft.moneyPipelines.add(pipeline);
    draft.rules.add(
      CalculationRuleDraft(
        clientId: 'r',
        name: 'Правило',
        categoryClientId: 'a',
        eventType: 'row_calculation',
        isEnabled: false,
        actions: [
          action,
          RuleActionDraft(
            actionType: 'set_field_visibility',
            targetFieldCode: 'visible',
          ),
        ],
      ),
    );
    expect(draft.occupiedCalculationFields('a'), {'total', 'amount'});
    expect(draft.occupiedCalculationFields('a', exceptAction: action), {
      'amount',
    });
    expect(draft.occupiedCalculationFields('a', exceptPipeline: pipeline), {
      'total',
    });
    expect(draft.occupiedCalculationFields('b'), isEmpty);
  });
  test('юридическое лицо сохраняет собственную ставку НДС', () {
    final entity = LegalEntityModel(
      id: 'entity-1',
      name: 'Исполнитель',
      companyType: 'ООО',
    )..vatRates = [null, 10, 22];

    final restored = LegalEntityModel.fromJson({
      ...entity.toJson(),
      'id': entity.id,
    });

    expect(restored.vatRates, [null, 10, 22]);
  });

  test('столбец сохраняет назначенные действия создания документов', () {
    final source = WorkflowColumnDraft(
      clientId: 'quote-first',
      name: 'Составить предложение',
      color: '#4D8DFF',
      creationActions: const [
        WorkflowCreationAction.quote,
        WorkflowCreationAction.prequote,
      ],
    );

    final restored = WorkflowColumnDraft.fromJson(source.toJson());

    expect(restored.creationActions, const [
      WorkflowCreationAction.quote,
      WorkflowCreationAction.prequote,
    ]);
  });

  test('категория сохраняет устойчивый id и упорядоченные системные поля', () {
    final source = CatalogCategoryDraft(
      clientId: 'equipment',
      name: 'Оборудование',
      sections: [],
      fields: [
        CatalogFieldDraft(
          fieldCode: 'name',
          isVisible: true,
          isRequired: true,
          label: 'Название оборудования',
        ),
        CatalogFieldDraft(
          fieldCode: 'base_price',
          isVisible: true,
          isRequired: false,
        ),
      ],
    );

    final restored = CatalogCategoryDraft.fromJson(source.toJson());

    expect(restored.clientId, 'equipment');
    expect(restored.fields.map((item) => item.fieldCode), [
      'name',
      'base_price',
    ]);
    expect(restored.fields.first.isRequired, isTrue);
    expect(restored.fields.first.label, 'Название оборудования');
    expect(catalogFieldLabel(restored.fields.first), 'Название оборудования');
  });

  test('старое поле без пользовательского названия использует системное', () {
    final source = CatalogFieldDraft(
      fieldCode: 'name',
      isVisible: true,
      isRequired: true,
    ).toJson()..remove('label');

    final restored = CatalogFieldDraft.fromJson(source);

    expect(restored.label, isNull);
    expect(catalogFieldLabel(restored), 'Наименование');
  });

  test('пользовательское поле сохраняет выбранный тип и пустое название', () {
    final source = CatalogFieldDraft(
      fieldCode: 'custom_101',
      fieldType: 'number',
      isVisible: true,
      isRequired: false,
      label: '',
    );

    final restored = CatalogFieldDraft.fromJson(source.toJson());

    expect(restored.fieldType, 'number');
    expect(catalogFieldType(restored), 'number');
    expect(catalogFieldLabel(restored), isEmpty);
  });

  test('реестр полей не содержит повторяющихся кодов', () {
    final codes = onboardingFieldDefinitions.map((item) => item.code).toList();

    expect(codes.toSet().length, codes.length);
    expect(onboardingFieldByCode['line_total']?.isCalculated, isTrue);
    expect(onboardingFieldByCode['line_total']?.canBeRequired, isFalse);
    expect(onboardingFieldByCode, isNot(contains('retail_price')));
    expect(defaultCatalogFieldCodes, [
      'name',
      'marking',
      'quantity',
      'unit',
      'base_price',
    ]);
    expect(isFixedCatalogField('name'), isTrue);
    expect(isFixedCatalogField('quantity'), isTrue);
    expect(isFixedCatalogField('supplier'), isFalse);
  });

  test('пользовательские типы не дублируют справочник и содержат сумму', () {
    final types = customCatalogFieldTypes
        .map((definition) => definition.fieldType)
        .toSet();

    expect(types, isNot(contains('enum')));
    expect(types, contains('dictionary'));
    expect(types, contains('calculated_money'));
    final calculated = customCatalogFieldTypes.singleWhere(
      (definition) => definition.fieldType == 'calculated_money',
    );
    expect(calculated.isCalculated, isTrue);
    expect(calculated.canBeRequired, isFalse);
  });

  test('старый черновик без зависимостей остаётся совместимым', () {
    final source = OrganizationOnboardingDraft.initial().toJson()
      ..remove('dependencies');

    final restored = OrganizationOnboardingDraft.fromJson(source);

    expect(restored.dependencies, isEmpty);
  });

  test('зависимость категорий сохраняет направление и relation-поле', () {
    final dependency = CategoryDependencyDraft(
      clientId: 'works-equipment',
      sourceCategoryClientId: 'works',
      targetCategoryClientId: 'equipment',
      targetFieldCode: 'linked_services',
    );

    final restored = CategoryDependencyDraft.fromJson(dependency.toJson());

    expect(restored.sourceCategoryClientId, 'works');
    expect(restored.targetCategoryClientId, 'equipment');
    expect(restored.targetFieldCode, 'linked_services');
  });

  test('старый канбан без категорий остаётся совместимым', () {
    final source = WorkflowDraft(
      code: 'quote',
      name: 'КП',
      columns: [],
      transitions: [],
    ).toJson()..remove('categories');

    final restored = WorkflowDraft.fromJson(source);

    expect(restored.categories, isEmpty);
    expect(restored.specialization.apiValue, isNull);
  });

  test('специализация канбана сохраняется в JSON', () {
    for (final specialization in [
      WorkflowSpecialization.prequote,
      WorkflowSpecialization.quoteAndPrequote,
    ]) {
      final source = WorkflowDraft(
        code: 'quote',
        name: 'Предложения',
        columns: [],
        transitions: [],
        specialization: specialization,
      );

      final restored = WorkflowDraft.fromJson(source.toJson());
      expect(restored.specialization, specialization);
    }
  });

  test('канбан сохраняет категории и порядок полей карточки', () {
    final source = WorkflowDraft(
      code: 'quote',
      name: 'КП',
      columns: [],
      transitions: [],
      categories: [
        WorkflowCategoryDraft(
          categoryClientId: 'equipment',
          fieldCodes: ['name', 'line_total'],
        ),
      ],
    );

    final restored = WorkflowDraft.fromJson(source.toJson());

    expect(restored.categories.single.categoryClientId, 'equipment');
    expect(restored.categories.single.fieldCodes, ['name', 'line_total']);
  });

  test('старый черновик без правил остаётся совместимым', () {
    final source = OrganizationOnboardingDraft.initial().toJson()
      ..remove('rules')
      ..remove('moneyPipelines');

    final restored = OrganizationOnboardingDraft.fromJson(source);

    expect(restored.rules, isEmpty);
    expect(restored.moneyPipelines, isEmpty);
  });

  test('правило, формула и денежный конвейер сохраняются в JSON', () {
    final source = OrganizationOnboardingDraft.initial()
      ..currentStep = 9
      ..rules.add(
        CalculationRuleDraft(
          clientId: 'calculate-total',
          name: 'Рассчитать сумму',
          categoryClientId: 'equipment',
          eventType: 'row_calculation',
          isEnabled: true,
          conditions: [],
          actions: [
            RuleActionDraft(
              actionType: 'calculate_field',
              targetFieldCode: 'line_total',
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
                  FormulaTokenDraft(tokenType: 'field', fieldCode: 'quantity'),
                ],
              ),
            ),
          ],
        ),
      )
      ..moneyPipelines.add(
        MoneyPipelineDraft(
          clientId: 'equipment-total',
          categoryClientId: 'equipment',
          basePriceFieldCode: 'base_price',
          resultFieldCode: 'line_total',
          decimalPlaces: 2,
          includeResultInTotals: true,
        ),
      );

    final restored = OrganizationOnboardingDraft.fromJson(source.toJson());

    expect(restored.currentStep, 9);
    expect(restored.rules.single.actions.single.formula?.tokens, hasLength(3));
    expect(restored.moneyPipelines.single.clientId, 'equipment-total');
    expect(restored.moneyPipelines.single.basePriceFieldCode, 'base_price');
  });

  test('старый денежный конвейер без id получает устойчивый id', () {
    final source = MoneyPipelineDraft(
      categoryClientId: 'equipment',
      basePriceFieldCode: 'base_price',
      resultFieldCode: 'line_total',
    ).toJson()..remove('clientId');

    final first = MoneyPipelineDraft.fromJson(source);
    final second = MoneyPipelineDraft.fromJson(source);

    expect(first.clientId, 'pipeline_equipment_line_total');
    expect(second.clientId, first.clientId);
  });
}
