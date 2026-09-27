using SkladKomforta.Application.Identity;

namespace SkladKomforta.Application.Quotes;

/// <summary>
/// Ограничивает печатную версию предложения одним типом и одним вариантом —
/// теми, что открыты у менеджера в редакторе.
/// </summary>
public static class QuotePrintSelection
{
    /// <summary>
    /// Возвращает копию предложения, в которой оставлены только указанные тип и вариант.
    /// </summary>
    /// <param name="quote">Сохранённое предложение.</param>
    /// <param name="proposalTypeId">Тип предложения; необязателен, если указан вариант.</param>
    /// <param name="variantId">
    /// Печатаемый вариант. Если не указаны ни тип, ни вариант, возвращается весь документ.
    /// </param>
    /// <returns>Предложение с одним типом и одним вариантом либо исходный документ.</returns>
    /// <exception cref="IdentityException">
    /// 400 <c>quote_print_variant_required</c> — указан тип без варианта;
    /// 404 <c>quote_print_variant_not_found</c> — вариант не принадлежит предложению или типу.
    /// </exception>
    public static QuoteDetails Apply(QuoteDetails quote, Guid? proposalTypeId, Guid? variantId)
    {
        if (variantId is null)
        {
            return proposalTypeId is null
                ? quote
                : throw new IdentityException(
                    400,
                    "quote_print_variant_required",
                    "Выберите вариант предложения для печати.");
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
