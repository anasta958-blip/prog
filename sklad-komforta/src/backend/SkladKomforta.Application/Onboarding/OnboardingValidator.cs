using SkladKomforta.Application.Identity;
using SkladKomforta.Application.Quotes;
using System.Diagnostics.CodeAnalysis;
using System.Net.Mail;

namespace SkladKomforta.Application.Onboarding;

/// <summary>Централизует ограничения черновика, общие для сохранения и активации.</summary>
public static class OnboardingValidator
{
    private static readonly HashSet<string> WorkflowSpecializations =
        [
            WorkflowSpecializationCodes.Quote,
            WorkflowSpecializationCodes.Prequote,
            WorkflowSpecializationCodes.QuoteAndPrequote,
            WorkflowSpecializationCodes.Order,
        ];

    /// <summary>
    /// Проверяет размеры, уникальность кодов и ссылки переходов. При финальной
    /// активации дополнительно требует заполнения каждого обязательного раздела.
    /// </summary>
    public static void Validate(OrganizationOnboardingDraft draft, bool forActivation)
    {
        if (draft.CurrentStep is < 1 or > 10)
            Fail("onboarding_step_invalid", "Номер шага должен быть от 1 до 10.");

        ValidateCompany(draft.Company);
        ValidateUnique(draft.Workflows.Select(item => item.Code), "Коды канбанов");
        ValidateUnique(draft.Categories.Select(item => item.ClientId), "Идентификаторы категорий");
        ValidateUnique(draft.Categories.Select(item => item.Name), "Названия категорий");
        ValidateUnique(draft.Roles.Select(item => item.Name), "Названия ролей");
        ValidateUnique(draft.Dictionaries.Select(item => item.Code), "Коды справочников");

        foreach (var workflow in draft.Workflows)
        {
            RequireText(workflow.Code, 2, 80, "Код канбана");
            RequireText(workflow.Name, 2, 120, "Название канбана");
            if (workflow.Specialization is not null &&
                !WorkflowSpecializations.Contains(workflow.Specialization))
            {
                Fail(
                    "onboarding_workflow_specialization_invalid",
                    $"Для канбана «{workflow.Name}» выбран неизвестный тип.");
            }
            ValidateUnique(workflow.Columns.Select(item => item.ClientId), "Идентификаторы столбцов");
            foreach (var column in workflow.Columns)
            {
                RequireText(column.ClientId, 1, 80, "Идентификатор столбца");
                RequireText(column.Name, 1, 120, "Название столбца");
                if (column.Color.Length != 7 || column.Color[0] != '#' || !column.Color[1..].All(Uri.IsHexDigit))
                    Fail("onboarding_color_invalid", "Цвет столбца должен иметь формат #RRGGBB.");
                foreach (var action in column.CreationActions ?? [])
                {
                    if (action is not WorkflowCreationActionCodes.Quote and
                        not WorkflowCreationActionCodes.Prequote and
                        not WorkflowCreationActionCodes.Order)
                        Fail("onboarding_creation_action_invalid", "Столбец содержит неизвестное действие создания.");
                }
            }

            ValidateCreationActions(workflow);

            var columnIds = workflow.Columns.Select(item => item.ClientId).ToHashSet(StringComparer.Ordinal);
            if (workflow.Transitions.Any(item => item.FromClientId == item.ToClientId ||
                                                 !columnIds.Contains(item.FromClientId) ||
                                                 !columnIds.Contains(item.ToClientId)))
                Fail("onboarding_transition_invalid", "Переход канбана ссылается на неизвестный столбец.");
        }

        foreach (var category in draft.Categories)
        {
            RequireText(category.ClientId, 1, 80, "Идентификатор категории");
            RequireText(category.Name, 1, 120, "Название категории");
            ValidateUnique(category.Fields.Select(item => item.FieldCode), $"Поля категории «{category.Name}»");
            ValidateUnique(
                category.Fields.Select(OnboardingFieldRegistry.LabelOf),
                $"Названия полей категории «{category.Name}»");
            ValidateFieldSelection(category.Fields, $"категории «{category.Name}»");
            foreach (var field in category.Fields)
            {
                if (field.TotalMode is not null && field.TotalMode is not ("none" or "total" or "separate" or "separate_only"))
                    Fail("onboarding_total_mode_invalid", "Неизвестный режим участия поля в итогах.");
                if (field.TotalMode is "total" or "separate" or "separate_only" &&
                    OnboardingFieldRegistry.FieldTypeOf(field) is not ("money" or "calculated_money"))
                    Fail("onboarding_total_mode_invalid", "В итоги можно включать только денежные значения и расчётные суммы.");
            }
            ValidateUnique(category.Sections.Select(item => item.Name), "Названия разделов");
            foreach (var section in category.Sections)
            {
                RequireText(section.Name, 1, 120, "Название раздела");
                ValidateUnique(section.Groups.Select(item => item.Name), "Названия групп");
                foreach (var group in section.Groups) RequireText(group.Name, 1, 120, "Название группы");
            }
        }

        ValidateTransfers(draft.Workflows);
        ValidateWorkflowCategories(draft.Workflows, draft.Categories);
        ValidateDependencies(draft.Categories, draft.Dependencies ?? []);
        ValidateRules(
            draft.Categories,
            draft.Dependencies ?? [],
            draft.Rules ?? [],
            draft.MoneyPipelines ?? []);
        ValidateDictionaryBindings(draft);

        ValidateUnique(draft.Fields.Select(item => $"{item.ContextCode}:{item.FieldCode}"), "Коды полей");
        foreach (var field in draft.Fields)
        {
            RequireText(field.ContextCode, 2, 40, "Контекст поля");
            var definition = OnboardingFieldRegistry.Get(field.FieldCode);
            if (!string.Equals(field.Label.Trim(), definition.Label, StringComparison.Ordinal) ||
                !string.Equals(field.FieldType.Trim(), definition.FieldType, StringComparison.Ordinal))
                Fail("onboarding_field_metadata_invalid", $"Метаданные поля «{definition.Label}» нельзя изменять.");
            if (field.IsRequired && !field.IsVisible)
                Fail("onboarding_field_invalid", "Обязательное поле не может быть скрыто.");
            if (field.IsRequired && !definition.CanBeRequired)
                Fail("onboarding_field_invalid", $"Поле «{definition.Label}» нельзя сделать обязательным.");
        }

        foreach (var role in draft.Roles) RequireText(role.Name, 2, 100, "Название роли");
        foreach (var dictionary in draft.Dictionaries)
        {
            RequireText(dictionary.Code, 2, 80, "Код справочника");
            RequireText(dictionary.Name, 2, 120, "Название справочника");
            ValidateUnique(dictionary.Items.Select(item => item.Value), "Значения справочника");
            foreach (var item in dictionary.Items) RequireText(item.Value, 1, 160, "Значение справочника");
        }

        if (forActivation &&
            (draft.Workflows.Count == 0 || draft.Workflows.Any(item => item.Columns.Count == 0) ||
             draft.Categories.Count == 0 ||
             draft.Workflows.Any(item => item.Categories is not { Count: > 0 } ||
                 item.Categories.Any(category => category.FieldCodes.Count == 0)) ||
             draft.Dictionaries.Count == 0))
            Fail("onboarding_incomplete", "Заполните канбаны, каталог, поля и справочники перед активацией.");
    }

    /// <summary>
    /// Гарантирует единственную кнопку каждого вида и запрещает действия,
    /// несовместимые с выбранной специализацией канбана.
    /// </summary>
    private static void ValidateCreationActions(WorkflowDraft workflow)
    {
        var actions = workflow.Columns
            .SelectMany(column => column.CreationActions ?? [])
            .ToArray();
        ValidateUnique(actions, $"Действия создания канбана «{workflow.Name}»");

        var required = workflow.Specialization switch
        {
            WorkflowSpecializationCodes.Quote => new[] { WorkflowCreationActionCodes.Quote },
            WorkflowSpecializationCodes.Prequote => new[] { WorkflowCreationActionCodes.Prequote },
            WorkflowSpecializationCodes.QuoteAndPrequote =>
                new[] { WorkflowCreationActionCodes.Quote, WorkflowCreationActionCodes.Prequote },
            WorkflowSpecializationCodes.Order => new[] { WorkflowCreationActionCodes.Order },
            _ => Array.Empty<string>(),
        };

        if (actions.Except(required, StringComparer.Ordinal).Any())
            Fail(
                "onboarding_creation_action_incompatible",
                $"Действие создания несовместимо с типом канбана «{workflow.Name}».");
        if (required.Except(actions, StringComparer.Ordinal).Any())
            Fail(
                "onboarding_creation_action_required",
                $"Выберите столбец для каждой кнопки создания в канбане «{workflow.Name}».");
    }

    /// <summary>Разрешает назначать существующий справочник только полю типа dictionary.</summary>
    private static void ValidateDictionaryBindings(OrganizationOnboardingDraft draft)
    {
        var dictionaryCodes = draft.Dictionaries
            .Select(item => item.Code.Trim())
            .ToHashSet(StringComparer.Ordinal);
        foreach (var field in draft.Categories.SelectMany(item => item.Fields))
            ValidateDictionaryBinding(
                field.FieldCode,
                OnboardingFieldRegistry.FieldTypeOf(field),
                OnboardingFieldRegistry.LabelOf(field),
                field.DictionaryCode,
                dictionaryCodes);
        foreach (var field in draft.Fields)
            ValidateDictionaryBinding(
                field.FieldCode,
                field.FieldType,
                field.Label,
                field.DictionaryCode,
                dictionaryCodes);
    }

    private static void ValidateDictionaryBinding(
        string fieldCode,
        string fieldType,
        string fieldLabel,
        string? dictionaryCode,
        HashSet<string> dictionaryCodes)
    {
        if (string.IsNullOrWhiteSpace(dictionaryCode)) return;
        if (fieldCode == "group")
            Fail(
                "onboarding_dictionary_binding_invalid",
                "Поле «Группа» использует группы выбранного раздела и не требует справочника.");
        if (fieldType != "dictionary")
            Fail("onboarding_dictionary_binding_invalid", $"Поле «{fieldLabel}» не поддерживает справочник.");
        if (!dictionaryCodes.Contains(dictionaryCode.Trim()))
            Fail("onboarding_dictionary_binding_invalid", $"Для поля «{fieldLabel}» выбран неизвестный справочник.");
    }

    /// <summary>Проверяет реквизиты одинаково при onboarding и последующем редактировании.</summary>
    public static void ValidateCompany(CompanyProfileDraft company)
    {
        RequireText(company.OrganizationName, 2, 200, "Название организации");
        if (company.LegalEntity is not { } legalEntity) return;
        ValidateDigits(legalEntity.Inn, [10, 12], "ИНН должен содержать 10 или 12 цифр.");
        ValidateDigits(legalEntity.Kpp, [9], "КПП должен содержать 9 цифр.");
        ValidateDigits(legalEntity.Ogrn, [13, 15], "ОГРН должен содержать 13 или 15 цифр.");
        ValidatePhone(legalEntity.Phone);
        ValidateEmail(legalEntity.Email);
    }

    /// <summary>
    /// Проверяет привязку категорий к канбанам. Обычное поле должно быть настроено
    /// в карточке категории; расчётное поле доступно независимо от этого списка.
    /// </summary>
    /// <summary>
    /// Проверяет перенос между КП и комплектацией, столбец дозаказа и справочники
    /// канбана комплектации. Перенос возможен только КП/ПКП → комплектация и
    /// комплектация → КП/ПКП, в существующий столбец другого канбана.
    /// </summary>
    private static void ValidateTransfers(IReadOnlyList<WorkflowDraft> workflows)
    {
        var byCode = workflows.ToDictionary(item => item.Code.Trim(), StringComparer.Ordinal);
        foreach (var workflow in workflows)
        {
            var isOrder = workflow.Specialization == WorkflowSpecializationCodes.Order;
            var isQuote = workflow.Specialization is WorkflowSpecializationCodes.Quote
                or WorkflowSpecializationCodes.Prequote
                or WorkflowSpecializationCodes.QuoteAndPrequote;
            if (workflow.Columns.Count(column => column.ReorderFrom) > 1)
                Fail("onboarding_reorder_column_invalid",
                    $"В канбане «{workflow.Name}» дозаказ может начинаться только с одного столбца.");
            if (!isOrder && workflow.Columns.Any(column => column.ReorderFrom))
                Fail("onboarding_reorder_column_invalid",
                    $"Столбец дозаказа задаётся только в канбане комплектации («{workflow.Name}»).");

            var settings = workflow.OrderSettings;
            var hasSettings = (settings?.ObjectTypes?.Count ?? 0) + (settings?.ShipmentStatuses?.Count ?? 0) > 0;
            if (hasSettings && !isOrder)
                Fail("onboarding_order_settings_invalid",
                    $"Справочники комплектации задаются только в канбане комплектации («{workflow.Name}»).");
            foreach (var values in new[] { settings?.ObjectTypes ?? [], settings?.ShipmentStatuses ?? [] })
            {
                ValidateUnique(values, $"Значения справочника канбана «{workflow.Name}»");
                foreach (var value in values) RequireText(value, 1, 160, "Значение справочника");
            }

            foreach (var column in workflow.Columns.Where(column => column.TransferTo is not null))
            {
                var transfer = column.TransferTo!;
                if (!isOrder && !isQuote)
                    Fail("onboarding_transfer_invalid",
                        $"Перенос настраивается только в канбанах КП и комплектации («{workflow.Name}»).");
                if (!byCode.TryGetValue(transfer.WorkflowCode.Trim(), out var target) ||
                    ReferenceEquals(target, workflow))
                    Fail("onboarding_transfer_invalid",
                        $"Столбец «{column.Name}» переносит карточки в неизвестный канбан.");
                var targetIsOrder = target.Specialization == WorkflowSpecializationCodes.Order;
                var targetIsQuote = target.Specialization is WorkflowSpecializationCodes.Quote
                    or WorkflowSpecializationCodes.Prequote
                    or WorkflowSpecializationCodes.QuoteAndPrequote;
                var quoteToPrequote = workflow.Specialization == WorkflowSpecializationCodes.Quote &&
                    target.Specialization == WorkflowSpecializationCodes.Prequote;
                var prequoteToQuote = workflow.Specialization == WorkflowSpecializationCodes.Prequote &&
                    target.Specialization == WorkflowSpecializationCodes.Quote;
                if (!((isQuote && targetIsOrder) || (isOrder && targetIsQuote) ||
                      quoteToPrequote || prequoteToQuote))
                    Fail("onboarding_transfer_invalid",
                        $"Из столбца «{column.Name}» нельзя переносить карточки в канбан «{target.Name}».");
                if (target.Columns.All(item => item.ClientId != transfer.ColumnClientId))
                    Fail("onboarding_transfer_invalid",
                        $"Столбец «{column.Name}» переносит карточки в неизвестный столбец канбана «{target.Name}».");
            }
        }
    }

    private static void ValidateWorkflowCategories(
        IReadOnlyList<WorkflowDraft> workflows,
        IReadOnlyList<CatalogCategoryDraft> categories)
    {
        var categoriesById = categories.ToDictionary(item => item.ClientId, StringComparer.Ordinal);
        foreach (var workflow in workflows)
        {
            var selections = workflow.Categories ?? [];
            ValidateUnique(
                selections.Select(item => item.CategoryClientId),
                $"Категории канбана «{workflow.Name}»");

            foreach (var selection in selections)
            {
                if (!categoriesById.TryGetValue(selection.CategoryClientId, out var category))
                    Fail("onboarding_workflow_category_invalid",
                        $"Канбан «{workflow.Name}» ссылается на неизвестную категорию.");

                ValidateUnique(
                    selection.FieldCodes,
                    $"Поля категории «{category.Name}» в канбане «{workflow.Name}»");
                foreach (var fieldCode in selection.FieldCodes)
                {
                    var categoryField = category.Fields.FirstOrDefault(item => item.FieldCode == fieldCode);
                    var definition = categoryField is null
                        ? OnboardingFieldRegistry.Get(fieldCode)
                        : OnboardingFieldRegistry.DefinitionOf(categoryField);
                    var orderOnly = workflow.Specialization == WorkflowSpecializationCodes.Order &&
                                    OnboardingFieldRegistry.OrderOnlyFieldCodes.Contains(fieldCode);
                    if (!definition.IsCalculated && categoryField is null && !orderOnly)
                        Fail("onboarding_workflow_field_invalid",
                            $"Поле «{definition.Label}» не настроено в категории «{category.Name}».");
                }

                if (selection.SupplierFilterFieldCode is { } supplierCode)
                {
                    var supplierField = category.Fields.FirstOrDefault(item => item.FieldCode == supplierCode);
                    var isDictionary = supplierField is not null
                        ? OnboardingFieldRegistry.FieldTypeOf(supplierField) == "dictionary"
                        : supplierCode == "shipment_status";
                    if (workflow.Specialization != WorkflowSpecializationCodes.Order ||
                        !selection.FieldCodes.Contains(supplierCode) || !isDictionary)
                        Fail("onboarding_supplier_filter_invalid",
                            $"Источник фильтра поставщика в категории «{category.Name}» должен быть подключённым полем-справочником канбана комплектации.");
                }

            }
        }
    }

    /// <summary>
    /// Проверяет направление зависимости и гарантирует, что результат можно
    /// записать только в реально выбранное relation-поле целевой категории.
    /// </summary>
    private static void ValidateDependencies(
        IReadOnlyList<CatalogCategoryDraft> categories,
        IReadOnlyList<CategoryDependencyDraft> dependencies)
    {
        ValidateUnique(dependencies.Select(item => item.ClientId), "Идентификаторы зависимостей");
        ValidateUnique(
            dependencies.Select(item =>
                $"{item.SourceCategoryClientId}:{item.TargetCategoryClientId}:{item.TargetFieldCode}"),
            "Зависимости категорий");

        var categoriesById = categories.ToDictionary(item => item.ClientId, StringComparer.Ordinal);
        foreach (var dependency in dependencies)
        {
            RequireText(dependency.ClientId, 1, 100, "Идентификатор зависимости");
            if (!categoriesById.TryGetValue(dependency.SourceCategoryClientId, out var source))
                Fail("onboarding_dependency_category_invalid", "Зависимость ссылается на неизвестную категорию.");
            if (!categoriesById.TryGetValue(dependency.TargetCategoryClientId, out var target))
                Fail("onboarding_dependency_category_invalid", "Зависимость ссылается на неизвестную категорию.");
            if (source.ClientId == target.ClientId)
                Fail("onboarding_dependency_self_reference", "Категорию нельзя привязать саму к себе.");

            var targetField = target.Fields.FirstOrDefault(item => item.FieldCode == dependency.TargetFieldCode);
            if (targetField is null)
                Fail("onboarding_dependency_field_invalid",
                    $"В категории «{target.Name}» отсутствует поле для выбранной зависимости.");
            if (OnboardingFieldRegistry.FieldTypeOf(targetField) != "relation")
                Fail("onboarding_dependency_field_invalid",
                    $"Поле «{OnboardingFieldRegistry.LabelOf(targetField)}» не хранит связи.");
        }
    }

    /// <summary>Проверяет событийные правила и настройки фиксированного денежного конвейера.</summary>
    private static void ValidateRules(
        IReadOnlyList<CatalogCategoryDraft> categories,
        IReadOnlyList<CategoryDependencyDraft> dependencies,
        IReadOnlyList<CalculationRuleDraft> rules,
        IReadOnlyList<MoneyPipelineDraft> pipelines)
    {
        ValidateUnique(rules.Select(item => item.ClientId), "Идентификаторы правил");
        ValidateUnique(
            rules.Select(item => $"{item.CategoryClientId}:{item.Name}"),
            "Названия правил внутри категории");
        ValidateUnique(
            pipelines.Select(item => string.IsNullOrWhiteSpace(item.ClientId)
                ? $"{item.CategoryClientId}:{item.ResultFieldCode}"
                : item.ClientId!),
            "Идентификаторы денежных конвейеров");
        ValidateUnique(
            pipelines.Select(item => $"{item.CategoryClientId}:{item.ResultFieldCode}"),
            "Поля результата денежных конвейеров");

        var categoriesById = categories.ToDictionary(item => item.ClientId, StringComparer.Ordinal);
        var dependenciesById = dependencies.ToDictionary(item => item.ClientId, StringComparer.Ordinal);

        foreach (var pipeline in pipelines)
        {
            var category = RequireRuleCategory(categoriesById, pipeline.CategoryClientId);
            var fields = category.Fields.ToDictionary(item => item.FieldCode, StringComparer.Ordinal);
            RequireRuleField(fields, pipeline.BasePriceFieldCode, ["money", "calculated_money"], "Базовая цена");
            RequireOptionalRuleField(fields, pipeline.ManualPriceFieldCode, ["money"], "Ручная цена");
            RequireOptionalRuleField(fields, pipeline.MarkupFieldCode, ["percent"], "Наценка");
            RequireOptionalRuleField(fields, pipeline.DiscountFieldCode, ["percent"], "Скидка");
            RequireOptionalRuleField(fields, pipeline.QuantityFieldCode, ["number"], "Количество");
            RequireRuleField(fields, pipeline.ResultFieldCode, ["money", "calculated_money"], "Поле результата");
            if (pipeline.DecimalPlaces is < 0 or > 6)
                Fail("onboarding_rule_invalid", "Округление денежного конвейера должно быть от 0 до 6 знаков.");
        }

        foreach (var rule in rules)
        {
            RequireText(rule.ClientId, 1, 100, "Идентификатор правила");
            RequireText(rule.Name, 1, 120, "Название правила");
            var category = RequireRuleCategory(categoriesById, rule.CategoryClientId);
            var fields = category.Fields.ToDictionary(item => item.FieldCode, StringComparer.Ordinal);
            RequireAllowed(
                rule.EventType,
                ["field_changed", "card_saving", "row_calculation", "variant_calculation"],
                "Событие правила");
            if (rule.EventType == "field_changed")
                RequireRuleField(fields, rule.EventFieldCode, null, "Поле события");
            else if (!string.IsNullOrWhiteSpace(rule.EventFieldCode))
                Fail("onboarding_rule_invalid", "Поле события задаётся только для изменения поля.");

            if (rule.EventType == "variant_calculation")
                fields.Add("variant_total", new CatalogFieldDraft("variant_total", true, false,
                    Label: "Итоговая сумма варианта (с НДС)", FieldType: "money"));

            foreach (var condition in rule.Conditions)
                ValidateCondition(fields, condition);
            if (rule.Actions.Count == 0)
                Fail("onboarding_rule_invalid", $"В правиле «{rule.Name}» отсутствуют действия.");
            foreach (var action in rule.Actions)
            {
                if (action.TargetFieldCode == "variant_total")
                    Fail("onboarding_rule_field_invalid", "Итоговая сумма варианта доступна только для чтения.");
                ValidateAction(fields, dependenciesById, category.ClientId, action);
            }
        }

        var writers = new HashSet<(string Category, string Field)>();
        void RegisterWriter(string categoryId, string fieldCode)
        {
            if (writers.Add((categoryId, fieldCode))) return;
            var category = categoriesById[categoryId];
            var field = category.Fields.First(item => item.FieldCode == fieldCode);
            Fail("onboarding_rule_target_conflict",
                $"Категория «{category.Name}»: в поле «{field.Label ?? fieldCode}» записывает несколько правил или конвейеров. Оставьте один источник записи.");
        }
        foreach (var pipeline in pipelines)
            RegisterWriter(pipeline.CategoryClientId, pipeline.ResultFieldCode);
        foreach (var rule in rules)
            foreach (var action in rule.Actions)
                if (action.ActionType is "set_field" or "calculate_field")
                    RegisterWriter(rule.CategoryClientId, action.TargetFieldCode!);
    }

    private static CatalogCategoryDraft RequireRuleCategory(
        Dictionary<string, CatalogCategoryDraft> categories,
        string categoryClientId)
    {
        if (!categories.TryGetValue(categoryClientId, out var category))
            Fail("onboarding_rule_category_invalid", "Правило ссылается на неизвестную категорию.");
        return category;
    }

    private static void ValidateCondition(
        IReadOnlyDictionary<string, CatalogFieldDraft> fields,
        RuleConditionDraft condition)
    {
        var field = RequireRuleField(fields, condition.FieldCode, null, "Поле условия");
        var fieldType = RuleFieldType(field);
        RequireAllowed(
            condition.Operator,
            ["is_true", "is_false", "greater_than_zero", "is_filled", "equals", "less_than", "greater_than"],
            "Условие");
        if (condition.Operator is "is_true" or "is_false" && fieldType != "boolean")
            Fail("onboarding_rule_field_invalid", "Условие по состоянию флажка применимо только к полю типа «Флажок».");
        if (condition.Operator == "greater_than_zero" && !IsNumericField(fieldType))
            Fail("onboarding_rule_field_invalid", "Сравнение с нулём применимо только к числовому полю.");
        if (condition.Operator is "equals" or "less_than" or "greater_than")
        {
            var numeric = condition.Operator is "less_than" or "greater_than";
            if (numeric && !IsNumericField(fieldType))
                Fail("onboarding_rule_field_invalid", "Сравнение больше или меньше применимо только к числовому полю.");
            if (condition.ComparisonFieldCode is not null)
            {
                var other = RequireRuleField(fields, condition.ComparisonFieldCode, null, "Поле сравнения");
                var otherType = RuleFieldType(other);
                if (numeric && !IsNumericField(otherType) ||
                    !numeric && fieldType != otherType && !(IsNumericField(fieldType) && IsNumericField(otherType)))
                    Fail("onboarding_rule_field_invalid", "Выберите совместимое поле для сравнения.");
            }
            else
            {
                if (string.IsNullOrWhiteSpace(condition.ComparisonValue))
                    Fail("onboarding_rule_invalid", "Для сравнения укажите значение.");
                if (numeric && !decimal.TryParse(condition.ComparisonValue?.Trim().Replace(',', '.'),
                    System.Globalization.NumberStyles.Number, System.Globalization.CultureInfo.InvariantCulture, out _))
                    Fail("onboarding_rule_invalid", "Для сравнения больше или меньше укажите число.");
            }
        }
    }

    private static void ValidateAction(
        IReadOnlyDictionary<string, CatalogFieldDraft> fields,
        Dictionary<string, CategoryDependencyDraft> dependencies,
        string categoryClientId,
        RuleActionDraft action)
    {
        RequireAllowed(
            action.ActionType,
            [
                "exclude_row", "set_field", "calculate_field", "add_related_cards",
                "remove_related_cards", "set_field_visibility", "block_save", "aggregate_money", "highlight_field"
            ],
            "Действие");

        switch (action.ActionType)
        {
            case "exclude_row":
                return;
            case "set_field":
                RequireRuleField(fields, action.TargetFieldCode, null, "Изменяемое поле");
                var hasSource = !string.IsNullOrWhiteSpace(action.SourceFieldCode);
                var hasConstant = action.ConstantValue is not null;
                if (hasSource == hasConstant)
                    Fail("onboarding_rule_invalid", "Для изменения поля выберите одно исходное поле или одну константу.");
                if (hasSource) RequireRuleField(fields, action.SourceFieldCode, null, "Исходное поле");
                return;
            case "calculate_field":
                RequireRuleField(fields, action.TargetFieldCode, ["number", "money", "percent", "calculated_money"], "Поле результата");
                ValidateFormula(fields, action.Formula);
                return;
            case "add_related_cards":
            case "remove_related_cards":
                if (string.IsNullOrWhiteSpace(action.DependencyClientId) ||
                    !dependencies.TryGetValue(action.DependencyClientId, out var dependency) ||
                    dependency.TargetCategoryClientId != categoryClientId)
                    Fail("onboarding_rule_dependency_invalid", "Действие с карточками ссылается на неподходящую зависимость.");
                return;
            case "set_field_visibility":
                RequireRuleField(fields, action.TargetFieldCode, null, "Поле видимости");
                if (action.BooleanValue is null)
                    Fail("onboarding_rule_invalid", "Для видимости поля выберите «Показать» или «Скрыть».");
                return;
            case "highlight_field":
                RequireRuleField(fields, action.TargetFieldCode, null, "Выделяемое поле");
                if (action.HighlightColor is not { Length: 7 } color || color[0] != '#' || !color[1..].All(Uri.IsHexDigit))
                    Fail("onboarding_color_invalid", "Цвет выделения должен иметь формат #RRGGBB.");
                RequireText(action.Message ?? string.Empty, 0, 300, "Сообщение выделенного поля");
                return;
            case "block_save":
                RequireText(action.Message ?? string.Empty, 0, 300, "Сообщение запрета сохранения");
                return;
            case "aggregate_money":
                RequireRuleField(fields, action.SourceFieldCode, ["money", "calculated_money"], "Денежное поле");
                RequireAllowed(action.AggregationOperation, ["add", "subtract"], "Операция агрегации");
                RequireAllowed(action.AggregationTarget, ["variant_total"], "Итог агрегации");
                if (action.MultiplyByQuantity)
                    RequireRuleField(fields, action.QuantityFieldCode, ["number"], "Поле количества");
                return;
        }
    }

    private static void ValidateFormula(
        IReadOnlyDictionary<string, CatalogFieldDraft> fields,
        FormulaDraft? formula)
    {
        if (formula is null || formula.Tokens.Count == 0)
            Fail("onboarding_formula_invalid", "Расчётная формула не заполнена.");
        if (formula.DecimalPlaces is < 0 or > 6)
            Fail("onboarding_formula_invalid", "Округление формулы должно быть от 0 до 6 знаков.");

        var expectsOperand = true;
        var groupDepth = 0;
        foreach (var token in formula.Tokens)
        {
            switch (token.TokenType)
            {
                case "field" when expectsOperand:
                    RequireRuleField(fields, token.FieldCode, ["number", "money", "percent", "calculated_money"], "Поле формулы");
                    expectsOperand = false;
                    break;
                case "constant" when expectsOperand && token.ConstantValue is not null:
                    expectsOperand = false;
                    break;
                case "open_group" when expectsOperand:
                    groupDepth++;
                    break;
                case "close_group" when !expectsOperand && groupDepth > 0:
                    groupDepth--;
                    break;
                case "operator" when !expectsOperand:
                    RequireAllowed(token.Operator, ["add", "subtract", "multiply", "divide"], "Операция формулы");
                    expectsOperand = true;
                    break;
                default:
                    Fail("onboarding_formula_invalid", "Нарушен порядок элементов формулы.");
                    break;
            }
        }

        if (expectsOperand || groupDepth != 0)
            Fail("onboarding_formula_invalid", "Формула не завершена или содержит незакрытые скобки.");
    }

    private static CatalogFieldDraft RequireRuleField(
        IReadOnlyDictionary<string, CatalogFieldDraft> fields,
        string? fieldCode,
        string[]? allowedTypes,
        string label)
    {
        if (string.IsNullOrWhiteSpace(fieldCode) || !fields.ContainsKey(fieldCode))
            Fail("onboarding_rule_field_invalid", $"{label} не выбрано или отсутствует в категории.");
        var field = fields[fieldCode];
        var fieldType = RuleFieldType(field);
        if (allowedTypes is not null && !allowedTypes.Contains(fieldType))
            Fail("onboarding_rule_field_invalid", $"Поле «{OnboardingFieldRegistry.LabelOf(field)}» имеет неподходящий тип.");
        return field;
    }

    private static void RequireOptionalRuleField(
        IReadOnlyDictionary<string, CatalogFieldDraft> fields,
        string? fieldCode,
        string[] allowedTypes,
        string label)
    {
        if (!string.IsNullOrWhiteSpace(fieldCode)) RequireRuleField(fields, fieldCode, allowedTypes, label);
    }

    private static bool IsNumericField(string fieldType) =>
        fieldType is "number" or "money" or "percent" or "calculated_money";

    private static string RuleFieldType(CatalogFieldDraft field) =>
        field.FieldCode == "variant_total" ? "money" : OnboardingFieldRegistry.FieldTypeOf(field);

    private static void RequireAllowed(string? value, string[] values, string label)
    {
        if (string.IsNullOrWhiteSpace(value) || !values.Contains(value))
            Fail("onboarding_rule_invalid", $"{label} имеет недопустимое значение.");
    }

    private static void ValidateFieldSelection(IReadOnlyList<CatalogFieldDraft> fields, string owner)
    {
        var selected = fields.Select(item => item.FieldCode).ToHashSet(StringComparer.Ordinal);
        foreach (var field in fields)
        {
            var definition = OnboardingFieldRegistry.DefinitionOf(field);
            RequireText(OnboardingFieldRegistry.LabelOf(field), 1, 120, "Название поля");
            if (OnboardingFieldRegistry.IsSystemField(field.FieldCode) &&
                !string.IsNullOrWhiteSpace(field.FieldType) &&
                !string.Equals(field.FieldType.Trim(), definition.FieldType, StringComparison.Ordinal))
                Fail("onboarding_field_metadata_invalid", $"Тип системного поля «{definition.Label}» нельзя изменять.");
            if (field.IsRequired && !field.IsVisible)
                Fail("onboarding_field_invalid", $"Обязательное поле «{OnboardingFieldRegistry.LabelOf(field)}» в {owner} не может быть скрыто.");
            if (field.IsRequired && !definition.CanBeRequired)
                Fail("onboarding_field_invalid", $"Поле «{OnboardingFieldRegistry.LabelOf(field)}» в {owner} нельзя сделать обязательным.");
        }

        if (selected.Contains("line_total") && (!selected.Contains("base_price") || !selected.Contains("quantity")))
            Fail("onboarding_field_dependency", $"Для суммы в {owner} необходимы поля «Цена» и «Количество».");
        if ((selected.Contains("markup_value") || selected.Contains("discount_value")) && !selected.Contains("base_price"))
            Fail("onboarding_field_dependency", $"Для наценки и скидки в {owner} необходимо поле «Цена».");

        foreach (var fixedField in OnboardingFieldRegistry.DefaultCatalogFields())
        {
            if (!selected.Contains(fixedField.FieldCode))
                Fail(
                    "onboarding_fixed_field_missing",
                    $"В {owner} нельзя удалить системное поле «{OnboardingFieldRegistry.Get(fixedField.FieldCode).Label}».");
        }
    }

    private static void ValidateUnique(IEnumerable<string> values, string label)
    {
        var normalized = values.Select(value => value.Trim()).ToArray();
        if (normalized.Distinct(StringComparer.OrdinalIgnoreCase).Count() != normalized.Length)
            Fail("onboarding_duplicate", $"{label} не должны повторяться.");
    }

    private static void RequireText(string value, int min, int max, string label)
    {
        var length = value.Trim().Length;
        if (length < min || length > max)
            Fail("onboarding_value_invalid", $"{label}: допустимо от {min} до {max} символов.");
    }

    /// <summary>Проверяет необязательный реквизит: если он заполнен, допускаются только цифры заданной длины.</summary>
    private static void ValidateDigits(string? value, IReadOnlyCollection<int> allowedLengths, string message)
    {
        if (string.IsNullOrWhiteSpace(value)) return;
        var normalized = value.Trim();
        if (!normalized.All(char.IsDigit) || !allowedLengths.Contains(normalized.Length))
            Fail("onboarding_company_details_invalid", message);
    }

    /// <summary>Проверяет разумный диапазон цифр телефона, сохраняя возможность пользовательского форматирования.</summary>
    private static void ValidatePhone(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return;
        var normalized = value.Trim();
        if (normalized.Any(character => !char.IsDigit(character) && character is not ('+' or '(' or ')' or '-' or ' ')))
            Fail("onboarding_company_details_invalid", "Телефон содержит недопустимые символы.");

        var digitCount = normalized.Count(char.IsDigit);
        if (digitCount is < 10 or > 15)
            Fail("onboarding_company_details_invalid", "Телефон должен содержать от 10 до 15 цифр.");
    }

    /// <summary>Проверяет синтаксис необязательного email на сервере, не полагаясь только на Flutter-форму.</summary>
    private static void ValidateEmail(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return;
        var normalized = value.Trim();
        try
        {
            var address = new MailAddress(normalized);
            if (!string.Equals(address.Address, normalized, StringComparison.OrdinalIgnoreCase) ||
                !normalized.Contains('.'))
                Fail("onboarding_company_details_invalid", "Введите корректный email.");
        }
        catch (FormatException)
        {
            Fail("onboarding_company_details_invalid", "Введите корректный email.");
        }
    }

    [DoesNotReturn]
    private static void Fail(string code, string message) =>
        throw new IdentityException(400, code, message);
}
