import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/network/api_response_decoder.dart';
import 'package:sklad_komforta_app/core/network/http_client_factory.dart'
    if (dart.library.js_interop) 'package:sklad_komforta_app/core/network/http_client_factory_web.dart';
import 'package:sklad_komforta_app/features/company/company_models.dart';

abstract interface class CompanyGateway {
  Future<CompanyProfileDraft> getProfile(String accessToken);
  Future<CompanyProfileDraft> updateProfile(
    String accessToken,
    CompanyProfileDraft profile,
  );
  void close();
}

/// REST-клиент рабочего профиля организации.
final class CompanyApi implements CompanyGateway {
  CompanyApi(this._config) : _client = createPlatformHttpClient();

  final AppConfig _config;
  final http.Client _client;

  @override
  Future<CompanyProfileDraft> getProfile(String accessToken) async {
    final data = await _send('GET', accessToken);
    return CompanyProfileDraft.fromJson(data as Map<String, dynamic>);
  }

  @override
  Future<CompanyProfileDraft> updateProfile(
    String accessToken,
    CompanyProfileDraft profile,
  ) async {
    final data = await _send('PUT', accessToken, body: profile.toJson());
    return CompanyProfileDraft.fromJson(data as Map<String, dynamic>);
  }

  Future<dynamic> _send(
    String method,
    String accessToken, {
    Map<String, dynamic>? body,
  }) async {
    final request =
        http.Request(method, Uri.parse('${_config.apiBaseUrl}/company/profile'))
          ..headers.addAll({
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
          });
    if (body != null) request.body = jsonEncode(body);
    final response = await _client.send(request);
    return decodeApiResponse(await http.Response.fromStream(response));
  }

  @override
  void close() => _client.close();
}
