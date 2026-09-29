import 'package:flutter/material.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/widgets/mobile_collapsible_navigation.dart';
import 'package:sklad_komforta_app/features/auth/auth_controller.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_controller.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_page.dart';
import 'package:sklad_komforta_app/features/company/company_controller.dart';
import 'package:sklad_komforta_app/features/company/configuration_edit_guard.dart';
import 'package:sklad_komforta_app/features/company/company_models.dart';
import 'package:sklad_komforta_app/features/company/company_page.dart';
import 'package:sklad_komforta_app/features/kanban/kanban_controller.dart';
import 'package:sklad_komforta_app/features/kanban/kanban_page.dart';

/// Главная оболочка авторизованной части приложения.
final class WorkspacePage extends StatefulWidget {
  const WorkspacePage({
    required this.config,
    required this.authController,
    this.catalogController,
    this.companyController,
    this.kanbanController,
    super.key,
  });

  final AppConfig config;
  final AuthController authController;
  final CatalogController? catalogController;
  final CompanyController? companyController;
  final KanbanController? kanbanController;

  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> {
  late final CatalogController catalogController;
  late final bool ownsCatalogController;
  late final CompanyController companyController;
  late final bool ownsCompanyController;
  late final KanbanController kanbanController;
  late final bool ownsKanbanController;
  int selectedIndex = 0;
  CompanySection companySection = CompanySection.settings;
  bool companyExpanded = false;
  final ConfigurationEditGuard configurationEditGuard =
      ConfigurationEditGuard();

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
    ownsKanbanController = widget.kanbanController == null;
    kanbanController =
        widget.kanbanController ??
        KanbanController(widget.config, widget.authController);
    kanbanController.initialize();
  }

  @override
  void dispose() {
    if (ownsCatalogController) catalogController.dispose();
    if (ownsCompanyController) companyController.dispose();
    if (ownsKanbanController) kanbanController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 840;
          final content = switch (selectedIndex) {
            1 => CatalogPage(controller: catalogController),
            2 => CompanyPage(
              controller: companyController,
              section: companySection,
              onSectionRequested: _selectCompanySection,
              configurationEditGuard: configurationEditGuard,
            ),
            3 => _SessionsPage(controller: widget.authController),
            _ => KanbanPage(
              controller: kanbanController,
              config: widget.config,
              authController: widget.authController,
            ),
          };
          if (!desktop) {
            return Scaffold(
              appBar: AppBar(
                toolbarHeight: 48,
                titleSpacing: 0,
                title: Text(
                  switch (selectedIndex) {
                    1 => 'Каталог товаров',
                    2 => companySection.label,
                    3 => 'Активные устройства',
                    _ => 'Канбаны',
                  },
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                backgroundColor: const Color(0xFF101823),
              ),
              drawer: Drawer(
                backgroundColor: const Color(0xFF101823),
                child: SafeArea(
                  child: _Navigation(
                    selectedIndex: selectedIndex,
                    companySection: companySection,
                    companyExpanded: companyExpanded,
                    lifecycle: companyController.lifecycle,
                    onSelect: _select,
                    onToggleCompany: _toggleCompany,
                    onSelectCompanySection: _selectCompanySection,
                  ),
                ),
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
                    companySection: companySection,
                    companyExpanded: companyExpanded,
                    lifecycle: companyController.lifecycle,
                    onSelect: _select,
                    onToggleCompany: _toggleCompany,
                    onSelectCompanySection: _selectCompanySection,
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

  Future<void> _select(int index) async {
    if (index != selectedIndex &&
        !await configurationEditGuard.canLeave(context)) {
      return;
    }
    if (!mounted) return;
    setState(() => selectedIndex = index);
    if (index == 0) kanbanController.reload();
    if (index == 1) catalogController.reloadConfiguration();
    if (index == 2) companyController.initialize();
    if (index == 3) widget.authController.loadSessions();
    Navigator.maybePop(context);
  }

  /// Пункт «Компания» — исключение из правила «сворачивать только стрелкой»:
  /// нажатие на всю строку открывает пространство, а повторное — сворачивает
  /// или разворачивает его разделы.
  void _toggleCompany() {
    setState(() {
      if (selectedIndex != 2) {
        selectedIndex = 2;
        companyExpanded = true;
      } else {
        companyExpanded = !companyExpanded;
      }
    });
    companyController.initialize();
  }

  Future<void> _selectCompanySection(CompanySection section) async {
    if ((selectedIndex != 2 || section != companySection) &&
        !await configurationEditGuard.canLeave(context)) {
      return;
    }
    if (!mounted) return;
    setState(() {
      selectedIndex = 2;
      companySection = section;
      companyExpanded = true;
    });
    companyController.initialize();
    Navigator.maybePop(context);
  }
}

final class _Navigation extends StatelessWidget {
  const _Navigation({
    required this.onSelect,
    required this.onToggleCompany,
    required this.onSelectCompanySection,
    required this.companySection,
    required this.companyExpanded,
    this.lifecycle,
    this.selectedIndex = 0,
  });
  final ValueChanged<int> onSelect;

  final VoidCallback onToggleCompany;
  final ValueChanged<CompanySection> onSelectCompanySection;
  final CompanySection companySection;
  final bool companyExpanded;
  final OrganizationLifecycle? lifecycle;
  final int selectedIndex;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(20, 19, 16, 17),
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
        icon: Icons.view_kanban_outlined,
        label: 'Канбаны',
        selected: selectedIndex == 0,
        onTap: () => onSelect(0),
      ),
      _NavigationItem(
        icon: Icons.inventory_2_outlined,
        label: 'Каталог товаров',
        selected: selectedIndex == 1,
        onTap: () => onSelect(1),
      ),
      _NavigationItem(
        icon: Icons.business_outlined,
        label: 'Компания',
        selected: selectedIndex == 2,
        trailing: AnimatedRotation(
          turns: companyExpanded ? 0 : -0.25,
          duration: const Duration(milliseconds: 160),
          child: const Icon(Icons.expand_more, size: 18),
        ),
        onTap: onToggleCompany,
      ),
      if (companyExpanded)
        for (final section in CompanySection.values)
          _NavigationItem(
            icon: section.icon,
            label: section.label,
            selected: selectedIndex == 2 && companySection == section,
            indent: 24,
            compact: true,
            onTap: () => onSelectCompanySection(section),
          ),
      if (companyExpanded && lifecycle != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(48, 7, 18, 7),
          child: Text(
            lifecycle!.isFrozen
                ? 'Организация заморожена'
                : 'Активна до ${_shortDate(lifecycle!.activeUntil)}',
            style: TextStyle(
              color: lifecycle!.isFrozen
                  ? const Color(0xFFFF809D)
                  : const Color(0xFF7891B4),
              fontSize: 10,
            ),
          ),
        ),
      _NavigationItem(
        icon: Icons.devices_outlined,
        label: 'Активные устройства',
        selected: selectedIndex == 3,
        onTap: () => onSelect(3),
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
    this.trailing,
    this.indent = 0,
    this.compact = false,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;
  final double indent;
  final bool compact;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      12 + indent,
      compact ? 1 : 3,
      12,
      compact ? 1 : 3,
    ),
    child: ListTile(
      dense: true,
      visualDensity: compact ? const VisualDensity(vertical: -2) : null,
      selected: selected,
      selectedTileColor: const Color(0xFF17345A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      leading: Icon(icon, size: 20),
      title: Text(label, style: const TextStyle(fontSize: 13)),
      trailing: trailing,
      onTap: onTap,
    ),
  );
}

String _shortDate(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';

final class _SessionsPage extends StatelessWidget {
  const _SessionsPage({required this.controller});
  final AuthController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => Padding(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 12 : 28),
      child: ListView(
        children: [
          MobileCollapsibleNavigation(
            title: 'Управление устройствами',
            summary: '${controller.sessions.length}',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Активные устройства',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
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
              ],
            ),
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
