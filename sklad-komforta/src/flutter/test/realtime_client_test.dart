import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/network/realtime_client.dart';

void main() {
  test('адрес WebSocket строится от адреса API', () {
    const local = AppConfig(
      apiBaseUrl: 'http://localhost:8080/api/v1',
      environment: 'development',
    );
    expect(
      RealtimeClient.socketUri(local, 'abc').toString(),
      'ws://localhost:8080/api/v1/realtime?ticket=abc',
    );

    // Web-сборка за nginx: относительный адрес от страницы, https → wss.
    const web = AppConfig(apiBaseUrl: '/api/v1', environment: 'production');
    expect(
      RealtimeClient.socketUri(
        web,
        'a+b/c',
        pageUri: Uri.parse('https://sklad.example/workspace'),
      ).toString(),
      'wss://sklad.example/api/v1/realtime?ticket=a%2Bb%2Fc',
    );
  });

  test('сигнал читается из JSON сервера', () {
    final event = RealtimeEvent.fromJson({
      'topic': 'kanban',
      'kind': 'changed',
      'boardId': 'board',
      'entityId': 'card',
    });
    expect(event.topic, 'kanban');
    expect(event.kind, RealtimeEvent.changed);
    expect(event.boardId, 'board');
    expect(event.entityId, 'card');
  });
}
