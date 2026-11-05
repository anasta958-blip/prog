import 'package:flutter/material.dart';

const documentLayoutSettingsPath = 'Компания → Конструктор ссылки и PDF';

Future<void> showDocumentLayoutRequiredDialog(
  BuildContext context, {
  required String documentName,
  Future<void> Function()? onOpenSettings,
}) async {
  final openSettings = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Внешний вид не настроен'),
      content: Text(
        'Для канбана не настроен внешний вид $documentName. '
        'Откройте «$documentLayoutSettingsPath» и сохраните настройку.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Закрыть'),
        ),
        if (onOpenSettings != null)
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Перейти в настройки'),
          ),
      ],
    ),
  );
  if (openSettings == true) await onOpenSettings?.call();
}
