using SkladKomforta.Application.Identity;

namespace SkladKomforta.Application.Quotes;

/// <summary>Результат безопасного расчёта одной позиции предложения.</summary>
public sealed record QuotePositionCalculation(decimal UnitPrice, decimal LineTotal);

/// <summary>
/// Выполняет зафиксированный денежный порядок без запуска пользовательского кода:
/// базовая или ручная цена, наценка, скидка, количество и итоговое округление.
/// </summary>
public static class QuoteCalculationEngine
{
    /// <summary>Рассчитывает цену единицы и сумму строки с точностью до копеек.</summary>
    public static QuotePositionCalculation Calculate(SaveQuotePositionRequest position)
    {
        var price = position.ManualPrice ?? position.BasePrice;
        price *= 1m + (position.MarkupPercent ?? 0m) / 100m;
        price *= 1m - (position.DiscountPercent ?? 0m) / 100m;
        if (price < 0)
            throw new IdentityException(400, "quote_price_invalid", "Расчётная цена позиции не может быть отрицательной.");

        return new QuotePositionCalculation(
            decimal.Round(price, 2, MidpointRounding.AwayFromZero),
            decimal.Round(price * position.Quantity, 2, MidpointRounding.AwayFromZero));
    }
}
