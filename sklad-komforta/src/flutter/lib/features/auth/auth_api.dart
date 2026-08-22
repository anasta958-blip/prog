import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/network/api_exception.dart';
import 'package:sklad_komforta_app/core/network/api_response_decoder.dart';
import 'package:sklad_komforta_app/core/network/http_client_factory.dart'
    if (dart.library.js_interop) 'package:sklad_komforta_app/core/network/http_client_factory_web.dart';

/// Совместимое имя ошибки auth-слоя; реализация едина для всех REST-модулей.
typedef AuthApiException = ApiException;

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
    return decodeApiResponse(response);
  }

  /// Выполняет авторизованный GET для списка активных устройств.
  @override
  Future<dynamic> get(String path, String accessToken) async {
    final response = await _client.get(
      Uri.parse('${_config.apiBaseUrl}$path'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    return decodeApiResponse(response);
  }

  @override
  Future<dynamic> delete(String path, String accessToken) async {
    final response = await _client.delete(
      Uri.parse('${_config.apiBaseUrl}$path'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    return decodeApiResponse(response);
  }

  /// Освобождает сокеты при уничтожении auth controller.
  @override
  void close() => _client.close();
}
