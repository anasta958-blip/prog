using SkladKomforta.Domain.Catalog;

namespace SkladKomforta.Domain.Tests.Catalog;

/// <summary>Фиксирует правила идентичности и цены карточек каталога.</summary>
public sealed class CatalogItemRulesTests
{
    [Theory]
    [InlineData("  CAPSULE   POOL ", "capsule pool")]
    [InlineData("МНТ-РU", "мнт-рu")]
    [InlineData("", "")]
    [InlineData(null, "")]
    public void IdentityPartIsNormalizedWithoutDependingOnSupplierOrUnit(
        string? source,
        string expected) =>
        Assert.Equal(expected, CatalogItemRules.NormalizeIdentityPart(source));

    [Theory]
    [InlineData(1, true)]
    [InlineData(0.01, true)]
    [InlineData(0, false)]
    [InlineData(-1, false)]
    public void CatalogPriceMustBePositive(decimal value, bool expected) =>
        Assert.Equal(expected, CatalogItemRules.IsValidPrice(value));
}
