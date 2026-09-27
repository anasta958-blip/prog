namespace SkladKomforta.Application.Quotes;

/// <summary>НДС начисляется сверху на сумму позиций без НДС.</summary>
public static class QuoteVatCalculator
{
    public static decimal Calculate(decimal subtotal, decimal? rate) =>
        rate.HasValue ? decimal.Round(subtotal * rate.Value / 100m, 2, MidpointRounding.AwayFromZero) : 0m;
}
