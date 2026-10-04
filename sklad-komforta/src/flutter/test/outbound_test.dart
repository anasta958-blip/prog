import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/network/api_exception.dart';
import 'package:sklad_komforta_app/core/security/token_store.dart';
import 'package:sklad_komforta_app/features/auth/auth_api.dart';
import 'package:sklad_komforta_app/features/auth/auth_controller.dart';
import 'package:sklad_komforta_app/features/outbound/outbound_api.dart';
import 'package:sklad_komforta_app/features/outbound/outbound_models.dart';
import 'package:sklad_komforta_app/features/outbound/outbound_send.dart';
import 'package:sklad_komforta_app/features/outbound/outbound_settings_controller.dart';
import 'package:sklad_komforta_app/features/outbound/outbound_settings_editor.dart';

void main() {
  const config = AppConfig(
    apiBaseUrl: 'https://example.test/api/v1',
    environment: 'test',
  );
  AuthController authorized() =>
      AuthController(config, api: _AuthGateway(), tokens: _Tokens())
        ..accessToken = 'access-token';

  test('настройки: секреты уходят только при вводе, пустое — null', () {
    final settings = OutboundSettingsModel.fromJson({
      'telegram': {
        'hasBotToken': true,
        'chatId': '-100',
        'usesTopics': false,
        'defaultTopicId': 5,
        'topics': [
          {'topicId': 5, 'name': 'Снабжение'},
        ],
        'captionTemplate': '',
      },
      'email': {
        'address': 'a@gmail.com',
        'hasPassword': true,
        'subjectTemplate': outboundDefaultTemplate,
      },
    });
    final json = settings.toJson();
    final telegram = json['telegram'] as Map<String, dynamic>;
    final email = json['email'] as Map<String, dynamic>;
    expect(telegram['botToken'], isNull);
    // Без топиков топик по умолчанию не отправляется.
    expect(telegram['defaultTopicId'], isNull);
    expect(telegram['captionTemplate'], '');
    expect(email['password'], isNull);
    expect(email['bodyTemplate'], isNull);

    settings
      ..botToken = ' 123:token '
      ..password = 'secret';
    final changed = settings.toJson();
    expect((changed['telegram'] as Map)['botToken'], '123:token');
    expect((changed['email'] as Map)['password'], 'secret');
    expect(
      outboundTemplateExample(outboundDefaultTemplate),
      'КП №15 — Лесная, 5',
    );
    expect(detectSmtpServer('user@Yandex.ru'), 'smtp.yandex.ru:465');
    expect(detectSmtpServer('user@company.ru'), isNull);
  });

  testWidgets('раздел «Внешняя отправка»: топики, сохранение и проверка', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 2200);
    addTearDown(tester.view.reset);
    final auth = authorized();
    final gateway = _MemoryOutboundGateway();
    final controller = OutboundSettingsController(auth, gateway: gateway);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: OutboundSettingsEditor(controller: controller),
          ),
        ),
      ),
    );
    await controller.load();
    await tester.pumpAndSettle();

    expect(find.text('Telegram'), findsOneWidget);
    expect(find.text('Почта'), findsOneWidget);
    expect(find.textContaining('Пример: КП №15 — Лесная, 5'), findsWidgets);

    await tester.enterText(
      find.byKey(const ValueKey('outbound-bot-token-1')),
      '123456789:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsawQ',
    );
    await tester.enterText(
      find.byKey(const ValueKey('outbound-chat-id-1')),
      '-1001234567890',
    );
    await tester.tap(find.byKey(const Key('outbound-uses-topics')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('outbound-topic-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('outbound-topic-id-0')),
      '15',
    );
    await tester.enterText(
      find.byKey(const ValueKey('outbound-topic-name-0')),
      'Снабжение',
    );
    // Gmail: сервер определяется сам, полей сервера нет.
    await tester.enterText(
      find.byKey(const ValueKey('outbound-address-1')),
      'sender@gmail.com',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('smtp.gmail.com:465'), findsOneWidget);
    expect(find.text('Сервер SMTP'), findsNothing);
    expect(controller.dirty, isTrue);

    // Проверка до сохранения запрещена.
    await tester.tap(find.byKey(const Key('outbound-test-telegram')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Сначала сохраните'), findsOneWidget);

    expect(await controller.save(), isTrue);
    await tester.pumpAndSettle();
    final saved = gateway.saved!.toJson();
    final telegram = saved['telegram'] as Map<String, dynamic>;
    expect(
      telegram['botToken'],
      '123456789:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsawQ',
    );
    expect(telegram['usesTopics'], isTrue);
    expect(telegram['topics'], [
      {'topicId': 15, 'name': 'Снабжение'},
    ]);
    expect((saved['email'] as Map)['address'], 'sender@gmail.com');
    expect(controller.dirty, isFalse);
    // Сохранённый токен не показывается, поле пустое.
    expect(find.textContaining('Сохранён. Введите новый'), findsOneWidget);

    await tester.tap(find.byKey(const Key('outbound-test-telegram')));
    await tester.pumpAndSettle();
    expect(gateway.tested, [OutboundChannel.telegram]);
    expect(find.textContaining('топик «Снабжение»'), findsOneWidget);

    // Другая почта — нужны сервер и порт.
    await tester.enterText(
      find.byKey(ValueKey('outbound-address-${controller.revision}')),
      'office@company.ru',
    );
    await tester.pumpAndSettle();
    expect(find.text('Сервер SMTP'), findsOneWidget);

    controller.dispose();
    auth.dispose();
  });

  testWidgets('отправка: выбор топика и ввод адреса только без значений по '
      'умолчанию', (tester) async {
    final auth = authorized();
    final gateway = _MemoryOutboundGateway()
      ..channels = const OutboundChannels(
        telegramReady: true,
        telegramTopicRequired: true,
        topics: [
          OutboundTopic(topicId: 5, name: 'Снабжение'),
          OutboundTopic(topicId: 7, name: 'Монтаж'),
        ],
        emailReady: true,
        emailRecipientRequired: true,
      );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                for (final channel in OutboundChannel.values)
                  TextButton(
                    onPressed: () => sendCardDocument(
                      context,
                      auth: auth,
                      boardId: 'orders',
                      cardId: 'card-1',
                      channel: channel,
                      gatewayFactory: (_) => gateway,
                    ),
                    child: Text('send-${channel.code}'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('send-telegram'));
    await tester.pumpAndSettle();
    expect(find.text('В какой топик отправить?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('outbound-topic-7')));
    await tester.pumpAndSettle();
    expect(gateway.sent.last, (OutboundChannel.telegram, 7, null));
    expect(find.textContaining('отправлен: топик'), findsOneWidget);

    await tester.tap(find.text('send-email'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('outbound-recipient')),
      'не адрес',
    );
    await tester.tap(find.byKey(const Key('outbound-recipient-send')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Введите адрес почты'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('outbound-recipient')),
      'client@mail.ru',
    );
    await tester.tap(find.byKey(const Key('outbound-recipient-send')));
    await tester.pumpAndSettle();
    expect(gateway.sent.last, (OutboundChannel.email, null, 'client@mail.ru'));

    // С топиком и адресом по умолчанию ничего не спрашивается.
    gateway.channels = const OutboundChannels(
      telegramReady: true,
      emailReady: true,
    );
    await tester.tap(find.text('send-telegram'));
    await tester.pumpAndSettle();
    expect(find.text('В какой топик отправить?'), findsNothing);
    expect(gateway.sent.last, (OutboundChannel.telegram, null, null));

    // Ошибка сервера показывается сообщением.
    gateway.failure = const ApiException(
      'outbound_telegram_failed',
      'Группа не найдена.',
      502,
    );
    await tester.tap(find.text('send-telegram'));
    await tester.pumpAndSettle();
    expect(find.text('Группа не найдена.'), findsOneWidget);
    auth.dispose();
  });
}

final class _MemoryOutboundGateway implements OutboundGateway {
  OutboundSettingsModel? saved;
  OutboundChannels channels = OutboundChannels.none;
  final tested = <OutboundChannel>[];
  final sent = <(OutboundChannel, int?, String?)>[];
  ApiException? failure;

  @override
  Future<OutboundSettingsModel> getSettings(String accessToken) async =>
      saved == null ? OutboundSettingsModel() : saved!.copy();

  @override
  Future<OutboundSettingsModel> saveSettings(
    String accessToken,
    OutboundSettingsModel settings,
  ) async {
    saved = settings.copy();
    // Как сервер: секреты не возвращаются, только признаки.
    return settings.copy()
      ..hasBotToken = settings.hasBotToken || settings.botToken.isNotEmpty
      ..hasPassword = settings.hasPassword || settings.password.isNotEmpty
      ..botToken = ''
      ..password = '';
  }

  @override
  Future<String> test(String accessToken, OutboundChannel channel) async {
    tested.add(channel);
    return 'топик «Снабжение»';
  }

  @override
  Future<OutboundChannels> getChannels(String accessToken) async => channels;

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
    if (failure case final error?) throw error;
    sent.add((channel, topicId, recipient));
    return OutboundSendResult(
      destination: recipient ?? 'топик «Монтаж»',
      fileName: 'Лесная, 5 — 03.10.2026.pdf',
    );
  }

  @override
  void close() {}
}

/// Сеть авторизации в этих тестах не нужна.
final class _AuthGateway implements AuthGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

final class _Tokens implements TokenRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}
