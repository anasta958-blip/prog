import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:sklad_komforta_app/app/app.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/platform/windows_keyboard_guard.dart';

/// Инициализирует Flutter binding, читает compile-time конфигурацию и запускает
/// единый корневой виджет для всех поддерживаемых платформ.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Модуль PDFium WASM нужен Web-сборке и намеренно лежит в общих ресурсах;
  // отладочное напоминание о нём на Windows/мобильных отключено. Для выпуска
  // не-Web сборок его убирает `dart run pdfrx:remove_wasm_modules`.
  unawaited(pdfrxFlutterInitialize(dismissPdfiumWasmWarnings: true));
  runApp(SkladKomfortaApp(config: AppConfig.fromEnvironment()));
  unawaited(installWindowsKeyboardGuard());
}
