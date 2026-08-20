import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/app/app.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';

void main() {
  testWidgets('shows the localized technical bootstrap', (tester) async {
    await tester.pumpWidget(
      const SkladKomfortaApp(
        config: AppConfig(
          apiBaseUrl: 'https://api.example.test/api/v1',
          environment: 'test',
        ),
      ),
    );

    expect(find.text('Склад Комфорта'), findsOneWidget);
    expect(find.text('https://api.example.test/api/v1'), findsOneWidget);
  });
}
