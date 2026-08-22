import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/core/widgets/app_select_field.dart';

void main() {
  testWidgets('меню переносится над полем при нехватке места снизу', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(500, 300);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: 40,
                right: 40,
                bottom: 8,
                child: AppSelectField<String>(
                  value: 'one',
                  label: 'Значение',
                  options: const [
                    AppSelectOption(value: 'one', label: 'Первое'),
                    AppSelectOption(value: 'two', label: 'Второе'),
                    AppSelectOption(value: 'three', label: 'Третье'),
                  ],
                  onChanged: (_) {},
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final field = find.byType(AppSelectField<String>);
    final fieldBounds = tester.getRect(field);
    await tester.tap(field);
    await tester.pumpAndSettle();

    final firstItem = tester.getRect(
      find.widgetWithText(MenuItemButton, 'Первое'),
    );
    expect(firstItem.bottom, lessThanOrEqualTo(fieldBounds.top));
  });
}
