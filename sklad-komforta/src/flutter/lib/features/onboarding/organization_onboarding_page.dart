import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:sklad_komforta_app/core/widgets/mobile_collapsible_navigation.dart';
import 'package:flutter/services.dart';
import 'package:sklad_komforta_app/core/widgets/app_select_field.dart';
import 'package:sklad_komforta_app/features/auth/auth_controller.dart';
import 'package:sklad_komforta_app/features/company/company_profile_form.dart';
import 'package:sklad_komforta_app/features/company/configuration_edit_guard.dart';
import 'package:sklad_komforta_app/features/onboarding/onboarding_field_registry.dart';
import 'package:sklad_komforta_app/features/onboarding/onboarding_models.dart';

/// Полноэкранный девятишаговый мастер создания изолированной организации.
final class OrganizationOnboardingPage extends StatefulWidget {
  const OrganizationOnboardingPage({
    required this.controller,
    this.settingsDraft,
    this.settingsBusy = false,
    this.settingsError,
    this.onSettingsSave,
    this.onCategoryDeletionImpact,
    this.onCategoryDeletionApproved,
    this.onCategoryDeletionApprovalsDiscarded,
    this.configurationEditGuard,
    super.key,
  });

  /// Общий auth controller, владеющий tenant JWT и сетевым состоянием.
  final AuthController controller;

  /// Полная актуальная конфигурация для повторного редактирования организации.
  final OrganizationOnboardingDraft? settingsDraft;

  /// Состояние сохранения рабочего раздела «Компания».
  final bool settingsBusy;

  /// Ошибка сохранения или загрузки полной конфигурации.
  final String? settingsError;

  /// Сохраняет изменённую конфигурацию без повторной активации организации.
  final Future<bool> Function(
    OrganizationOnboardingDraft draft, {
    required List<String> deleteCategoryData,
  })?
  onSettingsSave;

  /// Проверяет рабочие данные до удаления категории из действующей организации.
  final Future<CategoryDeletionImpact?> Function(String categoryClientId)?
  onCategoryDeletionImpact;

  /// Передаёт подтверждение владельцу рабочего состояния, чтобы оно не
  /// потерялось при переходе пользователя в другой раздел приложения.
  final ValueChanged<String>? onCategoryDeletionApproved;

  /// Отзывает подтверждения, если пользователь отказался сохранять черновик.
  final VoidCallback? onCategoryDeletionApprovalsDiscarded;

  /// Связывает локальный редактор с навигацией рабочего пространства.
  final ConfigurationEditGuard? configurationEditGuard;

  @override
  State<OrganizationOnboardingPage> createState() =>
      _OrganizationOnboardingPageState();
}

final class _OrganizationOnboardingPageState
    extends State<OrganizationOnboardingPage> {
  static const _steps = [
    ('Компания', Icons.business_outlined),
    ('Канбаны', Icons.view_kanban_outlined),
    ('Каталог', Icons.inventory_2_outlined),
    ('Поля', Icons.view_column_outlined),
    ('Правила и расчёты', Icons.calculate_outlined),
    ('Зависимости', Icons.account_tree_outlined),
    ('Роли', Icons.admin_panel_settings_outlined),
    ('Справочники', Icons.menu_book_outlined),
    ('Проверка', Icons.fact_check_outlined),
  ];
  static const _permissions = {
    'catalog.view': 'Просмотр каталога',
    'catalog.manage': 'Управление каталогом',
    'company.view': 'Просмотр компании',
    'company.manage': 'Управление компанией',
    'quotes.view': 'Просмотр КП и ПКП',
    'quotes.manage': 'Управление КП и ПКП',
    'orders.view': 'Просмотр комплектаций',
    'orders.manage': 'Управление комплектациями',
    'documents.view': 'Просмотр документов',
    'documents.manage': 'Управление документами',
  };
  static const _workflowColors = [
    '#4D8DFF',
    '#22C55E',
    '#F59E0B',
    '#EF4444',
    '#8B5CF6',
    '#06B6D4',
  ];
  // Реквизиты юридических лиц редактируются в отдельной вкладке «Компания».
  // Здесь остаётся только рабочая конфигурация без второго источника данных.
  static const _settingsStepIndexes = [1, 2, 3, 4, 5, 7];
  late OrganizationOnboardingDraft draft;
  late String _savedDraftJson;
  late int step;
  final _companyFormKey = GlobalKey<FormState>();
  final Set<String> _collapsedWorkflowCodes = <String>{};
  final Set<String> _collapsedCategoryIds = <String>{};
  final Set<String> _collapsedFieldCategoryIds = <String>{};
  final Set<String> _collapsedWorkflowFieldCodes = <String>{};
  final Set<CategoryDependencyDraft> _collapsedDependencies =
      <CategoryDependencyDraft>{};
  final Set<OnboardingRoleDraft> _collapsedRoles = <OnboardingRoleDraft>{};
  final Set<DictionaryDraft> _collapsedDictionaries = <DictionaryDraft>{};
  final Set<String> _collapsedRules = <String>{};
  final Set<String> _collapsedPipelines = <String>{};
  final Set<CatalogSectionDraft> _expandedCatalogSections =
      <CatalogSectionDraft>{};
  final Set<String> _approvedCategoryDataDeletions = <String>{};
  final Set<String> _checkingCategoryIds = <String>{};

  bool get _settingsMode => widget.onSettingsSave != null;
  bool get _busy =>
      _settingsMode ? widget.settingsBusy : widget.controller.busy;
  String? get _error =>
      _settingsMode ? widget.settingsError : widget.controller.error;

  @override
  void initState() {
    super.initState();
    final source =
        widget.settingsDraft ??
        widget.controller.onboardingDraft ??
        OrganizationOnboardingDraft.initial();
    draft = _settingsMode ? _copyDraft(source) : source;
    _ensureFixedCatalogFields();
    _savedDraftJson = jsonEncode(draft.toJson());
    _collapseConfiguredBlocks();
    step = _settingsMode
        ? _settingsStepIndexes.first
        : draft.currentStep.clamp(1, 9) - 1;
    widget.configurationEditGuard?.attach(this, _confirmLeave);
  }

  @override
  void didUpdateWidget(covariant OrganizationOnboardingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(
      oldWidget.configurationEditGuard,
      widget.configurationEditGuard,
    )) {
      oldWidget.configurationEditGuard?.detach(this);
      widget.configurationEditGuard?.attach(this, _confirmLeave);
    }
    if (_settingsMode &&
        widget.settingsDraft != null &&
        !identical(oldWidget.settingsDraft, widget.settingsDraft) &&
        !widget.settingsBusy) {
      draft = _copyDraft(widget.settingsDraft!);
      _approvedCategoryDataDeletions.clear();
      _ensureFixedCatalogFields();
      _savedDraftJson = jsonEncode(draft.toJson());
      _collapseConfiguredBlocks();
    }
  }

  @override
  void dispose() {
    widget.configurationEditGuard?.detach(this);
    super.dispose();
  }

  OrganizationOnboardingDraft _copyDraft(OrganizationOnboardingDraft value) =>
      OrganizationOnboardingDraft.fromJson(value.toJson());

  bool get _hasUnsavedChanges => jsonEncode(draft.toJson()) != _savedDraftJson;

  void _discardUnsavedChanges() {
    widget.onCategoryDeletionApprovalsDiscarded?.call();
    draft = OrganizationOnboardingDraft.fromJson(
      jsonDecode(_savedDraftJson) as Map<String, dynamic>,
    );
    _approvedCategoryDataDeletions.clear();
    _ensureFixedCatalogFields();
    _collapseConfiguredBlocks();
  }

  Future<bool> _confirmLeave(BuildContext context) async {
    if (!_settingsMode || !_hasUnsavedChanges) return true;
    final leave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B)),
        title: const Text('Изменения не сохранены'),
        content: const Text(
          'Вы изменили настройки организации, но не сохранили их. '
          'Если выйти сейчас, все внесённые изменения будут потеряны.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Остаться'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB83A4B),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Выйти без сохранения'),
          ),
        ],
      ),
    );
    if (!mounted || leave != true) return false;
    setState(_discardUnsavedChanges);
    return true;
  }

  /// Сворачивает уже настроенные составные блоки при первом показе конфигурации.
  /// Только что добавленные пользователем блоки раскрываются своими обработчиками.
  void _collapseConfiguredBlocks() {
    _collapsedWorkflowCodes
      ..clear()
      ..addAll(draft.workflows.map((workflow) => workflow.code));
    _collapsedCategoryIds
      ..clear()
      ..addAll(draft.categories.map((category) => category.clientId));
    _collapsedFieldCategoryIds
      ..clear()
      ..addAll(draft.categories.map((category) => category.clientId));
    _collapsedWorkflowFieldCodes
      ..clear()
      ..addAll(draft.workflows.map((workflow) => workflow.code));
    _collapsedDependencies
      ..clear()
      ..addAll(draft.dependencies);
    _collapsedRoles
      ..clear()
      ..addAll(draft.roles);
    _collapsedDictionaries
      ..clear()
      ..addAll(draft.dictionaries);
    _collapsedRules
      ..clear()
      ..addAll(draft.rules.map((rule) => rule.clientId));
    _collapsedPipelines
      ..clear()
      ..addAll(
        draft.moneyPipelines.map((pipeline) => pipeline.categoryClientId),
      );
    _expandedCatalogSections.clear();
  }

  void _toggleCollapsed<T>(Set<T> collapsedItems, T item) {
    if (!collapsedItems.add(item)) collapsedItems.remove(item);
  }

  /// Восстанавливает системные поля в старых черновиках и конфигурациях.
  /// Существующий порядок и все пользовательские поля при этом сохраняются.
  void _ensureFixedCatalogFields() {
    for (final category in draft.categories) {
      final selectedCodes = category.fields
          .map((field) => field.fieldCode)
          .toSet();
      for (final code in defaultCatalogFieldCodes) {
        if (selectedCodes.add(code)) {
          category.fields.add(
            CatalogFieldDraft(
              fieldCode: code,
              isVisible: true,
              isRequired: code == 'name',
              label: onboardingFieldByCode[code]!.label,
            ),
          );
        }
      }
    }
  }

  /// Сохраняет агрегат целиком, чтобы сервер мог проверить межшаговые связи.
  Future<void> _saveAndContinue() async {
    if (step == 0 && !(_companyFormKey.currentState?.validate() ?? false)) {
      _showMessage('Проверьте заполнение реквизитов организации.');
      return;
    }
    if (_settingsMode) {
      draft.currentStep = 9;
      final saved = await widget.onSettingsSave!(
        draft,
        deleteCategoryData: _approvedCategoryDataDeletions.toList(),
      );
      if (!mounted || !saved) return;
      setState(() {
        _approvedCategoryDataDeletions.clear();
        step = (step + 1).clamp(0, 8);
      });
      return;
    }
    draft.currentStep = (step + 2).clamp(1, 9);
    await widget.controller.saveOnboardingStep(draft);
    if (!mounted || widget.controller.error != null) return;
    setState(() {
      draft = widget.controller.onboardingDraft ?? draft;
      step = (step + 1).clamp(0, 8);
    });
  }

  Future<void> _saveSettings() async {
    draft.currentStep = 9;
    final saved = await widget.onSettingsSave!(
      draft,
      deleteCategoryData: _approvedCategoryDataDeletions.toList(),
    );
    if (!mounted || !saved) return;
    _approvedCategoryDataDeletions.clear();
    _savedDraftJson = jsonEncode(draft.toJson());
    _showMessage('Настройки организации сохранены.');
  }

  Future<void> _deleteCategory(String categoryClientId) async {
    if (_checkingCategoryIds.contains(categoryClientId)) return;
    if (!draft.categories.any((item) => item.clientId == categoryClientId)) {
      return;
    }

    if (_settingsMode) {
      final inspect = widget.onCategoryDeletionImpact;
      if (inspect == null) return;
      setState(() => _checkingCategoryIds.add(categoryClientId));
      final impact = await inspect(categoryClientId);
      if (!mounted) return;
      setState(() => _checkingCategoryIds.remove(categoryClientId));
      if (impact == null) return;

      if (impact.hasData) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            icon: const Icon(
              Icons.warning_amber_rounded,
              color: Color(0xFFF59E0B),
            ),
            title: const Text('Категория не пуста'),
            content: Text(
              'В категории «${impact.categoryName}» находится '
              '${impact.itemCount} карточек, ${impact.imageCount} изображений '
              'и ${impact.relationCount} связей. При сохранении они будут '
              'удалены без возможности восстановления.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Отмена'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFB83A4B),
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.delete_forever_outlined),
                label: const Text('Удалить всё'),
              ),
            ],
          ),
        );
        if (!mounted || confirmed != true) return;
        _approvedCategoryDataDeletions.add(categoryClientId);
        widget.onCategoryDeletionApproved?.call(categoryClientId);
      }
    }

    setState(() {
      final currentIndex = draft.categories.indexWhere(
        (item) => item.clientId == categoryClientId,
      );
      if (currentIndex < 0) return;
      final removed = draft.categories.removeAt(currentIndex);
      _collapsedCategoryIds.remove(removed.clientId);
      _expandedCatalogSections.removeAll(removed.sections);
      draft.dependencies.removeWhere(
        (dependency) =>
            dependency.sourceCategoryClientId == removed.clientId ||
            dependency.targetCategoryClientId == removed.clientId,
      );
      draft.rules.removeWhere(
        (rule) => rule.categoryClientId == removed.clientId,
      );
      draft.moneyPipelines.removeWhere(
        (pipeline) => pipeline.categoryClientId == removed.clientId,
      );
      for (final workflow in draft.workflows) {
        workflow.categories.removeWhere(
          (item) => item.categoryClientId == removed.clientId,
        );
      }
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF080E16), Color(0xFF101927)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1050;
            return Column(
              children: [
                if (!_settingsMode)
                  _Header(wide: wide, settingsMode: _settingsMode),
                _settingsMode
                    ? _SettingsTabs(step: step, onSelect: _selectStep)
                    : _Progress(step: step, wide: wide, onSelect: _selectStep),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      wide ? 28 : 14,
                      18,
                      wide ? 28 : 14,
                      28,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1540),
                        child: wide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(flex: 7, child: _editor()),
                                  const SizedBox(width: 18),
                                  SizedBox(width: 400, child: _preview()),
                                ],
                              )
                            : Column(
                                children: [
                                  _editor(),
                                  const SizedBox(height: 16),
                                  _preview(),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );

  Future<void> _selectStep(int value) async {
    if (_settingsMode) {
      if (value == step || widget.settingsBusy) return;
      if (!await _confirmLeave(context)) return;
      if (mounted) setState(() => step = value);
      return;
    }
    if (value <= draft.currentStep - 1) setState(() => step = value);
  }

  Widget _editor() => _Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _RoundIcon(_steps[step].$2),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                _settingsMode
                    ? _steps[step].$1
                    : '${step + 1}. ${_steps[step].$1}',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        if (_error != null) ...[
          _ErrorBanner(_error!),
          const SizedBox(height: 16),
        ],
        _stepBody(),
        const SizedBox(height: 24),
        Row(
          children: [
            if (!_settingsMode && step > 0)
              OutlinedButton.icon(
                onPressed: _busy ? null : () => setState(() => step--),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Назад'),
              ),
            const Spacer(),
            SizedBox(
              width: 250,
              child: FilledButton.icon(
                onPressed: _busy
                    ? null
                    : _settingsMode
                    ? _saveSettings
                    : step == 8
                    ? widget.controller.activateOrganization
                    : _saveAndContinue,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _settingsMode || step == 8
                            ? Icons.save_outlined
                            : Icons.arrow_forward,
                      ),
                label: Text(
                  _settingsMode
                      ? 'Сохранить изменения'
                      : step == 8
                      ? 'Активировать организацию'
                      : 'Сохранить и продолжить',
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _stepBody() => switch (step) {
    0 => _companyEditor(),
    1 => _workflowEditor(),
    2 => _catalogEditor(),
    3 => _fieldsEditor(),
    4 => _rulesEditor(),
    5 => _dependenciesEditor(),
    6 => _rolesEditor(),
    7 => _dictionariesEditor(),
    _ => _review(),
  };

  Widget _companyEditor() {
    return Form(
      key: _companyFormKey,
      child: CompanyProfileForm(
        profile: draft.company,
        onChanged: () => setState(() {}),
      ),
    );
  }

  Widget _workflowEditor() => Column(
    children: [
      for (final workflow in List<WorkflowDraft>.of(draft.workflows))
        Padding(
          key: ValueKey(workflow.code),
          padding: const EdgeInsets.only(bottom: 14),
          child: _workflowPanel(workflow),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () => setState(() {
            final code = _nextWorkflowCode();
            draft.workflows.add(
              WorkflowDraft(
                code: code,
                name: 'Новый канбан',
                columns: [],
                transitions: [],
              ),
            );
            _collapsedWorkflowCodes.remove(code);
          }),
          icon: const Icon(Icons.add),
          label: const Text('Добавить канбан'),
        ),
      ),
    ],
  );

  /// Возвращает первый свободный технический код, не показываемый пользователю.
  /// Поиск свободного номера исключает дубли после удаления канбана из середины.
  String _nextWorkflowCode() {
    final usedCodes = draft.workflows.map((workflow) => workflow.code).toSet();
    var number = 1;
    while (usedCodes.contains('workflow_$number')) {
      number++;
    }
    return 'workflow_$number';
  }

  Widget _workflowPanel(WorkflowDraft workflow) {
    final isExpanded = !_collapsedWorkflowCodes.contains(workflow.code);
    return _SubPanel(
      title: workflow.name.trim().isEmpty
          ? 'Канбан без названия'
          : workflow.name,
      expanded: isExpanded,
      collapseTooltip: 'Свернуть канбан',
      expandTooltip: 'Развернуть канбан',
      onToggle: () => setState(() {
        if (isExpanded) {
          _collapsedWorkflowCodes.add(workflow.code);
        } else {
          _collapsedWorkflowCodes.remove(workflow.code);
        }
      }),
      onDelete: () => setState(() {
        draft.workflows.remove(workflow);
        _collapsedWorkflowCodes.remove(workflow.code);
      }),
      child: Column(
        children: [
          _textField('Название канбана', workflow.name, (value) {
            setState(() => workflow.name = value);
          }),
          const SizedBox(height: 12),
          for (final column in List<WorkflowColumnDraft>.of(workflow.columns))
            KeyedSubtree(
              key: ValueKey(column.clientId),
              child: _workflowColumnRow(workflow, column),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() {
                workflow.columns.add(
                  WorkflowColumnDraft(
                    clientId:
                        '${workflow.code}-${DateTime.now().microsecondsSinceEpoch}',
                    name: 'Новый столбец',
                    color: '#4D8DFF',
                  ),
                );
              }),
              icon: const Icon(Icons.add),
              label: const Text('Добавить столбец'),
            ),
          ),
          if (workflow.columns.length > 1) ...[
            const SizedBox(height: 10),
            _workflowTransitionsEditor(workflow),
          ],
        ],
      ),
    );
  }

  Widget _workflowColumnRow(
    WorkflowDraft workflow,
    WorkflowColumnDraft column,
  ) {
    final columnIndex = workflow.columns.indexOf(column);
    return _OrderedRow(
      index: columnIndex,
      length: workflow.columns.length,
      onMove: (delta) => setState(
        () => _move(workflow.columns, columnIndex, columnIndex + delta),
      ),
      onDelete: () => setState(() {
        workflow.columns.remove(column);
        workflow.transitions.removeWhere(
          (transition) =>
              transition.fromClientId == column.clientId ||
              transition.toClientId == column.clientId,
        );
      }),
      child: Row(
        children: [
          Expanded(
            child: _textField(
              'Столбец ${columnIndex + 1}',
              column.name,
              (value) => setState(() => column.name = value),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 148,
            child: AppSelectField<String>(
              key: ValueKey('${column.clientId}-${column.color}'),
              value: column.color,
              label: 'Цвет',
              options: _workflowColors
                  .map(
                    (color) => AppSelectOption(
                      value: color,
                      label: color,
                      color: Color(
                        int.parse(color.substring(1), radix: 16) | 0xFF000000,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => column.color = value);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _workflowTransitionsEditor(WorkflowDraft workflow) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          const Text(
            'Разрешённые переходы',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          TextButton.icon(
            onPressed: () => setState(() => _allowAllTransitions(workflow)),
            icon: const Icon(Icons.done_all, size: 18),
            label: const Text('Разрешить все переходы'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      for (final from in workflow.columns)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0x55121D2B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2B3A50)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Из «${from.name}» можно перенести в:',
                style: const TextStyle(
                  color: Color(0xFFB9C8DC),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final to in workflow.columns)
                    if (from.clientId != to.clientId)
                      FilterChip(
                        label: Text(to.name),
                        selected: _hasTransition(
                          workflow,
                          from.clientId,
                          to.clientId,
                        ),
                        onSelected: (selected) => setState(
                          () => _setTransition(
                            workflow,
                            from.clientId,
                            to.clientId,
                            selected,
                          ),
                        ),
                      ),
                ],
              ),
            ],
          ),
        ),
    ],
  );

  Widget _catalogEditor() => Column(
    children: [
      for (
        var categoryIndex = 0;
        categoryIndex < draft.categories.length;
        categoryIndex++
      )
        Padding(
          key: ValueKey(draft.categories[categoryIndex].clientId),
          padding: const EdgeInsets.only(bottom: 14),
          child: _SubPanel(
            title: draft.categories[categoryIndex].name,
            expanded: !_collapsedCategoryIds.contains(
              draft.categories[categoryIndex].clientId,
            ),
            collapseTooltip: 'Свернуть категорию',
            expandTooltip: 'Развернуть категорию',
            onToggle: () => setState(() {
              final categoryId = draft.categories[categoryIndex].clientId;
              if (!_collapsedCategoryIds.add(categoryId)) {
                _collapsedCategoryIds.remove(categoryId);
              }
            }),
            onDelete:
                _checkingCategoryIds.contains(
                  draft.categories[categoryIndex].clientId,
                )
                ? null
                : () =>
                      _deleteCategory(draft.categories[categoryIndex].clientId),
            child: Column(
              children: [
                _textField('Категория', draft.categories[categoryIndex].name, (
                  value,
                ) {
                  setState(() => draft.categories[categoryIndex].name = value);
                }),
                const SizedBox(height: 10),
                for (
                  var sectionIndex = 0;
                  sectionIndex <
                      draft.categories[categoryIndex].sections.length;
                  sectionIndex++
                )
                  _CatalogSectionPanel(
                    title: draft
                        .categories[categoryIndex]
                        .sections[sectionIndex]
                        .name,
                    expanded: _expandedCatalogSections.contains(
                      draft.categories[categoryIndex].sections[sectionIndex],
                    ),
                    onToggle: () => setState(() {
                      final section = draft
                          .categories[categoryIndex]
                          .sections[sectionIndex];
                      if (!_expandedCatalogSections.add(section)) {
                        _expandedCatalogSections.remove(section);
                      }
                    }),
                    onDelete: () => setState(() {
                      final section = draft.categories[categoryIndex].sections
                          .removeAt(sectionIndex);
                      _expandedCatalogSections.remove(section);
                    }),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 14, 4, 0),
                          child: _textField(
                            'Название раздела',
                            draft
                                .categories[categoryIndex]
                                .sections[sectionIndex]
                                .name,
                            (value) => setState(
                              () =>
                                  draft
                                          .categories[categoryIndex]
                                          .sections[sectionIndex]
                                          .name =
                                      value,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (
                          var groupIndex = 0;
                          groupIndex <
                              draft
                                  .categories[categoryIndex]
                                  .sections[sectionIndex]
                                  .groups
                                  .length;
                          groupIndex++
                        )
                          Padding(
                            padding: const EdgeInsets.only(left: 32),
                            child: _DeleteRow(
                              onDelete: () => setState(
                                () => draft
                                    .categories[categoryIndex]
                                    .sections[sectionIndex]
                                    .groups
                                    .removeAt(groupIndex),
                              ),
                              child: _textField(
                                'Группа',
                                draft
                                    .categories[categoryIndex]
                                    .sections[sectionIndex]
                                    .groups[groupIndex]
                                    .name,
                                (value) =>
                                    draft
                                            .categories[categoryIndex]
                                            .sections[sectionIndex]
                                            .groups[groupIndex]
                                            .name =
                                        value,
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(left: 32),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => setState(
                                () => draft
                                    .categories[categoryIndex]
                                    .sections[sectionIndex]
                                    .groups
                                    .add(CatalogGroupDraft('Новая группа')),
                              ),
                              icon: const Icon(Icons.add),
                              label: const Text('Добавить группу'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(
                      () => draft.categories[categoryIndex].sections.add(
                        CatalogSectionDraft(name: 'Новый раздел', groups: []),
                      ),
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('Добавить раздел'),
                  ),
                ),
              ],
            ),
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () => setState(
            () => draft.categories.add(
              CatalogCategoryDraft(
                clientId: 'category_${DateTime.now().microsecondsSinceEpoch}',
                name: 'Новая категория',
                sections: [],
                fields: _defaultCatalogFields(),
              ),
            ),
          ),
          icon: const Icon(Icons.add),
          label: const Text('Добавить категорию'),
        ),
      ),
    ],
  );

  Widget _fieldsEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _InfoBanner(
          'Сначала настройте поля карточек категорий. Ниже привяжите категории к канбанам и выберите поля, которые будут видны в карточках каждого канбана.',
        ),
        const SizedBox(height: 20),
        const _SectionTitle(
          title: 'Поля карточек категорий',
          subtitle: 'Состав, порядок, видимость и обязательность полей.',
        ),
        const SizedBox(height: 12),
        for (final category in draft.categories)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _catalogFieldPanel(category),
          ),
        const SizedBox(height: 8),
        const _SectionTitle(
          title: 'Поля в канбанах',
          subtitle:
              'Для каждого канбана выберите категории, затем поля их карточек.',
        ),
        const SizedBox(height: 12),
        for (final workflow in draft.workflows)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _workflowFieldPanel(workflow),
          ),
      ],
    );
  }

  Widget _dependenciesEditor() => Column(
    children: [
      const _InfoBanner(
        'Зависимость определяет, позиции какой категории можно привязывать к позициям другой категории. Например: «Работы» → «Оборудование» → «Связанные позиции».',
      ),
      const SizedBox(height: 14),
      if (draft.categories.length < 2)
        const _InfoBanner('Для зависимости нужны как минимум две категории.'),
      for (var index = 0; index < draft.dependencies.length; index++)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: _dependencyPanel(index, draft.dependencies[index]),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: draft.categories.length < 2 ? null : _addDependency,
          icon: const Icon(Icons.add),
          label: const Text('Добавить зависимость'),
        ),
      ),
    ],
  );

  Widget _dependencyPanel(int index, CategoryDependencyDraft dependency) {
    final sourceItems = draft.categories
        .where(
          (category) => category.clientId != dependency.targetCategoryClientId,
        )
        .toList();
    final targetItems = draft.categories
        .where(
          (category) =>
              category.clientId != dependency.sourceCategoryClientId &&
              _relationFields(category).isNotEmpty,
        )
        .toList();
    final target = _categoryByClientId(dependency.targetCategoryClientId);
    final relationFields = target == null
        ? const <CatalogFieldDraft>[]
        : _relationFields(target);

    return _SubPanel(
      title: 'Зависимость ${index + 1}',
      expanded: !_collapsedDependencies.contains(dependency),
      onToggle: () =>
          setState(() => _toggleCollapsed(_collapsedDependencies, dependency)),
      collapseTooltip: 'Свернуть зависимость',
      expandTooltip: 'Развернуть зависимость',
      onDelete: () => setState(() {
        draft.dependencies.removeAt(index);
        _collapsedDependencies.remove(dependency);
      }),
      child: _responsiveFields([
        AppSelectField<String>(
          value:
              sourceItems.any(
                (category) =>
                    category.clientId == dependency.sourceCategoryClientId,
              )
              ? dependency.sourceCategoryClientId
              : null,
          label: 'Что привязываем',
          options: [
            for (final category in sourceItems)
              AppSelectOption(value: category.clientId, label: category.name),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() => dependency.sourceCategoryClientId = value);
            }
          },
        ),
        AppSelectField<String>(
          value:
              targetItems.any(
                (category) =>
                    category.clientId == dependency.targetCategoryClientId,
              )
              ? dependency.targetCategoryClientId
              : null,
          label: 'К чему привязываем',
          options: [
            for (final category in targetItems)
              AppSelectOption(value: category.clientId, label: category.name),
          ],
          onChanged: (value) {
            if (value == null) return;
            final selected = draft.categories.firstWhere(
              (category) => category.clientId == value,
            );
            final fields = _relationFields(selected);
            setState(() {
              dependency.targetCategoryClientId = value;
              dependency.targetFieldCode = fields.first.fieldCode;
            });
          },
        ),
        AppSelectField<String>(
          value:
              relationFields.any(
                (field) => field.fieldCode == dependency.targetFieldCode,
              )
              ? dependency.targetFieldCode
              : null,
          label: 'В какое поле записывать',
          options: [
            for (final field in relationFields)
              AppSelectOption(
                value: field.fieldCode,
                label: catalogFieldLabel(field),
              ),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() => dependency.targetFieldCode = value);
            }
          },
        ),
      ]),
    );
  }

  List<CatalogFieldDraft> _relationFields(CatalogCategoryDraft category) =>
      category.fields
          .where((field) => catalogFieldType(field) == 'relation')
          .toList();

  CatalogCategoryDraft? _categoryByClientId(String clientId) {
    for (final category in draft.categories) {
      if (category.clientId == clientId) return category;
    }
    return null;
  }

  void _addDependency() {
    CatalogCategoryDraft? target;
    for (final category in draft.categories) {
      if (_relationFields(category).isNotEmpty) {
        target = category;
        break;
      }
    }
    if (target == null) {
      _showMessage(
        'Сначала добавьте relation-поле «Связанные позиции» в карточку целевой категории.',
      );
      return;
    }
    CatalogCategoryDraft? source;
    for (final category in draft.categories) {
      if (category.clientId != target.clientId) {
        source = category;
        break;
      }
    }
    if (source == null) return;
    final selectedTarget = target;
    final selectedSource = source;
    setState(() {
      draft.dependencies.add(
        CategoryDependencyDraft(
          clientId: 'dependency_${DateTime.now().microsecondsSinceEpoch}',
          sourceCategoryClientId: selectedSource.clientId,
          targetCategoryClientId: selectedTarget.clientId,
          targetFieldCode: _relationFields(selectedTarget).first.fieldCode,
        ),
      );
    });
  }

  Widget _catalogFieldPanel(CatalogCategoryDraft category) {
    final isExpanded = !_collapsedFieldCategoryIds.contains(category.clientId);
    return _SubPanel(
      title: 'Категория: ${category.name}',
      expanded: isExpanded,
      collapseTooltip: 'Свернуть поля категории',
      expandTooltip: 'Развернуть поля категории',
      onToggle: () => setState(() {
        if (isExpanded) {
          _collapsedFieldCategoryIds.add(category.clientId);
        } else {
          _collapsedFieldCategoryIds.remove(category.clientId);
        }
      }),
      child: Column(
        children: [
          for (var index = 0; index < category.fields.length; index++)
            _OrderedRow(
              key: ValueKey(
                '${category.clientId}:${category.fields[index].fieldCode}',
              ),
              index: index,
              length: category.fields.length,
              onMove: (delta) => setState(() {
                final field = category.fields.removeAt(index);
                category.fields.insert(index + delta, field);
              }),
              onDelete: isFixedCatalogField(category.fields[index].fieldCode)
                  ? null
                  : () => setState(() {
                      final field = category.fields.removeAt(index);
                      draft.dependencies.removeWhere(
                        (dependency) =>
                            dependency.targetCategoryClientId ==
                                category.clientId &&
                            dependency.targetFieldCode == field.fieldCode,
                      );
                      _removeUnavailableWorkflowField(
                        category,
                        field.fieldCode,
                      );
                    }),
              child: _catalogFieldControls(category.fields[index]),
            ),
          _addCatalogFieldButton(category),
        ],
      ),
    );
  }

  /// Возвращает поля категории вместе с расчётными полями, доступными системе.
  List<OnboardingFieldDefinition> _workflowAvailableFields(
    CatalogCategoryDraft category,
  ) {
    final result = <OnboardingFieldDefinition>[];
    final added = <String>{};
    for (final field in category.fields) {
      final definition = catalogFieldDefinition(field);
      if (added.add(definition.code)) {
        result.add(definition);
      }
    }
    for (final definition in onboardingFieldDefinitions) {
      if (definition.isCalculated && added.add(definition.code)) {
        result.add(definition);
      }
    }
    return result;
  }

  /// Удаляет поле из карточек канбанов, если категория больше его не поддерживает.
  void _removeUnavailableWorkflowField(
    CatalogCategoryDraft category,
    String fieldCode,
  ) {
    if (_workflowAvailableFields(
      category,
    ).any((definition) => definition.code == fieldCode)) {
      return;
    }
    for (final workflow in draft.workflows) {
      final selection = _workflowCategory(workflow, category.clientId);
      selection?.fieldCodes.remove(fieldCode);
    }
  }

  WorkflowCategoryDraft? _workflowCategory(
    WorkflowDraft workflow,
    String categoryClientId,
  ) {
    for (final category in workflow.categories) {
      if (category.categoryClientId == categoryClientId) return category;
    }
    return null;
  }

  Widget _workflowFieldPanel(WorkflowDraft workflow) {
    final isExpanded = !_collapsedWorkflowFieldCodes.contains(workflow.code);
    return _SubPanel(
      title: 'Канбан: ${workflow.name}',
      expanded: isExpanded,
      collapseTooltip: 'Свернуть поля канбана',
      expandTooltip: 'Развернуть поля канбана',
      onToggle: () => setState(() {
        if (isExpanded) {
          _collapsedWorkflowFieldCodes.add(workflow.code);
        } else {
          _collapsedWorkflowFieldCodes.remove(workflow.code);
        }
      }),
      child: Column(
        children: [
          for (final category in draft.categories)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _workflowCategoryFields(workflow, category),
            ),
          if (draft.categories.isEmpty)
            const _EmptyHint('Сначала добавьте категории на шаге «Каталог».'),
        ],
      ),
    );
  }

  Widget _workflowCategoryFields(
    WorkflowDraft workflow,
    CatalogCategoryDraft category,
  ) {
    final selection = _workflowCategory(workflow, category.clientId);
    final availableFields = _workflowAvailableFields(category);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1724),
        border: Border.all(color: const Color(0xFF263A52)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                category.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text('Использовать категорию в этом канбане'),
              value: selection != null,
              onChanged: (enabled) => setState(() {
                if (enabled ?? false) {
                  workflow.categories.add(
                    WorkflowCategoryDraft(
                      categoryClientId: category.clientId,
                      fieldCodes: [
                        for (final field in category.fields)
                          if (field.isVisible) field.fieldCode,
                      ],
                    ),
                  );
                } else {
                  workflow.categories.removeWhere(
                    (item) => item.categoryClientId == category.clientId,
                  );
                }
              }),
            ),
            if (selection != null) ...[
              const Divider(height: 18),
              Padding(
                padding: const EdgeInsets.only(left: 18),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final definition in availableFields)
                      SizedBox(
                        width: 250,
                        child: CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(
                            _categoryFieldLabel(category, definition.code),
                          ),
                          subtitle: definition.isCalculated
                              ? const Text('Расчётное поле')
                              : null,
                          value: selection.fieldCodes.contains(definition.code),
                          onChanged: (enabled) => setState(() {
                            selection.fieldCodes.remove(definition.code);
                            if (enabled ?? false) {
                              selection.fieldCodes.add(definition.code);
                            }
                          }),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _catalogFieldControls(CatalogFieldDraft field) {
    final definition = catalogFieldDefinition(field);
    final flags = [
      _CompactFlag(
        label: 'Показывать',
        value: field.isVisible,
        onChanged: (value) => setState(() {
          field.isVisible = value;
          if (!value) field.isRequired = false;
        }),
      ),
      _CompactFlag(
        label: 'Обязательное',
        value: field.isRequired,
        onChanged: definition.canBeRequired && field.isVisible
            ? (value) => setState(() => field.isRequired = value)
            : null,
      ),
    ];
    final dictionarySelector =
        definition.fieldType == 'dictionary' && definition.code != 'group'
        ? SizedBox(
            width: 210,
            child: AppSelectField<String>(
              value:
                  draft.dictionaries.any(
                    (dictionary) => dictionary.code == field.dictionaryCode,
                  )
                  ? field.dictionaryCode
                  : null,
              label: 'Источник значений',
              options: [
                const AppSelectOption(
                  value: null,
                  label: 'Справочник не выбран',
                ),
                for (final dictionary in draft.dictionaries)
                  AppSelectOption(
                    value: dictionary.code,
                    label: dictionary.name,
                  ),
              ],
              onChanged: (value) =>
                  setState(() => field.dictionaryCode = value),
            ),
          )
        : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final name = TextFormField(
          initialValue: catalogFieldLabel(field),
          decoration: const InputDecoration(labelText: 'Название поля'),
          onChanged: (value) => field.label = value,
        );
        final type = _FieldTypeBadge(_fieldTypeLabel(definition.fieldType));
        if (constraints.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              name,
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [?dictionarySelector, type, ...flags],
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: name),
            if (dictionarySelector != null) ...[
              const SizedBox(width: 12),
              SizedBox(width: 210, child: dictionarySelector),
            ],
            const SizedBox(width: 10),
            SizedBox(width: 160, child: type),
            const SizedBox(width: 8),
            ...flags,
          ],
        );
      },
    );
  }

  Widget _addCatalogFieldButton(CatalogCategoryDraft category) => Align(
    alignment: Alignment.centerLeft,
    child: PopupMenuButton<OnboardingFieldDefinition>(
      tooltip: 'Выбрать тип нового поля',
      onSelected: (type) => setState(() {
        category.fields.add(
          CatalogFieldDraft(
            fieldCode: 'custom_${DateTime.now().microsecondsSinceEpoch}',
            fieldType: type.fieldType,
            isVisible: true,
            isRequired: false,
            label: '',
          ),
        );
      }),
      itemBuilder: (context) => [
        for (final type in customCatalogFieldTypes)
          PopupMenuItem(value: type, child: Text(type.label)),
      ],
      child: IgnorePointer(
        child: TextButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.add),
          label: const Text('Добавить поле'),
        ),
      ),
    ),
  );

  List<CatalogFieldDraft> _defaultCatalogFields() => [
    for (final code in defaultCatalogFieldCodes)
      CatalogFieldDraft(
        fieldCode: code,
        isVisible: true,
        isRequired: code == 'name' || code == 'quantity',
        label: onboardingFieldByCode[code]!.label,
      ),
  ];

  String _categoryFieldLabel(CatalogCategoryDraft category, String code) {
    for (final field in category.fields) {
      if (field.fieldCode == code) return catalogFieldLabel(field);
    }
    return onboardingFieldByCode[code]?.label ?? code;
  }

  String _fieldTypeLabel(String type) => switch (type) {
    'text' => 'Текст',
    'number' => 'Число',
    'money' => 'Деньги',
    'percent' => 'Процент',
    'dictionary' => 'Справочник',
    'boolean' => 'Флажок',
    'relation' => 'Связанные карточки',
    'enum' => 'Выбор значения',
    'calculated_money' => 'Расчётная сумма',
    _ => type,
  };

  Widget _rulesEditor() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const _InfoBanner(
        'Денежный расчёт всегда выполняется в порядке: базовая цена → ручная цена → наценка → скидка → количество → округление → итог.',
      ),
      const SizedBox(height: 16),
      const _SectionTitle(
        title: 'Денежные конвейеры',
        subtitle:
            'Сопоставьте уже созданные поля каждой категории с фиксированными этапами расчёта.',
      ),
      const SizedBox(height: 12),
      for (final category in draft.categories)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _moneyPipelinePanel(category),
        ),
      if (draft.categories.isEmpty)
        const _EmptyHint('Сначала создайте категории и поля.'),
      const SizedBox(height: 22),
      const _SectionTitle(
        title: 'Событийные правила',
        subtitle: 'Настройте условия и действия без программного кода.',
      ),
      const SizedBox(height: 12),
      for (var index = 0; index < draft.rules.length; index++)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _rulePanel(draft.rules[index], index),
        ),
      if (draft.rules.isEmpty)
        const _EmptyHint('Событийные правила ещё не добавлены.'),
      const SizedBox(height: 10),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: draft.categories.isEmpty ? null : _addRule,
          icon: const Icon(Icons.add),
          label: const Text('Добавить правило'),
        ),
      ),
    ],
  );

  Widget _moneyPipelinePanel(CatalogCategoryDraft category) {
    final pipeline = draft.moneyPipelines
        .where((item) => item.categoryClientId == category.clientId)
        .firstOrNull;
    if (pipeline == null) {
      return _SubPanel(
        title: category.name,
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Расчёт для категории не настроен. Поля останутся обычными значениями.',
              ),
            ),
            OutlinedButton.icon(
              onPressed:
                  _numericFields(category, const [
                    'money',
                    'calculated_money',
                  ]).isEmpty
                  ? null
                  : () => _addMoneyPipeline(category),
              icon: const Icon(Icons.tune),
              label: const Text('Настроить'),
            ),
          ],
        ),
      );
    }

    final expanded = !_collapsedPipelines.contains(category.clientId);
    return _SubPanel(
      title: category.name,
      expanded: expanded,
      onToggle: () => setState(
        () => _toggleCollapsed(_collapsedPipelines, category.clientId),
      ),
      onDelete: () => setState(() {
        draft.moneyPipelines.remove(pipeline);
        _collapsedPipelines.remove(category.clientId);
      }),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _responsiveFields([
            _ruleFieldSelect(
              category,
              'Базовая цена',
              pipeline.basePriceFieldCode,
              const ['money', 'calculated_money'],
              (value) => setState(() => pipeline.basePriceFieldCode = value!),
              required: true,
            ),
            _ruleFieldSelect(
              category,
              'Ручная цена',
              pipeline.manualPriceFieldCode,
              const ['money'],
              (value) => setState(() => pipeline.manualPriceFieldCode = value),
            ),
          ]),
          const SizedBox(height: 12),
          _responsiveFields([
            _ruleFieldSelect(
              category,
              'Наценка',
              pipeline.markupFieldCode,
              const ['percent'],
              (value) => setState(() => pipeline.markupFieldCode = value),
            ),
            _ruleFieldSelect(
              category,
              'Скидка',
              pipeline.discountFieldCode,
              const ['percent'],
              (value) => setState(() => pipeline.discountFieldCode = value),
            ),
            _ruleFieldSelect(
              category,
              'Количество',
              pipeline.quantityFieldCode,
              const ['number'],
              (value) => setState(() => pipeline.quantityFieldCode = value),
            ),
          ]),
          const SizedBox(height: 12),
          _responsiveFields([
            _ruleFieldSelect(
              category,
              'Записать результат в',
              pipeline.resultFieldCode,
              const ['money', 'calculated_money'],
              (value) => setState(() => pipeline.resultFieldCode = value!),
              required: true,
            ),
            AppSelectField<int>(
              value: pipeline.decimalPlaces,
              label: 'Округление',
              options: [
                for (var value = 0; value <= 6; value++)
                  AppSelectOption(value: value, label: '$value знаков'),
              ],
              onChanged: (value) =>
                  setState(() => pipeline.decimalPlaces = value ?? 2),
            ),
          ]),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Участвует в итогах'),
            subtitle: const Text(
              'Результат строки включается в сумму варианта.',
            ),
            value: pipeline.includeResultInTotals,
            onChanged: (value) =>
                setState(() => pipeline.includeResultInTotals = value ?? true),
          ),
        ],
      ),
    );
  }

  void _addMoneyPipeline(CatalogCategoryDraft category) {
    final money = _numericFields(category, const ['money', 'calculated_money']);
    if (money.isEmpty) return;
    final result = money.firstWhere(
      (field) => catalogFieldType(field) == 'calculated_money',
      orElse: () => money.first,
    );
    setState(() {
      draft.moneyPipelines.add(
        MoneyPipelineDraft(
          categoryClientId: category.clientId,
          basePriceFieldCode: money.first.fieldCode,
          resultFieldCode: result.fieldCode,
        ),
      );
      _collapsedPipelines.remove(category.clientId);
    });
  }

  void _addRule() {
    final category = draft.categories.first;
    final id = 'rule_${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      draft.rules.add(
        CalculationRuleDraft(
          clientId: id,
          name: 'Новое правило',
          categoryClientId: category.clientId,
          eventType: 'card_saving',
          isEnabled: true,
          actions: [
            RuleActionDraft(
              actionType: 'block_save',
              message: 'Заполните обязательные данные.',
            ),
          ],
        ),
      );
      _collapsedRules.remove(id);
    });
  }

  Widget _rulePanel(CalculationRuleDraft rule, int index) {
    final category = _categoryByClientId(rule.categoryClientId);
    final expanded = !_collapsedRules.contains(rule.clientId);
    return _SubPanel(
      title: rule.name,
      expanded: expanded,
      onToggle: () =>
          setState(() => _toggleCollapsed(_collapsedRules, rule.clientId)),
      onDelete: () => setState(() {
        draft.rules.removeAt(index);
        _collapsedRules.remove(rule.clientId);
      }),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _responsiveFields([
            _textField('Название правила', rule.name, (value) {
              setState(() => rule.name = value);
            }),
            AppSelectField<String>(
              value: category?.clientId,
              label: 'Категория',
              options: [
                for (final item in draft.categories)
                  AppSelectOption(value: item.clientId, label: item.name),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  rule.categoryClientId = value;
                  rule.eventFieldCode = null;
                  rule.conditions.clear();
                  rule.actions = [
                    RuleActionDraft(
                      actionType: 'block_save',
                      message: 'Заполните обязательные данные.',
                    ),
                  ];
                });
              },
            ),
          ]),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Правило активно'),
            value: rule.isEnabled,
            onChanged: (value) => setState(() => rule.isEnabled = value),
          ),
          const Divider(height: 24),
          _ruleEventEditor(rule, category),
          const Divider(height: 28),
          _ruleConditionsEditor(rule, category),
          const Divider(height: 28),
          _ruleActionsEditor(rule, category),
        ],
      ),
    );
  }

  Widget _ruleEventEditor(
    CalculationRuleDraft rule,
    CatalogCategoryDraft? category,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Событие', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 10),
      _responsiveFields([
        AppSelectField<String>(
          value: rule.eventType,
          label: 'Когда выполнять',
          options: const [
            AppSelectOption(
              value: 'field_changed',
              label: 'При изменении поля',
            ),
            AppSelectOption(
              value: 'card_saving',
              label: 'При сохранении карточки',
            ),
            AppSelectOption(
              value: 'row_calculation',
              label: 'При расчёте строки',
            ),
            AppSelectOption(
              value: 'variant_calculation',
              label: 'При расчёте варианта',
            ),
          ],
          onChanged: (value) => setState(() {
            rule.eventType = value ?? 'card_saving';
            if (rule.eventType != 'field_changed') rule.eventFieldCode = null;
          }),
        ),
        if (rule.eventType == 'field_changed' && category != null)
          _ruleFieldSelect(
            category,
            'Изменяемое поле',
            rule.eventFieldCode,
            const [],
            (value) => setState(() => rule.eventFieldCode = value),
            required: true,
          ),
      ]),
    ],
  );

  Widget _ruleConditionsEditor(
    CalculationRuleDraft rule,
    CatalogCategoryDraft? category,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Условия', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      for (var index = 0; index < rule.conditions.length; index++)
        _DeleteRow(
          onDelete: () => setState(() => rule.conditions.removeAt(index)),
          child: _conditionEditor(rule.conditions[index], category),
        ),
      TextButton.icon(
        onPressed: category == null || category.fields.isEmpty
            ? null
            : () => setState(
                () => rule.conditions.add(
                  RuleConditionDraft(
                    fieldCode: category.fields.first.fieldCode,
                    operator: 'is_filled',
                  ),
                ),
              ),
        icon: const Icon(Icons.add),
        label: const Text('Добавить условие'),
      ),
    ],
  );

  Widget _conditionEditor(
    RuleConditionDraft condition,
    CatalogCategoryDraft? category,
  ) {
    if (category == null) return const SizedBox.shrink();
    return _responsiveFields([
      _ruleFieldSelect(
        category,
        'Поле',
        condition.fieldCode,
        const [],
        (value) => setState(() => condition.fieldCode = value!),
        required: true,
      ),
      AppSelectField<String>(
        value: condition.operator,
        label: 'Проверка',
        options: const [
          AppSelectOption(value: 'is_true', label: 'Флажок включён'),
          AppSelectOption(value: 'is_false', label: 'Флажок выключен'),
          AppSelectOption(value: 'greater_than_zero', label: 'Больше нуля'),
          AppSelectOption(value: 'is_filled', label: 'Поле заполнено'),
          AppSelectOption(value: 'equals', label: 'Равно значению'),
        ],
        onChanged: (value) =>
            setState(() => condition.operator = value ?? 'is_filled'),
      ),
      if (condition.operator == 'equals')
        _textField('Значение', condition.comparisonValue ?? '', (value) {
          condition.comparisonValue = value;
        }),
    ]);
  }

  Widget _ruleActionsEditor(
    CalculationRuleDraft rule,
    CatalogCategoryDraft? category,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Действия', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      for (var index = 0; index < rule.actions.length; index++)
        _DeleteRow(
          onDelete: () => setState(() => rule.actions.removeAt(index)),
          child: _actionEditor(rule.actions[index], category),
        ),
      TextButton.icon(
        onPressed: () => setState(
          () => rule.actions.add(RuleActionDraft(actionType: 'exclude_row')),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Добавить действие'),
      ),
    ],
  );

  Widget _actionEditor(RuleActionDraft action, CatalogCategoryDraft? category) {
    final actionType = AppSelectField<String>(
      value: action.actionType,
      label: 'Действие',
      options: const [
        AppSelectOption(
          value: 'exclude_row',
          label: 'Исключить строку из расчёта',
        ),
        AppSelectOption(value: 'set_field', label: 'Изменить другое поле'),
        AppSelectOption(value: 'calculate_field', label: 'Рассчитать значение'),
        AppSelectOption(
          value: 'add_related_cards',
          label: 'Добавить связанные карточки',
        ),
        AppSelectOption(
          value: 'remove_related_cards',
          label: 'Удалить связанные карточки',
        ),
        AppSelectOption(
          value: 'set_field_visibility',
          label: 'Скрыть или показать поле',
        ),
        AppSelectOption(value: 'block_save', label: 'Запретить сохранение'),
        AppSelectOption(
          value: 'aggregate_money',
          label: 'Добавить в итог варианта',
        ),
      ],
      onChanged: (value) => setState(() {
        action.actionType = value ?? 'exclude_row';
        action.targetFieldCode = null;
        action.sourceFieldCode = null;
        action.constantValue = null;
        action.booleanValue = null;
        action.dependencyClientId = null;
        action.formula = null;
      }),
    );
    if (category == null) return actionType;

    final controls = <Widget>[actionType];
    switch (action.actionType) {
      case 'exclude_row':
        break;
      case 'set_field':
        controls.addAll([
          _ruleFieldSelect(
            category,
            'Изменить поле',
            action.targetFieldCode,
            const [],
            (value) => setState(() => action.targetFieldCode = value),
            required: true,
          ),
          _ruleFieldSelect(
            category,
            'Взять значение из',
            action.sourceFieldCode,
            const [],
            (value) => setState(() => action.sourceFieldCode = value),
            required: true,
          ),
        ]);
        break;
      case 'calculate_field':
        controls.add(
          _ruleFieldSelect(
            category,
            'Записать результат в',
            action.targetFieldCode,
            const ['number', 'money', 'percent', 'calculated_money'],
            (value) => setState(() => action.targetFieldCode = value),
            required: true,
          ),
        );
        break;
      case 'add_related_cards':
      case 'remove_related_cards':
        final dependencies = draft.dependencies
            .where(
              (dependency) =>
                  dependency.targetCategoryClientId == category.clientId,
            )
            .toList();
        controls.add(
          AppSelectField<String>(
            value:
                dependencies.any(
                  (item) => item.clientId == action.dependencyClientId,
                )
                ? action.dependencyClientId
                : null,
            label: 'Зависимость',
            options: [
              for (final dependency in dependencies)
                AppSelectOption(
                  value: dependency.clientId,
                  label: _dependencyLabel(dependency),
                ),
            ],
            onChanged: (value) =>
                setState(() => action.dependencyClientId = value),
          ),
        );
        break;
      case 'set_field_visibility':
        controls.addAll([
          _ruleFieldSelect(
            category,
            'Поле',
            action.targetFieldCode,
            const [],
            (value) => setState(() => action.targetFieldCode = value),
            required: true,
          ),
          AppSelectField<bool>(
            value: action.booleanValue,
            label: 'Видимость',
            options: const [
              AppSelectOption(value: true, label: 'Показать'),
              AppSelectOption(value: false, label: 'Скрыть'),
            ],
            onChanged: (value) => setState(() => action.booleanValue = value),
          ),
        ]);
        break;
      case 'block_save':
        controls.add(
          _textField(
            'Сообщение пользователю',
            action.message ?? '',
            (value) => action.message = value,
          ),
        );
        break;
      case 'aggregate_money':
        controls.addAll([
          _ruleFieldSelect(
            category,
            'Денежное поле',
            action.sourceFieldCode,
            const ['money', 'calculated_money'],
            (value) => setState(() => action.sourceFieldCode = value),
            required: true,
          ),
          AppSelectField<String>(
            value: action.aggregationOperation,
            label: 'Операция',
            options: const [
              AppSelectOption(value: 'add', label: 'Прибавить'),
              AppSelectOption(value: 'subtract', label: 'Вычесть'),
            ],
            onChanged: (value) => setState(() {
              action.aggregationOperation = value;
              action.aggregationTarget = 'variant_total';
            }),
          ),
        ]);
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _responsiveFields(controls),
        if (action.actionType == 'calculate_field') ...[
          const SizedBox(height: 12),
          _formulaEditor(action, category),
        ],
        if (action.actionType == 'aggregate_money') ...[
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Учитывать количество'),
            value: action.multiplyByQuantity,
            onChanged: (value) => setState(() {
              action.multiplyByQuantity = value ?? false;
              if (!action.multiplyByQuantity) action.quantityFieldCode = null;
            }),
          ),
          if (action.multiplyByQuantity)
            _ruleFieldSelect(
              category,
              'Поле количества',
              action.quantityFieldCode,
              const ['number'],
              (value) => setState(() => action.quantityFieldCode = value),
              required: true,
            ),
        ],
      ],
    );
  }

  String _dependencyLabel(CategoryDependencyDraft dependency) {
    final source = _categoryByClientId(dependency.sourceCategoryClientId);
    final target = _categoryByClientId(dependency.targetCategoryClientId);
    return '${source?.name ?? 'Категория'} → ${target?.name ?? 'Категория'}';
  }

  Widget _formulaEditor(RuleActionDraft action, CatalogCategoryDraft category) {
    final formula = action.formula ??= FormulaDraft();
    final numeric = _numericFields(category, const [
      'number',
      'money',
      'percent',
      'calculated_money',
    ]);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF0B141F),
        border: Border.all(color: const Color(0xFF2A405A)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Визуальная формула',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Container(
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF101C2B),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var index = 0; index < formula.tokens.length; index++)
                    InputChip(
                      label: Text(
                        _formulaTokenLabel(formula.tokens[index], category),
                      ),
                      onDeleted: () =>
                          setState(() => formula.tokens.removeAt(index)),
                    ),
                  if (formula.tokens.isEmpty)
                    const Text(
                      'Добавьте поле, число, операцию или скобку.',
                      style: TextStyle(color: Color(0xFF8FA4C2)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                PopupMenuButton<CatalogFieldDraft>(
                  onSelected: (field) => setState(
                    () => formula.tokens.add(
                      FormulaTokenDraft(
                        tokenType: 'field',
                        fieldCode: field.fieldCode,
                      ),
                    ),
                  ),
                  itemBuilder: (context) => [
                    for (final field in numeric)
                      PopupMenuItem(
                        value: field,
                        child: Text(catalogFieldLabel(field)),
                      ),
                  ],
                  child: const Chip(label: Text('+ Поле')),
                ),
                ActionChip(
                  label: const Text('+ Число'),
                  onPressed: () async {
                    final value = await _askFormulaConstant();
                    if (!mounted || value == null) return;
                    setState(
                      () => formula.tokens.add(
                        FormulaTokenDraft(
                          tokenType: 'constant',
                          constantValue: value,
                        ),
                      ),
                    );
                  },
                ),
                for (final operation in const [
                  ('add', '+'),
                  ('subtract', '−'),
                  ('multiply', '×'),
                  ('divide', '÷'),
                ])
                  ActionChip(
                    label: Text(operation.$2),
                    onPressed: () => setState(
                      () => formula.tokens.add(
                        FormulaTokenDraft(
                          tokenType: 'operator',
                          operator: operation.$1,
                        ),
                      ),
                    ),
                  ),
                ActionChip(
                  label: const Text('('),
                  onPressed: () => setState(
                    () => formula.tokens.add(
                      FormulaTokenDraft(tokenType: 'open_group'),
                    ),
                  ),
                ),
                ActionChip(
                  label: const Text(')'),
                  onPressed: () => setState(
                    () => formula.tokens.add(
                      FormulaTokenDraft(tokenType: 'close_group'),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: formula.tokens.isEmpty
                      ? null
                      : () => setState(formula.tokens.clear),
                  child: const Text('Очистить'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: 220,
              child: AppSelectField<int>(
                value: formula.decimalPlaces,
                label: 'Округление результата',
                options: [
                  for (var value = 0; value <= 6; value++)
                    AppSelectOption(value: value, label: '$value знаков'),
                ],
                onChanged: (value) =>
                    setState(() => formula.decimalPlaces = value ?? 2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<num?> _askFormulaConstant() async {
    final controller = TextEditingController();
    final result = await showDialog<num>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Добавить число'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]')),
          ],
          decoration: const InputDecoration(labelText: 'Значение'),
          onSubmitted: (_) {
            final value = num.tryParse(controller.text.replaceAll(',', '.'));
            if (value != null) Navigator.pop(dialogContext, value);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final value = num.tryParse(controller.text.replaceAll(',', '.'));
              if (value != null) Navigator.pop(dialogContext, value);
            },
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  String _formulaTokenLabel(
    FormulaTokenDraft token,
    CatalogCategoryDraft category,
  ) => switch (token.tokenType) {
    'field' => '[${_categoryFieldLabel(category, token.fieldCode ?? '')}]',
    'constant' => '${token.constantValue}',
    'operator' => switch (token.operator) {
      'add' => '+',
      'subtract' => '−',
      'multiply' => '×',
      'divide' => '÷',
      _ => '?',
    },
    'open_group' => '(',
    'close_group' => ')',
    _ => '?',
  };

  Widget _ruleFieldSelect(
    CatalogCategoryDraft category,
    String label,
    String? value,
    List<String> allowedTypes,
    ValueChanged<String?> onChanged, {
    bool required = false,
  }) {
    final fields = allowedTypes.isEmpty
        ? category.fields
        : _numericFields(category, allowedTypes);
    final selected = fields.any((field) => field.fieldCode == value)
        ? value
        : null;
    return AppSelectField<String>(
      value: selected,
      label: label,
      options: [
        if (!required)
          const AppSelectOption(value: null, label: 'Не используется'),
        for (final field in fields)
          AppSelectOption(
            value: field.fieldCode,
            label: catalogFieldLabel(field),
          ),
      ],
      onChanged: onChanged,
    );
  }

  List<CatalogFieldDraft> _numericFields(
    CatalogCategoryDraft category,
    List<String> allowedTypes,
  ) => category.fields
      .where((field) => allowedTypes.contains(catalogFieldType(field)))
      .toList();

  Widget _rolesEditor() => Column(
    children: [
      const _InfoBanner(
        'Директор всегда имеет полный доступ. Ниже создаются только дополнительные роли.',
      ),
      const SizedBox(height: 14),
      for (var roleIndex = 0; roleIndex < draft.roles.length; roleIndex++)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: _SubPanel(
            title: draft.roles[roleIndex].name,
            expanded: !_collapsedRoles.contains(draft.roles[roleIndex]),
            onToggle: () => setState(
              () => _toggleCollapsed(_collapsedRoles, draft.roles[roleIndex]),
            ),
            collapseTooltip: 'Свернуть роль',
            expandTooltip: 'Развернуть роль',
            onDelete: () => setState(() {
              final role = draft.roles.removeAt(roleIndex);
              _collapsedRoles.remove(role);
            }),
            child: Column(
              children: [
                _textField('Название роли', draft.roles[roleIndex].name, (
                  value,
                ) {
                  setState(() => draft.roles[roleIndex].name = value);
                }),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final permission in _permissions.entries)
                      FilterChip(
                        label: Text(permission.value),
                        selected: draft.roles[roleIndex].permissionCodes
                            .contains(permission.key),
                        onSelected: (selected) => setState(() {
                          final permissions =
                              draft.roles[roleIndex].permissionCodes;
                          selected
                              ? permissions.add(permission.key)
                              : permissions.remove(permission.key);
                        }),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () => setState(
            () => draft.roles.add(
              OnboardingRoleDraft(name: 'Новая роль', permissionCodes: []),
            ),
          ),
          icon: const Icon(Icons.add),
          label: const Text('Добавить роль'),
        ),
      ),
    ],
  );

  Widget _dictionariesEditor() => Column(
    children: [
      for (
        var dictionaryIndex = 0;
        dictionaryIndex < draft.dictionaries.length;
        dictionaryIndex++
      )
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: _SubPanel(
            title: draft.dictionaries[dictionaryIndex].name,
            expanded: !_collapsedDictionaries.contains(
              draft.dictionaries[dictionaryIndex],
            ),
            onToggle: () => setState(
              () => _toggleCollapsed(
                _collapsedDictionaries,
                draft.dictionaries[dictionaryIndex],
              ),
            ),
            collapseTooltip: 'Свернуть справочник',
            expandTooltip: 'Развернуть справочник',
            onDelete: () => setState(() {
              final dictionary = draft.dictionaries.removeAt(dictionaryIndex);
              _collapsedDictionaries.remove(dictionary);
            }),
            child: Column(
              children: [
                _textField(
                  'Название',
                  draft.dictionaries[dictionaryIndex].name,
                  (value) {
                    setState(
                      () => draft.dictionaries[dictionaryIndex].name = value,
                    );
                  },
                ),
                const SizedBox(height: 10),
                for (
                  var itemIndex = 0;
                  itemIndex < draft.dictionaries[dictionaryIndex].items.length;
                  itemIndex++
                )
                  _DeleteRow(
                    onDelete: () => setState(
                      () => draft.dictionaries[dictionaryIndex].items.removeAt(
                        itemIndex,
                      ),
                    ),
                    child: _textField(
                      'Значение',
                      draft
                          .dictionaries[dictionaryIndex]
                          .items[itemIndex]
                          .value,
                      (value) =>
                          draft
                                  .dictionaries[dictionaryIndex]
                                  .items[itemIndex]
                                  .value =
                              value,
                    ),
                  ),
                TextButton.icon(
                  onPressed: () => setState(
                    () => draft.dictionaries[dictionaryIndex].items.add(
                      DictionaryItemDraft('Новое значение'),
                    ),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Добавить значение'),
                ),
              ],
            ),
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () => setState(
            () => draft.dictionaries.add(
              DictionaryDraft(
                code: _nextDictionaryCode(),
                name: 'Новый справочник',
                items: [],
              ),
            ),
          ),
          icon: const Icon(Icons.add),
          label: const Text('Добавить справочник'),
        ),
      ),
    ],
  );

  /// Возвращает первый свободный технический код справочника.
  /// Код не зависит от названия и остаётся стабильным после переименования.
  String _nextDictionaryCode() {
    final usedCodes = draft.dictionaries
        .map((dictionary) => dictionary.code)
        .toSet();
    var number = 1;
    while (usedCodes.contains('dictionary_$number')) {
      number++;
    }
    return 'dictionary_$number';
  }

  Widget _review() => Column(
    children: [
      const _InfoBanner(
        'После активации структура станет рабочей. Дальнейшие изменения выполняются в настройках организации.',
      ),
      const SizedBox(height: 16),
      _ReviewRow('Организация', draft.company.organizationName),
      _ReviewRow('Канбаны', '${draft.workflows.length}'),
      _ReviewRow(
        'Столбцы',
        '${draft.workflows.fold<int>(0, (sum, item) => sum + item.columns.length)}',
      ),
      _ReviewRow('Категории', '${draft.categories.length}'),
      _ReviewRow('Поля', '${draft.fields.length}'),
      _ReviewRow('Денежные конвейеры', '${draft.moneyPipelines.length}'),
      _ReviewRow('Событийные правила', '${draft.rules.length}'),
      _ReviewRow('Зависимости', '${draft.dependencies.length}'),
      _ReviewRow('Дополнительные роли', '${draft.roles.length}'),
      _ReviewRow('Справочники', '${draft.dictionaries.length}'),
    ],
  );

  Widget _preview() => _Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Предварительный просмотр',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 18),
        Center(
          child: Column(
            children: [
              const _RoundIcon(Icons.business_outlined, size: 78),
              const SizedBox(height: 14),
              Text(
                draft.company.organizationName.trim().isEmpty
                    ? 'Название организации'
                    : draft.company.organizationName.trim(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              const _StatusChip(),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 8),
        _PreviewRow(
          Icons.business_center_outlined,
          'Тип компании',
          draft.company.companyType,
        ),
        _PreviewRow(
          Icons.description_outlined,
          'Юридическое название',
          draft.company.legalName,
          stacked: true,
        ),
        _PreviewRow(Icons.badge_outlined, 'ИНН', draft.company.inn),
        _PreviewRow(Icons.credit_card_outlined, 'КПП', draft.company.kpp),
        _PreviewRow(Icons.article_outlined, 'ОГРН', draft.company.ogrn),
        _PreviewRow(Icons.location_on_outlined, 'Адрес', draft.company.address),
        _PreviewRow(Icons.phone_outlined, 'Телефон', draft.company.phone),
        _PreviewRow(Icons.email_outlined, 'Email', draft.company.email),
        if (step > 0) ...[
          const SizedBox(height: 14),
          const Divider(),
          const SizedBox(height: 8),
          _ReviewRow('Канбаны', '${draft.workflows.length}'),
          _ReviewRow('Категории', '${draft.categories.length}'),
          _ReviewRow('Зависимости', '${draft.dependencies.length}'),
          _ReviewRow('Роли', '${draft.roles.length + 1}'),
        ],
      ],
    ),
  );

  Widget _textField(
    String label,
    String value,
    ValueChanged<String> onChanged, {
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String value)? validator,
  }) => TextFormField(
    initialValue: value,
    onChanged: onChanged,
    keyboardType: keyboardType,
    inputFormatters: inputFormatters,
    autovalidateMode: AutovalidateMode.onUserInteraction,
    validator: validator == null ? null : (value) => validator(value ?? ''),
    enableInteractiveSelection: true,
    decoration: InputDecoration(labelText: label),
  );

  Widget _responsiveFields(List<Widget> fields) => LayoutBuilder(
    builder: (context, constraints) => constraints.maxWidth < 620
        ? Column(
            children: [
              for (var index = 0; index < fields.length; index++) ...[
                fields[index],
                if (index + 1 < fields.length) const SizedBox(height: 12),
              ],
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < fields.length; index++) ...[
                Expanded(child: fields[index]),
                if (index + 1 < fields.length) const SizedBox(width: 12),
              ],
            ],
          ),
  );

  static void _move<T>(List<T> items, int from, int to) {
    if (to < 0 || to >= items.length) return;
    final item = items.removeAt(from);
    items.insert(to, item);
  }

  static bool _hasTransition(WorkflowDraft workflow, String from, String to) =>
      workflow.transitions.any(
        (transition) =>
            transition.fromClientId == from && transition.toClientId == to,
      );

  static void _setTransition(
    WorkflowDraft workflow,
    String from,
    String to,
    bool enabled,
  ) {
    workflow.transitions.removeWhere(
      (transition) =>
          transition.fromClientId == from && transition.toClientId == to,
    );
    if (enabled) {
      workflow.transitions.add(
        WorkflowTransitionDraft(fromClientId: from, toClientId: to),
      );
    }
  }

  static void _allowAllTransitions(WorkflowDraft workflow) {
    workflow.transitions = [
      for (final from in workflow.columns)
        for (final to in workflow.columns)
          if (from.clientId != to.clientId)
            WorkflowTransitionDraft(
              fromClientId: from.clientId,
              toClientId: to.clientId,
            ),
    ];
  }
}

final class _Header extends StatelessWidget {
  const _Header({required this.wide, required this.settingsMode});
  final bool wide;
  final bool settingsMode;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(wide ? 28 : 16, 20, wide ? 28 : 16, 12),
    child: Row(
      children: [
        const _BrandCube(),
        const SizedBox(width: 12),
        const Text(
          'Склад Комфорта',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 18),
        Container(width: 1, height: 28, color: const Color(0xFF314056)),
        const SizedBox(width: 18),
        Expanded(
          child: Text(
            settingsMode ? 'Настройки организации' : 'Создание организации',
            style: TextStyle(
              fontSize: wide ? 22 : 17,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Горизонтальные вкладки рабочего редактора без семантики обязательных шагов.
final class _SettingsTabs extends StatelessWidget {
  const _SettingsTabs({required this.step, required this.onSelect});
  final int step;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => MobileCollapsibleNavigation(
    title: 'Навигация настроек',
    summary: _OrganizationOnboardingPageState._steps[step].$1,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 12),
      decoration: const BoxDecoration(
        color: Color(0xFF0D151F),
        border: Border(bottom: BorderSide(color: Color(0xFF25364C))),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Center(
              child: SegmentedButton<int>(
                segments: [
                  for (final index
                      in _OrganizationOnboardingPageState._settingsStepIndexes)
                    ButtonSegment<int>(
                      value: index,
                      icon: Icon(
                        _OrganizationOnboardingPageState._steps[index].$2,
                        size: 17,
                      ),
                      label: Text(
                        _OrganizationOnboardingPageState._steps[index].$1,
                      ),
                    ),
                ],
                selected: {step},
                showSelectedIcon: false,
                onSelectionChanged: (values) => onSelect(values.first),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

final class _Progress extends StatelessWidget {
  const _Progress({
    required this.step,
    required this.wide,
    required this.onSelect,
  });
  final int step;
  final bool wide;
  final ValueChanged<int> onSelect;
  static const labels = [
    'Компания',
    'Канбаны',
    'Каталог',
    'Поля',
    'Правила и расчёты',
    'Зависимости',
    'Роли',
    'Справочники',
    'Проверка',
  ];
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(horizontal: wide ? 28 : 16, vertical: 12),
    child: wide
        ? Row(
            children: [
              for (var index = 0; index < labels.length; index++) ...[
                Expanded(
                  child: InkWell(
                    onTap: () => onSelect(index),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                height: 2,
                                color: index <= step
                                    ? const Color(0xFF4D8DFF)
                                    : const Color(0xFF3A4656),
                              ),
                            ),
                            _StepCircle(
                              index: index,
                              active: index == step,
                              completed: index < step,
                            ),
                            Expanded(
                              child: Container(
                                height: 2,
                                color: index < step
                                    ? const Color(0xFF4D8DFF)
                                    : const Color(0xFF3A4656),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${index + 1}. ${labels[index]}',
                          style: TextStyle(
                            color: index == step
                                ? const Color(0xFF4D8DFF)
                                : const Color(0xFF8FA4C2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          )
        : Row(
            children: [
              _StepCircle(index: step, active: true, completed: false),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${step + 1} из 9 · ${labels[step]}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              SizedBox(
                width: 90,
                child: LinearProgressIndicator(
                  value: (step + 1) / 9,
                  minHeight: 5,
                ),
              ),
            ],
          ),
  );
}

final class _StepCircle extends StatelessWidget {
  const _StepCircle({
    required this.index,
    required this.active,
    required this.completed,
  });
  final int index;
  final bool active;
  final bool completed;
  @override
  Widget build(BuildContext context) => Container(
    width: 32,
    height: 32,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: active || completed
          ? const Color(0xFF246FE5)
          : const Color(0xFF111A27),
      border: Border.all(
        color: active || completed
            ? const Color(0xFFA9C8FF)
            : const Color(0xFF65758B),
        width: 1.5,
      ),
    ),
    child: completed ? const Icon(Icons.check, size: 17) : Text('${index + 1}'),
  );
}

final class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 3),
      Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

final class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Text(message, style: Theme.of(context).textTheme.bodySmall),
  );
}

final class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xD9111A27),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: const Color(0xFF2A394E)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x33000000),
          blurRadius: 24,
          offset: Offset(0, 12),
        ),
      ],
    ),
    child: Padding(padding: const EdgeInsets.all(24), child: child),
  );
}

/// Раскрываемый раздел каталога без системного accessibility-announcement.
/// Стандартный ExpansionTile на Windows отправляет некорректный `viewId`,
/// поэтому здесь состояние контролируется родительским экраном напрямую.
final class _CatalogSectionPanel extends StatelessWidget {
  const _CatalogSectionPanel({
    required this.title,
    required this.expanded,
    required this.onToggle,
    required this.onDelete,
    required this.child,
  });

  final String title;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Semantics(
        button: true,
        label: expanded ? 'Свернуть раздел' : 'Развернуть раздел',
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: AnimatedRotation(
                    turns: expanded ? .5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(Icons.keyboard_arrow_down),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Semantics(
                  button: true,
                  label: 'Удалить раздел',
                  child: IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.topCenter,
        child: expanded ? child : const SizedBox.shrink(),
      ),
    ],
  );
}

final class _SubPanel extends StatelessWidget {
  const _SubPanel({
    required this.title,
    required this.child,
    this.onDelete,
    this.onToggle,
    this.expanded = true,
    this.collapseTooltip = 'Свернуть блок',
    this.expandTooltip = 'Развернуть блок',
  });
  final String title;
  final Widget child;
  final VoidCallback? onDelete;
  final VoidCallback? onToggle;
  final bool expanded;
  final String collapseTooltip;
  final String expandTooltip;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFF0D151F),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFF28384E)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (onToggle != null)
                Semantics(
                  button: true,
                  label: expanded ? collapseTooltip : expandTooltip,
                  child: IconButton(
                    onPressed: onToggle,
                    icon: AnimatedRotation(
                      turns: expanded ? .5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: const Icon(Icons.keyboard_arrow_down),
                    ),
                  ),
                ),
              if (onDelete != null)
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Удалить',
                ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            alignment: Alignment.topCenter,
            child: expanded
                ? Padding(padding: const EdgeInsets.only(top: 12), child: child)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    ),
  );
}

final class _RoundIcon extends StatelessWidget {
  const _RoundIcon(this.icon, {this.size = 50});
  final IconData icon;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: const Color(0x172E7DFF),
      border: Border.all(color: const Color(0xFF2E7DFF)),
    ),
    child: Icon(icon, color: const Color(0xFF67A0FF), size: size * .46),
  );
}

final class _BrandCube extends StatelessWidget {
  const _BrandCube();
  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 32,
    child: Icon(Icons.view_in_ar_outlined, color: Color(0xFF4D8DFF), size: 32),
  );
}

final class _StatusChip extends StatelessWidget {
  const _StatusChip();
  @override
  Widget build(BuildContext context) => const Chip(
    avatar: Icon(Icons.circle, size: 9, color: Color(0xFF67A0FF)),
    label: Text('Организация ещё не активирована'),
  );
}

final class _PreviewRow extends StatelessWidget {
  const _PreviewRow(this.icon, this.label, this.value, {this.stacked = false});
  final IconData icon;
  final String label;
  final String? value;
  final bool stacked;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: const Color(0xFF8FA4C2)),
        const SizedBox(width: 12),
        Expanded(
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(color: Color(0xFF8FA4C2)),
                    ),
                    const SizedBox(height: 4),
                    Text(value?.trim().isNotEmpty == true ? value! : '—'),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(color: Color(0xFF8FA4C2)),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        value?.trim().isNotEmpty == true ? value! : '—',
                      ),
                    ),
                  ],
                ),
        ),
      ],
    ),
  );
}

final class _ReviewRow extends StatelessWidget {
  const _ReviewRow(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: Color(0xFF8FA4C2))),
        ),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );
}

final class _DeleteRow extends StatelessWidget {
  const _DeleteRow({required this.child, required this.onDelete});
  final Widget child;
  final VoidCallback onDelete;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Expanded(child: child),
        IconButton(
          onPressed: onDelete,
          tooltip: 'Удалить',
          icon: const Icon(Icons.close),
        ),
      ],
    ),
  );
}

final class _OrderedRow extends StatelessWidget {
  const _OrderedRow({
    super.key,
    required this.index,
    required this.length,
    required this.child,
    required this.onMove,
    required this.onDelete,
  });
  final int index;
  final int length;
  final Widget child;
  final ValueChanged<int> onMove;
  final VoidCallback? onDelete;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        IconButton(
          onPressed: index > 0 ? () => onMove(-1) : null,
          icon: const Icon(Icons.arrow_upward),
          tooltip: 'Выше',
        ),
        IconButton(
          onPressed: index + 1 < length ? () => onMove(1) : null,
          icon: const Icon(Icons.arrow_downward),
          tooltip: 'Ниже',
        ),
        Expanded(child: child),
        IconButton(
          onPressed: onDelete,
          icon: Icon(onDelete == null ? Icons.lock_outline : Icons.close),
          tooltip: onDelete == null
              ? 'Системное поле нельзя удалить'
              : 'Удалить',
        ),
      ],
    ),
  );
}

final class _CompactFlag extends StatelessWidget {
  const _CompactFlag({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 142,
    child: CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(label, maxLines: 1, style: const TextStyle(fontSize: 12)),
      value: value,
      onChanged: onChanged == null
          ? null
          : (selected) => onChanged!(selected ?? false),
    ),
  );
}

final class _FieldTypeBadge extends StatelessWidget {
  const _FieldTypeBadge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 112),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    decoration: BoxDecoration(
      color: const Color(0xFF101C2B),
      border: Border.all(color: const Color(0xFF2A405A)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      label,
      textAlign: TextAlign.center,
      style: const TextStyle(color: Color(0xFF9DB2CE), fontSize: 12),
    ),
  );
}

final class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0x553A1420),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFF8F3652)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFFF7A9E)),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}

final class _InfoBanner extends StatelessWidget {
  const _InfoBanner(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0x332E7DFF),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFF315D97)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Color(0xFF67A0FF)),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}
