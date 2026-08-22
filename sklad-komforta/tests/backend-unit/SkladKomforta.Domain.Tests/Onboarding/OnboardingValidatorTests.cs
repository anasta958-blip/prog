using SkladKomforta.Application.Identity;
using SkladKomforta.Application.Onboarding;

namespace SkladKomforta.Domain.Tests.Onboarding;

/// <summary>Фиксирует серверные инварианты первичной настройки организации.</summary>
public sealed class OnboardingValidatorTests
{
    [Fact]
    public void DefaultCatalogFieldsExcludeOptionalAdjustmentsAndRetiredRetailPrice()
    {
        var defaults = OnboardingFieldRegistry.DefaultCatalogFields()
            .Select(field => field.FieldCode)
            .ToArray();

        Assert.DoesNotContain("retail_price", OnboardingFieldRegistry.All.Select(field => field.Code));
        Assert.DoesNotContain("markup_value", defaults);
        Assert.DoesNotContain("discount_value", defaults);
        Assert.DoesNotContain("line_total", defaults);
        Assert.Contains("base_price", defaults);
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
    public void CompleteConsistentDraftPassesActivationValidation()
    {
        var exception = Record.Exception(() =>
            OnboardingValidator.Validate(ValidDraft(), true));

        Assert.Null(exception);
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
            [new CatalogFieldDraft("name", true, true)]);
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
            Fields =
            [
                .. source.Categories[0].Fields,
                new CatalogFieldDraft("unit", true, false, "units"),
            ],
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
            Fields =
            [
                .. source.Categories[0].Fields,
                new CatalogFieldDraft("unit", true, false, "unknown"),
            ],
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

    private static OrganizationOnboardingDraft ValidDraft() => new(
        8,
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

    private static CatalogCategoryDraft Category(
        string clientId,
        string name,
        bool includeRelation = false)
    {
        var fields = new List<CatalogFieldDraft>
        {
            new CatalogFieldDraft("name", true, true),
            new CatalogFieldDraft("quantity", true, true),
            new CatalogFieldDraft("base_price", true, false),
            new CatalogFieldDraft("line_total", true, false),
        };
        if (includeRelation) fields.Add(new CatalogFieldDraft("linked_services", true, false));
        return new CatalogCategoryDraft(clientId, name, [], fields);
    }
}
