import 'package:flutter/material.dart';
import 'package:sklad_komforta_app/core/widgets/mobile_collapsible_navigation.dart';
import 'package:flutter/services.dart';
import 'package:sklad_komforta_app/core/widgets/app_select_field.dart';
import 'package:sklad_komforta_app/features/auth/auth_controller.dart';
import 'package:sklad_komforta_app/features/company/company_profile_form.dart';
import 'package:sklad_komforta_app/features/onboarding/onboarding_field_registry.dart';
import 'package:sklad_komforta_app/features/onboarding/onboarding_models.dart';

/// Полноэкранный восьмишаговый мастер создания изолированной организации.
final class OrganizationOnboardingPage extends StatefulWidget {
  const OrganizationOnboardingPage({
    required this.controller,
    this.settingsDraft,
    this.settingsBusy = false,
    this.settingsError,
    this.onSettingsSave,
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
  final Future<bool> Function(OrganizationOnboardingDraft draft)?
  onSettingsSave;

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
  static const _settingsStepIndexes = [1, 2, 3, 4, 6];
  late OrganizationOnboardingDraft draft;
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
  final Set<CatalogSectionDraft> _expandedCatalogSections =
      <CatalogSectionDraft>{};

  bool get _settingsMode => widget.onSettingsSave != null;
  bool get _busy =>
      _settingsMode ? widget.settingsBusy : widget.controller.busy;
  String? get _error =>
      _settingsMode ? widget.settingsError : widget.controller.error;

  @override
  void initState() {
    super.initState();
    draft =
        widget.settingsDraft ??
        widget.controller.onboardingDraft ??
        OrganizationOnboardingDraft.initial();
    _collapseConfiguredBlocks();
    step = _settingsMode
        ? _settingsStepIndexes.first
        : draft.currentStep.clamp(1, 8) - 1;
  }

  @override
  void didUpdateWidget(covariant OrganizationOnboardingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_settingsMode &&
        widget.settingsDraft != null &&
        !identical(oldWidget.settingsDraft, widget.settingsDraft) &&
        !widget.settingsBusy) {
      draft = widget.settingsDraft!;
      _collapseConfiguredBlocks();
    }
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
    _expandedCatalogSections.clear();
  }

  void _toggleCollapsed<T>(Set<T> collapsedItems, T item) {
    if (!collapsedItems.add(item)) collapsedItems.remove(item);
  }

  /// Сохраняет агрегат целиком, чтобы сервер мог проверить межшаговые связи.
  Future<void> _saveAndContinue() async {
    if (step == 0 && !(_companyFormKey.currentState?.validate() ?? false)) {
      _showMessage('Проверьте заполнение реквизитов организации.');
      return;
    }
    if (_settingsMode) {
      draft.currentStep = 8;
      final saved = await widget.onSettingsSave!(draft);
      if (!mounted || !saved) return;
      setState(() => step = (step + 1).clamp(0, 7));
      return;
    }
    draft.currentStep = (step + 2).clamp(1, 8);
    await widget.controller.saveOnboardingStep(draft);
    if (!mounted || widget.controller.error != null) return;
    setState(() {
      draft = widget.controller.onboardingDraft ?? draft;
      step = (step + 1).clamp(0, 7);
    });
  }

  Future<void> _saveSettings() async {
    draft.currentStep = 8;
    final saved = await widget.onSettingsSave!(draft);
    if (!mounted || !saved) return;
    _showMessage('Настройки организации сохранены.');
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
      draft.currentStep = 8;
      final saved = await widget.onSettingsSave!(draft);
      if (!mounted || !saved) return;
      setState(() => step = value);
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
                    : step == 7
                    ? widget.controller.activateOrganization
                    : _saveAndContinue,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _settingsMode || step == 7
                            ? Icons.save_outlined
                            : Icons.arrow_forward,
                      ),
                label: Text(
                  _settingsMode
                      ? 'Сохранить изменения'
                      : step == 7
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
    4 => _dependenciesEditor(),
    5 => _rolesEditor(),
    6 => _dictionariesEditor(),
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
            onDelete: () => setState(() {
              final category = draft.categories.removeAt(categoryIndex);
              _collapsedCategoryIds.remove(category.clientId);
              _expandedCatalogSections.removeAll(category.sections);
              draft.dependencies.removeWhere(
                (dependency) =>
                    dependency.sourceCategoryClientId == category.clientId ||
                    dependency.targetCategoryClientId == category.clientId,
              );
              for (final workflow in draft.workflows) {
                workflow.categories.removeWhere(
                  (item) => item.categoryClientId == category.clientId,
                );
              }
            }),
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
                label: onboardingFieldByCode[field.fieldCode]!.label,
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
          .where(
            (field) =>
                onboardingFieldByCode[field.fieldCode]?.fieldType == 'relation',
          )
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
              onDelete: () => setState(() {
                final field = category.fields.removeAt(index);
                draft.dependencies.removeWhere(
                  (dependency) =>
                      dependency.targetCategoryClientId == category.clientId &&
                      dependency.targetFieldCode == field.fieldCode,
                );
                _removeUnavailableWorkflowField(category, field.fieldCode);
              }),
              child: _catalogFieldControls(category.fields[index]),
            ),
          _addFieldButton(
            selectedCodes: category.fields.map((item) => item.fieldCode),
            onSelected: (definition) => setState(
              () => category.fields.add(
                CatalogFieldDraft(
                  fieldCode: definition.code,
                  isVisible: true,
                  isRequired: definition.code == 'name',
                ),
              ),
            ),
          ),
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
      final definition = onboardingFieldByCode[field.fieldCode];
      if (definition != null && added.add(definition.code)) {
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
                          title: Text(definition.label),
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
    final definition = onboardingFieldByCode[field.fieldCode]!;
    return Column(
      children: [
        _fieldControls(
          definition,
          field.isVisible,
          field.isRequired,
          (value) => setState(() {
            field.isVisible = value;
            if (!value) field.isRequired = false;
          }),
          definition.canBeRequired && field.isVisible
              ? (value) => setState(() => field.isRequired = value)
              : null,
        ),
        if (definition.fieldType == 'dictionary' &&
            definition.code != 'group') ...[
          const SizedBox(height: 8),
          AppSelectField<String>(
            value:
                draft.dictionaries.any(
                  (dictionary) => dictionary.code == field.dictionaryCode,
                )
                ? field.dictionaryCode
                : null,
            label: 'Источник значений',
            options: [
              const AppSelectOption(value: null, label: 'Справочник не выбран'),
              for (final dictionary in draft.dictionaries)
                AppSelectOption(value: dictionary.code, label: dictionary.name),
            ],
            onChanged: (value) => setState(() => field.dictionaryCode = value),
          ),
        ],
      ],
    );
  }

  Widget _fieldControls(
    OnboardingFieldDefinition definition,
    bool visible,
    bool required,
    ValueChanged<bool> onVisible,
    ValueChanged<bool>? onRequired,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final title = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            definition.label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 3),
          Text(
            '${definition.group} · ${definition.isCalculated ? 'расчётное' : definition.fieldType}',
            style: const TextStyle(color: Color(0xFF8FA4C2), fontSize: 12),
          ),
        ],
      );
      final flags = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Flag(label: 'Показывать', value: visible, onChanged: onVisible),
          if (definition.isCalculated)
            const _Flag(
              label: 'Рассчитывается',
              value: true,
              onChanged: null,
              tooltip:
                  'Значение вычисляется автоматически и не вводится пользователем.',
            )
          else
            _Flag(
              label: 'Обязательное',
              value: required,
              onChanged: onRequired,
              tooltip:
                  'Без значения этого поля позицию нельзя будет сохранить.',
            ),
        ],
      );
      return constraints.maxWidth < 620
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [title, flags],
            )
          : Row(
              children: [
                Expanded(child: title),
                flags,
              ],
            );
    },
  );

  Widget _addFieldButton({
    required Iterable<String> selectedCodes,
    required ValueChanged<OnboardingFieldDefinition> onSelected,
  }) {
    final selected = selectedCodes.toSet();
    final available = onboardingFieldDefinitions
        .where((definition) => !selected.contains(definition.code))
        .toList();
    return Align(
      alignment: Alignment.centerLeft,
      child: PopupMenuButton<OnboardingFieldDefinition>(
        enabled: available.isNotEmpty,
        onSelected: onSelected,
        itemBuilder: (context) => [
          for (final definition in available)
            PopupMenuItem(
              value: definition,
              child: Text('${definition.label} · ${definition.group}'),
            ),
        ],
        child: IgnorePointer(
          child: TextButton.icon(
            onPressed: available.isEmpty ? null : () {},
            icon: const Icon(Icons.add),
            label: Text(
              available.isEmpty ? 'Все поля добавлены' : 'Добавить поле',
            ),
          ),
        ),
      ),
    );
  }

  List<CatalogFieldDraft> _defaultCatalogFields() => [
    for (final code in defaultCatalogFieldCodes)
      CatalogFieldDraft(
        fieldCode: code,
        isVisible: true,
        isRequired: code == 'name' || code == 'quantity',
      ),
  ];

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
                  '${step + 1} из 8 · ${labels[step]}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              SizedBox(
                width: 90,
                child: LinearProgressIndicator(
                  value: (step + 1) / 8,
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
  final VoidCallback onDelete;
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
          icon: const Icon(Icons.close),
          tooltip: 'Удалить',
        ),
      ],
    ),
  );
}

final class _Flag extends StatelessWidget {
  const _Flag({
    required this.label,
    required this.value,
    required this.onChanged,
    this.tooltip,
  });
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? tooltip;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip ?? '',
    child: SizedBox(
      width: 154,
      child: CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(
          label,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.visible,
          style: const TextStyle(fontSize: 12),
        ),
        value: value,
        onChanged: onChanged == null
            ? null
            : (value) => onChanged!(value ?? false),
      ),
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
