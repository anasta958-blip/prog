import 'package:intl/intl.dart';

/// Число и русская форма существительного; учитывает 11–14 и отрицательные числа.
String russianCount(int count, String one, String few, String many) {
  final value = count.abs();
  final form = value % 100 >= 11 && value % 100 <= 14
      ? many
      : switch (value % 10) {
          1 => one,
          2 || 3 || 4 => few,
          _ => many,
        };
  return '$count $form';
}

/// Процент, уже выраженный в процентах, с русским десятичным разделителем.
String russianPercent(num value) =>
    '${NumberFormat('0.0', 'ru').format(value)} %';
