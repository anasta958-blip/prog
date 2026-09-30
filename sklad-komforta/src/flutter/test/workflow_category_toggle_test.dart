import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/security/token_store.dart';
import 'package:sklad_komforta_app/features/auth/auth_api.dart';
import 'package:sklad_komforta_app/features/auth/auth_controller.dart';
import 'package:sklad_komforta_app/features/onboarding/onboarding_models.dart';
import 'package:sklad_komforta_app/features/onboarding/organization_onboarding_page.dart';

void main() {
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
