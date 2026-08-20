using SkladKomforta.Domain.Tenancy;

namespace SkladKomforta.Domain.Tests.Tenancy;

public sealed class TenantSchemaNameTests
{
    [Fact]
    public void CreateUsesStableSafeSchemaName()
    {
        var organizationId = Guid.Parse("dc36629e-655a-476e-bab0-09ca8e23d765");

        var result = TenantSchemaName.Create(organizationId);

        Assert.Equal("tenant_dc36629e655a476ebab009ca8e23d765", result.Value);
    }

    [Theory]
    [InlineData("public")]
    [InlineData("tenant_dc36629e-655a-476e-bab0-09ca8e23d765")]
    [InlineData("tenant_dc36629e655a476ebab009ca8e23d765;drop table users")]
    public void ParseRejectsUnsafeSchemaName(string value)
    {
        Assert.Throws<ArgumentException>(() => TenantSchemaName.Parse(value));
    }
}
