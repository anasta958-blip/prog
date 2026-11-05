import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:sklad_komforta_app/app/app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/features/company/document_canvas_editor.dart';
import 'package:sklad_komforta_app/features/company/document_canvas_view.dart';
import 'package:sklad_komforta_app/features/company/document_field_picker.dart';
import 'package:sklad_komforta_app/features/company/document_layout_models.dart';
import 'package:sklad_komforta_app/features/company/document_template.dart';
import 'package:sklad_komforta_app/features/company/document_paper_surface.dart';
import 'package:sklad_komforta_app/features/company/document_party_rows.dart';

void main() {
  test('party fields flow, wrap and preserve old templates', () {
    const lines = [
      'ИНН: 123',
      'КПП: 456',
      'Очень длинное поле с адресом объекта',
      'Телефон: 123',
    ];
    final rows = documentPartyRows(
      lines,
      240,
      const TextStyle(fontSize: 12),
      true,
    );
    expect(rows.first.cells.length, 2);
    expect(rows.expand((r) => r.cells), lines);
    expect(
      rows.every((r) => r.widths.fold<double>(0, (a, b) => a + b) <= 240),
      isTrue,
    );
    expect(
      documentPartyRows(lines, 240, const TextStyle(fontSize: 12), false),
      hasLength(4),
    );
    final block = DocumentBlock(
      id: 'table',
      kind: 'table',
      x: 30,
      y: 30,
      flowFields: true,
      categoryOrder: ['b', 'a'],
    );
    final restored = DocumentBlock.fromJson(block.toJson());
    expect(restored.flowFields, isTrue);
    expect(restored.categoryOrder, ['b', 'a']);
    expect(restored.categoryRank('new'), 2);
    final old = block.toJson()
      ..remove('flowFields')
      ..remove('categoryOrder');
    expect(DocumentBlock.fromJson(old).flowFields, isFalse);
    expect(DocumentBlock.fromJson(old).categoryOrder, isEmpty);
  });
  setUpAll(() async {
    const fontPath = String.fromEnvironment('DOCUMENT_FONT_PATH');
    const iconsPath = String.fromEnvironment('DOCUMENT_ICONS_PATH');
    if (fontPath.isNotEmpty) {
      final font = FontLoader('Roboto')
        ..addFont(File(fontPath).readAsBytes().then(ByteData.sublistView));
      await font.load();
    }
    if (iconsPath.isNotEmpty) {
      final font = FontLoader('MaterialIcons')
        ..addFont(File(iconsPath).readAsBytes().then(ByteData.sublistView));
      await font.load();
    }
  });
  testWidgets('selected document fields reorder by dragging', (tester) async {
    var codes = ['name', 'quantity'];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => DocumentFieldPicker(
              fields: const [
                DocumentLayoutField('name', 'Название'),
                DocumentLayoutField('quantity', 'Количество'),
                DocumentLayoutField('secret', 'Скрытое'),
              ],
              codes: codes,
              onChanged: (value) => setState(() => codes = value),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      SliverReorderableList.maybeOf(
        tester.element(find.byType(ReorderableDragStartListener).at(1)),
      ),
      isNotNull,
    );
    expect(
      tester
          .widget<ReorderableDragStartListener>(
            find.byType(ReorderableDragStartListener).at(1),
          )
          .enabled,
      isTrue,
    );
    final reorder = await tester.startGesture(
      tester.getCenter(find.byType(ReorderableDragStartListener).at(1)),
      kind: ui.PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 100));
    await reorder.moveBy(const Offset(0, -20));
    await tester.pump(const Duration(milliseconds: 300));
    await reorder.moveBy(const Offset(0, -80));
    await tester.pump(const Duration(milliseconds: 300));
    await reorder.moveBy(const Offset(0, -60));
    await tester.pump(const Duration(milliseconds: 300));
    await reorder.up();
    await tester.pumpAndSettle();
    expect(codes, ['quantity', 'name']);
    expect(codes, isNot(contains('secret')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('canvas moves blocks and works on desktop and narrow screens', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 1000);
    addTearDown(tester.view.reset);
    final block = DocumentBlock(
      id: 'executor',
      kind: 'executor',
      x: 30,
      y: 30,
      width: 320,
    );
    final board = DocumentLayoutBoard(
      'board',
      'Канбан КП',
      'quote',
      [
        DocumentLayoutCategory(
          'category',
          'Оборудование',
          const [
            DocumentLayoutField('name', 'Наименование'),
            DocumentLayoutField('quantity', 'Количество'),
          ],
          ['name', 'quantity'],
        ),
        DocumentLayoutCategory('other', 'Дополнительно', const [], []),
      ],
      template: DocumentTemplate(
        blocks: [
          block,
          DocumentBlock(
            id: 'table',
            kind: 'table',
            x: 30,
            y: 250,
            width: 734,
            height: 250,
          ),
        ],
      ),
    );
    var changes = 0;
    final capture = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme().copyWith(
          textTheme: buildAppTheme().textTheme.apply(fontFamily: 'Roboto'),
        ),
        home: Scaffold(
          body: RepaintBoundary(
            key: capture,
            child: SingleChildScrollView(
              child: DocumentCanvasEditor(
                board: board,
                onChanged: () => changes++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final paper = find.byKey(const ValueKey('document-editor-paper'));
    final surface = tester.getRect(paper);
    expect(surface.width, closeTo(board.template!.width, .01));
    expect(
      surface.center.dx,
      closeTo(tester.getRect(find.byType(DocumentPaperSurface)).center.dx, .01),
    );
    final tableBlock = board.template!.blocks.last;
    final tableOrigin = Offset(tableBlock.x, tableBlock.y);
    final divider = find.byKey(const ValueKey('column-resize-category-0'));
    final columnDrag = await tester.startGesture(
      tester.getCenter(divider),
      kind: ui.PointerDeviceKind.mouse,
    );
    await columnDrag.moveBy(const Offset(20, 0));
    await tester.pump();
    await columnDrag.moveBy(const Offset(60, 0));
    await tester.pump();
    await columnDrag.up();
    await tester.pumpAndSettle();
    expect(tableBlock.columnWidths['category/name'], greaterThan(1));
    expect(tableBlock.columnWidths['category/quantity'], lessThan(1));
    expect(Offset(tableBlock.x, tableBlock.y), tableOrigin);
    expect(
      DocumentTemplate.fromJson(
        board.template!.toJson(),
      ).blocks.last.columnWidths,
      tableBlock.columnWidths,
    );
    final categoryPicker = find.byKey(
      const ValueKey('document-category-order'),
    );
    tester
        .widget<IconButton>(
          find
              .descendant(
                of: categoryPicker,
                matching: find.byWidgetPredicate(
                  (w) => w is IconButton && w.tooltip == 'Переместить ниже',
                ),
              )
              .first,
        )
        .onPressed!();
    await tester.pumpAndSettle();
    expect(tableBlock.categoryOrder, ['other', 'category']);
    final canvasTable = find.byKey(const ValueKey('canvas-block-table'));
    expect(
      tester
          .getTopLeft(
            find.descendant(
              of: canvasTable,
              matching: find.text('Дополнительно'),
            ),
          )
          .dy,
      lessThan(
        tester
            .getTopLeft(
              find.descendant(
                of: canvasTable,
                matching: find.text('Оборудование'),
              ),
            )
            .dy,
      ),
    );
    final start = block.y;
    final drag = await tester.startGesture(
      tester.getTopLeft(find.byKey(const ValueKey('canvas-block-executor'))) +
          const Offset(10, 10),
      kind: ui.PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 100));
    await drag.moveBy(const Offset(20, 20));
    await tester.pump();
    await drag.moveBy(const Offset(50, 40));
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();
    expect(block.y, greaterThan(start));
    expect(changes, greaterThan(0));
    tester
        .widget<SwitchListTile>(
          find.widgetWithText(SwitchListTile, 'Заполнять по ширине'),
        )
        .onChanged!(true);
    await tester.pumpAndSettle();
    expect(block.flowFields, isTrue);
    expect(tester.takeException(), isNull);
    final touchStart = block.y;
    final touch = await tester.startGesture(
      tester.getTopLeft(find.byKey(const ValueKey('canvas-block-executor'))) +
          const Offset(12, 12),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await touch.moveBy(const Offset(0, 40));
    await tester.pump();
    await touch.up();
    await tester.pumpAndSettle();
    expect(block.y, greaterThan(touchStart));
    final beforeScroll = tester.getRect(paper);
    tester.binding.handlePointerEvent(
      PointerScrollEvent(
        position: Offset(beforeScroll.right - 10, 400),
        scrollDelta: const Offset(0, 180),
      ),
    );
    await tester.pumpAndSettle();
    final afterScroll = tester.getRect(paper);
    expect(afterScroll.size, beforeScroll.size);
    expect(afterScroll.top, lessThan(beforeScroll.top));
    // Restore the top before capturing the editor and changing screen width.
    tester.binding.handlePointerEvent(
      PointerScrollEvent(
        position: Offset(afterScroll.right - 10, 400),
        scrollDelta: const Offset(0, -1000),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Увеличить'));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(paper).height,
      closeTo(beforeScroll.height * 1.25, .01),
    );
    await tester.tap(find.byTooltip('Уменьшить'));
    await tester.pumpAndSettle();
    if (const bool.fromEnvironment('DOCUMENT_CANVAS_CAPTURE')) {
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '${Directory.systemTemp.path}/sklad-canvas-editor.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    final pageScroll = ScrollController();
    addTearDown(pageScroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            controller: pageScroll,
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 300)),
              SliverFillRemaining(
                child: DocumentCanvasEditor(
                  board: board,
                  onChanged: () => changes++,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    pageScroll.jumpTo(pageScroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(paper).dy, lessThan(150));
    await tester.tap(find.byKey(const ValueKey('canvas-block-executor')));
    await tester.pumpAndSettle();
    final props = find.byKey(const ValueKey('document-properties-scroll'));
    final propsWidget = tester.widget<SingleChildScrollView>(props);
    final fixedPaper = tester.getRect(paper);
    final pageOffset = pageScroll.offset;
    tester.binding.handlePointerEvent(
      PointerScrollEvent(
        position: tester.getCenter(props),
        scrollDelta: const Offset(0, 220),
      ),
    );
    await tester.pumpAndSettle();
    expect(propsWidget.controller!.offset, greaterThan(0));
    expect(pageScroll.offset, pageOffset);
    expect(tester.getRect(paper), fixedPaper);
    final paperViewport = find.byKey(const ValueKey('document-paper-scroll'));
    tester.binding.handlePointerEvent(
      PointerScrollEvent(
        position: tester.getCenter(paperViewport),
        scrollDelta: const Offset(0, 160),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<SingleChildScrollView>(paperViewport).controller!.offset,
      greaterThan(0),
    );
    expect(pageScroll.offset, pageOffset);
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(360, 900);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('long document tables expand and shift following totals', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 1000);
    addTearDown(tester.view.reset);
    final template = DocumentTemplate(
      blocks: [
        DocumentBlock(
          id: 'table',
          kind: 'table',
          x: 30,
          y: 30,
          width: 734,
          height: 100,
        ),
        DocumentBlock(id: 'totals', kind: 'totals', x: 30, y: 150, width: 734),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DocumentCanvasView(
              document: {
                'template': template.toJson(),
                'blocks': [
                  {
                    'id': 'table',
                    'title': '',
                    'lines': <String>[],
                    'tables': [
                      {
                        'title': 'Оборудование',
                        'columns': ['Наименование'],
                        'widths': [1],
                        'rows': List.generate(80, (i) => ['Позиция $i']),
                      },
                    ],
                  },
                  {
                    'id': 'totals',
                    'title': 'Итоги',
                    'lines': ['Итого: 800 ₽'],
                    'tables': [],
                  },
                ],
              },
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getTopLeft(find.text('Итого: 800 ₽')).dy,
      greaterThan(tester.getBottomLeft(find.text('Позиция 79')).dy),
    );
    expect(
      tester
          .getRect(find.byKey(const ValueKey('document-preview-paper')))
          .center
          .dx,
      closeTo(800, .01),
    );
    expect(tester.takeException(), isNull);
  });
}
