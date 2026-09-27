using System.Text.Json;
using System.Text.Json.Nodes;

namespace SkladKomforta.Infrastructure;

/// <summary>Compares business snapshots, excluding persistence metadata.</summary>
internal static class AuditChanges
{
    private static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web);
    private static readonly HashSet<string> Metadata = new(StringComparer.Ordinal)
    {
        "createdAt", "updatedAt", "createdBy", "updatedBy", "currentStep",
        "createdByName", "updatedByName", "thumbnailUrl",
        "temporaryPassword", "password", "passwordHash",
    };
    private static readonly HashSet<string> Sets = new(StringComparer.Ordinal)
    {
        "permissionCodes", "subordinateRoleIds", "cardVisibilityMembershipIds", "vatRates",
    };

    public static string? Serialize(object? before, object? after)
    {
        var oldValue = Normalize(JsonSerializer.SerializeToNode(before, Options));
        var newValue = Normalize(JsonSerializer.SerializeToNode(after, Options));
        // Save requests omit read-only properties present in database summaries.
        if (before is not null && after is not null && before.GetType() != after.GetType()
            && oldValue is JsonObject oldObject && newValue is JsonObject newObject)
        {
            foreach (var key in oldObject.Select(pair => pair.Key).Except(newObject.Select(pair => pair.Key)).ToArray())
                oldObject.Remove(key);
        }
        if (before is not null && after is not null && JsonNode.DeepEquals(oldValue, newValue))
            return null;
        return new JsonObject { ["before"] = oldValue, ["after"] = newValue }.ToJsonString(Options);
    }

    private static JsonNode? Normalize(JsonNode? node, string? property = null, bool dynamicValue = false)
    {
        if (node is null && !dynamicValue && property is not null && Sets.Contains(property))
            return new JsonArray();
        if (node is JsonObject obj)
        {
            var result = new JsonObject();
            foreach (var pair in obj)
            {
                if (!dynamicValue && Metadata.Contains(pair.Key)) continue;
                result[pair.Key] = Normalize(pair.Value, pair.Key, dynamicValue || pair.Key == "values");
            }
            return result;
        }
        if (node is JsonArray array)
        {
            var items = array.Select(item => Normalize(item, dynamicValue: dynamicValue)).ToArray();
            if (!dynamicValue && property is not null && Sets.Contains(property))
                items = items.OrderBy(item => item?.ToJsonString(), StringComparer.Ordinal).ToArray();
            return new JsonArray(items);
        }
        if (!dynamicValue && node is JsonValue value && value.TryGetValue<string>(out var text))
            return string.IsNullOrWhiteSpace(text) ? null : JsonValue.Create(text.Trim());
        return node?.DeepClone();
    }
}
