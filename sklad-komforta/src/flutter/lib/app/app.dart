import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/l10n/app_localizations.dart';

/// Корневой виджет общего Windows, macOS, Web, Android и iOS приложения.
///
/// Здесь подключаются локализация, тема и верхнеуровневая навигация. Бизнес-
/// экраны будут добавляться только после согласования их визуальных вариантов.
class SkladKomfortaApp extends StatelessWidget {
  /// Создаёт приложение с явно переданной конфигурацией среды.
  const SkladKomfortaApp({required this.config, super.key});

  /// Настройки API и среды, общие для всего дерева виджетов.
  final AppConfig config;

  /// Формирует MaterialApp с русской локалью и общей премиальной тёмной темой.
  @override
  Widget build(BuildContext context) {
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
      theme: _buildTheme(),
      home: _BootstrapPage(config: config),
    );
  }

  /// Возвращает централизованную тему технического каркаса без стилей будущих
  /// бизнес-модулей, которые будут сформированы после утверждения дизайна.
  ThemeData _buildTheme() {
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
    );
  }
}

class _BootstrapPage extends StatelessWidget {
  /// Создаёт диагностическую стартовую страницу текущей технической итерации.
  const _BootstrapPage({required this.config});

  final AppConfig config;

  /// Показывает активную среду и API, чтобы быстро обнаружить ошибочную сборку.
  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border.all(color: const Color(0xFF2B3A51)),
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x55000000),
                    blurRadius: 36,
                    offset: Offset(0, 18),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(strings.appTitle, style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 12),
                    Text(strings.bootstrapReady),
                    const SizedBox(height: 24),
                    _TechnicalValue(label: strings.environment, value: config.environment),
                    const SizedBox(height: 10),
                    _TechnicalValue(label: strings.apiAddress, value: config.apiBaseUrl),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TechnicalValue extends StatelessWidget {
  /// Создаёт строку технического параметра с фиксированной колонкой названия.
  const _TechnicalValue({required this.label, required this.value});

  final String label;
  final String value;

  /// Выводит значение как SelectableText для удобной диагностики адреса API.
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 112,
          child: Text(label, style: const TextStyle(color: Color(0xFF8FA4C2))),
        ),
        Expanded(child: SelectableText(value)),
      ],
    );
  }
}
