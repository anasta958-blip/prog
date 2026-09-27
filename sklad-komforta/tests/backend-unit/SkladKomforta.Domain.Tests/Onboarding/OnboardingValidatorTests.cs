using SkladKomforta.Application.Identity;
using SkladKomforta.Application.Onboarding;
using SkladKomforta.Application.Quotes;

namespace SkladKomforta.Domain.Tests.Onboarding;

/// <summary>Фиксирует серверные инварианты первичной настройки организации.</summary>
public sealed class OnboardingValidatorTests
{
    [Fact]
    public void DefaultCatalogFieldsContainOnlyFixedCategoryFields()
    {
        var defaults = OnboardingFieldRegistry.DefaultCatalogFields()
            .Select(field => field.FieldCode)
            .ToArray();

        Assert.DoesNotContain("retail_price", OnboardingFieldRegistry.All.Select(field => field.Code));
        Assert.Equal(["name", "marking", "unit", "base_price"], defaults);
    }

    [Theory]
    [InlineData("name")]
    [InlineData("marking")]
    [InlineData("unit")]
    [InlineData("base_price")]
    public void DraftRejectsCategoryWithoutFixedField(string removedFieldCode)
    {
        var source = ValidDraft();
        var category = source.Categories[0] with
        {
            Fields = OnboardingFieldRegistry.DefaultCatalogFields()
                .Where(field => field.FieldCode != removedFieldCode)
                .ToArray(),
        };

        var exception = Assert.Throws<IdentityException>(() =>
            OnboardingValidator.Validate(source with { Categories = [category] }, false));

        Assert.Equal("onboarding_fixed_field_missing", exception.Code);
    }

    [Fact]
    public void DraftAcceptsCustomCatalogFieldLabel()
    {
        var source = ValidDraft();
        var category = source.Categories[0] with
        {
            Fields = source.Categories[0].Fields
                .Select(field => field.FieldCode == "name"
                    ? field with { Label = "Название оборудования" }
                    : field)
                .ToArray(),
        };

        var exception = Record.Exception(() =>
            OnboardingValidator.Validate(source with { Categories = [category] }, false));

        Assert.Null(exception);
    }

    [Fact]
    public void DraftRejectsDuplicateCatalogFieldLabelsIgnoringCase()
    {
        var source = ValidDraft();
        var category = source.Categories[0] with
        {
            Fields = source.Categories[0].Fields
                .Select(field => field.FieldCode switch
                {
                    "name" => field with { Label = "Модель" },
                    "marking" => field with { Label = " модель " },
                    _ => field,
                })
                .ToArray(),
        };

        var exception = Assert.Throws<IdentityException>(() =>
            OnboardingValidator.Validate(source with { Categories = [category] }, false));

        Assert.Equal("onboarding_duplicate", exception.Code);
    }

    [Fact]
    public void DraftRejectsDuplicateCategoryNamesIgnoringCase()
    {
        var draft = ValidDraft() with
        {
            Categories =
            [
                Category("equipment", "Оборудование"),
                Category("materials", " оборудование "),
            ],
        };

        var exception = Assert.Throws<IdentityException>(() =>
            OnboardingValidator.Validate(draft, false));

        Assert.Equal("onboarding_duplicate", exception.Code);
    }

    [Fact]
    public void ActivationRequiresEveryConfigurationArea()
    {
        var draft = ValidDraft() with { Dictionaries = [] };

        var exception = Assert.Throws<IdentityException>(() =>
            OnboardingValidator.Validate(draft, true));

        Assert.Equal("onboarding_incomplete", exception.Code);
    }

    [Fact]
    public void ActiveConfigurationMayBeSavedAfterItsOnlyWorkflowCategoryWasRemoved()
    {
        var source = ValidDraft();
        var draft = source with
        {
            Workflows = source.Workflows
                .Select(workflow => workflow with { Categories = [] })
                .ToArray(),
        };

        var saveException = Record.Exception(() =>
            OnboardingValidator.Validate(draft, false));
        var activationException = Assert.Throws<IdentityException>(() =>
            OnboardingValidator.Validate(draft, true));

        Assert.Null(saveException);
        Assert.Equal("onboarding_incomplete", activationException.Code);
    }

    [Fact]
    public void CompleteConsistentDraftPassesActivationValidation()
    {
        var exception = Record.Exception(() =>
            OnboardingValidator.Validate(ValidDraft(), true));

        Assert.Null(exception);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("quote")]
    [InlineData("quote_and_prequote")]
    [InlineData("order")]
    public void DraftAcceptsSupportedWorkflowSpecialization(string? specialization)
    {
        var source = ValidDraft();
        var workflows = source.Workflows
            .Select(item => item with
            {
                Specialization = specialization,
                Columns =
                [
                    item.Columns[0] with
                    {
                        CreationActions = specialization switch
                        {
                            "quote" => [WorkflowCreationActionCodes.Quote],
                            "quote_and_prequote" =>
                                [WorkflowCreationActionCodes.Quote, WorkflowCreationActionCodes.Prequote],
                            "order" => [WorkflowCreationActionCodes.Order],
                            _ => [],
                        },
                    },
                ],
            })
            .ToArray();

        var exception = Record.Exception(() =>
            OnboardingValidator.Validate(source with { Workflows = workflows }, false));

        Assert.Null(exception);
    }

    [Fact]
    public void SpecializedWorkflowRequiresConfiguredCreationColumn()
    {
        var source = ValidDraft();
        var workflow = source.Workflows[0] with
        {
            Specialization = WorkflowSpecializationCodes.Quote,
        };

        var exception = Assert.Throws<IdentityException>(() =>
            OnboardingValidator.Validate(source with { Workflows = [workflow] }, false));

        Assert.Equal("onboarding_creation_action_required", exception.Code);
    }

    [Fact]
    public void CreationActionCannotBeDuplicatedAcrossColumns()
    {
        var source = ValidDraft();
        var workflow = source.Workflows[0] with
        {
            Specialization = WorkflowSpecializationCodes.Quote,
            Columns =
            [
                new WorkflowColumnDraft("first", "Первый", "#4D8DFF", [WorkflowCreationActionCodes.Quote]),
                new WorkflowColumnDraft("second", "Второй", "#4D8DFF", [WorkflowCreationActionCodes.Quote]),
            ],
        };

        var exception = Assert.Throws<IdentityException>(() =>
            OnboardingValidator.Validate(source with { Workflows = [workflow] }, false));

        Assert.Equal("onboarding_duplicate", exception.Code);
    }

    [Fact]
    public void DraftRejectsUnknownWorkflowSpecialization()
    {
        var source = ValidDraft();
        var workflows = source.Workflows
            .Select(item => item with { Specialization = "unknown" })
            .ToArray();

        var exception = Assert.Throws<IdentityException>(() =>
            OnboardingValidator.Validate(source with { Workflows = workflows }, false));

        Assert.Equal("onboarding_workflow_specialization_invalid", exception.Code);
    }

    [Theory]
    [InlineData("123ABC7890", null, null, null, null)]
    [InlineData(null, "123", null, null, null)]
    [InlineData(null, null, "12345678901234", null, null)]
    [InlineData(null, null, null, "телефон", null)]
    [InlineData(null, null, null, null, "incorrect-email")]
    public void DraftRejectsInvalidCompanyDetails(
        string? inn,
        string? kpp,
        string? ogrn,
        string? phone,
        string? email)
    {
        var draft = ValidDraft() with
        {
            Company = ValidDraft().Company with
            {
                Inn = inn,
                Kpp = kpp,
                Ogrn = ogrn,
                Phone = phone,
                Email = email,
            },
        };

        var exception = Assert.Throws<IdentityException>(() =>
            OnboardingValidator.Validate(draft, false));

        Assert.Equal("onboarding_company_details_invalid", exception.Code);
    }

    [Fact]
    public void DraftAcceptsValidCompanyDetails()
    {
        var source = ValidDraft();
        var draft = source with
        {
            Company = source.Company with
            {
                Inn = "772994700534",
                Kpp = "123456789",
                Ogrn = "323508100309129",
                Phone = "+7 (925) 625-91-15",
                Email = "office@example.ru",
            },
        };

        var exception = Record.Exception(() =>
            OnboardingValidator.Validate(draft, false));

        Assert.Null(exception);
    }

    [Fact]
    public void DraftRejectsUnknownCatalogField()
    {
        var source = ValidDraft();
        var draft = source with
        {
            Categories =
            [
                new CatalogCategoryDraft(
                    "equipment",
                    "Оборудование",
                    [],
                    [new CatalogFieldDraft("name", true, true), new CatalogFieldDraft("custom_price", true, false)]),
            ],
        };

        var exception = Assert.Throws<IdentityException>(() =>
            OnboardingValidator.Validate(draft, false));

        Assert.Equal("onboarding_field_unknown", exception.Code);
    }

    [Fact]
    public void DraftAcceptsNamedCustomCatalogFieldWithSupportedType()
    {
        var source = ValidDraft();
        var category = source.Categories[0];
        var draft = source with
        {
            Categories =
            [
                category with
                {
                    Fields =
                    [
                        .. category.Fields,
                        new CatalogFieldDraft("custom_101", true, false, null, "Мощность", "number"),
                    ],
                },
            ],
        };

        var exception = Record.Exception(() =>
            OnboardingValidator.Validate(draft, false));

        Assert.Null(exception);
    }

    [Fact]
    public void DraftAcceptsOptionalCustomCalculatedMoneyField()
    {
        var source = ValidDraft();
        var category = source.Categories[0];
        var draft = source with
        {
            Categories =
            [
                category with
                {
                    Fields =
                    [
                        .. category.Fields,
                        new CatalogFieldDraft(
                            "custom_total", true, false, null,
                            "Расчётная сумма", "calculated_money"),
                    ],
                },
            ],
        };

        var exception = Record.Exception(() =>
            OnboardingValidator.Validate(draft, false));

        Assert.Null(exception);
    }

    [Fact]
    public void DraftRejectsCustomCatalogFieldWithoutName()
    {
        var source = ValidDraft();
        var category = source.Categories[0];
        var draft = source with
        {
            Categories =
            [
                category with
                {
                    Fields =
                    [
                        .. category.Fields,
                        new CatalogFieldDraft("custom_102", true, false, null, "", "text"),
                    ],
                },
            ],
        };

        var exception = Assert.Throws<IdentityException>(() =>
            OnboardingValidator.Validate(draft, false));

        Assert.Equal("onboarding_value_invalid", exception.Code);
    }

    [Fact]
    public void DraftRejectsCalculatedTotalWithoutPriceAndQuantity()
    {
        var source = ValidDraft();
        var draft = source with
        {
            Categories =
            [
                new CatalogCategoryDraft(
                    "equipment",
                    "Оборудование",
                    [],
                    [new CatalogFieldDraft("name", true, true), new CatalogFieldDraft("line_total", true, false)]),
            ],
        };

        var exception = Assert.Throws<IdentityException>(() =>
            OnboardingValidator.Validate(draft, false));

        Assert.Equal("onboarding_field_dependency", exception.Code);
    }

    [Fact]
    public void DraftAcceptsDependencyStoredInRelationField()
    {
        var source = ValidDraft();
        var draft = source with
        {
            Categories =
            [
                Category("equipment", "Оборудование", true),
                Category("works", "Работы"),
            ],
            Dependencies =
            [
                new CategoryDependencyDraft("works-equipment", "works", "equipment", "linked_services"),
            ],
        };

        var exception = Record.Exception(() =>
            OnboardingValidator.Validate(draft, false));

        Assert.Null(exception);
    }

    [Fact]
    public void DraftRejectsDependencyWithUnknownCategory()
    {
        var source = ValidDraft();
        var draft = source with
        {
            Dependencies =
            [
                new CategoryDependencyDraft("unknown-equipment", "unknown", "equipment", "linked_services"),
            ],
        };

        var exception = Assert.Throws<IdentityException>(() =>
            OnboardingValidator.Validate(draft, false));

        Assert.Equal("onboarding_dependency_category_invalid", exception.Code);
    }

    [Fact]
    public void DraftRejectsDependencyStoredInOrdinaryField()
    {
        var source = ValidDraft();
        var draft = source with
        {
            Categories =
            [
                Category("equipment", "Оборудование"),
                Category("works", "Работы"),
            ],
            Dependencies =
            [
                new CategoryDependencyDraft("works-equipment", "works", "equipment", "name"),
            ],
        };

        var exception = Assert.Throws<IdentityException>(() =>
            OnboardingValidator.Validate(draft, false));

        Assert.Equal("onboarding_dependency_field_invalid", exception.Code);
    }

    [Fact]
    public void DraftRejectsUnknownWorkflowCategory()
    {
        var source = ValidDraft();
        var workflow = source.Workflows[0] with
        {
            Categories = [new WorkflowCategoryDraft("unknown", ["name"])],
        };

        var exception = Assert.Throws<IdentityException>(() =>
            OnboardingValidator.Validate(source with { Workflows = [workflow] }, false));

        Assert.Equal("onboarding_workflow_category_invalid", exception.Code);
    }

    [Fact]
    public void DraftRejectsWorkflowFieldMissingFromCategory()
    {
        var source = ValidDraft();
        var workflow = source.Workflows[0] with
        {
            Categories = [new WorkflowCategoryDraft("equipment", ["supplier"])],
        };

        var exception = Assert.Throws<IdentityException>(() =>
            OnboardingValidator.Validate(source with { Workflows = [workflow] }, false));

        Assert.Equal("onboarding_workflow_field_invalid", exception.Code);
    }

    [Fact]
    public void DraftAcceptsCalculatedWorkflowFieldWithoutCatalogSelection()
    {
        var source = ValidDraft();
        var category = new CatalogCategoryDraft(
            "equipment",
            "Оборудование",
            [],
            OnboardingFieldRegistry.DefaultCatalogFields());
        var workflow = source.Workflows[0] with
        {
            Categories = [new WorkflowCategoryDraft("equipment", ["name", "line_total"])],
        };

        var exception = Record.Exception(() => OnboardingValidator.Validate(
            source with { Workflows = [workflow], Categories = [category] },
            false));

        Assert.Null(exception);
    }

    [Fact]
    public void DraftAcceptsExistingDictionaryBoundToDictionaryField()
    {
        var source = ValidDraft();
        var category = source.Categories[0] with
        {
            Fields = source.Categories[0].Fields
                .Select(field => field.FieldCode == "unit"
                    ? field with { DictionaryCode = "units" }
                    : field)
                .ToArray(),
        };

        var exception = Record.Exception(() => OnboardingValidator.Validate(
            source with { Categories = [category] },
            false));

        Assert.Null(exception);
    }

    [Fact]
    public void DraftRejectsDictionaryBoundToNonDictionaryField()
    {
        var source = ValidDraft();
        var category = source.Categories[0] with
        {
            Fields = source.Categories[0].Fields
                .Select(field => field.FieldCode == "base_price"
                    ? field with { DictionaryCode = "units" }
                    : field)
                .ToArray(),
        };

        var exception = Assert.Throws<IdentityException>(() =>
            OnboardingValidator.Validate(source with { Categories = [category] }, false));

        Assert.Equal("onboarding_dictionary_binding_invalid", exception.Code);
    }

    [Fact]
    public void DraftRejectsUnknownDictionaryBinding()
    {
        var source = ValidDraft();
        var category = source.Categories[0] with
        {
            Fields = source.Categories[0].Fields
                .Select(field => field.FieldCode == "unit"
                    ? field with { DictionaryCode = "unknown" }
                    : field)
                .ToArray(),
        };

        var exception = Assert.Throws<IdentityException>(() =>
            OnboardingValidator.Validate(source with { Categories = [category] }, false));

        Assert.Equal("onboarding_dictionary_binding_invalid", exception.Code);
    }

    [Fact]
    public void DraftRejectsDictionaryBoundToStructuralGroup()
    {
        var source = ValidDraft();
        var category = source.Categories[0] with
        {
            Fields =
            [
                .. source.Categories[0].Fields,
                new CatalogFieldDraft("group", true, false, "units"),
            ],
        };

        var exception = Assert.Throws<IdentityException>(() =>
            OnboardingValidator.Validate(source with { Categories = [category] }, false));

        Assert.Equal("onboarding_dictionary_binding_invalid", exception.Code);
    }

    [Fact]
    public void DraftAcceptsConfiguredMoneyPipelineAndFormulaRule()
    {
        var source = ValidDraft();
        var category = CategoryWithCalculationFields();
        var formula = new FormulaDraft(
        [
            new FormulaTokenDraft("field", FieldCode: "base_price"),
            new FormulaTokenDraft("operator", Operator: "multiply"),
            new FormulaTokenDraft("field", FieldCode: "custom_quantity"),
        ]);
        var rule = new CalculationRuleDraft(
            "calculate-total",
            "Рассчитать сумму",
            "equipment",
            "row_calculation",
            true,
            null,
            [],
            [new RuleActionDraft("calculate_field", TargetFieldCode: "line_total", Formula: formula)]);
        var pipeline = new MoneyPipelineDraft(
            "equipment",
            "base_price",
            "custom_manual_price",
            "custom_markup",
            "custom_discount",
            "custom_quantity",
            "custom_total",
            2,
            true);

        var exception = Record.Exception(() => OnboardingValidator.Validate(
            source with { CurrentStep = 9, Categories = [category], Rules = [rule], MoneyPipelines = [pipeline] },
            false));

        Assert.Null(exception);
    }

    [Fact]
    public void DraftRejectsTextFieldUsedAsMarkup()
    {
        var source = ValidDraft();
        var category = CategoryWithCalculationFields();
        var pipeline = new MoneyPipelineDraft(
            "equipment",
            "base_price",
            null,
            "name",
            null,
            "custom_quantity",
            "custom_total",
            2,
            true);

        var exception = Assert.Throws<IdentityException>(() => OnboardingValidator.Validate(
            source with { Categories = [category], MoneyPipelines = [pipeline] },
            false));

        Assert.Equal("onboarding_rule_field_invalid", exception.Code);
    }

    [Fact]
    public void DraftAcceptsSeveralMoneyPipelinesWithDifferentResultsInOneCategory()
    {
        var source = ValidDraft();
        var category = CategoryWithCalculationFields();
        var first = new MoneyPipelineDraft(
            "equipment", "base_price", null, "custom_markup", null,
            "custom_quantity", "custom_total", 2, true, "pipeline-total");
        var second = new MoneyPipelineDraft(
            "equipment", "base_price", "custom_manual_price", null, "custom_discount",
            "custom_quantity", "custom_manual_price", 2, false, "pipeline-manual");

        var exception = Record.Exception(() => OnboardingValidator.Validate(
            source with { Categories = [category], MoneyPipelines = [first, second] },
            false));

        Assert.Null(exception);
    }

    [Fact]
    public void DraftRejectsSeveralMoneyPipelinesWritingToSameResult()
    {
        var source = ValidDraft();
        var category = CategoryWithCalculationFields();
        var first = new MoneyPipelineDraft(
            "equipment", "base_price", null, "custom_markup", null,
            "custom_quantity", "custom_total", 2, true, "pipeline-first");
        var second = new MoneyPipelineDraft(
            "equipment", "base_price", null, null, "custom_discount",
            "custom_quantity", "custom_total", 2, true, "pipeline-second");

        var exception = Assert.Throws<IdentityException>(() => OnboardingValidator.Validate(
            source with { Categories = [category], MoneyPipelines = [first, second] },
            false));

        Assert.Equal("onboarding_duplicate", exception.Code);
    }

    [Fact]
    public void DraftRejectsFormulaWithMissingOperand()
    {
        var source = ValidDraft();
        var category = CategoryWithCalculationFields();
        var rule = new CalculationRuleDraft(
            "broken-formula",
            "Незавершённая формула",
            "equipment",
            "row_calculation",
            true,
            null,
            [],
            [
                new RuleActionDraft(
                    "calculate_field",
                    TargetFieldCode: "custom_total",
                    Formula: new FormulaDraft(
                    [
                        new FormulaTokenDraft("field", FieldCode: "base_price"),
                        new FormulaTokenDraft("operator", Operator: "multiply"),
                    ])),
            ]);

        var exception = Assert.Throws<IdentityException>(() => OnboardingValidator.Validate(
            source with { Categories = [category], Rules = [rule] },
            false));

        Assert.Equal("onboarding_formula_invalid", exception.Code);
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public void DraftRejectsRuleWritingPipelineResult(bool enabled)
    {
        var source = ValidDraft();
        var category = CategoryWithCalculationFields();
        var rule = new CalculationRuleDraft("copy", "Копировать цену", "equipment", "row_calculation", enabled,
            null, [], [new RuleActionDraft("set_field", TargetFieldCode: "custom_total", SourceFieldCode: "base_price")]);
        var pipeline = new MoneyPipelineDraft("equipment", "base_price", null, null, null, null, "custom_total", 2, true);
        var exception = Assert.Throws<IdentityException>(() => OnboardingValidator.Validate(
            source with { Categories = [category], Rules = [rule], MoneyPipelines = [pipeline] }, false));
        Assert.Equal("onboarding_rule_target_conflict", exception.Code);
        var second = rule with { ClientId = "copy2", Name = "Вторая запись" };
        exception = Assert.Throws<IdentityException>(() => OnboardingValidator.Validate(
            source with { Categories = [category], Rules = [rule, second] }, false));
        Assert.Equal("onboarding_rule_target_conflict", exception.Code);
    }

    private static OrganizationOnboardingDraft ValidDraft() => new(
        9,
        new CompanyProfileDraft("Склад Комфорта", "ООО", null, null, null, null, null, null, null),
        [
            new WorkflowDraft(
                "quote",
                "Коммерческие предложения",
                [new WorkflowColumnDraft("quote-1", "Составить КП", "#4D8DFF")],
                [],
                [new WorkflowCategoryDraft("equipment", ["name", "line_total"])]),
        ],
        [Category("equipment", "Оборудование")],
        [new EntityFieldDraft("quote", "name", "Наименование", "text", true, true)],
        [],
        [new DictionaryDraft("units", "Единицы измерения", [new DictionaryItemDraft("шт")])]);

    private static CatalogCategoryDraft CategoryWithCalculationFields()
    {
        var category = Category("equipment", "Оборудование");
        return category with
        {
            Fields =
            [
                .. category.Fields,
                new CatalogFieldDraft("custom_manual_price", true, false, FieldType: "money", Label: "Ручная цена"),
                new CatalogFieldDraft("custom_markup", true, false, FieldType: "percent", Label: "Наценка"),
                new CatalogFieldDraft("custom_discount", true, false, FieldType: "percent", Label: "Скидка"),
                new CatalogFieldDraft("custom_quantity", true, true, FieldType: "number", Label: "Количество для расчёта"),
                new CatalogFieldDraft("custom_total", true, false, FieldType: "calculated_money", Label: "Итоговая цена"),
            ],
        };
    }

    private static CatalogCategoryDraft Category(
        string clientId,
        string name,
        bool includeRelation = false)
    {
        var fields = OnboardingFieldRegistry.DefaultCatalogFields().ToList();
        fields.Add(new CatalogFieldDraft("quantity", true, true));
        fields.Add(new CatalogFieldDraft("line_total", true, false));
        if (includeRelation) fields.Add(new CatalogFieldDraft("linked_services", true, false));
        return new CatalogCategoryDraft(clientId, name, [], fields);
    }
}
