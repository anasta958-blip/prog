import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/network/api_response_decoder.dart';
import 'package:sklad_komforta_app/core/network/content_disposition.dart';
import 'package:sklad_komforta_app/core/network/http_client_factory.dart'
    if (dart.library.js_interop) 'package:sklad_komforta_app/core/network/http_client_factory_web.dart';
import 'package:sklad_komforta_app/features/quotes/quote_models.dart';

/// Заменяемый transport специализированной части КП/ПКП.
abstract interface class QuoteGateway {
  Future<QuoteDraft> createQuote(
    String accessToken,
    String boardId,
    String columnId,
    QuoteDraft draft,
  );

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

  Future<QuoteCalculationPreview> previewCalculation(
    String accessToken,
    String boardId,
    String cardId,
  );

  Future<QuoteDraft> applyCalculation(
    String accessToken,
    String boardId,
    String cardId,
    QuoteCalculationPreview preview,
  );

  /// Скачивает PDF сохранённого предложения. Если указан [variantId], в документ
  /// попадают только этот вариант и его тип; иначе печатается весь документ.
  Future<QuotePdfDownload> downloadPdf(
    String accessToken,
    String boardId,
    String cardId, {
    String? proposalTypeId,
    String? variantId,
  });

  void close();
}

/// REST-клиент атомарного чтения и сохранения дерева предложения.
final class QuoteApi implements QuoteGateway {
  QuoteApi(this._config) : _client = createPlatformHttpClient();

  final AppConfig _config;
  final http.Client _client;

  @override
  Future<QuoteDraft> createQuote(
    String accessToken,
    String boardId,
    String columnId,
    QuoteDraft draft,
  ) async {
    final path = '/kanbans/${Uri.encodeComponent(boardId)}/quotes';
    final request =
        http.Request('POST', Uri.parse('${_config.apiBaseUrl}$path'))
          ..headers.addAll({
            'Authorization': 'Bearer $accessToken',
            'Accept': 'application/json',
            'Content-Type': 'application/json; charset=utf-8',
          });
    request.body = jsonEncode({'columnId': columnId, 'quote': draft.toJson()});
    final response = await http.Response.fromStream(
      await _client.send(request),
    );
    return QuoteDraft.fromJson(
      decodeApiResponse(response) as Map<String, dynamic>,
    );
  }

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

  @override
  Future<QuoteCalculationPreview> previewCalculation(
    String accessToken,
    String boardId,
    String cardId,
  ) async => QuoteCalculationPreview.fromJson(
    await _send(
          'GET',
          boardId,
          cardId,
          accessToken,
          subpath: 'calculation-preview',
        )
        as Map<String, dynamic>,
  );

  @override
  Future<QuoteDraft> applyCalculation(
    String accessToken,
    String boardId,
    String cardId,
    QuoteCalculationPreview preview,
  ) async => QuoteDraft.fromJson(
    await _send(
          'POST',
          boardId,
          cardId,
          accessToken,
          subpath: 'apply-calculation',
          body: {
            'currentCalculationVersion': preview.currentCalculationVersion,
            'quoteUpdatedAt': preview.quoteUpdatedAt,
          },
        )
        as Map<String, dynamic>,
  );

  @override
  Future<QuotePdfDownload> downloadPdf(
    String accessToken,
    String boardId,
    String cardId, {
    String? proposalTypeId,
    String? variantId,
  }) async {
    final path =
        '/kanbans/${Uri.encodeComponent(boardId)}/cards/'
        '${Uri.encodeComponent(cardId)}/quote/pdf';
    final uri = Uri.parse('${_config.apiBaseUrl}$path').replace(
      queryParameters: {
        'proposalTypeId': ?proposalTypeId,
        'variantId': ?variantId,
      },
    );
    final response = await _client.get(
      uri,
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/pdf',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      decodeApiResponse(response);
    }
    return QuotePdfDownload(
      fileName:
          contentDispositionFileName(response.headers['content-disposition']) ??
          'Коммерческое предложение.pdf',
      bytes: response.bodyBytes,
    );
  }

  Future<dynamic> _send(
    String method,
    String boardId,
    String cardId,
    String accessToken, {
    Map<String, dynamic>? body,
    String subpath = '',
  }) async {
    final path =
        '/kanbans/${Uri.encodeComponent(boardId)}/cards/'
        '${Uri.encodeComponent(cardId)}/quote/$subpath';
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

/// Бинарный официальный документ, готовый для сохранения на устройстве.
final class QuotePdfDownload {
  const QuotePdfDownload({required this.fileName, required this.bytes});

  final String fileName;
  final Uint8List bytes;
}
