using SkladKomforta.Application.Identity;
using SkladKomforta.Application.Onboarding;

namespace SkladKomforta.Domain.Tests.Onboarding;

/// <summary>Фиксирует серверные инварианты первичной настройки организации.</summary>
public sealed class OnboardingValidatorTests
{
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

    private static OrganizationOnboardingDraft ValidDraft() => new(
        7,
        new CompanyProfileDraft("Склад Комфорта", "ООО", null, null, null, null, null, null, null),
        [
            new WorkflowDraft(
                "quote",
                "Коммерческие предложения",
                [new WorkflowColumnDraft("quote-1", "Составить КП", "#4D8DFF")],
                []),
        ],
        [Category("equipment", "Оборудование")],
        [new EntityFieldDraft("quote", "name", "Наименование", "text", true, true)],
        [],
        [new DictionaryDraft("units", "Единицы измерения", [new DictionaryItemDraft("шт")])]);

    private static CatalogCategoryDraft Category(string clientId, string name) => new(
        clientId,
        name,
        [],
        [
            new CatalogFieldDraft("name", true, true),
            new CatalogFieldDraft("quantity", true, true),
            new CatalogFieldDraft("base_price", true, false),
            new CatalogFieldDraft("line_total", true, false),
        ]);
}
