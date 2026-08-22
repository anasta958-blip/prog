import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/network/http_client_factory.dart'
    if (dart.library.js_interop) 'package:sklad_komforta_app/core/network/http_client_factory_web.dart';

/// Ошибка API со стабильным кодом и безопасным сообщением сервера.
final class AuthApiException implements Exception {
  const AuthApiException(this.code, this.message, [this.statusCode]);
  final String code;
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

/// Контракт Identity API, позволяющий проверять контроллер без реальной сети.
abstract interface class AuthGateway {
  /// Выполняет POST-запрос и возвращает поле data единого API-конверта.
  Future<dynamic> post(
    String path,
    Map<String, dynamic> body, {
    String? accessToken,
  });

  /// Выполняет авторизованный GET-запрос и возвращает поле data.
  Future<dynamic> get(String path, String accessToken);

  /// Выполняет авторизованный DELETE-запрос.
  Future<dynamic> delete(String path, String accessToken);

  /// Освобождает ресурсы транспортного клиента.
  void close();
}

/// Минимальный REST-клиент Identity, общий для всех Flutter-платформ.
final class AuthApi implements AuthGateway {
  AuthApi(this._config) : _client = createPlatformHttpClient();

  final AppConfig _config;
  final http.Client _client;

  /// Выполняет POST и распаковывает единый серверный конверт {ok,data,error}.
  @override
  Future<dynamic> post(
    String path,
    Map<String, dynamic> body, {
    String? accessToken,
  }) async {
    final response = await _client.post(
      Uri.parse('${_config.apiBaseUrl}$path'),
      headers: {
        'Content-Type': 'application/json',
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode(body),
    );
    return _unwrap(response);
  }

  /// Выполняет авторизованный GET для списка активных устройств.
  @override
  Future<dynamic> get(String path, String accessToken) async {
    final response = await _client.get(
      Uri.parse('${_config.apiBaseUrl}$path'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    return _unwrap(response);
  }

  @override
  Future<dynamic> delete(String path, String accessToken) async {
    final response = await _client.delete(
      Uri.parse('${_config.apiBaseUrl}$path'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    return _unwrap(response);
  }

  dynamic _unwrap(http.Response response) {
    final decodedBody = utf8.decode(response.bodyBytes);
    if (response.statusCode == 401 && decodedBody.trim().isEmpty) {
      throw const AuthApiException(
        'session_expired',
        'Сессия истекла. Войдите снова.',
        401,
      );
    }
    final Map<String, dynamic> envelope;
    try {
      envelope = jsonDecode(decodedBody) as Map<String, dynamic>;
    } on FormatException {
      throw AuthApiException(
        'invalid_server_response',
        'Сервер вернул некорректный ответ (HTTP ${response.statusCode}).',
        response.statusCode,
      );
    } on TypeError {
      throw AuthApiException(
        'invalid_server_response',
        'Сервер вернул ответ неизвестного формата (HTTP ${response.statusCode}).',
        response.statusCode,
      );
    }
    if (envelope['ok'] != true) {
      final error = envelope['error'] as Map<String, dynamic>?;
      throw AuthApiException(
        error?['code'] as String? ?? 'request_failed',
        error?['message'] as String? ?? 'Не удалось выполнить запрос.',
        response.statusCode,
      );
    }
    return envelope['data'];
  }

  /// Освобождает сокеты при уничтожении auth controller.
  @override
  void close() => _client.close();
}
