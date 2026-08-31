import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/network/api_response_decoder.dart';
import 'package:sklad_komforta_app/core/network/http_client_factory.dart'
    if (dart.library.js_interop) 'package:sklad_komforta_app/core/network/http_client_factory_web.dart';
import 'package:sklad_komforta_app/features/quotes/quote_models.dart';

/// Заменяемый transport специализированной части КП/ПКП.
abstract interface class QuoteGateway {
  Future<QuoteDraft> getQuote(
    String accessToken,
    String boardId,
    String cardId,
  );

  Future<QuoteDraft> saveQuote(
    String accessToken,
    String boardId,
    String cardId,
    QuoteDraft draft,
  );

  void close();
}

/// REST-клиент атомарного чтения и сохранения дерева предложения.
final class QuoteApi implements QuoteGateway {
  QuoteApi(this._config) : _client = createPlatformHttpClient();

  final AppConfig _config;
  final http.Client _client;

  @override
  Future<QuoteDraft> getQuote(
    String accessToken,
    String boardId,
    String cardId,
  ) async => QuoteDraft.fromJson(
    await _send('GET', boardId, cardId, accessToken) as Map<String, dynamic>,
  );

  @override
  Future<QuoteDraft> saveQuote(
    String accessToken,
    String boardId,
    String cardId,
    QuoteDraft draft,
  ) async => QuoteDraft.fromJson(
    await _send('PUT', boardId, cardId, accessToken, body: draft.toJson())
        as Map<String, dynamic>,
  );

  Future<dynamic> _send(
    String method,
    String boardId,
    String cardId,
    String accessToken, {
    Map<String, dynamic>? body,
  }) async {
    final path =
        '/kanbans/${Uri.encodeComponent(boardId)}/cards/'
        '${Uri.encodeComponent(cardId)}/quote/';
    final request =
        http.Request(method, Uri.parse('${_config.apiBaseUrl}$path'))
          ..headers.addAll({
            'Authorization': 'Bearer $accessToken',
            'Accept': 'application/json',
            if (body != null) 'Content-Type': 'application/json; charset=utf-8',
          });
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(
      await _client.send(request),
    );
    return decodeApiResponse(response);
  }

  @override
  void close() => _client.close();
}
