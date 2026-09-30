import 'dart:async';
import 'dart:convert';

import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/network/api_response_decoder.dart';
import 'package:sklad_komforta_app/core/network/http_client_factory.dart'
    if (dart.library.js_interop) 'package:sklad_komforta_app/core/network/http_client_factory_web.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Сигнал сервера «данные изменились». Самих данных в нём нет: получатель
/// перечитывает их обычными запросами с проверкой прав.
final class RealtimeEvent {
  const RealtimeEvent({
    required this.topic,
    required this.kind,
    this.boardId,
    this.entityId,
    this.section,
  });

  factory RealtimeEvent.fromJson(Map<String, dynamic> json) => RealtimeEvent(
    topic: json['topic'] as String? ?? '',
    kind: json['kind'] as String? ?? '',
    boardId: json['boardId'] as String?,
    entityId: json['entityId'] as String?,
    section: json['section'] as String?,
  );

  /// Изменились записи (карточки, товары).
  static const changed = 'changed';

  /// Изменилась структура модуля: канбаны, категории, поля.
  static const configuration = 'configuration';

  /// Соединение восстановлено после обрыва: за это время сигналы могли быть
  /// пропущены, поэтому нужно перечитать текущие данные.
  static const resync = 'resync';

  final String topic;
  final String kind;

  /// Канбан, к которому относится изменение, если известен.
  final String? boardId;

  /// Карточка, товар или запись раздела, если изменение относится к одной записи.
  final String? entityId;

  /// Раздел темы `company`: `configuration`, `profile`, `legal_entities`,
  /// `clients`, `employees`, `access`.
  final String? section;
}

/// Источник сигналов для контроллера; заменяется в тестах.
abstract interface class RealtimeSource {
  /// Сигналы темы. Служебные сообщения сервера сюда не попадают.
  Stream<RealtimeEvent> get events;

  /// Запускает подключение и переподключения. Повторный вызов ничего не делает.
  void start();

  /// Закрывает соединение и прекращает переподключения.
  Future<void> close();
}

/// Выполняет запрос с действующим токеном доступа (обычно
/// `AuthController.executeAuthorized`).
typedef AuthorizedRunner =
    Future<T> Function<T>(Future<T> Function(String accessToken) request);

/// WebSocket-подписка на тему уведомлений об изменениях.
///
/// Подключение открывается по одноразовому билету из [ticketPath]: браузерный
/// WebSocket не передаёт заголовок Authorization, а токен доступа в адресе
/// попал бы в журналы прокси. При обрыве клиент переподключается с растущей
/// паузой (1, 2, 4 … 30 с) и после восстановления выдаёт событие
/// [RealtimeEvent.resync].
final class RealtimeClient implements RealtimeSource {
  RealtimeClient({
    required AppConfig config,
    required this.topic,
    required this.ticketPath,
    required AuthorizedRunner authorized,
  }) : _config = config,
       _authorized = authorized;

  final AppConfig _config;
  final AuthorizedRunner _authorized;

  /// Тема, на которую подписан клиент (`kanban`, `catalog`).
  final String topic;

  /// Путь endpoint-а выдачи билета относительно базового адреса API.
  final String ticketPath;

  final StreamController<RealtimeEvent> _events =
      StreamController<RealtimeEvent>.broadcast();
  WebSocketChannel? _channel;
  Completer<void>? _pause;
  bool _started = false;
  bool _closed = false;
  bool _connectedBefore = false;

  @override
  Stream<RealtimeEvent> get events => _events.stream;

  @override
  void start() {
    if (_started || _closed) return;
    _started = true;
    unawaited(_run());
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _pause?.complete();
    await _channel?.sink.close();
    await _events.close();
  }

  Future<void> _run() async {
    var attempt = 0;
    while (!_closed) {
      try {
        final ticket = await _authorized(_issueTicket);
        if (_closed) break;
        final channel = WebSocketChannel.connect(socketUri(_config, ticket));
        _channel = channel;
        await channel.ready;
        await for (final raw in channel.stream) {
          if (raw is! String) continue;
          final event = RealtimeEvent.fromJson(
            jsonDecode(raw) as Map<String, dynamic>,
          );
          if (event.kind == 'ready') {
            attempt = 0;
            if (_connectedBefore) _emit(_resyncEvent);
            _connectedBefore = true;
          } else if (event.kind != 'ping' && event.topic == topic) {
            _emit(event);
          }
        }
      } on Object {
        // Сеть, истёкшая сессия или недоступный сервер: повторим позже.
      }
      _channel = null;
      if (_closed) break;
      await _wait(_retryDelay(attempt++));
    }
  }

  RealtimeEvent get _resyncEvent =>
      RealtimeEvent(topic: topic, kind: RealtimeEvent.resync);

  void _emit(RealtimeEvent event) {
    if (!_closed) _events.add(event);
  }

  Future<void> _wait(Duration delay) {
    final pause = Completer<void>();
    _pause = pause;
    final timer = Timer(delay, () {
      if (!pause.isCompleted) pause.complete();
    });
    return pause.future.whenComplete(timer.cancel);
  }

  static Duration _retryDelay(int attempt) =>
      Duration(seconds: attempt >= 5 ? 30 : 1 << attempt);

  Future<String> _issueTicket(String accessToken) async {
    final client = createPlatformHttpClient();
    try {
      final response = await client.post(
        Uri.parse('${_config.apiBaseUrl}$ticketPath'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/json',
        },
      );
      final data = decodeApiResponse(response) as Map<String, dynamic>;
      return data['ticket'] as String;
    } finally {
      client.close();
    }
  }

  /// Адрес WebSocket по базовому адресу API. Относительный адрес (Web-сборка
  /// за nginx) разрешается от адреса страницы; http/https меняются на ws/wss.
  static Uri socketUri(AppConfig config, String ticket, {Uri? pageUri}) {
    final base = config.apiBaseUrl.endsWith('/')
        ? config.apiBaseUrl
        : '${config.apiBaseUrl}/';
    final api = (pageUri ?? Uri.base).resolve(base).resolve('realtime');
    return api.replace(
      scheme: api.scheme == 'https' ? 'wss' : 'ws',
      queryParameters: {'ticket': ticket},
    );
  }
}
