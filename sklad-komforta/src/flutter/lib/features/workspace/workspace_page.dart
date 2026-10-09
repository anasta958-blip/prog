import 'package:flutter/material.dart';
import 'package:sklad_komforta_app/core/platform/workspace_address.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/widgets/mobile_collapsible_navigation.dart';
import 'package:sklad_komforta_app/core/widgets/workspace_header.dart';
import 'package:sklad_komforta_app/features/auth/auth_controller.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_controller.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_page.dart';
import 'package:sklad_komforta_app/features/company/company_controller.dart';
import 'package:sklad_komforta_app/features/company/configuration_edit_guard.dart';
import 'package:sklad_komforta_app/features/company/company_models.dart';
import 'package:sklad_komforta_app/features/company/company_page.dart';
import 'package:sklad_komforta_app/features/kanban/kanban_controller.dart';
import 'package:sklad_komforta_app/features/kanban/kanban_page.dart';
import 'package:sklad_komforta_app/features/orders/pdf_viewer_window.dart';

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
  int _boardBackRequest = 0;
  CompanySection companySection = CompanySection.settings;
  bool companyExpanded = false;

  /// Боковая панель на широком экране свёрнута до иконок.
  bool sidebarCollapsed = false;
  // Сохраняет состояние открытой страницы при смене адаптивной оболочки.
  final GlobalKey _contentKey = GlobalKey();
  final ConfigurationEditGuard configurationEditGuard =
      ConfigurationEditGuard();

  static const _sidebarStorageKey = 'workspace.sidebar_collapsed.v1';
  static const FlutterSecureStorage _preferences = FlutterSecureStorage();

  /// Восстанавливает состояние панели с прошлого запуска. Ошибка хранилища не
  /// мешает работе: панель просто остаётся развёрнутой.
  Future<void> _restoreSidebar() async {
    try {
      final stored = await _preferences.read(key: _sidebarStorageKey);
      if (mounted && stored == 'true') {
        setState(() => sidebarCollapsed = true);
      }
    } catch (_) {}
  }

  void _toggleSidebar() {
    setState(() => sidebarCollapsed = !sidebarCollapsed);
    _preferences
        .write(key: _sidebarStorageKey, value: '$sidebarCollapsed')
        .catchError((Object _) {});
  }

  @override
  void initState() {
    super.initState();
    final path = readWorkspacePath()
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList();
    selectedIndex = switch (path.firstOrNull) {
      'catalog' => 1,
      'company' => 2,
      'devices' => 3,
      _ => 0,
    };
    if (selectedIndex == 2) {
      companySection =
          CompanySection.values
              .where((section) => section.name == path.lastOrNull)
              .firstOrNull ??
          CompanySection.settings;
      companyExpanded = true;
    }
    _restoreSidebar();
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
    if (selectedIndex == 2) companyController.initialize();
    if (selectedIndex == 3) widget.authController.loadSessions();
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
    // Окна просмотра PDF плавают над рабочей областью и закрываются вместе
    // с ней (например, при выходе).
    body: PdfViewerHost(
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 840;
            final page = switch (selectedIndex) {
              1 => CatalogPage(controller: catalogController),
              2 => CompanyPage(
                controller: companyController,
                section: companySection,
                onSectionRequested: _selectCompanySection,
                configurationEditGuard: configurationEditGuard,
              ),
              3 => _SessionsPage(controller: widget.authController),
              _ => KanbanPage(
                backRequest: _boardBackRequest,
                controller: kanbanController,
                config: widget.config,
                authController: widget.authController,
              ),
            };
            final content = KeyedSubtree(key: _contentKey, child: page);
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
                      onLogout: () =>
                          _confirmLogout(context, widget.authController),
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
                AnimatedContainer(
                  key: const Key('workspace-sidebar'),
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  width: sidebarCollapsed ? 72 : 248,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      color: Color(0xFF101823),
                      border: Border(
                        right: BorderSide(color: Color(0xFF253348)),
                      ),
                    ),
                    child: _Navigation(
                      selectedIndex: selectedIndex,
                      companySection: companySection,
                      companyExpanded: companyExpanded,
                      lifecycle: companyController.lifecycle,
                      onSelect: _select,
                      onLogout: () =>
                          _confirmLogout(context, widget.authController),
                      onToggleCompany: _toggleCompany,
                      onSelectCompanySection: _selectCompanySection,
                      collapsed: sidebarCollapsed,
                      onToggleSidebar: _toggleSidebar,
                    ),
                  ),
                ),
                Expanded(child: content),
              ],
            );
          },
        ),
      ),
    ),
  );

  Future<void> _select(int index) async {
    if (index != selectedIndex &&
        !await configurationEditGuard.canLeave(context)) {
      return;
    }
    if (!mounted) return;
    final returningToBoard = index == 0 && selectedIndex == 0;
    setState(() {
      selectedIndex = index;
      if (returningToBoard) _boardBackRequest++;
    });
    if (index == 0 && !returningToBoard) kanbanController.reload();
    if (index == 1) catalogController.reloadConfiguration();
    if (index == 2) companyController.initialize();
    if (index == 3) widget.authController.loadSessions();
    _saveAddress();
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
    _saveAddress();
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
    _saveAddress();
    Navigator.maybePop(context);
  }

  void _saveAddress() => writeWorkspacePath(switch (selectedIndex) {
    1 => '/catalog',
    2 => '/company/${companySection.name}',
    3 => '/devices',
    _ => '/kanban',
  });
}

Future<void> _confirmLogout(
  BuildContext context,
  AuthController controller,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Выйти из учётной записи?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Выйти'),
        ),
      ],
    ),
  );
  if (confirmed == true) await controller.logout();
}

final class _Navigation extends StatelessWidget {
  const _Navigation({
    required this.onSelect,
    required this.onLogout,
    required this.onToggleCompany,
    required this.onSelectCompanySection,
    required this.companySection,
    required this.companyExpanded,
    this.lifecycle,
    this.selectedIndex = 0,
    this.collapsed = false,
    this.onToggleSidebar,
  });
  final ValueChanged<int> onSelect;
  final VoidCallback onLogout;

  final VoidCallback onToggleCompany;
  final ValueChanged<CompanySection> onSelectCompanySection;
  final CompanySection companySection;
  final bool companyExpanded;
  final OrganizationLifecycle? lifecycle;
  final int selectedIndex;

  /// Панель свёрнута пользователем до иконок (только на широком экране).
  final bool collapsed;

  /// Кнопка сворачивания панели; в выдвижном меню телефона её нет.
  final VoidCallback? onToggleSidebar;

  // Компактная раскладка выбирается по фактической ширине, поэтому во время
  // анимации ширины подписи не вылезают за край панели.
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        _build(context, iconsOnly: collapsed || constraints.maxWidth < 180),
  );

  Widget _sidebarToggle() => IconButton(
    key: const Key('workspace-sidebar-toggle'),
    tooltip: collapsed ? 'Развернуть панель' : 'Свернуть панель',
    onPressed: onToggleSidebar,
    icon: Icon(
      collapsed
          ? Icons.keyboard_double_arrow_right
          : Icons.keyboard_double_arrow_left,
      size: 20,
    ),
  );

  Widget _build(BuildContext context, {required bool iconsOnly}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (iconsOnly)
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 19, 0, 8),
          child: Column(
            children: [
              const Tooltip(message: 'Склад Комфорта', child: _BrandMark()),
              if (onToggleSidebar != null) ...[
                const SizedBox(height: 8),
                _sidebarToggle(),
              ],
            ],
          ),
        )
      else
        Container(
          height: workspaceHeaderHeight,
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            onToggleSidebar == null ? 16 : 6,
            0,
          ),
          child: Row(
            children: [
              const _BrandMark(),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Склад Комфорта',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              if (onToggleSidebar != null) _sidebarToggle(),
            ],
          ),
        ),
      const Divider(height: 1),
      if (iconsOnly)
        const SizedBox(height: 12)
      else
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
      // Пункты прокручиваются, если не помещаются по высоте (невысокое окно,
      // раскрытые разделы компании, перенос подписей во время анимации).
      Expanded(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _NavigationItem(
                iconsOnly: iconsOnly,
                icon: Icons.view_kanban_outlined,
                label: 'Канбаны',
                selected: selectedIndex == 0,
                onTap: () => onSelect(0),
              ),
              _NavigationItem(
                iconsOnly: iconsOnly,
                icon: Icons.inventory_2_outlined,
                label: 'Каталог товаров',
                selected: selectedIndex == 1,
                onTap: () => onSelect(1),
              ),
              _NavigationItem(
                iconsOnly: iconsOnly,
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
                    iconsOnly: iconsOnly,
                    icon: section.icon,
                    label: section.label,
                    selected: selectedIndex == 2 && companySection == section,
                    indent: 24,
                    compact: true,
                    onTap: () => onSelectCompanySection(section),
                  ),
              if (companyExpanded && lifecycle != null && !iconsOnly)
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
                iconsOnly: iconsOnly,
                icon: Icons.devices_outlined,
                label: 'Активные устройства',
                selected: selectedIndex == 3,
                onTap: () => onSelect(3),
              ),
            ],
          ),
        ),
      ),
      _NavigationItem(
        iconsOnly: iconsOnly,
        icon: Icons.logout,
        label: 'Выйти',
        selected: false,
        onTap: onLogout,
      ),
      if (iconsOnly)
        const Padding(
          padding: EdgeInsets.only(bottom: 18),
          child: Tooltip(
            message: 'Соединение защищено',
            child: Icon(
              Icons.cloud_done_outlined,
              size: 20,
              color: Color(0xFF50C878),
            ),
          ),
        )
      else
        const Padding(
          padding: EdgeInsets.all(16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0xFF121E2C),
              borderRadius: BorderRadius.all(Radius.circular(12)),
              border: Border.fromBorderSide(
                BorderSide(color: Color(0xFF26364C)),
              ),
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
    this.iconsOnly = false,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;
  final double indent;
  final bool compact;

  /// Свёрнутая панель: только иконка, название — во всплывающей подсказке.
  final bool iconsOnly;
  @override
  Widget build(BuildContext context) => iconsOnly
      ? Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 12,
            vertical: compact ? 1 : 3,
          ),
          child: Tooltip(
            message: label,
            waitDuration: const Duration(milliseconds: 300),
            child: Material(
              color: selected ? const Color(0xFF17345A) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onTap,
                child: SizedBox(
                  height: compact ? 36 : 44,
                  child: Icon(
                    icon,
                    size: compact ? 18 : 20,
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                ),
              ),
            ),
          ),
        )
      : Padding(
          padding: EdgeInsets.fromLTRB(
            12 + indent,
            compact ? 1 : 3,
            12,
            compact ? 1 : 3,
          ),
          child: ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            minLeadingWidth: 20,
            horizontalTitleGap: 8,
            visualDensity: compact ? const VisualDensity(vertical: -2) : null,
            selected: selected,
            selectedTileColor: const Color(0xFF17345A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            leading: Icon(icon, size: 20),
            title: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
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
                    TextButton.icon(
                      label: const Text('Выйти'),
                      onPressed: controller.busy
                          ? null
                          : () => _confirmLogout(context, controller),
                      icon: const Icon(Icons.logout),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Управление входами на устройствах.',
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
                  (session['ipAddress'] as String?)?.replaceFirst(
                        RegExp(r'^::ffff:', caseSensitive: false),
                        '',
                      ) ??
                      'IP не определён',
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
