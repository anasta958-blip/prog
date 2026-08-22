import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/network/api_response_decoder.dart';
import 'package:sklad_komforta_app/core/network/http_client_factory.dart'
    if (dart.library.js_interop) 'package:sklad_komforta_app/core/network/http_client_factory_web.dart';
import 'package:sklad_komforta_app/features/onboarding/onboarding_models.dart';

abstract interface class CompanyGateway {
  Future<CompanyProfileDraft> getProfile(String accessToken);
  Future<CompanyProfileDraft> updateProfile(
    String accessToken,
    CompanyProfileDraft profile,
  );
  Future<OrganizationOnboardingDraft> getConfiguration(String accessToken);
  Future<OrganizationOnboardingDraft> updateConfiguration(
    String accessToken,
    OrganizationOnboardingDraft draft,
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

  @override
  Future<OrganizationOnboardingDraft> getConfiguration(
    String accessToken,
  ) async {
    final data = await _sendPath('GET', '/company/configuration', accessToken);
    return OrganizationOnboardingDraft.fromJson(data as Map<String, dynamic>);
  }

  @override
  Future<OrganizationOnboardingDraft> updateConfiguration(
    String accessToken,
    OrganizationOnboardingDraft draft,
  ) async {
    final data = await _sendPath(
      'PUT',
      '/company/configuration',
      accessToken,
      body: draft.toJson(),
    );
    return OrganizationOnboardingDraft.fromJson(data as Map<String, dynamic>);
  }

  Future<dynamic> _send(
    String method,
    String accessToken, {
    Map<String, dynamic>? body,
  }) async {
    return _sendPath(method, '/company/profile', accessToken, body: body);
  }

  Future<dynamic> _sendPath(
    String method,
    String path,
    String accessToken, {
    Map<String, dynamic>? body,
  }) async {
    final request =
        http.Request(method, Uri.parse('${_config.apiBaseUrl}$path'))
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
