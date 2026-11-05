import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:sklad_komforta_app/core/widgets/app_select_field.dart';
import 'package:flutter/gestures.dart';
import 'document_field_picker.dart';
import 'document_layout_models.dart';
import 'document_template.dart';
import 'document_paper_surface.dart';
import 'document_party_rows.dart';

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
  double zoomFactor = 1.25;
  final propertiesScroll = ScrollController();
  final paperScroll = ScrollController();
  @override
  void dispose() {
    propertiesScroll.dispose();
    paperScroll.dispose();
    super.dispose();
  }

  String? selectedId;
  Offset? touchOrigin;
  Size? resizeOrigin;
  DocumentTemplate get template => widget.board.template!;
  DocumentBlock? get selected =>
      template.blocks.where((b) => b.id == selectedId).firstOrNull;

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
        final desktop = constraints.maxWidth >= 1200;
        final bounded = desktop && constraints.hasBoundedHeight;
        final panelHeight = bounded
            ? constraints.maxHeight
            : math.max(260.0, MediaQuery.sizeOf(context).height - 180);
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
                'Ширина столбцов меняется перетаскиванием синих границ таблицы. '
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
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: math.max(120, panelHeight - 80),
            ),
            child: Listener(
              onPointerSignal: containScroll,
              child: Scrollbar(
                controller: propertiesScroll,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  key: const ValueKey('document-properties-scroll'),
                  controller: propertiesScroll,
                  primary: false,
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: ClampingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.only(right: 12),
                  child: properties(),
                ),
              ),
            ),
          ),
        );
        final center = panel(
          'Холст документа',
          Column(
            children: [
              paperViewport(
                bounded,
                DocumentPaperSurface(
                  width: template.width,
                  height: template.height,
                  fitWidth: true,
                  zoom: zoomFactor,
                  child: GestureDetector(
                    onTap: () => setState(() => selectedId = null),
                    child: Container(
                      key: const ValueKey('document-editor-paper'),
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
            ],
          ),
          expand: bounded,
          actions: [
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
            if (constraints.maxWidth >= 500)
              TextButton(
                onPressed: () => setState(() => selectedId = null),
                child: const Text('Параметры страницы'),
              )
            else
              IconButton(
                tooltip: 'Параметры страницы',
                onPressed: () => setState(() => selectedId = null),
                icon: const Icon(Icons.tune),
              ),
          ],
        );
        if (!desktop) {
          final stacked = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [left, center, right],
          );
          return constraints.hasBoundedHeight
              ? SingleChildScrollView(primary: false, child: stacked)
              : stacked;
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 210,
              height: bounded ? panelHeight : null,
              child: bounded
                  ? SingleChildScrollView(primary: false, child: left)
                  : left,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: bounded
                  ? SizedBox(height: panelHeight, child: center)
                  : center,
            ),
            const SizedBox(width: 12),
            SizedBox(width: 330, child: right),
          ],
        );
      },
    ),
  );

  void zoom(double factor) {
    setState(() => zoomFactor = (zoomFactor * factor).clamp(.25, 2.0));
  }

  Widget paperViewport(bool bounded, Widget paper) {
    final viewport = Listener(
      onPointerSignal: containScroll,
      child: Scrollbar(
        controller: paperScroll,
        thumbVisibility: true,
        child: SingleChildScrollView(
          key: const ValueKey('document-paper-scroll'),
          controller: paperScroll,
          primary: false,
          physics: const AlwaysScrollableScrollPhysics(
            parent: ClampingScrollPhysics(),
          ),
          child: paper,
        ),
      ),
    );
    return bounded
        ? Expanded(child: viewport)
        : SizedBox(
            height: MediaQuery.sizeOf(context).height * .7,
            child: viewport,
          );
  }

  void containScroll(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      // The inner scrollable gets first refusal. At its edges, consume the
      // wheel rather than letting an ancestor scroll the whole page.
      GestureBinding.instance.pointerSignalResolver.register(event, (_) {});
    }
  }

  Widget panel(
    String title,
    Widget child, {
    bool expand = false,
    List<Widget> actions = const [],
  }) => Container(
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
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            ...actions,
          ],
        ),
        SizedBox(height: actions.isEmpty ? 14 : 8),
        if (expand) Expanded(child: child) else child,
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
          for (final category in orderedCategories(block)) ...[
            Text(
              category.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if ((category.codes ?? []).isNotEmpty)
              LayoutBuilder(
                builder: (context, constraints) {
                  final codes = category.codes!;
                  final weights = [
                    for (final code in codes)
                      block.columnWidths['${category.id}/$code'] ?? 1.0,
                  ];
                  final total = weights.fold<double>(0, (sum, w) => sum + w);
                  return Stack(
                    children: [
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
                      for (var i = 0; i < codes.length - 1; i++)
                        Positioned(
                          left:
                              constraints.maxWidth *
                                  weights
                                      .take(i + 1)
                                      .fold<double>(0, (sum, w) => sum + w) /
                                  total -
                              6,
                          top: 0,
                          bottom: 0,
                          width: 12,
                          child: MouseRegion(
                            cursor: SystemMouseCursors.resizeColumn,
                            child: Tooltip(
                              message: 'Перетащите границу столбца',
                              child: GestureDetector(
                                key: ValueKey(
                                  'column-resize-${category.id}-$i',
                                ),
                                behavior: HitTestBehavior.opaque,
                                onHorizontalDragStart: (_) =>
                                    setState(() => selectedId = block.id),
                                onHorizontalDragUpdate: (details) => change(() {
                                  final first = '${category.id}/${codes[i]}';
                                  final second =
                                      '${category.id}/${codes[i + 1]}';
                                  final a = block.columnWidths[first] ?? 1.0;
                                  final b = block.columnWidths[second] ?? 1.0;
                                  final delta =
                                      (details.delta.dx *
                                              total /
                                              constraints.maxWidth)
                                          .clamp(
                                            math.max(.2 - a, b - 20),
                                            math.min(20 - a, b - .2),
                                          );
                                  block.columnWidths[first] = a + delta;
                                  block.columnWidths[second] = b - delta;
                                }),
                                child: Center(
                                  child: Container(
                                    width: 2,
                                    color: const Color(0xFF4B88FF),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
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
          LayoutBuilder(
            builder: (context, constraints) {
              final rows = documentPartyRows([
                for (final code in block.fields)
                  '${documentPartyFields.firstWhere((f) => f.code == code).label}: …',
              ], block.effectiveFieldColumns);
              return Column(
                children: [
                  for (final row in rows)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < row.cells.length; i++)
                          Expanded(
                            flex: (row.widths[i] * 100).round(),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Text(
                                row.cells[i],
                                textAlign: switch (block.align) {
                                  'right' => TextAlign.right,
                                  'center' => TextAlign.center,
                                  _ => TextAlign.left,
                                },
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
              );
            },
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
          AppSelectField<bool>(
            value: template.landscape,
            label: 'Формат листа',
            options: const [
              AppSelectOption(value: false, label: 'A4, книжный'),
              AppSelectOption(value: true, label: 'A4, альбомный'),
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
          AppSelectField<String>(
            value: template.fontFamily,
            label: 'Шрифт',
            options: const [
              AppSelectOption(value: 'sans', label: 'Без засечек'),
              AppSelectOption(value: 'serif', label: 'С засечками'),
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
        AppSelectField<String>(
          key: ValueKey(block.id),
          value: block.align,
          label: 'Выравнивание',
          options: const [
            AppSelectOption(value: 'left', label: 'Слева'),
            AppSelectOption(value: 'center', label: 'По центру'),
            AppSelectOption(value: 'right', label: 'Справа'),
          ],
          onChanged: (v) => change(() => block.align = v!),
        ),
        const SizedBox(height: 12),
        if (block.kind == 'executor' || block.kind == 'client') ...[
          _NumberInput(
            key: ValueKey('party-columns-${block.id}'),
            value: block.effectiveFieldColumns.toDouble(),
            label: 'Количество столбцов',
            min: 1,
            max: documentPartyFields.length.toDouble(),
            integerOnly: true,
            onChanged: (value) {
              change(() => block.fieldColumns = value.toInt());
            },
          ),
          DocumentFieldPicker(
            fields: documentPartyFieldsFor(block.kind),
            codes: block.fields,
            onChanged: (codes) => change(() => block.fields = codes),
          ),
        ],
        if (block.kind == 'table' && widget.board.categories.length > 1) ...[
          const Text('Порядок категорий'),
          DocumentFieldPicker(
            key: const ValueKey('document-category-order'),
            showSelection: false,
            fields: [
              for (final category in widget.board.categories)
                DocumentLayoutField(category.id, category.name),
            ],
            codes: orderedCategories(block).map((c) => c.id).toList(),
            onChanged: (codes) => change(() => block.categoryOrder = codes),
          ),
        ],
        if (block.kind == 'table')
          for (final category in orderedCategories(block))
            ExpansionTile(
              key: ValueKey('category-fields-${category.id}'),
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

  List<DocumentLayoutCategory> orderedCategories(DocumentBlock block) {
    final indexed = widget.board.categories.indexed.toList()
      ..sort((a, b) {
        final rank = block
            .categoryRank(a.$2.id)
            .compareTo(block.categoryRank(b.$2.id));
        return rank == 0 ? a.$1.compareTo(b.$1) : rank;
      });
    return indexed.map((entry) => entry.$2).toList();
  }
}

class _NumberInput extends StatefulWidget {
  const _NumberInput({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.integerOnly = false,
    super.key,
  });
  final String label;
  final double value, min, max;
  final ValueChanged<double> onChanged;
  final bool integerOnly;
  @override
  State<_NumberInput> createState() => _NumberInputState();
}

class _NumberInputState extends State<_NumberInput> {
  late final controller = TextEditingController(
    text: widget.value.toStringAsFixed(widget.integerOnly ? 0 : 2),
  );
  final focus = FocusNode();
  @override
  void didUpdateWidget(_NumberInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!focus.hasFocus && oldWidget.value != widget.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || focus.hasFocus) return;
        final text = widget.value.toStringAsFixed(widget.integerOnly ? 0 : 2);
        if (controller.text != text) controller.text = text;
      });
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
    keyboardType: TextInputType.numberWithOptions(decimal: !widget.integerOnly),
    validator: (text) {
      final value = parse(text ?? '');
      return value == null ||
              !value.isFinite ||
              value < widget.min ||
              value > widget.max
          ? widget.integerOnly
                ? 'Целое число от ${widget.min.toInt()} до ${widget.max.toInt()}'
                : 'От ${widget.min} до ${widget.max}'
          : null;
    },
    onChanged: (text) {
      final value = parse(text);
      if (value != null &&
          value.isFinite &&
          value >= widget.min &&
          value <= widget.max) {
        widget.onChanged(value);
      }
    },
    onTapOutside: (_) => focus.unfocus(),
  );

  double? parse(String text) => widget.integerOnly
      ? int.tryParse(text.trim())?.toDouble()
      : double.tryParse(text.replaceAll(',', '.'));
}
