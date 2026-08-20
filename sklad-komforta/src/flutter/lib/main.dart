import 'package:flutter/widgets.dart';
import 'package:sklad_komforta_app/app/app.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';

/// Инициализирует Flutter binding, читает compile-time конфигурацию и запускает
/// единый корневой виджет для всех поддерживаемых платформ.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(SkladKomfortaApp(config: AppConfig.fromEnvironment()));
}
