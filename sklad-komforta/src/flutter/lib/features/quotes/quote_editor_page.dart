import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/models/workflow_specialization.dart';
import 'package:sklad_komforta_app/core/widgets/app_select_field.dart';
import 'package:sklad_komforta_app/features/auth/auth_controller.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_models.dart';
import 'package:sklad_komforta_app/features/kanban/kanban_models.dart';
import 'package:sklad_komforta_app/features/quotes/quote_controller.dart';
import 'package:sklad_komforta_app/features/quotes/quote_models.dart';

const _background = Color(0xFF0B1119);
const _surface = Color(0xFF111A27);
const _surfaceRaised = Color(0xFF162131);
const _border = Color(0xFF293A51);
const _muted = Color(0xFF8FA4C2);
const _accent = Color(0xFF4D8DFF);

/// Полноэкранный редактор специализированного содержимого карточки КП/ПКП.
final class QuoteEditorPage extends StatefulWidget {
  const QuoteEditorPage({
    required this.config,
    required this.authController,
    required this.board,
    required this.card,
    required this.onBack,
    this.controller,
    super.key,
  });

  final AppConfig config;
  final AuthController authController;
  final KanbanBoard board;
  final KanbanCard card;
  final VoidCallback onBack;
  final QuoteController? controller;

  @override
  State<QuoteEditorPage> createState() => _QuoteEditorPageState();
}

final class _QuoteEditorPageState extends State<QuoteEditorPage> {
  late final QuoteController controller;
  late final bool ownsController;
  final Set<String> expandedCategories = <String>{};
  final Set<String> expandedSections = <String>{};

  @override
  void initState() {
    super.initState();
    ownsController = widget.controller == null;
    controller =
        widget.controller ??
        QuoteController(widget.config, widget.authController);
    controller.initialize(board: widget.board, card: widget.card);
  }

  @override
  void dispose() {
    if (ownsController) controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      if (controller.loading && controller.draft == null) {
        return const ColoredBox(
          color: _background,
          child: Center(child: CircularProgressIndicator()),
        );
      }
      if (controller.draft == null) {
        return _LoadFailure(
          message: controller.error ?? 'Предложение не загружено.',
          onBack: widget.onBack,
        );
      }
      return ColoredBox(
        color: _background,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 900;
            return Column(
              children: [
                _CommandBar(
                  controller: controller,
                  card: widget.card,
                  board: widget.board,
                  compact: compact,
                  onBack: _requestBack,
                  onSave: () =>
                      controller.save(board: widget.board, card: widget.card),
                ),
                if (controller.error case final message?)
                  _MessageBanner(message: message, error: true),
                if (controller.successMessage case final message?)
                  _MessageBanner(message: message),
                Expanded(
                  child: _body(compact: compact, constraints: constraints),
                ),
              ],
            );
          },
        ),
      );
    },
  );

  Widget _body({required bool compact, required BoxConstraints constraints}) {
    final editor = ListView(
      padding: EdgeInsets.fromLTRB(
        compact ? 12 : 18,
        12,
        compact ? 12 : 10,
        24,
      ),
      children: [
        _MetadataPanel(controller: controller, board: widget.board),
        const SizedBox(height: 12),
        _TypeTabs(controller: controller),
        const SizedBox(height: 10),
        _VariantTabs(controller: controller),
        const SizedBox(height: 10),
        if (controller.activeVariant case final variant?)
          _VariantContent(
            controller: controller,
            variant: variant,
            expandedCategories: expandedCategories,
            expandedSections: expandedSections,
            onToggleCategory: _toggleCategory,
            onToggleSection: _toggleSection,
            onAddCategory: _addCategory,
            onAddSection: _addSection,
            onAddPosition: _addPosition,
          ),
        if (compact) ...[
          if (controller.activeVariant case final variant?) ...[
            const SizedBox(height: 12),
            _SummaryColumn(controller: controller, variant: variant),
          ],
        ],
      ],
    );
    if (compact) return editor;
    final variant = controller.activeVariant;
    return Row(
      children: [
        Expanded(child: editor),
        if (variant != null)
          SizedBox(
            width: constraints.maxWidth < 1180 ? 230 : 270,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 12, 14, 20),
              child: _SummaryColumn(controller: controller, variant: variant),
            ),
          ),
      ],
    );
  }

  void _toggleCategory(String id) {
    setState(() {
      expandedCategories.contains(id)
          ? expandedCategories.remove(id)
          : expandedCategories.add(id);
    });
  }

  void _toggleSection(String id) {
    setState(() {
      expandedSections.contains(id)
          ? expandedSections.remove(id)
          : expandedSections.add(id);
    });
  }

  Future<void> _requestBack() async {
    if (!controller.dirty) {
      widget.onBack();
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Есть несохранённые изменения'),
        content: const Text(
          'Если выйти сейчас, изменения редактора не попадут на сервер.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Остаться'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Выйти без сохранения'),
          ),
        ],
      ),
    );
    if (leave == true) widget.onBack();
  }

  Future<void> _addCategory() async {
    final variant = controller.activeVariant;
    final configuration = controller.catalog;
    if (variant == null || configuration == null) return;
    final available = configuration.categories
        .where(
          (candidate) => !variant.categories.any(
            (existing) => existing.catalogCategoryId == candidate.id,
          ),
        )
        .toList();
    final selected = await _selectDialog<CatalogCategory>(
      title: 'Добавить категорию',
      values: available,
      label: (item) => item.name,
    );
    if (selected != null) {
      controller.addCategory(selected);
      expandedCategories.add(
        variant.categories
            .firstWhere((item) => item.catalogCategoryId == selected.id)
            .id,
      );
    }
  }

  Future<void> _addSection(QuoteCategoryDraft category) async {
    final source = controller.catalog?.categories
        .where((item) => item.id == category.catalogCategoryId)
        .firstOrNull;
    if (source == null) return;
    final available = source.sections
        .where(
          (candidate) => !category.sections.any(
            (existing) => existing.catalogSectionId == candidate.id,
          ),
        )
        .toList();
    final selected = await _selectDialog<CatalogSection>(
      title: 'Добавить раздел',
      values: available,
      label: (item) => item.name,
    );
    if (selected != null) {
      controller.addSection(category, selected);
      expandedSections.add(
        category.sections
            .firstWhere((item) => item.catalogSectionId == selected.id)
            .id,
      );
    }
  }

  Future<T?> _selectDialog<T>({
    required String title,
    required List<T> values,
    required String Function(T item) label,
  }) => showDialog<T>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: values.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(20),
                child: Text('Доступных элементов нет.'),
              )
            : ListView.separated(
                shrinkWrap: true,
                itemCount: values.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) => ListTile(
                  title: Text(label(values[index])),
                  onTap: () => Navigator.pop(context, values[index]),
                ),
              ),
      ),
    ),
  );

  Future<void> _addPosition(
    QuoteCategoryDraft category,
    QuoteSectionDraft section,
  ) async {
    final categoryId = category.catalogCategoryId;
    if (categoryId == null) return;
    await controller.searchCatalog(
      categoryId: categoryId,
      sectionId: section.catalogSectionId,
    );
    if (!mounted) return;
    final item = await showDialog<CatalogItem>(
      context: context,
      builder: (dialogContext) => _CatalogPickerDialog(
        controller: controller,
        categoryId: categoryId,
        sectionId: section.catalogSectionId,
      ),
    );
    if (item != null) controller.addCatalogPosition(section, item);
  }
}

final class _CommandBar extends StatelessWidget {
  const _CommandBar({
    required this.controller,
    required this.card,
    required this.board,
    required this.compact,
    required this.onBack,
    required this.onSave,
  });

  final QuoteController controller;
  final KanbanCard card;
  final KanbanBoard board;
  final bool compact;
  final VoidCallback onBack;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final draft = controller.draft!;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFF0F1722),
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.description_outlined, color: _accent),
            const SizedBox(width: 9),
            Text(
              '${draft.kind.label} №${card.number}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            if (!compact) ...[
              const SizedBox(width: 18),
              const Text(
                'Коммерческие предложения',
                style: TextStyle(color: _muted),
              ),
            ],
            const Spacer(),
            if (board.specialization == WorkflowSpecialization.quoteAndPrequote)
              SizedBox(
                width: 130,
                child: AppSelectField<QuoteKind>(
                  value: draft.kind,
                  label: 'Документ',
                  isDense: true,
                  options: QuoteKind.values
                      .map(
                        (value) =>
                            AppSelectOption(value: value, label: value.label),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      controller.updateDocument((draft) => draft.kind = value);
                    }
                  },
                ),
              ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: controller.saving ? null : onSave,
              icon: controller.saving
                  ? const SizedBox.square(
                      dimension: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined, size: 18),
              label: Text(compact ? '' : 'Сохранить'),
            ),
            if (!compact) ...[
              const SizedBox(width: 7),
              const _DisabledAction(
                icon: Icons.visibility_outlined,
                label: 'Предпросмотр',
              ),
              const _DisabledAction(
                icon: Icons.print_outlined,
                label: 'Печать',
              ),
              const _DisabledAction(icon: Icons.link, label: 'Ссылка'),
            ],
            const SizedBox(width: 7),
            OutlinedButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: Text(compact ? '' : 'Назад'),
            ),
          ],
        ),
      ),
    );
  }
}

final class _DisabledAction extends StatelessWidget {
  const _DisabledAction({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 7),
    child: OutlinedButton.icon(
      onPressed: null,
      icon: Icon(icon, size: 17),
      label: Text(label),
    ),
  );
}

final class _MetadataPanel extends StatelessWidget {
  const _MetadataPanel({required this.controller, required this.board});
  final QuoteController controller;
  final KanbanBoard board;

  @override
  Widget build(BuildContext context) {
    final draft = controller.draft!;
    return _Panel(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 780;
          final fields = <Widget>[
            _TextField(
              initialValue: draft.title,
              label: 'Название КП',
              onChanged: (value) =>
                  controller.updateDocument((draft) => draft.title = value),
            ),
            AppSelectField<String>(
              value: draft.clientId.isEmpty ? null : draft.clientId,
              label: 'Заказчик',
              options: controller.clients
                  .map(
                    (item) => AppSelectOption(value: item.id, label: item.name),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  controller.updateDocument((draft) => draft.clientId = value);
                }
              },
            ),
            AppSelectField<String>(
              value: draft.executorCompanyId.isEmpty
                  ? null
                  : draft.executorCompanyId,
              label: 'Исполнитель',
              options: controller.executors
                  .map(
                    (item) => AppSelectOption(value: item.id, label: item.name),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  controller.updateDocument(
                    (draft) => draft.executorCompanyId = value,
                  );
                }
              },
            ),
            AppSelectField<String>(
              value: draft.managerUserId,
              label: 'Менеджер',
              options: [
                const AppSelectOption<String>(value: null, label: 'Не указан'),
                ...controller.employees
                    .where((item) => item.isActive)
                    .map(
                      (item) => AppSelectOption(
                        value: item.userId,
                        label: item.displayName,
                      ),
                    ),
              ],
              onChanged: (value) => controller.updateDocument(
                (draft) => draft.managerUserId = value,
              ),
            ),
            AppSelectField<String>(
              value: draft.salesHeadUserId,
              label: 'РОП',
              options: [
                const AppSelectOption<String>(value: null, label: 'Не указан'),
                ...controller.employees
                    .where((item) => item.isActive)
                    .map(
                      (item) => AppSelectOption(
                        value: item.userId,
                        label: item.displayName,
                      ),
                    ),
              ],
              onChanged: (value) => controller.updateDocument(
                (draft) => draft.salesHeadUserId = value,
              ),
            ),
          ];
          final selectionMode = AppSelectField<String>(
            value: draft.selectionMode,
            label: 'Выбор клиента',
            options: const [
              AppSelectOption(value: 'variant', label: 'Один вариант'),
              AppSelectOption(
                value: 'proposal_type',
                label: 'Тип со всеми вариантами',
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                controller.updateDocument(
                  (draft) => draft.selectionMode = value,
                );
              }
            },
          );
          return Column(
            children: [
              if (narrow) ...[
                for (final field in fields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: field,
                  ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: selectionMode,
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(flex: 2, child: fields[0]),
                    const SizedBox(width: 10),
                    Expanded(child: fields[3]),
                    const SizedBox(width: 10),
                    Expanded(child: fields[4]),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: fields[1]),
                    const SizedBox(width: 10),
                    Expanded(child: fields[2]),
                    const SizedBox(width: 10),
                    Expanded(child: selectionMode),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              _TextField(
                initialValue: draft.additionalInformation,
                label: 'Дополнительная информация',
                maxLines: 2,
                onChanged: (value) => controller.updateDocument(
                  (draft) => draft.additionalInformation = value,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

final class _TypeTabs extends StatelessWidget {
  const _TypeTabs({required this.controller});
  final QuoteController controller;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 42,
    child: ListView(
      scrollDirection: Axis.horizontal,
      children: [
        for (final type in controller.draft!.proposalTypes)
          Padding(
            padding: const EdgeInsets.only(right: 7),
            child: _TabButton(
              label: type.name,
              selected: type.id == controller.activeType?.id,
              icon: Icons.folder_copy_outlined,
              onPressed: () => controller.selectType(type.id),
              onRename: () => _rename(context, type.name, (value) {
                type.name = value;
                controller.positionChanged();
              }),
            ),
          ),
        OutlinedButton.icon(
          onPressed: controller.addType,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Добавить тип'),
        ),
      ],
    ),
  );
}

final class _VariantTabs extends StatelessWidget {
  const _VariantTabs({required this.controller});
  final QuoteController controller;

  @override
  Widget build(BuildContext context) {
    final type = controller.activeType;
    if (type == null) return const SizedBox.shrink();
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final variant in type.variants)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _TabButton(
                      label: variant.name,
                      selected: variant.id == controller.activeVariant?.id,
                      onPressed: () => controller.selectVariant(variant.id),
                      onRename: () => _rename(context, variant.name, (value) {
                        variant.name = value;
                        controller.positionChanged();
                      }),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: controller.addVariant,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Добавить вариант'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 145,
          child: AppSelectField<double>(
            value: controller.activeVariant?.vatRate,
            label: 'НДС',
            isDense: true,
            options: const [
              AppSelectOption<double>(value: null, label: 'Без НДС'),
              AppSelectOption(value: 5, label: '5%'),
              AppSelectOption(value: 10, label: '10%'),
              AppSelectOption(value: 20, label: '20%'),
            ],
            onChanged: (value) {
              final variant = controller.activeVariant;
              if (variant != null) {
                variant.vatRate = value;
                controller.positionChanged();
              }
            },
          ),
        ),
      ],
    );
  }
}

final class _VariantContent extends StatelessWidget {
  const _VariantContent({
    required this.controller,
    required this.variant,
    required this.expandedCategories,
    required this.expandedSections,
    required this.onToggleCategory,
    required this.onToggleSection,
    required this.onAddCategory,
    required this.onAddSection,
    required this.onAddPosition,
  });

  final QuoteController controller;
  final QuoteVariantDraft variant;
  final Set<String> expandedCategories;
  final Set<String> expandedSections;
  final ValueChanged<String> onToggleCategory;
  final ValueChanged<String> onToggleSection;
  final VoidCallback onAddCategory;
  final ValueChanged<QuoteCategoryDraft> onAddSection;
  final void Function(QuoteCategoryDraft, QuoteSectionDraft) onAddPosition;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (variant.categories.isEmpty)
        _EmptyVariant(onAddCategory: onAddCategory)
      else
        for (final category in variant.categories)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _CategoryBlock(
              controller: controller,
              category: category,
              expanded: expandedCategories.contains(category.id),
              expandedSections: expandedSections,
              onToggle: () => onToggleCategory(category.id),
              onToggleSection: onToggleSection,
              onAddSection: () => onAddSection(category),
              onAddPosition: (section) => onAddPosition(category, section),
            ),
          ),
      Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton.icon(
          onPressed: onAddCategory,
          icon: const Icon(Icons.add),
          label: const Text('Добавить категорию'),
        ),
      ),
    ],
  );
}

final class _CategoryBlock extends StatelessWidget {
  const _CategoryBlock({
    required this.controller,
    required this.category,
    required this.expanded,
    required this.expandedSections,
    required this.onToggle,
    required this.onToggleSection,
    required this.onAddSection,
    required this.onAddPosition,
  });

  final QuoteController controller;
  final QuoteCategoryDraft category;
  final bool expanded;
  final Set<String> expandedSections;
  final VoidCallback onToggle;
  final ValueChanged<String> onToggleSection;
  final VoidCallback onAddSection;
  final ValueChanged<QuoteSectionDraft> onAddPosition;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _border),
    ),
    child: Column(
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(expanded ? Icons.expand_more : Icons.chevron_right),
                const Icon(Icons.folder_outlined, size: 18, color: _accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    category.name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                _MoneyLabel('Закупка', category.purchaseTotal),
                const SizedBox(width: 16),
                _MoneyLabel('Розница', category.clientTotal),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Добавить раздел',
                  onPressed: onAddSection,
                  icon: const Icon(Icons.create_new_folder_outlined),
                ),
              ],
            ),
          ),
        ),
        if (expanded) ...[
          const Divider(height: 1),
          if (category.sections.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton.icon(
                onPressed: onAddSection,
                icon: const Icon(Icons.add),
                label: const Text('Добавить раздел'),
              ),
            )
          else
            for (final section in category.sections)
              _SectionBlock(
                controller: controller,
                section: section,
                expanded: expandedSections.contains(section.id),
                onToggle: () => onToggleSection(section.id),
                onAddPosition: () => onAddPosition(section),
              ),
        ],
      ],
    ),
  );
}

final class _SectionBlock extends StatelessWidget {
  const _SectionBlock({
    required this.controller,
    required this.section,
    required this.expanded,
    required this.onToggle,
    required this.onAddPosition,
  });

  final QuoteController controller;
  final QuoteSectionDraft section;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onAddPosition;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      DecoratedBox(
        decoration: const BoxDecoration(color: Color(0xFF132334)),
        child: _SectionHeader(
          controller: controller,
          section: section,
          expanded: expanded,
          onToggle: onToggle,
          onAddPosition: onAddPosition,
        ),
      ),
      if (expanded)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: 1190,
            child: Column(
              children: [
                const _SectionColumnHeader(),
                if (section.positions.isEmpty)
                  InkWell(
                    onTap: onAddPosition,
                    child: const SizedBox(
                      height: 56,
                      child: Center(
                        child: Text(
                          'В разделе нет позиций. Добавить из каталога',
                          style: TextStyle(color: _muted),
                        ),
                      ),
                    ),
                  )
                else
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    itemCount: section.positions.length,
                    onReorder: (oldIndex, newIndex) =>
                        controller.reorderPosition(section, oldIndex, newIndex),
                    itemBuilder: (context, index) => _PositionRow(
                      key: ValueKey(section.positions[index].id),
                      controller: controller,
                      section: section,
                      position: section.positions[index],
                      index: index,
                    ),
                  ),
              ],
            ),
          ),
        ),
      const Divider(height: 1),
    ],
  );
}

/// Адаптивная шапка раздела. Заголовки колонок намеренно находятся ниже,
/// внутри раскрытого раздела, а не над всей категорией.
final class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.controller,
    required this.section,
    required this.expanded,
    required this.onToggle,
    required this.onAddPosition,
  });

  final QuoteController controller;
  final QuoteSectionDraft section;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onAddPosition;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final title = Row(
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onToggle,
            icon: Icon(expanded ? Icons.expand_more : Icons.chevron_right),
          ),
          const Icon(Icons.folder_open_outlined, size: 17),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              section.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (constraints.maxWidth < 760)
            IconButton(
              tooltip: 'Добавить позицию',
              onPressed: onAddPosition,
              icon: const Icon(Icons.add_circle_outline),
            ),
        ],
      );
      final actions = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PercentAction(
            label: 'Наценка',
            initialValue: section.markupPercent,
            onApply: (value) =>
                controller.applyPercent(section, value: value, markup: true),
          ),
          const SizedBox(width: 8),
          _PercentAction(
            label: 'Скидка',
            initialValue: section.discountPercent,
            onApply: (value) =>
                controller.applyPercent(section, value: value, markup: false),
          ),
          const SizedBox(width: 10),
          _MoneyLabel('Итого', section.clientTotal),
          if (constraints.maxWidth >= 760)
            IconButton(
              tooltip: 'Добавить позицию',
              onPressed: onAddPosition,
              icon: const Icon(Icons.add_circle_outline),
            ),
        ],
      );
      if (constraints.maxWidth >= 760) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          child: Row(
            children: [
              Expanded(child: title),
              actions,
            ],
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            title,
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: actions,
            ),
          ],
        ),
      );
    },
  );
}

final class _SectionColumnHeader extends StatelessWidget {
  const _SectionColumnHeader();

  @override
  Widget build(BuildContext context) => Container(
    height: 38,
    decoration: const BoxDecoration(
      color: Color(0xFF1A2B3E),
      border: Border(
        top: BorderSide(color: Color(0xFF3B5D80)),
        bottom: BorderSide(color: Color(0xFF3B5D80)),
      ),
    ),
    child: const Row(
      children: [
        SizedBox(width: 38),
        SizedBox(width: 34),
        _HeaderCell('ГРУППА', 105),
        _HeaderCell('НАИМЕНОВАНИЕ', 150),
        _HeaderCell('МАРКИРОВКА / РАЗМЕР', 145),
        _HeaderCell('КОЛ-ВО', 72),
        _HeaderCell('ЕД.', 64),
        _HeaderCell('ПОСТАВЩИК', 115),
        _HeaderCell('ЗАКУПКА', 90),
        _HeaderCell('НАЦЕНКА', 78),
        _HeaderCell('ЦЕНА', 90),
        _HeaderCell('СКИДКА', 78),
        _HeaderCell('СУММА', 95),
        SizedBox(width: 36),
      ],
    ),
  );
}

final class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.label, this.width);
  final String label;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFFA9BEDA),
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: .25,
        ),
      ),
    ),
  );
}

final class _PositionRow extends StatelessWidget {
  const _PositionRow({
    required this.controller,
    required this.section,
    required this.position,
    required this.index,
    super.key,
  });

  final QuoteController controller;
  final QuoteSectionDraft section;
  final QuotePositionDraft position;
  final int index;

  @override
  Widget build(BuildContext context) {
    final changedExternally = position.values['changed_externally'] == true;
    final isNew = position.catalogItemId == null;
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: isNew
            ? const Color(0x1AF5B942)
            : changedExternally
            ? const Color(0x18EF5350)
            : index.isEven
            ? const Color(0xFF101A27)
            : const Color(0xFF0E1722),
        border: Border(
          bottom: const BorderSide(color: Color(0xFF233248)),
          left: changedExternally
              ? const BorderSide(color: Color(0xFFEF5350), width: 2)
              : BorderSide.none,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 38,
            child: Checkbox(
              value: position.selected,
              onChanged: (value) {
                position.selected = value ?? false;
                controller.positionChanged();
              },
            ),
          ),
          SizedBox(
            width: 34,
            child: ReorderableDragStartListener(
              index: index,
              child: const MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: Icon(Icons.drag_indicator, size: 18, color: _muted),
              ),
            ),
          ),
          _RowText(position.values['group']?.toString() ?? '', 105),
          _RowInput(
            initialValue: position.name,
            width: 150,
            onChanged: (value) {
              position.name = value;
              controller.positionChanged();
            },
          ),
          _RowInput(
            initialValue: position.marking,
            width: 145,
            onChanged: (value) {
              position.marking = value;
              controller.positionChanged();
            },
          ),
          _RowNumber(
            value: position.quantity,
            width: 72,
            onChanged: (value) {
              if (value > 0) position.quantity = value;
              controller.positionChanged();
            },
          ),
          _RowInput(
            initialValue: position.unit,
            width: 64,
            onChanged: (value) {
              position.unit = value;
              controller.positionChanged();
            },
          ),
          _RowText(position.values['supplier']?.toString() ?? '', 115),
          _RowNumber(
            value: position.purchasePrice ?? 0,
            width: 90,
            onChanged: (value) {
              position.purchasePrice = value;
              controller.positionChanged();
            },
          ),
          _RowNumber(
            value: position.markupPercent ?? 0,
            width: 78,
            onChanged: (value) {
              position.markupPercent = value;
              controller.positionChanged();
            },
          ),
          _RowNumber(
            value: position.manualPrice ?? position.basePrice,
            width: 90,
            onChanged: (value) {
              position.manualPrice = value;
              controller.positionChanged();
            },
          ),
          _RowNumber(
            value: position.discountPercent ?? 0,
            width: 78,
            onChanged: (value) {
              position.discountPercent = value;
              controller.positionChanged();
            },
          ),
          _RowText(_money(position.lineTotal), 95, alignEnd: true),
          SizedBox(
            width: 36,
            child: IconButton(
              tooltip: 'Удалить позицию',
              onPressed: () => controller.removePosition(section, position),
              icon: const Icon(
                Icons.delete_outline,
                size: 17,
                color: Color(0xFFFF6B6B),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _SummaryColumn extends StatelessWidget {
  const _SummaryColumn({required this.controller, required this.variant});
  final QuoteController controller;
  final QuoteVariantDraft variant;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _SummaryCard(
        title: 'Сводка варианта',
        rows: [
          ('Итого для клиента', variant.clientTotal),
          ('Итого закупка', variant.purchaseTotal),
          ('Валовая прибыль', variant.margin),
          ('НДС', variant.vatAmount),
        ],
        footer: (
          'Маржинальность',
          '${variant.marginPercent.toStringAsFixed(1)}%',
        ),
      ),
      const SizedBox(height: 10),
      _SummaryCard(
        title: 'Сводка типа',
        rows: [
          for (final item
              in controller.activeType?.variants ?? const <QuoteVariantDraft>[])
            (item.name, item.clientTotal),
        ],
      ),
    ],
  );
}

final class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.title, required this.rows, this.footer});
  final String title;
  final List<(String, double)> rows;
  final (String, String)? footer;

  @override
  Widget build(BuildContext context) => _Panel(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    row.$1,
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ),
                Text(
                  _money(row.$2),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        if (footer case final value?) ...[
          const Divider(),
          Row(
            children: [
              Expanded(
                child: Text(value.$1, style: const TextStyle(color: _muted)),
              ),
              Text(
                value.$2,
                style: const TextStyle(
                  color: Color(0xFF55D889),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

final class _PercentAction extends StatefulWidget {
  const _PercentAction({
    required this.label,
    required this.initialValue,
    required this.onApply,
  });
  final String label;
  final double? initialValue;
  final ValueChanged<double> onApply;

  @override
  State<_PercentAction> createState() => _PercentActionState();
}

final class _PercentActionState extends State<_PercentAction> {
  late final TextEditingController input;

  @override
  void initState() {
    super.initState();
    input = TextEditingController();
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(widget.label, style: const TextStyle(fontSize: 11, color: _muted)),
      const SizedBox(width: 5),
      SizedBox(
        width: 62,
        child: TextField(
          controller: input,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          style: const TextStyle(fontSize: 12),
          decoration: const InputDecoration(
            isDense: true,
            suffixText: '%',
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          ),
        ),
      ),
      const SizedBox(width: 4),
      SizedBox(
        height: 32,
        child: OutlinedButton(
          onPressed: () {
            final value = double.tryParse(input.text.replaceAll(',', '.'));
            if (value == null) return;
            widget.onApply(value);
            input.clear();
          },
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          child: const Text('Применить', style: TextStyle(fontSize: 10)),
        ),
      ),
    ],
  );
}

final class _CatalogPickerDialog extends StatefulWidget {
  const _CatalogPickerDialog({
    required this.controller,
    required this.categoryId,
    required this.sectionId,
  });
  final QuoteController controller;
  final String categoryId;
  final String? sectionId;

  @override
  State<_CatalogPickerDialog> createState() => _CatalogPickerDialogState();
}

final class _CatalogPickerDialogState extends State<_CatalogPickerDialog> {
  final search = TextEditingController();

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Добавить позицию из каталога'),
    content: SizedBox(
      width: 640,
      height: 520,
      child: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) => Column(
          children: [
            TextField(
              controller: search,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Поиск по наименованию и маркировке',
                suffixIcon: IconButton(
                  onPressed: _search,
                  icon: const Icon(Icons.search),
                ),
              ),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: widget.controller.catalogSearching
                  ? const Center(child: CircularProgressIndicator())
                  : widget.controller.catalogSearchResults.isEmpty
                  ? const Center(child: Text('Подходящие позиции не найдены.'))
                  : ListView.separated(
                      itemCount: widget.controller.catalogSearchResults.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item =
                            widget.controller.catalogSearchResults[index];
                        return ListTile(
                          leading: const Icon(Icons.inventory_2_outlined),
                          title: Text(item.name),
                          subtitle: Text(item.marking),
                          trailing: Text(_money(_catalogPrice(item))),
                          onTap: () => Navigator.pop(context, item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Закрыть'),
      ),
    ],
  );

  void _search() => widget.controller.searchCatalog(
    categoryId: widget.categoryId,
    sectionId: widget.sectionId,
    search: search.text,
  );
}

final class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(12)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _border),
    ),
    child: Padding(padding: padding, child: child),
  );
}

final class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onPressed,
    required this.onRename,
    this.icon,
  });
  final String label;
  final bool selected;
  final VoidCallback onPressed;
  final VoidCallback onRename;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? const Color(0xFF1D4E89) : _surfaceRaised,
    borderRadius: BorderRadius.circular(8),
    child: InkWell(
      onTap: onPressed,
      onLongPress: onRename,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 17, color: selected ? Colors.white : _muted),
              const SizedBox(width: 7),
            ],
            Text(
              label,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            const SizedBox(width: 5),
            InkWell(
              onTap: onRename,
              child: const Icon(Icons.edit_outlined, size: 14, color: _muted),
            ),
          ],
        ),
      ),
    ),
  );
}

final class _TextField extends StatelessWidget {
  const _TextField({
    required this.initialValue,
    required this.label,
    required this.onChanged,
    this.maxLines = 1,
  });
  final String initialValue;
  final String label;
  final ValueChanged<String> onChanged;
  final int maxLines;

  @override
  Widget build(BuildContext context) => TextFormField(
    initialValue: initialValue,
    maxLines: maxLines,
    decoration: InputDecoration(labelText: label),
    onChanged: onChanged,
  );
}

final class _RowText extends StatelessWidget {
  const _RowText(this.text, this.width, {this.alignEnd = false});
  final String text;
  final double width;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: alignEnd ? TextAlign.end : TextAlign.start,
        style: const TextStyle(fontSize: 11),
      ),
    ),
  );
}

final class _RowInput extends StatelessWidget {
  const _RowInput({
    required this.initialValue,
    required this.width,
    required this.onChanged,
  });
  final String initialValue;
  final double width;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: TextFormField(
        initialValue: initialValue,
        style: const TextStyle(fontSize: 11),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 7, vertical: 9),
        ),
        onChanged: onChanged,
      ),
    ),
  );
}

final class _RowNumber extends StatelessWidget {
  const _RowNumber({
    required this.value,
    required this.width,
    required this.onChanged,
  });
  final double value;
  final double width;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => _RowInput(
    initialValue: value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString(),
    width: width,
    onChanged: (text) {
      final parsed = double.tryParse(text.replaceAll(',', '.'));
      if (parsed != null) onChanged(parsed);
    },
  );
}

final class _MoneyLabel extends StatelessWidget {
  const _MoneyLabel(this.label, this.value);
  final String label;
  final double value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Text(label, style: const TextStyle(color: _muted, fontSize: 9)),
      Text(
        _money(value),
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      ),
    ],
  );
}

final class _EmptyVariant extends StatelessWidget {
  const _EmptyVariant({required this.onAddCategory});
  final VoidCallback onAddCategory;

  @override
  Widget build(BuildContext context) => _Panel(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: [
          const Icon(Icons.inventory_2_outlined, size: 42, color: _muted),
          const SizedBox(height: 12),
          const Text(
            'Вариант пока пуст',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'Добавьте первую категорию из настроек организации.',
            style: TextStyle(color: _muted),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAddCategory,
            icon: const Icon(Icons.add),
            label: const Text('Добавить категорию'),
          ),
        ],
      ),
    ),
  );
}

final class _MessageBanner extends StatelessWidget {
  const _MessageBanner({required this.message, this.error = false});
  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: error ? const Color(0xFF4A1D29) : const Color(0xFF123B2A),
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
    child: Row(
      children: [
        Icon(
          error ? Icons.error_outline : Icons.check_circle_outline,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(message)),
      ],
    ),
  );
}

final class _LoadFailure extends StatelessWidget {
  const _LoadFailure({required this.message, required this.onBack});
  final String message;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: _background,
    child: Center(
      child: _Panel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 42, color: Color(0xFFFF6B81)),
            const SizedBox(height: 12),
            Text(message),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onBack,
              child: const Text('Вернуться в канбан'),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _rename(
  BuildContext context,
  String initialValue,
  ValueChanged<String> onSave,
) async {
  final input = TextEditingController(text: initialValue);
  final value = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Изменить название'),
      content: TextField(controller: input, autofocus: true),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, input.text.trim()),
          child: const Text('Сохранить'),
        ),
      ],
    ),
  );
  input.dispose();
  if (value != null && value.isNotEmpty) onSave(value);
}

double _catalogPrice(CatalogItem item) {
  final value = item.values['base_price'];
  if (value is num) return value.toDouble();
  return double.tryParse('$value'.replaceAll(',', '.')) ?? 0;
}

final _moneyFormat = NumberFormat.currency(
  locale: 'ru_RU',
  symbol: '₽',
  decimalDigits: 2,
);

String _money(double value) => _moneyFormat.format(value);
