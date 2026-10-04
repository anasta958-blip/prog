import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sklad_komforta_app/core/widgets/app_notice.dart';
import 'package:sklad_komforta_app/core/widgets/app_select_field.dart';
import 'package:sklad_komforta_app/features/outbound/outbound_models.dart';
import 'package:sklad_komforta_app/features/outbound/outbound_settings_controller.dart';

const _muted = Color(0xFF8FA4C2);
const _border = Color(0xFF293A51);
const _accent = Color(0xFF4D8DFF);

/// Сервер SMTP для известных почт, как на сервере: подсказка без запроса.
String? detectSmtpServer(String address) {
  final at = address.lastIndexOf('@');
  if (at < 0) return null;
  return switch (address.substring(at + 1).trim().toLowerCase()) {
    'gmail.com' || 'googlemail.com' => 'smtp.gmail.com:465',
    'yandex.ru' ||
    'ya.ru' ||
    'yandex.com' ||
    'yandex.by' ||
    'yandex.kz' ||
    'narod.ru' => 'smtp.yandex.ru:465',
    'mail.ru' ||
    'inbox.ru' ||
    'list.ru' ||
    'bk.ru' ||
    'internet.ru' => 'smtp.mail.ru:465',
    _ => null,
  };
}

/// Раздел «Внешняя отправка»: Telegram и почта. Сохранение выполняет
/// владелец ([OutboundSettingsController.save]) — кнопкой страницы настроек.
final class OutboundSettingsEditor extends StatelessWidget {
  const OutboundSettingsEditor({required this.controller, super.key});

  final OutboundSettingsController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      if (controller.forbidden) {
        return const _Notice(
          icon: Icons.lock_outline,
          text: 'Нет права «Настройка внешней отправки».',
        );
      }
      if (!controller.loaded) {
        return controller.loading
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            : _Notice(
                icon: Icons.error_outline,
                text: controller.error ?? 'Настройки отправки не загружены.',
                action: TextButton(
                  onPressed: () => controller.load(force: true),
                  child: const Text('Повторить'),
                ),
              );
      }
      final telegram = _TelegramSection(controller: controller);
      final email = _EmailSection(controller: controller);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Кнопка «Отправить» в КП, ПКП и комплектации и в меню карточки '
            'отправляет PDF — тот же, что при печати. Имя файла: название '
            'карточки и дата. Способ появляется в кнопке, когда он заполнен.',
            style: TextStyle(color: _muted),
          ),
          const SizedBox(height: 14),
          if (controller.error case final error?) ...[
            _Banner(text: error, error: true),
            const SizedBox(height: 12),
          ] else if (controller.message case final message?) ...[
            AutoDismissNotice(
              message: message,
              child: _Banner(text: message, error: false),
            ),
            const SizedBox(height: 12),
          ],
          LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth >= 1000
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: telegram),
                      const SizedBox(width: 16),
                      Expanded(child: email),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [telegram, const SizedBox(height: 16), email],
                  ),
          ),
          const SizedBox(height: 16),
          const _PlaceholderHelp(),
        ],
      );
    },
  );
}

final class _TelegramSection extends StatelessWidget {
  const _TelegramSection({required this.controller});

  final OutboundSettingsController controller;

  @override
  Widget build(BuildContext context) {
    final settings = controller.settings;
    final revision = controller.revision;
    void changed(VoidCallback update) {
      update();
      controller.changed();
    }

    final defaultTopicKnown = settings.topics.any(
      (topic) => topic.topicId == settings.defaultTopicId,
    );
    return _Section(
      icon: Icons.send_outlined,
      title: 'Telegram',
      channel: OutboundChannel.telegram,
      testing: controller.testing == OutboundChannel.telegram,
      onTest: controller.busy
          ? null
          : () => controller.test(OutboundChannel.telegram),
      children: [
        _SecretField(
          key: ValueKey('outbound-bot-token-$revision'),
          label: 'Токен бота',
          saved: settings.hasBotToken && !settings.clearBotToken,
          hint: 'Выдаёт @BotFather: 123456789:AA…',
          onChanged: (value) => changed(() => settings.botToken = value),
          onClear: () => changed(() {
            settings.botToken = '';
            settings.clearBotToken = true;
          }),
        ),
        _TextField(
          key: ValueKey('outbound-chat-id-$revision'),
          label: 'ID группы',
          initialValue: settings.chatId,
          helper:
              'Число вида -1001234567890 или @имя группы. Бот должен быть '
              'добавлен в группу и иметь право отправлять сообщения.',
          onChanged: (value) => changed(() => settings.chatId = value),
        ),
        SwitchListTile(
          key: const Key('outbound-uses-topics'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Группа с топиками'),
          subtitle: const Text('Документы отправляются в топик группы'),
          value: settings.usesTopics,
          onChanged: (value) => changed(() => settings.usesTopics = value),
        ),
        if (settings.usesTopics) ...[
          _TopicsEditor(
            key: ValueKey('outbound-topics-$revision'),
            topics: settings.topics,
            onChanged: (topics) => changed(() {
              settings.topics = topics;
              if (!topics.any(
                (topic) => topic.topicId == settings.defaultTopicId,
              )) {
                settings.defaultTopicId = null;
              }
            }),
          ),
          AppSelectField<int?>(
            key: ValueKey(
              'outbound-default-topic-${settings.topics.length}-'
              '${settings.defaultTopicId}',
            ),
            label: 'Топик по умолчанию',
            value: defaultTopicKnown ? settings.defaultTopicId : null,
            options: [
              const AppSelectOption<int?>(
                value: null,
                label: 'Не задан — выбирать при отправке',
              ),
              for (final topic in settings.topics)
                AppSelectOption<int?>(
                  value: topic.topicId,
                  label: '${topic.name} (${topic.topicId})',
                ),
            ],
            onChanged: (value) =>
                changed(() => settings.defaultTopicId = value),
          ),
        ],
        _TemplateField(
          key: ValueKey('outbound-caption-$revision'),
          label: 'Подпись к файлу',
          initialValue: settings.captionTemplate,
          emptyHint: 'Пусто — в группу уйдёт только файл',
          onChanged: (value) => changed(() => settings.captionTemplate = value),
        ),
      ],
    );
  }
}

final class _EmailSection extends StatelessWidget {
  const _EmailSection({required this.controller});

  final OutboundSettingsController controller;

  @override
  Widget build(BuildContext context) {
    final settings = controller.settings;
    final revision = controller.revision;
    void changed(VoidCallback update) {
      update();
      controller.changed();
    }

    final address = settings.address.trim();
    final detected = detectSmtpServer(address);
    return _Section(
      icon: Icons.mail_outline,
      title: 'Почта',
      channel: OutboundChannel.email,
      testing: controller.testing == OutboundChannel.email,
      onTest: controller.busy
          ? null
          : () => controller.test(OutboundChannel.email),
      children: [
        _TextField(
          key: ValueKey('outbound-address-$revision'),
          label: 'Адрес почты отправителя',
          initialValue: settings.address,
          keyboardType: TextInputType.emailAddress,
          helper: detected != null
              ? 'Сервер определён автоматически: $detected'
              : address.contains('@')
              ? 'Для этой почты укажите сервер SMTP и порт ниже.'
              : null,
          onChanged: (value) => changed(() => settings.address = value),
        ),
        _SecretField(
          key: ValueKey('outbound-password-$revision'),
          label: 'Пароль приложения',
          saved: settings.hasPassword && !settings.clearPassword,
          hint:
              'Создаётся в настройках безопасности почты; обычный пароль '
              'не подойдёт. При смене адреса введите пароль заново.',
          onChanged: (value) => changed(() => settings.password = value),
          onClear: () => changed(() {
            settings.password = '';
            settings.clearPassword = true;
          }),
        ),
        if (address.contains('@') && detected == null)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _TextField(
                  key: ValueKey('outbound-smtp-host-$revision'),
                  label: 'Сервер SMTP',
                  initialValue: settings.smtpHost,
                  helper: 'Например: smtp.company.ru',
                  onChanged: (value) =>
                      changed(() => settings.smtpHost = value),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 130,
                child: AppSelectField<int?>(
                  key: ValueKey('outbound-smtp-port-${settings.smtpPort}'),
                  label: 'Порт',
                  value: settings.smtpPort,
                  options: const [
                    AppSelectOption(value: null, label: 'Выберите'),
                    AppSelectOption(value: 465, label: '465 (SSL)'),
                    AppSelectOption(value: 587, label: '587 (STARTTLS)'),
                    AppSelectOption(value: 25, label: '25'),
                    AppSelectOption(value: 2525, label: '2525'),
                  ],
                  onChanged: (value) =>
                      changed(() => settings.smtpPort = value),
                ),
              ),
            ],
          ),
        _TextField(
          key: ValueKey('outbound-sender-name-$revision'),
          label: 'От кого',
          initialValue: settings.senderName,
          helper: 'Имя отправителя в письме, например «Склад Комфорта»',
          onChanged: (value) => changed(() => settings.senderName = value),
        ),
        _TextField(
          key: ValueKey('outbound-recipient-$revision'),
          label: 'Получатель по умолчанию (необязательно)',
          initialValue: settings.defaultRecipient,
          keyboardType: TextInputType.emailAddress,
          helper: 'Пусто — адрес вводится при каждой отправке',
          onChanged: (value) =>
              changed(() => settings.defaultRecipient = value),
        ),
        _TemplateField(
          key: ValueKey('outbound-subject-$revision'),
          label: 'Тема письма',
          initialValue: settings.subjectTemplate,
          emptyHint: 'Пусто — тема по умолчанию: $outboundDefaultTemplate',
          onChanged: (value) => changed(() => settings.subjectTemplate = value),
        ),
        _TemplateField(
          key: ValueKey('outbound-body-$revision'),
          label: 'Текст письма (необязательно)',
          initialValue: settings.bodyTemplate,
          maxLines: 5,
          emptyHint: 'Пусто — письмо только с файлом',
          onChanged: (value) => changed(() => settings.bodyTemplate = value),
        ),
      ],
    );
  }
}

final class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.children,
    required this.testing,
    required this.onTest,
    required this.channel,
  });

  final OutboundChannel channel;
  final IconData icon;
  final String title;
  final List<Widget> children;
  final bool testing;
  final VoidCallback? onTest;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFF111A26),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _border),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: _accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              OutlinedButton.icon(
                key: Key('outbound-test-${channel.code}'),
                onPressed: onTest,
                icon: testing
                    ? const SizedBox.square(
                        dimension: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline, size: 17),
                label: const Text('Проверить'),
              ),
            ],
          ),
          for (final child in children) ...[const SizedBox(height: 14), child],
        ],
      ),
    ),
  );
}

final class _TextField extends StatelessWidget {
  const _TextField({
    required this.label,
    required this.initialValue,
    required this.onChanged,
    this.helper,
    this.keyboardType,
    super.key,
  });

  final String label;
  final String initialValue;
  final ValueChanged<String> onChanged;
  final String? helper;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) => TextFormField(
    initialValue: initialValue,
    keyboardType: keyboardType,
    decoration: InputDecoration(
      labelText: label,
      helperText: helper,
      helperMaxLines: 3,
    ),
    onChanged: onChanged,
  );
}

/// Поле секрета: сохранённое значение не показывается и не приходит с
/// сервера — можно ввести новое или удалить сохранённое.
final class _SecretField extends StatefulWidget {
  const _SecretField({
    required this.label,
    required this.saved,
    required this.hint,
    required this.onChanged,
    required this.onClear,
    super.key,
  });

  final String label;
  final bool saved;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  State<_SecretField> createState() => _SecretFieldState();
}

final class _SecretFieldState extends State<_SecretField> {
  final input = TextEditingController();
  bool visible = false;

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: input,
    obscureText: !visible,
    autocorrect: false,
    enableSuggestions: false,
    decoration: InputDecoration(
      labelText: widget.label,
      hintText: widget.saved ? '•••••••• сохранён' : null,
      helperText: widget.saved
          ? 'Сохранён. Введите новый, чтобы заменить.'
          : widget.hint,
      helperMaxLines: 3,
      suffixIcon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: visible ? 'Скрыть' : 'Показать',
            onPressed: () => setState(() => visible = !visible),
            icon: Icon(
              visible
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 18,
            ),
          ),
          if (widget.saved)
            IconButton(
              tooltip: 'Удалить сохранённый',
              onPressed: () {
                input.clear();
                widget.onClear();
              },
              icon: const Icon(Icons.delete_outline, size: 18),
            ),
        ],
      ),
    ),
    onChanged: widget.onChanged,
  );
}

/// Поле шаблона с примером результата подстановки.
final class _TemplateField extends StatefulWidget {
  const _TemplateField({
    required this.label,
    required this.initialValue,
    required this.emptyHint,
    required this.onChanged,
    this.maxLines = 2,
    super.key,
  });

  final String label;
  final String initialValue;
  final String emptyHint;
  final ValueChanged<String> onChanged;
  final int maxLines;

  @override
  State<_TemplateField> createState() => _TemplateFieldState();
}

final class _TemplateFieldState extends State<_TemplateField> {
  late String value = widget.initialValue;

  @override
  Widget build(BuildContext context) {
    final example = outboundTemplateExample(value);
    return TextFormField(
      initialValue: widget.initialValue,
      minLines: 1,
      maxLines: widget.maxLines,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: example.isEmpty ? widget.emptyHint : 'Пример: $example',
        helperMaxLines: 3,
      ),
      onChanged: (text) {
        setState(() => value = text);
        widget.onChanged(text);
      },
    );
  }
}

/// Справочник топиков: ID и понятное название.
final class _TopicsEditor extends StatefulWidget {
  const _TopicsEditor({
    required this.topics,
    required this.onChanged,
    super.key,
  });

  final List<OutboundTopic> topics;
  final ValueChanged<List<OutboundTopic>> onChanged;

  @override
  State<_TopicsEditor> createState() => _TopicsEditorState();
}

final class _TopicRow {
  _TopicRow(this.key, String id, String name)
    : id = TextEditingController(text: id),
      name = TextEditingController(text: name);

  final int key;
  final TextEditingController id;
  final TextEditingController name;
}

final class _TopicsEditorState extends State<_TopicsEditor> {
  late final List<_TopicRow> rows = [
    for (final (index, topic) in widget.topics.indexed)
      _TopicRow(index, '${topic.topicId}', topic.name),
  ];
  late int nextKey = rows.length;

  @override
  void dispose() {
    for (final row in rows) {
      row.id.dispose();
      row.name.dispose();
    }
    super.dispose();
  }

  /// Неполные строки (без ID или названия) не попадают в настройки.
  void _publish() => widget.onChanged([
    for (final row in rows)
      if (int.tryParse(row.id.text.trim()) case final id?
          when id > 0 && row.name.text.trim().isNotEmpty)
        OutboundTopic(topicId: id, name: row.name.text.trim()),
  ]);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Топики', style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 4),
      const Text(
        'ID топика — число после последней «/» в ссылке на сообщение топика '
        '(t.me/c/1234567890/15 → 15).',
        style: TextStyle(color: _muted, fontSize: 12),
      ),
      const SizedBox(height: 8),
      for (final row in rows)
        Padding(
          key: ValueKey('outbound-topic-row-${row.key}'),
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              SizedBox(
                width: 110,
                child: TextField(
                  key: ValueKey('outbound-topic-id-${row.key}'),
                  controller: row.id,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'ID',
                    isDense: true,
                  ),
                  onChanged: (_) => _publish(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: ValueKey('outbound-topic-name-${row.key}'),
                  controller: row.name,
                  decoration: const InputDecoration(
                    labelText: 'Название',
                    isDense: true,
                  ),
                  onChanged: (_) => _publish(),
                ),
              ),
              IconButton(
                tooltip: 'Удалить топик',
                onPressed: () {
                  setState(() => rows.remove(row));
                  _publish();
                  row.id.dispose();
                  row.name.dispose();
                },
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      TextButton.icon(
        key: const Key('outbound-topic-add'),
        onPressed: () => setState(() => rows.add(_TopicRow(nextKey++, '', ''))),
        icon: const Icon(Icons.add),
        label: const Text('Добавить топик'),
      ),
    ],
  );
}

final class _PlaceholderHelp extends StatelessWidget {
  const _PlaceholderHelp();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _border),
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Подстановки в теме, подписи и тексте письма',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 18,
            runSpacing: 6,
            children: [
              for (final (code, meaning) in outboundTemplatePlaceholders)
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: code,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _accent,
                        ),
                      ),
                      TextSpan(
                        text: ' — $meaning',
                        style: const TextStyle(color: _muted),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

final class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.error});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: error ? const Color(0x33B83A4B) : const Color(0x2222C55E),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: error ? const Color(0xFFB83A4B) : const Color(0xFF22C55E),
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(
            error ? Icons.error_outline : Icons.check_circle_outline,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    ),
  );
}

final class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Row(
      children: [
        Icon(icon, color: _muted),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
        ?action,
      ],
    ),
  );
}
