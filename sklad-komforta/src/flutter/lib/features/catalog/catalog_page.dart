import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sklad_komforta_app/core/widgets/app_select_field.dart';
import 'package:intl/intl.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_controller.dart';
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
  CatalogItemDraft? draft;
  String? editingItemId;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final persistentEditor = constraints.maxWidth >= 1180;
        return Row(
          children: [
            Expanded(child: _catalogBody(persistentEditor)),
            if (persistentEditor && draft != null)
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
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            loading: controller.loading,
            onRefresh: controller.reloadConfiguration,
            onCreate: () =>
                _openEditor(controller.createDraft(), null, persistentEditor),
          ),
          const SizedBox(height: 18),
          TextField(
            key: const Key('catalog-search'),
            onChanged: controller.updateSearch,
            decoration: const InputDecoration(
              hintText: 'Поиск по наименованию или маркировке…',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 40,
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
          const SizedBox(height: 12),
          _Filters(controller: controller),
          const SizedBox(height: 14),
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
          if (controller.error != null) ...[
            const SizedBox(height: 10),
            _InlineError(controller.error!),
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
                        >= 1250 => 5,
                        >= 970 => 4,
                        >= 700 => 3,
                        >= 430 => 2,
                        _ => 1,
                      };
                      return GridView.builder(
                        key: const PageStorageKey('catalog-grid'),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: columns == 1 ? 1.55 : 0.76,
                        ),
                        itemCount: controller.items.length,
                        itemBuilder: (context, index) {
                          final item = controller.items[index];
                          return _ProductCard(
                            item: item,
                            category: _category(item.categoryId),
                            selected: editingItemId == item.id,
                            onTap: () => _openEditor(
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

  Future<void> _openEditor(
    CatalogItemDraft value,
    String? itemId,
    bool persistent,
  ) async {
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

  void _closeEditor() {
    widget.controller.selectItem(null);
    setState(() {
      draft = null;
      editingItemId = null;
    });
  }
}

final class _Header extends StatelessWidget {
  const _Header({
    required this.loading,
    required this.onRefresh,
    required this.onCreate,
  });
  final bool loading;
  final VoidCallback onRefresh;
  final VoidCallback onCreate;
  @override
  Widget build(BuildContext context) => Wrap(
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
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: loading ? null : onRefresh,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
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
  const _Filters({required this.controller});
  final CatalogController controller;
  @override
  Widget build(BuildContext context) {
    final category = controller.selectedCategory;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        SizedBox(
          width: 210,
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
          width: 190,
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

final class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.item,
    required this.category,
    required this.selected,
    required this.onTap,
  });
  final CatalogItem item;
  final CatalogCategory? category;
  final bool selected;
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
  Widget build(BuildContext context) => DecoratedBox(
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
