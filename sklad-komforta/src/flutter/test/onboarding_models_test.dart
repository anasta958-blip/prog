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
  });
}
