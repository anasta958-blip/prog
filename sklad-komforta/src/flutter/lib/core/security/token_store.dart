import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Абстракция безопасного хранения refresh-токена на клиентском устройстве.
abstract interface class TokenRepository {
  /// Читает сохранённый refresh-токен, если платформа допускает его хранение.
  Future<String?> readRefreshToken();

  /// Заменяет refresh-токен после серверной ротации.
  Future<void> writeRefreshToken(String? value);

  /// Удаляет локальные данные текущей сессии.
  Future<void> clear();
}

/// Хранит refresh-токен только в системном хранилище нативных платформ.
///
/// Web никогда не записывает refresh-токен в JavaScript storage: браузер
/// использует недоступную скриптам HttpOnly cookie, установленную API.
final class TokenStore implements TokenRepository {
  static const _refreshKey = 'identity.refresh_token';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  /// Читает нативный refresh-токен либо возвращает null для Web.
  @override
  Future<String?> readRefreshToken() =>
      kIsWeb ? Future<String?>.value() : _storage.read(key: _refreshKey);

  /// Сохраняет новый нативный refresh-токен после успешной ротации.
  @override
  Future<void> writeRefreshToken(String? value) async {
    if (kIsWeb || value == null) return;
    await _storage.write(key: _refreshKey, value: value);
  }

  /// Удаляет локальный refresh-токен при завершении текущей сессии.
  @override
  Future<void> clear() async {
    if (!kIsWeb) await _storage.delete(key: _refreshKey);
  }
}
