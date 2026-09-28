import 'package:flutter/material.dart';

/// Стрелка сворачивания блока.
///
/// Во всём приложении блок сворачивается и разворачивается только этой
/// кнопкой. Нажатие на остальную часть заголовка выполняет основное действие
/// заголовка (выбор, переход) либо ничего не делает, чтобы случайный клик по
/// названию не прятал содержимое.
final class CollapseToggle extends StatelessWidget {
  const CollapseToggle({
    required this.expanded,
    required this.onPressed,
    this.expandTooltip = 'Развернуть',
    this.collapseTooltip = 'Свернуть',
    this.color,
    this.size = 20,
    this.compact = false,
    super.key,
  });

  final bool expanded;
  final VoidCallback? onPressed;

  /// Подсказка и доступное имя кнопки в свёрнутом состоянии.
  final String expandTooltip;

  /// Подсказка и доступное имя кнопки в развёрнутом состоянии.
  final String collapseTooltip;
  final Color? color;
  final double size;

  /// Уменьшенные отступы для плотных строк.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final label = expanded ? collapseTooltip : expandTooltip;
    // Подсказка видна при наведении, а экранный диктор получает то же
    // название как метку кнопки (подсказка сама по себе меткой не является).
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      onTap: onPressed,
      excludeSemantics: true,
      child: IconButton(
        tooltip: label,
        onPressed: onPressed,
        color: color,
        visualDensity: compact ? VisualDensity.compact : null,
        icon: AnimatedRotation(
          // Развёрнуто — стрелка вниз, свёрнуто — вправо.
          turns: expanded ? 0 : -0.25,
          duration: const Duration(milliseconds: 160),
          child: Icon(Icons.expand_more, size: size),
        ),
      ),
    );
  }
}
