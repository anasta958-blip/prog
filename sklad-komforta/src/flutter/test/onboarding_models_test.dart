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
        CatalogFieldDraft(fieldCode: 'name', isVisible: true, isRequired: true),
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
  });

  test('реестр полей не содержит повторяющихся кодов', () {
    final codes = onboardingFieldDefinitions.map((item) => item.code).toList();

    expect(codes.toSet().length, codes.length);
    expect(onboardingFieldByCode['line_total']?.isCalculated, isTrue);
    expect(onboardingFieldByCode['line_total']?.canBeRequired, isFalse);
    expect(onboardingFieldByCode, isNot(contains('retail_price')));
    expect(defaultCatalogFieldCodes, isNot(contains('markup_value')));
    expect(defaultCatalogFieldCodes, isNot(contains('discount_value')));
    expect(defaultCatalogFieldCodes, isNot(contains('line_total')));
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
}
