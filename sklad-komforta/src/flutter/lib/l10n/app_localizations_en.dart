// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Sklad Komforta';

  @override
  String get bootstrapReady =>
      'The technical client shell is ready. Business screens will be implemented after design approval.';

  @override
  String get environment => 'Environment';

  @override
  String get apiAddress => 'API';
}
