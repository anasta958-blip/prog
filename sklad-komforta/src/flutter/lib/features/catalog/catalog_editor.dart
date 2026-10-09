import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:sklad_komforta_app/core/widgets/app_notice.dart';
import 'package:sklad_komforta_app/core/widgets/app_number_field.dart';
import 'package:sklad_komforta_app/core/widgets/app_select_field.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_models.dart';

/// Редактор карточки разделяет динамические поля, цены, остатки и изображения.
final class CatalogEditor extends StatefulWidget {
  const CatalogEditor({
    required this.draft,
    required this.configuration,
    required this.saving,
    required this.error,
    required this.isNew,
    required this.images,
    required this.imagesLoading,
    required this.relations,
    required this.relationsLoading,
    required this.onClose,
    required this.onSave,
    this.imagesError,
    this.relationsError,
    this.onDelete,
    this.onUploadImage,
    this.onDeleteImage,
    this.onSearchRelations,
    this.onAddRelation,
    this.onRemoveRelation,
    this.bulkItems = const [],
    this.relationCounts = const {},
    super.key,
  });

  final CatalogItemDraft draft;
  final List<CatalogItem> bulkItems;
  final Map<String, int> relationCounts;
  bool get isBulk => bulkItems.length > 1;
  final CatalogConfiguration configuration;
  final bool saving;
  final String? error;
  final bool isNew;
  final List<CatalogItemImage> images;
  final bool imagesLoading;
  final List<CatalogItemRelation> relations;
  final bool relationsLoading;
  final String? imagesError;
  final String? relationsError;
  final VoidCallback onClose;
  final Future<bool> Function() onSave;
  final Future<bool> Function()? onDelete;
  final Future<bool> Function(
    String fileName,
    String contentType,
    Uint8List bytes,
  )?
  onUploadImage;
  final Future<bool> Function(String imageId)? onDeleteImage;
  final Future<List<CatalogRelationCandidate>> Function(
    String dependencyId,
    String search,
  )?
  onSearchRelations;
  final Future<bool> Function(
    CatalogDependency dependency,
    CatalogRelationCandidate candidate,
  )?
  onAddRelation;
  final Future<bool> Function(String dependencyId, String sourceItemId)?
  onRemoveRelation;

  @override
  State<CatalogEditor> createState() => _CatalogEditorState();
}

class _CatalogEditorState extends State<CatalogEditor> {
  // Вкладки «Основное» и «Цены» проверяются отдельно: все вкладки построены
  // в IndexedStack, и ошибка на скрытой вкладке иначе молча блокирует
  // сохранение.
  final mainFormKey = GlobalKey<FormState>();
  final priceFormKey = GlobalKey<FormState>();
  int selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _normalizeStructure();
  }

  CatalogCategory get category => widget.configuration.categories.firstWhere(
    (item) => item.id == widget.draft.categoryId,
  );

  CatalogSection? get section {
    for (final item in category.sections) {
      if (item.id == widget.draft.sectionId) return item;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: Color(0xFF111A27),
      border: Border(left: BorderSide(color: Color(0xFF29384D))),
    ),
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.isBulk
                      ? 'Связи товаров: ${widget.bulkItems.length}'
                      : widget.isNew
                      ? 'Новый товар'
                      : 'Редактирование товара',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Закрыть',
                onPressed: widget.saving || widget.relationsLoading
                    ? null
                    : widget.onClose,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        if (widget.isBulk)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Связи',
              style: TextStyle(
                color: Color(0xFF4D8DFF),
                fontWeight: FontWeight.w700,
              ),
            ),
          )
        else
          _EditorTabs(
            selected: selectedTab,
            onSelected: (value) => setState(() => selectedTab = value),
          ),
        const Divider(height: 1),
        if (widget.relationsLoading) const LinearProgressIndicator(),
        Expanded(
          child: widget.isBulk
              ? _scroll([_relationsEditor()])
              : IndexedStack(
                  index: selectedTab,
                  children: [
                    Form(key: mainFormKey, child: _scroll(_mainFields())),
                    Form(key: priceFormKey, child: _scroll(_priceFields())),
                    _scroll([const _StockPlaceholder()]),
                    _scroll([_imagesEditor()]),
                    _scroll([_relationsEditor()]),
                  ],
                ),
        ),
        if (widget.error != null ||
            widget.imagesError != null ||
            widget.relationsError != null)
          AutoDismissNotice(
            message:
                widget.relationsError ?? widget.imagesError ?? widget.error!,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.relationsError ?? widget.imagesError ?? widget.error!,
                  style: const TextStyle(color: Color(0xFFFF809D)),
                ),
              ),
            ),
          ),
        const Divider(height: 1),
        if (!widget.isBulk)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 10,
              runSpacing: 8,
              children: [
                if (widget.onDelete != null)
                  IconButton(
                    tooltip: 'Удалить товар',
                    onPressed: widget.saving ? null : widget.onDelete,
                    color: const Color(0xFFFF7180),
                    icon: const Icon(Icons.delete_outline),
                  ),
                OutlinedButton(
                  onPressed: widget.saving ? null : widget.onClose,
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  key: const Key('catalog-save'),
                  onPressed: widget.saving
                      ? null
                      : () async {
                          if (!_validate()) return;
                          await widget.onSave();
                        },
                  child: widget.saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Сохранить'),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  Widget _scroll(List<Widget> children) =>
      ListView(padding: const EdgeInsets.all(20), children: children);

  List<Widget> _mainFields() => [
    AppSelectField<String>(
      value: widget.draft.categoryId,
      label: 'Категория',
      options: [
        for (final item in widget.configuration.categories)
          AppSelectOption(value: item.id, label: item.name),
      ],
      enabled: !widget.saving,
      onChanged: widget.saving
          ? null
          : (value) {
              if (value == null) return;
              setState(() {
                widget.draft.categoryId = value;
                widget.draft.sectionId = null;
                widget.draft.groupId = null;
                final allowedCodes = category.fields
                    .map((field) => field.code)
                    .toSet();
                widget.draft.values.removeWhere(
                  (code, _) => !allowedCodes.contains(code),
                );
                _normalizeStructure();
              });
            },
    ),
    if (category.sections.isNotEmpty) ...[
      const SizedBox(height: 14),
      AppSelectField<String>(
        value: widget.draft.sectionId,
        label: 'Раздел',
        options: [
          const AppSelectOption(value: null, label: 'Не выбран'),
          for (final item in category.sections)
            AppSelectOption(value: item.id, label: item.name),
        ],
        enabled: !widget.saving,
        onChanged: widget.saving
            ? null
            : (value) => setState(() {
                widget.draft.sectionId = value;
                widget.draft.groupId = null;
                _normalizeGroup();
              }),
      ),
    ],
    if (_groupVisible && section?.groups.isNotEmpty == true) ...[
      const SizedBox(height: 14),
      AppSelectField<String>(
        value: widget.draft.groupId,
        label: 'Группа',
        options: [
          const AppSelectOption(value: null, label: 'Без группы'),
          for (final item in section!.groups)
            AppSelectOption(value: item.id, label: item.name),
        ],
        enabled: !widget.saving,
        onChanged: widget.saving
            ? null
            : (value) => setState(() => widget.draft.groupId = value),
      ),
    ],
    const SizedBox(height: 14),
    TextFormField(
      initialValue: widget.draft.name,
      decoration: const InputDecoration(labelText: 'Наименование *'),
      textInputAction: TextInputAction.next,
      onChanged: (value) => widget.draft.name = value,
      validator: (value) => value == null || value.trim().isEmpty
          ? 'Введите наименование.'
          : null,
    ),
    if (_fieldVisible('marking')) ...[
      const SizedBox(height: 14),
      TextFormField(
        initialValue: widget.draft.marking,
        decoration: const InputDecoration(labelText: 'Маркировка / размер'),
        textInputAction: TextInputAction.next,
        onChanged: (value) => widget.draft.marking = value,
      ),
    ],
    for (final field in category.fields)
      if (_isDynamic(field) && !_isPriceField(field)) ...[
        const SizedBox(height: 14),
        _dynamicField(field),
      ],
    const SizedBox(height: 14),
    AppSelectField<String>(
      value: widget.draft.status,
      label: 'Статус',
      options: const [
        AppSelectOption(value: 'pending', label: 'Не согласовано'),
        AppSelectOption(value: 'approved', label: 'Согласовано'),
      ],
      enabled: !widget.saving,
      onChanged: widget.saving
          ? null
          : (value) => setState(() => widget.draft.status = value ?? 'pending'),
    ),
  ];

  List<Widget> _priceFields() {
    final fields = category.fields
        .where((field) => _isDynamic(field) && _isPriceField(field))
        .toList();
    if (fields.isEmpty) {
      return const [
        _EmptyTab(
          icon: Icons.payments_outlined,
          title: 'Ценовые поля не настроены',
          message: 'Добавьте нужные поля в настройках этой категории.',
        ),
      ];
    }
    return [
      const _TabIntroduction(
        icon: Icons.payments_outlined,
        title: 'Цены товара',
        message: 'Здесь собраны денежные и процентные поля карточки.',
      ),
      for (final field in fields) ...[
        const SizedBox(height: 14),
        _dynamicField(field),
      ],
    ];
  }

  Widget _dynamicField(CatalogField field) => _DynamicField(
    key: ValueKey('${category.id}-${field.code}'),
    field: field,
    value: widget.draft.values[field.code],
    dictionary: _dictionaryFor(field),
    enabled: !widget.saving,
    onChanged: (value) => widget.draft.values[field.code] = value,
  );

  Widget _imagesEditor() {
    if (widget.isNew) {
      return const _EmptyTab(
        icon: Icons.add_photo_alternate_outlined,
        title: 'Сначала сохраните товар',
        message:
            'После первого сохранения к карточке можно добавить изображения.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: _TabIntroduction(
                icon: Icons.photo_library_outlined,
                title: 'Изображения товара',
                message:
                    'JPEG, PNG или WebP, не более 10 МБ. Максимум 8 файлов.',
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed:
                  widget.imagesLoading ||
                      widget.images.length >= 8 ||
                      widget.onUploadImage == null
                  ? null
                  : _pickImage,
              icon: widget.imagesLoading
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Добавить'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (widget.images.isEmpty && !widget.imagesLoading)
          const _EmptyTab(
            icon: Icons.image_not_supported_outlined,
            title: 'Изображений пока нет',
            message: 'Добавьте первое изображение товара.',
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.88,
            ),
            itemCount: widget.images.length,
            itemBuilder: (context, index) {
              final image = widget.images[index];
              return _ImageTile(
                image: image,
                busy: widget.imagesLoading,
                onDelete: widget.onDeleteImage == null
                    ? null
                    : () => widget.onDeleteImage!(image.id),
              );
            },
          ),
      ],
    );
  }

  Widget _relationsEditor() {
    if (widget.isNew) {
      return const _EmptyTab(
        icon: Icons.account_tree_outlined,
        title: 'Сначала сохраните товар',
        message:
            'После первого сохранения к карточке можно привязать другие карточки.',
      );
    }
    final dependencies = widget.configuration.dependencies
        .where(
          (item) => widget.isBulk
              ? widget.bulkItems.any(
                  (target) => target.categoryId == item.targetCategoryId,
                )
              : item.targetCategoryId == widget.draft.categoryId,
        )
        .toList();
    if (dependencies.isEmpty) {
      return const _EmptyTab(
        icon: Icons.link_off_outlined,
        title: 'Зависимости не настроены',
        message: 'Разрешённые связи категорий задаются в настройках компании.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TabIntroduction(
          icon: Icons.account_tree_outlined,
          title: 'Связанные карточки',
          message: widget.isBulk
              ? 'Изменения сохраняются сразу для выбранных товаров подходящей категории. Остальные связи сохраняются.'
              : 'Одна карточка может использоваться в любом количестве других товаров.',
        ),
        const SizedBox(height: 16),
        for (final dependency in dependencies) ...[
          _relationGroup(dependency),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _relationGroup(CatalogDependency dependency) {
    final sourceCategory = widget.configuration.categories.firstWhere(
      (item) => item.id == dependency.sourceCategoryId,
    );
    final attached = widget.relations
        .where((item) => item.dependencyId == dependency.id)
        .toList();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF0E1621),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF29384D)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    sourceCategory.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                FilledButton.icon(
                  onPressed:
                      widget.relationsLoading ||
                          widget.onSearchRelations == null ||
                          widget.onAddRelation == null
                      ? null
                      : () => _pickRelation(dependency, sourceCategory.name),
                  icon: const Icon(Icons.add_link, size: 18),
                  label: const Text('Привязать'),
                ),
              ],
            ),
            if (attached.isEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Карточки не привязаны',
                style: TextStyle(color: Color(0xFF8298B8)),
              ),
            ] else
              for (final relation in attached) ...[
                const SizedBox(height: 10),
                _RelationRow(
                  relation: relation,
                  busy: widget.relationsLoading,
                  onDelete: widget.onRemoveRelation == null
                      ? null
                      : () => widget.onRemoveRelation!(
                          relation.dependencyId,
                          relation.sourceItemId,
                        ),
                ),
                if (widget.isBulk)
                  Text(
                    'Привязано к ${widget.relationCounts['${relation.dependencyId}/${relation.sourceItemId}'] ?? 0} из ${_targetCount(dependency)} товаров',
                    style: const TextStyle(color: Color(0xFF8298B8)),
                  ),
              ],
            if (widget.isBulk) ...[
              const SizedBox(height: 8),
              Text(
                'Применяется к ${_targetCount(dependency)} из ${widget.bulkItems.length} выбранных товаров',
                style: const TextStyle(color: Color(0xFF8298B8)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickRelation(
    CatalogDependency dependency,
    String categoryName,
  ) async {
    final candidate = await showDialog<CatalogRelationCandidate>(
      context: context,
      builder: (context) => _RelationPickerDialog(
        title: categoryName,
        dependencyId: dependency.id,
        excludedIds: widget.relations
            .where((item) => item.dependencyId == dependency.id)
            .where(
              (item) =>
                  !widget.isBulk ||
                  widget.relationCounts['${item.dependencyId}/${item.sourceItemId}'] ==
                      _targetCount(dependency),
            )
            .map((item) => item.sourceItemId)
            .toSet(),
        search: widget.onSearchRelations!,
      ),
    );
    if (candidate != null && mounted) {
      await widget.onAddRelation!(dependency, candidate);
    }
  }

  int _targetCount(CatalogDependency dependency) => widget.bulkItems
      .where((item) => item.categoryId == dependency.targetCategoryId)
      .length;

  Future<void> _pickImage() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
    );
    if (!mounted || file == null) return;
    Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const AppSnackBar(
          content: Text('Не удалось прочитать выбранный файл.'),
        ),
      );
      return;
    }
    if (!mounted) return;
    final extension = file.name.contains('.')
        ? file.name.split('.').last.toLowerCase()
        : '';
    final contentType = switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => null,
    };
    if (contentType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const AppSnackBar(
          content: Text('Выберите изображение JPEG, PNG или WebP.'),
        ),
      );
      return;
    }
    await widget.onUploadImage!(file.name, contentType, bytes);
  }

  /// Проверяет вкладки по очереди и открывает первую, где есть ошибка.
  bool _validate() {
    final forms = [mainFormKey, priceFormKey];
    for (var index = 0; index < forms.length; index++) {
      if (forms[index].currentState?.validate() == false) {
        setState(() => selectedTab = index);
        return false;
      }
    }
    return true;
  }

  bool get _groupVisible => _fieldVisible('group');

  bool _fieldVisible(String code) =>
      category.fields.any((field) => field.code == code && field.isVisible);

  bool _isDynamic(CatalogField field) =>
      field.isVisible &&
      !const {'group', 'name', 'marking'}.contains(field.code) &&
      field.fieldType != 'calculated_money' &&
      field.fieldType != 'relation';

  bool _isPriceField(CatalogField field) =>
      const {'money', 'percent', 'calculated_money'}.contains(field.fieldType);

  CatalogDictionary? _dictionaryFor(CatalogField field) {
    if (field.fieldType != 'dictionary') return null;
    if (field.dictionaryCode case final code?) {
      for (final dictionary in widget.configuration.dictionaries) {
        if (dictionary.code == code) return dictionary;
      }
    }
    return null;
  }

  void _normalizeStructure() {
    if (category.sections.length == 1) {
      widget.draft.sectionId = category.sections.single.id;
    }
    _normalizeGroup();
  }

  void _normalizeGroup() {
    if (_groupVisible && section?.groups.length == 1) {
      widget.draft.groupId = section!.groups.single.id;
    }
  }
}

final class _EditorTabs extends StatelessWidget {
  const _EditorTabs({required this.selected, required this.onSelected});
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 58,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _tab(0, Icons.tune, 'Основное'),
            _tab(1, Icons.payments_outlined, 'Цены'),
            _tab(2, Icons.warehouse_outlined, 'Остатки'),
            _tab(3, Icons.photo_library_outlined, 'Изображения'),
            _tab(4, Icons.account_tree_outlined, 'Связи'),
          ],
        ),
      ),
    ),
  );

  Widget _tab(int index, IconData icon, String label) => TextButton(
    onPressed: () => onSelected(index),
    style: TextButton.styleFrom(
      foregroundColor: selected == index
          ? const Color(0xFF6DA2FF)
          : const Color(0xFF9AAAC2),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      side: BorderSide(
        color: selected == index ? const Color(0xFF4D8DFF) : Colors.transparent,
        width: 0,
      ),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 17),
        const SizedBox(height: 3),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    ),
  );
}

final class _RelationRow extends StatelessWidget {
  const _RelationRow({
    required this.relation,
    required this.busy,
    required this.onDelete,
  });

  final CatalogItemRelation relation;
  final bool busy;
  final Future<bool> Function()? onDelete;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFF152132),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 9, 4, 9),
      child: Row(
        children: [
          const Icon(Icons.link, size: 18, color: Color(0xFF6DA2FF)),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  relation.sourceName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (relation.sourceMarking.isNotEmpty)
                  Text(
                    relation.sourceMarking,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF8298B8),
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Убрать связь',
            onPressed: busy || onDelete == null ? null : onDelete,
            color: const Color(0xFFFF7180),
            icon: const Icon(Icons.link_off, size: 19),
          ),
        ],
      ),
    ),
  );
}

final class _RelationPickerDialog extends StatefulWidget {
  const _RelationPickerDialog({
    required this.title,
    required this.dependencyId,
    required this.excludedIds,
    required this.search,
  });

  final String title;
  final String dependencyId;
  final Set<String> excludedIds;
  final Future<List<CatalogRelationCandidate>> Function(
    String dependencyId,
    String search,
  )
  search;

  @override
  State<_RelationPickerDialog> createState() => _RelationPickerDialogState();
}

final class _RelationPickerDialogState extends State<_RelationPickerDialog> {
  Timer? timer;
  List<CatalogRelationCandidate> items = const [];
  bool loading = true;
  String? error;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Выберите: ${widget.title}'),
    content: SizedBox(
      width: 520,
      height: 430,
      child: Column(
        children: [
          TextField(
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Поиск по наименованию или маркировке',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) {
              timer?.cancel();
              timer = Timer(
                const Duration(milliseconds: 300),
                () => _load(value),
              );
            },
          ),
          const SizedBox(height: 14),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : error != null
                ? Center(child: Text(error!))
                : items.isEmpty
                ? const Center(child: Text('Подходящие карточки не найдены'))
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return ListTile(
                        title: Text(item.name),
                        subtitle: item.marking.isEmpty
                            ? null
                            : Text(item.marking),
                        trailing: item.status == 'approved'
                            ? const Icon(
                                Icons.check_circle_outline,
                                color: Color(0xFF43CE8B),
                              )
                            : const Icon(
                                Icons.schedule,
                                color: Color(0xFFF5B64B),
                              ),
                        onTap: () => Navigator.pop(context, item),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
    ],
  );

  Future<void> _load(String query) async {
    final request = ++generation;
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final loaded = await widget.search(widget.dependencyId, query);
      if (!mounted || request != generation) return;
      setState(() {
        items = loaded
            .where((item) => !widget.excludedIds.contains(item.id))
            .toList(growable: false);
        loading = false;
      });
    } on Object {
      if (!mounted || request != generation) return;
      setState(() {
        error = 'Не удалось загрузить карточки.';
        loading = false;
      });
    }
  }
}

final class _StockPlaceholder extends StatelessWidget {
  const _StockPlaceholder();

  @override
  Widget build(BuildContext context) => const _EmptyTab(
    icon: Icons.warehouse_outlined,
    title: 'Складской учёт ещё не подключён',
    message:
        'Здесь будут остатки товара по каждому складу и общий доступный остаток. '
        'Сейчас данные не сохраняются, чтобы не создавать фиктивную складскую модель.',
  );
}

final class _TabIntroduction extends StatelessWidget {
  const _TabIntroduction({
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: const Color(0xFF6DA2FF), size: 22),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              message,
              style: const TextStyle(color: Color(0xFF8FA3BF), height: 1.35),
            ),
          ],
        ),
      ),
    ],
  );
}

final class _EmptyTab extends StatelessWidget {
  const _EmptyTab({
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: const Color(0xFF151F2E),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFF2A3B52)),
    ),
    child: Column(
      children: [
        Icon(icon, size: 34, color: const Color(0xFF6D86A8)),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF8FA3BF), height: 1.4),
        ),
      ],
    ),
  );
}

final class _ImageTile extends StatelessWidget {
  const _ImageTile({
    required this.image,
    required this.busy,
    required this.onDelete,
  });
  final CatalogItemImage image;
  final bool busy;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFF0C1522),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFF2A3B52)),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            image.downloadUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: Color(0xFF7185A3),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(9, 18, 38, 8),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xE6101824)],
                ),
              ),
              child: Text(
                image.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ),
          Positioned(
            right: 6,
            bottom: 4,
            child: IconButton.filledTonal(
              tooltip: 'Удалить изображение',
              onPressed: busy ? null : onDelete,
              icon: const Icon(Icons.delete_outline, size: 17),
            ),
          ),
        ],
      ),
    ),
  );
}

final class _DynamicField extends StatelessWidget {
  const _DynamicField({
    required this.field,
    required this.value,
    required this.dictionary,
    required this.enabled,
    required this.onChanged,
    super.key,
  });
  final CatalogField field;
  final dynamic value;
  final CatalogDictionary? dictionary;
  final bool enabled;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) {
    if (field.fieldType == 'boolean') {
      return CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(field.label),
        value: value == true,
        onChanged: enabled ? (selected) => onChanged(selected == true) : null,
      );
    }
    if (dictionary != null) {
      final values = dictionary!.items.map((item) => item.value).toList();
      final selected = values.contains(value) ? value as String : null;
      return AppSelectField<String>(
        value: selected,
        label: _label,
        options: [
          const AppSelectOption(value: null, label: 'Не выбрано'),
          for (final item in values) AppSelectOption(value: item, label: item),
        ],
        enabled: enabled,
        onChanged: enabled ? onChanged : null,
        validator: field.isRequired && selected == null
            ? (_) => 'Выберите значение.'
            : null,
      );
    }
    if (field.fieldType == 'dictionary') {
      return AppSelectField<String>(
        value: null,
        label: _label,
        options: const [
          AppSelectOption(value: null, label: 'Справочник не назначен'),
        ],
        enabled: false,
        onChanged: null,
      );
    }
    if (_numeric) {
      return AppNumberField(
        value: value?.toString() ?? '',
        groupThousands: field.fieldType == 'money',
        enabled: enabled,
        minimum: field.fieldType == 'money' ? 0 : null,
        decoration: InputDecoration(labelText: _label),
        // Очищенное поле отправляется как null, а не пустая строка: сервер
        // отклоняет строку в числовом поле.
        onChanged: (text) => onChanged(
          text.trim().isEmpty
              ? null
              : num.tryParse(text.replaceAll(',', '.')) ?? text,
        ),
        validator: (text) {
          if (field.isRequired && (text ?? '').trim().isEmpty) {
            return 'Заполните поле.';
          }
          final normalized = (text ?? '').trim();
          if (field.code == 'base_price' &&
              normalized.isNotEmpty &&
              (num.tryParse(normalized.replaceAll(',', '.')) ?? 0) <= 0) {
            return 'Цена должна быть больше нуля.';
          }
          return null;
        },
      );
    }
    return TextFormField(
      initialValue: value?.toString() ?? '',
      enabled: enabled,
      decoration: InputDecoration(labelText: _label),
      keyboardType: _numeric
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : TextInputType.text,
      onChanged: (text) {
        if (!_numeric) {
          onChanged(text);
          return;
        }
        onChanged(num.tryParse(text.replaceAll(',', '.')) ?? text);
      },
      validator: (text) {
        final normalized = text?.trim() ?? '';
        if (field.isRequired && normalized.isEmpty) return 'Заполните поле.';
        if (_numeric &&
            normalized.isNotEmpty &&
            num.tryParse(normalized.replaceAll(',', '.')) == null) {
          return 'Введите число.';
        }
        if (field.code == 'base_price' && normalized.isNotEmpty) {
          final number = num.tryParse(normalized.replaceAll(',', '.'));
          if (number == null || number <= 0) {
            return 'Цена должна быть больше нуля.';
          }
        }
        return null;
      },
      maxLines: field.code.contains('note') ? 3 : 1,
    );
  }

  bool get _numeric =>
      const {'number', 'money', 'percent'}.contains(field.fieldType);
  String get _label => '${field.label}${field.isRequired ? ' *' : ''}';
}
