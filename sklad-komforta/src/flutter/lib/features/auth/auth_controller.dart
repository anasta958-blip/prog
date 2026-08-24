import 'package:flutter/foundation.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/security/token_store.dart';
import 'package:sklad_komforta_app/features/auth/auth_api.dart';
import 'package:sklad_komforta_app/features/onboarding/onboarding_models.dart';

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
  AuthController(this.config, {AuthGateway? api, TokenRepository? tokens})
    : _api = api ?? AuthApi(config),
      _tokens = tokens ?? TokenStore();

  final AuthGateway _api;
  final AppConfig config;
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
  bool organizationProvisioned = false;
  OrganizationOnboardingDraft? onboardingDraft;
  Future<void>? _refreshInFlight;

  /// Восстанавливает нативную сессию из secure storage или Web-сессию из cookie.
  Future<void> initialize() async {
    try {
      final refresh = await _tokens.readRefreshToken();
      final data =
          await _api.post('/auth/refresh', {'refreshToken': refresh ?? ''})
              as Map<String, dynamic>;
      await _acceptTokens(data);
      organizationProvisioned = data['organizationId'] != null;
      if (organizationProvisioned) {
        await loadOnboarding();
      } else {
        onboardingDraft = OrganizationOnboardingDraft.initial();
        stage = AuthStage.organization;
      }
    } on AuthApiException catch (exception) {
      if (exception.statusCode == 401) {
        await _tokens.clear();
      } else {
        error = exception.message;
      }
      stage = AuthStage.login;
    } catch (_) {
      error = 'Не удалось связаться с сервером. Повторите попытку позже.';
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
    organizationProvisioned = tokens['organizationId'] != null;
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
    organizationProvisioned = tokens['organizationId'] != null;
    stage = data['onboardingRequired'] == true
        ? AuthStage.organization
        : AuthStage.ready;
    if (stage == AuthStage.ready) await loadSessions();
  });

  /// Продолжает после однократного показа recovery-кодов.
  Future<void> continueAfterRecoveryCodes() async {
    if (accessToken == null) {
      recoveryCodes = const [];
      stage = AuthStage.login;
      notifyListeners();
      return;
    }
    if (organizationProvisioned) {
      await _run(loadOnboarding);
      if (error == null) {
        recoveryCodes = const [];
        notifyListeners();
      }
    } else {
      recoveryCodes = const [];
      onboardingDraft = OrganizationOnboardingDraft.initial();
      stage = AuthStage.organization;
      notifyListeners();
    }
  }

  /// Сохраняет текущий шаг; при первом вызове предварительно создаёт tenant.
  Future<void> saveOnboardingStep(OrganizationOnboardingDraft draft) =>
      _run(() async {
        var draftToSave = draft;
        if (!organizationProvisioned) {
          final company = draft.company;
          final data =
              await _withValidAccessToken(
                    (token) => _api.post('/identity/organization', {
                      'name': draft.company.organizationName,
                    }, accessToken: token),
                  )
                  as Map<String, dynamic>;
          accessToken = data['accessToken'] as String;
          organizationProvisioned = true;
          final initialState =
              await _withValidAccessToken(
                    (token) => _api.get('/onboarding/', token),
                  )
                  as Map<String, dynamic>;
          draftToSave =
              OrganizationOnboardingDraft.fromJson(
                  initialState['draft'] as Map<String, dynamic>,
                )
                ..company = company
                ..currentStep = draft.currentStep;
        }
        final data =
            await _withValidAccessToken(
                  (token) => _api.post(
                    '/onboarding/draft',
                    draftToSave.toJson(),
                    accessToken: token,
                  ),
                )
                as Map<String, dynamic>;
        onboardingDraft = OrganizationOnboardingDraft.fromJson(
          data['draft'] as Map<String, dynamic>,
        );
        stage = AuthStage.organization;
      });

  /// Загружает серверный прогресс и открывает рабочее приложение после активации.
  Future<void> loadOnboarding() async {
    if (accessToken == null) return;
    final data =
        await _withValidAccessToken((token) => _api.get('/onboarding/', token))
            as Map<String, dynamic>;
    onboardingDraft = OrganizationOnboardingDraft.fromJson(
      data['draft'] as Map<String, dynamic>,
    );
    if (data['isCompleted'] == true) {
      stage = AuthStage.ready;
      await loadSessions();
    } else {
      stage = AuthStage.organization;
    }
  }

  /// Материализует проверенный черновик и завершает первичную настройку.
  Future<void> activateOrganization() => _run(() async {
    await _withValidAccessToken(
      (token) =>
          _api.post('/onboarding/activate', const {}, accessToken: token),
    );
    stage = AuthStage.ready;
    await loadSessions();
  });

  /// Загружает активные устройства без refresh-токенов и хешей.
  Future<void> loadSessions() async {
    if (accessToken == null) return;
    final data =
        await _withValidAccessToken(
              (token) => _api.get('/identity/sessions', token),
            )
            as List<dynamic>;
    sessions = data.cast<Map<String, dynamic>>();
  }

  /// Отзывает выбранное устройство и обновляет список без выхода текущего.
  Future<void> revokeSession(String sessionId) => _run(() async {
    if (accessToken == null) return;
    await _withValidAccessToken(
      (token) => _api.delete('/identity/sessions/$sessionId', token),
    );
    await loadSessions();
  });

  /// Отзывает все устройства, кроме текущего, и обновляет список.
  Future<void> revokeOtherSessions() => _run(() async {
    if (accessToken == null) return;
    await _withValidAccessToken(
      (token) => _api.delete('/identity/sessions', token),
    );
    await loadSessions();
  });

  /// Завершает текущую серверную сессию и очищает нативный refresh-токен.
  Future<void> logout() => _run(() async {
    if (accessToken != null) {
      await _withValidAccessToken(
        (token) => _api.post('/identity/logout', const {}, accessToken: token),
      );
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

  /// Повторяет защищённый запрос один раз после ротации истёкшего access token.
  /// Refresh-токен остаётся в secure storage, а Web передаёт HttpOnly cookie.
  Future<dynamic> _withValidAccessToken(
    Future<dynamic> Function(String accessToken) request,
  ) async {
    final currentToken = accessToken;
    if (currentToken == null) {
      throw const AuthApiException(
        'session_expired',
        'Сессия истекла. Войдите снова.',
        401,
      );
    }
    try {
      return await request(currentToken);
    } on AuthApiException catch (exception) {
      if (exception.statusCode != 401) rethrow;
      if (accessToken == currentToken) {
        await _refreshAccessToken();
      }
      return request(accessToken!);
    }
  }

  /// Выполняет запрос бизнес-модуля с текущим access token и один раз
  /// повторяет его после безопасной ротации refresh-сессии.
  Future<T> executeAuthorized<T>(
    Future<T> Function(String accessToken) request,
  ) async {
    try {
      return await _withValidAccessToken(request) as T;
    } on AuthApiException catch (exception) {
      if (exception.statusCode == 401) {
        await _tokens.clear();
        accessToken = null;
        sessions = const [];
        stage = AuthStage.login;
        error = 'Сессия истекла. Войдите снова.';
        notifyListeners();
      }
      rethrow;
    }
  }

  /// Ротирует refresh-сессию без изменения текущего экрана приложения.
  Future<void> _refreshAccessToken() {
    final activeRefresh = _refreshInFlight;
    if (activeRefresh != null) return activeRefresh;

    final refresh = _performRefresh();
    _refreshInFlight = refresh;
    return refresh.whenComplete(() {
      if (identical(_refreshInFlight, refresh)) {
        _refreshInFlight = null;
      }
    });
  }

  /// Выполняет единственную фактическую ротацию refresh-токена.
  Future<void> _performRefresh() async {
    final refresh = await _tokens.readRefreshToken();
    final data =
        await _api.post('/auth/refresh', {'refreshToken': refresh ?? ''})
            as Map<String, dynamic>;
    await _acceptTokens(data);
    organizationProvisioned = data['organizationId'] != null;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await action();
    } on AuthApiException catch (exception) {
      if (exception.statusCode == 401) {
        await _tokens.clear();
        accessToken = null;
        sessions = const [];
        stage = AuthStage.login;
        error = 'Сессия истекла. Войдите снова.';
      } else {
        error = exception.message;
      }
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
