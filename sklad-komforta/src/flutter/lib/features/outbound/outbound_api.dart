import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/network/api_response_decoder.dart';
import 'package:sklad_komforta_app/core/network/http_client_factory.dart'
    if (dart.library.js_interop) 'package:sklad_komforta_app/core/network/http_client_factory_web.dart';
import 'package:sklad_komforta_app/features/outbound/outbound_models.dart';

/// Заменяемый транспорт внешней отправки (в тестах — память).
abstract interface class OutboundGateway {
  /// Настройки без секретов (право `outbound.settings.manage`).
  Future<OutboundSettingsModel> getSettings(String accessToken);

  /// Сохраняет настройки; новые токен и пароль передаются только здесь.
  Future<OutboundSettingsModel> saveSettings(
    String accessToken,
    OutboundSettingsModel settings,
  );

  /// Тестовое сообщение сохранённым способом; возвращает, куда оно ушло.
  Future<String> test(String accessToken, OutboundChannel channel);

  /// Готовность способов отправки (право `documents.send`).
  Future<OutboundChannels> getChannels(String accessToken);

  /// Отправляет PDF карточки КП, ПКП или комплектации.
  Future<OutboundSendResult> send(
    String accessToken, {
    required String boardId,
    required String cardId,
    required OutboundChannel channel,
    int? topicId,
    String? recipient,
    String? proposalTypeId,
    String? variantId,
  });

  void close();
}

/// REST-клиент внешней отправки.
final class OutboundApi implements OutboundGateway {
  OutboundApi(this._config) : _client = createPlatformHttpClient();

  final AppConfig _config;
  final http.Client _client;

  @override
  Future<OutboundSettingsModel> getSettings(String accessToken) async =>
      OutboundSettingsModel.fromJson(
        await _send('GET', '/company/outbound/', accessToken)
            as Map<String, dynamic>,
      );

  @override
  Future<OutboundSettingsModel> saveSettings(
    String accessToken,
    OutboundSettingsModel settings,
  ) async => OutboundSettingsModel.fromJson(
    await _send(
          'PUT',
          '/company/outbound/',
          accessToken,
          body: settings.toJson(),
        )
        as Map<String, dynamic>,
  );

  @override
  Future<String> test(String accessToken, OutboundChannel channel) async =>
      ((await _send(
                'POST',
                '/company/outbound/test/${channel.code}',
                accessToken,
              )
              as Map<String, dynamic>)['destination']
          as String);

  @override
  Future<OutboundChannels> getChannels(String accessToken) async =>
      OutboundChannels.fromJson(
        await _send('GET', '/outbound/channels', accessToken)
            as Map<String, dynamic>,
      );

  @override
  Future<OutboundSendResult> send(
    String accessToken, {
    required String boardId,
    required String cardId,
    required OutboundChannel channel,
    int? topicId,
    String? recipient,
    String? proposalTypeId,
    String? variantId,
  }) async {
    final today = DateTime.now();
    final date =
        '${today.year.toString().padLeft(4, '0')}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    return OutboundSendResult.fromJson(
      await _send(
            'POST',
            '/outbound/kanbans/${Uri.encodeComponent(boardId)}/cards/'
                '${Uri.encodeComponent(cardId)}/send',
            accessToken,
            body: {
              'channel': channel.code,
              'topicId': ?topicId,
              'recipient': ?recipient,
              'proposalTypeId': ?proposalTypeId,
              'variantId': ?variantId,
              // Дата пользователя: имя файла и {дата} совпадают с его календарём.
              'clientDate': date,
            },
          )
          as Map<String, dynamic>,
    );
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
