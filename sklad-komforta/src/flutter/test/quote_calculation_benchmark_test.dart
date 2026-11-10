import 'package:flutter_test/flutter_test.dart';
import '../benchmark/quote_calculation.dart';

// Run explicitly: flutter test test/quote_calculation_benchmark_test.dart
void main() {
  test('partial and full calculation timings', () {
    for (final line in runCalculationBenchmark()) {
      // ignore: avoid_print
      print(line);
    }
  });
}
