using System.Reflection;
using System.Text.Json;
using SkladKomforta.Application.Company;
using SkladKomforta.Application.Identity;
using SkladKomforta.Infrastructure.Company;

namespace SkladKomforta.Api.IntegrationTests;

public sealed class CompanyClientValidationTests
{
    private static readonly MethodInfo Validate = typeof(PostgresCompanyWorkspaceService)
        .GetMethod("ValidateClient", BindingFlags.NonPublic | BindingFlags.Static)!;

    [Theory]
    [InlineData("person")]
    [InlineData("ip")]
    [InlineData("ooo")]
    public void OptionalClientDetailsAreAccepted(string type)
    {
        var request = JsonSerializer.Deserialize<SaveCompanyClientRequest>(
            JsonSerializer.Serialize(new { Name = type == "person" ? "" : "Test", CompanyType = type }))!;
        Validate.Invoke(null, [request]);
        Validate.Invoke(null, [request with { CompanyName = "А", LegalName = "Б" }]);
    }

    [Theory]
    [InlineData("ip")]
    [InlineData("ooo")]
    public void BusinessClientRequiresName(string type)
    {
        var request = JsonSerializer.Deserialize<SaveCompanyClientRequest>(
            JsonSerializer.Serialize(new { Name = "  ", CompanyType = type }))!;
        var exception = Assert.Throws<TargetInvocationException>(() => Validate.Invoke(null, [request]));
        Assert.IsType<IdentityException>(exception.InnerException);
    }

    [Theory]
    [InlineData("person", "PassportSeries")]
    [InlineData("person", "Phone")]
    [InlineData("ip", "Inn")]
    [InlineData("ooo", "Kpp")]
    [InlineData("ooo", "BankAccount")]
    [InlineData("ooo", "Email")]
    public void SuppliedInvalidDetailsAreStillRejected(string type, string field)
    {
        var data = new Dictionary<string, string> { ["Name"] = "Test", ["CompanyType"] = type, [field] = "x" };
        var request = JsonSerializer.Deserialize<SaveCompanyClientRequest>(JsonSerializer.Serialize(data))!;
        var exception = Assert.Throws<TargetInvocationException>(() => Validate.Invoke(null, [request]));
        Assert.IsType<IdentityException>(exception.InnerException);
    }
}
