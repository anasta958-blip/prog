import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/features/company/company_audit.dart';
import 'package:sklad_komforta_app/features/company/company_models.dart';

CompanyAuditEntryModel entry(Object? before, Object? after, {int id = 1}) =>
    CompanyAuditEntryModel(
      id: id,
      entityType: 'catalog_item',
      action: 'updated',
      actorName: 'Иван Иванов',
      createdAt: DateTime(2026, 9, 20, 12, 30),
      diff: {'before': before, 'after': after},
    );

void main() {
  testWidgets('short changes have no redundant expand button', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompanyAuditCard(
            entry: entry({'name': 'Было'}, {'name': 'Стало'}),
          ),
        ),
      ),
    );
    expect(find.byType(TextButton), findsNothing);
  });
  testWidgets('a truncated value can be expanded even for one change', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 320,
              child: CompanyAuditCard(
                entry: entry(
                  {'note': 'Коротко'},
                  {'note': List.filled(80, 'Подробности').join(' ')},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Все подробности (1)'), findsOneWidget);
    await tester.tap(find.text('Все подробности (1)'));
    await tester.pump();
    expect(find.text('Свернуть'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final width in [390.0, 1200.0, 1440.0, 1920.0]) {
    testWidgets('audit list uses available width $width', (tester) async {
      tester.view.physicalSize = Size(width, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CompanyAuditList(
              entries: [
                for (var id = 1; id <= 3; id++)
                  entry(
                    {'name': 'Было'},
                    {
                      'name': id == 1
                          ? List.filled(30, 'Название').join(' ')
                          : 'Стало',
                      if (id == 2) 'marking': 'Дополнительное изменение',
                    },
                    id: id,
                  ),
              ],
            ),
          ),
        ),
      );
      final first = tester.getRect(find.byKey(const ValueKey(1)));
      final second = tester.getRect(find.byKey(const ValueKey(2)));
      final third = tester.getRect(find.byKey(const ValueKey(3)));
      expect(first.height, second.height);
      expect(first.height, third.height);
      expect(first.height, lessThan(300));
      if (width >= 1000) {
        expect(first.top, second.top);
        expect(second.left, greaterThan(first.right));
        expect(third.width, closeTo(first.width, 0.01));
        if (width >= 1440) {
          expect(third.top, first.top);
          expect(third.left, greaterThan(second.right));
        } else {
          expect(third.top, greaterThan(first.bottom));
        }
      } else {
        expect(first.left, second.left);
        expect(second.top, greaterThan(first.bottom));
      }
      expect(tester.takeException(), isNull);
    });
  }
  test('nested changes show only changed fields', () {
    final changes = auditChanges(
      entry(
        {
          'name': 'Товар',
          'values': {'base_price': 100, 'unit': 'шт'},
        },
        {
          'name': 'Товар',
          'values': {'base_price': 120, 'unit': 'шт'},
        },
      ),
    );
    expect(changes, hasLength(1));
    expect(changes.single.field, 'Поля / Цена');
    expect(changes.single.before, '100');
    expect(changes.single.after, '120');
  });
  test('configuration matches named objects and preserves deletions', () {
    final changes = auditChanges(
      entry(
        {
          'categories': [
            {'clientId': 'a', 'name': 'Оборудование'},
            {'clientId': 'b', 'name': 'Работы'},
          ],
        },
        {
          'categories': [
            {'clientId': 'a', 'name': 'Новое название'},
          ],
        },
      ),
    );
    expect(changes, hasLength(2));
    expect(changes.first.before, 'Оборудование');
    expect(changes.first.after, 'Новое название');
    expect(changes.last.after, 'Удалено');
  });
  test(
    'technical timestamps do not appear but dynamic fields are retained',
    () {
      expect(
        auditChanges(entry({'updatedAt': 'old'}, {'updatedAt': 'new'})),
        isEmpty,
      );
      expect(
        auditChanges(
          entry(
            {
              'values': {'updatedAt': 'old'},
            },
            {
              'values': {'updatedAt': 'new'},
            },
          ),
        ),
        hasLength(1),
      );
    },
  );
  for (final width in [390.0, 1000.0]) {
    testWidgets('audit summary and details fit width $width', (tester) async {
      tester.view.resetPhysicalSize();
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CompanyAuditCard(
                entry: entry(
                  {
                    'name': 'Товар',
                    'marking': 'A',
                    'status': 'draft',
                    'values': {'base_price': 100},
                  },
                  {
                    'name': 'Новый товар',
                    'marking': 'B',
                    'status': 'approved',
                    'values': {'base_price': 120},
                  },
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Кто: Иван Иванов'), findsOneWidget);
      expect(find.text('Когда: 20.09.2026 12:30'), findsOneWidget);
      expect(find.text('Поля / Цена'), findsNothing);
      expect(find.text('Маркировка'), findsNothing);
      await tester.tap(find.text('Все подробности (4)'));
      await tester.pump();
      expect(find.text('Поля / Цена'), findsOneWidget);
      expect(find.text('Маркировка'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
