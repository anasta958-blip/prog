import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/network/api_exception.dart';
import 'package:sklad_komforta_app/core/network/api_response_decoder.dart';
import 'package:sklad_komforta_app/features/auth/auth_controller.dart';
import 'package:sklad_komforta_app/features/onboarding/onboarding_models.dart';
import 'package:sklad_komforta_app/features/onboarding/organization_onboarding_page.dart';

void main() {
  test('API validation preserves target and supports old error envelopes', () {
    for (final target in [null, 'rule:broken']) {
      final response = http.Response(
        jsonEncode({
          'ok': false,
          'error': {
            'code': 'invalid',
            'message': 'Invalid formula',
            'target': ?target,
          },
        }),
        400,
      );
      expect(
        () => decodeApiResponse(response),
        throwsA(isA<ApiException>().having((e) => e.target, 'target', target)),
      );
    }
  });

  testWidgets(
    'failed save opens exact rule and keeps error visible outside scroll',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 850);
      addTearDown(tester.view.reset);
      final auth = AuthController(
        const AppConfig(
          apiBaseUrl: 'https://example.test',
          environment: 'test',
        ),
      );
      addTearDown(auth.dispose);
      final draft = OrganizationOnboardingDraft.initial();
      draft.categories.add(
        CatalogCategoryDraft(
          clientId: 'category',
          name: 'Категория',
          sections: [],
          fields: [],
        ),
      );
      for (var index = 0; index < 16; index++) {
        draft.rules.add(
          CalculationRuleDraft(
            clientId: 'rule-$index',
            name: 'Одинаковое имя',
            categoryClientId: 'category',
            eventType: 'card_saving',
            isEnabled: true,
            actions: [
              RuleActionDraft(actionType: 'block_save', message: 'Проверка'),
            ],
          ),
        );
      }
      String? error;
      const message = 'В формуле не выбрано поле.';
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => OrganizationOnboardingPage(
              controller: auth,
              settingsDraft: draft,
              settingsError: error,
              settingsErrorTarget: error == null ? null : 'rule:rule-9',
              onSettingsSave: (_, {deleteCategoryData = const []}) async {
                setState(() => error = message);
                return false;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Правила и расчёты').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Сохранить изменения'));
      await tester.tap(find.text('Сохранить изменения'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      final broken = find.byKey(const ValueKey('rule-9'));
      final other = find.byKey(const ValueKey('rule-8'));
      expect(
        find.descendant(of: broken, matching: find.text('Событие')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: other, matching: find.text('Событие')),
        findsNothing,
      );
      expect(
        find.descendant(of: broken, matching: find.text(message)),
        findsOneWidget,
      );
      final notice = find.byKey(const ValueKey('settings-validation-notice'));
      expect(notice, findsOneWidget);
      expect(tester.getRect(notice).bottom, lessThanOrEqualTo(850));
      expect(tester.getRect(broken).top, greaterThanOrEqualTo(0));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Закрыть сообщение'));
      await tester.pumpAndSettle();
      expect(notice, findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
