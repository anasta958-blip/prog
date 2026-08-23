import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/network/api_exception.dart';
import 'package:sklad_komforta_app/core/network/api_response_decoder.dart';
import 'package:sklad_komforta_app/core/network/http_client_factory.dart'
    if (dart.library.js_interop) 'package:sklad_komforta_app/core/network/http_client_factory_web.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_models.dart';

/// Заменяемый в тестах transport рабочего каталога.
abstract interface class CatalogGateway {
  Future<CatalogConfiguration> getConfiguration(String accessToken);

  Future<CatalogItemPage> getItems({
    required String accessToken,
    String? categoryId,
    String? sectionId,
    String? status,
    String? search,
    required int page,
    required int pageSize,
  });

  Future<CatalogItem> createItem(String accessToken, CatalogItemDraft draft);
  Future<CatalogItem> updateItem(
    String accessToken,
    String itemId,
    CatalogItemDraft draft,
  );
  Future<void> deleteItem(String accessToken, String itemId);
  void close();
}

/// Дополнительный контракт файлов карточки, отделённый от базового CRUD.
abstract interface class CatalogImageGateway {
  Future<List<CatalogItemImage>> getImages(String accessToken, String itemId);
  Future<CatalogItemImage> uploadImage({
    required String accessToken,
    required String itemId,
    required String fileName,
    required String contentType,
    required Uint8List bytes,
  });
  Future<void> deleteImage(String accessToken, String itemId, String imageId);
}

/// Контракт привязок карточек отделён от базового CRUD и файлов.
abstract interface class CatalogRelationGateway {
  Future<List<CatalogItemRelation>> getRelations(
    String accessToken,
    String itemId,
  );
  Future<List<CatalogRelationCandidate>> searchRelationCandidates({
    required String accessToken,
    required String dependencyId,
    required String search,
  });
  Future<List<CatalogItemRelation>> replaceRelations({
    required String accessToken,
    required String itemId,
    required List<CatalogItemRelation> relations,
  });
}

/// XLSX и массовые операции вынесены из CRUD-контракта для независимого тестирования.
abstract interface class CatalogTransferGateway {
  Future<CatalogSpreadsheetDownload> downloadTemplate({
    required String accessToken,
    String? categoryId,
  });
  Future<CatalogSpreadsheetDownload> exportCatalog({
    required String accessToken,
    String? categoryId,
    String? sectionId,
    String? status,
    String? search,
  });
  Future<CatalogImportResult> importCatalog({
    required String accessToken,
    required String fileName,
    required Uint8List bytes,
  });
  Future<CatalogBulkResult> applyBulk({
    required String accessToken,
    required List<String> itemIds,
    required String action,
    String? status,
  });
}

/// HTTP-реализация каталога с единым серверным конвертом `{ok,data,error}`.
final class CatalogApi
    implements
        CatalogGateway,
        CatalogImageGateway,
        CatalogRelationGateway,
        CatalogTransferGateway {
  CatalogApi(this._config) : _client = createPlatformHttpClient();

  final AppConfig _config;
  final http.Client _client;

  @override
  Future<CatalogConfiguration> getConfiguration(String accessToken) async {
    final data = await _send('GET', '/catalog/configuration', accessToken);
    return CatalogConfiguration.fromJson(data as Map<String, dynamic>);
  }

  @override
  Future<CatalogItemPage> getItems({
    required String accessToken,
    String? categoryId,
    String? sectionId,
    String? status,
    String? search,
    required int page,
    required int pageSize,
  }) async {
    final query = <String, String>{
      if (status != null && status.isNotEmpty) 'status': status,
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      'page': '$page',
      'pageSize': '$pageSize',
    };
    if (categoryId case final value?) query['categoryId'] = value;
    if (sectionId case final value?) query['sectionId'] = value;
    final data = await _send(
      'GET',
      '/catalog/items',
      accessToken,
      query: query,
    );
    return CatalogItemPage.fromJson(data as Map<String, dynamic>);
  }

  @override
  Future<CatalogItem> createItem(
    String accessToken,
    CatalogItemDraft draft,
  ) async {
    final data = await _send(
      'POST',
      '/catalog/items',
      accessToken,
      body: draft.toJson(),
    );
    return CatalogItem.fromJson(data as Map<String, dynamic>);
  }

  @override
  Future<CatalogItem> updateItem(
    String accessToken,
    String itemId,
    CatalogItemDraft draft,
  ) async {
    final data = await _send(
      'PUT',
      '/catalog/items/$itemId',
      accessToken,
      body: draft.toJson(),
    );
    return CatalogItem.fromJson(data as Map<String, dynamic>);
  }

  @override
  Future<void> deleteItem(String accessToken, String itemId) async {
    await _send('DELETE', '/catalog/items/$itemId', accessToken);
  }

  @override
  Future<List<CatalogItemImage>> getImages(
    String accessToken,
    String itemId,
  ) async {
    final data = await _send(
      'GET',
      '/catalog/items/$itemId/images',
      accessToken,
    );
    return (data as List<dynamic>)
        .map((item) => CatalogItemImage.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<CatalogItemImage> uploadImage({
    required String accessToken,
    required String itemId,
    required String fileName,
    required String contentType,
    required Uint8List bytes,
  }) async {
    final ticketData = await _send(
      'POST',
      '/catalog/items/$itemId/images/uploads',
      accessToken,
      body: {
        'fileName': fileName,
        'contentType': contentType,
        'byteSize': bytes.length,
      },
    );
    final ticket = CatalogImageUploadTicket.fromJson(
      ticketData as Map<String, dynamic>,
    );
    try {
      final uploadUri = Uri.parse(ticket.uploadUrl);
      late final http.Response uploadResponse;
      try {
        // Используем тот же управляемый платформенный клиент, что и для REST API.
        uploadResponse = await _client.put(
          uploadUri,
          headers: {'Content-Type': contentType},
          body: bytes,
        );
      } on http.ClientException catch (exception) {
        final port = uploadUri.hasPort ? ':${uploadUri.port}' : '';
        throw ApiException(
          'catalog_image_storage_unreachable',
          'Хранилище изображений недоступно по адресу '
              '${uploadUri.host}$port: ${exception.message}',
        );
      }
      if (uploadResponse.statusCode < 200 || uploadResponse.statusCode >= 300) {
        throw ApiException(
          'catalog_image_upload_failed',
          'Не удалось загрузить изображение в хранилище.',
          uploadResponse.statusCode,
        );
      }
      final confirmed = await _send(
        'POST',
        '/catalog/items/$itemId/images/${ticket.imageId}/confirm',
        accessToken,
      );
      return CatalogItemImage.fromJson(confirmed as Map<String, dynamic>);
    } on Object {
      // Неудачная попытка не должна занимать один из восьми слотов карточки.
      // Ошибку очистки намеренно не подменяем исходной ошибкой загрузки.
      try {
        await _send(
          'DELETE',
          '/catalog/items/$itemId/images/${ticket.imageId}',
          accessToken,
        );
      } on Object {
        // Сервер дополнительно исключает устаревшие ticket из лимита через час.
      }
      rethrow;
    }
  }

  @override
  Future<void> deleteImage(
    String accessToken,
    String itemId,
    String imageId,
  ) async {
    await _send(
      'DELETE',
      '/catalog/items/$itemId/images/$imageId',
      accessToken,
    );
  }

  @override
  Future<List<CatalogItemRelation>> getRelations(
    String accessToken,
    String itemId,
  ) async {
    final data = await _send(
      'GET',
      '/catalog/items/$itemId/relations',
      accessToken,
    );
    return (data as List<dynamic>)
        .map(
          (item) => CatalogItemRelation.fromJson(item as Map<String, dynamic>),
        )
        .toList(growable: false);
  }

  @override
  Future<List<CatalogRelationCandidate>> searchRelationCandidates({
    required String accessToken,
    required String dependencyId,
    required String search,
  }) async {
    final data = await _send(
      'GET',
      '/catalog/dependencies/$dependencyId/candidates',
      accessToken,
      query: {'search': search.trim(), 'limit': '30'},
    );
    return (data as List<dynamic>)
        .map(
          (item) =>
              CatalogRelationCandidate.fromJson(item as Map<String, dynamic>),
        )
        .toList(growable: false);
  }

  @override
  Future<List<CatalogItemRelation>> replaceRelations({
    required String accessToken,
    required String itemId,
    required List<CatalogItemRelation> relations,
  }) async {
    final data = await _send(
      'PUT',
      '/catalog/items/$itemId/relations',
      accessToken,
      body: relations.map((item) => item.toSaveJson()).toList(),
    );
    return (data as List<dynamic>)
        .map(
          (item) => CatalogItemRelation.fromJson(item as Map<String, dynamic>),
        )
        .toList(growable: false);
  }

  @override
  Future<CatalogSpreadsheetDownload> downloadTemplate({
    required String accessToken,
    String? categoryId,
  }) {
    final query = <String, String>{};
    if (categoryId case final value?) query['categoryId'] = value;
    return _download(
      '/catalog/template.xlsx',
      accessToken,
      query: query,
      fallbackName: 'Шаблон каталога.xlsx',
    );
  }

  @override
  Future<CatalogSpreadsheetDownload> exportCatalog({
    required String accessToken,
    String? categoryId,
    String? sectionId,
    String? status,
    String? search,
  }) {
    final query = <String, String>{};
    final selectedCategoryId = categoryId;
    final selectedSectionId = sectionId;
    final selectedStatus = status;
    final searchValue = search?.trim();
    if (selectedCategoryId != null) query['categoryId'] = selectedCategoryId;
    if (selectedSectionId != null) query['sectionId'] = selectedSectionId;
    if (selectedStatus != null && selectedStatus.isNotEmpty) {
      query['status'] = selectedStatus;
    }
    if (searchValue != null && searchValue.isNotEmpty) {
      query['search'] = searchValue;
    }
    return _download(
      '/catalog/export.xlsx',
      accessToken,
      query: query,
      fallbackName: 'Каталог.xlsx',
    );
  }

  @override
  Future<CatalogImportResult> importCatalog({
    required String accessToken,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${_config.apiBaseUrl}/catalog/import.xlsx'),
    )..headers['Authorization'] = 'Bearer $accessToken';
    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: fileName),
    );
    final response = await http.Response.fromStream(
      await _client.send(request),
    );
    final data = decodeApiResponse(response);
    return CatalogImportResult.fromJson(data as Map<String, dynamic>);
  }

  @override
  Future<CatalogBulkResult> applyBulk({
    required String accessToken,
    required List<String> itemIds,
    required String action,
    String? status,
  }) async {
    final body = <String, dynamic>{'itemIds': itemIds, 'action': action};
    final selectedStatus = status;
    if (selectedStatus != null) body['status'] = selectedStatus;
    final data = await _send(
      'POST',
      '/catalog/items/bulk',
      accessToken,
      body: body,
    );
    return CatalogBulkResult.fromJson(data as Map<String, dynamic>);
  }

  Future<CatalogSpreadsheetDownload> _download(
    String path,
    String accessToken, {
    required String fallbackName,
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse(
      '${_config.apiBaseUrl}$path',
    ).replace(queryParameters: query == null || query.isEmpty ? null : query);
    final response = await _client.get(
      uri,
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      decodeApiResponse(response);
    }
    return CatalogSpreadsheetDownload(
      fileName:
          _downloadName(response.headers['content-disposition']) ??
          fallbackName,
      bytes: response.bodyBytes,
    );
  }

  static String? _downloadName(String? disposition) {
    if (disposition == null) return null;
    final encoded = RegExp(
      r"filename\*=UTF-8''([^;]+)",
      caseSensitive: false,
    ).firstMatch(disposition)?.group(1);
    if (encoded != null) return Uri.decodeComponent(encoded);
    return RegExp(
      r'filename="?([^";]+)',
      caseSensitive: false,
    ).firstMatch(disposition)?.group(1);
  }

  Future<dynamic> _send(
    String method,
    String path,
    String accessToken, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final uri = Uri.parse(
      '${_config.apiBaseUrl}$path',
    ).replace(queryParameters: query);
    final request = http.Request(method, uri)
      ..headers.addAll({
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      });
    if (body != null) request.body = jsonEncode(body);
    final streamed = await _client.send(request);
    return decodeApiResponse(await http.Response.fromStream(streamed));
  }

  @override
  void close() => _client.close();
}
