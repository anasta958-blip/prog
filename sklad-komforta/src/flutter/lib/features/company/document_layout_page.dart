import 'package:flutter/material.dart';
import 'package:sklad_komforta_app/core/network/api_exception.dart';
import 'package:sklad_komforta_app/core/widgets/app_select_field.dart';
import 'company_controller.dart';
import 'configuration_edit_guard.dart';
import 'document_layout_models.dart';

final class DocumentLayoutPage extends StatefulWidget {
  const DocumentLayoutPage({
    required this.controller,
    this.guard,
    this.showTitle = true,
    super.key,
  });
  final bool showTitle;
  final CompanyController controller;
  final ConfigurationEditGuard? guard;
  @override
  State<DocumentLayoutPage> createState() => _DocumentLayoutPageState();
}

final class _DocumentLayoutPageState extends State<DocumentLayoutPage> {
  List<DocumentLayoutBoard>? boards;
  String? boardId;
  String? error;
  bool order = false;
  bool dirty = false;
  bool saving = false;
  bool saved = false;

  DocumentLayoutBoard? get board =>
      boards?.where((item) => item.id == boardId).firstOrNull;
  List<DocumentLayoutBoard> get available =>
      boards
          ?.where((item) => (item.specialization == 'order') == order)
          .toList() ??
      [];

  @override
  void initState() {
    super.initState();
    widget.guard?.attach(this, _canLeave);
    _load();
  }

  @override
  void dispose() {
    widget.guard?.detach(this);
    super.dispose();
  }

  Future<bool> _canLeave(BuildContext context) async {
    if (saving) return false;
    if (!dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Несохранённые настройки'),
            content: const Text('Выйти без сохранения изменений конструктора?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Остаться'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Не сохранять'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _load() async {
    try {
      final result = await widget.controller.getDocumentLayouts();
      if (!mounted) return;
      setState(() {
        boards = result;
        if (!available.any((item) => item.id == boardId)) {
          boardId = available.firstOrNull?.id;
        }
        dirty = false;
        error = null;
      });
    } catch (exception) {
      if (mounted) {
        setState(
          () => error = exception is ApiException
              ? exception.message
              : 'Не удалось загрузить настройки конструктора.',
        );
      }
    }
  }

  Future<void> _select({bool? nextOrder, String? nextBoard}) async {
    if (!await _canLeave(context) || !mounted) return;
    if (dirty) await _load();
    if (!mounted || dirty) return;
    setState(() {
      order = nextOrder ?? order;
      boardId = nextOrder != null ? available.firstOrNull?.id : nextBoard;
      saved = false;
    });
  }

  void _change(VoidCallback action) => setState(() {
    action();
    dirty = true;
    saved = false;
  });

  Future<void> _save() async {
    final current = board;
    if (current == null) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.controller.saveDocumentLayout(current);
      if (mounted) {
        setState(() {
          dirty = false;
          saved = true;
        });
      }
    } catch (exception) {
      if (mounted) {
        setState(
          () => error = exception is ApiException
              ? exception.message
              : 'Не удалось сохранить настройки.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (boards == null && error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (widget.showTitle)
          const Text(
            'Конструктор ссылки и PDF',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            ChoiceChip(
              label: const Text('КП / ПКП'),
              selected: !order,
              onSelected: saving ? null : (_) => _select(nextOrder: false),
            ),
            ChoiceChip(
              label: const Text('Комплектация'),
              selected: order,
              onSelected: saving ? null : (_) => _select(nextOrder: true),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          order
              ? 'Выберите поля и их порядок в PDF комплектации.'
              : 'Выберите поля и их порядок. Один набор используется в клиентской ссылке и PDF КП/ПКП.',
        ),
        const SizedBox(height: 8),
        const Text(
          'Настройки относятся к таблицам позиций. Итоги и шапка документа не меняются. '
          'Визуальное оформление блоков будет добавлено отдельно.',
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              error!,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        if (boards == null)
          TextButton(onPressed: _load, child: const Text('Повторить')),
        if (boards != null && available.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('Канбаны этого типа не настроены.'),
          ),
        if (available.isNotEmpty) ...[
          const SizedBox(height: 20),
          AbsorbPointer(
            absorbing: saving,
            child: AppSelectField<String>(
              value: boardId,
              label: 'Канбан',
              options: available
                  .map(
                    (item) => AppSelectOption(value: item.id, label: item.name),
                  )
                  .toList(),
              onChanged: (value) => _select(nextBoard: value),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Внимание: выбранные поля КП/ПКП будут доступны внешнему клиенту, в том числе закупочные данные, если вы их включите.',
          ),
          if (board?.categories.isEmpty ?? false)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('В канбане нет категорий.'),
            ),
          for (final category
              in board?.categories ?? <DocumentLayoutCategory>[])
            _category(category),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: saving || !dirty ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(saving ? 'Сохранение…' : 'Сохранить настройки'),
              ),
              if (saved) const Text('Настройки сохранены'),
            ],
          ),
        ],
      ],
    );
  }

  Widget _category(DocumentLayoutCategory category) {
    final codes = category.codes;
    final ordered = codes == null
        ? category.fields
        : [
            ...codes.map(
              (code) =>
                  category.fields.firstWhere((field) => field.code == code),
            ),
            ...category.fields.where((field) => !codes.contains(field.code)),
          ];
    return Card(
      margin: const EdgeInsets.only(top: 14),
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text(category.name),
        childrenPadding: const EdgeInsets.all(12),
        children: [
          SwitchListTile(
            title: const Text('Свой набор полей'),
            subtitle: Text(
              codes == null
                  ? 'Используется прежний стандартный вид документа.'
                  : 'Отмеченные поля выводятся в указанном порядке.',
            ),
            value: codes != null,
            onChanged: saving
                ? null
                : (enabled) => _change(
                    () => category.codes = enabled
                        ? category.fields
                              .where(
                                (field) =>
                                    order ||
                                    const {
                                      'name',
                                      'marking',
                                      'quantity',
                                      'unit',
                                      'base_price',
                                      'discount_value',
                                      'line_total',
                                    }.contains(field.code),
                              )
                              .map((field) => field.code)
                              .toList()
                        : null,
                  ),
          ),
          if (codes != null && codes.isEmpty)
            const Text('Поля не выбраны: таблица позиций не будет показана.'),
          if (codes != null)
            for (final field in ordered)
              Row(
                children: [
                  Expanded(
                    child: CheckboxListTile(
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(field.label),
                      value: codes.contains(field.code),
                      onChanged: saving
                          ? null
                          : (value) => _change(() {
                              if (value == true) {
                                codes.add(field.code);
                              } else {
                                codes.remove(field.code);
                              }
                            }),
                    ),
                  ),
                  if (codes.contains(field.code)) ...[
                    IconButton(
                      tooltip: 'Переместить выше',
                      icon: const Icon(Icons.arrow_upward),
                      onPressed: saving || codes.indexOf(field.code) == 0
                          ? null
                          : () => _move(codes, field.code, -1),
                    ),
                    IconButton(
                      tooltip: 'Переместить ниже',
                      icon: const Icon(Icons.arrow_downward),
                      onPressed:
                          saving ||
                              codes.indexOf(field.code) == codes.length - 1
                          ? null
                          : () => _move(codes, field.code, 1),
                    ),
                  ],
                ],
              ),
        ],
      ),
    );
  }

  void _move(List<String> codes, String code, int offset) => _change(() {
    final index = codes.indexOf(code);
    codes.removeAt(index);
    codes.insert(index + offset, code);
  });
}
