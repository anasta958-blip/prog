using System.Data.Common;
using System.Globalization;
using System.Text.Json;
using Npgsql;
using NpgsqlTypes;
using SkladKomforta.Application.Abstractions.Files;
using SkladKomforta.Application.Abstractions.Persistence;
using SkladKomforta.Application.Catalog;
using SkladKomforta.Application.Identity;
using SkladKomforta.Application.Onboarding;
using SkladKomforta.Domain.Catalog;

namespace SkladKomforta.Infrastructure.Catalog;

/// <summary>
/// Хранит карточки в текущей tenant-схеме и проверяет их по материализованной
/// onboarding-конфигурации до выполнения изменяющего SQL.
/// </summary>
internal sealed class PostgresCatalogService(
    IDatabaseConnectionFactory connectionFactory,
    IObjectStorage objectStorage) : ICatalogService
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private static readonly Dictionary<string, string> ImageExtensions =
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["image/jpeg"] = ".jpg",
            ["image/png"] = ".png",
            ["image/webp"] = ".webp",
        };
    private const long MaxImageByteSize = 10 * 1024 * 1024;
    private const int MaxImagesPerItem = 8;
    private static readonly HashSet<string> ReservedValueCodes =
        ["group", "name", "marking"];

    /// <inheritdoc />
    public async Task<CatalogConfiguration> GetConfigurationAsync(CancellationToken cancellationToken)
    {
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        var categories = await ReadCategoriesAsync(connection, cancellationToken);
        var dictionaries = await ReadDictionariesAsync(connection, cancellationToken);
        return new CatalogConfiguration(categories, dictionaries);
    }

    /// <inheritdoc />
    public async Task<CatalogItemPage> GetItemsAsync(
        CatalogItemQuery query,
        CancellationToken cancellationToken)
    {
        var page = query.Page < 1 ? 1 : query.Page;
        var pageSize = Math.Clamp(query.PageSize, 1, 100);
        var status = NormalizeStatus(query.Status, true);
        var search = query.Search?.Trim() ?? string.Empty;

        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT item.id, item.category_id, item.section_id, item.group_id,
                   item.name, item.marking, item.status, item.values,
                   item.created_by, item.created_at, item.updated_by, item.updated_at,
                   image.object_key,
                   count(*) OVER()
            FROM catalog_items AS item
            LEFT JOIN LATERAL (
                SELECT catalog_image.object_key
                FROM catalog_item_images AS catalog_image
                WHERE catalog_image.catalog_item_id = item.id
                  AND catalog_image.ready_at IS NOT NULL
                  AND catalog_image.deleted_at IS NULL
                ORDER BY catalog_image.sort_order, catalog_image.created_at, catalog_image.id
                LIMIT 1
            ) AS image ON true
            WHERE item.deleted_at IS NULL
              AND (@category_id IS NULL OR item.category_id = @category_id)
              AND (@section_id IS NULL OR item.section_id = @section_id)
              AND (@status = '' OR item.status = @status)
              AND (@search = '' OR item.name ILIKE '%' || @search || '%'
                   OR item.marking ILIKE '%' || @search || '%')
            ORDER BY item.updated_at DESC, item.id
            LIMIT @limit OFFSET @offset
            """;
        AddGuidParameter(command, "category_id", query.CategoryId);
        AddGuidParameter(command, "section_id", query.SectionId);
        AddParameter(command, "status", status ?? string.Empty);
        AddParameter(command, "search", search);
        AddParameter(command, "limit", pageSize);
        AddParameter(command, "offset", (page - 1) * pageSize);

        var items = new List<CatalogItemSummary>();
        var total = 0;
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            var item = ReadItem(reader);
            if (!reader.IsDBNull(12))
            {
                item = item with
                {
                    ThumbnailUrl = await objectStorage.CreateDownloadUrlAsync(
                        reader.GetString(12),
                        TimeSpan.FromMinutes(15),
                        cancellationToken),
                };
            }
            items.Add(item);
            total = checked((int)reader.GetInt64(13));
        }
        return new CatalogItemPage(items, page, pageSize, total);
    }

    /// <inheritdoc />
    public async Task<CatalogItemSummary> GetItemAsync(Guid itemId, CancellationToken cancellationToken)
    {
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        return await ReadItemAsync(connection, null, itemId, cancellationToken);
    }

    /// <inheritdoc />
    public async Task<CatalogItemSummary> CreateItemAsync(
        Guid actorUserId,
        SaveCatalogItemRequest request,
        CancellationToken cancellationToken)
    {
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        var normalized = await ValidateAsync(connection, transaction, request, cancellationToken);
        var itemId = Guid.NewGuid();
        await using (var command = connection.CreateCommand())
        {
            command.Transaction = transaction;
            command.CommandText = """
                INSERT INTO catalog_items
                    (id, category_id, section_id, group_id, name, marking, status,
                     values, created_by, updated_by)
                VALUES
                    (@id, @category_id, @section_id, @group_id, @name, @marking,
                     @status, CAST(@values AS jsonb), @actor, @actor)
                """;
            AddItemParameters(command, itemId, actorUserId, normalized);
            await ExecuteItemWriteAsync(command, cancellationToken);
        }

        var created = await ReadItemAsync(connection, transaction, itemId, cancellationToken);
        await WriteAuditAsync(connection, transaction, actorUserId, itemId, "created", null, created, cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return created;
    }

    /// <inheritdoc />
    public async Task<CatalogItemSummary> UpdateItemAsync(
        Guid actorUserId,
        Guid itemId,
        SaveCatalogItemRequest request,
        CancellationToken cancellationToken)
    {
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        var before = await ReadItemAsync(connection, transaction, itemId, cancellationToken);
        var normalized = await ValidateAsync(connection, transaction, request, cancellationToken);
        await using (var command = connection.CreateCommand())
        {
            command.Transaction = transaction;
            command.CommandText = """
                UPDATE catalog_items
                SET category_id = @category_id,
                    section_id = @section_id,
                    group_id = @group_id,
                    name = @name,
                    marking = @marking,
                    status = @status,
                    values = CAST(@values AS jsonb),
                    updated_by = @actor,
                    updated_at = now()
                WHERE id = @id AND deleted_at IS NULL
                """;
            AddItemParameters(command, itemId, actorUserId, normalized);
            if (await ExecuteItemWriteAsync(command, cancellationToken) != 1)
                throw NotFound();
        }

        var updated = await ReadItemAsync(connection, transaction, itemId, cancellationToken);
        await WriteAuditAsync(connection, transaction, actorUserId, itemId, "updated", before, updated, cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return updated;
    }

    /// <inheritdoc />
    public async Task DeleteItemAsync(Guid actorUserId, Guid itemId, CancellationToken cancellationToken)
    {
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        var before = await ReadItemAsync(connection, transaction, itemId, cancellationToken);
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            UPDATE catalog_items
            SET deleted_at = now(), deleted_by = @actor,
                delete_reason = 'Удалено пользователем', updated_at = now(), updated_by = @actor
            WHERE id = @id AND deleted_at IS NULL
            """;
        AddParameter(command, "actor", actorUserId);
        AddParameter(command, "id", itemId);
        if (await command.ExecuteNonQueryAsync(cancellationToken) != 1) throw NotFound();
        await WriteAuditAsync(connection, transaction, actorUserId, itemId, "deleted", before, null, cancellationToken);
        await transaction.CommitAsync(cancellationToken);
    }

    /// <inheritdoc />
    public async Task<IReadOnlyList<CatalogItemImageSummary>> GetImagesAsync(
        Guid itemId,
        CancellationToken cancellationToken)
    {
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        await ReadItemAsync(connection, null, itemId, cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT id, file_name, content_type, byte_size, sort_order, object_key
            FROM catalog_item_images
            WHERE catalog_item_id = @item_id
              AND ready_at IS NOT NULL AND deleted_at IS NULL
            ORDER BY sort_order, created_at, id
            """;
        AddParameter(command, "item_id", itemId);
        var rows = new List<ImageRow>();
        await using (var reader = await command.ExecuteReaderAsync(cancellationToken))
        {
            while (await reader.ReadAsync(cancellationToken))
                rows.Add(new ImageRow(
                    reader.GetGuid(0),
                    reader.GetString(1),
                    reader.GetString(2),
                    reader.GetInt64(3),
                    reader.GetInt32(4),
                    reader.GetString(5),
                    true));
        }

        var result = new List<CatalogItemImageSummary>(rows.Count);
        foreach (var row in rows)
        {
            result.Add(new CatalogItemImageSummary(
                row.Id,
                row.FileName,
                row.ContentType,
                row.ByteSize,
                row.SortOrder,
                await objectStorage.CreateDownloadUrlAsync(
                    row.ObjectKey,
                    TimeSpan.FromMinutes(5),
                    cancellationToken)));
        }
        return result;
    }

    /// <inheritdoc />
    public async Task<CatalogImageUploadTicket> BeginImageUploadAsync(
        Guid actorUserId,
        Guid itemId,
        BeginCatalogImageUploadRequest request,
        CancellationToken cancellationToken)
    {
        var fileName = Path.GetFileName(request.FileName.Trim());
        if (fileName.Length is < 1 or > 180)
            throw Invalid("catalog_image_name_invalid", "Имя изображения должно содержать от 1 до 180 символов.");
        if (!ImageExtensions.TryGetValue(request.ContentType.Trim(), out var extension))
            throw Invalid("catalog_image_type_invalid", "Допустимы изображения JPEG, PNG и WebP.");
        if (request.ByteSize is < 1 or > MaxImageByteSize)
            throw Invalid("catalog_image_size_invalid", "Размер изображения не должен превышать 10 МБ.");

        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        await ReadItemAsync(connection, transaction, itemId, cancellationToken);
        int sortOrder;
        await using (var count = connection.CreateCommand())
        {
            count.Transaction = transaction;
            count.CommandText = """
                SELECT count(*), COALESCE(max(sort_order), -1) + 1
                FROM catalog_item_images
                WHERE catalog_item_id = @item_id AND deleted_at IS NULL
                  AND (ready_at IS NOT NULL OR created_at > now() - interval '1 hour')
                """;
            AddParameter(count, "item_id", itemId);
            await using var reader = await count.ExecuteReaderAsync(cancellationToken);
            await reader.ReadAsync(cancellationToken);
            if (reader.GetInt64(0) >= MaxImagesPerItem)
                throw Invalid("catalog_image_limit", "К одной карточке можно добавить не более 8 изображений.");
            sortOrder = reader.GetInt32(1);
        }

        var imageId = Guid.NewGuid();
        var objectKey = $"catalog/{itemId:N}/{imageId:N}{extension}";
        await using (var insert = connection.CreateCommand())
        {
            insert.Transaction = transaction;
            insert.CommandText = """
                INSERT INTO catalog_item_images
                    (id, catalog_item_id, object_key, file_name, content_type,
                     byte_size, sort_order, created_by)
                VALUES
                    (@id, @item_id, @object_key, @file_name, @content_type,
                     @byte_size, @sort_order, @actor)
                """;
            AddParameter(insert, "id", imageId);
            AddParameter(insert, "item_id", itemId);
            AddParameter(insert, "object_key", objectKey);
            AddParameter(insert, "file_name", fileName);
            AddParameter(insert, "content_type", request.ContentType.Trim().ToLowerInvariant());
            AddParameter(insert, "byte_size", request.ByteSize);
            AddParameter(insert, "sort_order", sortOrder);
            AddParameter(insert, "actor", actorUserId);
            await insert.ExecuteNonQueryAsync(cancellationToken);
        }
        await transaction.CommitAsync(cancellationToken);

        var expiresAt = DateTimeOffset.UtcNow.AddMinutes(5);
        return new CatalogImageUploadTicket(
            imageId,
            await objectStorage.CreateUploadUrlAsync(
                objectKey,
                request.ContentType.Trim().ToLowerInvariant(),
                TimeSpan.FromMinutes(5),
                cancellationToken),
            expiresAt);
    }

    /// <inheritdoc />
    public async Task<CatalogItemImageSummary> ConfirmImageUploadAsync(
        Guid actorUserId,
        Guid itemId,
        Guid imageId,
        CancellationToken cancellationToken)
    {
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        var row = await ReadImageRowAsync(connection, transaction, itemId, imageId, false, cancellationToken);
        var metadata = await objectStorage.GetMetadataAsync(row.ObjectKey, cancellationToken);
        if (metadata is null || metadata.ByteSize != row.ByteSize ||
            !string.Equals(metadata.ContentType, row.ContentType, StringComparison.OrdinalIgnoreCase))
        {
            throw Invalid("catalog_image_upload_invalid", "Загруженный файл не соответствует выбранному изображению.");
        }

        await using (var update = connection.CreateCommand())
        {
            update.Transaction = transaction;
            update.CommandText = """
                UPDATE catalog_item_images SET ready_at = COALESCE(ready_at, now())
                WHERE id = @id AND catalog_item_id = @item_id AND deleted_at IS NULL
                """;
            AddParameter(update, "id", imageId);
            AddParameter(update, "item_id", itemId);
            if (await update.ExecuteNonQueryAsync(cancellationToken) != 1)
                throw ImageNotFound();
        }
        await WriteImageAuditAsync(connection, transaction, actorUserId, itemId, imageId, "image_added", cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        var downloadUrl = await objectStorage.CreateDownloadUrlAsync(row.ObjectKey, TimeSpan.FromMinutes(5), cancellationToken);
        return new CatalogItemImageSummary(row.Id, row.FileName, row.ContentType, row.ByteSize, row.SortOrder, downloadUrl);
    }

    /// <inheritdoc />
    public async Task DeleteImageAsync(
        Guid actorUserId,
        Guid itemId,
        Guid imageId,
        CancellationToken cancellationToken)
    {
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        var row = await ReadImageRowAsync(connection, transaction, itemId, imageId, false, cancellationToken);
        await using (var update = connection.CreateCommand())
        {
            update.Transaction = transaction;
            update.CommandText = """
                UPDATE catalog_item_images SET deleted_at = now()
                WHERE id = @id AND catalog_item_id = @item_id AND deleted_at IS NULL
                """;
            AddParameter(update, "id", imageId);
            AddParameter(update, "item_id", itemId);
            if (await update.ExecuteNonQueryAsync(cancellationToken) != 1)
                throw ImageNotFound();
        }
        await WriteImageAuditAsync(
            connection,
            transaction,
            actorUserId,
            itemId,
            imageId,
            row.IsReady ? "image_deleted" : "image_upload_cancelled",
            cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        await objectStorage.DeleteAsync(row.ObjectKey, cancellationToken);
    }

    private static async Task<IReadOnlyList<CatalogCategorySummary>> ReadCategoriesAsync(
        DbConnection connection,
        CancellationToken token)
    {
        var categories = new Dictionary<Guid, MutableCategory>();
        await using (var fields = connection.CreateCommand())
        {
            fields.CommandText = """
                SELECT category.id, category.name, category.sort_order,
                       field.field_code, field.is_visible, field.is_required, field.sort_order,
                       field.dictionary_code
                FROM catalog_categories AS category
                LEFT JOIN catalog_category_fields AS field ON field.category_id = category.id
                ORDER BY category.sort_order, field.sort_order
                """;
            await using var reader = await fields.ExecuteReaderAsync(token);
            while (await reader.ReadAsync(token))
            {
                var id = reader.GetGuid(0);
                if (!categories.TryGetValue(id, out var category))
                {
                    category = new MutableCategory(id, reader.GetString(1), reader.GetInt32(2));
                    categories.Add(id, category);
                }
                if (!reader.IsDBNull(3))
                {
                    var definition = OnboardingFieldRegistry.Get(reader.GetString(3));
                    category.Fields.Add(new CatalogFieldSummary(
                        definition.Code,
                        definition.Label,
                        definition.FieldType,
                        reader.GetBoolean(4),
                        reader.GetBoolean(5),
                        reader.GetInt32(6),
                        reader.IsDBNull(7) ? null : reader.GetString(7)));
                }
            }
        }

        await using (var structure = connection.CreateCommand())
        {
            structure.CommandText = """
                SELECT section.category_id, section.id, section.name, section.sort_order,
                       catalog_group.id, catalog_group.name, catalog_group.sort_order
                FROM catalog_sections AS section
                LEFT JOIN catalog_groups AS catalog_group ON catalog_group.section_id = section.id
                ORDER BY section.category_id, section.sort_order, catalog_group.sort_order
                """;
            await using var reader = await structure.ExecuteReaderAsync(token);
            while (await reader.ReadAsync(token))
            {
                if (!categories.TryGetValue(reader.GetGuid(0), out var category)) continue;
                var sectionId = reader.GetGuid(1);
                if (!category.Sections.TryGetValue(sectionId, out var section))
                {
                    section = new MutableSection(sectionId, reader.GetString(2), reader.GetInt32(3));
                    category.Sections.Add(sectionId, section);
                }
                if (!reader.IsDBNull(4))
                    section.Groups.Add(new CatalogGroupSummary(
                        reader.GetGuid(4), reader.GetString(5), reader.GetInt32(6)));
            }
        }
        return categories.Values.OrderBy(item => item.SortOrder).Select(item => item.ToSummary()).ToArray();
    }

    private static async Task<IReadOnlyList<CatalogDictionarySummary>> ReadDictionariesAsync(
        DbConnection connection,
        CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT dictionary.id, dictionary.code, dictionary.name, dictionary.sort_order,
                   item.id, item.value, item.sort_order
            FROM dictionary_types AS dictionary
            LEFT JOIN dictionary_items AS item ON item.dictionary_type_id = dictionary.id
            ORDER BY dictionary.sort_order, item.sort_order
            """;
        var dictionaries = new Dictionary<Guid, MutableDictionary>();
        await using var reader = await command.ExecuteReaderAsync(token);
        while (await reader.ReadAsync(token))
        {
            var id = reader.GetGuid(0);
            if (!dictionaries.TryGetValue(id, out var dictionary))
            {
                dictionary = new MutableDictionary(id, reader.GetString(1), reader.GetString(2), reader.GetInt32(3));
                dictionaries.Add(id, dictionary);
            }
            if (!reader.IsDBNull(4))
                dictionary.Items.Add(new CatalogDictionaryItemSummary(
                    reader.GetGuid(4), reader.GetString(5), reader.GetInt32(6)));
        }
        return dictionaries.Values.OrderBy(item => item.SortOrder).Select(item => item.ToSummary()).ToArray();
    }

    private static async Task<NormalizedItem> ValidateAsync(
        DbConnection connection,
        DbTransaction transaction,
        SaveCatalogItemRequest request,
        CancellationToken token)
    {
        var name = request.Name.Trim();
        var marking = request.Marking?.Trim() ?? string.Empty;
        if (name.Length is < 1 or > 240)
            throw Invalid("catalog_name_invalid", "Наименование должно содержать от 1 до 240 символов.");
        if (marking.Length > 240)
            throw Invalid("catalog_marking_invalid", "Маркировка должна содержать не более 240 символов.");
        var status = NormalizeStatus(request.Status, false)!;
        var values = request.Values?.ToDictionary(item => item.Key.Trim(), item => item.Value.Clone(), StringComparer.Ordinal)
                     ?? new Dictionary<string, JsonElement>(StringComparer.Ordinal);
        if (values.Keys.Any(string.IsNullOrWhiteSpace) || values.Keys.Any(ReservedValueCodes.Contains))
            throw Invalid("catalog_field_invalid", "Системные поля карточки нельзя передавать в наборе значений.");

        var configured = new Dictionary<string, bool>(StringComparer.Ordinal);
        await using (var fields = connection.CreateCommand())
        {
            fields.Transaction = transaction;
            fields.CommandText = """
                SELECT field.field_code, field.is_required
                FROM catalog_categories AS category
                JOIN catalog_category_fields AS field ON field.category_id = category.id
                WHERE category.id = @category_id
                """;
            AddParameter(fields, "category_id", request.CategoryId);
            await using var reader = await fields.ExecuteReaderAsync(token);
            while (await reader.ReadAsync(token)) configured.Add(reader.GetString(0), reader.GetBoolean(1));
        }
        if (configured.Count == 0)
            throw Invalid("catalog_category_invalid", "Категория каталога не найдена или не имеет полей.");
        if (values.Keys.Any(code => !configured.ContainsKey(code)))
            throw Invalid("catalog_field_invalid", "Карточка содержит поле, не настроенное для выбранной категории.");
        if (configured.GetValueOrDefault("marking") && string.IsNullOrEmpty(marking))
            throw Invalid("catalog_required_field_missing", "Заполните обязательное поле «Маркировка / размер».");
        if (configured.GetValueOrDefault("group") && request.GroupId is null)
            throw Invalid("catalog_required_field_missing", "Выберите обязательную группу.");
        foreach (var field in configured.Where(item => item.Value && !ReservedValueCodes.Contains(item.Key)))
        {
            if (!values.TryGetValue(field.Key, out var value) || IsEmpty(value))
                throw Invalid("catalog_required_field_missing", $"Заполните обязательное поле «{OnboardingFieldRegistry.Get(field.Key).Label}».");
        }
        foreach (var value in values) ValidateValue(value.Key, value.Value);

        await ValidateStructureAsync(connection, transaction, request.CategoryId, request.SectionId, request.GroupId, token);
        return new NormalizedItem(
            request.CategoryId,
            request.SectionId,
            request.GroupId,
            name,
            marking,
            status,
            values);
    }

    private static void ValidateValue(string code, JsonElement value)
    {
        if (value.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined) return;
        var definition = OnboardingFieldRegistry.Get(code);
        var valid = definition.FieldType switch
        {
            "text" or "dictionary" or "enum" => value.ValueKind == JsonValueKind.String,
            "number" or "money" or "percent" => TryDecimal(value, out _),
            "boolean" => value.ValueKind is JsonValueKind.True or JsonValueKind.False,
            "relation" => value.ValueKind == JsonValueKind.Array,
            "calculated_money" => false,
            _ => false,
        };
        if (!valid)
            throw Invalid("catalog_field_type_invalid", $"Поле «{definition.Label}» имеет неверный тип значения.");
        if (code == "base_price" && TryDecimal(value, out var price) && !CatalogItemRules.IsValidPrice(price))
            throw Invalid("catalog_price_invalid", "Цена товара должна быть больше нуля.");
    }

    private static async Task ValidateStructureAsync(
        DbConnection connection,
        DbTransaction transaction,
        Guid categoryId,
        Guid? sectionId,
        Guid? groupId,
        CancellationToken token)
    {
        if (sectionId is null && groupId is null) return;
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            SELECT EXISTS (
                SELECT 1
                FROM catalog_sections AS section
                LEFT JOIN catalog_groups AS catalog_group
                    ON catalog_group.section_id = section.id AND catalog_group.id = @group_id
                WHERE section.id = @section_id AND section.category_id = @category_id
                  AND (@group_id IS NULL OR catalog_group.id IS NOT NULL)
            )
            """;
        AddParameter(command, "category_id", categoryId);
        AddGuidParameter(command, "section_id", sectionId);
        AddGuidParameter(command, "group_id", groupId);
        if (await command.ExecuteScalarAsync(token) is not true)
            throw Invalid("catalog_structure_invalid", "Раздел или группа не принадлежат выбранной категории.");
    }

    private static async Task<CatalogItemSummary> ReadItemAsync(
        DbConnection connection,
        DbTransaction? transaction,
        Guid itemId,
        CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            SELECT id, category_id, section_id, group_id, name, marking, status,
                   values, created_by, created_at, updated_by, updated_at
            FROM catalog_items
            WHERE id = @id AND deleted_at IS NULL
            """;
        AddParameter(command, "id", itemId);
        await using var reader = await command.ExecuteReaderAsync(token);
        return await reader.ReadAsync(token) ? ReadItem(reader) : throw NotFound();
    }

    private static CatalogItemSummary ReadItem(DbDataReader reader) => new(
        reader.GetGuid(0),
        reader.GetGuid(1),
        reader.IsDBNull(2) ? null : reader.GetGuid(2),
        reader.IsDBNull(3) ? null : reader.GetGuid(3),
        reader.GetString(4),
        reader.GetString(5),
        reader.GetString(6),
        ReadValues(reader.GetString(7)),
        reader.IsDBNull(8) ? null : reader.GetGuid(8),
        new DateTimeOffset(reader.GetFieldValue<DateTime>(9)),
        reader.IsDBNull(10) ? null : reader.GetGuid(10),
        new DateTimeOffset(reader.GetFieldValue<DateTime>(11)));

    private static Dictionary<string, JsonElement> ReadValues(string json)
    {
        using var document = JsonDocument.Parse(json);
        return document.RootElement.EnumerateObject()
            .ToDictionary(item => item.Name, item => item.Value.Clone(), StringComparer.Ordinal);
    }

    private static async Task<ImageRow> ReadImageRowAsync(
        DbConnection connection,
        DbTransaction transaction,
        Guid itemId,
        Guid imageId,
        bool requireReady,
        CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            SELECT id, file_name, content_type, byte_size, sort_order, object_key,
                   ready_at IS NOT NULL
            FROM catalog_item_images
            WHERE id = @id AND catalog_item_id = @item_id AND deleted_at IS NULL
              AND (@require_ready = false OR ready_at IS NOT NULL)
            """;
        AddParameter(command, "id", imageId);
        AddParameter(command, "item_id", itemId);
        AddParameter(command, "require_ready", requireReady);
        await using var reader = await command.ExecuteReaderAsync(token);
        if (!await reader.ReadAsync(token)) throw ImageNotFound();
        return new ImageRow(
            reader.GetGuid(0),
            reader.GetString(1),
            reader.GetString(2),
            reader.GetInt64(3),
            reader.GetInt32(4),
            reader.GetString(5),
            reader.GetBoolean(6));
    }

    private static async Task WriteImageAuditAsync(
        DbConnection connection,
        DbTransaction transaction,
        Guid actor,
        Guid itemId,
        Guid imageId,
        string action,
        CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            INSERT INTO audit_log (actor_user_id, entity_type, entity_id, action, diff)
            VALUES (@actor, 'catalog_item', @item_id, @action,
                    jsonb_build_object('imageId', @image_id))
            """;
        AddParameter(command, "actor", actor);
        AddParameter(command, "item_id", itemId);
        AddParameter(command, "image_id", imageId);
        AddParameter(command, "action", action);
        await command.ExecuteNonQueryAsync(token);
    }

    private static async Task WriteAuditAsync(
        DbConnection connection,
        DbTransaction transaction,
        Guid actor,
        Guid itemId,
        string action,
        CatalogItemSummary? before,
        CatalogItemSummary? after,
        CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            INSERT INTO audit_log (actor_user_id, entity_type, entity_id, action, diff)
            VALUES (@actor, 'catalog_item', @item_id, @action, CAST(@diff AS jsonb))
            """;
        AddParameter(command, "actor", actor);
        AddParameter(command, "item_id", itemId);
        AddParameter(command, "action", action);
        AddParameter(command, "diff", JsonSerializer.Serialize(new { before, after }, JsonOptions));
        await command.ExecuteNonQueryAsync(token);
    }

    private static void AddItemParameters(DbCommand command, Guid itemId, Guid actor, NormalizedItem item)
    {
        AddParameter(command, "id", itemId);
        AddParameter(command, "actor", actor);
        AddParameter(command, "category_id", item.CategoryId);
        AddGuidParameter(command, "section_id", item.SectionId);
        AddGuidParameter(command, "group_id", item.GroupId);
        AddParameter(command, "name", item.Name);
        AddParameter(command, "marking", item.Marking);
        AddParameter(command, "status", item.Status);
        AddParameter(command, "values", JsonSerializer.Serialize(item.Values, JsonOptions));
    }

    private static async Task<int> ExecuteItemWriteAsync(DbCommand command, CancellationToken token)
    {
        try
        {
            return await command.ExecuteNonQueryAsync(token);
        }
        catch (PostgresException exception) when (exception.SqlState == PostgresErrorCodes.UniqueViolation)
        {
            throw new IdentityException(409, "catalog_item_exists", "Товар с такой группой, наименованием и маркировкой уже существует.");
        }
        catch (PostgresException exception) when (exception.SqlState == PostgresErrorCodes.ForeignKeyViolation)
        {
            throw Invalid("catalog_structure_invalid", "Категория, раздел или группа каталога не существуют.");
        }
    }

    private static string? NormalizeStatus(string? value, bool allowEmpty)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            if (allowEmpty) return null;
            throw Invalid("catalog_status_invalid", "Укажите статус товара.");
        }
        var status = value.Trim().ToLowerInvariant();
        return status is "pending" or "approved"
            ? status
            : throw Invalid("catalog_status_invalid", "Неизвестный статус товара.");
    }

    private static bool IsEmpty(JsonElement value) =>
        value.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined ||
        value.ValueKind == JsonValueKind.String && string.IsNullOrWhiteSpace(value.GetString());

    private static bool TryDecimal(JsonElement value, out decimal result)
    {
        if (value.ValueKind == JsonValueKind.Number) return value.TryGetDecimal(out result);
        if (value.ValueKind == JsonValueKind.String)
            return decimal.TryParse(value.GetString(), NumberStyles.Number, CultureInfo.InvariantCulture, out result);
        result = default;
        return false;
    }

    private static IdentityException Invalid(string code, string message) => new(400, code, message);

    private static IdentityException NotFound() =>
        new(404, "catalog_item_not_found", "Товар каталога не найден.");

    private static IdentityException ImageNotFound() =>
        new(404, "catalog_image_not_found", "Изображение товара не найдено.");

    private static void AddParameter(DbCommand command, string name, object value)
    {
        var parameter = command.CreateParameter();
        parameter.ParameterName = name;
        parameter.Value = value;
        command.Parameters.Add(parameter);
    }

    private static void AddGuidParameter(DbCommand command, string name, Guid? value)
    {
        var parameter = command.CreateParameter();
        parameter.ParameterName = name;
        parameter.Value = value.HasValue ? value.Value : DBNull.Value;
        if (parameter is NpgsqlParameter npgsqlParameter)
            npgsqlParameter.NpgsqlDbType = NpgsqlDbType.Uuid;
        command.Parameters.Add(parameter);
    }

    private sealed record NormalizedItem(
        Guid CategoryId,
        Guid? SectionId,
        Guid? GroupId,
        string Name,
        string Marking,
        string Status,
        IReadOnlyDictionary<string, JsonElement> Values);

    private sealed record ImageRow(
        Guid Id,
        string FileName,
        string ContentType,
        long ByteSize,
        int SortOrder,
        string ObjectKey,
        bool IsReady);

    private sealed class MutableCategory(Guid id, string name, int sortOrder)
    {
        public Guid Id { get; } = id;
        public string Name { get; } = name;
        public int SortOrder { get; } = sortOrder;
        public List<CatalogFieldSummary> Fields { get; } = [];
        public Dictionary<Guid, MutableSection> Sections { get; } = [];
        public CatalogCategorySummary ToSummary() =>
            new(Id, Name, SortOrder, Fields, Sections.Values.OrderBy(item => item.SortOrder).Select(item => item.ToSummary()).ToArray());
    }

    private sealed class MutableSection(Guid id, string name, int sortOrder)
    {
        public Guid Id { get; } = id;
        public string Name { get; } = name;
        public int SortOrder { get; } = sortOrder;
        public List<CatalogGroupSummary> Groups { get; } = [];
        public CatalogSectionSummary ToSummary() => new(Id, Name, SortOrder, Groups);
    }

    private sealed class MutableDictionary(Guid id, string code, string name, int sortOrder)
    {
        public Guid Id { get; } = id;
        public string Code { get; } = code;
        public string Name { get; } = name;
        public int SortOrder { get; } = sortOrder;
        public List<CatalogDictionaryItemSummary> Items { get; } = [];
        public CatalogDictionarySummary ToSummary() => new(Id, Code, Name, SortOrder, Items);
    }
}
