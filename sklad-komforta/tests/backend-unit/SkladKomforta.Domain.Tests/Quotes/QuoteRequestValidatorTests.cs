using SkladKomforta.Application.Identity;
using SkladKomforta.Application.Quotes;

namespace SkladKomforta.Domain.Tests.Quotes;

public sealed class QuoteRequestValidatorTests
{
    [Fact]
    public void AcceptsEmptyDraftWithRequiredHeader()
    {
        QuoteRequestValidator.Validate(ValidRequest());
    }

    [Fact]
    public void RejectsPrequoteWithUnknownSelectionMode()
    {
        var request = ValidRequest() with
        {
            QuoteKind = QuoteKindCodes.Prequote,
            SelectionMode = "unknown",
        };

        var error = Assert.Throws<IdentityException>(() => QuoteRequestValidator.Validate(request));

        Assert.Equal("quote_selection_mode_invalid", error.Code);
    }

    [Fact]
    public void RejectsSelectionFromAnotherProposalType()
    {
        var firstVariantId = Guid.NewGuid();
        var secondVariantId = Guid.NewGuid();
        var request = ValidRequest() with
        {
            ProposalTypes =
            [
                new SaveQuoteProposalTypeRequest(
                    null,
                    "Тип",
                    secondVariantId,
                    [new SaveQuoteVariantRequest(firstVariantId, "Вариант", null, null, [])]),
            ],
        };

        var error = Assert.Throws<IdentityException>(() => QuoteRequestValidator.Validate(request));

        Assert.Equal("quote_selected_variant_invalid", error.Code);
    }

    [Fact]
    public void RejectsDuplicatePositionIdentifiers()
    {
        var positionId = Guid.NewGuid();
        var position = new SaveQuotePositionRequest(
            positionId, null, "Позиция", null, "шт", 1, null, 10, null,
            null, null, false, null);
        var request = ValidRequest() with
        {
            ProposalTypes =
            [
                new SaveQuoteProposalTypeRequest(null, "Тип", null,
                [
                    new SaveQuoteVariantRequest(null, "Вариант", null, null,
                    [
                        new SaveQuoteCategoryRequest(null, null, "Категория",
                        [
                            new SaveQuoteSectionRequest(
                                null, null, "Раздел", null, null, [position, position]),
                        ]),
                    ]),
                ]),
            ],
        };

        var error = Assert.Throws<IdentityException>(() => QuoteRequestValidator.Validate(request));

        Assert.Equal("quote_entity_id_invalid", error.Code);
    }

    private static SaveQuoteRequest ValidRequest() =>
        new(
            QuoteKindCodes.Quote,
            "Коммерческое предложение",
            Guid.NewGuid(),
            Guid.NewGuid(),
            null,
            null,
            "variant",
            null,
            []);
}
