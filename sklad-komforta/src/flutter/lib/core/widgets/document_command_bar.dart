import 'package:flutter/material.dart';
import 'workspace_header.dart';

/// Команда редактора с одинаковой семантикой в кнопке и меню.
class DocumentCommand {
  const DocumentCommand(this.label, this.icon, this.onPressed);
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
}

/// Общая адаптивная шапка документов. До 600 px вторичные команды находятся
/// в меню; номер документа и выход остаются видимыми. Колбэки не меняют
/// существующие правила сохранения, печати и выхода из редактора.
class DocumentCommandBar extends StatelessWidget {
  const DocumentCommandBar({
    super.key,
    required this.title,
    required this.shortTitle,
    required this.onBack,
    required this.onSave,
    required this.saving,
    required this.commands,
    this.extra,
    this.selector,
  });
  final String title;
  final String shortTitle;
  final VoidCallback onBack;
  final VoidCallback onSave;
  final bool saving;
  final List<DocumentCommand> commands;
  final Widget? extra;
  final Widget? selector;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final narrow = constraints.maxWidth < 600;
      final icons = constraints.maxWidth < 1100;
      final menu = MenuAnchor(
        menuChildren: [
          for (final command in commands)
            MenuItemButton(
              onPressed: command.onPressed,
              leadingIcon: Icon(command.icon),
              child: Text(command.label),
            ),
          if (extra != null)
            Padding(padding: const EdgeInsets.all(8), child: extra),
          if (selector != null)
            SizedBox(
              width: 230,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: selector,
              ),
            ),
        ],
        builder: (context, controller, _) => IconButton(
          tooltip: 'Ещё',
          icon: const Icon(Icons.more_vert),
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
        ),
      );
      return DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0xFF0F1722),
          border: Border(bottom: BorderSide(color: Color(0xFF293A51))),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: workspaceHeaderHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Назад',
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back),
                ),
                Expanded(
                  child: Text(
                    constraints.maxWidth < 760 ? shortTitle : title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (constraints.maxWidth < 760)
                  IconButton.filled(
                    tooltip: 'Сохранить',
                    onPressed: saving ? null : onSave,
                    icon: saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                  )
                else
                  FilledButton.icon(
                    onPressed: saving ? null : onSave,
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: const Text('Сохранить'),
                  ),
                if (narrow)
                  menu
                else ...[
                  for (final command in commands)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: icons
                          ? IconButton.outlined(
                              tooltip: command.label,
                              onPressed: command.onPressed,
                              icon: Icon(command.icon, size: 18),
                            )
                          : OutlinedButton.icon(
                              onPressed: command.onPressed,
                              icon: Icon(command.icon, size: 18),
                              label: Text(command.label),
                            ),
                    ),
                  ?extra,
                  if (selector != null)
                    SizedBox(
                      width: 135,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: selector,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}
