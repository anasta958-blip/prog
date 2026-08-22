import 'package:flutter/material.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/features/auth/auth_controller.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_controller.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_page.dart';
import 'package:sklad_komforta_app/features/company/company_controller.dart';
import 'package:sklad_komforta_app/features/company/company_page.dart';

/// Главная оболочка авторизованной части приложения.
final class WorkspacePage extends StatefulWidget {
  const WorkspacePage({
    required this.config,
    required this.authController,
    this.catalogController,
    this.companyController,
    super.key,
  });

  final AppConfig config;
  final AuthController authController;
  final CatalogController? catalogController;
  final CompanyController? companyController;

  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> {
  late final CatalogController catalogController;
  late final bool ownsCatalogController;
  late final CompanyController companyController;
  late final bool ownsCompanyController;
  int selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    ownsCatalogController = widget.catalogController == null;
    catalogController =
        widget.catalogController ??
        CatalogController(widget.config, widget.authController);
    catalogController.initialize();
    ownsCompanyController = widget.companyController == null;
    companyController =
        widget.companyController ??
        CompanyController(widget.config, widget.authController);
  }

  @override
  void dispose() {
    if (ownsCatalogController) catalogController.dispose();
    if (ownsCompanyController) companyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 840;
          final content = switch (selectedIndex) {
            1 => CompanyPage(controller: companyController),
            2 => _SessionsPage(controller: widget.authController),
            _ => CatalogPage(controller: catalogController),
          };
          if (!desktop) {
            return Scaffold(
              appBar: AppBar(
                title: const Text('Склад Комфорта'),
                backgroundColor: const Color(0xFF101823),
              ),
              drawer: Drawer(
                backgroundColor: const Color(0xFF101823),
                child: SafeArea(child: _Navigation(onSelect: _select)),
              ),
              body: content,
            );
          }
          return Row(
            children: [
              SizedBox(
                width: 220,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: Color(0xFF101823),
                    border: Border(right: BorderSide(color: Color(0xFF253348))),
                  ),
                  child: _Navigation(
                    selectedIndex: selectedIndex,
                    onSelect: _select,
                  ),
                ),
              ),
              Expanded(child: content),
            ],
          );
        },
      ),
    ),
  );

  void _select(int index) {
    setState(() => selectedIndex = index);
    if (index == 1) companyController.initialize();
    if (index == 2) widget.authController.loadSessions();
    Navigator.maybePop(context);
  }
}

final class _Navigation extends StatelessWidget {
  const _Navigation({required this.onSelect, this.selectedIndex = 0});
  final ValueChanged<int> onSelect;
  final int selectedIndex;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(20, 22, 16, 20),
        child: Row(
          children: [
            _BrandMark(),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Склад Комфорта',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
      const Divider(height: 1),
      const Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
        child: Text(
          'РАБОЧЕЕ ПРОСТРАНСТВО',
          style: TextStyle(
            color: Color(0xFF6F86A7),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        ),
      ),
      _NavigationItem(
        icon: Icons.inventory_2_outlined,
        label: 'Каталог товаров',
        selected: selectedIndex == 0,
        onTap: () => onSelect(0),
      ),
      _NavigationItem(
        icon: Icons.business_outlined,
        label: 'Компания',
        selected: selectedIndex == 1,
        onTap: () => onSelect(1),
      ),
      _NavigationItem(
        icon: Icons.devices_outlined,
        label: 'Активные устройства',
        selected: selectedIndex == 2,
        onTap: () => onSelect(2),
      ),
      const Spacer(),
      const Padding(
        padding: EdgeInsets.all(16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Color(0xFF121E2C),
            borderRadius: BorderRadius.all(Radius.circular(12)),
            border: Border.fromBorderSide(BorderSide(color: Color(0xFF26364C))),
          ),
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  Icons.cloud_done_outlined,
                  size: 18,
                  color: Color(0xFF50C878),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Соединение защищено',
                    style: TextStyle(fontSize: 11, color: Color(0xFF92A7C4)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

final class _BrandMark extends StatelessWidget {
  const _BrandMark();
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFF4D8DFF),
      borderRadius: BorderRadius.circular(10),
    ),
    child: const SizedBox(
      width: 34,
      height: 34,
      child: Icon(Icons.inventory_2_outlined, size: 19),
    ),
  );
}

final class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
    child: ListTile(
      dense: true,
      selected: selected,
      selectedTileColor: const Color(0xFF17345A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      leading: Icon(icon, size: 20),
      title: Text(label, style: const TextStyle(fontSize: 13)),
      onTap: onTap,
    ),
  );
}

final class _SessionsPage extends StatelessWidget {
  const _SessionsPage({required this.controller});
  final AuthController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => Padding(
      padding: const EdgeInsets.all(28),
      child: ListView(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Активные устройства',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Выйти',
                onPressed: controller.busy ? null : controller.logout,
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Управление действующими refresh-сессиями учётной записи.',
            style: TextStyle(color: Color(0xFF8FA4C2)),
          ),
          const SizedBox(height: 24),
          for (final session in controller.sessions)
            Card(
              child: ListTile(
                leading: const Icon(Icons.devices_outlined),
                title: Text(
                  (session['deviceName'] as String?) ??
                      'Неизвестное устройство',
                ),
                subtitle: Text(
                  (session['ipAddress'] as String?) ?? 'IP не определён',
                ),
                trailing: session['isCurrent'] == true
                    ? const Chip(label: Text('Текущее'))
                    : IconButton(
                        tooltip: 'Отозвать сессию',
                        onPressed: controller.busy
                            ? null
                            : () => controller.revokeSession(
                                session['id'] as String,
                              ),
                        icon: const Icon(Icons.close),
                      ),
              ),
            ),
          if (controller.sessions.any(
            (session) => session['isCurrent'] != true,
          ))
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: OutlinedButton(
                onPressed: controller.busy
                    ? null
                    : controller.revokeOtherSessions,
                child: const Text('Завершить остальные сессии'),
              ),
            ),
        ],
      ),
    ),
  );
}
