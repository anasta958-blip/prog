using System.Text.Json;
using SkladKomforta.Infrastructure;

namespace SkladKomforta.Api.IntegrationTests;

public sealed class AuditChangesTests
{
    [Fact]
    public void PersistenceMetadataDoesNotCreateAnEvent()
    {
        var before = new { Name = "Товар", UpdatedAt = DateTime.UtcNow, UpdatedByName = "Иван", ThumbnailUrl = "old" };
        var after = before with { UpdatedAt = DateTime.UtcNow.AddDays(1), UpdatedByName = "Анна", ThumbnailUrl = "new" };
        Assert.Null(AuditChanges.Serialize(before, after));
    }

    [Fact]
    public void RequestIsComparedWithoutReadOnlyPropertiesAndSetOrdering()
    {
        var before = new { Id = Guid.NewGuid(), Name = "Роль", IsSystem = false, PermissionCodes = new[] { "a", "b" } };
        var after = new { Name = "Роль", PermissionCodes = new[] { "b", "a" } };
        Assert.Null(AuditChanges.Serialize(before, after));
        Assert.NotNull(AuditChanges.Serialize(before, after with { Name = "Другая роль" }));
    }

    [Fact]
    public void NestedChangesAndRemovedDynamicFieldsAreNotLost()
    {
        var before = JsonSerializer.Deserialize<JsonElement>("""{"values":{"price":12,"updatedAt":"custom"}}""");
        var after = JsonSerializer.Deserialize<JsonElement>("""{"values":{"price":12}}""");
        Assert.NotNull(AuditChanges.Serialize(before, after));
        Assert.Null(AuditChanges.Serialize(before, before));
    }

    [Fact]
    public void ReorderingBusinessListsRemainsAnEvent()
    {
        var before = new { Fields = new[] { "a", "b" } };
        var after = new { Fields = new[] { "b", "a" } };
        Assert.NotNull(AuditChanges.Serialize(before, after));
    }

    [Fact]
    public void CreationDeletionAndSecretRedactionArePreserved()
    {
        var value = new { Name = "Клиент", Password = "secret" };
        Assert.DoesNotContain("secret", AuditChanges.Serialize(null, value)!);
        Assert.NotNull(AuditChanges.Serialize(value, null));
    }
}
