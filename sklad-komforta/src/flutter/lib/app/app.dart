import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/l10n/app_localizations.dart';
import 'package:sklad_komforta_app/features/auth/auth_flow_page.dart';
import 'package:sklad_komforta_app/features/auth/auth_controller.dart';
import 'package:sklad_komforta_app/features/quotes/quote_client_access_page.dart';

/// Корневой виджет общего Windows, macOS, Web, Android и iOS приложения.
///
/// Здесь подключаются локализация, тема и верхнеуровневая навигация. Бизнес-
/// экраны будут добавляться только после согласования их визуальных вариантов.
class SkladKomfortaApp extends StatelessWidget {
  /// Создаёт приложение с явно переданной конфигурацией среды.
  const SkladKomfortaApp({
    required this.config,
    this.authController,
    this.initializeAuthController = true,
    super.key,
  });

  /// Настройки API и среды, общие для всего дерева виджетов.
  final AppConfig config;

  /// Необязательный контроллер для изолированных widget-тестов без сети.
  final AuthController? authController;

  /// Отключается только в тесте конкретного auth-этапа.
  final bool initializeAuthController;

  /// Формирует MaterialApp с русской локалью и общей премиальной тёмной темой.
  @override
  Widget build(BuildContext context) {
    final quoteAccessToken = Uri.base.queryParameters['quoteAccessToken'];
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('ru'),
      theme: buildAppTheme(),
      home: quoteAccessToken?.trim().isNotEmpty == true
          ? QuoteClientAccessPage(
              config: config,
              accessToken: quoteAccessToken!,
            )
          : AuthFlowPage(
              config: config,
              controller: authController,
              initializeController: initializeAuthController,
            ),
    );
  }
}

/// Возвращает централизованную тему всех экранов приложения.
ThemeData buildAppTheme() {
  const background = Color(0xFF0D121A);
  const surface = Color(0xFF161E2B);
  const accent = Color(0xFF4D8DFF);

  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: background,
    colorScheme: const ColorScheme.dark(
      primary: accent,
      surface: surface,
      onSurface: Color(0xFFF2F6FF),
    ),
    textTheme: const TextTheme(
      headlineMedium: TextStyle(
        fontFamily: 'Georgia',
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      bodyMedium: TextStyle(height: 1.5),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF0D151F),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF2B3A51)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF2B3A51)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: accent, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}
