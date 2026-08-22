import 'package:flutter/foundation.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/network/api_exception.dart';
import 'package:sklad_komforta_app/features/auth/auth_controller.dart';
import 'package:sklad_komforta_app/features/company/company_api.dart';
import 'package:sklad_komforta_app/features/onboarding/onboarding_models.dart';

/// Состояние рабочего пространства компании и безопасное обновление токена.
final class CompanyController extends ChangeNotifier {
  CompanyController(AppConfig config, this._auth, {CompanyGateway? api})
    : _api = api ?? CompanyApi(config),
      _ownsApi = api == null;

  final AuthController _auth;
  final CompanyGateway _api;
  final bool _ownsApi;

  /// Авторизационный контекст нужен общему редактору onboarding-настроек.
  AuthController get authController => _auth;

  CompanyProfileDraft? profile;
  OrganizationOnboardingDraft? configuration;
  bool loading = false;
  bool saving = false;
  String? error;
  bool saved = false;

  Future<void> initialize() async {
    if (loading || configuration != null) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      configuration = await _auth.executeAuthorized(_api.getConfiguration);
      profile = configuration!.company;
    } on ApiException catch (exception) {
      error = exception.message;
    } on Object {
      error = 'Не удалось загрузить данные компании. Проверьте подключение.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void markChanged() {
    if (saved) {
      saved = false;
      notifyListeners();
    }
  }

  Future<bool> save() async {
    final value = profile;
    if (value == null || saving) return false;
    saving = true;
    saved = false;
    error = null;
    notifyListeners();
    try {
      profile = await _auth.executeAuthorized(
        (token) => _api.updateProfile(token, value),
      );
      saved = true;
      return true;
    } on ApiException catch (exception) {
      error = exception.message;
      return false;
    } on Object {
      error = 'Не удалось сохранить данные компании. Проверьте подключение.';
      return false;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  Future<bool> saveConfiguration(OrganizationOnboardingDraft draft) async {
    if (saving) return false;
    saving = true;
    saved = false;
    error = null;
    notifyListeners();
    try {
      configuration = await _auth.executeAuthorized(
        (token) => _api.updateConfiguration(token, draft),
      );
      profile = configuration!.company;
      saved = true;
      return true;
    } on ApiException catch (exception) {
      error = exception.message;
      return false;
    } on Object {
      error =
          'Не удалось сохранить настройки организации. Проверьте подключение.';
      return false;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_ownsApi) _api.close();
    super.dispose();
  }
}
