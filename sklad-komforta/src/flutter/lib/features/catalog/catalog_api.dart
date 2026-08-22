import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sklad_komforta_app/core/config/app_config.dart';
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

/// HTTP-реализация каталога с единым серверным конвертом `{ok,data,error}`.
final class CatalogApi implements CatalogGateway {
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

  Future<dynamic> _send(
    String method,
    String path,
    String accessToken, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
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
