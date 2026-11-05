import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'document_field_picker.dart';
import 'document_layout_models.dart';
import 'document_template.dart';

class DocumentCanvasEditor extends StatefulWidget {
  const DocumentCanvasEditor({
    required this.board,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });
  final DocumentLayoutBoard board;
  final VoidCallback onChanged;
  final bool enabled;
  @override
  State<DocumentCanvasEditor> createState() => _DocumentCanvasEditorState();
}

class _DocumentCanvasEditorState extends State<DocumentCanvasEditor> {
  final transform = TransformationController(
    Matrix4.diagonal3Values(.65, .65, 1),
  );
  String? selectedId;
  Offset? touchOrigin;
  Size? resizeOrigin;
  DocumentTemplate get template => widget.board.template!;
  DocumentBlock? get selected =>
      template.blocks.where((b) => b.id == selectedId).firstOrNull;
  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }

  void change(VoidCallback action) {
    if (!widget.enabled) return;
    setState(action);
    widget.onChanged();
  }

  void add(String kind) => change(() {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final wide = kind == 'table' || kind == 'totals';
    final y = template.blocks.fold<double>(
      template.margin,
      (value, block) => math.max(value, block.y + block.height + 16),
    );
    template.blocks.add(
      DocumentBlock(
        id: id,
        kind: kind,
        x: template.margin,
        y: y.clamp(template.margin, template.height - template.margin - 150),
        width: wide ? template.width - template.margin * 2 : 320,
        fontSize: template.fontSize,
      ),
    );
    selectedId = id;
  });

  void constrain(DocumentBlock block) {
    block.width = block.width.clamp(100, template.width - template.margin * 2);
    block.height = block.height.clamp(
      60,
      template.height - template.margin * 2,
    );
    block.x = block.x.clamp(
      template.margin,
      template.width - template.margin - block.width,
    );
    block.y = block.y.clamp(
      template.margin,
      template.height - template.margin - block.height,
    );
  }

  @override
  Widget build(BuildContext context) => AbsorbPointer(
    absorbing: !widget.enabled,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final left = panel(
          'Компоненты',
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final entry in documentBlockNames.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton.icon(
                    onPressed: template.blocks.any((b) => b.kind == entry.key)
                        ? null
                        : () => add(entry.key),
                    icon: Icon(switch (entry.key) {
                      'executor' => Icons.business_outlined,
                      'client' => Icons.person_outline,
                      'table' => Icons.table_chart_outlined,
                      _ => Icons.summarize_outlined,
                    }),
                    label: Text(entry.value),
                  ),
                ),
              const SizedBox(height: 12),
              const Text(
                'Перетаскивайте блок за его область. Нижний правый угол меняет размер. '
                'На сенсорном экране удерживайте блок перед переносом. '
                'На холсте показаны образцы, а не данные клиента.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              const Text(
                'Высота таблицы на холсте условная. Все строки документа выводятся при печати, '
                'длинные таблицы продолжаются на следующих страницах.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        );
        final right = panel(
          selected == null ? 'Настройки холста' : 'Свойства блока',
          properties(),
        );
        final center = panel(
          'Холст документа',
          Column(
            children: [
              Wrap(
                children: [
                  IconButton(
                    tooltip: 'Уменьшить',
                    onPressed: () => zoom(.8),
                    icon: const Icon(Icons.zoom_out),
                  ),
                  IconButton(
                    tooltip: 'Увеличить',
                    onPressed: () => zoom(1.25),
                    icon: const Icon(Icons.zoom_in),
                  ),
                  TextButton(
                    onPressed: () => setState(() => selectedId = null),
                    child: const Text('Параметры страницы'),
                  ),
                ],
              ),
              SizedBox(
                height: 650,
                child: ClipRect(
                  child: InteractiveViewer(
                    transformationController: transform,
                    constrained: false,
                    minScale: .25,
                    maxScale: 2,
                    boundaryMargin: const EdgeInsets.all(150),
                    child: GestureDetector(
                      onTap: () => setState(() => selectedId = null),
                      child: Container(
                        width: template.width,
                        height: template.height,
                        decoration: const BoxDecoration(color: Colors.white),
                        child: Stack(
                          children: [
                            Positioned(
                              left: template.margin,
                              right: template.margin,
                              top: template.margin,
                              bottom: template.margin,
                              child: IgnorePointer(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: const Color(0xFFD9DFE8),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            for (final block in template.blocks)
                              canvasBlock(block),
                            if (template.blocks.isEmpty)
                              const Center(
                                child: Text(
                                  'Добавьте компоненты слева',
                                  style: TextStyle(color: Colors.black54),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
        if (constraints.maxWidth < 1100) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [left, center, right],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 210, child: left),
            const SizedBox(width: 12),
            Expanded(child: center),
            const SizedBox(width: 12),
            SizedBox(width: 330, child: right),
          ],
        );
      },
    ),
  );

  void zoom(double factor) {
    final scale = (transform.value.getMaxScaleOnAxis() * factor).clamp(
      .25,
      2.0,
    );
    transform.value = Matrix4.diagonal3Values(scale, scale, 1);
  }

  Widget panel(String title, Widget child) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFF101B29),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFF2A3B50)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        child,
      ],
    ),
  );

  Widget canvasBlock(DocumentBlock block) => Positioned(
    left: block.x,
    top: block.y,
    width: block.width,
    height: block.height,
    child: GestureDetector(
      key: ValueKey('canvas-block-${block.kind}'),
      onTap: () => setState(() => selectedId = block.id),
      onPanStart: (_) => setState(() => selectedId = block.id),
      onLongPressStart: (_) => setState(() {
        selectedId = block.id;
        touchOrigin = Offset(block.x, block.y);
      }),
      onLongPressMoveUpdate: (details) => change(() {
        block.x = touchOrigin!.dx + details.localOffsetFromOrigin.dx;
        block.y = touchOrigin!.dy + details.localOffsetFromOrigin.dy;
        constrain(block);
      }),
      onPanUpdate: (details) => change(() {
        block.x += details.delta.dx;
        block.y += details.delta.dy;
        constrain(block);
      }),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
            color: selectedId == block.id
                ? const Color(0xFF4B88FF)
                : const Color(0xFFD9DFE8),
            width: selectedId == block.id ? 2 : 1,
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: ClipRect(
                child: Padding(
                  padding: EdgeInsets.all(block.padding),
                  child: DefaultTextStyle(
                    style: TextStyle(
                      color: const Color(0xFF172033),
                      fontSize: block.fontSize,
                      height: template.lineHeight,
                      fontFamily: template.fontFamily == 'serif'
                          ? 'Georgia'
                          : 'Roboto',
                    ),
                    child: SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: sample(block),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: GestureDetector(
                onLongPressStart: (_) =>
                    resizeOrigin = Size(block.width, block.height),
                onLongPressMoveUpdate: (details) => change(() {
                  block.width =
                      resizeOrigin!.width + details.localOffsetFromOrigin.dx;
                  block.height =
                      resizeOrigin!.height + details.localOffsetFromOrigin.dy;
                  constrain(block);
                }),
                onPanUpdate: (details) => change(() {
                  block.width += details.delta.dx;
                  block.height += details.delta.dy;
                  constrain(block);
                }),
                child: const MouseRegion(
                  cursor: SystemMouseCursors.resizeUpLeftDownRight,
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: Icon(
                      Icons.open_in_full,
                      size: 18,
                      color: Color(0xFF4B88FF),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget sample(DocumentBlock block) {
    final alignment = switch (block.align) {
      'center' => CrossAxisAlignment.center,
      'right' => CrossAxisAlignment.end,
      _ => CrossAxisAlignment.start,
    };
    if (block.kind == 'table') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final category in widget.board.categories) ...[
            Text(
              category.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if ((category.codes ?? []).isNotEmpty)
              Table(
                border: TableBorder.all(color: const Color(0xFFD9DFE8)),
                columnWidths: {
                  for (var i = 0; i < category.codes!.length; i++)
                    i: FlexColumnWidth(
                      block.columnWidths['${category.id}/${category.codes![i]}'] ??
                          1,
                    ),
                },
                children: [
                  TableRow(
                    children: [
                      for (final code in category.codes!)
                        Padding(
                          padding: const EdgeInsets.all(4),
                          child: Text(
                            category.fields
                                .firstWhere((f) => f.code == code)
                                .label,
                          ),
                        ),
                    ],
                  ),
                  TableRow(
                    children: [
                      for (final _ in category.codes!)
                        const Padding(
                          padding: EdgeInsets.all(4),
                          child: Text('…'),
                        ),
                    ],
                  ),
                ],
              ),
            const SizedBox(height: 8),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: alignment,
      children: [
        Text(
          documentBlockNames[block.kind]!,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (block.kind == 'totals') ...[
          const Text('НДС: …'),
          const Text('Сумма без НДС: …'),
          const Text('Итого для клиента: …'),
        ] else
          for (final code in block.fields)
            Text(
              '${documentPartyFields.firstWhere((f) => f.code == code).label}: …',
            ),
      ],
    );
  }

  Widget number(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> apply,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: _NumberInput(
      key: ValueKey('$selectedId/$label'),
      label: label,
      value: value,
      min: min,
      max: max,
      onChanged: (v) => change(() => apply(v)),
    ),
  );

  Widget properties() {
    final block = selected;
    if (block == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<bool>(
            initialValue: template.landscape,
            decoration: const InputDecoration(labelText: 'Формат листа'),
            items: const [
              DropdownMenuItem(value: false, child: Text('A4, книжный')),
              DropdownMenuItem(value: true, child: Text('A4, альбомный')),
            ],
            onChanged: (value) => change(() {
              template.landscape = value!;
              for (final b in template.blocks) {
                constrain(b);
              }
            }),
          ),
          const SizedBox(height: 12),
          number('Отступы страницы, px', template.margin, 0, 100, (v) {
            template.margin = v;
            for (final b in template.blocks) {
              constrain(b);
            }
          }),
          DropdownButtonFormField<String>(
            initialValue: template.fontFamily,
            decoration: const InputDecoration(labelText: 'Шрифт'),
            items: const [
              DropdownMenuItem(value: 'sans', child: Text('Без засечек')),
              DropdownMenuItem(value: 'serif', child: Text('С засечками')),
            ],
            onChanged: (v) => change(() => template.fontFamily = v!),
          ),
          const SizedBox(height: 12),
          number('Размер шрифта, px', template.fontSize, 8, 36, (v) {
            template.fontSize = v;
            for (final b in template.blocks) {
              b.fontSize = v;
            }
          }),
          number(
            'Межстрочный интервал',
            template.lineHeight,
            1,
            2,
            (v) => template.lineHeight = v,
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(documentBlockNames[block.kind]!),
        const SizedBox(height: 12),
        number('Слева, px', block.x, template.margin, template.width, (v) {
          block.x = v;
          constrain(block);
        }),
        number('Сверху, px', block.y, template.margin, template.height, (v) {
          block.y = v;
          constrain(block);
        }),
        number('Ширина, px', block.width, 100, template.width, (v) {
          block.width = v;
          constrain(block);
        }),
        number('Высота, px', block.height, 60, template.height, (v) {
          block.height = v;
          constrain(block);
        }),
        number(
          'Внутренний отступ, px',
          block.padding,
          0,
          24,
          (v) => block.padding = v,
        ),
        number(
          'Размер шрифта блока, px',
          block.fontSize,
          8,
          36,
          (v) => block.fontSize = v,
        ),
        DropdownButtonFormField<String>(
          key: ValueKey(block.id),
          initialValue: block.align,
          decoration: const InputDecoration(labelText: 'Выравнивание'),
          items: const [
            DropdownMenuItem(value: 'left', child: Text('Слева')),
            DropdownMenuItem(value: 'center', child: Text('По центру')),
            DropdownMenuItem(value: 'right', child: Text('Справа')),
          ],
          onChanged: (v) => change(() => block.align = v!),
        ),
        const SizedBox(height: 12),
        if (block.kind == 'executor' || block.kind == 'client')
          DocumentFieldPicker(
            fields: documentPartyFieldsFor(block.kind),
            codes: block.fields,
            onChanged: (codes) => change(() => block.fields = codes),
          ),
        if (block.kind == 'table')
          for (final category in widget.board.categories)
            ExpansionTile(
              title: Text(category.name),
              children: [
                DocumentFieldPicker(
                  fields: category.fields,
                  codes: category.codes ?? [],
                  onChanged: (codes) => change(() => category.codes = codes),
                ),
                for (final code in category.codes ?? <String>[])
                  number(
                    'Ширина: ${category.fields.firstWhere((f) => f.code == code).label}',
                    block.columnWidths['${category.id}/$code'] ?? 1,
                    .2,
                    20,
                    (v) => block.columnWidths['${category.id}/$code'] = v,
                  ),
                const Text('Ширины колонок относительные: 2 вдвое шире 1.'),
              ],
            ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => change(() {
            template.blocks.remove(block);
            selectedId = null;
          }),
          icon: const Icon(Icons.delete_outline),
          label: const Text('Удалить блок'),
        ),
      ],
    );
  }
}

class _NumberInput extends StatefulWidget {
  const _NumberInput({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    super.key,
  });
  final String label;
  final double value, min, max;
  final ValueChanged<double> onChanged;
  @override
  State<_NumberInput> createState() => _NumberInputState();
}

class _NumberInputState extends State<_NumberInput> {
  late final controller = TextEditingController(
    text: widget.value.toStringAsFixed(2),
  );
  final focus = FocusNode();
  @override
  void didUpdateWidget(_NumberInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!focus.hasFocus && oldWidget.value != widget.value) {
      controller.text = widget.value.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    focusNode: focus,
    decoration: InputDecoration(labelText: widget.label),
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    validator: (text) {
      final value = double.tryParse((text ?? '').replaceAll(',', '.'));
      return value == null ||
              !value.isFinite ||
              value < widget.min ||
              value > widget.max
          ? 'От ${widget.min} до ${widget.max}'
          : null;
    },
    onChanged: (text) {
      final value = double.tryParse(text.replaceAll(',', '.'));
      if (value != null &&
          value.isFinite &&
          value >= widget.min &&
          value <= widget.max) {
        widget.onChanged(value);
      }
    },
    onTapOutside: (_) => focus.unfocus(),
  );
}
