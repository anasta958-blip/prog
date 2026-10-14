using System.Data.Common;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using Npgsql;
using SkladKomforta.Application.Abstractions.Files;
using SkladKomforta.Application.Abstractions.Persistence;
using SkladKomforta.Application.Abstractions.Tenancy;
using SkladKomforta.Application.Company;
using SkladKomforta.Application.Identity;
using SkladKomforta.Application.Onboarding;

namespace SkladKomforta.Infrastructure.Company;

/// <summary>Работает с названием пространства и его конфигурацией, без реквизитов юрлиц.</summary>
internal sealed class PostgresCompanyService(
    IDatabaseConnectionFactory connectionFactory,
    ITenantContext tenantContext,
    IObjectStorage objectStorage,
    ILogger<PostgresCompanyService> logger) : ICompanyService
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private static readonly Action<ILogger, string, Exception?> LogObjectDeleteFailed =
        LoggerMessage.Define<string>(
            LogLevel.Error,
            new EventId(2101, nameof(LogObjectDeleteFailed)),
            "Не удалось удалить объект {ObjectKey} после удаления категории каталога.");

    public async Task<OrganizationOnboardingDraft> GetConfigurationAsync(
        CancellationToken cancellationToken)
    {
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        var draft = await ReadDraftAsync(connection, cancellationToken);
        var profile = await ReadAsync(connection, cancellationToken);
        return draft with { Company = ToDraft(profile), CurrentStep = 10 };
    }

    public async Task<OrganizationOnboardingDraft> UpdateConfigurationAsync(
        Guid userId,
        OrganizationOnboardingDraft draft,
        IReadOnlyList<string> deleteCategoryData,
        CancellationToken cancellationToken)
    {
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        var profile = await ReadAsync(connection, cancellationToken);
        var normalized = draft with { CurrentStep = 10, Company = ToDraft(profile) };
        // Рабочая конфигурация уже активирована. При её редактировании проверяем
        // структуру и ссылки, но не требования мастера первичной активации:
        // удаление категории может временно оставить канбан без категорий.
        OnboardingValidator.Validate(normalized, false);
        var previous = await ReadDraftAsync(connection, cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        var objectKeysToDelete = new List<string>();
        try
        {
            var deletions = await PrepareCategoryDeletionsAsync(
                connection, transaction, previous, normalized,
                deleteCategoryData, cancellationToken);
            foreach (var deletion in deletions)
            {
                objectKeysToDelete.AddRange(deletion.ObjectKeys);
                await ExecuteAsync(connection, transaction,
                    "DELETE FROM catalog_items WHERE category_id = @category_id",
                    cancellationToken, ("category_id", deletion.CategoryId));
                await ExecuteAsync(connection, transaction, """
                    INSERT INTO audit_log (actor_user_id, entity_type, entity_id, action, diff)
                    VALUES (@user_id, 'catalog_category', @category_id,
                            'deleted_with_data', CAST(@diff AS jsonb))
                    """, cancellationToken,
                    ("user_id", userId), ("category_id", deletion.CategoryId),
                    ("diff", JsonSerializer.Serialize(new
                    {
                        categoryName = deletion.Impact.CategoryName,
                        itemCount = deletion.Impact.ItemCount,
                        imageCount = deletion.Impact.ImageCount,
                        relationCount = deletion.Impact.RelationCount
                    }, JsonOptions)));
            }
            await SyncDictionariesAsync(connection, transaction, normalized.Dictionaries, cancellationToken);
            // Keep unchanged dependency identities: deleting them cascades to product links.
            await ExecuteAsync(connection, transaction, """
                DELETE FROM catalog_category_dependencies AS dependency
                WHERE NOT EXISTS (
                    SELECT 1
                    FROM jsonb_array_elements(CAST(@dependencies AS jsonb)) AS desired
                    JOIN catalog_categories AS source
                      ON source.client_id = desired->>'sourceCategoryClientId'
                    JOIN catalog_categories AS target
                      ON target.client_id = desired->>'targetCategoryClientId'
                    WHERE dependency.client_id = desired->>'clientId'
                      AND dependency.source_category_id = source.id
                      AND dependency.target_category_id = target.id
                      AND dependency.target_field_code = desired->>'targetFieldCode')
                """, cancellationToken,
                ("dependencies", JsonSerializer.Serialize(normalized.Dependencies ?? [], JsonOptions)));
            var categoryIds = await SyncCatalogAsync(
                connection, transaction, previous.Categories, normalized.Categories, cancellationToken);
            await SyncWorkflowsAsync(
                connection, transaction, previous.Workflows, normalized.Workflows, categoryIds, cancellationToken);
            await SyncDependenciesAsync(
                connection, transaction, normalized.Dependencies ?? [], categoryIds, cancellationToken);
            await SyncEntityFieldsAsync(connection, transaction, normalized.Fields, cancellationToken);
            // Роли после активации управляются отдельным разделом прав доступа.
            // Повторное сохранение каталогов или канбанов не должно перетирать их.

            await ExecuteAsync(connection, transaction, """
                UPDATE onboarding_draft
                SET current_step = 9, payload = CAST(@payload AS jsonb),
                    updated_by = @user_id, updated_at = now()
                WHERE singleton
                """, cancellationToken,
                ("payload", JsonSerializer.Serialize(normalized, JsonOptions)), ("user_id", userId));
            var configurationDiff = AuditChanges.Serialize(previous, normalized);
            if (configurationDiff is not null)
                await ExecuteAsync(connection, transaction, """
                INSERT INTO audit_log (actor_user_id, entity_type, entity_id, action, diff)
                VALUES (@user_id, 'organization_configuration', @organization_id,
                        'updated', CAST(@diff AS jsonb))
                """, cancellationToken,
                ("user_id", userId), ("organization_id", tenantContext.OrganizationId),
                ("diff", configurationDiff));
            await transaction.CommitAsync(cancellationToken);
        }
        catch (PostgresException exception) when (exception.SqlState is "23001" or "23503" or "23505")
        {
            throw new IdentityException(
                409,
                "organization_configuration_conflict",
                exception.SqlState is "23001" or "23503"
                    ? "Нельзя удалить элемент настройки, который используется в рабочих данных."
                    : "В настройках организации обнаружены повторяющиеся значения.");
        }

        foreach (var objectKey in objectKeysToDelete.Distinct(StringComparer.Ordinal))
        {
            try
            {
                await objectStorage.DeleteAsync(objectKey, CancellationToken.None);
            }
            catch (Exception exception)
            {
                LogObjectDeleteFailed(logger, objectKey, exception);
            }
        }
        return normalized;
    }

    public async Task<CategoryDeletionImpact> GetCategoryDeletionImpactAsync(
        string categoryClientId,
        CancellationToken cancellationToken)
    {
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        var draft = await ReadDraftAsync(connection, cancellationToken);
        var categoryIndex = draft.Categories.ToList().FindIndex(
            category => category.ClientId == categoryClientId);
        if (categoryIndex < 0)
            throw new IdentityException(404, "catalog_category_not_found", "Категория не найдена.");

        var rows = await ReadOrderedRowsAsync(
            connection, null, "SELECT id, name FROM catalog_categories ORDER BY sort_order", cancellationToken);
        if (categoryIndex >= rows.Count)
            throw new IdentityException(409, "organization_configuration_invalid", "Настройки каталога не соответствуют данным базы.");

        return await ReadCategoryDeletionImpactAsync(
            connection, null, categoryClientId, rows[categoryIndex], cancellationToken);
    }

    public async Task<CompanyProfile> GetAsync(CancellationToken cancellationToken)
    {
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        return await ReadAsync(connection, cancellationToken);
    }

    public async Task<CompanyProfile> UpdateAsync(
        Guid userId,
        CompanyProfile profile,
        CancellationToken cancellationToken)
    {
        OnboardingValidator.ValidateCompany(new CompanyProfileDraft(profile.OrganizationName));

        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        var before = await ReadAsync(connection, cancellationToken, transaction);

        await ExecuteAsync(connection, transaction,
            "UPDATE public.organizations SET name = @name, updated_at = now() WHERE id = @organization_id",
            cancellationToken,
            ("name", profile.OrganizationName.Trim()), ("organization_id", tenantContext.OrganizationId));

        var profileDiff = AuditChanges.Serialize(before, profile);
        if (profileDiff is not null)
            await ExecuteAsync(connection, transaction, """
            INSERT INTO audit_log (actor_user_id, entity_type, entity_id, action, diff)
            VALUES (@user_id, 'organization_profile', @organization_id, 'updated', CAST(@diff AS jsonb))
            """, cancellationToken,
            ("user_id", userId), ("organization_id", tenantContext.OrganizationId),
            ("diff", profileDiff));

        await transaction.CommitAsync(cancellationToken);
        return await ReadAsync(connection, cancellationToken);
    }

    private static async Task<OrganizationOnboardingDraft> ReadDraftAsync(
        DbConnection connection,
        CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.CommandText = "SELECT payload FROM onboarding_draft WHERE singleton";
        var payload = await command.ExecuteScalarAsync(token) as string;
        return payload is not null
            ? JsonSerializer.Deserialize<OrganizationOnboardingDraft>(payload, JsonOptions)
              ?? throw new IdentityException(500, "organization_configuration_invalid", "Настройки организации повреждены.")
            : throw new IdentityException(404, "organization_configuration_not_found", "Настройки организации не найдены.");
    }

    private static async Task<IReadOnlyList<CategoryDeletionPlan>> PrepareCategoryDeletionsAsync(
        DbConnection connection,
        DbTransaction transaction,
        OrganizationOnboardingDraft previous,
        OrganizationOnboardingDraft next,
        IReadOnlyList<string> approvedCategoryClientIds,
        CancellationToken token)
    {
        var retainedIds = next.Categories
            .Select(category => category.ClientId)
            .ToHashSet(StringComparer.Ordinal);
        var removedCategories = previous.Categories
            .Select((category, index) => (Category: category, Index: index))
            .Where(item => !retainedIds.Contains(item.Category.ClientId))
            .ToArray();
        var removedIds = removedCategories
            .Select(item => item.Category.ClientId)
            .ToHashSet(StringComparer.Ordinal);
        var approvedIds = approvedCategoryClientIds.ToHashSet(StringComparer.Ordinal);

        if (approvedIds.Except(removedIds).Any())
            throw new IdentityException(
                400,
                "catalog_category_delete_confirmation_invalid",
                "Разрешение на удаление данных относится к категории, которая не удаляется.");

        var rows = await ReadOrderedRowsAsync(
            connection, transaction,
            "SELECT id, name FROM catalog_categories ORDER BY sort_order", token);
        var result = new List<CategoryDeletionPlan>();
        foreach (var removed in removedCategories)
        {
            if (removed.Index >= rows.Count)
                throw new IdentityException(
                    409,
                    "organization_configuration_invalid",
                    "Настройки каталога не соответствуют данным базы.");

            var row = rows[removed.Index];
            var impact = await ReadCategoryDeletionImpactAsync(
                connection, transaction, removed.Category.ClientId, row, token);
            if (!approvedIds.Contains(removed.Category.ClientId))
            {
                if (impact.ItemCount > 0 || impact.ImageCount > 0 || impact.RelationCount > 0)
                    throw new IdentityException(
                        409,
                        "catalog_category_not_empty",
                        $"Категория «{impact.CategoryName}» содержит рабочие данные. Подтвердите их удаление отдельно.");
                continue;
            }

            var objectKeys = await ReadCategoryImageObjectKeysAsync(
                connection, transaction, row.Id, token);
            result.Add(new CategoryDeletionPlan(row.Id, impact, objectKeys));
        }
        return result;
    }

    private static async Task<CategoryDeletionImpact> ReadCategoryDeletionImpactAsync(
        DbConnection connection,
        DbTransaction? transaction,
        string categoryClientId,
        ExistingRow category,
        CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            SELECT
                (SELECT count(*) FROM catalog_items item
                 WHERE item.category_id = @category_id),
                (SELECT count(*) FROM catalog_item_images image
                 JOIN catalog_items item ON item.id = image.catalog_item_id
                 WHERE item.category_id = @category_id),
                (SELECT count(DISTINCT relation.id)
                 FROM catalog_item_relations relation
                 JOIN catalog_items target_item ON target_item.id = relation.target_item_id
                 JOIN catalog_items source_item ON source_item.id = relation.source_item_id
                 WHERE target_item.category_id = @category_id
                    OR source_item.category_id = @category_id)
            """;
        Add(command, "category_id", category.Id);
        await using var reader = await command.ExecuteReaderAsync(token);
        await reader.ReadAsync(token);
        return new CategoryDeletionImpact(
            categoryClientId,
            category.Key,
            checked((int)reader.GetInt64(0)),
            checked((int)reader.GetInt64(1)),
            checked((int)reader.GetInt64(2)));
    }

    private static async Task<IReadOnlyList<string>> ReadCategoryImageObjectKeysAsync(
        DbConnection connection,
        DbTransaction transaction,
        Guid categoryId,
        CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            SELECT image.object_key
            FROM catalog_item_images image
            JOIN catalog_items item ON item.id = image.catalog_item_id
            WHERE item.category_id = @category_id
            """;
        Add(command, "category_id", categoryId);
        var result = new List<string>();
        await using var reader = await command.ExecuteReaderAsync(token);
        while (await reader.ReadAsync(token)) result.Add(reader.GetString(0));
        return result;
    }

    private static async Task SyncDictionariesAsync(
        DbConnection connection,
        DbTransaction transaction,
        IReadOnlyList<DictionaryDraft> dictionaries,
        CancellationToken token)
    {
        var existing = await ReadKeyedIdsAsync(connection, transaction,
            "SELECT code, id FROM dictionary_types", token);
        var retained = new HashSet<Guid>();
        for (var index = 0; index < dictionaries.Count; index++)
        {
            var dictionary = dictionaries[index];
            var code = dictionary.Code.Trim();
            var id = existing.GetValueOrDefault(code, Guid.NewGuid());
            retained.Add(id);
            await ExecuteAsync(connection, transaction, """
                INSERT INTO dictionary_types (id, code, name, sort_order)
                VALUES (@id, @code, @name, @sort)
                ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, sort_order = EXCLUDED.sort_order
                """, token, ("id", id), ("code", code), ("name", dictionary.Name.Trim()), ("sort", index));
            await ExecuteAsync(connection, transaction,
                "DELETE FROM dictionary_items WHERE dictionary_type_id = @id", token, ("id", id));
            for (var itemIndex = 0; itemIndex < dictionary.Items.Count; itemIndex++)
                await ExecuteAsync(connection, transaction, """
                    INSERT INTO dictionary_items (id, dictionary_type_id, value, sort_order)
                    VALUES (@id, @type_id, @value, @sort)
                    """, token, ("id", Guid.NewGuid()), ("type_id", id),
                    ("value", dictionary.Items[itemIndex].Value.Trim()), ("sort", itemIndex));
        }
        await DeleteMissingAsync(connection, transaction, "dictionary_types", retained, token);
    }

    private static async Task<IReadOnlyDictionary<string, Guid>> SyncCatalogAsync(
        DbConnection connection,
        DbTransaction transaction,
        IReadOnlyList<CatalogCategoryDraft> oldCategories,
        IReadOnlyList<CatalogCategoryDraft> categories,
        CancellationToken token)
    {
        var existingByClientId = await ReadKeyedIdsAsync(connection, transaction,
            "SELECT client_id, id FROM catalog_categories", token);
        var retained = new HashSet<Guid>();
        var result = new Dictionary<string, Guid>(StringComparer.Ordinal);

        for (var index = 0; index < categories.Count; index++)
        {
            var category = categories[index];
            var id = existingByClientId.GetValueOrDefault(category.ClientId, Guid.NewGuid());
            retained.Add(id);
            result[category.ClientId] = id;
            await ExecuteAsync(connection, transaction, """
                INSERT INTO catalog_categories (id, client_id, name, sort_order)
                VALUES (@id, @client_id, @name, @sort)
                ON CONFLICT (id) DO UPDATE SET client_id = EXCLUDED.client_id,
                    name = EXCLUDED.name, sort_order = EXCLUDED.sort_order
                """, token, ("id", id), ("client_id", category.ClientId),
                ("name", category.Name.Trim()), ("sort", index));
            var oldCategory = oldCategories.FirstOrDefault(item => item.ClientId == category.ClientId);
            await SyncSectionsAsync(connection, transaction, id, oldCategory?.Sections ?? [], category.Sections, token);
            await ExecuteAsync(connection, transaction, """
                UPDATE catalog_category_fields SET sort_order = sort_order + (
                    SELECT COALESCE(MAX(sort_order), 0) + @count + 1
                    FROM catalog_category_fields WHERE category_id = @id)
                WHERE category_id = @id
                """, token, ("id", id), ("count", category.Fields.Count));
            for (var fieldIndex = 0; fieldIndex < category.Fields.Count; fieldIndex++)
            {
                var field = category.Fields[fieldIndex];
                await ExecuteAsync(connection, transaction, """
                    INSERT INTO catalog_category_fields
                        (category_id, field_code, label, field_type, is_visible, is_required, sort_order, dictionary_code)
                    VALUES (@category_id, @code, @label, @field_type, @visible, @required, @sort, @dictionary_code)
                    ON CONFLICT (category_id, field_code) DO UPDATE SET
                        label = EXCLUDED.label, field_type = EXCLUDED.field_type,
                        is_visible = EXCLUDED.is_visible, is_required = EXCLUDED.is_required,
                        sort_order = EXCLUDED.sort_order, dictionary_code = EXCLUDED.dictionary_code
                    """, token, ("category_id", id), ("code", field.FieldCode.Trim()),
                    ("label", OnboardingFieldRegistry.LabelOf(field)),
                    ("field_type", OnboardingFieldRegistry.FieldTypeOf(field)),
                    ("visible", field.IsVisible), ("required", field.IsRequired), ("sort", fieldIndex),
                    ("dictionary_code", Db(field.DictionaryCode)));
            }
            await ExecuteAsync(connection, transaction, """
                DELETE FROM catalog_category_fields
                WHERE category_id = @id AND field_code NOT IN (
                    SELECT jsonb_array_elements_text(CAST(@codes AS jsonb)))
                """, token, ("id", id),
                ("codes", JsonSerializer.Serialize(category.Fields.Select(field => field.FieldCode.Trim()), JsonOptions)));
        }
        await DeleteMissingAsync(connection, transaction, "catalog_categories", retained, token);
        return result;
    }

    private static async Task SyncSectionsAsync(
        DbConnection connection,
        DbTransaction transaction,
        Guid categoryId,
        IReadOnlyList<CatalogSectionDraft> oldSections,
        IReadOnlyList<CatalogSectionDraft> sections,
        CancellationToken token)
    {
        var rows = await ReadOrderedRowsAsync(connection, transaction,
            "SELECT id, name FROM catalog_sections WHERE category_id = @parent ORDER BY sort_order",
            token, categoryId);
        var matched = MatchByPreviousOrder(oldSections.Select(item => item.Name), rows);
        var retained = new HashSet<Guid>();
        for (var index = 0; index < sections.Count; index++)
        {
            var section = sections[index];
            var oldName = index < oldSections.Count ? oldSections[index].Name : section.Name;
            var id = matched.GetValueOrDefault(oldName, Guid.NewGuid());
            retained.Add(id);
            await ExecuteAsync(connection, transaction, """
                INSERT INTO catalog_sections (id, category_id, name, sort_order)
                VALUES (@id, @parent, @name, @sort)
                ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, sort_order = EXCLUDED.sort_order
                """, token, ("id", id), ("parent", categoryId), ("name", section.Name.Trim()), ("sort", index));
            var oldGroups = index < oldSections.Count ? oldSections[index].Groups : [];
            await SyncGroupsAsync(connection, transaction, id, oldGroups, section.Groups, token);
        }
        await DeleteMissingAsync(connection, transaction, "catalog_sections", retained, token, "category_id", categoryId);
    }

    private static async Task SyncGroupsAsync(
        DbConnection connection,
        DbTransaction transaction,
        Guid sectionId,
        IReadOnlyList<CatalogGroupDraft> oldGroups,
        IReadOnlyList<CatalogGroupDraft> groups,
        CancellationToken token)
    {
        var rows = await ReadOrderedRowsAsync(connection, transaction,
            "SELECT id, name FROM catalog_groups WHERE section_id = @parent ORDER BY sort_order", token, sectionId);
        var matched = MatchByPreviousOrder(oldGroups.Select(item => item.Name), rows);
        var retained = new HashSet<Guid>();
        for (var index = 0; index < groups.Count; index++)
        {
            var group = groups[index];
            var oldName = index < oldGroups.Count ? oldGroups[index].Name : group.Name;
            var id = matched.GetValueOrDefault(oldName, Guid.NewGuid());
            retained.Add(id);
            await ExecuteAsync(connection, transaction, """
                INSERT INTO catalog_groups (id, section_id, name, sort_order)
                VALUES (@id, @parent, @name, @sort)
                ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, sort_order = EXCLUDED.sort_order
                """, token, ("id", id), ("parent", sectionId), ("name", group.Name.Trim()), ("sort", index));
        }
        await DeleteMissingAsync(connection, transaction, "catalog_groups", retained, token, "section_id", sectionId);
    }

    private static async Task SyncWorkflowsAsync(
        DbConnection connection,
        DbTransaction transaction,
        IReadOnlyList<WorkflowDraft> oldWorkflows,
        IReadOnlyList<WorkflowDraft> workflows,
        IReadOnlyDictionary<string, Guid> categoryIds,
        CancellationToken token)
    {
        var existing = await ReadKeyedIdsAsync(connection, transaction,
            "SELECT code, id FROM workflows", token);
        var retained = new HashSet<Guid>();
        var workflowIds = new Dictionary<string, Guid>(StringComparer.Ordinal);
        var allColumnIds = new Dictionary<string, Dictionary<string, Guid>>(StringComparer.Ordinal);
        for (var index = 0; index < workflows.Count; index++)
        {
            var workflow = workflows[index];
            var id = existing.GetValueOrDefault(workflow.Code, Guid.NewGuid());
            retained.Add(id);
            workflowIds[workflow.Code.Trim()] = id;
            await ExecuteAsync(connection, transaction, """
                INSERT INTO workflows (id, code, name, sort_order, specialization)
                VALUES (@id, @code, @name, @sort, @specialization)
                ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name,
                                               sort_order = EXCLUDED.sort_order,
                                               specialization = EXCLUDED.specialization
                """, token, ("id", id), ("code", workflow.Code.Trim()),
                ("name", workflow.Name.Trim()), ("sort", index),
                ("specialization", Db(workflow.Specialization)));

            await ExecuteAsync(connection, transaction,
                "DELETE FROM workflow_transitions WHERE from_column_id IN (SELECT id FROM workflow_columns WHERE workflow_id = @id)",
                token, ("id", id));
            await ExecuteAsync(connection, transaction,
                "DELETE FROM workflow_column_creation_actions WHERE workflow_id = @id",
                token, ("id", id));
            var oldWorkflow = oldWorkflows.FirstOrDefault(item => item.Code == workflow.Code);
            var rows = await ReadOrderedRowsAsync(connection, transaction,
                "SELECT id, name FROM workflow_columns WHERE workflow_id = @parent ORDER BY sort_order", token, id);
            var oldColumns = oldWorkflow?.Columns ?? [];
            var matched = MatchByPreviousOrder(oldColumns.Select(item => item.ClientId), rows);
            var columnIds = new Dictionary<string, Guid>(StringComparer.Ordinal);
            allColumnIds[workflow.Code.Trim()] = columnIds;
            var retainedColumns = new HashSet<Guid>();
            for (var columnIndex = 0; columnIndex < workflow.Columns.Count; columnIndex++)
            {
                var column = workflow.Columns[columnIndex];
                var oldKey = columnIndex < oldColumns.Count ? oldColumns[columnIndex].ClientId : column.ClientId;
                var columnId = matched.GetValueOrDefault(oldKey, Guid.NewGuid());
                columnIds[column.ClientId] = columnId;
                retainedColumns.Add(columnId);
                await ExecuteAsync(connection, transaction, """
                    INSERT INTO workflow_columns (id, workflow_id, name, color, sort_order)
                    VALUES (@id, @parent, @name, @color, @sort)
                    ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, color = EXCLUDED.color,
                                                   sort_order = EXCLUDED.sort_order
                    """, token, ("id", columnId), ("parent", id), ("name", column.Name.Trim()),
                    ("color", column.Color), ("sort", columnIndex));
                foreach (var action in column.CreationActions ?? [])
                    await ExecuteAsync(connection, transaction, """
                        INSERT INTO workflow_column_creation_actions (workflow_id, column_id, action_kind)
                        VALUES (@workflow_id, @column_id, @action_kind)
                        """, token,
                        ("workflow_id", id), ("column_id", columnId), ("action_kind", action));
            }
            await DeleteMissingAsync(connection, transaction, "workflow_columns", retainedColumns,
                token, "workflow_id", id);
            foreach (var transition in workflow.Transitions)
                await ExecuteAsync(connection, transaction, """
                    INSERT INTO workflow_transitions (from_column_id, to_column_id)
                    VALUES (@from, @to)
                    """, token, ("from", columnIds[transition.FromClientId]),
                    ("to", columnIds[transition.ToClientId]));

            var workflowCategories = workflow.Categories ?? [];
            var retainedWorkflowCategoryIds = new List<Guid>();
            await ExecuteAsync(connection, transaction, """
                UPDATE workflow_categories
                SET sort_order = sort_order + (
                    SELECT COALESCE(MAX(current_category.sort_order), 0) + @category_count + 1
                    FROM workflow_categories AS current_category
                    WHERE current_category.workflow_id = @workflow_id)
                WHERE workflow_id = @workflow_id
                """, token, ("workflow_id", id), ("category_count", workflowCategories.Count));
            for (var categoryIndex = 0; categoryIndex < workflowCategories.Count; categoryIndex++)
            {
                var selection = workflowCategories[categoryIndex];
                var categoryId = categoryIds[selection.CategoryClientId];
                retainedWorkflowCategoryIds.Add(categoryId);
                await ExecuteAsync(connection, transaction, """
                    INSERT INTO workflow_categories (workflow_id, category_id, sort_order, supplier_filter_field_code)
                    VALUES (@workflow_id, @category_id, @sort, @supplier_field)
                    ON CONFLICT (workflow_id, category_id)
                    DO UPDATE SET sort_order = EXCLUDED.sort_order,
                                  supplier_filter_field_code = EXCLUDED.supplier_filter_field_code
                    """, token, ("workflow_id", id), ("category_id", categoryId), ("sort", categoryIndex),
                    ("supplier_field", (object?)selection.SupplierFilterFieldCode ?? DBNull.Value));
                await ExecuteAsync(connection, transaction, """
                    DELETE FROM workflow_category_fields
                    WHERE workflow_id = @workflow_id AND category_id = @category_id
                    """, token, ("workflow_id", id), ("category_id", categoryId));
                for (var fieldIndex = 0; fieldIndex < selection.FieldCodes.Count; fieldIndex++)
                    await ExecuteAsync(connection, transaction, """
                        INSERT INTO workflow_category_fields
                            (workflow_id, category_id, field_code, sort_order)
                        VALUES (@workflow_id, @category_id, @code, @sort)
                        """, token, ("workflow_id", id), ("category_id", categoryId),
                        ("code", selection.FieldCodes[fieldIndex]), ("sort", fieldIndex));
            }
            var retainedCategoryJson = JsonSerializer.Serialize(retainedWorkflowCategoryIds, JsonOptions);
            await ExecuteAsync(connection, transaction, """
                DELETE FROM workflow_category_fields
                WHERE workflow_id = @workflow_id
                  AND category_id NOT IN (
                      SELECT CAST(value AS uuid)
                      FROM jsonb_array_elements_text(CAST(@retained AS jsonb)) AS retained_id(value))
                """, token, ("workflow_id", id), ("retained", retainedCategoryJson));
            await ExecuteAsync(connection, transaction, """
                DELETE FROM workflow_categories
                WHERE workflow_id = @workflow_id
                  AND category_id NOT IN (
                      SELECT CAST(value AS uuid)
                      FROM jsonb_array_elements_text(CAST(@retained AS jsonb)) AS retained_id(value))
                """, token, ("workflow_id", id), ("retained", retainedCategoryJson));
        }
        await DeleteMissingAsync(connection, transaction, "workflows", retained, token);
        await Orders.WorkflowOrderConfiguration.SaveAsync(
            connection, transaction, workflows, workflowIds, allColumnIds, token);
    }

    private static async Task SyncDependenciesAsync(
        DbConnection connection,
        DbTransaction transaction,
        IReadOnlyList<CategoryDependencyDraft> dependencies,
        IReadOnlyDictionary<string, Guid> categoryIds,
        CancellationToken token)
    {
        await ExecuteAsync(connection, transaction, """
            UPDATE catalog_category_dependencies SET sort_order = sort_order + (
                SELECT COALESCE(MAX(sort_order), 0) + @count + 1
                FROM catalog_category_dependencies)
            """, token, ("count", dependencies.Count));
        for (var index = 0; index < dependencies.Count; index++)
        {
            var dependency = dependencies[index];
            await ExecuteAsync(connection, transaction, """
                INSERT INTO catalog_category_dependencies
                    (id, client_id, source_category_id, target_category_id, target_field_code, sort_order)
                VALUES (@id, @client_id, @source, @target, @field, @sort)
                ON CONFLICT (client_id) DO UPDATE SET sort_order = EXCLUDED.sort_order
                """, token, ("id", Guid.NewGuid()),
                ("client_id", dependency.ClientId.Trim()),
                ("source", categoryIds[dependency.SourceCategoryClientId]),
                ("target", categoryIds[dependency.TargetCategoryClientId]),
                ("field", dependency.TargetFieldCode.Trim()), ("sort", index));
        }
    }

    private static async Task SyncEntityFieldsAsync(
        DbConnection connection,
        DbTransaction transaction,
        IReadOnlyList<EntityFieldDraft> fields,
        CancellationToken token)
    {
        await ExecuteAsync(connection, transaction, "DELETE FROM entity_field_definitions", token);
        var orders = new Dictionary<string, int>(StringComparer.Ordinal);
        foreach (var field in fields)
        {
            var order = orders.GetValueOrDefault(field.ContextCode);
            orders[field.ContextCode] = order + 1;
            await ExecuteAsync(connection, transaction, """
                INSERT INTO entity_field_definitions
                    (id, context_code, field_code, label, field_type, is_visible,
                     is_required, sort_order, dictionary_code)
                VALUES (@id, @context, @code, @label, @type, @visible,
                        @required, @sort, @dictionary_code)
                """, token, ("id", Guid.NewGuid()), ("context", field.ContextCode.Trim()),
                ("code", field.FieldCode.Trim()), ("label", field.Label.Trim()),
                ("type", field.FieldType.Trim()), ("visible", field.IsVisible),
                ("required", field.IsRequired), ("sort", order),
                ("dictionary_code", Db(field.DictionaryCode)));
        }
    }

    private static async Task<Dictionary<string, Guid>> ReadKeyedIdsAsync(
        DbConnection connection,
        DbTransaction transaction,
        string sql,
        CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = sql;
        var result = new Dictionary<string, Guid>(StringComparer.Ordinal);
        await using var reader = await command.ExecuteReaderAsync(token);
        while (await reader.ReadAsync(token)) result[reader.GetString(0)] = reader.GetGuid(1);
        return result;
    }

    private static async Task<List<ExistingRow>> ReadOrderedRowsAsync(
        DbConnection connection,
        DbTransaction? transaction,
        string sql,
        CancellationToken token,
        Guid? parent = null)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = sql;
        if (parent.HasValue) Add(command, "parent", parent.Value);
        var result = new List<ExistingRow>();
        await using var reader = await command.ExecuteReaderAsync(token);
        while (await reader.ReadAsync(token)) result.Add(new ExistingRow(reader.GetGuid(0), reader.GetString(1)));
        return result;
    }

    private static Dictionary<string, Guid> MatchByPreviousOrder(
        IEnumerable<string> previousKeys,
        IReadOnlyList<ExistingRow> rows)
    {
        var result = new Dictionary<string, Guid>(StringComparer.Ordinal);
        var keys = previousKeys.ToArray();
        for (var index = 0; index < keys.Length && index < rows.Count; index++)
            result[keys[index]] = rows[index].Id;
        return result;
    }

    private static async Task DeleteMissingAsync(
        DbConnection connection,
        DbTransaction transaction,
        string table,
        HashSet<Guid> retained,
        CancellationToken token,
        string? parentColumn = null,
        Guid? parentId = null)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = $"DELETE FROM {table} WHERE " +
            (parentColumn is null ? string.Empty : $"{parentColumn} = @parent AND ") +
            (retained.Count == 0 ? "true" : "id <> ALL(@retained)");
        if (parentColumn is not null) Add(command, "parent", parentId!.Value);
        if (retained.Count > 0) Add(command, "retained", retained.ToArray());
        await command.ExecuteNonQueryAsync(token);
    }

    private static void Add(DbCommand command, string name, object value)
    {
        var parameter = command.CreateParameter();
        parameter.ParameterName = name;
        parameter.Value = value;
        command.Parameters.Add(parameter);
    }

    private static CompanyProfileDraft ToDraft(CompanyProfile profile) => new(profile.OrganizationName);

    private sealed record ExistingRow(Guid Id, string Key);
    private sealed record CategoryDeletionPlan(
        Guid CategoryId,
        CategoryDeletionImpact Impact,
        IReadOnlyList<string> ObjectKeys);

    private async Task<CompanyProfile> ReadAsync(
        DbConnection connection,
        CancellationToken token,
        DbTransaction? transaction = null)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            SELECT name FROM public.organizations
            WHERE id = @organization_id AND deleted_at IS NULL
            """;
        Add(command, "organization_id", tenantContext.OrganizationId);
        await using var reader = await command.ExecuteReaderAsync(token);
        if (!await reader.ReadAsync(token))
            throw new IdentityException(404, "company_profile_not_found", "Данные компании не найдены.");
        return new CompanyProfile(reader.GetString(0));
    }

    private static object Db(string? value) =>
        string.IsNullOrWhiteSpace(value) ? DBNull.Value : value.Trim();

    private static async Task ExecuteAsync(
        DbConnection connection,
        DbTransaction transaction,
        string sql,
        CancellationToken token,
        params (string Name, object Value)[] parameters)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = sql;
        foreach (var (name, value) in parameters)
        {
            var parameter = command.CreateParameter();
            parameter.ParameterName = name;
            parameter.Value = value;
            command.Parameters.Add(parameter);
        }
        await command.ExecuteNonQueryAsync(token);
    }
}
