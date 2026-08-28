import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/features/onboarding/onboarding_field_registry.dart';
import 'package:sklad_komforta_app/features/onboarding/onboarding_models.dart';

void main() {
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
    expect(defaultCatalogFieldCodes, ['name', 'marking', 'unit', 'base_price']);
    expect(isFixedCatalogField('name'), isTrue);
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
    expect(restored.moneyPipelines.single.basePriceFieldCode, 'base_price');
  });
}
