import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:sklad_komforta_app/features/kanban/kanban_models.dart';
import 'package:sklad_komforta_app/features/quotes/quote_editor_page.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/features/auth/auth_controller.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_models.dart';
import 'package:sklad_komforta_app/features/onboarding/onboarding_models.dart';
import 'package:sklad_komforta_app/features/quotes/quote_controller.dart';
import 'package:sklad_komforta_app/features/quotes/quote_models.dart';

void main() {
  late AuthController auth;
  late QuoteController controller;
  setUp(() {
    const config = AppConfig(
      apiBaseUrl: 'https://example.test',
      environment: 'test',
    );
    auth = AuthController(config);
    controller = QuoteController(config, auth);
    controller.catalog = CatalogConfiguration(
      categories: const [
        CatalogCategory(
          id: 'category',
          clientId: 'equipment',
          name: 'Equipment',
          sortOrder: 0,
          fields: [],
          sections: [],
        ),
      ],
      dictionaries: [],
      marginSettings: [
        MarginSettingsDraft(
          categoryClientId: 'equipment',
          revenueFields: [
            MarginFieldDraft(fieldCode: 'sale', multiplyByQuantity: true),
          ],
          costFields: [
            MarginFieldDraft(fieldCode: 'cost', multiplyByQuantity: true),
            MarginFieldDraft(fieldCode: 'delivery'),
          ],
        ),
      ],
    );
  });
  tearDown(() {
    controller.dispose();
    auth.dispose();
  });

  QuoteCategoryDraft category(
    num sale,
    num cost, {
    num quantity = 1,
    num delivery = 0,
    bool excluded = false,
  }) => QuoteCategoryDraft.fromJson({
    'id': 'category-row',
    'catalogCategoryId': 'category',
    'name': 'Equipment',
    'sections': [
      {
        'id': 'section',
        'name': 'Section',
        'positions': [
          {
            'id': 'row',
            'name': 'Product',
            'quantity': quantity,
            'basePrice': 999,
            'excludeFromTotals': excluded,
            'values': {'sale': sale, 'cost': cost, 'delivery': delivery},
          },
        ],
      },
    ],
  });

  test('margin uses configured fields and independent quantity flags', () {
    final item = category(100, 60, quantity: 2, delivery: 10);
    final before = item.toJson();
    expect(controller.marginSummary([item]), (margin: 70.0, percent: 35.0));
    expect(item.toJson(), before);
  });
  test('aggregate margin is weighted by revenue, not averaged percentages', () {
    expect(controller.marginSummary([category(100, 80), category(900, 450)]), (
      margin: 470.0,
      percent: 47.0,
    ));
  });
  test('excluded rows do not contribute', () {
    expect(
      controller.marginSummary([
        category(100, 80),
        category(900, 0, excluded: true),
      ]),
      (margin: 20.0, percent: 20.0),
    );
  });
  test('zero revenue has no percentage; negative margin remains negative', () {
    expect(controller.marginSummary([category(0, 10)]), (
      margin: -10.0,
      percent: null,
    ));
    expect(controller.marginSummary([category(100, 120)]), (
      margin: -20.0,
      percent: -20.0,
    ));
  });
  test('settings round trip through organization and catalog payloads', () {
    final draft = OrganizationOnboardingDraft.initial()
      ..marginSettings = controller.catalog!.marginSettings;
    final json = draft.toJson();
    expect(OrganizationOnboardingDraft.fromJson(json).toJson(), json);
    final catalog = CatalogConfiguration.fromJson({
      'categories': [],
      'dictionaries': [],
      'marginSettings': json['marginSettings'],
    });
    expect(
      catalog.marginSettings.single.toJson(),
      draft.marginSettings.single.toJson(),
    );
    json.remove('marginSettings');
    expect(OrganizationOnboardingDraft.fromJson(json).marginSettings, isEmpty);
  });
  test('unconfigured summaries are hidden', () {
    controller.catalog!.marginSettings.clear();
    expect(controller.marginSummary([category(100, 80)]), isNull);
  });

  testWidgets(
    'internal summary renders margin as money and profitability as percent',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1600, 1000);
      addTearDown(tester.view.reset);
      final type = QuoteProposalTypeDraft.create();
      type.variants.first.categories.add(category(100, 80));
      controller.draft = QuoteDraft(
        kind: QuoteKind.quote,
        title: 'Quote',
        clientId: '',
        executorCompanyId: '',
        selectionMode: 'variant',
        proposalTypes: [type],
      );
      controller.activeTypeId = type.id;
      controller.activeVariantId = type.variants.first.id;
      const config = AppConfig(
        apiBaseUrl: 'https://example.test',
        environment: 'test',
      );
      const board = KanbanBoard(
        id: 'board',
        code: 'quotes',
        name: 'Quotes',
        columns: [],
        transitions: [],
        categories: [],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuoteEditorPage(
              config: config,
              authController: auth,
              board: board,
              controller: controller,
              onBack: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Маржа'), findsWidgets);
      expect(find.text('Маржинальность'), findsWidgets);
      expect(find.text('20,00 %'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
