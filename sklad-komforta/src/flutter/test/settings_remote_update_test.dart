import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/security/token_store.dart';
import 'package:sklad_komforta_app/features/auth/auth_api.dart';
import 'package:sklad_komforta_app/features/auth/auth_controller.dart';
import 'package:sklad_komforta_app/features/onboarding/onboarding_models.dart';
import 'package:sklad_komforta_app/features/onboarding/organization_onboarding_page.dart';

void main() {
  testWidgets('чужое изменение настроек не затирает несохранённые правки формы', (
    tester,
  ) async {
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
    final server = ValueNotifier(_draft(selected: true));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder(
            valueListenable: server,
            builder: (context, draft, _) => OrganizationOnboardingPage(
              controller: auth,
              settingsDraft: draft,
              onSettingsSave: (_, {deleteCategoryData = const []}) async =>
                  true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Поля').first);
    await tester.pumpAndSettle();
    Future<void> expandWorkflow() async {
      final toggle = find.bySemanticsLabel('Развернуть поля канбана');
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
    }

    await expandWorkflow();
    const hint = 'Использовать категорию в этом канбане';
    const unused = 'Категория не используется';

    // Несохранённая правка: категория снята с канбана.
    await tester.ensureVisible(find.text(hint));
    await tester.tap(find.text(hint));
    await tester.pumpAndSettle();
    expect(find.textContaining(unused), findsOneWidget);

    // Другой пользователь сохранил настройки: правка остаётся, есть предупреждение.
    server.value = _draft(selected: true, email: 'other@example.test');
    await tester.pumpAndSettle();
    expect(find.textContaining(unused), findsOneWidget);
    expect(
      find.textContaining('Настройки изменил другой пользователь'),
      findsOneWidget,
    );

    auth.dispose();
  });

  testWidgets('без несохранённых правок форма принимает чужие настройки', (
    tester,
  ) async {
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
    final server = ValueNotifier(_draft(selected: true));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder(
            valueListenable: server,
            builder: (context, draft, _) => OrganizationOnboardingPage(
              controller: auth,
              settingsDraft: draft,
              onSettingsSave: (_, {deleteCategoryData = const []}) async =>
                  true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Поля').first);
    await tester.pumpAndSettle();
    Future<void> expandWorkflow() async {
      final toggle = find.bySemanticsLabel('Развернуть поля канбана');
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
    }

    await expandWorkflow();

    // Правок нет: форма сразу показывает версию другого пользователя.
    server.value = _draft(selected: false, email: 'other@example.test');
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Настройки изменил другой пользователь'),
      findsNothing,
    );
    await expandWorkflow();
    final select = tester.widget<CheckboxListTile>(
      find.byKey(const Key('workflow-category-select-quote:equipment')),
    );
    expect(select.value, isFalse);
    expect(find.text('Поля на карточке'), findsNothing);
    auth.dispose();
  });
}

OrganizationOnboardingDraft _draft({required bool selected, String? email}) {
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
          if (selected)
            WorkflowCategoryDraft(
              categoryClientId: 'equipment',
              fieldCodes: ['name'],
            ),
        ],
      ),
    );
  draft.company.email = email;
  return draft;
}

/// Сеть в этом тесте не нужна: страница работает с переданным черновиком.
final class _Gateway implements AuthGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

final class _Tokens implements TokenRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}
