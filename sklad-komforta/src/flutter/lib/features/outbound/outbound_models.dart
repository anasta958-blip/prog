/// Способ внешней отправки документа.
enum OutboundChannel {
  telegram('telegram', 'В Telegram'),
  email('email', 'На почту');

  const OutboundChannel(this.code, this.label);

  /// Значение в API.
  final String code;

  /// Подпись кнопки и пункта меню.
  final String label;
}

/// Шаблон темы письма и подписи в Telegram по умолчанию.
const outboundDefaultTemplate = '{документ} №{номер} — {название}';

/// Подстановки шаблонов и их значения для примера в подсказке.
const outboundTemplatePlaceholders = <(String, String)>[
  ('{документ}', 'КП, ПКП или Комплектация'),
  ('{номер}', 'номер карточки'),
  ('{название}', 'название карточки (адрес объекта)'),
  ('{заказчик}', 'заказчик'),
  ('{дата}', 'дата отправки'),
];

/// Пример подстановки, как на сервере: для подсказки под полями шаблонов.
String outboundTemplateExample(String template) => template
    .replaceAll('{документ}', 'КП')
    .replaceAll('{номер}', '15')
    .replaceAll('{название}', 'Лесная, 5')
    .replaceAll('{заказчик}', 'Петров И. И.')
    .replaceAll('{дата}', '03.10.2026')
    .trim();

/// Топик Telegram-группы из справочника настроек.
final class OutboundTopic {
  const OutboundTopic({required this.topicId, required this.name});

  /// Идентификатор топика (`message_thread_id`).
  final int topicId;

  /// Понятное название для выбора при отправке.
  final String name;

  factory OutboundTopic.fromJson(Map<String, dynamic> json) => OutboundTopic(
    topicId: (json['topicId'] as num).toInt(),
    name: json['name'] as String,
  );

  Map<String, dynamic> toJson() => {'topicId': topicId, 'name': name};
}

/// Настройки внешней отправки. Токен бота и пароль почты сервер не
/// возвращает: [hasBotToken]/[hasPassword] сообщают, что они сохранены, а
/// новые значения передаются только при сохранении ([botToken], [password]).
final class OutboundSettingsModel {
  OutboundSettingsModel({
    this.hasBotToken = false,
    this.chatId = '',
    this.usesTopics = false,
    this.defaultTopicId,
    List<OutboundTopic>? topics,
    this.captionTemplate = outboundDefaultTemplate,
    this.address = '',
    this.hasPassword = false,
    this.senderName = '',
    this.smtpHost = '',
    this.smtpPort,
    this.subjectTemplate = outboundDefaultTemplate,
    this.bodyTemplate = '',
    this.defaultRecipient = '',
    this.detectedSmtpServer,
  }) : topics = topics ?? <OutboundTopic>[];

  bool hasBotToken;
  String chatId;
  bool usesTopics;
  int? defaultTopicId;
  List<OutboundTopic> topics;
  String captionTemplate;

  String address;
  bool hasPassword;
  String senderName;
  String smtpHost;
  int? smtpPort;
  String subjectTemplate;
  String bodyTemplate;
  String defaultRecipient;

  /// Сервер SMTP, определённый по домену адреса (`smtp.gmail.com:465`).
  String? detectedSmtpServer;

  /// Новый токен бота; пустой — оставить сохранённый.
  String botToken = '';

  /// Удалить сохранённый токен.
  bool clearBotToken = false;

  /// Новый пароль приложения; пустой — оставить сохранённый.
  String password = '';

  /// Удалить сохранённый пароль.
  bool clearPassword = false;

  factory OutboundSettingsModel.fromJson(Map<String, dynamic> json) {
    final telegram = json['telegram'] as Map<String, dynamic>;
    final email = json['email'] as Map<String, dynamic>;
    return OutboundSettingsModel(
      hasBotToken: telegram['hasBotToken'] as bool? ?? false,
      chatId: telegram['chatId'] as String? ?? '',
      usesTopics: telegram['usesTopics'] as bool? ?? false,
      defaultTopicId: (telegram['defaultTopicId'] as num?)?.toInt(),
      topics: ((telegram['topics'] as List<dynamic>?) ?? const [])
          .map((item) => OutboundTopic.fromJson(item as Map<String, dynamic>))
          .toList(),
      captionTemplate: telegram['captionTemplate'] as String? ?? '',
      address: email['address'] as String? ?? '',
      hasPassword: email['hasPassword'] as bool? ?? false,
      senderName: email['senderName'] as String? ?? '',
      smtpHost: email['smtpHost'] as String? ?? '',
      smtpPort: (email['smtpPort'] as num?)?.toInt(),
      subjectTemplate: email['subjectTemplate'] as String? ?? '',
      bodyTemplate: email['bodyTemplate'] as String? ?? '',
      defaultRecipient: email['defaultRecipient'] as String? ?? '',
      detectedSmtpServer: email['detectedSmtpServer'] as String?,
    );
  }

  /// Команда сохранения. Пустые строки уходят как `null`.
  Map<String, dynamic> toJson() {
    String? text(String value) => value.trim().isEmpty ? null : value.trim();
    return {
      'telegram': {
        'botToken': text(botToken),
        'clearBotToken': clearBotToken,
        'chatId': text(chatId),
        'usesTopics': usesTopics,
        'defaultTopicId': usesTopics ? defaultTopicId : null,
        'topics': [for (final topic in topics) topic.toJson()],
        'captionTemplate': captionTemplate.trim(),
      },
      'email': {
        'address': text(address),
        'password': password.isEmpty ? null : password,
        'clearPassword': clearPassword,
        'senderName': text(senderName),
        'smtpHost': text(smtpHost),
        'smtpPort': smtpPort,
        'subjectTemplate': subjectTemplate.trim(),
        'bodyTemplate': text(bodyTemplate),
        'defaultRecipient': text(defaultRecipient),
      },
    };
  }

  OutboundSettingsModel copy() =>
      OutboundSettingsModel.fromJson(toResponseJson())
        ..botToken = botToken
        ..clearBotToken = clearBotToken
        ..password = password
        ..clearPassword = clearPassword;

  /// Состояние в форме ответа сервера (для копии и сравнения правок).
  Map<String, dynamic> toResponseJson() => {
    'telegram': {
      'hasBotToken': hasBotToken,
      'chatId': chatId,
      'usesTopics': usesTopics,
      'defaultTopicId': defaultTopicId,
      'topics': [for (final topic in topics) topic.toJson()],
      'captionTemplate': captionTemplate,
    },
    'email': {
      'address': address,
      'hasPassword': hasPassword,
      'senderName': senderName,
      'smtpHost': smtpHost,
      'smtpPort': smtpPort,
      'subjectTemplate': subjectTemplate,
      'bodyTemplate': bodyTemplate,
      'defaultRecipient': defaultRecipient,
      'detectedSmtpServer': detectedSmtpServer,
    },
  };
}

/// Готовность способов отправки для кнопок и меню карточки.
final class OutboundChannels {
  const OutboundChannels({
    this.telegramReady = false,
    this.telegramTopicRequired = false,
    this.topics = const [],
    this.emailReady = false,
    this.emailRecipientRequired = false,
  });

  /// Ни один способ не настроен или нет права отправки.
  static const none = OutboundChannels();

  final bool telegramReady;

  /// Топик по умолчанию не задан — выбирается из [topics] при отправке.
  final bool telegramTopicRequired;
  final List<OutboundTopic> topics;
  final bool emailReady;

  /// Получатель по умолчанию не задан — адрес вводится при отправке.
  final bool emailRecipientRequired;

  /// Доступные способы в порядке меню.
  List<OutboundChannel> get available => [
    if (telegramReady) OutboundChannel.telegram,
    if (emailReady) OutboundChannel.email,
  ];

  factory OutboundChannels.fromJson(Map<String, dynamic> json) =>
      OutboundChannels(
        telegramReady: json['telegramReady'] as bool? ?? false,
        telegramTopicRequired: json['telegramTopicRequired'] as bool? ?? false,
        topics: ((json['topics'] as List<dynamic>?) ?? const [])
            .map((item) => OutboundTopic.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
        emailReady: json['emailReady'] as bool? ?? false,
        emailRecipientRequired:
            json['emailRecipientRequired'] as bool? ?? false,
      );
}

/// Результат отправки: куда ушёл документ и имя файла.
final class OutboundSendResult {
  const OutboundSendResult({required this.destination, required this.fileName});

  final String destination;
  final String fileName;

  factory OutboundSendResult.fromJson(Map<String, dynamic> json) =>
      OutboundSendResult(
        destination: json['destination'] as String,
        fileName: json['fileName'] as String,
      );
}
