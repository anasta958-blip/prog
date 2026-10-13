using System.Text.Json;
using SkladKomforta.Application.Onboarding;

namespace SkladKomforta.Domain.Tests.Onboarding;

public sealed class CompanyProfileDraftTests
{
    private static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web);

    [Fact]
    public void LegacyDetailsAreReadIntoLegalEntityButNeverWrittenBackFlat()
    {
        var draft = JsonSerializer.Deserialize<CompanyProfileDraft>("""
            {"organizationName":"Склад","companyType":"ИП","legalName":"Иванов Иван",
             "inn":"772994700534","phone":"+79991234567"}
            """, Options)!;
        Assert.Equal("ip", draft.LegalEntity!.CompanyType);
        Assert.Equal("772994700534", draft.LegalEntity.Inn);
        using var output = JsonDocument.Parse(JsonSerializer.Serialize(draft, Options));
        Assert.False(output.RootElement.TryGetProperty("inn", out _));
        Assert.Equal("772994700534", output.RootElement.GetProperty("legalEntity").GetProperty("inn").GetString());
    }

    [Fact]
    public void WorkspaceWithoutLegalEntitySerializesOnlyName()
    {
        using var output = JsonDocument.Parse(JsonSerializer.Serialize(new CompanyProfileDraft("Склад"), Options));
        Assert.Single(output.RootElement.EnumerateObject());
    }
}
