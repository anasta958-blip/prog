import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:sklad_komforta_app/core/widgets/collapse_toggle.dart';
import 'package:sklad_komforta_app/core/widgets/app_notice.dart';
import 'package:intl/intl.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/models/workflow_specialization.dart';
import 'package:sklad_komforta_app/core/widgets/app_select_field.dart';
import 'package:sklad_komforta_app/features/auth/auth_controller.dart';
import 'package:sklad_komforta_app/features/kanban/kanban_card_editor.dart';
import 'package:sklad_komforta_app/features/kanban/kanban_controller.dart';
import 'package:sklad_komforta_app/features/kanban/kanban_models.dart';
import 'package:sklad_komforta_app/features/quotes/quote_editor_page.dart';
import 'package:sklad_komforta_app/features/quotes/quote_models.dart';

/// Рабочее пространство настроенных канбанов без содержимого КП/ПКП.
final class KanbanPage extends StatefulWidget {
  const KanbanPage({
    required this.controller,
    this.config,
    this.authController,
    super.key,
  });

  final KanbanController controller;
  final AppConfig? config;
  final AuthController? authController;

  @override
  State<KanbanPage> createState() => _KanbanPageState();
}

final class _KanbanPageState extends State<KanbanPage> {
  final ScrollController _horizontal = ScrollController();
  final GlobalKey _canvasKey = GlobalKey();
  Timer? _autoScrollTimer;
  double _autoScrollDirection = 0;
  bool _mobileToolbarExpanded = false;
  bool _openingClientLink = false;

  Future<void> _openClientLink(KanbanCard card) async {
    final config = widget.config;
    final auth = widget.authController;
    if (_openingClientLink || config == null || auth == null) return;
    setState(() => _openingClientLink = true);
    try {
      await showQuoteClientAccessDialog(
        context: context,
        config: config,
        auth: auth,
        boardId: card.workflowId,
        cardId: card.id,
      );
    } finally {
      if (mounted) setState(() => _openingClientLink = false);
    }
  }

  KanbanCard? _openedQuoteCard;
  String? _newQuoteColumnId;
  QuoteKind? _newQuoteKind;
  KanbanBoard? _quoteBoard;

  bool get _quoteEditorOpen =>
      _quoteBoard != null &&
      widget.config != null &&
      widget.authController != null;

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
        AppSnackBar(
          content: Text(
            widget.controller.error ?? 'Не удалось переместить карточку.',
          ),
        ),
      );
    }
  }

  Future<void> _deleteCard(KanbanCard card) async {
    final board = widget.controller.board;
    if (board == null || widget.controller.saving) return;
    final specialized = board.specialization != WorkflowSpecialization.standard;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.delete_outline, color: Color(0xFFEF6674)),
        title: Text(specialized ? 'Удалить документ?' : 'Удалить карточку?'),
        content: Text(
          specialized
              ? 'Карточка и связанное содержимое будут удалены из рабочего канбана. '
                    'Действие сохранится в аудите.'
              : 'Карточка будет удалена из рабочего канбана. '
                    'Действие сохранится в аудите.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB83A4B),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final deleted = await widget.controller.deleteCard(card);
    if (!mounted || deleted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      AppSnackBar(
        content: Text(
          widget.controller.error ?? 'Не удалось удалить карточку.',
        ),
      ),
    );
  }

  Future<void> _openEditor(KanbanColumn column, {KanbanCard? card}) async {
    final board = widget.controller.board;
    if (board == null || board.categories.isEmpty) return;
    final opensQuoteEditor =
        board.specialization == WorkflowSpecialization.quote ||
        board.specialization == WorkflowSpecialization.quoteAndPrequote;
    if (card != null &&
        opensQuoteEditor &&
        widget.config != null &&
        widget.authController != null) {
      _stopAutoScroll();
      setState(() {
        _openedQuoteCard = card;
        _quoteBoard = board;
      });
      return;
    }
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

  void _openSpecializedEditor(
    KanbanColumn column,
    WorkflowCreationAction action,
  ) {
    if (action == WorkflowCreationAction.order) {
      ScaffoldMessenger.of(context).showSnackBar(
        const AppSnackBar(
          content: Text(
            'Редактор комплектации будет подключён отдельным этапом.',
          ),
        ),
      );
      return;
    }
    if (widget.config == null || widget.authController == null) return;
    _stopAutoScroll();
    setState(() {
      _quoteBoard = widget.controller.board;
      _openedQuoteCard = null;
      _newQuoteColumnId = column.id;
      _newQuoteKind = action == WorkflowCreationAction.prequote
          ? QuoteKind.prequote
          : QuoteKind.quote;
    });
  }

  Future<void> _closeQuoteEditor() async {
    final card = _openedQuoteCard;
    final newColumnId = _newQuoteColumnId;
    final boardId = _quoteBoard?.id;
    if (card == null && newColumnId == null) return;
    final columnId = card?.columnId ?? newColumnId!;
    setState(() {
      _openedQuoteCard = null;
      _newQuoteColumnId = null;
      _newQuoteKind = null;
      _quoteBoard = null;
    });
    if (widget.controller.board?.id != boardId) return;
    final currentPage = widget.controller.pageFor(columnId)?.page ?? 1;
    await widget.controller.loadColumn(columnId, page: currentPage);
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
              if (!_quoteEditorOpen)
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
    if (_quoteEditorOpen) {
      return QuoteEditorPage(
        key: ValueKey(
          'quote:${_quoteBoard!.id}:${_openedQuoteCard?.id ?? _newQuoteColumnId}:${_newQuoteKind?.name}',
        ),
        config: widget.config!,
        authController: widget.authController!,
        board: _quoteBoard!,
        card: _openedQuoteCard,
        creationColumnId: _newQuoteColumnId,
        createKind: _newQuoteKind,
        onBack: () => unawaited(_closeQuoteEditor()),
      );
    }
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
                      width: compact ? 286 : 330,
                      child: _KanbanColumnPanel(
                        controller: controller,
                        board: board,
                        column: board.columns[index],
                        isFirst: index == 0,
                        canCreate:
                            board.categories.isNotEmpty &&
                            board.specialization ==
                                WorkflowSpecialization.standard,
                        onCreate: () => _openEditor(board.columns[index]),
                        onCreateSpecialized: (action) => _openSpecializedEditor(
                          board.columns[index],
                          action,
                        ),
                        onOpen: (card) =>
                            _openEditor(board.columns[index], card: card),
                        onDelete: _deleteCard,
                        onShare:
                            widget.config != null &&
                                widget.authController != null &&
                                (board.specialization ==
                                        WorkflowSpecialization.quote ||
                                    board.specialization ==
                                        WorkflowSpecialization.quoteAndPrequote)
                            ? _openClientLink
                            : null,
                        sharingBusy: _openingClientLink,
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
    final authorSelector = _CardAuthorSelector(controller: controller);
    if (compact) {
      return DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0xFF101823),
          border: Border(bottom: BorderSide(color: Color(0xFF253348))),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                  CollapseToggle(
                    expanded: expanded,
                    compact: true,
                    onPressed: onToggle,
                  ),
                ],
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  children: [
                    selector,
                    const SizedBox(height: 8),
                    _CardSearchField(controller: controller),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: authorSelector),
                        const SizedBox(width: 8),
                        IconButton.outlined(
                          tooltip: 'Обновить',
                          onPressed: controller.loading
                              ? null
                              : controller.reload,
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
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
          const SizedBox(width: 12),
          SizedBox(width: 320, child: authorSelector),
          const SizedBox(width: 12),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: _CardSearchField(controller: controller),
            ),
          ),
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

/// Поиск карточек по названию или номеру. Запрос отправляется через 350 мс
/// после окончания ввода, чтобы не нагружать сервер на каждую букву.
final class _CardSearchField extends StatefulWidget {
  const _CardSearchField({required this.controller});

  final KanbanController controller;

  @override
  State<_CardSearchField> createState() => _CardSearchFieldState();
}

final class _CardSearchFieldState extends State<_CardSearchField> {
  late final TextEditingController input = TextEditingController(
    text: widget.controller.cardSearch,
  );
  Timer? debounce;

  @override
  void dispose() {
    debounce?.cancel();
    input.dispose();
    super.dispose();
  }

  void _changed(String value) {
    debounce?.cancel();
    debounce = Timer(
      const Duration(milliseconds: 350),
      () => widget.controller.setCardSearch(value),
    );
    setState(() {});
  }

  void _clear() {
    debounce?.cancel();
    input.clear();
    widget.controller.setCardSearch('');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => TextField(
    key: const Key('kanban-card-search'),
    controller: input,
    onChanged: _changed,
    onSubmitted: (value) {
      debounce?.cancel();
      widget.controller.setCardSearch(value);
    },
    textInputAction: TextInputAction.search,
    style: const TextStyle(fontSize: 13),
    decoration: InputDecoration(
      isDense: true,
      hintText: 'Поиск: название или номер',
      prefixIcon: const Icon(Icons.search, size: 18),
      suffixIcon: input.text.isEmpty
          ? null
          : IconButton(
              tooltip: 'Очистить поиск',
              icon: const Icon(Icons.close, size: 16),
              onPressed: _clear,
            ),
    ),
  );
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

final class _CardAuthorSelector extends StatelessWidget {
  const _CardAuthorSelector({required this.controller});

  final KanbanController controller;

  @override
  Widget build(BuildContext context) {
    final users = controller.cardAuthors
        .where((author) => !author.isCurrentUser)
        .toList(growable: false);
    return AppSelectField<String>(
      value: controller.authorFilterKey,
      label: 'Карточки пользователя',
      isDense: true,
      enabled: !controller.loading,
      options: [
        const AppSelectOption(value: 'own', label: 'Свои'),
        for (final author in users) ...[
          AppSelectOption(
            value: 'user:${author.userId}',
            label: author.displayName,
          ),
          AppSelectOption(
            value: 'own:${author.userId}',
            label: 'Свои и ${author.displayName}',
          ),
        ],
      ],
      onChanged: controller.loading
          ? null
          : (value) {
              if (value != null) controller.selectAuthorFilter(value);
            },
    );
  }
}

final class _KanbanColumnPanel extends StatelessWidget {
  const _KanbanColumnPanel({
    required this.controller,
    required this.board,
    required this.column,
    required this.isFirst,
    required this.canCreate,
    required this.onCreate,
    required this.onCreateSpecialized,
    required this.onOpen,
    required this.onDelete,
    required this.onDrop,
    required this.onDragMove,
    required this.onDragEnd,
    this.onShare,
    this.sharingBusy = false,
  });

  final KanbanController controller;
  final KanbanBoard board;
  final KanbanColumn column;
  final bool isFirst;
  final bool canCreate;
  final VoidCallback onCreate;
  final ValueChanged<WorkflowCreationAction> onCreateSpecialized;
  final ValueChanged<KanbanCard> onOpen;
  final ValueChanged<KanbanCard> onDelete;
  final Future<void> Function(KanbanCard card, int targetIndex) onDrop;
  final ValueChanged<Offset> onDragMove;
  final VoidCallback onDragEnd;
  final ValueChanged<KanbanCard>? onShare;
  final bool sharingBusy;

  Future<void> _archiveCard(BuildContext context, KanbanCard card) async {
    final success = await controller.setArchived(card, !card.isArchived);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        AppSnackBar(
          content: Text(
            success
                ? (card.isArchived
                      ? 'Карточка возвращена из архива.'
                      : 'Карточка перемещена в архив.')
                : (controller.error ?? 'Не удалось изменить архив.'),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final accent = _parseColor(column.color);
    final page = controller.pageFor(column.id);
    final archive = controller.archiveFor(column.id);
    final archiveExpanded = controller.expandedArchives.contains(column.id);
    final busy = controller.isColumnLoading(column.id);
    final selectedTotal = page?.selectedTotal;
    final columnTotal = selectedTotal == null
        ? null
        : Text(
            'Выбрано на ${NumberFormat.currency(locale: 'ru_RU', symbol: '₽', decimalDigits: 2).format(selectedTotal)}',
            key: Key('kanban-column-total-${column.id}'),
            style: const TextStyle(
              color: Color(0xFF9FB6D6),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          );
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
                if (board.specialization == WorkflowSpecialization.standard)
                  IconButton(
                    tooltip: !canCreate
                        ? 'Создание карточек отключено настройками канбана'
                        : 'Добавить карточку',
                    onPressed: !canCreate || controller.saving
                        ? null
                        : onCreate,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.add, size: 20),
                  ),
              ],
            ),
          ),
          // Сумма выбранного стоит в одной строке с кнопками создания, а если
          // кнопок нет — отдельной строкой под заголовком.
          if (column.creationActions.isNotEmpty || columnTotal != null)
            Padding(
              padding: EdgeInsets.fromLTRB(
                column.creationActions.isEmpty ? 32 : 12,
                0,
                12,
                column.creationActions.isEmpty ? 10 : 11,
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final action in column.creationActions)
                    OutlinedButton.icon(
                      onPressed: controller.saving
                          ? null
                          : () => onCreateSpecialized(action),
                      icon: Icon(
                        action == WorkflowCreationAction.order
                            ? Icons.inventory_2_outlined
                            : Icons.description_outlined,
                        size: 17,
                      ),
                      label: Text(action.label),
                    ),
                  ?columnTotal,
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
                          onDelete: () => onDelete(card),
                          onShare: onShare == null
                              ? null
                              : () => onShare!(card),
                          sharingBusy: sharingBusy,
                          onArchive: controller.saving
                              ? null
                              : () => _archiveCard(context, card),
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
          const Divider(height: 1, indent: 10, endIndent: 10),
          // Архив — исключение из правила «сворачивать только стрелкой»:
          // строка целиком показывает и скрывает архив колонки.
          TextButton(
            onPressed: () => controller.toggleArchive(column.id),
            child: Row(
              children: [
                const Text('Архив'),
                const SizedBox(width: 8),
                Text('${archive?.total ?? 0}'),
                const Spacer(),
                AnimatedRotation(
                  turns: archiveExpanded ? 0 : -0.25,
                  duration: const Duration(milliseconds: 160),
                  child: const Icon(Icons.expand_more, size: 18),
                ),
              ],
            ),
          ),
          if (archiveExpanded)
            Flexible(
              child: Column(
                children: [
                  Expanded(
                    child: archive == null || archive.items.isEmpty
                        ? const Center(child: Text('Архив пуст'))
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                            itemCount: archive.items.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final card = archive.items[index];
                              return _KanbanCardTile(
                                card: card,
                                board: board,
                                accent: accent,
                                onTap: () => onOpen(card),
                                onDelete: () => onDelete(card),
                                onShare: onShare == null
                                    ? null
                                    : () => onShare!(card),
                                sharingBusy: sharingBusy,
                                onArchive: controller.saving
                                    ? null
                                    : () => _archiveCard(context, card),
                                onDragMove: (_) {},
                                onDragEnd: () {},
                              );
                            },
                          ),
                  ),
                  if (archive != null && archive.pageCount > 1)
                    _ColumnPager(
                      page: archive,
                      busy: controller.archiveLoading,
                      onPage: (value) =>
                          controller.loadArchive(column.id, page: value),
                    ),
                ],
              ),
            ),
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
    required this.onDelete,
    required this.onDragMove,
    required this.onDragEnd,
    this.dragPreview = false,
    this.onArchive,
    this.onShare,
    this.sharingBusy = false,
  });

  final KanbanCard card;
  final KanbanBoard board;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final ValueChanged<Offset> onDragMove;
  final VoidCallback onDragEnd;
  final bool dragPreview;
  final VoidCallback? onArchive;
  final VoidCallback? onShare;
  final bool sharingBusy;

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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          card.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            height: 1.25,
                          ),
                        ),
                      ),
                      if (!dragPreview) ...[
                        const SizedBox(width: 6),
                        if (!card.isArchived || onShare != null)
                          SizedBox.square(
                            dimension: 30,
                            child: PopupMenuButton<String>(
                              tooltip: 'Действия карточки',
                              enabled:
                                  onArchive != null ||
                                  (onShare != null && !sharingBusy),
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.more_vert, size: 18),
                              position: PopupMenuPosition.under,
                              offset: const Offset(0, 4),
                              menuPadding: const EdgeInsets.symmetric(
                                vertical: 4,
                              ),
                              constraints: const BoxConstraints.tightFor(
                                width: 112,
                              ),
                              onSelected: (action) {
                                if (action == 'share') {
                                  onShare?.call();
                                } else {
                                  onArchive?.call();
                                }
                              },
                              itemBuilder: (_) => [
                                if (onShare != null)
                                  PopupMenuItem(
                                    value: 'share',
                                    enabled: !sharingBusy,
                                    height: 32,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    child: const Text(
                                      'Ссылка',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                  ),
                                if (!card.isArchived)
                                  PopupMenuItem(
                                    value: 'archive',
                                    enabled: onArchive != null,
                                    height: 32,
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    child: Text(
                                      'В архив',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        SizedBox.square(
                          dimension: 30,
                          child: IconButton(
                            tooltip: 'Удалить',
                            onPressed: onDelete,
                            visualDensity: VisualDensity.standard,
                            constraints: const BoxConstraints.tightFor(
                              width: 30,
                              height: 30,
                            ),
                            padding: EdgeInsets.zero,
                            color: const Color(0xFFEF6674),
                            icon: const Icon(Icons.delete_outline, size: 18),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),
                  if (card.isArchived && !dragPreview)
                    TextButton.icon(
                      onPressed: onArchive,
                      icon: const Icon(Icons.unarchive_outlined, size: 16),
                      label: const Text('Из архива'),
                    ),
                  if (card.quote case final quote?)
                    _QuoteCardDetails(card: card, quote: quote)
                  else ...[
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
                            card.updatedByName ??
                                card.createdByName ??
                                'Система',
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
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (dragPreview || card.isArchived) return cardBody;

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
              onDelete: () {},
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
          onDelete: () {},
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

/// Подробности карточки КП/ПКП: номер, стороны, создание, выбранное с суммой,
/// просмотры ссылки, последнее изменение и последний перенос между колонками.
final class _QuoteCardDetails extends StatelessWidget {
  const _QuoteCardDetails({required this.card, required this.quote});

  final KanbanCard card;
  final KanbanQuoteSummary quote;

  static const _muted = Color(0xFF8EA5C4);
  static const _faint = Color(0xFF7188A8);

  static String _dateTime(DateTime value) =>
      DateFormat('dd.MM.yyyy, HH:mm', 'ru').format(value.toLocal());

  static String _money(double value) => NumberFormat.currency(
    locale: 'ru_RU',
    symbol: '₽',
    decimalDigits: 2,
  ).format(value);

  /// «Имя · Роль», без роли — только имя.
  static String _person(String? name, String? role) {
    final person = name?.trim().isNotEmpty == true ? name!.trim() : 'Система';
    return role?.trim().isNotEmpty == true
        ? '$person · ${role!.trim()}'
        : person;
  }

  Widget _line(String label, String? value, {Key? key}) => Padding(
    key: key,
    padding: const EdgeInsets.only(top: 4),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label:  ',
            style: const TextStyle(color: _muted),
          ),
          TextSpan(
            text: value?.trim().isNotEmpty == true ? value!.trim() : '—',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 13, height: 1.3),
    ),
  );

  Widget _trace(
    String label,
    String? name,
    String? role,
    DateTime at,
    Key key,
  ) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Text(
      '$label: ${_person(name, role)} (${_dateTime(at)})',
      key: key,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: _faint, fontSize: 10, height: 1.3),
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '${quote.kindLabel} №${card.number}',
        key: Key('kanban-quote-number-${card.id}'),
        style: const TextStyle(
          color: _muted,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      _line('Исполнитель', quote.executorName),
      _line('Заказчик', quote.clientName),
      _line(
        'Создано',
        '${_dateTime(card.createdAt)} · ${_person(card.createdByName, card.createdByRole)}',
      ),
      const SizedBox(height: 8),
      if (quote.selections.isEmpty)
        Text('Не выбрано', style: const TextStyle(color: _muted, fontSize: 12))
      else
        for (final selection in quote.selections)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    selection.variantName == null
                        ? '${selection.proposalTypeName} (тип целиком)'
                        : '${selection.proposalTypeName}: ${selection.variantName}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _money(selection.total),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
      const SizedBox(height: 6),
      Row(
        children: [
          const Icon(Icons.visibility_outlined, size: 13, color: _faint),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              quote.linkViews == 0
                  ? 'Ссылку ещё не открывали'
                  : 'Просмотров ссылки: ${quote.linkViews}'
                        '${quote.lastViewedAt == null ? '' : ' · ${_dateTime(quote.lastViewedAt!)}'}',
              key: Key('kanban-quote-views-${card.id}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _muted, fontSize: 10),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      const Divider(height: 1),
      const SizedBox(height: 4),
      _trace(
        'Изменил',
        card.updatedByName,
        card.updatedByRole,
        card.updatedAt,
        Key('kanban-quote-updated-${card.id}'),
      ),
      if (card.movedAt case final movedAt?)
        _trace(
          'Статус изменил',
          card.movedByName,
          card.movedByRole,
          movedAt,
          Key('kanban-quote-moved-${card.id}'),
        ),
    ],
  );
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
