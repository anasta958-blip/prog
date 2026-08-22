import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/security/token_store.dart';
import 'package:sklad_komforta_app/features/auth/auth_api.dart';
import 'package:sklad_komforta_app/features/auth/auth_controller.dart';
import 'package:sklad_komforta_app/features/company/company_api.dart';
import 'package:sklad_komforta_app/features/company/company_controller.dart';
import 'package:sklad_komforta_app/features/company/company_page.dart';
import 'package:sklad_komforta_app/features/onboarding/onboarding_models.dart';

void main() {
  const config = AppConfig(
    apiBaseUrl: 'https://api.example.test/api/v1',
    environment: 'test',
  );

  test(
    'профиль компании загружается и сохраняется через общий токен',
    () async {
      final gateway = _MemoryCompanyGateway();
      final auth = AuthController(
        config,
        api: _NoopAuthGateway(),
        tokens: _MemoryTokenRepository(),
      )..accessToken = 'access-token';
      final controller = CompanyController(config, auth, api: gateway);

      await controller.initialize();
      expect(controller.profile?.organizationName, 'Склад Комфорта');
      expect(controller.configuration, isNotNull);

      controller.profile!.organizationName = 'Новая компания';
      final result = await controller.save();

      expect(result, isTrue);
      expect(gateway.saved?.organizationName, 'Новая компания');
      expect(controller.saved, isTrue);
      expect(controller.error, isNull);

      final configurationSaved = await controller.saveConfiguration(
        controller.configuration!,
      );
      expect(configurationSaved, isTrue);
      expect(gateway.savedConfiguration, isNotNull);

      controller.dispose();
      auth.dispose();
    },
  );

  testWidgets('раздел компании открывает полную конфигурацию организации', (
    tester,
  ) async {
    final gateway = _MemoryCompanyGateway();
    final auth = AuthController(
      config,
      api: _NoopAuthGateway(),
      tokens: _MemoryTokenRepository(),
    )..accessToken = 'access-token';
    final controller = CompanyController(config, auth, api: gateway);
    await controller.initialize();

    await tester.pumpWidget(
      MaterialApp(home: CompanyPage(controller: controller)),
    );

    expect(find.text('Настройки организации'), findsOneWidget);
    final continueButton = find.text('Сохранить и продолжить');
    await tester.ensureVisible(continueButton);
    await tester.tap(continueButton);
    await tester.pumpAndSettle();
    expect(find.text('2. Канбаны'), findsOneWidget);
    expect(gateway.savedConfiguration, isNotNull);
    expect(gateway.savedConfiguration!.currentStep, 8);

    controller.dispose();
    auth.dispose();
  });
}

final class _MemoryCompanyGateway implements CompanyGateway {
  CompanyProfileDraft? saved;
  OrganizationOnboardingDraft? savedConfiguration;

  @override
  Future<CompanyProfileDraft> getProfile(String accessToken) async =>
      CompanyProfileDraft(organizationName: 'Склад Комфорта')
        ..companyType = 'ООО';

  @override
  Future<OrganizationOnboardingDraft> getConfiguration(
    String accessToken,
  ) async {
    final draft = OrganizationOnboardingDraft.initial();
    draft.company.organizationName = 'Склад Комфорта';
    draft.company.companyType = 'ООО';
    return draft;
  }

  @override
  Future<CompanyProfileDraft> updateProfile(
    String accessToken,
    CompanyProfileDraft profile,
  ) async {
    saved = profile;
    return CompanyProfileDraft.fromJson(profile.toJson());
  }

  @override
  Future<OrganizationOnboardingDraft> updateConfiguration(
    String accessToken,
    OrganizationOnboardingDraft draft,
  ) async {
    savedConfiguration = draft;
    return OrganizationOnboardingDraft.fromJson(draft.toJson());
  }

  @override
  void close() {}
}

final class _NoopAuthGateway implements AuthGateway {
  @override
  Future<dynamic> delete(String path, String accessToken) async => null;
  @override
  Future<dynamic> get(String path, String accessToken) async => null;
  @override
  Future<dynamic> post(
    String path,
    Map<String, dynamic> body, {
    String? accessToken,
  }) async => null;
  @override
  void close() {}
}

final class _MemoryTokenRepository implements TokenRepository {
  @override
  Future<void> clear() async {}
  @override
  Future<String?> readRefreshToken() async => null;
  @override
  Future<void> writeRefreshToken(String? value) async {}
}
