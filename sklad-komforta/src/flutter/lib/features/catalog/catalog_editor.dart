import 'package:flutter/material.dart';
import 'package:sklad_komforta_app/core/widgets/app_select_field.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_models.dart';

/// Динамическая форма карточки, построенная по настройкам выбранной категории.
final class CatalogEditor extends StatefulWidget {
  const CatalogEditor({
    required this.draft,
    required this.configuration,
    required this.saving,
    required this.error,
    required this.isNew,
    required this.onClose,
    required this.onSave,
    this.onDelete,
    super.key,
  });

  final CatalogItemDraft draft;
  final CatalogConfiguration configuration;
  final bool saving;
  final String? error;
  final bool isNew;
  final VoidCallback onClose;
  final Future<bool> Function() onSave;
  final Future<bool> Function()? onDelete;

  @override
  State<CatalogEditor> createState() => _CatalogEditorState();
}

class _CatalogEditorState extends State<CatalogEditor> {
  final formKey = GlobalKey<FormState>();

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
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.isNew ? 'Новый товар' : 'Редактирование товара',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Закрыть',
                onPressed: widget.saving ? null : widget.onClose,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Form(
            key: formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
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
                        : (value) =>
                              setState(() => widget.draft.groupId = value),
                  ),
                ],
                const SizedBox(height: 14),
                TextFormField(
                  initialValue: widget.draft.name,
                  decoration: const InputDecoration(
                    labelText: 'Наименование *',
                  ),
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
                    decoration: const InputDecoration(
                      labelText: 'Маркировка / размер',
                    ),
                    textInputAction: TextInputAction.next,
                    onChanged: (value) => widget.draft.marking = value,
                  ),
                ],
                for (final field in category.fields)
                  if (_isDynamic(field)) ...[
                    const SizedBox(height: 14),
                    _DynamicField(
                      key: ValueKey('${category.id}-${field.code}'),
                      field: field,
                      value: widget.draft.values[field.code],
                      dictionary: _dictionaryFor(field),
                      enabled: !widget.saving,
                      onChanged: (value) =>
                          widget.draft.values[field.code] = value,
                    ),
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
                      : (value) => setState(
                          () => widget.draft.status = value ?? 'pending',
                        ),
                ),
                if (widget.error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    widget.error!,
                    style: const TextStyle(color: Color(0xFFFF809D)),
                  ),
                ],
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (widget.onDelete != null)
                IconButton(
                  tooltip: 'Удалить товар',
                  onPressed: widget.saving ? null : widget.onDelete,
                  color: const Color(0xFFFF7180),
                  icon: const Icon(Icons.delete_outline),
                ),
              const Spacer(),
              OutlinedButton(
                onPressed: widget.saving ? null : widget.onClose,
                child: const Text('Отмена'),
              ),
              const SizedBox(width: 10),
              FilledButton(
                key: const Key('catalog-save'),
                onPressed: widget.saving
                    ? null
                    : () async {
                        if (formKey.currentState?.validate() != true) return;
                        await widget.onSave();
                      },
                child: widget.saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
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

  bool get _groupVisible => _fieldVisible('group');

  bool _fieldVisible(String code) =>
      category.fields.any((field) => field.code == code && field.isVisible);

  bool _isDynamic(CatalogField field) =>
      field.isVisible &&
      !const {'group', 'name', 'marking'}.contains(field.code) &&
      field.fieldType != 'calculated_money' &&
      field.fieldType != 'relation';

  CatalogDictionary? _dictionaryFor(CatalogField field) {
    if (field.fieldType != 'dictionary') return null;
    final aliases = switch (field.code) {
      'unit' => const ['unit', 'единиц'],
      'supplier' => const ['supplier', 'постав'],
      _ => [field.code, field.label.toLowerCase()],
    };
    for (final dictionary in widget.configuration.dictionaries) {
      final source = '${dictionary.code} ${dictionary.name}'.toLowerCase();
      if (aliases.any(source.contains)) return dictionary;
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
