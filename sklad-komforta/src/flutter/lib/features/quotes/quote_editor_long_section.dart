part of 'quote_editor_page.dart';

bool _usesLazyStructure(QuoteVariantDraft? variant) =>
    variant != null &&
    variant.categories.fold<int>(
          0,
          (total, category) =>
              total +
              category.sections.fold<int>(
                0,
                (count, section) => count + section.positions.length,
              ),
        ) >=
        50;

List<Widget> _variantStructureSlivers({
  required QuoteController controller,
  required KanbanBoard board,
  required QuoteVariantDraft variant,
  required Set<String> expandedCategories,
  required Set<String> expandedSections,
  required ValueChanged<String> onToggleCategory,
  required ValueChanged<String> onToggleSection,
  required VoidCallback onAddCategory,
  required ValueChanged<QuoteCategoryDraft> onAddSection,
  required void Function(QuoteCategoryDraft, QuoteSectionDraft) onAddPosition,
  required _ColumnWidthStore columnWidthStore,
}) {
  return [
    for (
      var categoryIndex = 0;
      categoryIndex < variant.categories.length;
      categoryIndex++
    ) ...[
      Builder(
        builder: (context) {
          final category = variant.categories[categoryIndex];
          return _lazyStructureHeader(
            token: variant,
            index: categoryIndex,
            onReorder: (oldIndex, newIndex) =>
                controller.reorderCategory(variant, oldIndex, newIndex),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _CategoryBlock(
                reorderControls: _StructureReorderControls(
                  index: categoryIndex,
                  count: variant.categories.length,
                  enabled: !controller.saving,
                  label: 'категорию',
                  onReorder: (oldIndex, newIndex) =>
                      controller.reorderCategory(variant, oldIndex, newIndex),
                ),
                controller: controller,
                board: board,
                category: category,
                expanded: expandedCategories.contains(category.id),
                expandedSections: expandedSections,
                onToggle: () => onToggleCategory(category.id),
                onToggleSection: onToggleSection,
                onAddSection: () => onAddSection(category),
                onAddPosition: (section) => onAddPosition(category, section),
                columnWidthStore: columnWidthStore,
                showContents: false,
              ),
            ),
          );
        },
      ),
      if (expandedCategories.contains(variant.categories[categoryIndex].id))
        for (
          var sectionIndex = 0;
          sectionIndex < variant.categories[categoryIndex].sections.length;
          sectionIndex++
        ) ...[
          Builder(
            builder: (context) {
              final category = variant.categories[categoryIndex];
              final section = category.sections[sectionIndex];
              final fields = _positionFields(board, controller, category)
                  .where(
                    (field) =>
                        field.code != 'group' ||
                        controller.catalogGroups(category, section).isNotEmpty,
                  )
                  .toList(growable: false);
              return _lazyStructureHeader(
                token: category,
                index: sectionIndex,
                onReorder: (oldIndex, newIndex) =>
                    controller.reorderSection(category, oldIndex, newIndex),
                child: _SectionBlock(
                  key: ValueKey(section.id),
                  reorderControls: _StructureReorderControls(
                    index: sectionIndex,
                    count: category.sections.length,
                    enabled: !controller.saving,
                    label: 'раздел',
                    onReorder: (oldIndex, newIndex) =>
                        controller.reorderSection(category, oldIndex, newIndex),
                  ),
                  controller: controller,
                  category: category,
                  section: section,
                  fields: fields,
                  expanded: expandedSections.contains(section.id),
                  onToggle: () => onToggleSection(section.id),
                  onAddPosition: () => onAddPosition(category, section),
                  widthScope: category.catalogCategoryId ?? category.id,
                  columnWidthStore: columnWidthStore,
                  showContents: false,
                ),
              );
            },
          ),
          if (expandedSections.contains(
            variant.categories[categoryIndex].sections[sectionIndex].id,
          ))
            _LazySectionRows(
              key: ValueKey(
                'lazy-rows-${variant.categories[categoryIndex].sections[sectionIndex].id}',
              ),
              controller: controller,
              category: variant.categories[categoryIndex],
              section: variant.categories[categoryIndex].sections[sectionIndex],
              fields:
                  _positionFields(
                        board,
                        controller,
                        variant.categories[categoryIndex],
                      )
                      .where(
                        (field) =>
                            field.code != 'group' ||
                            controller
                                .catalogGroups(
                                  variant.categories[categoryIndex],
                                  variant
                                      .categories[categoryIndex]
                                      .sections[sectionIndex],
                                )
                                .isNotEmpty,
                      )
                      .toList(growable: false),
              widthScope:
                  variant.categories[categoryIndex].catalogCategoryId ??
                  variant.categories[categoryIndex].id,
              columnWidthStore: columnWidthStore,
              onAddPosition: () => onAddPosition(
                variant.categories[categoryIndex],
                variant.categories[categoryIndex].sections[sectionIndex],
              ),
            ),
        ],
      const SliverToBoxAdapter(child: SizedBox(height: 10)),
    ],
    SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: onAddCategory,
            icon: const Icon(Icons.add),
            label: const Text('Добавить категорию'),
          ),
        ),
      ),
    ),
  ];
}

Widget _lazyStructureHeader({
  required Object token,
  required int index,
  required void Function(int, int) onReorder,
  required Widget child,
}) => SliverToBoxAdapter(
  child: DragTarget<_StructureDrag>(
    onWillAcceptWithDetails: (details) =>
        identical(details.data.scope, token) && details.data.index != index,
    onAcceptWithDetails: (details) => onReorder(
      details.data.index,
      details.data.index < index ? index + 1 : index,
    ),
    builder: (context, candidates, rejected) => DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: candidates.isNotEmpty && candidates.first!.index > index
                ? _accent
                : Colors.transparent,
            width: 2,
          ),
          bottom: BorderSide(
            color: candidates.isNotEmpty && candidates.first!.index < index
                ? _accent
                : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: _StructureDragSurface(token: token, child: child),
    ),
  ),
);

({double tableWidth, List<double> fieldWidths, bool overflows}) _lazyWidths(
  double viewportWidth,
  List<KanbanField> fields,
  _ColumnWidthStore store,
  String scope,
) {
  const fixed = 38.0 + 34.0 + 36.0;
  final preferred = [
    for (final field in fields)
      store.widthFor(scope, field.code, _fieldWidth(field)),
  ];
  final preferredWidth = preferred.fold<double>(0, (sum, width) => sum + width);
  final width = math.max(viewportWidth, fixed + preferredWidth);
  final available = width - fixed;
  final scale = preferredWidth > 0 && !store.hasCustomWidths(scope)
      ? available / preferredWidth
      : 1.0;
  return (
    tableWidth: width,
    fieldWidths: [for (final value in preferred) value * scale],
    overflows: width > viewportWidth + 0.5,
  );
}

final class _LazySectionRows extends StatefulWidget {
  const _LazySectionRows({
    super.key,
    required this.controller,
    required this.category,
    required this.section,
    required this.fields,
    required this.widthScope,
    required this.columnWidthStore,
    required this.onAddPosition,
  });

  final QuoteController controller;
  final QuoteCategoryDraft category;
  final QuoteSectionDraft section;
  final List<KanbanField> fields;
  final String widthScope;
  final _ColumnWidthStore columnWidthStore;
  final VoidCallback onAddPosition;

  @override
  State<_LazySectionRows> createState() => _LazySectionRowsState();
}

final class _LazySectionRowsState extends State<_LazySectionRows> {
  final Map<String, FocusNode> _entryNodes = {};
  final ValueNotifier<double> _horizontalOffset = ValueNotifier<double>(0);
  String? _scheduledFocusId;

  List<String> get _entryCodes {
    final present = widget.fields.map((field) => field.code).toSet();
    return [
      for (final code in _entryFieldOrder)
        if (present.contains(code)) code,
    ];
  }

  FocusNode _entryNode(String id, String code) => _entryNodes.putIfAbsent(
    '$id|$code',
    () => FocusNode(debugLabel: 'quote-entry-$id-$code'),
  );

  void _advance(QuotePositionDraft position, String code) {
    final codes = _entryCodes;
    final index = codes.indexOf(code);
    if (index >= 0 && index < codes.length - 1) {
      _entryNode(position.id, codes[index + 1]).requestFocus();
    } else if (position.name.trim().isEmpty &&
        position.marking.trim().isEmpty) {
      if (codes.isNotEmpty) _entryNode(position.id, codes.first).requestFocus();
    } else {
      widget.onAddPosition();
    }
  }

  Future<void> _resolve(QuotePositionDraft position) async {
    final controller = widget.controller;
    final item = await controller.resolveEntryItem(
      category: widget.category,
      section: widget.section,
      position: position,
    );
    if (!mounted) return;
    if (item != null) {
      await controller.applyCatalogItem(
        widget.category,
        widget.section,
        position,
        item,
      );
    } else if (position.catalogItemId != null) {
      controller.detachCatalogItem(position);
    }
  }

  void _pruneNodes() {
    final live = widget.section.positions.map((row) => row.id).toSet();
    final removed = <FocusNode>[];
    _entryNodes.removeWhere((key, node) {
      if (live.contains(key.split('|').first)) return false;
      removed.add(node);
      return true;
    });
    if (removed.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final node in removed) {
          node.dispose();
        }
      });
    }
  }

  @override
  void dispose() {
    for (final node in _entryNodes.values) {
      node.dispose();
    }
    _horizontalOffset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _pruneNodes();
    final controller = widget.controller;
    final section = widget.section;
    final fields = widget.fields;
    final requested = controller.focusRequestPositionId;
    if (requested == null) _scheduledFocusId = null;
    if (requested != null &&
        requested != _scheduledFocusId &&
        section.positions.any((row) => row.id == requested)) {
      _scheduledFocusId = requested;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || controller.focusRequestPositionId != requested) return;
        Scrollable.ensureVisible(context, alignment: 1);
      });
    }
    final visible = section.positions
        .where(controller.isPositionVisible)
        .toList(growable: false);
    final entry = _EntryContext(
      category: widget.category,
      codes: _entryCodes,
      nodeFor: _entryNode,
      onSubmitted: _advance,
      resolve: _resolve,
    );
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: AnimatedBuilder(
            animation: widget.columnWidthStore,
            builder: (context, _) => LayoutBuilder(
              builder: (context, constraints) {
                final sizing = _lazyWidths(
                  constraints.maxWidth,
                  fields,
                  widget.columnWidthStore,
                  widget.widthScope,
                );
                return _SyncedHorizontal(
                  offset: _horizontalOffset,
                  width: sizing.tableWidth,
                  scrollbar: sizing.overflows,
                  child: ValueListenableBuilder<int>(
                    valueListenable: controller.selectionChanges,
                    builder: (context, _, _) => _SectionColumnHeader(
                      fields: fields,
                      fieldWidths: sizing.fieldWidths,
                      selectedCount: section.positions
                          .where((row) => row.selected)
                          .length,
                      positionCount: section.positions.length,
                      onSelectionChanged: (selected) =>
                          controller.setSectionSelection(section, selected),
                      onResizeStart: (index) =>
                          widget.columnWidthStore.beginResize(
                            scope: widget.widthScope,
                            fields: fields,
                            currentWidths: sizing.fieldWidths,
                            fieldIndex: index,
                          ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        if (visible.isEmpty)
          SliverToBoxAdapter(
            child: InkWell(
              onTap: widget.onAddPosition,
              child: const SizedBox(
                height: 56,
                child: Center(
                  child: Text(
                    'В разделе нет позиций. Нажмите, чтобы добавить строку',
                  ),
                ),
              ),
            ),
          )
        else
          SliverReorderableList(
            itemCount: visible.length,
            onReorder: (oldIndex, newIndex) {
              if (!controller.positionFiltersActive) {
                controller.reorderPosition(section, oldIndex, newIndex);
              }
            },
            itemBuilder: (context, index) {
              final position = visible[index];
              if (controller.focusRequestPositionId == position.id &&
                  _entryCodes.isNotEmpty) {
                controller.focusRequestPositionId = null;
                final node = _entryNode(position.id, _entryCodes.first);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) node.requestFocus();
                });
              }
              return ValueListenableBuilder<int>(
                key: ValueKey(position.id),
                valueListenable: controller.changesForPosition(position.id),
                builder: (context, _, _) => AnimatedBuilder(
                  animation: widget.columnWidthStore,
                  builder: (context, _) => LayoutBuilder(
                    builder: (context, constraints) {
                      final sizing = _lazyWidths(
                        constraints.maxWidth,
                        fields,
                        widget.columnWidthStore,
                        widget.widthScope,
                      );
                      return _SyncedHorizontal(
                        offset: _horizontalOffset,
                        width: sizing.tableWidth,
                        child: _PositionRow(
                          controller: controller,
                          entry: entry,
                          section: section,
                          position: position,
                          fields: fields,
                          fieldWidths: sizing.fieldWidths,
                          index: index,
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

final class _SyncedHorizontal extends StatefulWidget {
  const _SyncedHorizontal({
    required this.offset,
    required this.width,
    required this.child,
    this.scrollbar = false,
  });
  final ValueNotifier<double> offset;
  final double width;
  final Widget child;
  final bool scrollbar;

  @override
  State<_SyncedHorizontal> createState() => _SyncedHorizontalState();
}

final class _SyncedHorizontalState extends State<_SyncedHorizontal> {
  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: widget.offset.value,
  );

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_fromScroll);
    widget.offset.addListener(_fromGroup);
  }

  @override
  void didUpdateWidget(covariant _SyncedHorizontal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.offset != widget.offset) {
      oldWidget.offset.removeListener(_fromGroup);
      widget.offset.addListener(_fromGroup);
      WidgetsBinding.instance.addPostFrameCallback((_) => _fromGroup());
    }
  }

  void _fromScroll() {
    if ((_scroll.offset - widget.offset.value).abs() > 0.5) {
      widget.offset.value = _scroll.offset;
    }
  }

  void _fromGroup() {
    if (!_scroll.hasClients) return;
    final target = widget.offset.value.clamp(
      _scroll.position.minScrollExtent,
      _scroll.position.maxScrollExtent,
    );
    if ((_scroll.offset - target).abs() > 0.5) _scroll.jumpTo(target);
  }

  @override
  void dispose() {
    widget.offset.removeListener(_fromGroup);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = SingleChildScrollView(
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      child: SizedBox(width: widget.width, child: widget.child),
    );
    return widget.scrollbar
        ? Scrollbar(
            controller: _scroll,
            scrollbarOrientation: ScrollbarOrientation.bottom,
            child: content,
          )
        : content;
  }
}
