using System.Text.Json;
using System.Text.Json.Serialization;
using SkladKomforta.Application.Company;

namespace SkladKomforta.Application.Onboarding;

/// <summary>Читает старые плоские черновики, но пишет только новую структуру.</summary>
public sealed class CompanyProfileDraftJsonConverter : JsonConverter<CompanyProfileDraft>
{
    private static readonly string[] LegacyDetailKeys = ["legalName", "inn", "kpp", "ogrn", "address", "phone", "email"];
    public override CompanyProfileDraft Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        using var document = JsonDocument.ParseValue(ref reader);
        var root = document.RootElement;
        if (root.ValueKind != JsonValueKind.Object) throw new JsonException("Expected company object.");
        string? Text(string key) => root.TryGetProperty(key, out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString() : null;
        var name = Text("organizationName") ?? "";
        SaveLegalEntityRequest? company = null;
        if (root.TryGetProperty("legalEntity", out var entity) && entity.ValueKind == JsonValueKind.Object)
            company = entity.Deserialize<SaveLegalEntityRequest>(options);
        else if (entity.ValueKind is not (JsonValueKind.Undefined or JsonValueKind.Null))
            throw new JsonException("Expected legalEntity object.");
        else if (LegacyDetailKeys.Any(key => !string.IsNullOrWhiteSpace(Text(key))))
            company = new SaveLegalEntityRequest(name,
                Text("companyType")?.ToLowerInvariant() is "ip" or "ип" ? "ip" : "ooo",
                Text("legalName"), Text("inn"), Text("kpp"), Text("ogrn"), Text("address"),
                Text("phone"), Text("email"), null, null, null, null, null, null, null, null,
                null, null, [null], true);
        return new CompanyProfileDraft(name, company);
    }

    public override void Write(Utf8JsonWriter writer, CompanyProfileDraft value, JsonSerializerOptions options)
    {
        writer.WriteStartObject();
        writer.WriteString("organizationName", value.OrganizationName);
        if (value.LegalEntity is not null)
        {
            writer.WritePropertyName("legalEntity");
            JsonSerializer.Serialize(writer, value.LegalEntity, options);
        }
        writer.WriteEndObject();
    }
}
