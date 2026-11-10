// This standalone benchmark runs directly in a browser, outside Flutter.
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;

import 'quote_calculation.dart';

void main() {
  final lines = runCalculationBenchmark();
  html.document.body!.text = lines.join('\n');
}
