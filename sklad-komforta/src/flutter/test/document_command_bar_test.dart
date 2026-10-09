import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/core/widgets/document_command_bar.dart';

void main() {
  testWidgets('команды доступны без переполнений, вторичные действия в меню', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var backs = 0;
    var saves = 0;
    var previews = 0;
    for (final width in [
      320.0,
      375.0,
      600.0,
      800.0,
      899.0,
      900.0,
      1024.0,
      1440.0,
    ]) {
      tester.view.physicalSize = Size(width, 812);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                DocumentCommandBar(
                  title: 'Комплектация №123456',
                  shortTitle: '№123456',
                  saving: false,
                  onBack: () => backs++,
                  onSave: () => saves++,
                  commands: [
                    DocumentCommand(
                      'Предпросмотр',
                      Icons.visibility,
                      () => previews++,
                    ),
                    DocumentCommand('Печать', Icons.print, () {}),
                    DocumentCommand('Ссылка', Icons.link, () {}),
                  ],
                  selector: const SizedBox(height: 40, child: Text('КП / ПКП')),
                  extra: IconButton(
                    tooltip: 'Отправить',
                    onPressed: () {},
                    icon: const Icon(Icons.send),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Назад'));
      if (width < 600) {
        expect(find.text('№123456'), findsOneWidget);
        expect(find.text('Предпросмотр'), findsNothing);
        await tester.tap(find.byTooltip('Сохранить'));
        await tester.tap(find.byTooltip('Ещё'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(MenuItemButton, 'Предпросмотр'));
      } else {
        await tester.tap(
          width < 760 ? find.byTooltip('Сохранить') : find.text('Сохранить'),
        );
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(backs, 8);
    expect(saves, 8);
    expect(previews, 2);
  });
}
