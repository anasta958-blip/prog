import 'package:flutter/material.dart';
import 'package:sklad_komforta_app/core/network/api_exception.dart';
import 'package:sklad_komforta_app/core/widgets/app_notice.dart';
import 'package:sklad_komforta_app/features/auth/auth_controller.dart';
import 'package:sklad_komforta_app/features/outbound/outbound_api.dart';
import 'package:sklad_komforta_app/features/outbound/outbound_models.dart';

/// Создаёт транспорт отправки; тесты подменяют его памятью.
typedef OutboundGatewayFactory = OutboundGateway Function(AuthController auth);

OutboundGateway _defaultGateway(AuthController auth) =>
    OutboundApi(auth.config);

/// Готовность способов отправки. Без права `documents.send` или при ошибке
/// сети — [OutboundChannels.none]: кнопки отправки просто не показываются.
Future<OutboundChannels> loadOutboundChannels(
  AuthController auth, {
  OutboundGatewayFactory? gatewayFactory,
}) async {
  final gateway = (gatewayFactory ?? _defaultGateway)(auth);
  try {
    return await auth.executeAuthorized(gateway.getChannels);
  } on Object {
    return OutboundChannels.none;
  } finally {
    gateway.close();
  }
}

/// Отправляет PDF карточки в [channel]. Топик выбирается, только если в
/// настройках нет топика по умолчанию; адрес вводится, только если нет
/// получателя по умолчанию. Результат или ошибка показываются сообщением.
///
/// Возвращает `true`, если документ отправлен.
Future<bool> sendCardDocument(
  BuildContext context, {
  required AuthController auth,
  required String boardId,
  required String cardId,
  required OutboundChannel channel,
  String? proposalTypeId,
  String? variantId,
  OutboundGatewayFactory? gatewayFactory,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  // Новое сообщение сразу заменяет прежние (в том числе «Отправляю…»), а не
  // встаёт в очередь за ними.
  void show(String text) => messenger
    ..clearSnackBars()
    ..showSnackBar(AppSnackBar(content: Text(text)));

  final gateway = (gatewayFactory ?? _defaultGateway)(auth);
  try {
    // Настройки могли измениться: перед отправкой читаем их заново.
    final channels = await auth.executeAuthorized(gateway.getChannels);
    int? topicId;
    String? recipient;
    if (channel == OutboundChannel.telegram) {
      if (!channels.telegramReady) {
        show('Отправка в Telegram не настроена.');
        return false;
      }
      if (channels.telegramTopicRequired) {
        if (!context.mounted) return false;
        final topic = await showDialog<OutboundTopic>(
          context: context,
          builder: (_) => _TopicDialog(topics: channels.topics),
        );
        if (topic == null) return false;
        topicId = topic.topicId;
      }
    } else {
      if (!channels.emailReady) {
        show('Отправка по почте не настроена.');
        return false;
      }
      if (channels.emailRecipientRequired) {
        if (!context.mounted) return false;
        recipient = await showDialog<String>(
          context: context,
          builder: (_) => const _RecipientDialog(),
        );
        if (recipient == null) return false;
      }
    }

    show(
      channel == OutboundChannel.telegram
          ? 'Отправляю в Telegram…'
          : 'Отправляю письмо…',
    );
    final result = await auth.executeAuthorized(
      (token) => gateway.send(
        token,
        boardId: boardId,
        cardId: cardId,
        channel: channel,
        topicId: topicId,
        recipient: recipient,
        proposalTypeId: proposalTypeId,
        variantId: variantId,
      ),
    );
    show(
      channel == OutboundChannel.telegram
          ? 'Файл «${result.fileName}» отправлен: ${result.destination}.'
          : 'Письмо с файлом «${result.fileName}» отправлено на ${result.destination}.',
    );
    return true;
  } on ApiException catch (exception) {
    show(exception.message);
    return false;
  } on Object {
    show('Не удалось отправить документ. Проверьте подключение.');
    return false;
  } finally {
    gateway.close();
  }
}

/// Иконка способа отправки.
IconData outboundChannelIcon(OutboundChannel channel) => switch (channel) {
  OutboundChannel.telegram => Icons.send_outlined,
  OutboundChannel.email => Icons.mail_outline,
};

/// Кнопка «Отправить» с меню доступных способов для командной панели
/// редактора. Без доступных способов не показывается.
final class OutboundSendButton extends StatelessWidget {
  const OutboundSendButton({
    required this.channels,
    required this.onSend,
    this.compact = false,
    this.busy = false,
    super.key,
  });

  final OutboundChannels channels;
  final ValueChanged<OutboundChannel> onSend;
  final bool compact;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final available = channels.available;
    if (available.isEmpty) return const SizedBox.shrink();
    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      menuChildren: [
        for (final channel in available)
          MenuItemButton(
            key: ValueKey('outbound-send-${channel.code}'),
            leadingIcon: Icon(outboundChannelIcon(channel), size: 18),
            onPressed: () => onSend(channel),
            child: Text(channel.label),
          ),
      ],
      builder: (context, controller, _) {
        void toggle() =>
            controller.isOpen ? controller.close() : controller.open();
        final icon = busy
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.forward_to_inbox_outlined, size: 18);
        return Padding(
          padding: const EdgeInsets.only(left: 7),
          child: compact
              ? IconButton.outlined(
                  key: const Key('outbound-send'),
                  tooltip: 'Отправить',
                  onPressed: busy ? null : toggle,
                  icon: icon,
                )
              : OutlinedButton.icon(
                  key: const Key('outbound-send'),
                  onPressed: busy ? null : toggle,
                  icon: icon,
                  label: const Text('Отправить'),
                ),
        );
      },
    );
  }
}

final class _TopicDialog extends StatelessWidget {
  const _TopicDialog({required this.topics});

  final List<OutboundTopic> topics;

  @override
  Widget build(BuildContext context) => SimpleDialog(
    title: const Text('В какой топик отправить?'),
    children: [
      for (final topic in topics)
        SimpleDialogOption(
          key: ValueKey('outbound-topic-${topic.topicId}'),
          onPressed: () => Navigator.pop(context, topic),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.forum_outlined, size: 18),
                const SizedBox(width: 12),
                Expanded(child: Text(topic.name)),
              ],
            ),
          ),
        ),
    ],
  );
}

final class _RecipientDialog extends StatefulWidget {
  const _RecipientDialog();

  @override
  State<_RecipientDialog> createState() => _RecipientDialogState();
}

final class _RecipientDialogState extends State<_RecipientDialog> {
  final input = TextEditingController();
  String? error;

  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void _submit() {
    final value = input.text.trim();
    if (!_email.hasMatch(value)) {
      setState(() => error = 'Введите адрес почты, например client@mail.ru');
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Кому отправить?'),
    content: SizedBox(
      width: 380,
      child: TextField(
        key: const Key('outbound-recipient'),
        controller: input,
        autofocus: true,
        keyboardType: TextInputType.emailAddress,
        decoration: InputDecoration(
          labelText: 'Адрес почты получателя',
          errorText: error,
        ),
        onSubmitted: (_) => _submit(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton.icon(
        key: const Key('outbound-recipient-send'),
        onPressed: _submit,
        icon: const Icon(Icons.send_outlined, size: 18),
        label: const Text('Отправить'),
      ),
    ],
  );
}
