using SkladKomforta.Application.Identity;
using SkladKomforta.Application.Quotes;

namespace SkladKomforta.Domain.Tests.Quotes;

public sealed class QuotePrintSelectionTests
{
    private static readonly Guid ConditionersId = Guid.NewGuid();
    private static readonly Guid BoilersId = Guid.NewGuid();
    private static readonly Guid EconomyId = Guid.NewGuid();
    private static readonly Guid PremiumId = Guid.NewGuid();
    private static readonly Guid BoilerVariantId = Guid.NewGuid();

    private static readonly QuoteDetails Quote = new(
        Guid.NewGuid(),
        Guid.NewGuid(),
        Guid.NewGuid(),
        QuoteKindCodes.Quote,
        "Коттедж",
        Guid.NewGuid(),
        Guid.NewGuid(),
        null,
        null,
        "variant",
        null,
        [
            new QuoteProposalTypeDetails(ConditionersId, "Кондиционеры", 0, PremiumId,
                [Variant(EconomyId, "Эконом", 0), Variant(PremiumId, "Премиум", 1)]),
            new QuoteProposalTypeDetails(BoilersId, "Бойлеры", 1, null,
                [Variant(BoilerVariantId, "Базовый", 0)]),
        ],
        DateTimeOffset.UtcNow,
        DateTimeOffset.UtcNow);

    [Fact]
    public void SelectedTypeAndVariantAreTheOnlyPrintedContent()
    {
        var printed = QuotePrintSelection.Apply(Quote, ConditionersId, EconomyId);

        var type = Assert.Single(printed.ProposalTypes);
        Assert.Equal(ConditionersId, type.Id);
        Assert.Equal(EconomyId, Assert.Single(type.Variants).Id);
        Assert.Equal(Quote.Title, printed.Title);
    }

    [Fact]
    public void VariantAloneIdentifiesItsType()
    {
        var printed = QuotePrintSelection.Apply(Quote, null, BoilerVariantId);

        Assert.Equal(BoilersId, Assert.Single(printed.ProposalTypes).Id);
    }

    [Fact]
    public void WithoutSelectionWholeDocumentIsPrinted()
    {
        Assert.Same(Quote, QuotePrintSelection.Apply(Quote, null, null));
    }

    [Fact]
    public void VariantFromAnotherTypeIsRejected()
    {
        var error = Assert.Throws<IdentityException>(() =>
            QuotePrintSelection.Apply(Quote, BoilersId, EconomyId));

        Assert.Equal(404, error.StatusCode);
        Assert.Equal("quote_print_variant_not_found", error.Code);
    }

    [Fact]
    public void TypeWithoutVariantKeepsAllVariantsOfThatType()
    {
        var printed = QuotePrintSelection.Apply(Quote, ConditionersId, null);

        var type = Assert.Single(printed.ProposalTypes);
        Assert.Equal(ConditionersId, type.Id);
        Assert.Equal([EconomyId, PremiumId], type.Variants.Select(item => item.Id));
    }

    [Fact]
    public void UnknownTypeIsRejected()
    {
        var error = Assert.Throws<IdentityException>(() =>
            QuotePrintSelection.Apply(Quote, Guid.NewGuid(), null));

        Assert.Equal(404, error.StatusCode);
        Assert.Equal("quote_print_type_not_found", error.Code);
    }

    private static QuoteVariantDetails Variant(Guid id, string name, int sortOrder) =>
        new(id, name, null, 20m, sortOrder, []);
}
