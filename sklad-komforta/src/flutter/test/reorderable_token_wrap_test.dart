import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/core/widgets/reorderable_token_wrap.dart';

void main() {
  testWidgets('компонент не переносится в чужую формулу', (tester) async {
    var changes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ReorderableTokenWrap(
                onReorder: (_, _) => changes++,
                children: const [
                  SizedBox(
                    width: 100,
                    height: 48,
                    child: Text('Первое выражение'),
                  ),
                ],
              ),
              const SizedBox(height: 40),
              ReorderableTokenWrap(
                onReorder: (_, _) => changes++,
                children: const [
                  SizedBox(
                    width: 100,
                    height: 48,
                    child: Text('Второе выражение'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    final start = tester.getCenter(find.text('Первое выражение'));
    final end = tester.getCenter(find.text('Второе выражение'));
    await tester.dragFrom(start, end - start);
    await tester.pumpAndSettle();
    expect(changes, 0);
    expect(tester.takeException(), isNull);
  });
  for (final width in [320.0, 375.0, 1024.0]) {
    testWidgets(
      'вся длинная формула видна без горизонтального обрезания $width',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 812));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(12),
                child: ReorderableTokenWrap(
                  onReorder: (_, _) {},
                  children: [
                    for (var i = 0; i < 12; i++)
                      Container(
                        key: ValueKey(i),
                        padding: const EdgeInsets.all(8),
                        child: Text('Поле $i'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        for (var i = 0; i < 12; i++) {
          final rect = tester.getRect(find.byKey(ValueKey(i)));
          expect(rect.left, greaterThanOrEqualTo(12));
          expect(rect.right, lessThanOrEqualTo(width - 12));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
