import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sklad_komforta_app/core/network/api_exception.dart';

/// Распаковывает единый серверный конверт `{ok,data,error}` для всех модулей.
dynamic decodeApiResponse(http.Response response) {
  final decodedBody = utf8.decode(response.bodyBytes);
  if (response.statusCode == 401 && decodedBody.trim().isEmpty) {
    throw const ApiException(
      'session_expired',
      'Сессия истекла. Войдите снова.',
      401,
    );
  }
  try {
    final envelope = jsonDecode(decodedBody) as Map<String, dynamic>;
    if (envelope['ok'] == true) return envelope['data'];
    final error = envelope['error'] as Map<String, dynamic>?;
    throw ApiException(
      error?['code'] as String? ?? 'request_failed',
      error?['message'] as String? ?? 'Не удалось выполнить запрос.',
      response.statusCode,
      error?['target'] as String?,
    );
  } on ApiException {
    rethrow;
  } on Object {
    throw ApiException(
      'invalid_server_response',
      'Сервер вернул некорректный ответ (HTTP ${response.statusCode}).',
      response.statusCode,
    );
  }
}
