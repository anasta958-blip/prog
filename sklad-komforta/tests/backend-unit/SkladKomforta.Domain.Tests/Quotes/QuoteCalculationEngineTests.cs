using System.Text.Json;
using SkladKomforta.Application.Identity;
using SkladKomforta.Application.Quotes;

namespace SkladKomforta.Domain.Tests.Quotes;

public sealed class QuoteCalculationEngineTests
{
    [Fact]
    public void UsesFixedPriceOrderAndRoundsOnlyAtTheEnd()
    {
        var position = Position(
            quantity: 3m,
            basePrice: 100m,
            manualPrice: 120m,
            markup: 10m,
            discount: 5m);

        var result = QuoteCalculationEngine.Calculate(position);

        Assert.Equal(125.40m, result.UnitPrice);
        Assert.Equal(376.20m, result.LineTotal);
    }

    [Fact]
    public void UsesBasePriceWhenManualPriceIsMissing()
    {
        var result = QuoteCalculationEngine.Calculate(Position(
            quantity: 2m, basePrice: 99.995m));

        Assert.Equal(100.00m, result.UnitPrice);
        Assert.Equal(199.99m, result.LineTotal);
    }

    [Fact]
    public void RejectsCalculationThatProducesNegativePrice()
    {
        var error = Assert.Throws<IdentityException>(() =>
            QuoteCalculationEngine.Calculate(Position(
                quantity: 1m, basePrice: 100m, discount: 150m)));

        Assert.Equal("quote_price_invalid", error.Code);
    }

    private static SaveQuotePositionRequest Position(
        decimal quantity,
        decimal basePrice,
        decimal? manualPrice = null,
        decimal? markup = null,
        decimal? discount = null) =>
        new(
            null, null, "Позиция", null, "шт", quantity, null, basePrice,
            manualPrice, markup, discount, false,
            new Dictionary<string, JsonElement>());
}
