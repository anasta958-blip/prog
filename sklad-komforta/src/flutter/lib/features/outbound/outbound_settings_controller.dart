import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:sklad_komforta_app/core/network/api_exception.dart';
import 'package:sklad_komforta_app/features/auth/auth_controller.dart';
import 'package:sklad_komforta_app/features/outbound/outbound_api.dart';
import 'package:sklad_komforta_app/features/outbound/outbound_models.dart';

/// Состояние раздела «Внешняя отправка»: загрузка, правки, сохранение и
/// проверка способов отправки.
final class OutboundSettingsController extends ChangeNotifier {
  OutboundSettingsController(this._auth, {OutboundGateway? gateway})
    : _gateway = gateway ?? OutboundApi(_auth.config),
      _ownsGateway = gateway == null;

  final AuthController _auth;
  final OutboundGateway _gateway;
  final bool _ownsGateway;

  /// Редактируемая копия настроек.
  OutboundSettingsModel settings = OutboundSettingsModel();
  String _savedJson = jsonEncode(OutboundSettingsModel().toJson());

  /// Растёт при каждой загрузке и сохранении: поля формы пересоздаются со
  /// значениями сервера.
  int revision = 0;

  bool loaded = false;
  bool loading = false;
  bool saving = false;

  /// Нет права `outbound.settings.manage`.
  bool forbidden = false;

  /// Способ, проверка которого идёт сейчас.
  OutboundChannel? testing;
  String? error;
  String? message;
  bool _disposed = false;

  /// Есть несохранённые правки (включая введённые токен или пароль).
  bool get dirty => jsonEncode(settings.toJson()) != _savedJson;

  bool get busy => loading || saving || testing != null;

  /// Загружает настройки после текущего кадра: безопасно вызывать из build.
  void scheduleLoad() => SchedulerBinding.instance.addPostFrameCallback((_) {
    if (!_disposed) load();
  });

  /// Загружает настройки; без [force] — только при первом обращении.
  Future<void> load({bool force = false}) async {
    if (loading || (loaded && !force)) return;
    loading = true;
    error = null;
    _notify();
    try {
      _accept(await _auth.executeAuthorized(_gateway.getSettings));
      forbidden = false;
      loaded = true;
    } on ApiException catch (exception) {
      forbidden = exception.statusCode == 403;
      error = forbidden ? null : exception.message;
    } on Object {
      error = 'Не удалось загрузить настройки отправки. Проверьте подключение.';
    } finally {
      loading = false;
      _notify();
    }
  }

  /// Перечитывает настройки после изменения другим пользователем, если в
  /// форме нет собственных несохранённых правок.
  Future<void> refreshFromServer() async {
    if (!loaded || dirty || busy) return;
    await load(force: true);
  }

  /// Уведомляет форму о правке поля.
  void changed() => _notify();

  /// Сохраняет настройки. Возвращает `true` при успехе.
  Future<bool> save() async {
    if (saving) return false;
    saving = true;
    error = null;
    message = null;
    _notify();
    try {
      _accept(
        await _auth.executeAuthorized(
          (token) => _gateway.saveSettings(token, settings),
        ),
      );
      message = 'Настройки отправки сохранены.';
      return true;
    } on ApiException catch (exception) {
      error = exception.message;
      return false;
    } on Object {
      error = 'Не удалось сохранить настройки. Проверьте подключение.';
      return false;
    } finally {
      saving = false;
      _notify();
    }
  }

  /// Отменяет несохранённые правки.
  void discard() {
    _accept(
      OutboundSettingsModel.fromJson(
        jsonDecode(_savedResponseJson) as Map<String, dynamic>,
      ),
    );
    _notify();
  }

  /// Отправляет тестовое сообщение сохранённым способом.
  Future<void> test(OutboundChannel channel) async {
    if (busy) return;
    if (dirty) {
      error = 'Сначала сохраните настройки, затем проверьте отправку.';
      _notify();
      return;
    }
    testing = channel;
    error = null;
    message = null;
    _notify();
    try {
      final destination = await _auth.executeAuthorized(
        (token) => _gateway.test(token, channel),
      );
      message = channel == OutboundChannel.telegram
          ? 'Тестовое сообщение отправлено: $destination.'
          : 'Тестовое письмо отправлено на $destination.';
    } on ApiException catch (exception) {
      error = exception.message;
    } on Object {
      error = 'Не удалось выполнить проверку. Проверьте подключение.';
    } finally {
      testing = null;
      _notify();
    }
  }

  String _savedResponseJson = jsonEncode(
    OutboundSettingsModel().toResponseJson(),
  );

  void _accept(OutboundSettingsModel value) {
    settings = value;
    _savedJson = jsonEncode(value.toJson());
    _savedResponseJson = jsonEncode(value.toResponseJson());
    revision++;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_ownsGateway) _gateway.close();
    super.dispose();
  }
}
