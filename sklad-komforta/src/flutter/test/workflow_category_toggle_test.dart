import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/models/workflow_specialization.dart';
import 'package:sklad_komforta_app/core/widgets/app_select_field.dart';
import 'package:sklad_komforta_app/core/security/token_store.dart';
import 'package:sklad_komforta_app/features/auth/auth_api.dart';
import 'package:sklad_komforta_app/features/auth/auth_controller.dart';
import 'package:sklad_komforta_app/features/onboarding/onboarding_models.dart';
import 'package:sklad_komforta_app/features/onboarding/organization_onboarding_page.dart';

void main() {
  testWidgets(
    'источник фильтра выбирается из подключённых справочников и сохраняется',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 1600);
      addTearDown(tester.view.reset);
      final auth = AuthController(
        const AppConfig(
          apiBaseUrl: 'https://example.test/api/v1',
          environment: 'test',
        ),
        api: _Gateway(),
        tokens: _Tokens(),
      );
      final draft = OrganizationOnboardingDraft.initial()
        ..categories.add(
          CatalogCategoryDraft(
            clientId: 'equipment',
            name: 'Оборудование',
            sections: [],
            fields: [
              CatalogFieldDraft(
                fieldCode: 'name',
                isVisible: true,
                isRequired: true,
              ),
              CatalogFieldDraft(
                fieldCode: 'custom_vendor',
                label: 'Продавец',
                fieldType: 'dictionary',
                isVisible: true,
                isRequired: false,
              ),
              CatalogFieldDraft(
                fieldCode: 'custom_unused',
                label: 'Не подключено',
                fieldType: 'dictionary',
                isVisible: true,
                isRequired: false,
              ),
            ],
          ),
        )
        ..workflows.add(
          WorkflowDraft(
            code: 'orders',
            name: 'Комплектация',
            specialization: WorkflowSpecialization.order,
            columns: [],
            transitions: [],
            categories: [
              WorkflowCategoryDraft(
                categoryClientId: 'equipment',
                fieldCodes: ['name', 'custom_vendor'],
              ),
            ],
          ),
        );
      OrganizationOnboardingDraft? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrganizationOnboardingPage(
              controller: auth,
              settingsDraft: draft,
              onSettingsSave: (value, {deleteCategoryData = const []}) async {
                saved = value;
                return true;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Поля').first);
      await tester.pumpAndSettle();
      final toggle = find.bySemanticsLabel('Развернуть поля канбана');
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      final selector = find.byKey(
        const ValueKey('supplier-filter-source-orders-equipment'),
      );
      await tester.ensureVisible(selector);
      final field = tester.widget<AppSelectField<String>>(selector);
      expect(field.options.map((item) => item.value), [null, 'custom_vendor']);
      await tester.tap(selector);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, 'Продавец'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<AppSelectField<String>>(selector).value,
        'custom_vendor',
      );
      await tester.tap(find.text('Сохранить изменения').first);
      await tester.pumpAndSettle();
      expect(
        saved!.workflows.single.categories.single.supplierFilterFieldCode,
        'custom_vendor',
      );
      auth.dispose();
    },
  );

  testWidgets(
    'снятие и установка выбора не сворачивают развёрнутую категорию канбана',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 1400);
      addTearDown(tester.view.reset);
      final auth = AuthController(
        const AppConfig(
          apiBaseUrl: 'https://example.test/api/v1',
          environment: 'test',
        ),
        api: _Gateway(),
        tokens: _Tokens(),
      );
      final draft = OrganizationOnboardingDraft.initial()
        ..categories.add(
          CatalogCategoryDraft(
            clientId: 'equipment',
            name: 'Оборудование',
            sections: [],
            fields: [
              CatalogFieldDraft(
                fieldCode: 'name',
                isVisible: true,
                isRequired: true,
              ),
            ],
          ),
        )
        ..workflows.add(
          WorkflowDraft(
            code: 'quote',
            name: 'Коммерческие предложения',
            columns: [],
            transitions: [],
            categories: [
              WorkflowCategoryDraft(
                categoryClientId: 'equipment',
                fieldCodes: ['name'],
              ),
            ],
          ),
        );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrganizationOnboardingPage(
              controller: auth,
              settingsDraft: draft,
              onSettingsSave: (_, {deleteCategoryData = const []}) async =>
                  true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Поля').first);
      await tester.pumpAndSettle();
      final workflowToggle = find.bySemanticsLabel('Развернуть поля канбана');
      await tester.ensureVisible(workflowToggle);
      await tester.tap(workflowToggle);
      await tester.pumpAndSettle();

      const hint = 'Использовать категорию в этом канбане';
      const collapse = 'Свернуть поля категории в канбане';
      await tester.ensureVisible(find.text(hint));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(collapse), findsOneWidget);

      await tester.tap(find.text(hint));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(collapse), findsOneWidget);
      expect(find.textContaining('Категория не используется'), findsOneWidget);

      await tester.tap(find.text(hint));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(collapse), findsOneWidget);
      expect(find.text('Поля на карточке'), findsOneWidget);
      auth.dispose();
    },
  );
}

/// Сеть в этом тесте не нужна: страница настроек работает с переданным черновиком.
final class _Gateway implements AuthGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

final class _Tokens implements TokenRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}
