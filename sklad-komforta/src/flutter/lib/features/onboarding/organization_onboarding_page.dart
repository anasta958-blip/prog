import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sklad_komforta_app/features/auth/auth_controller.dart';
import 'package:sklad_komforta_app/features/onboarding/onboarding_field_registry.dart';
import 'package:sklad_komforta_app/features/onboarding/onboarding_models.dart';

/// Полноэкранный семишаговый мастер создания изолированной организации.
final class OrganizationOnboardingPage extends StatefulWidget {
  const OrganizationOnboardingPage({required this.controller, super.key});

  /// Общий auth controller, владеющий tenant JWT и сетевым состоянием.
  final AuthController controller;

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
  static final _digitsOnly = FilteringTextInputFormatter.digitsOnly;

  late OrganizationOnboardingDraft draft;
  late int step;
  final _companyFormKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    draft =
        widget.controller.onboardingDraft ??
        OrganizationOnboardingDraft.initial();
    step = draft.currentStep.clamp(1, 7) - 1;
  }

  /// Сохраняет агрегат целиком, чтобы сервер мог проверить межшаговые связи.
  Future<void> _saveAndContinue() async {
    if (step == 0 && !(_companyFormKey.currentState?.validate() ?? false)) {
      _showMessage('Проверьте заполнение реквизитов организации.');
      return;
    }
    draft.currentStep = (step + 2).clamp(1, 7);
    await widget.controller.saveOnboardingStep(draft);
    if (!mounted || widget.controller.error != null) return;
    setState(() {
      draft = widget.controller.onboardingDraft ?? draft;
      step = (step + 1).clamp(0, 6);
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
                _Header(wide: wide),
                _Progress(step: step, wide: wide, onSelect: _selectStep),
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

  void _selectStep(int value) {
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
                '${step + 1}. ${_steps[step].$1}',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        if (widget.controller.error != null) ...[
          _ErrorBanner(widget.controller.error!),
          const SizedBox(height: 16),
        ],
        _stepBody(),
        const SizedBox(height: 24),
        Row(
          children: [
            if (step > 0)
              OutlinedButton.icon(
                onPressed: widget.controller.busy
                    ? null
                    : () => setState(() => step--),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Назад'),
              ),
            const Spacer(),
            SizedBox(
              width: 250,
              child: FilledButton.icon(
                onPressed: widget.controller.busy
                    ? null
                    : step == 6
                    ? widget.controller.activateOrganization
                    : _saveAndContinue,
                icon: widget.controller.busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        step == 6
                            ? Icons.verified_outlined
                            : Icons.arrow_forward,
                      ),
                label: Text(
                  step == 6
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
    4 => _rolesEditor(),
    5 => _dictionariesEditor(),
    _ => _review(),
  };

  Widget _companyEditor() {
    final company = draft.company;
    return Form(
      key: _companyFormKey,
      child: Column(
        children: [
          _responsiveFields([
            _textField(
              'Название организации',
              company.organizationName,
              (value) => setState(() => company.organizationName = value),
              validator: (value) => value.trim().length < 2
                  ? 'Введите не менее двух символов'
                  : null,
            ),
            DropdownButtonFormField<String>(
              initialValue: company.companyType,
              decoration: const InputDecoration(labelText: 'Тип компании'),
              items: const [
                DropdownMenuItem(value: 'ООО', child: Text('ООО')),
                DropdownMenuItem(value: 'ИП', child: Text('ИП')),
                DropdownMenuItem(value: 'АО', child: Text('АО')),
              ],
              onChanged: (value) => setState(() => company.companyType = value),
            ),
          ]),
          const SizedBox(height: 14),
          _textField('Юридическое название', company.legalName ?? '', (value) {
            setState(() => company.legalName = value);
          }),
          const SizedBox(height: 14),
          _responsiveFields([
            _textField(
              'ИНН',
              company.inn ?? '',
              (value) => setState(() => company.inn = value),
              keyboardType: TextInputType.number,
              inputFormatters: [
                _digitsOnly,
                LengthLimitingTextInputFormatter(12),
              ],
              validator: (value) => _validateDigitsLength(value, const {
                10,
                12,
              }, 'ИНН должен содержать 10 или 12 цифр'),
            ),
            _textField(
              'КПП',
              company.kpp ?? '',
              (value) => setState(() => company.kpp = value),
              keyboardType: TextInputType.number,
              inputFormatters: [
                _digitsOnly,
                LengthLimitingTextInputFormatter(9),
              ],
              validator: (value) => _validateDigitsLength(value, const {
                9,
              }, 'КПП должен содержать 9 цифр'),
            ),
            _textField(
              'ОГРН',
              company.ogrn ?? '',
              (value) => setState(() => company.ogrn = value),
              keyboardType: TextInputType.number,
              inputFormatters: [
                _digitsOnly,
                LengthLimitingTextInputFormatter(15),
              ],
              validator: (value) => _validateDigitsLength(value, const {
                13,
                15,
              }, 'ОГРН должен содержать 13 или 15 цифр'),
            ),
          ]),
          const SizedBox(height: 22),
          const Divider(),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Контактные данные',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 14),
          _textField('Адрес', company.address ?? '', (value) {
            setState(() => company.address = value);
          }),
          const SizedBox(height: 14),
          _responsiveFields([
            _textField(
              'Телефон',
              company.phone ?? '',
              (value) => setState(() => company.phone = value),
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+()\-\s]')),
                LengthLimitingTextInputFormatter(24),
              ],
              validator: _validatePhone,
            ),
            _textField(
              'Email',
              company.email ?? '',
              (value) => setState(() => company.email = value),
              keyboardType: TextInputType.emailAddress,
              validator: _validateEmail,
            ),
          ]),
        ],
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
          onPressed: () => setState(
            () => draft.workflows.add(
              WorkflowDraft(
                code: 'workflow_${draft.workflows.length + 1}',
                name: 'Новый канбан',
                columns: [],
                transitions: [],
              ),
            ),
          ),
          icon: const Icon(Icons.add),
          label: const Text('Добавить канбан'),
        ),
      ),
    ],
  );

  Widget _workflowPanel(WorkflowDraft workflow) => _SubPanel(
    title: workflow.name,
    onDelete: () => setState(() => draft.workflows.remove(workflow)),
    child: Column(
      children: [
        _responsiveFields([
          _textField('Код', workflow.code, (value) => workflow.code = value),
          _textField('Название канбана', workflow.name, (value) {
            setState(() => workflow.name = value);
          }),
        ]),
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
            child: DropdownButtonFormField<String>(
              key: ValueKey('${column.clientId}-${column.color}'),
              initialValue: column.color,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Цвет'),
              items: _workflowColors
                  .map(
                    (color) => DropdownMenuItem(
                      value: color,
                      child: _ColorOption(color),
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
          padding: const EdgeInsets.only(bottom: 14),
          child: _SubPanel(
            title: draft.categories[categoryIndex].name,
            onDelete: () =>
                setState(() => draft.categories.removeAt(categoryIndex)),
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
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(
                      draft
                          .categories[categoryIndex]
                          .sections[sectionIndex]
                          .name,
                    ),
                    trailing: IconButton(
                      tooltip: 'Удалить раздел',
                      onPressed: () => setState(
                        () => draft.categories[categoryIndex].sections.removeAt(
                          sectionIndex,
                        ),
                      ),
                      icon: const Icon(Icons.delete_outline),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 14, 4, 0),
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
                        _DeleteRow(
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
                      TextButton.icon(
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
                    ],
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
    const contexts = {
      'quote': 'КП',
      'preliminary_quote': 'ПКП',
      'order': 'Комплектация',
    };
    return Column(
      children: [
        const _InfoBanner(
          'Поля выбираются из системного реестра. Так расчёты скидки, наценки, цены и суммы работают одинаково во всех организациях.',
        ),
        const SizedBox(height: 14),
        for (final category in draft.categories)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _catalogFieldPanel(category),
          ),
        for (final entry in contexts.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _fieldContextPanel(entry.key, entry.value),
          ),
      ],
    );
  }

  Widget _catalogFieldPanel(CatalogCategoryDraft category) => _SubPanel(
    title: 'Карточка категории: ${category.name}',
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
            onDelete: () => setState(() => category.fields.removeAt(index)),
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

  Widget _catalogFieldControls(CatalogFieldDraft field) {
    final definition = onboardingFieldByCode[field.fieldCode]!;
    return _fieldControls(
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
    );
  }

  Widget _fieldContextPanel(String contextCode, String title) {
    final fields = draft.fields
        .where((item) => item.contextCode == contextCode)
        .toList();
    return _SubPanel(
      title: 'Поля: $title',
      child: Column(
        children: [
          for (var index = 0; index < fields.length; index++)
            _OrderedRow(
              index: index,
              length: fields.length,
              onMove: (delta) => setState(
                () => _swapFields(fields[index], fields[index + delta]),
              ),
              onDelete: () =>
                  setState(() => draft.fields.remove(fields[index])),
              child: _fieldControls(
                onboardingFieldByCode[fields[index].fieldCode]!,
                fields[index].isVisible,
                fields[index].isRequired,
                (value) => setState(() {
                  fields[index].isVisible = value;
                  if (!value) fields[index].isRequired = false;
                }),
                onboardingFieldByCode[fields[index].fieldCode]!.canBeRequired &&
                        fields[index].isVisible
                    ? (value) =>
                          setState(() => fields[index].isRequired = value)
                    : null,
              ),
            ),
          _addFieldButton(
            selectedCodes: fields.map((item) => item.fieldCode),
            onSelected: (definition) => setState(
              () => draft.fields.add(
                EntityFieldDraft(
                  contextCode: contextCode,
                  fieldCode: definition.code,
                  label: definition.label,
                  fieldType: definition.fieldType,
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
          _Flag(label: 'Обязательное', value: required, onChanged: onRequired),
        ],
      );
      return constraints.maxWidth < 470
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

  void _swapFields(EntityFieldDraft first, EntityFieldDraft second) {
    final firstIndex = draft.fields.indexOf(first);
    final secondIndex = draft.fields.indexOf(second);
    draft.fields[firstIndex] = second;
    draft.fields[secondIndex] = first;
  }

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
            onDelete: () => setState(() => draft.roles.removeAt(roleIndex)),
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
            onDelete: () =>
                setState(() => draft.dictionaries.removeAt(dictionaryIndex)),
            child: Column(
              children: [
                _responsiveFields([
                  _textField('Код', draft.dictionaries[dictionaryIndex].code, (
                    value,
                  ) {
                    draft.dictionaries[dictionaryIndex].code = value;
                  }),
                  _textField(
                    'Название',
                    draft.dictionaries[dictionaryIndex].name,
                    (value) {
                      setState(
                        () => draft.dictionaries[dictionaryIndex].name = value,
                      );
                    },
                  ),
                ]),
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
                code: 'dictionary_${draft.dictionaries.length + 1}',
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

  static String? _validateDigitsLength(
    String value,
    Set<int> allowedLengths,
    String message,
  ) {
    final normalized = value.trim();
    if (normalized.isEmpty) return null;
    return allowedLengths.contains(normalized.length) ? null : message;
  }

  static String? _validatePhone(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return null;
    final digits = normalized.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 10 && digits.length <= 15
        ? null
        : 'Телефон должен содержать от 10 до 15 цифр';
  }

  static String? _validateEmail(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return null;
    final valid = RegExp(
      r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
      caseSensitive: false,
    ).hasMatch(normalized);
    return valid ? null : 'Введите корректный email';
  }

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
  const _Header({required this.wide});
  final bool wide;
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
            'Создание организации',
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
                  '${step + 1} из 7 · ${labels[step]}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              SizedBox(
                width: 90,
                child: LinearProgressIndicator(
                  value: (step + 1) / 7,
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

final class _SubPanel extends StatelessWidget {
  const _SubPanel({required this.title, required this.child, this.onDelete});
  final String title;
  final Widget child;
  final VoidCallback? onDelete;
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
              if (onDelete != null)
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Удалить',
                ),
            ],
          ),
          const SizedBox(height: 12),
          child,
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

final class _ColorOption extends StatelessWidget {
  const _ColorOption(this.hex);
  final String hex;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: Color(int.parse(hex.substring(1), radix: 16) | 0xFF000000),
          shape: BoxShape.circle,
        ),
      ),
      const SizedBox(width: 7),
      Flexible(child: Text(hex, overflow: TextOverflow.ellipsis)),
    ],
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
  });
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 112,
    child: CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(label, style: const TextStyle(fontSize: 11)),
      value: value,
      onChanged: onChanged == null
          ? null
          : (value) => onChanged!(value ?? false),
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
