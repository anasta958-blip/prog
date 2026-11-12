import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/core/widgets/app_select_field.dart';
import 'package:sklad_komforta_app/features/onboarding/margin_sources_editor.dart';
import 'package:sklad_komforta_app/features/onboarding/onboarding_models.dart';

void main() {
  test('both sides of configured margin are required', () {
    final settings = MarginSettingsDraft(categoryClientId: 'category');
    expect(settings.hasRequiredSources, isFalse);
    settings.revenueFields.add(MarginFieldDraft(fieldCode: 'sale'));
    expect(settings.hasRequiredSources, isFalse);
    settings.costFields.add(MarginFieldDraft(fieldCode: 'cost'));
    expect(settings.hasRequiredSources, isTrue);
    settings.revenueFields.clear();
    expect(settings.hasRequiredSources, isFalse);
  });
  for (final width in [320.0, 1200.0]) {
    testWidgets('margin sources can be added, multiplied and removed at $width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 1000);
      addTearDown(tester.view.reset);
      final category = CatalogCategoryDraft(
        clientId: 'equipment',
        name: 'Оборудование',
        sections: [],
        fields: [
          CatalogFieldDraft(
            fieldCode: 'custom_a',
            label: 'Поле А',
            fieldType: 'money',
            isVisible: true,
            isRequired: false,
          ),
          CatalogFieldDraft(
            fieldCode: 'custom_b',
            label: 'Поле Б',
            fieldType: 'calculated_money',
            isVisible: true,
            isRequired: false,
          ),
          CatalogFieldDraft(
            fieldCode: 'custom_text',
            label: 'Текст',
            fieldType: 'text',
            isVisible: true,
            isRequired: false,
          ),
        ],
      );
      MarginSettingsDraft? settings;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: MarginSourcesEditor(
                    category: category,
                    settings: settings,
                    onChanged: (value) => setState(() => settings = value),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Выручка ='), findsOneWidget);
      expect(find.text('Затраты ='), findsOneWidget);
      final initial = tester.widget<AppSelectField<String>>(
        find.byKey(const ValueKey('margin-revenue-add-0')),
      );
      expect(initial.options.map((item) => item.value), [
        'custom_a',
        'custom_b',
      ]);
      await tester.tap(find.byKey(const ValueKey('margin-revenue-add-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Поле А').last);
      await tester.pumpAndSettle();
      expect(settings!.revenueFields.single.fieldCode, 'custom_a');
      expect(
        find.text(
          'Для сохранения выберите хотя бы одно поле выручки и одно поле затрат.',
        ),
        findsOneWidget,
      );
      final next = tester.widget<AppSelectField<String>>(
        find.byKey(const ValueKey('margin-revenue-add-1')),
      );
      expect(next.options.map((item) => item.value), ['custom_b']);
      await tester.tap(
        find.byKey(const ValueKey('margin-revenue-quantity-custom_a')),
      );
      await tester.pumpAndSettle();
      expect(settings!.revenueFields.single.multiplyByQuantity, isTrue);
      tester
          .widget<AppSelectField<String>>(
            find.byKey(const ValueKey('margin-revenue-add-1')),
          )
          .onChanged!('custom_b');
      await tester.pumpAndSettle();
      expect(settings!.revenueFields.length, 2);
      expect(find.text('+'), findsOneWidget);
      expect(settings!.revenueFields.first.multiplyByQuantity, isTrue);
      expect(settings!.revenueFields.last.multiplyByQuantity, isFalse);
      final cost = tester.widget<AppSelectField<String>>(
        find.byKey(const ValueKey('margin-cost-add-0')),
      );
      cost.onChanged!('custom_b');
      await tester.pumpAndSettle();
      expect(settings!.costFields.single.fieldCode, 'custom_b');
      expect(
        find.text(
          'Для сохранения выберите хотя бы одно поле выручки и одно поле затрат.',
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Убрать поле из выручки').first);
      await tester.pumpAndSettle();
      expect(settings!.revenueFields.single.fieldCode, 'custom_b');
      expect(settings!.costFields.single.fieldCode, 'custom_b');
      expect(find.text('+'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
