import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sklad_komforta_app/core/widgets/app_select_field.dart';
import 'package:sklad_komforta_app/features/kanban/kanban_card_editor.dart';
import 'package:sklad_komforta_app/features/kanban/kanban_controller.dart';
import 'package:sklad_komforta_app/features/kanban/kanban_models.dart';

/// Рабочее пространство настроенных канбанов без содержимого КП/ПКП.
final class KanbanPage extends StatefulWidget {
  const KanbanPage({required this.controller, super.key});

  final KanbanController controller;

  @override
  State<KanbanPage> createState() => _KanbanPageState();
}

final class _KanbanPageState extends State<KanbanPage> {
  final ScrollController _horizontal = ScrollController();
  final GlobalKey _canvasKey = GlobalKey();
  Timer? _autoScrollTimer;
  double _autoScrollDirection = 0;
  bool _mobileToolbarExpanded = false;

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _horizontal.dispose();
    super.dispose();
  }

  void _updateAutoScroll(Offset globalPosition) {
    final renderObject = _canvasKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !_horizontal.hasClients) return;
    final local = renderObject.globalToLocal(globalPosition);
    const edge = 72.0;
    final nextDirection = local.dx < edge
        ? -1.0
        : local.dx > renderObject.size.width - edge
        ? 1.0
        : 0.0;
    if (nextDirection == _autoScrollDirection) return;
    _autoScrollDirection = nextDirection;
    _autoScrollTimer?.cancel();
    if (nextDirection == 0) return;
    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!_horizontal.hasClients) return;
      final position = _horizontal.position;
      final next = (position.pixels + _autoScrollDirection * 9).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (next != position.pixels) _horizontal.jumpTo(next);
    });
  }

  void _stopAutoScroll() {
    _autoScrollDirection = 0;
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  Future<void> _dropCard(
    KanbanCard card,
    String targetColumnId,
    int targetIndex,
  ) async {
    _stopAutoScroll();
    final moved = await widget.controller.moveCard(
      card,
      targetColumnId,
      targetIndex,
    );
    if (!moved && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.controller.error ?? 'Не удалось переместить карточку.',
          ),
        ),
      );
    }
  }

  Future<void> _openEditor(KanbanColumn column, {KanbanCard? card}) async {
    final board = widget.controller.board;
    if (board == null || board.categories.isEmpty) return;
    final availableCategories = board.categories;
    final draft = card == null
        ? KanbanCardDraft.create(board, column.id)
        : KanbanCardDraft.fromCard(card);
    if (card == null) {
      draft.categoryId = availableCategories.first.categoryId;
      draft.sectionId = availableCategories.first.sections.length == 1
          ? availableCategories.first.sections.single.id
          : null;
    } else if (draft.sectionId == null) {
      for (final category in availableCategories) {
        if (category.categoryId == draft.categoryId &&
            category.sections.length == 1) {
          draft.sectionId = category.sections.single.id;
          break;
        }
      }
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) => KanbanCardEditor(
          board: board,
          draft: draft,
          card: card,
          saving: widget.controller.saving,
          error: widget.controller.error,
          categories: availableCategories,
          onCancel: () => Navigator.of(dialogContext).pop(),
          onSave: () async {
            if (await widget.controller.saveCard(draft, card: card) &&
                dialogContext.mounted) {
              Navigator.of(dialogContext).pop();
            }
          },
          onDelete: card == null
              ? null
              : () async {
                  final confirmed = await showDialog<bool>(
                    context: dialogContext,
                    builder: (context) => AlertDialog(
                      title: const Text('Удалить карточку?'),
                      content: const Text(
                        'Карточка будет скрыта из канбана. Действие сохранится в аудите.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Отмена'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Удалить'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true &&
                      await widget.controller.deleteCard(card) &&
                      dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        // На узком desktop-окне полная панель уже не помещается, поэтому
        // используем тот же сворачиваемый вариант, что и на мобильных экранах.
        final compact = constraints.maxWidth < 860;
        return ColoredBox(
          color: const Color(0xFF0B1119),
          child: Column(
            children: [
              _Toolbar(
                controller: widget.controller,
                compact: compact,
                expanded: _mobileToolbarExpanded,
                onToggle: () => setState(
                  () => _mobileToolbarExpanded = !_mobileToolbarExpanded,
                ),
              ),
              Expanded(child: _body(compact)),
            ],
          ),
        );
      },
    ),
  );

  Widget _body(bool compact) {
    final controller = widget.controller;
    if (controller.loading && controller.board == null) {
      return const _LoadingBoard();
    }
    if (controller.error != null && controller.board == null) {
      return _MessageState(
        icon: Icons.cloud_off_outlined,
        title: 'Не удалось открыть канбан',
        message: controller.error!,
        actionLabel: 'Повторить',
        onAction: controller.reload,
      );
    }
    final board = controller.board;
    if (board == null) {
      return const _MessageState(
        icon: Icons.view_kanban_outlined,
        title: 'Канбаны ещё не настроены',
        message:
            'Создайте хотя бы один канбан в настройках организации. Он появится здесь автоматически.',
      );
    }
    if (board.columns.isEmpty) {
      return const _MessageState(
        icon: Icons.view_column_outlined,
        title: 'В канбане нет столбцов',
        message: 'Добавьте столбцы в настройках организации.',
      );
    }
    return KeyedSubtree(
      key: _canvasKey,
      child: ScrollConfiguration(
        behavior: const _KanbanScrollBehavior(),
        child: Scrollbar(
          controller: _horizontal,
          thumbVisibility: !compact,
          interactive: true,
          child: MouseRegion(
            cursor: SystemMouseCursors.grab,
            child: SingleChildScrollView(
              controller: _horizontal,
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.fromLTRB(compact ? 12 : 22, 16, 22, 22),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (
                    var index = 0;
                    index < board.columns.length;
                    index++
                  ) ...[
                    SizedBox(
                      width: compact ? 286 : 318,
                      child: _KanbanColumnPanel(
                        controller: controller,
                        board: board,
                        column: board.columns[index],
                        isFirst: index == 0,
                        canCreate: board.categories.isNotEmpty,
                        onCreate: () => _openEditor(board.columns[index]),
                        onOpen: (card) =>
                            _openEditor(board.columns[index], card: card),
                        onDrop: (card, targetIndex) => _dropCard(
                          card,
                          board.columns[index].id,
                          targetIndex,
                        ),
                        onDragMove: _updateAutoScroll,
                        onDragEnd: _stopAutoScroll,
                      ),
                    ),
                    if (index != board.columns.length - 1)
                      const SizedBox(width: 12),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Разрешает прокручивать только рабочий холст канбана перетаскиванием мышью.
/// Остальные списки приложения сохраняют стандартное desktop-поведение.
final class _KanbanScrollBehavior extends MaterialScrollBehavior {
  const _KanbanScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    ...super.dragDevices,
    PointerDeviceKind.mouse,
  };
}

final class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.controller,
    required this.compact,
    required this.expanded,
    required this.onToggle,
  });

  final KanbanController controller;
  final bool compact;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final selector = _BoardSelector(controller: controller);
    if (compact) {
      return DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0xFF101823),
          border: Border(bottom: BorderSide(color: Color(0xFF253348))),
        ),
        child: Column(
          children: [
            InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.view_kanban_outlined,
                      color: Color(0xFF4D8DFF),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        controller.board?.name ?? 'Канбаны',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    AnimatedRotation(
                      turns: expanded ? .5 : 0,
                      duration: const Duration(milliseconds: 160),
                      child: const Icon(Icons.expand_more),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Row(
                  children: [
                    Expanded(child: selector),
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      tooltip: 'Обновить',
                      onPressed: controller.loading ? null : controller.reload,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ),
              crossFadeState: expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 180),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 14),
      decoration: const BoxDecoration(
        color: Color(0xFF101823),
        border: Border(bottom: BorderSide(color: Color(0xFF253348))),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.view_kanban_outlined,
            color: Color(0xFF4D8DFF),
            size: 28,
          ),
          const SizedBox(width: 12),
          const Text(
            'Канбаны',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 24),
          SizedBox(width: 320, child: selector),
          const Spacer(),
          if (controller.board case final board?)
            _MetaChip(
              icon: Icons.view_column_outlined,
              label: '${board.columns.length} столбцов',
            ),
          const SizedBox(width: 8),
          IconButton.outlined(
            tooltip: 'Обновить канбан',
            onPressed: controller.loading ? null : controller.reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }
}

final class _BoardSelector extends StatelessWidget {
  const _BoardSelector({required this.controller});

  final KanbanController controller;

  @override
  Widget build(BuildContext context) => AppSelectField<String>(
    value: controller.board?.id,
    label: 'Рабочий канбан',
    isDense: true,
    enabled: !controller.loading,
    options: controller.boards
        .map(
          (board) =>
              AppSelectOption<String>(value: board.id, label: board.name),
        )
        .toList(growable: false),
    onChanged: controller.loading
        ? null
        : (value) {
            if (value != null) controller.selectBoard(value);
          },
  );
}

final class _KanbanColumnPanel extends StatelessWidget {
  const _KanbanColumnPanel({
    required this.controller,
    required this.board,
    required this.column,
    required this.isFirst,
    required this.canCreate,
    required this.onCreate,
    required this.onOpen,
    required this.onDrop,
    required this.onDragMove,
    required this.onDragEnd,
  });

  final KanbanController controller;
  final KanbanBoard board;
  final KanbanColumn column;
  final bool isFirst;
  final bool canCreate;
  final VoidCallback onCreate;
  final ValueChanged<KanbanCard> onOpen;
  final Future<void> Function(KanbanCard card, int targetIndex) onDrop;
  final ValueChanged<Offset> onDragMove;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final accent = _parseColor(column.color);
    final page = controller.pageFor(column.id);
    final busy = controller.isColumnLoading(column.id);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111A26),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFF27364B)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(height: 3, color: accent),
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 13, 12, 12),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    column.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                _CountBadge(count: page?.total ?? 0),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: !canCreate
                      ? 'Создание карточек отключено настройками канбана'
                      : 'Добавить карточку',
                  onPressed: !canCreate || controller.saving ? null : onCreate,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.add, size: 20),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: busy && page == null
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : page == null || page.items.isEmpty
                ? _InsertionTarget(
                    controller: controller,
                    targetColumnId: column.id,
                    targetIndex: 0,
                    onDrop: onDrop,
                    onDragMove: onDragMove,
                    child: _EmptyColumn(
                      isFirst: isFirst,
                      canCreate: canCreate,
                      hasCategories: board.categories.isNotEmpty,
                      onCreate: onCreate,
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(10),
                    itemCount: page.items.length * 2 + 1,
                    itemBuilder: (context, index) {
                      if (index.isEven) {
                        return _InsertionTarget(
                          controller: controller,
                          targetColumnId: column.id,
                          targetIndex: index ~/ 2,
                          onDrop: onDrop,
                          onDragMove: onDragMove,
                          isTrailing: index == page.items.length * 2,
                        );
                      }
                      final card = page.items[index ~/ 2];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: _KanbanCardTile(
                          card: card,
                          board: board,
                          accent: accent,
                          onTap: () => onOpen(card),
                          onDragMove: onDragMove,
                          onDragEnd: onDragEnd,
                        ),
                      );
                    },
                  ),
          ),
          if (page != null && page.pageCount > 1) ...[
            const Divider(height: 1),
            _ColumnPager(
              page: page,
              busy: busy,
              onPage: (value) => controller.loadColumn(column.id, page: value),
            ),
          ],
        ],
      ),
    );
  }
}

final class _EmptyColumn extends StatelessWidget {
  const _EmptyColumn({
    required this.isFirst,
    required this.canCreate,
    required this.hasCategories,
    required this.onCreate,
  });

  final bool isFirst;
  final bool canCreate;
  final bool hasCategories;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isFirst ? Icons.note_add_outlined : Icons.inbox_outlined,
            size: 32,
            color: const Color(0xFF637C9F),
          ),
          const SizedBox(height: 10),
          Text(
            canCreate
                ? 'В этом столбце пока нет карточек'
                : hasCategories
                ? 'Создание карточек отключено настройками канбана'
                : 'Назначьте канбану хотя бы одну категорию',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF8EA3C0),
              fontSize: 12,
              height: 1.35,
            ),
          ),
          if (canCreate) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add, size: 17),
              label: const Text('Создать карточку'),
            ),
          ],
        ],
      ),
    ),
  );
}

final class _CardDragPayload {
  const _CardDragPayload(this.card);

  final KanbanCard card;
}

/// Точная позиция вставки между карточками. Клиентская проверка нужна для
/// понятной подсветки, а окончательное решение всегда принимает backend.
final class _InsertionTarget extends StatelessWidget {
  const _InsertionTarget({
    required this.controller,
    required this.targetColumnId,
    required this.targetIndex,
    required this.onDrop,
    required this.onDragMove,
    this.child,
    this.isTrailing = false,
  });

  final KanbanController controller;
  final String targetColumnId;
  final int targetIndex;
  final Future<void> Function(KanbanCard card, int targetIndex) onDrop;
  final ValueChanged<Offset> onDragMove;
  final Widget? child;
  final bool isTrailing;

  @override
  Widget build(BuildContext context) => DragTarget<_CardDragPayload>(
    onWillAcceptWithDetails: (details) =>
        controller.canMoveCard(details.data.card, targetColumnId),
    onMove: (details) => onDragMove(details.offset),
    onAcceptWithDetails: (details) => onDrop(details.data.card, targetIndex),
    builder: (context, candidates, rejected) {
      final active = candidates.isNotEmpty;
      if (child != null) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: active ? const Color(0x174D8DFF) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: active
                ? Border.all(color: const Color(0xFF4D8DFF), width: 1.5)
                : null,
          ),
          child: child,
        );
      }
      return AnimatedContainer(
        duration: const Duration(milliseconds: 110),
        height: isTrailing ? (active ? 130 : 90) : (active ? 24 : 7),
        margin: const EdgeInsets.symmetric(horizontal: 3),
        alignment: Alignment.center,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          height: active ? 3 : 0,
          decoration: BoxDecoration(
            color: const Color(0xFF4D8DFF),
            borderRadius: BorderRadius.circular(99),
            boxShadow: active
                ? const [BoxShadow(color: Color(0x664D8DFF), blurRadius: 8)]
                : null,
          ),
        ),
      );
    },
  );
}

/// Компактная операционная карточка выбранного варианта дизайна.
final class _KanbanCardTile extends StatelessWidget {
  const _KanbanCardTile({
    required this.card,
    required this.board,
    required this.accent,
    required this.onTap,
    required this.onDragMove,
    required this.onDragEnd,
    this.dragPreview = false,
  });

  final KanbanCard card;
  final KanbanBoard board;
  final Color accent;
  final VoidCallback onTap;
  final ValueChanged<Offset> onDragMove;
  final VoidCallback onDragEnd;
  final bool dragPreview;

  KanbanCategory? get category {
    for (final item in board.categories) {
      if (item.categoryId == card.categoryId) return item;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final configuredFields =
        category?.fields
            .where(
              (field) =>
                  field.code != 'name' &&
                  field.fieldType != 'relation' &&
                  card.values.containsKey(field.code),
            )
            .take(3)
            .toList(growable: false) ??
        const <KanbanField>[];
    final cardBody = Material(
      color: const Color(0xFF151F2E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(11),
        side: const BorderSide(color: Color(0xFF2A3A51)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: dragPreview ? null : onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(height: 3, color: accent),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '№${card.number}',
                    style: const TextStyle(
                      color: Color(0xFF8EA5C4),
                      fontSize: 11,
                    ),
                  ),
                  if (category != null) ...[
                    const SizedBox(height: 9),
                    _CategoryChip(label: category!.name, accent: accent),
                  ],
                  for (final field in configuredFields) ...[
                    const SizedBox(height: 8),
                    _CardValue(
                      label: field.label,
                      value: _displayValue(field, card.values[field.code]),
                    ),
                  ],
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      const Icon(
                        Icons.person_outline,
                        size: 14,
                        color: Color(0xFF7188A8),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          card.updatedByName ?? card.createdByName ?? 'Система',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF93A9C6),
                            fontSize: 10,
                          ),
                        ),
                      ),
                      Text(
                        DateFormat(
                          'dd.MM.yy, HH:mm',
                          'ru',
                        ).format(card.updatedAt.toLocal()),
                        style: const TextStyle(
                          color: Color(0xFF7188A8),
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (dragPreview) return cardBody;

    return Draggable<_CardDragPayload>(
      data: _CardDragPayload(card),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 292,
          child: Opacity(
            opacity: .92,
            child: _KanbanCardTile(
              card: card,
              board: board,
              accent: accent,
              onTap: () {},
              onDragMove: (_) {},
              onDragEnd: () {},
              dragPreview: true,
            ),
          ),
        ),
      ),
      onDragUpdate: (details) => onDragMove(details.globalPosition),
      onDragEnd: (_) => onDragEnd(),
      childWhenDragging: Opacity(
        opacity: .35,
        child: _KanbanCardTile(
          card: card,
          board: board,
          accent: accent,
          onTap: () {},
          onDragMove: (_) {},
          onDragEnd: () {},
          dragPreview: true,
        ),
      ),
      child: MouseRegion(cursor: SystemMouseCursors.grab, child: cardBody),
    );
  }

  String _displayValue(KanbanField field, dynamic value) {
    if (value == null) return '—';
    if (field.fieldType == 'boolean') return value == true ? 'Да' : 'Нет';
    if (field.fieldType == 'dictionary') {
      for (final option in field.options) {
        if (option.value == value) return option.value;
      }
    }
    if (field.fieldType == 'money' && value is num) {
      return NumberFormat.currency(
        locale: 'ru_RU',
        symbol: '₽',
        decimalDigits: 0,
      ).format(value);
    }
    if (field.fieldType == 'percent') return '$value%';
    return '$value';
  }
}

final class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label, required this.accent});
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: accent.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: accent.withValues(alpha: .4)),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: accent,
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

final class _CardValue extends StatelessWidget {
  const _CardValue({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFF7188A8), fontSize: 10),
        ),
      ),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
    ],
  );
}

final class _ColumnPager extends StatelessWidget {
  const _ColumnPager({
    required this.page,
    required this.busy,
    required this.onPage,
  });

  final KanbanCardPage page;
  final bool busy;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'Предыдущая страница',
          visualDensity: VisualDensity.compact,
          onPressed: busy || page.page <= 1
              ? null
              : () => onPage(page.page - 1),
          icon: const Icon(Icons.chevron_left, size: 20),
        ),
        Text(
          '${page.page} / ${page.pageCount}',
          style: const TextStyle(color: Color(0xFFA1B4CE), fontSize: 11),
        ),
        IconButton(
          tooltip: 'Следующая страница',
          visualDensity: VisualDensity.compact,
          onPressed: busy || page.page >= page.pageCount
              ? null
              : () => onPage(page.page + 1),
          icon: const Icon(Icons.chevron_right, size: 20),
        ),
      ],
    ),
  );
}

final class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFF142033),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFF293A53)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF7FAEFF)),
        const SizedBox(width: 7),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    ),
  );
}

final class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 25),
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xFF1B2940),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: const Color(0xFF2D4261)),
    ),
    child: Text(
      '$count',
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 11, color: Color(0xFFAEC3DF)),
    ),
  );
}

final class _LoadingBoard extends StatelessWidget {
  const _LoadingBoard();

  @override
  Widget build(BuildContext context) => ListView.separated(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.all(22),
    itemCount: 4,
    separatorBuilder: (_, _) => const SizedBox(width: 12),
    itemBuilder: (_, _) => Container(
      width: 318,
      decoration: BoxDecoration(
        color: const Color(0xFF111A26),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFF27364B)),
      ),
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    ),
  );
}

final class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: const Color(0xFF6685B1)),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF91A6C3), height: 1.45),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

Color _parseColor(String value) {
  final normalized = value.replaceFirst('#', '');
  final parsed = int.tryParse(normalized, radix: 16);
  return parsed == null ? const Color(0xFF4D8DFF) : Color(0xFF000000 | parsed);
}
