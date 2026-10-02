import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/network/api_exception.dart';
import 'package:sklad_komforta_app/core/network/api_response_decoder.dart';
import 'package:sklad_komforta_app/core/network/content_disposition.dart';
import 'package:sklad_komforta_app/core/network/http_client_factory.dart'
    if (dart.library.js_interop) 'package:sklad_komforta_app/core/network/http_client_factory_web.dart';
import 'package:sklad_komforta_app/features/orders/order_models.dart';
import 'package:sklad_komforta_app/features/quotes/quote_api.dart';

/// Заменяемый транспорт комплектации (в тестах — память).
abstract interface class OrderGateway {
  Future<OrderDocument> getOrder(
    String accessToken,
    String boardId,
    String cardId,
  );

  /// Создаёт карточку в столбце с действием «Создать комплектацию».
  Future<OrderDocument> createOrder(
    String accessToken,
    String boardId,
    String columnId,
    OrderDocument order,
  );

  Future<OrderDocument> saveOrder(
    String accessToken,
    String boardId,
    String cardId,
    OrderDocument order,
  );

  /// PDF сохранённой комплектации.
  Future<QuotePdfDownload> downloadPdf(
    String accessToken,
    String boardId,
    String cardId,
  );

  Future<List<OrderInvoice>> getInvoices(
    String accessToken,
    String boardId,
    String cardId,
  );

  /// Загружает PDF-счёт: билет → прямая загрузка в хранилище → подтверждение.
  Future<OrderInvoice> uploadInvoice(
    String accessToken,
    String boardId,
    String cardId, {
    required String fileName,
    required Uint8List bytes,
  });

  Future<void> deleteInvoice(
    String accessToken,
    String boardId,
    String cardId,
    String invoiceId,
  );

  /// Содержимое счёта по его короткоживущей ссылке хранилища.
  Future<Uint8List> fetchInvoice(OrderInvoice invoice);

  void close();
}

/// REST-клиент комплектации.
final class OrderApi implements OrderGateway {
  OrderApi(this._config) : _client = createPlatformHttpClient();

  final AppConfig _config;
  final http.Client _client;

  String _orderPath(String boardId, String cardId) =>
      '/kanbans/${Uri.encodeComponent(boardId)}/cards/'
      '${Uri.encodeComponent(cardId)}/order';

  @override
  Future<OrderDocument> getOrder(
    String accessToken,
    String boardId,
    String cardId,
  ) async => OrderDocument.fromJson(
    await _send('GET', '${_orderPath(boardId, cardId)}/', accessToken)
        as Map<String, dynamic>,
  );

  @override
  Future<OrderDocument> createOrder(
    String accessToken,
    String boardId,
    String columnId,
    OrderDocument order,
  ) async => OrderDocument.fromJson(
    await _send(
          'POST',
          '/kanbans/${Uri.encodeComponent(boardId)}/orders',
          accessToken,
          body: {'columnId': columnId, 'order': order.toJson()},
        )
        as Map<String, dynamic>,
  );

  @override
  Future<OrderDocument> saveOrder(
    String accessToken,
    String boardId,
    String cardId,
    OrderDocument order,
  ) async => OrderDocument.fromJson(
    await _send(
          'PUT',
          '${_orderPath(boardId, cardId)}/',
          accessToken,
          body: order.toJson(),
        )
        as Map<String, dynamic>,
  );

  @override
  Future<QuotePdfDownload> downloadPdf(
    String accessToken,
    String boardId,
    String cardId,
  ) async {
    final response = await _client.get(
      Uri.parse('${_config.apiBaseUrl}${_orderPath(boardId, cardId)}/pdf'),
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
          'Комплектация.pdf',
      bytes: response.bodyBytes,
    );
  }

  @override
  Future<List<OrderInvoice>> getInvoices(
    String accessToken,
    String boardId,
    String cardId,
  ) async =>
      ((await _send(
                    'GET',
                    '${_orderPath(boardId, cardId)}/invoices',
                    accessToken,
                  )
                  as List<dynamic>)
              .map(
                (item) => OrderInvoice.fromJson(item as Map<String, dynamic>),
              ))
          .toList(growable: false);

  @override
  Future<OrderInvoice> uploadInvoice(
    String accessToken,
    String boardId,
    String cardId, {
    required String fileName,
    required Uint8List bytes,
  }) async {
    final base = _orderPath(boardId, cardId);
    final ticket =
        await _send(
              'POST',
              '$base/invoices/uploads',
              accessToken,
              body: {
                'fileName': fileName,
                'contentType': 'application/pdf',
                'byteSize': bytes.length,
              },
            )
            as Map<String, dynamic>;
    final invoiceId = ticket['invoiceId'] as String;
    try {
      final uploadUri = Uri.parse(ticket['uploadUrl'] as String);
      late final http.Response upload;
      try {
        upload = await _client.put(
          uploadUri,
          headers: {'Content-Type': 'application/pdf'},
          body: bytes,
        );
      } on http.ClientException catch (exception) {
        final port = uploadUri.hasPort ? ':${uploadUri.port}' : '';
        throw ApiException(
          'order_invoice_storage_unreachable',
          'Хранилище файлов недоступно по адресу ${uploadUri.host}$port: '
              '${exception.message}',
        );
      }
      if (upload.statusCode < 200 || upload.statusCode >= 300) {
        throw ApiException(
          'order_invoice_upload_failed',
          'Не удалось загрузить счёт в хранилище.',
          upload.statusCode,
        );
      }
      return OrderInvoice.fromJson(
        await _send('POST', '$base/invoices/$invoiceId/confirm', accessToken)
            as Map<String, dynamic>,
      );
    } on Object {
      // Незавершённая загрузка не должна оставаться в списке.
      try {
        await _send('DELETE', '$base/invoices/$invoiceId', accessToken);
      } on Object {
        // Ошибку очистки не подменяем исходной ошибкой загрузки.
      }
      rethrow;
    }
  }

  @override
  Future<void> deleteInvoice(
    String accessToken,
    String boardId,
    String cardId,
    String invoiceId,
  ) => _send(
    'DELETE',
    '${_orderPath(boardId, cardId)}/invoices/${Uri.encodeComponent(invoiceId)}',
    accessToken,
  );

  @override
  Future<Uint8List> fetchInvoice(OrderInvoice invoice) async {
    // Pre-signed URL самодостаточен: без токена и cookie приложения.
    final response = await http.get(Uri.parse(invoice.downloadUrl));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        'order_invoice_download_failed',
        'Не удалось получить счёт.',
        response.statusCode,
      );
    }
    return response.bodyBytes;
  }

  Future<dynamic> _send(
    String method,
    String path,
    String accessToken, {
    Map<String, dynamic>? body,
  }) async {
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
