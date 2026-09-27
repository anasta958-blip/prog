import 'package:flutter/material.dart';
import 'package:sklad_komforta_app/core/widgets/app_notice.dart';
import 'package:flutter/services.dart';
import 'package:sklad_komforta_app/core/widgets/app_select_field.dart';
import 'package:sklad_komforta_app/core/widgets/mobile_collapsible_navigation.dart';
import 'package:sklad_komforta_app/features/company/company_controller.dart';
import 'package:sklad_komforta_app/features/company/company_models.dart';
import 'package:sklad_komforta_app/features/company/company_audit.dart';
import 'package:sklad_komforta_app/features/company/configuration_edit_guard.dart';
import 'package:sklad_komforta_app/features/onboarding/organization_onboarding_page.dart';

/// Разделы пространства «Компания», отображаемые внутри основной навигации.
enum CompanySection {
  settings('Настройки организации', Icons.tune_outlined),
  clients('Клиенты', Icons.handshake_outlined),
  employees('Сотрудники и структура', Icons.account_tree_outlined),
  access('Права доступа', Icons.admin_panel_settings_outlined),
  audit('Аудит изменений', Icons.history_outlined);

  const CompanySection(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Содержимое выбранного подпространства без дублирующего бокового меню.
final class CompanyPage extends StatelessWidget {
  const CompanyPage({
    required this.controller,
    this.section = CompanySection.settings,
    this.onSectionRequested,
    this.configurationEditGuard,
    super.key,
  });
  final CompanyController controller;
  final CompanySection section;
  final ValueChanged<CompanySection>? onSectionRequested;
  final ConfigurationEditGuard? configurationEditGuard;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      if (controller.loading && controller.configuration == null) {
        return const Center(child: CircularProgressIndicator());
      }
      if (controller.configuration == null) {
        return _CompanyError(
          message: controller.error ?? 'Настройки организации не найдены.',
          onRetry: controller.initialize,
        );
      }
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(supportsAnnounce: false),
        child: ColoredBox(
          color: const Color(0xFF080E16),
          child: switch (section) {
            CompanySection.clients => _ClientsSection(controller: controller),
            CompanySection.employees => _EmployeesSection(
              controller: controller,
              onOpenAccess: () =>
                  onSectionRequested?.call(CompanySection.access),
            ),
            CompanySection.access => _AccessSection(controller: controller),
            CompanySection.audit => _AuditSection(controller: controller),
            CompanySection.settings => _OrganizationSettingsSection(
              controller: controller,
              configurationEditGuard: configurationEditGuard,
            ),
          },
        ),
      );
    },
  );
}

/// В настройках отдельно редактируются юридические лица и рабочая конфигурация.
final class _OrganizationSettingsSection extends StatefulWidget {
  const _OrganizationSettingsSection({
    required this.controller,
    this.configurationEditGuard,
  });
  final CompanyController controller;
  final ConfigurationEditGuard? configurationEditGuard;
  @override
  State<_OrganizationSettingsSection> createState() =>
      _OrganizationSettingsSectionState();
}

final class _OrganizationSettingsSectionState
    extends State<_OrganizationSettingsSection> {
  int tab = 0;
  late final ConfigurationEditGuard _configurationEditGuard =
      widget.configurationEditGuard ?? ConfigurationEditGuard();
  @override
  Widget build(BuildContext context) => Column(
    children: [
      _SectionHeader(
        title: 'Настройки организации',
        subtitle:
            'Юридические лица и рабочая конфигурация текущей организации.',
        trailing: SegmentedButton<int>(
          segments: const [
            ButtonSegment(
              value: 0,
              icon: Icon(Icons.business_outlined),
              label: Text('Юридические лица'),
            ),
            ButtonSegment(
              value: 1,
              icon: Icon(Icons.tune_outlined),
              label: Text('Рабочая конфигурация'),
            ),
          ],
          selected: {tab},
          showSelectedIcon: false,
          onSelectionChanged: _selectTab,
        ),
      ),
      Expanded(
        child: tab == 0
            ? _LegalEntitiesSection(controller: widget.controller)
            : OrganizationOnboardingPage(
                controller: widget.controller.authController,
                settingsDraft: widget.controller.configuration,
                settingsBusy: widget.controller.saving,
                settingsError: widget.controller.error,
                onSettingsSave: widget.controller.saveConfiguration,
                onCategoryDeletionImpact:
                    widget.controller.getCategoryDeletionImpact,
                onCategoryDeletionApproved:
                    widget.controller.approveCategoryDataDeletion,
                onCategoryDeletionApprovalsDiscarded:
                    widget.controller.discardCategoryDataDeletionApprovals,
                configurationEditGuard: _configurationEditGuard,
              ),
      ),
    ],
  );

  Future<void> _selectTab(Set<int> value) async {
    final next = value.first;
    if (next == tab) return;
    if (!await _configurationEditGuard.canLeave(context)) {
      return;
    }
    if (mounted) setState(() => tab = next);
  }
}

final class _LegalEntitiesSection extends StatelessWidget {
  const _LegalEntitiesSection({required this.controller});
  final CompanyController controller;
  @override
  Widget build(BuildContext context) => !controller.canViewLegalEntities
      ? const _NoAccessState(section: 'юридическим лицам')
      : _CollectionPage(
          emptyIcon: Icons.business_outlined,
          emptyText: 'Добавьте первое юридическое лицо.',
          onAdd: () => _editLegalEntity(context, controller, null),
          children: [
            for (final item in controller.legalEntities)
              _EntityCard(
                icon: Icons.apartment_outlined,
                title: item.name,
                badge: item.isDefault ? 'По умолчанию' : item.companyType,
                lines: [
                  item.legalName,
                  item.inn == null ? null : 'ИНН ${item.inn}',
                  item.phone,
                  item.email,
                ],
                onEdit: () => _editLegalEntity(context, controller, item),
                onDelete: () => controller.deleteLegalEntity(item.id),
              ),
          ],
        );
}

final class _ClientsSection extends StatelessWidget {
  const _ClientsSection({required this.controller});
  final CompanyController controller;
  @override
  Widget build(BuildContext context) => !controller.canViewClients
      ? const _NoAccessState(section: 'клиентам')
      : Column(
          children: [
            _SectionHeader(
              title: 'Клиенты',
              subtitle: 'Единый справочник заказчиков для будущих КП и ПКП.',
              trailing: FilledButton.icon(
                onPressed: () => _editClient(context, controller, null),
                icon: const Icon(Icons.add),
                label: const Text('Добавить клиента'),
              ),
            ),
            Expanded(
              child: _CollectionPage(
                emptyIcon: Icons.handshake_outlined,
                emptyText: 'Клиенты ещё не добавлены.',
                onAdd: () => _editClient(context, controller, null),
                showAddButton: false,
                children: [
                  for (final item in controller.clients)
                    _EntityCard(
                      icon: Icons.person_outline,
                      title: item.name,
                      badge: _partyTypeLabel(item.companyType),
                      lines: [
                        item.companyName,
                        item.contactName,
                        item.phone,
                        item.email,
                        item.address,
                      ],
                      onEdit: () => _editClient(context, controller, item),
                      onDelete: () => controller.deleteClient(item.id),
                    ),
                ],
              ),
            ),
          ],
        );
}

final class _EmployeesSection extends StatelessWidget {
  const _EmployeesSection({
    required this.controller,
    required this.onOpenAccess,
  });
  final CompanyController controller;
  final VoidCallback onOpenAccess;
  @override
  Widget build(BuildContext context) {
    if (!controller.canViewEmployees) {
      return const _NoAccessState(section: 'сотрудникам');
    }
    final roots = controller.employees
        .where((item) => item.supervisorMembershipId == null)
        .toList();
    return Column(
      children: [
        _SectionHeader(
          title: 'Дерево иерархии сотрудников',
          subtitle: 'Руководители и вся их нижестоящая ветка сотрудников.',
          trailing: FilledButton.icon(
            onPressed:
                controller.roles
                    .where((role) => role.name != 'Директор')
                    .isEmpty
                ? null
                : () => _createEmployee(context, controller),
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Добавить сотрудника'),
          ),
        ),
        if (controller.roles.where((role) => role.name != 'Директор').isEmpty)
          _InlineNotice(
            text:
                'Перед добавлением сотрудника создайте хотя бы одну назначаемую роль.',
            actionLabel: 'Открыть права доступа',
            onAction: onOpenAccess,
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(22),
            children: [
              if (controller.employees.isEmpty)
                const _EmptyState(
                  icon: Icons.account_tree_outlined,
                  text: 'Сотрудники ещё не добавлены.',
                ),
              for (final root in roots)
                _EmployeeTreeNode(
                  employee: root,
                  all: controller.employees,
                  controller: controller,
                  depth: 0,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Контекстная подсказка объясняет заблокированное действие и ведёт к исправлению.
final class _InlineNotice extends StatelessWidget {
  const _InlineNotice({
    required this.text,
    required this.actionLabel,
    required this.onAction,
  });

  final String text;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF101D2B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF29415F)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 18, color: Color(0xFF6EA3FF)),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
            TextButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    ),
  );
}

final class _EmployeeTreeNode extends StatefulWidget {
  const _EmployeeTreeNode({
    required this.employee,
    required this.all,
    required this.controller,
    required this.depth,
  });
  final EmployeeModel employee;
  final List<EmployeeModel> all;
  final CompanyController controller;
  final int depth;

  @override
  State<_EmployeeTreeNode> createState() => _EmployeeTreeNodeState();
}

final class _EmployeeTreeNodeState extends State<_EmployeeTreeNode> {
  bool expanded = true;

  @override
  Widget build(BuildContext context) {
    final children = widget.all
        .where(
          (item) => item.supervisorMembershipId == widget.employee.membershipId,
        )
        .toList();
    return Container(
      margin: EdgeInsets.only(left: widget.depth == 0 ? 0 : 24, bottom: 10),
      padding: EdgeInsets.only(left: widget.depth == 0 ? 0 : 12),
      decoration: widget.depth == 0
          ? null
          : const BoxDecoration(
              border: Border(left: BorderSide(color: Color(0xFF31527A))),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 38,
                child: children.isEmpty
                    ? const SizedBox.shrink()
                    : IconButton(
                        onPressed: () => setState(() => expanded = !expanded),
                        icon: AnimatedRotation(
                          turns: expanded ? .25 : 0,
                          duration: const Duration(milliseconds: 160),
                          child: const Icon(Icons.chevron_right),
                        ),
                        tooltip: expanded
                            ? 'Свернуть ветку'
                            : 'Развернуть ветку',
                      ),
              ),
              Expanded(
                child: _EntityCard(
                  icon: widget.employee.isDirector
                      ? Icons.workspace_premium_outlined
                      : Icons.badge_outlined,
                  title: widget.employee.displayName,
                  badge: widget.employee.roleName,
                  lines: [
                    'Логин: ${widget.employee.login}',
                    widget.employee.email,
                    'Активен до ${_date(widget.employee.activeUntil)}',
                  ],
                  onEdit: () => _editEmployee(
                    context,
                    widget.controller,
                    widget.employee,
                  ),
                  onDelete: widget.employee.isDirector
                      ? null
                      : () => widget.controller.deleteEmployee(
                          widget.employee.membershipId,
                        ),
                ),
              ),
            ],
          ),
          if (expanded)
            for (final child in children)
              _EmployeeTreeNode(
                employee: child,
                all: widget.all,
                controller: widget.controller,
                depth: widget.depth + 1,
              ),
        ],
      ),
    );
  }
}

final class _AccessSection extends StatelessWidget {
  const _AccessSection({required this.controller});
  final CompanyController controller;
  @override
  Widget build(BuildContext context) => !controller.canViewAccess
      ? const _NoAccessState(section: 'правам доступа')
      : Column(
          children: [
            _SectionHeader(
              title: 'Права доступа',
              subtitle: 'Роли определяют права и допустимые нижестоящие роли.',
              trailing: FilledButton.icon(
                onPressed: () => _editRole(context, controller, null),
                icon: const Icon(Icons.add),
                label: const Text('Добавить роль'),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(22),
                children: [
                  for (final role in controller.roles)
                    Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      clipBehavior: Clip.antiAlias,
                      child: _SafeExpansionTile(
                        leading: Icon(
                          role.isSystem
                              ? Icons.shield_outlined
                              : Icons.admin_panel_settings_outlined,
                          color: const Color(0xFF6EA3FF),
                        ),
                        title: Text(
                          role.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '${role.permissionCodes.length} прав · '
                          '${role.subordinateRoleIds.length} подчинённых ролей · '
                          '${_cardVisibilityLabel(role.cardVisibilityMode)}',
                        ),
                        trailing: role.isSystem
                            ? const Icon(Icons.lock_outline, size: 18)
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                          child: Row(
                            children: [
                              Expanded(
                                child: Wrap(
                                  spacing: 7,
                                  runSpacing: 7,
                                  children: [
                                    for (final code in role.permissionCodes)
                                      Chip(
                                        label: Text(
                                          _permissionName(
                                            controller.permissions,
                                            code,
                                          ),
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              if (!role.isSystem) ...[
                                IconButton(
                                  onPressed: () =>
                                      _editRole(context, controller, role),
                                  icon: const Icon(Icons.edit_outlined),
                                  tooltip: 'Редактировать',
                                ),
                                IconButton(
                                  onPressed: () =>
                                      controller.deleteRole(role.id),
                                  icon: const Icon(Icons.delete_outline),
                                  color: const Color(0xFFFF6F86),
                                  tooltip: 'Удалить',
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
}

/// Читаемый журнал действий без вывода внутренних JSON-структур пользователю.
final class _AuditSection extends StatelessWidget {
  const _AuditSection({required this.controller});

  final CompanyController controller;

  @override
  Widget build(BuildContext context) => !controller.canViewAudit
      ? const _NoAccessState(section: 'аудиту изменений')
      : Column(
          children: [
            const _SectionHeader(
              title: 'Аудит изменений',
              subtitle: 'Последние действия пользователей текущей организации.',
            ),
            Expanded(
              child: controller.auditEntries.isEmpty
                  ? const _EmptyState(
                      icon: Icons.history_outlined,
                      text: 'Изменений пока нет.',
                    )
                  : CompanyAuditList(
                      entries: controller.auditEntries,
                      names: {
                        ...auditReferenceNames(
                          controller.configuration?.toJson(),
                        ),
                        for (final role in controller.roles) role.id: role.name,
                        for (final permission in controller.permissions)
                          permission.code: permission.name,
                        for (final employee in controller.employees)
                          employee.membershipId: employee.displayName,
                        for (final employee in controller.employees)
                          employee.userId: employee.displayName,
                        for (final client in controller.clients)
                          client.id: client.name,
                        for (final entity in controller.legalEntities)
                          entity.id: entity.name,
                      },
                    ),
            ),
          ],
        );
}

final class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    this.trailing,
  });
  final String title;
  final String subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => MobileCollapsibleNavigation(
    title: 'Управление разделом',
    summary: title,
    child: Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
      decoration: const BoxDecoration(
        color: Color(0xFF101823),
        border: Border(bottom: BorderSide(color: Color(0xFF253348))),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 12,
        spacing: 20,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 650),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: Color(0xFF8FA4C2)),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    ),
  );
}

final class _CollectionPage extends StatelessWidget {
  const _CollectionPage({
    required this.children,
    required this.emptyIcon,
    required this.emptyText,
    required this.onAdd,
    this.showAddButton = true,
  });
  final List<Widget> children;
  final IconData emptyIcon;
  final String emptyText;
  final VoidCallback onAdd;
  final bool showAddButton;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(22),
    children: [
      if (showAddButton)
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Добавить юридическое лицо'),
          ),
        ),
      if (showAddButton) const SizedBox(height: 16),
      if (children.isEmpty)
        _EmptyState(icon: emptyIcon, text: emptyText)
      else
        ...children,
    ],
  );
}

final class _EntityCard extends StatelessWidget {
  const _EntityCard({
    required this.icon,
    required this.title,
    required this.badge,
    required this.lines,
    this.onEdit,
    this.onDelete,
  });
  final IconData icon;
  final String title;
  final String badge;
  final List<String?> lines;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF1A355A),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(11),
              child: Icon(icon, color: const Color(0xFF6EA3FF)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 9,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Chip(
                      label: Text(badge, style: const TextStyle(fontSize: 10)),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  lines
                      .whereType<String>()
                      .where((value) => value.trim().isNotEmpty)
                      .join(' · '),
                  style: const TextStyle(
                    color: Color(0xFF91A6C2),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (onEdit != null)
            IconButton(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Редактировать',
            ),
          if (onDelete != null)
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
              color: const Color(0xFFFF6F86),
              tooltip: 'Удалить',
            ),
        ],
      ),
    ),
  );
}

final class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(60),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 50, color: const Color(0xFF547093)),
          const SizedBox(height: 12),
          Text(text, style: const TextStyle(color: Color(0xFF8FA4C2))),
        ],
      ),
    ),
  );
}

final class _NoAccessState extends StatelessWidget {
  const _NoAccessState({required this.section});

  final String section;

  @override
  Widget build(BuildContext context) => _EmptyState(
    icon: Icons.lock_outline,
    text: 'У вашей роли нет доступа к $section.',
  );
}

Future<void> _editLegalEntity(
  BuildContext context,
  CompanyController controller,
  LegalEntityModel? source,
) async {
  final item = source == null
      ? LegalEntityModel(id: '', name: '', companyType: 'ООО')
      : LegalEntityModel.fromJson({...source.toJson(), 'id': source.id});
  await showDialog<void>(
    context: context,
    builder: (context) => _withoutAccessibilityAnnouncements(
      context,
      _LegalEntityDialog(
        item: item,
        controller: controller,
        create: source == null,
      ),
    ),
  );
}

Future<void> _editClient(
  BuildContext context,
  CompanyController controller,
  CompanyClientModel? source,
) async {
  final item = source == null
      ? CompanyClientModel(id: '', name: '')
      : CompanyClientModel.fromJson({...source.toJson(), 'id': source.id});
  await showDialog<void>(
    context: context,
    builder: (context) => _withoutAccessibilityAnnouncements(
      context,
      _ClientDialog(item: item, controller: controller, create: source == null),
    ),
  );
}

Future<void> _createEmployee(
  BuildContext context,
  CompanyController controller,
) async {
  await showDialog<void>(
    context: context,
    builder: (context) => _withoutAccessibilityAnnouncements(
      context,
      _EmployeeDialog(
        roles: controller.roles,
        employees: controller.employees,
        controller: controller,
      ),
    ),
  );
}

Future<void> _editEmployee(
  BuildContext context,
  CompanyController controller,
  EmployeeModel source,
) async {
  await showDialog<void>(
    context: context,
    builder: (context) => _withoutAccessibilityAnnouncements(
      context,
      _EditEmployeeDialog(
        source: source,
        roles: controller.roles,
        employees: controller.employees,
        controller: controller,
      ),
    ),
  );
}

Future<void> _editRole(
  BuildContext context,
  CompanyController controller,
  CompanyRoleModel? source,
) async {
  await showDialog<void>(
    context: context,
    builder: (context) => _withoutAccessibilityAnnouncements(
      context,
      _RoleDialog(
        source: source,
        roles: controller.roles,
        employees: controller.employees,
        permissions: controller.permissions,
        controller: controller,
      ),
    ),
  );
}

Widget _withoutAccessibilityAnnouncements(BuildContext context, Widget child) =>
    MediaQuery(
      data: MediaQuery.of(context).copyWith(supportsAnnounce: false),
      child: child,
    );

final class _LegalEntityDialog extends StatefulWidget {
  const _LegalEntityDialog({
    required this.item,
    required this.controller,
    required this.create,
  });
  final LegalEntityModel item;
  final CompanyController controller;
  final bool create;
  @override
  State<_LegalEntityDialog> createState() => _LegalEntityDialogState();
}

final class _LegalEntityDialogState extends State<_LegalEntityDialog> {
  final key = GlobalKey<FormState>();
  bool submitting = false;
  String? submitError;
  late String vatRatesInput;

  @override
  void initState() {
    super.initState();
    widget.item.companyType = _normalizeLegalType(widget.item.companyType);
    vatRatesInput = _formatVatRates(widget.item.vatRates);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
    contentPadding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
    title: Text(
      widget.item.id.isEmpty
          ? 'Новое юридическое лицо'
          : 'Редактирование юридического лица',
    ),
    content: SizedBox(
      width: 840,
      child: Form(
        key: key,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _formField(
                'Короткое название',
                widget.item.name,
                (value) => widget.item.name = value,
                required: true,
              ),
              const SizedBox(height: 12),
              AppSelectField<String>(
                value: widget.item.companyType,
                label: 'Тип компании',
                options: const [
                  AppSelectOption(value: 'ooo', label: 'ООО'),
                  AppSelectOption(value: 'ip', label: 'ИП'),
                ],
                onChanged: (value) => setState(() {
                  widget.item.companyType = value ?? 'ooo';
                  if (widget.item.companyType == 'ip') widget.item.kpp = null;
                }),
              ),
              const SizedBox(height: 12),
              _formField(
                widget.item.companyType == 'ip'
                    ? 'ФИО индивидуального предпринимателя'
                    : 'Юридическое название',
                widget.item.legalName ?? '',
                (value) => widget.item.legalName = value,
                required: true,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _digitsField(
                      'ИНН',
                      widget.item.inn ?? '',
                      (value) => widget.item.inn = value,
                      required: true,
                      lengths: widget.item.companyType == 'ip'
                          ? const [12]
                          : const [10],
                    ),
                  ),
                  if (widget.item.companyType != 'ip') ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: _digitsField(
                        'КПП',
                        widget.item.kpp ?? '',
                        (value) => widget.item.kpp = value,
                        required: true,
                        lengths: const [9],
                      ),
                    ),
                  ],
                  const SizedBox(width: 10),
                  Expanded(
                    child: _digitsField(
                      widget.item.companyType == 'ip' ? 'ОГРНИП' : 'ОГРН',
                      widget.item.ogrn ?? '',
                      (value) => widget.item.ogrn = value,
                      required: true,
                      lengths: widget.item.companyType == 'ip'
                          ? const [15]
                          : const [13],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _formField(
                'Адрес',
                widget.item.address ?? '',
                (value) => widget.item.address = value,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _phoneField(
                      'Телефон',
                      widget.item.phone ?? '',
                      (value) => widget.item.phone = value,
                      required: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _emailField(
                      'Email',
                      widget.item.email ?? '',
                      (value) => widget.item.email = value,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _formField(
                'Сайт',
                widget.item.website ?? '',
                (value) => widget.item.website = value,
                validator: _websiteValidator,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _formField(
                      'Директор',
                      widget.item.directorName ?? '',
                      (value) => widget.item.directorName = value,
                      required: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _formField(
                      'Подписант',
                      widget.item.signatoryName ?? '',
                      (value) => widget.item.signatoryName = value,
                      required: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _formField(
                      'Должность подписанта',
                      widget.item.signatoryTitle ?? '',
                      (value) => widget.item.signatoryTitle = value,
                      required: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _formField(
                'Банк',
                widget.item.bankName ?? '',
                (value) => widget.item.bankName = value,
                required: true,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _digitsField(
                      'БИК',
                      widget.item.bankBik ?? '',
                      (value) => widget.item.bankBik = value,
                      required: true,
                      lengths: const [9],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _digitsField(
                      'Расчётный счёт',
                      widget.item.bankAccount ?? '',
                      (value) => widget.item.bankAccount = value,
                      required: true,
                      lengths: const [20],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _digitsField(
                      'Корреспондентский счёт',
                      widget.item.corrAccount ?? '',
                      (value) => widget.item.corrAccount = value,
                      required: true,
                      lengths: const [20],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _formField(
                'Вводный текст по умолчанию',
                widget.item.introDefault ?? '',
                (value) => widget.item.introDefault = value,
                maximumLength: 2000,
              ),
              const SizedBox(height: 12),
              _formField(
                'Дополнительный текст по умолчанию',
                widget.item.footerDefault ?? '',
                (value) => widget.item.footerDefault = value,
                maximumLength: 2000,
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: vatRatesInput,
                onChanged: (value) => vatRatesInput = value,
                validator: _validateVatRates,
                decoration: const InputDecoration(
                  labelText: 'Доступные ставки НДС',
                  helperText: 'Укажите через запятую: Без НДС, 5, 10, 20',
                ),
              ),
              CheckboxListTile(
                value: widget.item.isDefault,
                onChanged: (value) =>
                    setState(() => widget.item.isDefault = value ?? false),
                title: const Text('Исполнитель по умолчанию'),
                contentPadding: EdgeInsets.zero,
              ),
              if (submitError != null) ...[
                const SizedBox(height: 10),
                _DialogError(message: submitError!),
              ],
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: submitting ? null : () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: submitting ? null : _submit,
        child: submitting
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Сохранить'),
      ),
    ],
  );

  Future<void> _submit() async {
    if (key.currentState?.validate() != true) return;
    widget.item.vatRates = _parseVatRates(vatRatesInput)!;
    setState(() {
      submitting = true;
      submitError = null;
    });
    final saved = await widget.controller.saveLegalEntity(
      widget.item,
      create: widget.create,
    );
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      submitting = false;
      submitError =
          widget.controller.error ?? 'Не удалось сохранить юридическое лицо.';
    });
  }
}

List<double?>? _parseVatRates(String value) {
  final result = <double?>[];
  for (final rawToken in value.split(',')) {
    final token = rawToken.trim();
    if (token.isEmpty) return null;
    if (token.toLowerCase() == 'без ндс') {
      result.add(null);
      continue;
    }
    final rate = double.tryParse(token.replaceAll('%', '').trim());
    if (rate == null || rate < 0 || rate > 100) return null;
    result.add(rate);
  }
  return result.isEmpty ||
          result.length > 20 ||
          result.toSet().length != result.length
      ? null
      : result;
}

String _formatVatRates(List<double?> rates) => rates
    .map((rate) {
      if (rate == null) return 'Без НДС';
      return rate == rate.roundToDouble()
          ? rate.toInt().toString()
          : rate.toString();
    })
    .join(', ');

String? _validateVatRates(String? value) {
  return value != null && _parseVatRates(value) != null
      ? null
      : 'Укажите уникальные ставки от 0 до 100 через запятую; для работы без НДС напишите «Без НДС»';
}

final class _ClientDialog extends StatefulWidget {
  const _ClientDialog({
    required this.item,
    required this.controller,
    required this.create,
  });
  final CompanyClientModel item;
  final CompanyController controller;
  final bool create;

  @override
  State<_ClientDialog> createState() => _ClientDialogState();
}

final class _ClientDialogState extends State<_ClientDialog> {
  final formKey = GlobalKey<FormState>();
  CompanyClientModel get item => widget.item;
  bool submitting = false;
  String? submitError;

  @override
  Widget build(BuildContext context) => AlertDialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
    title: Text(item.id.isEmpty ? 'Новый клиент' : 'Редактирование клиента'),
    content: SizedBox(
      width: 780,
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppSelectField<String>(
                  value: item.companyType,
                  label: 'Тип клиента',
                  options: const [
                    AppSelectOption(value: 'person', label: 'Физическое лицо'),
                    AppSelectOption(value: 'ip', label: 'ИП'),
                    AppSelectOption(value: 'ooo', label: 'ООО / организация'),
                  ],
                  onChanged: (value) => setState(() {
                    item.companyType = value ?? 'person';
                    if (item.companyType != 'ooo') item.kpp = null;
                  }),
                ),
                const SizedBox(height: 12),
                _formField(
                  item.companyType == 'person'
                      ? 'ФИО'
                      : item.companyType == 'ip'
                      ? 'Название ИП'
                      : 'Название компании',
                  item.companyName ?? item.name,
                  (value) {
                    item.companyName = value;
                    item.name = value;
                    if (item.companyType != 'person') item.legalName = value;
                  },
                  required: true,
                ),
                if (item.companyType == 'person') ...[
                  const SizedBox(height: 12),
                  _DialogFieldGrid(
                    columns: 2,
                    children: [
                      _phoneField(
                        'Телефон',
                        item.phone ?? '',
                        (value) => item.phone = value,
                        required: true,
                      ),
                      _emailField(
                        'Email',
                        item.email ?? '',
                        (value) => item.email = value,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _DialogFieldGrid(
                    columns: 3,
                    children: [
                      _digitsField(
                        'Серия паспорта',
                        item.passportSeries ?? '',
                        (value) => item.passportSeries = value,
                        lengths: const [4],
                        required: true,
                      ),
                      _digitsField(
                        'Номер паспорта',
                        item.passportNumber ?? '',
                        (value) => item.passportNumber = value,
                        lengths: const [6],
                        required: true,
                      ),
                      _formField(
                        'Кем выдан',
                        item.passportIssuedBy ?? '',
                        (value) => item.passportIssuedBy = value,
                        required: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _formField(
                    'Адрес регистрации',
                    item.address ?? '',
                    (value) => item.address = value,
                    maximumLength: 500,
                    maxLines: 3,
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  _DialogFieldGrid(
                    columns: item.companyType == 'ip' ? 2 : 3,
                    children: [
                      _digitsField(
                        'ИНН',
                        item.inn ?? '',
                        (value) => item.inn = value,
                        lengths: item.companyType == 'ip'
                            ? const [12]
                            : const [10],
                        required: true,
                      ),
                      if (item.companyType != 'ip')
                        _digitsField(
                          'КПП',
                          item.kpp ?? '',
                          (value) => item.kpp = value,
                          lengths: const [9],
                          required: true,
                        ),
                      _digitsField(
                        item.companyType == 'ip' ? 'ОГРНИП' : 'ОГРН',
                        item.ogrn ?? '',
                        (value) => item.ogrn = value,
                        lengths: item.companyType == 'ip'
                            ? const [15]
                            : const [13],
                        required: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _DialogFieldGrid(
                    columns: 3,
                    children: [
                      _phoneField(
                        'Телефон',
                        item.phone ?? '',
                        (value) => item.phone = value,
                        required: true,
                      ),
                      _emailField(
                        'Email',
                        item.email ?? '',
                        (value) => item.email = value,
                      ),
                      _formField(
                        'Банк',
                        item.bankName ?? '',
                        (value) => item.bankName = value,
                        required: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _digitsField(
                    'БИК',
                    item.bankBik ?? '',
                    (value) => item.bankBik = value,
                    lengths: const [9],
                    required: true,
                  ),
                  const SizedBox(height: 12),
                  _formField(
                    'Юридический адрес',
                    item.address ?? '',
                    (value) => item.address = value,
                    maximumLength: 500,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  _DialogFieldGrid(
                    columns: 2,
                    children: [
                      _digitsField(
                        'Расчётный счёт',
                        item.bankAccount ?? '',
                        (value) => item.bankAccount = value,
                        lengths: const [20],
                        required: true,
                      ),
                      _digitsField(
                        'Корреспондентский счёт',
                        item.corrAccount ?? '',
                        (value) => item.corrAccount = value,
                        lengths: const [20],
                        required: true,
                      ),
                    ],
                  ),
                ],
                if (submitError != null) ...[
                  const SizedBox(height: 10),
                  _DialogError(message: submitError!),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: submitting ? null : () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: submitting ? null : _submit,
        child: submitting
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Сохранить'),
      ),
    ],
  );

  Future<void> _submit() async {
    if (formKey.currentState?.validate() != true) return;
    final primaryName = (item.companyName?.trim().isNotEmpty ?? false)
        ? item.companyName!.trim()
        : item.name.trim();
    item.name = primaryName;
    item.companyName = primaryName;
    if (item.companyType != 'person') item.legalName = item.name;
    setState(() {
      submitting = true;
      submitError = null;
    });
    final saved = await widget.controller.saveClient(
      item,
      create: widget.create,
    );
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      submitting = false;
      submitError = widget.controller.error ?? 'Не удалось сохранить клиента.';
    });
  }
}

final class _EmployeeDialog extends StatefulWidget {
  const _EmployeeDialog({
    required this.roles,
    required this.employees,
    required this.controller,
  });
  final List<CompanyRoleModel> roles;
  final List<EmployeeModel> employees;
  final CompanyController controller;
  @override
  State<_EmployeeDialog> createState() => _EmployeeDialogState();
}

final class _EmployeeDialogState extends State<_EmployeeDialog> {
  final key = GlobalKey<FormState>();
  String login = '',
      name = '',
      password = '',
      email = '',
      phone = '',
      telegram = '';
  String? roleId, supervisorId;
  bool submitting = false;
  String? submitError;
  @override
  Widget build(BuildContext context) {
    roleId ??= widget.roles
        .where((role) => role.name != 'Директор')
        .firstOrNull
        ?.id;
    final supervisors = widget.employees.where((employee) {
      final role = widget.roles
          .where((item) => item.id == employee.roleId)
          .firstOrNull;
      return role?.subordinateRoleIds.contains(roleId) ?? false;
    }).toList();
    return AlertDialog(
      title: const Text('Новый сотрудник'),
      content: SizedBox(
        width: 580,
        child: Form(
          key: key,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _formField(
                  'ФИО',
                  name,
                  (value) => name = value,
                  required: true,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _formField(
                        'Логин',
                        login,
                        (value) => login = value,
                        required: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _formField(
                        'Одноразовый пароль',
                        password,
                        (value) => password = value,
                        required: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                AppSelectField<String>(
                  value: roleId,
                  label: 'Роль',
                  options: [
                    for (final role in widget.roles.where(
                      (role) => role.name != 'Директор',
                    ))
                      AppSelectOption(value: role.id, label: role.name),
                  ],
                  onChanged: (value) => setState(() {
                    roleId = value;
                    supervisorId = null;
                  }),
                ),
                const SizedBox(height: 12),
                AppSelectField<String>(
                  value: supervisorId,
                  label: 'Руководитель',
                  options: [
                    const AppSelectOption<String>(
                      value: null,
                      label: 'Без руководителя',
                    ),
                    for (final employee in supervisors)
                      AppSelectOption(
                        value: employee.membershipId,
                        label: '${employee.displayName} · ${employee.roleName}',
                      ),
                  ],
                  onChanged: (value) => setState(() => supervisorId = value),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _emailField(
                        'Email',
                        email,
                        (value) => email = value,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _phoneField(
                        'Телефон',
                        phone,
                        (value) => phone = value,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _formField('Telegram', telegram, (value) => telegram = value),
                if (submitError != null) ...[
                  const SizedBox(height: 10),
                  _DialogError(message: submitError!),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: submitting ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: roleId == null || submitting ? null : _submit,
          child: submitting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Создать'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (key.currentState?.validate() != true || roleId == null) return;
    setState(() {
      submitting = true;
      submitError = null;
    });
    final saved = await widget.controller.createEmployee(
      CreateEmployeeModel(
        login: login,
        displayName: name,
        temporaryPassword: password,
        roleId: roleId!,
        supervisorMembershipId: supervisorId,
        email: email,
        phone: phone,
        telegram: telegram,
      ),
    );
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      submitting = false;
      submitError = widget.controller.error ?? 'Не удалось создать сотрудника.';
    });
  }
}

final class _EditEmployeeDialog extends StatefulWidget {
  const _EditEmployeeDialog({
    required this.source,
    required this.roles,
    required this.employees,
    required this.controller,
  });

  final EmployeeModel source;
  final List<CompanyRoleModel> roles;
  final List<EmployeeModel> employees;
  final CompanyController controller;

  @override
  State<_EditEmployeeDialog> createState() => _EditEmployeeDialogState();
}

final class _EditEmployeeDialogState extends State<_EditEmployeeDialog> {
  final key = GlobalKey<FormState>();
  late String name;
  late String roleId;
  late String? supervisorId;
  late String email;
  late String phone;
  late String telegram;
  late bool isActive;
  bool submitting = false;
  String? submitError;

  @override
  void initState() {
    super.initState();
    name = widget.source.displayName;
    roleId = widget.source.roleId;
    supervisorId = widget.source.supervisorMembershipId;
    email = widget.source.email ?? '';
    phone = widget.source.phone ?? '';
    telegram = widget.source.telegram ?? '';
    isActive = widget.source.isActive;
  }

  @override
  Widget build(BuildContext context) {
    final supervisors = widget.employees.where((employee) {
      if (employee.membershipId == widget.source.membershipId) return false;
      final role = widget.roles
          .where((item) => item.id == employee.roleId)
          .firstOrNull;
      return role?.subordinateRoleIds.contains(roleId) ?? false;
    }).toList();
    if (supervisorId != null &&
        supervisors.every(
          (employee) => employee.membershipId != supervisorId,
        )) {
      supervisorId = null;
    }

    return AlertDialog(
      title: Text('Сотрудник · ${widget.source.login}'),
      content: SizedBox(
        width: 580,
        child: Form(
          key: key,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _formField(
                  'ФИО',
                  name,
                  (value) => name = value,
                  required: true,
                ),
                const SizedBox(height: 12),
                AppSelectField<String>(
                  value: roleId,
                  label: 'Роль',
                  options: [
                    for (final role in widget.roles.where(
                      (role) =>
                          !role.isSystem || role.id == widget.source.roleId,
                    ))
                      AppSelectOption(value: role.id, label: role.name),
                  ],
                  onChanged: widget.source.isDirector
                      ? null
                      : (value) => setState(() {
                          if (value == null) return;
                          roleId = value;
                          supervisorId = null;
                        }),
                ),
                const SizedBox(height: 12),
                AppSelectField<String>(
                  value: supervisorId,
                  label: 'Руководитель',
                  options: [
                    const AppSelectOption<String>(
                      value: null,
                      label: 'Без руководителя',
                    ),
                    for (final employee in supervisors)
                      AppSelectOption(
                        value: employee.membershipId,
                        label: '${employee.displayName} · ${employee.roleName}',
                      ),
                  ],
                  onChanged: widget.source.isDirector
                      ? null
                      : (value) => setState(() => supervisorId = value),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _emailField(
                        'Email',
                        email,
                        (value) => email = value,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _phoneField(
                        'Телефон',
                        phone,
                        (value) => phone = value,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _formField('Telegram', telegram, (value) => telegram = value),
                const SizedBox(height: 6),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: isActive,
                  onChanged: widget.source.isDirector
                      ? null
                      : (value) => setState(() => isActive = value),
                  title: const Text('Учётная запись активна'),
                  subtitle: Text(
                    'Общий срок организации: ${_date(widget.source.activeUntil)}',
                  ),
                ),
                if (submitError != null) ...[
                  const SizedBox(height: 10),
                  _DialogError(message: submitError!),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: submitting ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: submitting ? null : _submit,
          child: submitting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Сохранить'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (key.currentState?.validate() != true) return;
    setState(() {
      submitting = true;
      submitError = null;
    });
    final saved = await widget.controller.updateEmployee(
      widget.source.membershipId,
      UpdateEmployeeModel(
        displayName: name,
        roleId: roleId,
        supervisorMembershipId: supervisorId,
        isActive: isActive,
        email: email,
        phone: phone,
        telegram: telegram,
      ),
    );
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      submitting = false;
      submitError =
          widget.controller.error ?? 'Не удалось сохранить сотрудника.';
    });
  }
}

final class _RoleDialog extends StatefulWidget {
  const _RoleDialog({
    required this.source,
    required this.roles,
    required this.employees,
    required this.permissions,
    required this.controller,
  });
  final CompanyRoleModel? source;
  final List<CompanyRoleModel> roles;
  final List<EmployeeModel> employees;
  final List<CompanyPermissionModel> permissions;
  final CompanyController controller;
  @override
  State<_RoleDialog> createState() => _RoleDialogState();
}

final class _RoleDialogState extends State<_RoleDialog> {
  late String name;
  late Set<String> permissions;
  late Set<String> subordinates;
  late String cardVisibilityMode;
  late Set<String> cardVisibilityMembershipIds;
  bool submitting = false;
  String? submitError;
  @override
  void initState() {
    super.initState();
    name = widget.source?.name ?? '';
    permissions = {...?widget.source?.permissionCodes};
    subordinates = {...?widget.source?.subordinateRoleIds};
    cardVisibilityMode = widget.source?.cardVisibilityMode ?? 'own';
    cardVisibilityMembershipIds = {
      ...?widget.source?.cardVisibilityMembershipIds,
    };
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<CompanyPermissionModel>>{};
    for (final permission in widget.permissions) {
      groups.putIfAbsent(permission.groupName, () => []).add(permission);
    }
    return AlertDialog(
      title: Text(widget.source == null ? 'Новая роль' : 'Редактирование роли'),
      content: SizedBox(
        width: 660,
        height: 620,
        child: Column(
          children: [
            _formField(
              'Название роли',
              name,
              (value) => setState(() => name = value),
              required: true,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  const Text(
                    'Права пространств',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  for (final group in groups.entries)
                    _RolePermissionGroup(
                      name: group.key,
                      permissions: group.value,
                      selected: permissions,
                      onChanged: (code, selected) => setState(
                        () => selected
                            ? permissions.add(code)
                            : permissions.remove(code),
                      ),
                    ),
                  const SizedBox(height: 12),
                  const Text(
                    'Видимость карточек',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  AppSelectField<String>(
                    value: cardVisibilityMode,
                    label: 'Какие карточки видит пользователь',
                    options: const [
                      AppSelectOption(value: 'own', label: 'Только свои'),
                      AppSelectOption(value: 'all', label: 'Все карточки'),
                      AppSelectOption(
                        value: 'subordinates',
                        label: 'Свои и подчинённых',
                      ),
                      AppSelectOption(
                        value: 'specific',
                        label: 'Свои и выбранных сотрудников',
                      ),
                    ],
                    onChanged: (value) => setState(() {
                      cardVisibilityMode = value ?? 'own';
                      if (cardVisibilityMode != 'specific') {
                        cardVisibilityMembershipIds.clear();
                      }
                    }),
                  ),
                  if (cardVisibilityMode == 'specific') ...[
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D1724),
                        border: Border.all(color: const Color(0xFF263A52)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          for (final employee in widget.employees)
                            CheckboxListTile(
                              dense: true,
                              controlAffinity: ListTileControlAffinity.leading,
                              value: cardVisibilityMembershipIds.contains(
                                employee.membershipId,
                              ),
                              title: Text(employee.displayName),
                              subtitle: Text(employee.roleName),
                              onChanged: (value) => setState(
                                () => value == true
                                    ? cardVisibilityMembershipIds.add(
                                        employee.membershipId,
                                      )
                                    : cardVisibilityMembershipIds.remove(
                                        employee.membershipId,
                                      ),
                              ),
                            ),
                          if (widget.employees.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(14),
                              child: Text('Сотрудники ещё не созданы.'),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Text(
                    'Подчинённые роли',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  for (final role in widget.roles.where(
                    (role) => !role.isSystem && role.id != widget.source?.id,
                  ))
                    CheckboxListTile(
                      value: subordinates.contains(role.id),
                      onChanged: (value) => setState(
                        () => value == true
                            ? subordinates.add(role.id)
                            : subordinates.remove(role.id),
                      ),
                      title: Text(role.name),
                      dense: true,
                    ),
                  if (submitError != null) ...[
                    const SizedBox(height: 10),
                    _DialogError(message: submitError!),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: submitting ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: name.trim().length < 2 || submitting ? null : _submit,
          child: submitting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Сохранить'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    setState(() {
      submitting = true;
      submitError = null;
    });
    final saved = await widget.controller.saveRole(
      CompanyRoleModel(
        id: widget.source?.id ?? '',
        name: name.trim(),
        isSystem: false,
        permissionCodes: permissions.toList(),
        subordinateRoleIds: subordinates.toList(),
        cardVisibilityMode: cardVisibilityMode,
        cardVisibilityMembershipIds: cardVisibilityMembershipIds.toList(),
      ),
      create: widget.source == null,
    );
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      submitting = false;
      submitError = widget.controller.error ?? 'Не удалось сохранить роль.';
    });
  }
}

String _cardVisibilityLabel(String mode) => switch (mode) {
  'all' => 'все карточки',
  'subordinates' => 'свои и подчинённых',
  'specific' => 'свои и выбранных сотрудников',
  _ => 'только свои карточки',
};

/// Визуально отделяет пространство прав от вложенных разрешений и сохраняет
/// компактное раскрытие длинного списка.
final class _RolePermissionGroup extends StatelessWidget {
  const _RolePermissionGroup({
    required this.name,
    required this.permissions,
    required this.selected,
    required this.onChanged,
  });

  final String name;
  final List<CompanyPermissionModel> permissions;
  final Set<String> selected;
  final void Function(String code, bool selected) onChanged;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      color: const Color(0xFF101A28),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFF2B405C)),
    ),
    clipBehavior: Clip.antiAlias,
    child: _SafeExpansionTile(
      initiallyExpanded: true,
      leading: const DecoratedBox(
        decoration: BoxDecoration(
          color: Color(0xFF17345D),
          shape: BoxShape.circle,
        ),
        child: SizedBox.square(
          dimension: 32,
          child: Icon(
            Icons.space_dashboard_outlined,
            size: 17,
            color: Color(0xFF78A9FF),
          ),
        ),
      ),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text('${permissions.length} разрешений'),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0xFF0B131E),
          border: Border(top: BorderSide(color: Color(0xFF2B405C))),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
          child: Column(
            children: [
              for (var index = 0; index < permissions.length; index++) ...[
                CheckboxListTile(
                  value: selected.contains(permissions[index].code),
                  onChanged: (value) =>
                      onChanged(permissions[index].code, value == true),
                  title: Text(permissions[index].name),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  dense: true,
                ),
                if (index < permissions.length - 1)
                  const Divider(height: 1, color: Color(0xFF1D2A3D)),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

/// Раскрываемая панель без системного announcement, который в текущем Flutter
/// передаёт Windows accessibility-плагину некорректный `viewId`.
final class _SafeExpansionTile extends StatefulWidget {
  const _SafeExpansionTile({
    required this.title,
    required this.child,
    this.subtitle,
    this.leading,
    this.trailing,
    this.initiallyExpanded = false,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final Widget child;
  final bool initiallyExpanded;

  @override
  State<_SafeExpansionTile> createState() => _SafeExpansionTileState();
}

final class _SafeExpansionTileState extends State<_SafeExpansionTile> {
  late bool expanded;

  @override
  void initState() {
    super.initState();
    expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      InkWell(
        onTap: () => setState(() => expanded = !expanded),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              if (widget.leading != null) ...[
                widget.leading!,
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    widget.title,
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 3),
                      DefaultTextStyle.merge(
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF8FA4C2),
                        ),
                        child: widget.subtitle!,
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.trailing != null) ...[
                widget.trailing!,
                const SizedBox(width: 8),
              ],
              ExcludeSemantics(
                child: AnimatedRotation(
                  turns: expanded ? .5 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: const Icon(Icons.keyboard_arrow_down),
                ),
              ),
            ],
          ),
        ),
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 160),
        alignment: Alignment.topCenter,
        child: expanded ? widget.child : const SizedBox.shrink(),
      ),
    ],
  );
}

/// Ошибка сохранения остаётся внутри открытой формы и не уничтожает ввод.
final class _DialogError extends StatelessWidget {
  const _DialogError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) =>
      AutoDismissNotice(message: message, child: _content(context));

  Widget _content(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFF3A1722),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFF9B3C59)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline, size: 18, color: Color(0xFFFF809D)),
        const SizedBox(width: 8),
        Expanded(child: Text(message)),
      ],
    ),
  );
}

Widget _formField(
  String label,
  String value,
  ValueChanged<String> changed, {
  bool required = false,
  int maximumLength = 500,
  int maxLines = 1,
  String? Function(String?)? validator,
}) => TextFormField(
  key: ValueKey(label),
  initialValue: value,
  onChanged: changed,
  enableInteractiveSelection: true,
  inputFormatters: [LengthLimitingTextInputFormatter(maximumLength)],
  maxLines: maxLines,
  validator: (value) {
    final normalized = value?.trim() ?? '';
    if (required && normalized.length < 2) {
      return 'Введите не менее двух символов';
    }
    return validator?.call(value);
  },
  decoration: InputDecoration(labelText: required ? '$label *' : label),
);

Widget _digitsField(
  String label,
  String value,
  ValueChanged<String> changed, {
  List<int> lengths = const [],
  bool required = false,
}) => TextFormField(
  key: ValueKey(label),
  initialValue: value,
  onChanged: changed,
  enableInteractiveSelection: true,
  keyboardType: TextInputType.number,
  inputFormatters: [
    FilteringTextInputFormatter.digitsOnly,
    if (lengths.isNotEmpty)
      LengthLimitingTextInputFormatter(lengths.reduce((a, b) => a > b ? a : b)),
  ],
  validator: (value) {
    final normalized = value?.trim() ?? '';
    if (required && normalized.isEmpty) return 'Заполните поле «$label»';
    if (normalized.isEmpty ||
        lengths.isEmpty ||
        lengths.contains(normalized.length)) {
      return null;
    }
    return lengths.length == 1
        ? '$label должен содержать ${lengths.first} цифр'
        : '$label имеет неверную длину';
  },
  decoration: InputDecoration(labelText: required ? '$label *' : label),
);

Widget _emailField(String label, String value, ValueChanged<String> changed) =>
    TextFormField(
      key: ValueKey(label),
      initialValue: value,
      onChanged: changed,
      enableInteractiveSelection: true,
      keyboardType: TextInputType.emailAddress,
      validator: (value) {
        final normalized = value?.trim() ?? '';
        if (normalized.isEmpty) return null;
        return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(normalized)
            ? null
            : 'Введите корректный email';
      },
      decoration: InputDecoration(labelText: label),
    );

Widget _phoneField(
  String label,
  String value,
  ValueChanged<String> changed, {
  bool required = false,
}) => TextFormField(
  key: ValueKey(label),
  initialValue: _formatRussianPhone(value),
  onChanged: changed,
  enableInteractiveSelection: true,
  keyboardType: TextInputType.phone,
  inputFormatters: const [_RussianPhoneInputFormatter()],
  validator: (value) {
    final digits = _onlyDigits(value ?? '');
    if (digits.isEmpty) return required ? 'Укажите телефон' : null;
    return digits.length == 11 && digits.startsWith('7')
        ? null
        : 'Введите телефон в формате +7 (999) 123-45-67';
  },
  decoration: InputDecoration(
    labelText: required ? '$label *' : label,
    hintText: '+7 (___) ___-__-__',
  ),
);

/// Адаптивная сетка полей сохраняет широкую форму на desktop и не создаёт
/// горизонтального переполнения на небольших окнах.
final class _DialogFieldGrid extends StatelessWidget {
  const _DialogFieldGrid({required this.children, required this.columns});

  final List<Widget> children;
  final int columns;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final actualColumns = constraints.maxWidth < 640 ? 1 : columns;
      const gap = 10.0;
      final width =
          (constraints.maxWidth - gap * (actualColumns - 1)) / actualColumns;
      return Wrap(
        spacing: gap,
        runSpacing: 12,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

String? _websiteValidator(String? value) {
  final normalized = value?.trim() ?? '';
  if (normalized.isEmpty) return null;
  final uri = Uri.tryParse(normalized);
  return uri != null &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.contains('.')
      ? null
      : 'Введите адрес сайта с http:// или https://';
}

String _onlyDigits(String value) => value.replaceAll(RegExp(r'\D'), '');

String _formatRussianPhone(String value) {
  var digits = _onlyDigits(value);
  if (digits.isEmpty) return '';
  if (digits.startsWith('8')) digits = '7${digits.substring(1)}';
  if (!digits.startsWith('7')) digits = '7$digits';
  digits = digits.substring(0, digits.length.clamp(0, 11));

  final buffer = StringBuffer('+7');
  if (digits.length > 1) {
    buffer.write(' (${digits.substring(1, digits.length.clamp(1, 4))}');
  }
  if (digits.length >= 4) buffer.write(')');
  if (digits.length > 4) {
    buffer.write(' ${digits.substring(4, digits.length.clamp(4, 7))}');
  }
  if (digits.length > 7) {
    buffer.write('-${digits.substring(7, digits.length.clamp(7, 9))}');
  }
  if (digits.length > 9) buffer.write('-${digits.substring(9)}');
  return buffer.toString();
}

/// Приводит ввод российского номера к единому виду и не допускает лишние
/// символы или цифры сверх полной маски.
final class _RussianPhoneInputFormatter extends TextInputFormatter {
  const _RussianPhoneInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = _formatRussianPhone(newValue.text);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

String _normalizeLegalType(String value) =>
    switch (value.trim().toLowerCase()) {
      'ип' || 'ip' => 'ip',
      _ => 'ooo',
    };

String _partyTypeLabel(String value) => switch (value) {
  'person' => 'Физическое лицо',
  'ip' => 'ИП',
  _ => 'ООО',
};

String _permissionName(List<CompanyPermissionModel> values, String code) =>
    values.where((value) => value.code == code).firstOrNull?.name ??
    switch (code) {
      'system.full_access' => 'Полный доступ',
      _ => 'Неизвестное право',
    };
String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';

final class _CompanyError extends StatelessWidget {
  const _CompanyError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 42, color: Color(0xFFFF809D)),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Повторить'),
          ),
        ],
      ),
    ),
  );
}
