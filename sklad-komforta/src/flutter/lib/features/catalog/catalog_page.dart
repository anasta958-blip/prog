import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:sklad_komforta_app/core/widgets/app_notice.dart';
import 'package:sklad_komforta_app/core/widgets/app_select_field.dart';
import 'package:intl/intl.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_controller.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_bulk_relations_editor.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_editor.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_models.dart';

/// Карточное представление каталога, выбранное пользователем как вариант 2.
final class CatalogPage extends StatefulWidget {
  const CatalogPage({required this.controller, super.key});
  final CatalogController controller;

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  late final TextEditingController _searchController;
  CatalogItemDraft? draft;
  String? editingItemId;
  bool mobileControlsExpanded = false;
  bool mobileFiltersExpanded = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.controller.search);
  }

  @override
  void didUpdateWidget(covariant CatalogPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _searchController.text = widget.controller.search;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final persistentEditor = constraints.maxWidth >= 1180;
        return Row(
          children: [
            Expanded(child: _catalogBody(persistentEditor)),
            if (persistentEditor && widget.controller.bulkItems.length > 1)
              SizedBox(width: 400, child: _bulkEditor(_closeBulkEditor))
            else if (persistentEditor && draft != null)
              SizedBox(
                width: 400,
                child: CatalogEditor(
                  key: ValueKey(editingItemId ?? 'new'),
                  draft: draft!,
                  configuration: widget.controller.configuration!,
                  saving: widget.controller.saving,
                  error: widget.controller.error,
                  isNew: editingItemId == null,
                  images: widget.controller.images,
                  imagesLoading: widget.controller.imagesLoading,
                  imagesError: widget.controller.imagesError,
                  relations: widget.controller.relations,
                  relationsLoading: widget.controller.relationsLoading,
                  relationsError: widget.controller.relationsError,
                  onClose: _closeEditor,
                  onSave: _save,
                  onDelete: editingItemId == null ? null : _delete,
                  onUploadImage: editingItemId == null
                      ? null
                      : (name, contentType, bytes) =>
                            widget.controller.uploadImage(
                              itemId: editingItemId!,
                              fileName: name,
                              contentType: contentType,
                              bytes: bytes,
                            ),
                  onDeleteImage: editingItemId == null
                      ? null
                      : (imageId) => widget.controller.deleteImage(
                          editingItemId!,
                          imageId,
                        ),
                  onSearchRelations: widget.controller.searchRelationCandidates,
                  onAddRelation: editingItemId == null
                      ? null
                      : (dependency, candidate) => widget.controller
                            .addRelation(editingItemId!, dependency, candidate),
                  onRemoveRelation: editingItemId == null
                      ? null
                      : (dependencyId, sourceItemId) =>
                            widget.controller.removeRelation(
                              editingItemId!,
                              dependencyId,
                              sourceItemId,
                            ),
                ),
              ),
          ],
        );
      },
    ),
  );

  Widget _catalogBody(bool persistentEditor) {
    final controller = widget.controller;
    final mobile = MediaQuery.sizeOf(context).width < 600;
    if (controller.configuration == null && controller.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.configuration == null) {
      return _CatalogMessage(
        icon: Icons.cloud_off_outlined,
        title: 'Каталог не загрузился',
        message: controller.error ?? 'Повторите загрузку.',
        actionLabel: 'Повторить',
        onAction: controller.initialize,
      );
    }
    final categories = controller.configuration!.categories;
    if (categories.isEmpty) {
      return _CatalogMessage(
        icon: Icons.account_tree_outlined,
        title: 'Категории не настроены',
        message:
            'Добавьте категории в настройках организации, затем обновите каталог.',
        actionLabel: 'Обновить',
        onAction: controller.reloadConfiguration,
      );
    }
    return Padding(
      padding: mobile
          ? const EdgeInsets.fromLTRB(12, 10, 12, 10)
          : const EdgeInsets.fromLTRB(24, 22, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (mobile) ...[
            _MobileControlsToggle(
              expanded: mobileControlsExpanded,
              total: controller.total,
              selectedCount: controller.selectedIds.length,
              onTap: () => setState(
                () => mobileControlsExpanded = !mobileControlsExpanded,
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (!mobile || mobileControlsExpanded) ...[
            _Header(
              compact: mobile,
              loading: controller.loading,
              transferBusy: controller.transferBusy,
              onRefresh: controller.reloadConfiguration,
              onTemplate: _downloadTemplate,
              onImport: _importCatalog,
              onExport: _exportCatalog,
              onCreate: () =>
                  _openEditor(controller.createDraft(), null, persistentEditor),
            ),
            SizedBox(height: mobile ? 10 : 18),
            TextField(
              key: const Key('catalog-search'),
              controller: _searchController,
              onChanged: controller.updateSearch,
              decoration: const InputDecoration(
                hintText: 'Поиск по наименованию или маркировке…',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            SizedBox(height: mobile ? 10 : 14),
            SizedBox(
              height: mobile ? 36 : 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _CategoryChip(
                    label: 'Все категории',
                    selected: controller.categoryId == null,
                    onTap: () => controller.selectCategory(null),
                  ),
                  for (final category in categories)
                    _CategoryChip(
                      label: category.name,
                      selected: controller.categoryId == category.id,
                      onTap: () => controller.selectCategory(category.id),
                    ),
                ],
              ),
            ),
            SizedBox(height: mobile ? 8 : 12),
            if (mobile) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => setState(
                    () => mobileFiltersExpanded = !mobileFiltersExpanded,
                  ),
                  icon: Icon(
                    mobileFiltersExpanded
                        ? Icons.filter_alt_off_outlined
                        : Icons.filter_alt_outlined,
                    size: 18,
                  ),
                  label: Text(
                    mobileFiltersExpanded ? 'Скрыть фильтры' : 'Фильтры',
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: mobileFiltersExpanded
                    ? Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: _Filters(controller: controller, compact: true),
                      )
                    : const SizedBox.shrink(),
              ),
            ] else
              _Filters(controller: controller),
            SizedBox(height: mobile ? 8 : 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Найдено товаров: ${controller.total}',
                    style: const TextStyle(color: Color(0xFF8FA4C2)),
                  ),
                ),
                if (controller.loading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ],
          if (controller.hasSelection) ...[
            const SizedBox(height: 12),
            _BulkToolbar(
              controller: controller,
              onDelete: _bulkDelete,
              onEditRelations: () => _openBulkEditor(persistentEditor),
            ),
          ],
          if (controller.error != null) ...[
            const SizedBox(height: 10),
            _InlineError(controller.error!),
          ],
          if (controller.transferMessage != null) ...[
            const SizedBox(height: 10),
            _InlineSuccess(controller.transferMessage!),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: controller.items.isEmpty
                ? _CatalogMessage(
                    icon: Icons.inventory_2_outlined,
                    title: 'Товары не найдены',
                    message: 'Измените фильтры или создайте первую карточку.',
                    actionLabel: 'Добавить товар',
                    onAction: () => _openEditor(
                      controller.createDraft(),
                      null,
                      persistentEditor,
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = switch (constraints.maxWidth) {
                        >= 1500 => 6,
                        >= 1250 => 5,
                        >= 970 => 4,
                        >= 700 => 3,
                        >= 600 => 2,
                        _ => 1,
                      };
                      return GridView.builder(
                        key: const PageStorageKey('catalog-grid'),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: columns == 1 ? 0.96 : 0.82,
                        ),
                        itemCount: controller.items.length,
                        itemBuilder: (context, index) {
                          final item = controller.items[index];
                          return _ProductCard(
                            item: item,
                            category: _category(item.categoryId),
                            selected: editingItemId == item.id,
                            selectedForBulk: controller.selectedIds.contains(
                              item.id,
                            ),
                            onToggleSelection: () =>
                                controller.toggleSelection(item.id),
                            onTap: () => controller.selectedIds.length > 1
                                ? _openBulkEditor(persistentEditor)
                                : _openEditor(
                                    CatalogItemDraft.fromItem(item),
                                    item.id,
                                    persistentEditor,
                                  ),
                          );
                        },
                      );
                    },
                  ),
          ),
          if (controller.total > 0) ...[
            const SizedBox(height: 12),
            _Pagination(controller: controller),
          ],
        ],
      ),
    );
  }

  CatalogCategory? _category(String id) {
    for (final category in widget.controller.configuration!.categories) {
      if (category.id == id) return category;
    }
    return null;
  }

  Widget _bulkEditor(VoidCallback onClose) {
    final items = widget.controller.bulkItems;
    final ids = items.map((item) => item.id).toList()..sort();
    return CatalogBulkRelationsEditor(
      key: ValueKey(ids.join('/')),
      controller: widget.controller,
      items: items,
      onClose: onClose,
    );
  }

  void _closeBulkEditor() {
    widget.controller.clearSelection();
    if (editingItemId != null) {
      unawaited(widget.controller.loadRelations(editingItemId!));
    }
  }

  Future<void> _openBulkEditor(bool persistent) async {
    if (widget.controller.bulkItems.length < 2 || persistent) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: const Color(0xFF111A27),
        child: _bulkEditor(() => Navigator.pop(context)),
      ),
    );
    if (mounted && editingItemId != null) {
      unawaited(widget.controller.loadRelations(editingItemId!));
    }
  }

  Future<void> _openEditor(
    CatalogItemDraft value,
    String? itemId,
    bool persistent,
  ) async {
    if (widget.controller.selectedIds.length > 1) {
      widget.controller.clearSelection(notify: false);
    }
    widget.controller.selectItem(
      itemId == null
          ? null
          : widget.controller.items
                .where((item) => item.id == itemId)
                .firstOrNull,
    );
    setState(() {
      draft = value;
      editingItemId = itemId;
    });
    if (itemId != null) {
      unawaited(widget.controller.loadImages(itemId));
      unawaited(widget.controller.loadRelations(itemId));
    }
    if (persistent) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: const Color(0xFF111A27),
        child: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) {
            final activeDraft = draft;
            if (activeDraft == null) return const SizedBox.shrink();
            return CatalogEditor(
              draft: activeDraft,
              configuration: widget.controller.configuration!,
              saving: widget.controller.saving,
              error: widget.controller.error,
              isNew: editingItemId == null,
              images: widget.controller.images,
              imagesLoading: widget.controller.imagesLoading,
              imagesError: widget.controller.imagesError,
              relations: widget.controller.relations,
              relationsLoading: widget.controller.relationsLoading,
              relationsError: widget.controller.relationsError,
              onClose: () => Navigator.pop(dialogContext),
              onSave: () async {
                final saved = await _save();
                if (saved && dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
                return saved;
              },
              onDelete: editingItemId == null
                  ? null
                  : () async {
                      final deleted = await _delete();
                      if (deleted && dialogContext.mounted) {
                        Navigator.pop(dialogContext);
                      }
                      return deleted;
                    },
              onUploadImage: editingItemId == null
                  ? null
                  : (name, contentType, bytes) => widget.controller.uploadImage(
                      itemId: editingItemId!,
                      fileName: name,
                      contentType: contentType,
                      bytes: bytes,
                    ),
              onDeleteImage: editingItemId == null
                  ? null
                  : (imageId) =>
                        widget.controller.deleteImage(editingItemId!, imageId),
              onSearchRelations: widget.controller.searchRelationCandidates,
              onAddRelation: editingItemId == null
                  ? null
                  : (dependency, candidate) => widget.controller.addRelation(
                      editingItemId!,
                      dependency,
                      candidate,
                    ),
              onRemoveRelation: editingItemId == null
                  ? null
                  : (dependencyId, sourceItemId) =>
                        widget.controller.removeRelation(
                          editingItemId!,
                          dependencyId,
                          sourceItemId,
                        ),
            );
          },
        ),
      ),
    );
    if (mounted) _closeEditor();
  }

  Future<bool> _save() async {
    final value = draft;
    if (value == null) return false;
    final saved = await widget.controller.save(value, itemId: editingItemId);
    if (saved && mounted) {
      setState(() {
        editingItemId = widget.controller.selectedItem?.id;
        draft = widget.controller.selectedItem == null
            ? null
            : CatalogItemDraft.fromItem(widget.controller.selectedItem!);
      });
    }
    return saved;
  }

  Future<bool> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить товар?'),
        content: const Text('Карточка будет перемещена в архив каталога.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD94F5C),
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    final deleted = await widget.controller.deleteSelected();
    if (deleted && mounted) _closeEditor();
    return deleted;
  }

  Future<void> _downloadTemplate() async {
    final file = await widget.controller.downloadTemplate();
    if (file != null) await _saveSpreadsheet(file);
  }

  Future<void> _exportCatalog() async {
    final file = await widget.controller.exportCatalog();
    if (file != null) await _saveSpreadsheet(file);
  }

  Future<void> _saveSpreadsheet(CatalogSpreadsheetDownload file) async {
    try {
      await FilePicker.saveFile(
        dialogTitle: 'Сохранить XLSX',
        fileName: file.fileName,
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        bytes: file.bytes,
      );
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const AppSnackBar(content: Text('Не удалось сохранить XLSX-файл.')),
      );
    }
  }

  Future<void> _importCatalog() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    await widget.controller.importCatalog(fileName: file.name, bytes: bytes);
  }

  Future<void> _bulkDelete() async {
    final count = widget.controller.selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить выбранные карточки?'),
        content: Text('$count карточек будут перемещены в архив каталога.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD94F5C),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.controller.applyBulk(action: 'delete');
    }
  }

  void _closeEditor() {
    widget.controller.selectItem(null);
    setState(() {
      draft = null;
      editingItemId = null;
    });
  }
}

final class _MobileControlsToggle extends StatelessWidget {
  const _MobileControlsToggle({
    required this.expanded,
    required this.total,
    required this.selectedCount,
    required this.onTap,
  });

  final bool expanded;
  final int total;
  final int selectedCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFF131D2A),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: const BorderSide(color: Color(0xFF29384D)),
    ),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.tune, size: 18, color: Color(0xFF6DA2FF)),
            const SizedBox(width: 9),
            const Expanded(
              child: Text(
                'Управление каталогом',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              selectedCount > 0 ? 'Выбрано: $selectedCount' : '$total',
              style: const TextStyle(fontSize: 11, color: Color(0xFF8FA4C2)),
            ),
            const SizedBox(width: 6),
            AnimatedRotation(
              turns: expanded ? .5 : 0,
              duration: const Duration(milliseconds: 160),
              child: const Icon(Icons.expand_more, size: 20),
            ),
          ],
        ),
      ),
    ),
  );
}

final class _Header extends StatelessWidget {
  const _Header({
    required this.compact,
    required this.loading,
    required this.transferBusy,
    required this.onRefresh,
    required this.onTemplate,
    required this.onImport,
    required this.onExport,
    required this.onCreate,
  });
  final bool compact;
  final bool loading;
  final bool transferBusy;
  final VoidCallback onRefresh;
  final VoidCallback onTemplate;
  final VoidCallback onImport;
  final VoidCallback onExport;
  final VoidCallback onCreate;
  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              key: const Key('catalog-create'),
              onPressed: onCreate,
              icon: const Icon(Icons.add, size: 19),
              label: const Text('Добавить товар'),
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            tooltip: 'Действия с каталогом',
            enabled: !transferBusy,
            onSelected: (value) {
              switch (value) {
                case 'refresh':
                  onRefresh();
                case 'template':
                  onTemplate();
                case 'import':
                  onImport();
                case 'export':
                  onExport();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'refresh',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.refresh),
                  title: Text('Обновить'),
                ),
              ),
              PopupMenuItem(
                value: 'template',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.description_outlined),
                  title: Text('Скачать шаблон'),
                ),
              ),
              PopupMenuItem(
                value: 'import',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.upload_file_outlined),
                  title: Text('Импорт'),
                ),
              ),
              PopupMenuItem(
                value: 'export',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.download_outlined),
                  title: Text('Экспорт'),
                ),
              ),
            ],
            icon: const Icon(Icons.more_horiz),
          ),
        ],
      );
    }
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 12,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Каталог товаров',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 4),
            Text(
              'Карточки и структура текущей организации',
              style: TextStyle(color: Color(0xFF8298B8)),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              tooltip: 'Обновить',
              onPressed: loading ? null : onRefresh,
              icon: const Icon(Icons.refresh),
            ),
            OutlinedButton.icon(
              onPressed: transferBusy ? null : onTemplate,
              icon: const Icon(Icons.description_outlined),
              label: const Text('Шаблон'),
            ),
            OutlinedButton.icon(
              onPressed: transferBusy ? null : onImport,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Импорт'),
            ),
            OutlinedButton.icon(
              onPressed: transferBusy ? null : onExport,
              icon: const Icon(Icons.download_outlined),
              label: const Text('Экспорт'),
            ),
            FilledButton.icon(
              key: const Key('catalog-create'),
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Добавить товар'),
            ),
          ],
        ),
      ],
    );
  }
}

final class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    ),
  );
}

final class _Filters extends StatelessWidget {
  const _Filters({required this.controller, this.compact = false});
  final CatalogController controller;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final category = controller.selectedCategory;
    final fieldWidth = compact ? double.infinity : null;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        SizedBox(
          width: fieldWidth ?? 210,
          child: AppSelectField<String>(
            value: controller.sectionId,
            label: 'Раздел',
            isDense: true,
            options: [
              const AppSelectOption(value: null, label: 'Все разделы'),
              for (final section
                  in category?.sections ?? const <CatalogSection>[])
                AppSelectOption(value: section.id, label: section.name),
            ],
            enabled: category != null,
            onChanged: category == null ? null : controller.selectSection,
          ),
        ),
        SizedBox(
          width: fieldWidth ?? 190,
          child: AppSelectField<String>(
            value: controller.status,
            label: 'Статус',
            isDense: true,
            options: const [
              AppSelectOption(value: null, label: 'Все статусы'),
              AppSelectOption(value: 'approved', label: 'Согласовано'),
              AppSelectOption(value: 'pending', label: 'Не согласовано'),
            ],
            onChanged: controller.selectStatus,
          ),
        ),
      ],
    );
  }
}

final class _BulkToolbar extends StatelessWidget {
  const _BulkToolbar({
    required this.controller,
    required this.onDelete,
    required this.onEditRelations,
  });

  final CatalogController controller;
  final VoidCallback onDelete;
  final VoidCallback onEditRelations;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFF14243A),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFF31547E)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Checkbox(
            value: controller.currentPageSelected,
            onChanged: controller.transferBusy
                ? null
                : (_) => controller.toggleCurrentPage(),
          ),
          Text(
            'Выбрано: ${controller.selectedIds.length}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (controller.selectedIds.length > 1)
            OutlinedButton.icon(
              onPressed: controller.transferBusy ? null : onEditRelations,
              icon: const Icon(Icons.account_tree_outlined),
              label: const Text('Связи'),
            ),
          OutlinedButton(
            onPressed: controller.transferBusy
                ? null
                : () => controller.applyBulk(
                    action: 'set_status',
                    status: 'approved',
                  ),
            child: const Text('Согласовать'),
          ),
          OutlinedButton(
            onPressed: controller.transferBusy
                ? null
                : () => controller.applyBulk(
                    action: 'set_status',
                    status: 'pending',
                  ),
            child: const Text('Снять согласование'),
          ),
          OutlinedButton.icon(
            onPressed: controller.transferBusy ? null : onDelete,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFFF809D),
            ),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Удалить'),
          ),
          TextButton(
            onPressed: controller.transferBusy
                ? null
                : controller.clearSelection,
            child: const Text('Снять выбор'),
          ),
        ],
      ),
    ),
  );
}

final class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.item,
    required this.category,
    required this.selected,
    required this.selectedForBulk,
    required this.onToggleSelection,
    required this.onTap,
  });
  final CatalogItem item;
  final CatalogCategory? category;
  final bool selected;
  final bool selectedForBulk;
  final VoidCallback onToggleSelection;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final approved = item.status == 'approved';
    final price = item.values['base_price'];
    return Material(
      color: selected ? const Color(0xFF142A45) : const Color(0xFF131D2A),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? const Color(0xFF4D8DFF)
                  : const Color(0xFF29384D),
            ),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0E1621),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(11),
                          child: item.thumbnailUrl == null
                              ? _ProductImageFallback(category: category)
                              : Image.network(
                                  item.thumbnailUrl!,
                                  width: double.infinity,
                                  height: double.infinity,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) =>
                                      _ProductImageFallback(category: category),
                                  loadingBuilder: (context, child, progress) =>
                                      progress == null
                                      ? child
                                      : const Center(
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                ),
                        ),
                      ),
                      Positioned(
                        top: 7,
                        right: 7,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xDD0B131E),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Checkbox(
                            value: selectedForBulk,
                            onChanged: (_) => onToggleSelection(),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 5),
              Text(
                item.marking.isEmpty ? 'Без маркировки' : item.marking,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF8FA4C2), fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                category?.name ?? 'Категория',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF6F86A7), fontSize: 11),
              ),
              const SizedBox(height: 10),
              Text(
                _price(price),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              _StatusBadge(approved: approved),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _categoryIcon(String? category) {
    final value = category?.toLowerCase() ?? '';
    if (value.contains('работ')) return Icons.handyman_outlined;
    if (value.contains('материал')) return Icons.layers_outlined;
    return Icons.inventory_2_outlined;
  }

  static String _price(dynamic value) {
    final amount = value is num ? value.toDouble() : double.tryParse('$value');
    if (amount == null) return 'Цена не указана';
    return '${NumberFormat('#,##0.##', 'ru').format(amount)} ₽';
  }
}

final class _ProductImageFallback extends StatelessWidget {
  const _ProductImageFallback({required this.category});

  final CatalogCategory? category;

  @override
  Widget build(BuildContext context) => Center(
    child: Icon(
      _ProductCard._categoryIcon(category?.name),
      size: 54,
      color: const Color(0xFF6688B5),
    ),
  );
}

final class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.approved});
  final bool approved;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: approved ? const Color(0xFF123923) : const Color(0xFF3C2D12),
      borderRadius: BorderRadius.circular(7),
      border: Border.all(
        color: approved ? const Color(0xFF216C40) : const Color(0xFF70511B),
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(
        approved ? 'Согласовано' : 'Не согласовано',
        style: TextStyle(
          fontSize: 11,
          color: approved ? const Color(0xFF6DD998) : const Color(0xFFE5B457),
        ),
      ),
    ),
  );
}

final class _Pagination extends StatelessWidget {
  const _Pagination({required this.controller});
  final CatalogController controller;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      IconButton(
        tooltip: 'Предыдущая страница',
        onPressed: controller.page > 1
            ? () => controller.goToPage(controller.page - 1)
            : null,
        icon: const Icon(Icons.chevron_left),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text('Страница ${controller.page} из ${controller.pageCount}'),
      ),
      IconButton(
        tooltip: 'Следующая страница',
        onPressed: controller.page < controller.pageCount
            ? () => controller.goToPage(controller.page + 1)
            : null,
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );
}

final class _InlineError extends StatelessWidget {
  const _InlineError(this.message);
  final String message;
  @override
  Widget build(BuildContext context) =>
      AutoDismissNotice(message: message, child: _content(context));

  Widget _content(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFF3A1E27),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFFF809D)),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}

final class _InlineSuccess extends StatelessWidget {
  const _InlineSuccess(this.message);

  final String message;

  @override
  Widget build(BuildContext context) =>
      AutoDismissNotice(message: message, child: _content(context));

  Widget _content(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFF123122),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFF286E48)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, color: Color(0xFF6DD998)),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}

final class _CatalogMessage extends StatelessWidget {
  const _CatalogMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 52, color: const Color(0xFF6F86A7)),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 7),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF8FA4C2)),
          ),
          const SizedBox(height: 18),
          FilledButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    ),
  );
}
