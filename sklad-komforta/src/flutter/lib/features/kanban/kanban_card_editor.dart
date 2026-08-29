import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sklad_komforta_app/core/widgets/app_select_field.dart';
import 'package:sklad_komforta_app/features/kanban/kanban_models.dart';

/// Универсальная форма карточки строится только из полей, выбранных для
/// категории в настройках канбана. Специальные редакторы КП и комплектации
/// будут подключаться поверх этого контракта отдельными модулями.
final class KanbanCardEditor extends StatefulWidget {
  const KanbanCardEditor({
    required this.board,
    required this.draft,
    required this.saving,
    required this.onSave,
    required this.onCancel,
    this.error,
    this.card,
    this.onDelete,
    this.readOnly = false,
    this.categories,
    super.key,
  });

  final KanbanBoard board;
  final KanbanCardDraft draft;
  final KanbanCard? card;
  final bool saving;
  final String? error;
  final Future<void> Function() onSave;
  final VoidCallback onCancel;
  final Future<void> Function()? onDelete;
  final bool readOnly;
  final List<KanbanCategory>? categories;

  @override
  State<KanbanCardEditor> createState() => _KanbanCardEditorState();
}

final class _KanbanCardEditorState extends State<KanbanCardEditor> {
  final _formKey = GlobalKey<FormState>();

  KanbanCategory? _categoryById(String categoryId) {
    for (final category in widget.categories ?? widget.board.categories) {
      if (category.categoryId == categoryId) return category;
    }
    return null;
  }

  KanbanCategory? get _category => _categoryById(widget.draft.categoryId);

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
    backgroundColor: const Color(0xFF111A27),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: Color(0xFF2A3A50)),
    ),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620, maxHeight: 760),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 12, 14),
            child: Row(
              children: [
                const Icon(
                  Icons.description_outlined,
                  color: Color(0xFF4D8DFF),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.card == null
                        ? 'Новая карточка'
                        : 'Карточка №${widget.card!.number}',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Закрыть',
                  onPressed: widget.saving ? null : widget.onCancel,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(22),
                children: [
                  AppSelectField<String>(
                    value: widget.draft.categoryId.isEmpty
                        ? null
                        : widget.draft.categoryId,
                    label: 'Категория *',
                    options: [
                      for (final category
                          in widget.categories ?? widget.board.categories)
                        AppSelectOption(
                          value: category.categoryId,
                          label: category.name,
                        ),
                    ],
                    enabled: !widget.saving && !widget.readOnly,
                    validator: (value) =>
                        value == null ? 'Выберите категорию карточки.' : null,
                    onChanged: widget.saving || widget.readOnly
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() {
                              widget.draft.categoryId = value;
                              final category = _categoryById(value);
                              widget.draft.sectionId =
                                  category?.sections.length == 1
                                  ? category!.sections.single.id
                                  : null;
                              widget.draft.values.clear();
                            });
                          },
                  ),
                  if ((_category?.sections.isNotEmpty ?? false)) ...[
                    const SizedBox(height: 16),
                    AppSelectField<String>(
                      value: widget.draft.sectionId,
                      label: 'Раздел *',
                      options: [
                        for (final section in _category!.sections)
                          AppSelectOption(
                            value: section.id,
                            label: section.name,
                          ),
                      ],
                      enabled:
                          !widget.saving &&
                          !widget.readOnly &&
                          _category!.sections.length > 1,
                      validator: (value) =>
                          value == null ? 'Выберите раздел карточки.' : null,
                      onChanged:
                          widget.saving ||
                              widget.readOnly ||
                              _category!.sections.length == 1
                          ? null
                          : (value) =>
                                setState(() => widget.draft.sectionId = value),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: widget.draft.title,
                    enabled: !widget.saving && !widget.readOnly,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Название карточки *',
                    ),
                    maxLength: 200,
                    onChanged: (value) => widget.draft.title = value,
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Введите название карточки.'
                        : null,
                  ),
                  for (final field in _category?.fields ?? const [])
                    if (field.code != 'name' &&
                        field.fieldType != 'relation' &&
                        field.fieldType != 'calculated_money') ...[
                      const SizedBox(height: 14),
                      _fieldEditor(field),
                    ],
                  if (widget.error != null) ...[
                    const SizedBox(height: 16),
                    _EditorError(message: widget.error!),
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
                  IconButton.outlined(
                    tooltip: 'Удалить карточку',
                    color: const Color(0xFFFF7180),
                    onPressed: widget.saving ? null : widget.onDelete,
                    icon: const Icon(Icons.delete_outline),
                  ),
                const Spacer(),
                OutlinedButton(
                  onPressed: widget.saving ? null : widget.onCancel,
                  child: Text(widget.readOnly ? 'Закрыть' : 'Отмена'),
                ),
                if (!widget.readOnly) ...[
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: widget.saving
                        ? null
                        : () async {
                            if (_formKey.currentState?.validate() != true) {
                              return;
                            }
                            await widget.onSave();
                          },
                    icon: widget.saving
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined, size: 18),
                    label: const Text('Сохранить'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _fieldEditor(KanbanField field) {
    final label = '${field.label}${field.isRequired ? ' *' : ''}';
    final value = widget.draft.values[field.code];
    if (field.fieldType == 'boolean') {
      return CheckboxListTile(
        value: value == true,
        enabled: !widget.saving && !widget.readOnly,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(label),
        onChanged: widget.readOnly
            ? null
            : (next) => setState(
                () => widget.draft.values[field.code] = next ?? false,
              ),
      );
    }
    if (field.fieldType == 'dictionary' && field.options.isNotEmpty) {
      return AppSelectField<String>(
        value: value as String?,
        label: label,
        options: [
          if (!field.isRequired)
            const AppSelectOption<String>(value: null, label: 'Не выбрано'),
          for (final option in field.options)
            AppSelectOption(value: option.value, label: option.value),
        ],
        enabled: !widget.saving && !widget.readOnly,
        validator: field.isRequired
            ? (selected) => selected == null ? 'Выберите значение.' : null
            : null,
        onChanged: widget.saving || widget.readOnly
            ? null
            : (selected) => setState(() {
                if (selected == null) {
                  widget.draft.values.remove(field.code);
                } else {
                  widget.draft.values[field.code] = selected;
                }
              }),
      );
    }
    final numeric = const {
      'number',
      'money',
      'percent',
    }.contains(field.fieldType);
    return TextFormField(
      key: ValueKey('${widget.draft.categoryId}-${field.code}'),
      initialValue: value?.toString() ?? '',
      enabled: !widget.saving && !widget.readOnly,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : TextInputType.text,
      inputFormatters: numeric
          ? [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*[.,]?\d*'))]
          : null,
      decoration: InputDecoration(labelText: label),
      onChanged: (next) {
        if (next.trim().isEmpty) {
          widget.draft.values.remove(field.code);
        } else if (numeric) {
          final parsed = num.tryParse(next.replaceAll(',', '.'));
          if (parsed != null) widget.draft.values[field.code] = parsed;
        } else {
          widget.draft.values[field.code] = next;
        }
      },
      validator: (next) {
        if (field.isRequired && (next == null || next.trim().isEmpty)) {
          return 'Заполните поле «${field.label}».';
        }
        if (numeric && next != null && next.trim().isNotEmpty) {
          if (num.tryParse(next.replaceAll(',', '.')) == null) {
            return 'Введите число.';
          }
        }
        return null;
      },
    );
  }
}

final class _EditorError extends StatelessWidget {
  const _EditorError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFF321825),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFF8D3455)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline, color: Color(0xFFFF809D), size: 19),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: Color(0xFFFFB1C3), height: 1.35),
          ),
        ),
      ],
    ),
  );
}
