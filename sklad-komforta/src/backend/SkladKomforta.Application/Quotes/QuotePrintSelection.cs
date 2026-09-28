using SkladKomforta.Application.Identity;

namespace SkladKomforta.Application.Quotes;

/// <summary>
/// Ограничивает печатную версию предложения тем, что выбрал менеджер: одним
/// вариантом, всеми вариантами одного типа либо всем документом.
/// </summary>
public static class QuotePrintSelection
{
    /// <summary>
    /// Возвращает копию предложения с выбранным содержимым.
    /// </summary>
    /// <param name="quote">Сохранённое предложение.</param>
    /// <param name="proposalTypeId">Тип предложения; необязателен, если указан вариант.</param>
    /// <param name="variantId">
    /// Печатаемый вариант. Без варианта, но с типом остаются все варианты этого типа;
    /// если не указаны ни тип, ни вариант, возвращается весь документ.
    /// </param>
    /// <returns>Предложение с одним вариантом, одним типом либо исходный документ.</returns>
    /// <exception cref="IdentityException">
    /// 404 <c>quote_print_type_not_found</c> — тип не найден в предложении;
    /// 404 <c>quote_print_variant_not_found</c> — вариант не принадлежит предложению или типу.
    /// </exception>
    public static QuoteDetails Apply(QuoteDetails quote, Guid? proposalTypeId, Guid? variantId)
    {
        if (variantId is null)
        {
            if (proposalTypeId is null) return quote;
            var wholeType = quote.ProposalTypes.FirstOrDefault(item => item.Id == proposalTypeId)
                ?? throw new IdentityException(
                    404,
                    "quote_print_type_not_found",
                    "Выбранный тип не найден в сохранённом предложении. Обновите документ и повторите печать.");
            return quote with { ProposalTypes = [wholeType] };
        }

        var type = quote.ProposalTypes.FirstOrDefault(item =>
            item.Variants.Any(variant => variant.Id == variantId) &&
            (proposalTypeId is null || item.Id == proposalTypeId));
        if (type is null)
        {
            throw new IdentityException(
                404,
                "quote_print_variant_not_found",
                "Выбранный вариант не найден в сохранённом предложении. Обновите документ и повторите печать.");
        }

        var variant = type.Variants.Single(item => item.Id == variantId);
        return quote with { ProposalTypes = [type with { Variants = [variant] }] };
    }
}
