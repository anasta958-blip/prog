using SkladKomforta.Domain.Company;

namespace SkladKomforta.Domain.Tests.Company;

public sealed class TaxpayerNumberTests
{
    [Theory]
    [InlineData("7707083893")]
    [InlineData("500123456750")]
    public void IsValidAcceptsCorrectChecksum(string value)
    {
        Assert.True(TaxpayerNumber.IsValid(value));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("7707083894")]
    [InlineData("500123456751")]
    [InlineData("770708389")]
    [InlineData("77070838931")]
    [InlineData("77070 8389")]
    [InlineData("７７０７０８３８９３")]
    public void IsValidRejectsWrongLengthDigitsOrChecksum(string? value)
    {
        Assert.False(TaxpayerNumber.IsValid(value));
    }

    [Fact]
    public void IsIndividualDependsOnLength()
    {
        Assert.True(TaxpayerNumber.IsIndividual("500123456750"));
        Assert.False(TaxpayerNumber.IsIndividual("7707083893"));
    }
}
