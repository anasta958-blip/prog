import 'package:flutter/material.dart';
import 'package:sklad_komforta_app/core/platform/workspace_address.dart';
import 'package:sklad_komforta_app/core/network/api_exception.dart';
import 'package:sklad_komforta_app/core/widgets/app_select_field.dart';
import 'package:sklad_komforta_app/core/widgets/app_notice.dart';
import 'company_controller.dart';
import 'configuration_edit_guard.dart';
import 'document_layout_models.dart';
import 'document_template.dart';
import 'document_canvas_editor.dart';

final class DocumentLayoutPage extends StatefulWidget {
  const DocumentLayoutPage({
    required this.controller,
    this.guard,
    this.showTitle = true,
    this.readPath = readWorkspacePath,
    this.writePath = writeWorkspacePath,
    super.key,
  });
  final bool showTitle;
  final String Function() readPath;
  final ValueChanged<String> writePath;
  final CompanyController controller;
  final ConfigurationEditGuard? guard;
  @override
  State<DocumentLayoutPage> createState() => _DocumentLayoutPageState();
}

final class _DocumentLayoutPageState extends State<DocumentLayoutPage> {
  final form = GlobalKey<FormState>();
  List<DocumentLayoutBoard>? boards;
  String? boardId;
  String? error;
  bool order = false;
  bool dirty = false;
  bool saving = false;

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
    final path = widget.readPath().split('/');
    if (path.length >= 4 &&
        path[1] == 'company' &&
        path[2] == 'documents' &&
        (path[3] == 'quote' || path[3] == 'order')) {
      order = path[3] == 'order';
      boardId = path.length == 5 ? path[4] : null;
    }
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
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            icon: const Icon(
              Icons.warning_amber_rounded,
              color: Color(0xFFF59E0B),
            ),
            title: const Text('Изменения не сохранены'),
            content: const Text('Выйти без сохранения изменений конструктора?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Остаться'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFB83A4B),
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Выйти без сохранения'),
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
        if (!available.any((item) => item.id == boardId)) boardId = null;
        if (board case final current?) _prepare(current);
        dirty = false;
        error = null;
      });
      _saveAddress();
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
      boardId = nextOrder != null ? null : nextBoard;
      if (board case final current?) _prepare(current);
    });
    _saveAddress();
  }

  void _saveAddress() => widget.writePath(
    '/company/documents/${order ? 'order' : 'quote'}${boardId == null ? '' : '/$boardId'}',
  );

  void _change(VoidCallback action) => setState(() {
    action();
    dirty = true;
  });

  Future<void> _save() async {
    if (!(form.currentState?.validate() ?? true)) return;
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
        });
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const AppSnackBar(
              content: Text('Настройки конструктора сохранены.'),
            ),
          );
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
    return Form(
      key: form,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.showTitle)
                    const Text(
                      'Конструктор ссылки и PDF',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  if (widget.showTitle) const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) => Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ChoiceChip(
                          label: const Text('КП / ПКП'),
                          selected: !order,
                          onSelected: saving
                              ? null
                              : (_) => _select(nextOrder: false),
                        ),
                        ChoiceChip(
                          label: const Text('Комплектация'),
                          selected: order,
                          onSelected: saving
                              ? null
                              : (_) => _select(nextOrder: true),
                        ),
                        if (available.isNotEmpty) ...[
                          SizedBox(
                            width: constraints.maxWidth >= 1000
                                ? (constraints.maxWidth - 800).clamp(
                                    240.0,
                                    480.0,
                                  )
                                : constraints.maxWidth.clamp(0.0, 320.0),
                            child: AbsorbPointer(
                              absorbing: saving,
                              child: AppSelectField<String>(
                                value: boardId,
                                label: 'Канбан',
                                isDense: true,
                                options: available
                                    .map(
                                      (item) => AppSelectOption(
                                        value: item.id,
                                        label: item.name,
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) => _select(nextBoard: value),
                              ),
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: saving || board == null ? null : _save,
                            icon: const Icon(Icons.save_outlined),
                            label: Text(
                              saving ? 'Сохранение…' : 'Сохранить настройки',
                            ),
                          ),
                          if (dirty) const Text('Есть несохранённые изменения'),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    order
                        ? 'Макет PDF комплектации.'
                        : 'Макет ссылки и PDF. Выбранные поля будут доступны клиенту, включая закупочные данные, если вы их включите.',
                    style: const TextStyle(fontSize: 12),
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
                    TextButton(
                      onPressed: _load,
                      child: const Text('Повторить'),
                    ),
                  if (boards != null && available.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('Канбаны этого типа не настроены.'),
                    ),
                  if (available.isNotEmpty) ...[
                    if (board?.categories.isEmpty ?? false)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('В канбане нет категорий.'),
                      ),
                    if (board == null)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Выберите канбан, чтобы открыть холст документа.',
                        ),
                      ),
                  ],
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          if (board case final current?)
            SliverFillRemaining(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: DocumentCanvasEditor(
                  key: ValueKey(current.id),
                  board: current,
                  enabled: !saving,
                  onChanged: () => _change(() {}),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _prepare(DocumentLayoutBoard current) {
    for (final category in current.categories) {
      category.codes ??= category.fields
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
          .map((f) => f.code)
          .toList();
    }
    current.template ??= DocumentTemplate(
      blocks: [
        DocumentBlock(
          id: 'executor',
          kind: 'executor',
          x: 30,
          y: 30,
          width: 350,
        ),
        DocumentBlock(id: 'client', kind: 'client', x: 400, y: 30, width: 364),
        DocumentBlock(
          id: 'table',
          kind: 'table',
          x: 30,
          y: 200,
          width: 734,
          height: 380,
        ),
        DocumentBlock(id: 'totals', kind: 'totals', x: 414, y: 600, width: 350),
      ],
    );
  }
}
