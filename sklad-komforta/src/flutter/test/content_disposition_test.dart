import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/core/network/content_disposition.dart';

void main() {
  test('читает русское имя файла из filename*', () {
    expect(
      contentDispositionFileName(
        "attachment; filename*=UTF-8''%D0%9A%D0%9F%20-%20%D0%A2%D0%B5%D1%81%D1%82.pdf",
      ),
      'КП - Тест.pdf',
    );
  });

  test('поддерживает обычный filename', () {
    expect(
      contentDispositionFileName('attachment; filename="quote.pdf"'),
      'quote.pdf',
    );
  });
}
