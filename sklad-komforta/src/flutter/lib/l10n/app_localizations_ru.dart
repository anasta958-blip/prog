// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'Склад Комфорта';

  @override
  String get bootstrapReady =>
      'Технический каркас клиента готов. Бизнес-экраны будут реализованы после согласования вариантов дизайна.';

  @override
  String get environment => 'Среда';

  @override
  String get apiAddress => 'API';
}
