import 'package:flutter/material.dart';
import 'package:sklad_komforta_app/core/widgets/collapse_toggle.dart';

/// Сворачивает служебную навигацию страницы на узком экране.
///
/// На desktop и tablet [child] возвращается без дополнительной обёртки, поэтому
/// существующая компоновка не меняется. На телефоне панель закрыта по умолчанию
/// и занимает только одну компактную строку над основным содержимым.
final class MobileCollapsibleNavigation extends StatefulWidget {
  const MobileCollapsibleNavigation({
    required this.title,
    required this.child,
    this.summary,
    this.breakpoint = 600,
    super.key,
  });

  final String title;
  final String? summary;
  final Widget child;
  final double breakpoint;

  @override
  State<MobileCollapsibleNavigation> createState() =>
      _MobileCollapsibleNavigationState();
}

final class _MobileCollapsibleNavigationState
    extends State<MobileCollapsibleNavigation> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= widget.breakpoint) {
      return widget.child;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: const Color(0xFF131D2A),
          shape: const Border(bottom: BorderSide(color: Color(0xFF29384D))),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 4, 2),
            child: Row(
              children: [
                const Icon(Icons.tune, size: 18, color: Color(0xFF6DA2FF)),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (widget.summary case final summary?) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF8FA4C2),
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                CollapseToggle(
                  expanded: expanded,
                  compact: true,
                  onPressed: () => setState(() => expanded = !expanded),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: expanded ? widget.child : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
