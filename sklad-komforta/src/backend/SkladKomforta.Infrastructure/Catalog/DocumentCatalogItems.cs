using System.Data.Common;
using System.Text.Json;
using SkladKomforta.Application.Identity;

namespace SkladKomforta.Infrastructure.Catalog;

/// <summary>Registers manually entered document rows in the same transaction as the document.</summary>
internal static class DocumentCatalogItems
{
    public static async Task<Guid?> ResolveAsync(
        DbConnection connection, DbTransaction transaction, Guid actor,
        Guid? itemId, Guid? categoryId, Guid? sectionId, string name, string? marking,
        string? unit, IReadOnlyDictionary<string, JsonElement>? values,
        decimal? basePrice, CancellationToken token)
    {
        if (itemId.HasValue) return itemId;
        // Legacy documents can contain categories without a catalog counterpart.
        if (!categoryId.HasValue) return null;

        var data = values?.ToDictionary(pair => pair.Key, pair => pair.Value)
            ?? new Dictionary<string, JsonElement>();
        data.TryAdd("unit", JsonSerializer.SerializeToElement(unit ?? string.Empty));
        if (basePrice.HasValue) data["base_price"] = JsonSerializer.SerializeToElement(basePrice.Value);
        var group = data.TryGetValue("group", out var groupValue) && groupValue.ValueKind == JsonValueKind.String
            ? groupValue.GetString()?.Trim() ?? string.Empty : string.Empty;

        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        void Add(string key, object? value)
        {
            var parameter = command.CreateParameter();
            parameter.ParameterName = key;
            parameter.Value = value ?? DBNull.Value;
            command.Parameters.Add(parameter);
        }
        Add("actor", actor);
        Add("category", categoryId.Value);
        Add("section", sectionId);
        Add("group_name", group);
        Add("name", name.Trim());
        Add("marking", marking?.Trim() ?? string.Empty);
        Add("values", JsonSerializer.Serialize(data));
        command.CommandText = """
            SELECT id FROM catalog_groups
             WHERE section_id = CAST(@section AS uuid)
               AND lower(btrim(name)) = lower(@group_name)
             ORDER BY sort_order, id LIMIT 1
            """;
        var groupId = await command.ExecuteScalarAsync(token) as Guid?;
        Add("group_id", groupId);
        command.CommandText = """
            INSERT INTO catalog_items
                (category_id, section_id, group_id, name, marking, status, values, created_by, updated_by)
            VALUES
                (@category, CAST(@section AS uuid), CAST(@group_id AS uuid), @name, @marking, 'pending',
                 (SELECT COALESCE(jsonb_object_agg(entry.key, entry.value), '{}'::jsonb)
                    FROM jsonb_each(CAST(@values AS jsonb)) AS entry
                   WHERE entry.key NOT IN ('name', 'marking', 'group', 'supplier')
                     AND EXISTS (SELECT 1 FROM catalog_category_fields AS field
                                  WHERE field.category_id = @category AND field.field_code = entry.key
                                    AND field.field_type <> 'calculated_money')),
                 @actor, @actor)
            ON CONFLICT DO NOTHING
            RETURNING id
            """;
        var createdId = await command.ExecuteScalarAsync(token) as Guid?;
        if (createdId.HasValue)
        {
            Add("created_id", createdId.Value);
            command.CommandText = """
                INSERT INTO audit_log (actor_user_id, entity_type, entity_id, action, diff)
                SELECT @actor, 'catalog_item', id, 'created', jsonb_build_object('after', to_jsonb(item))
                  FROM catalog_items AS item WHERE id = @created_id
                """;
            await command.ExecuteNonQueryAsync(token);
            return createdId;
        }

        // A separate statement sees a concurrent insert after ON CONFLICT has waited for it.
        command.CommandText = """
            SELECT id FROM catalog_items
             WHERE deleted_at IS NULL
               AND COALESCE(group_id::text, '') = COALESCE(CAST(@group_id AS uuid)::text, '')
               AND normalized_name = lower(regexp_replace(btrim(@name), '\s+', ' ', 'g'))
               AND normalized_marking = lower(regexp_replace(btrim(@marking), '\s+', ' ', 'g'))
            """;
        return await command.ExecuteScalarAsync(token) as Guid?
            ?? throw new IdentityException(409, "catalog_item_conflict",
                "Не удалось добавить позицию в каталог. Повторите сохранение документа.");
    }
}
