import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/core/widgets/app_notice.dart';

void main() {
  test('всплывающие уведомления показываются пять секунд', () {
    expect(
      const AppSnackBar(content: Text('Сообщение')).duration,
      const Duration(seconds: 5),
    );
  });
  testWidgets('уведомление скрывается и новое получает свои пять секунд', (
    tester,
  ) async {
    Widget notice(String message) => MaterialApp(
      home: AutoDismissNotice(message: message, child: Text(message)),
    );
    await tester.pumpWidget(notice('Сохранено'));
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Сохранено'), findsOneWidget);
    await tester.pumpWidget(notice('Ошибка операции'));
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Ошибка операции'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Ошибка операции'), findsNothing);
    await tester.pumpWidget(notice('Новое сообщение'));
    expect(find.text('Новое сообщение'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });
}
