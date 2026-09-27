using SkladKomforta.Application.Quotes;

namespace SkladKomforta.Api.IntegrationTests;

public sealed class QuoteVatCalculatorTests
{
    [Theory]
    [InlineData(4100, 1, 41)]
    [InlineData(4100, 20, 820)]
    [InlineData(4100, 0, 0)]
    [InlineData(4100, null, 0)]
    [InlineData(0, 22, 0)]
    [InlineData(120.02, 20, 24)]
    [InlineData(0.5, 1, 0.01)]
    public void VatIsAddedToNetPrices(decimal subtotal, int? rate, decimal expected)
    {
        Assert.Equal(expected, QuoteVatCalculator.Calculate(subtotal, rate));
    }
}
