import 'package:flutter/foundation.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/security/token_store.dart';
import 'package:sklad_komforta_app/features/auth/auth_api.dart';

/// Экраны последовательного auth/onboarding сценария.
enum AuthStage {
  loading,
  login,
  changePassword,
  setupTotp,
  verifyTotp,
  recoveryCodes,
  organization,
  ready,
}

/// Управляет только состоянием авторизации и не содержит UI-разметки.
final class AuthController extends ChangeNotifier {
  /// Создаёт production-контроллер либо принимает тестовые adapter-ы.
  AuthController(AppConfig config, {AuthGateway? api, TokenRepository? tokens})
    : _api = api ?? AuthApi(config),
      _tokens = tokens ?? TokenStore();

  final AuthGateway _api;
  final TokenRepository _tokens;
  AuthStage stage = AuthStage.loading;
  String? error;
  String? challengeToken;
  String? totpSecret;
  String? otpAuthUri;
  String? accessToken;
  List<String> recoveryCodes = const [];
  List<Map<String, dynamic>> sessions = const [];
  bool busy = false;

  /// Восстанавливает нативную сессию из secure storage или Web-сессию из cookie.
  Future<void> initialize() async {
    try {
      final refresh = await _tokens.readRefreshToken();
      final data =
          await _api.post('/auth/refresh', {'refreshToken': refresh ?? ''})
              as Map<String, dynamic>;
      await _acceptTokens(data);
      stage = data['organizationId'] == null
          ? AuthStage.organization
          : AuthStage.ready;
      if (stage == AuthStage.ready) await loadSessions();
    } catch (_) {
      await _tokens.clear();
      stage = AuthStage.login;
    }
    notifyListeners();
  }

  /// Проверяет логин/пароль и открывает обязательный сервером следующий шаг.
  Future<void> login(String login, String password) => _run(() async {
    final data =
        await _api.post('/auth/login', {
              'login': login,
              'password': password,
              'deviceType': _deviceType,
              'deviceName': _deviceName,
            })
            as Map<String, dynamic>;
    challengeToken = data['challengeToken'] as String?;
    stage = _stageFromServer(data['step'] as int);
    if (stage == AuthStage.setupTotp) await beginTotpSetup();
  });

  /// Меняет одноразовый пароль и немедленно запускает настройку TOTP.
  Future<void> changePassword(String password) => _run(() async {
    final data =
        await _api.post('/auth/initial-password', {
              'challengeToken': challengeToken,
              'newPassword': password,
            })
            as Map<String, dynamic>;
    challengeToken = data['challengeToken'] as String?;
    stage = AuthStage.setupTotp;
    await beginTotpSetup();
  });

  /// Получает Base32-секрет и otpauth URI текущего challenge.
  Future<void> beginTotpSetup() async {
    final data =
        await _api.post('/auth/totp/setup', {'challengeToken': challengeToken})
            as Map<String, dynamic>;
    totpSecret = data['secret'] as String?;
    otpAuthUri = data['otpAuthUri'] as String?;
  }

  /// Подтверждает TOTP; первичная настройка также показывает recovery-коды.
  Future<void> verifyTotp(String code) => _run(() async {
    final setup = stage == AuthStage.setupTotp;
    final data =
        await _api.post(setup ? '/auth/totp/confirm' : '/auth/totp/verify', {
              'challengeToken': challengeToken,
              'code': code,
            })
            as Map<String, dynamic>;
    final tokens = data['tokens'] as Map<String, dynamic>;
    await _acceptTokens(tokens);
    recoveryCodes =
        (data['recoveryCodes'] as List<dynamic>?)?.cast<String>() ?? const [];
    if (recoveryCodes.isNotEmpty) {
      stage = AuthStage.recoveryCodes;
    } else {
      stage = data['onboardingRequired'] == true
          ? AuthStage.organization
          : AuthStage.ready;
      if (stage == AuthStage.ready) await loadSessions();
    }
  });

  /// Расходует один recovery-код вместо TOTP и завершает тот же login challenge.
  Future<void> verifyRecoveryCode(String code) => _run(() async {
    final data =
        await _api.post('/auth/recovery/verify', {
              'challengeToken': challengeToken,
              'recoveryCode': code,
            })
            as Map<String, dynamic>;
    final tokens = data['tokens'] as Map<String, dynamic>;
    await _acceptTokens(tokens);
    stage = data['onboardingRequired'] == true
        ? AuthStage.organization
        : AuthStage.ready;
    if (stage == AuthStage.ready) await loadSessions();
  });

  /// Продолжает после однократного показа recovery-кодов.
  void continueAfterRecoveryCodes() {
    recoveryCodes = const [];
    stage = accessToken == null ? AuthStage.login : AuthStage.organization;
    notifyListeners();
  }

  /// Создаёт первую организацию и заменяет access token на tenant-aware JWT.
  Future<void> createOrganization(String name) => _run(() async {
    final data =
        await _api.post('/identity/organization', {
              'name': name,
            }, accessToken: accessToken)
            as Map<String, dynamic>;
    accessToken = data['accessToken'] as String;
    stage = AuthStage.ready;
    await loadSessions();
  });

  /// Загружает активные устройства без refresh-токенов и хешей.
  Future<void> loadSessions() async {
    if (accessToken == null) return;
    final data =
        await _api.get('/identity/sessions', accessToken!) as List<dynamic>;
    sessions = data.cast<Map<String, dynamic>>();
  }

  /// Отзывает выбранное устройство и обновляет список без выхода текущего.
  Future<void> revokeSession(String sessionId) => _run(() async {
    if (accessToken == null) return;
    await _api.delete('/identity/sessions/$sessionId', accessToken!);
    await loadSessions();
  });

  /// Отзывает все устройства, кроме текущего, и обновляет список.
  Future<void> revokeOtherSessions() => _run(() async {
    if (accessToken == null) return;
    await _api.delete('/identity/sessions', accessToken!);
    await loadSessions();
  });

  /// Завершает текущую серверную сессию и очищает нативный refresh-токен.
  Future<void> logout() => _run(() async {
    if (accessToken != null) {
      await _api.post('/identity/logout', const {}, accessToken: accessToken);
    }
    await _tokens.clear();
    accessToken = null;
    sessions = const [];
    stage = AuthStage.login;
  });

  Future<void> _acceptTokens(Map<String, dynamic> data) async {
    accessToken = data['accessToken'] as String;
    await _tokens.writeRefreshToken(data['refreshToken'] as String?);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await action();
    } on AuthApiException catch (exception) {
      error = exception.message;
    } catch (_) {
      error = 'Не удалось связаться с сервером. Проверьте подключение.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  static AuthStage _stageFromServer(int step) => switch (step) {
    1 => AuthStage.changePassword,
    2 => AuthStage.setupTotp,
    3 => AuthStage.verifyTotp,
    _ => AuthStage.login,
  };

  int get _deviceType {
    if (kIsWeb) return 1;
    return switch (defaultTargetPlatform) {
      TargetPlatform.windows => 2,
      TargetPlatform.android => 3,
      TargetPlatform.iOS => 4,
      TargetPlatform.macOS => 5,
      _ => 2,
    };
  }

  String get _deviceName => kIsWeb ? 'Web-браузер' : defaultTargetPlatform.name;

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }
}
