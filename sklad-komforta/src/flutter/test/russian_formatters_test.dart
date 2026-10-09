import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/core/formatters/russian.dart';

void main() {
  test('русские формы числительных', () {
    for (final n in [1, 21, 101]) {
      expect(russianCount(n, 'столбец', 'столбца', 'столбцов'), '$n столбец');
    }
    for (final n in [2, 3, 4, 22]) {
      expect(russianCount(n, 'столбец', 'столбца', 'столбцов'), '$n столбца');
    }
    for (final n in [0, 5, 11, 12, 14, 111]) {
      expect(russianCount(n, 'столбец', 'столбца', 'столбцов'), '$n столбцов');
    }
    expect(russianPercent(0), '0,0 %');
  });
}
