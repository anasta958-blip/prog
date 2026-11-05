import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:sklad_komforta_app/app/app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/features/company/document_canvas_editor.dart';
import 'package:sklad_komforta_app/features/company/document_canvas_view.dart';
import 'package:sklad_komforta_app/features/company/document_field_picker.dart';
import 'package:sklad_komforta_app/features/company/document_layout_models.dart';
import 'package:sklad_komforta_app/features/company/document_template.dart';

void main() {
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
          const [DocumentLayoutField('name', 'Наименование')],
          ['name'],
        ),
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
    tester.view.physicalSize = const Size(360, 900);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('long document tables expand and shift following totals', (
    tester,
  ) async {
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
    expect(tester.takeException(), isNull);
  });
}
