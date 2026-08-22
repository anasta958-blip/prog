using System.Data.Common;
using System.Text.Json;
using Npgsql;
using SkladKomforta.Application.Abstractions.Persistence;
using SkladKomforta.Application.Abstractions.Tenancy;
using SkladKomforta.Application.Company;
using SkladKomforta.Application.Identity;
using SkladKomforta.Application.Onboarding;

namespace SkladKomforta.Infrastructure.Company;

/// <summary>Работает с единственным профилем организации в текущей tenant-схеме.</summary>
internal sealed class PostgresCompanyService(
    IDatabaseConnectionFactory connectionFactory,
    ITenantContext tenantContext) : ICompanyService
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public async Task<OrganizationOnboardingDraft> GetConfigurationAsync(
        CancellationToken cancellationToken)
    {
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        var draft = await ReadDraftAsync(connection, cancellationToken);
        var profile = await ReadAsync(connection, cancellationToken);
        return draft with { Company = ToDraft(profile), CurrentStep = 8 };
    }

    public async Task<OrganizationOnboardingDraft> UpdateConfigurationAsync(
        Guid userId,
        OrganizationOnboardingDraft draft,
        CancellationToken cancellationToken)
    {
        var normalized = draft with { CurrentStep = 8 };
        OnboardingValidator.Validate(normalized, true);
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        var previous = await ReadDraftAsync(connection, cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        try
        {
            await UpdateProfileAsync(connection, transaction, userId, normalized.Company, cancellationToken);
            await SyncDictionariesAsync(connection, transaction, normalized.Dictionaries, cancellationToken);
            await ExecuteAsync(connection, transaction, "DELETE FROM catalog_category_dependencies", cancellationToken);
            var categoryIds = await SyncCatalogAsync(
                connection, transaction, previous.Categories, normalized.Categories, cancellationToken);
            await SyncWorkflowsAsync(
                connection, transaction, previous.Workflows, normalized.Workflows, categoryIds, cancellationToken);
            await SyncDependenciesAsync(
                connection, transaction, normalized.Dependencies ?? [], categoryIds, cancellationToken);
            await SyncEntityFieldsAsync(connection, transaction, normalized.Fields, cancellationToken);
            await SyncRolesAsync(connection, transaction, previous.Roles, normalized.Roles, cancellationToken);

            await ExecuteAsync(connection, transaction, """
                UPDATE onboarding_draft
                SET current_step = 8, payload = CAST(@payload AS jsonb),
                    updated_by = @user_id, updated_at = now()
                WHERE singleton
                """, cancellationToken,
                ("payload", JsonSerializer.Serialize(normalized, JsonOptions)), ("user_id", userId));
            await ExecuteAsync(connection, transaction, """
                INSERT INTO audit_log (actor_user_id, entity_type, entity_id, action, diff)
                VALUES (@user_id, 'organization_configuration', @organization_id,
                        'updated', CAST(@diff AS jsonb))
                """, cancellationToken,
                ("user_id", userId), ("organization_id", tenantContext.OrganizationId),
                ("diff", JsonSerializer.Serialize(new { before = previous, after = normalized }, JsonOptions)));
            await transaction.CommitAsync(cancellationToken);
            return normalized;
        }
        catch (PostgresException exception) when (exception.SqlState is "23503" or "23505")
        {
            throw new IdentityException(
                409,
                "organization_configuration_conflict",
                exception.SqlState == "23503"
                    ? "Нельзя удалить элемент настройки, который используется в рабочих данных."
                    : "В настройках организации обнаружены повторяющиеся значения.");
        }
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
        OnboardingValidator.ValidateCompany(new CompanyProfileDraft(
            profile.OrganizationName, profile.CompanyType, profile.LegalName,
            profile.Inn, profile.Kpp, profile.Ogrn, profile.Address,
            profile.Phone, profile.Email));

        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        var before = await ReadAsync(connection, cancellationToken, transaction);

        await ExecuteAsync(connection, transaction, """
            UPDATE organization_profile SET
                organization_name = @name, company_type = @type, legal_name = @legal,
                inn = @inn, kpp = @kpp, ogrn = @ogrn, address = @address,
                phone = @phone, email = @email, updated_by = @user_id, updated_at = now()
            WHERE singleton
            """, cancellationToken,
            ("name", profile.OrganizationName.Trim()), ("type", Db(profile.CompanyType)),
            ("legal", Db(profile.LegalName)), ("inn", Db(profile.Inn)),
            ("kpp", Db(profile.Kpp)), ("ogrn", Db(profile.Ogrn)),
            ("address", Db(profile.Address)), ("phone", Db(profile.Phone)),
            ("email", Db(profile.Email)), ("user_id", userId));

        await ExecuteAsync(connection, transaction,
            "UPDATE public.organizations SET name = @name, updated_at = now() WHERE id = @organization_id",
            cancellationToken,
            ("name", profile.OrganizationName.Trim()), ("organization_id", tenantContext.OrganizationId));

        await ExecuteAsync(connection, transaction, """
            INSERT INTO audit_log (actor_user_id, entity_type, entity_id, action, diff)
            VALUES (@user_id, 'organization_profile', @organization_id, 'updated', CAST(@diff AS jsonb))
            """, cancellationToken,
            ("user_id", userId), ("organization_id", tenantContext.OrganizationId),
            ("diff", JsonSerializer.Serialize(new { before, after = profile }, JsonOptions)));

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

    private async Task UpdateProfileAsync(
        DbConnection connection,
        DbTransaction transaction,
        Guid userId,
        CompanyProfileDraft profile,
        CancellationToken token)
    {
        await ExecuteAsync(connection, transaction, """
            UPDATE organization_profile SET
                organization_name = @name, company_type = @type, legal_name = @legal,
                inn = @inn, kpp = @kpp, ogrn = @ogrn, address = @address,
                phone = @phone, email = @email, updated_by = @user_id, updated_at = now()
            WHERE singleton
            """, token,
            ("name", profile.OrganizationName.Trim()), ("type", Db(profile.CompanyType)),
            ("legal", Db(profile.LegalName)), ("inn", Db(profile.Inn)), ("kpp", Db(profile.Kpp)),
            ("ogrn", Db(profile.Ogrn)), ("address", Db(profile.Address)),
            ("phone", Db(profile.Phone)), ("email", Db(profile.Email)), ("user_id", userId));
        await ExecuteAsync(connection, transaction,
            "UPDATE public.organizations SET name = @name, updated_at = now() WHERE id = @organization_id",
            token, ("name", profile.OrganizationName.Trim()), ("organization_id", tenantContext.OrganizationId));
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
        var existingRows = await ReadOrderedRowsAsync(connection, transaction,
            "SELECT id, name FROM catalog_categories ORDER BY sort_order", token);
        var existingByClientId = MatchByPreviousOrder(oldCategories.Select(item => item.ClientId), existingRows);
        var retained = new HashSet<Guid>();
        var result = new Dictionary<string, Guid>(StringComparer.Ordinal);

        for (var index = 0; index < categories.Count; index++)
        {
            var category = categories[index];
            var id = existingByClientId.GetValueOrDefault(category.ClientId, Guid.NewGuid());
            retained.Add(id);
            result[category.ClientId] = id;
            await ExecuteAsync(connection, transaction, """
                INSERT INTO catalog_categories (id, name, sort_order) VALUES (@id, @name, @sort)
                ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, sort_order = EXCLUDED.sort_order
                """, token, ("id", id), ("name", category.Name.Trim()), ("sort", index));
            var oldCategory = oldCategories.FirstOrDefault(item => item.ClientId == category.ClientId);
            await SyncSectionsAsync(connection, transaction, id, oldCategory?.Sections ?? [], category.Sections, token);
            await ExecuteAsync(connection, transaction,
                "DELETE FROM catalog_category_fields WHERE category_id = @id", token, ("id", id));
            for (var fieldIndex = 0; fieldIndex < category.Fields.Count; fieldIndex++)
            {
                var field = category.Fields[fieldIndex];
                await ExecuteAsync(connection, transaction, """
                    INSERT INTO catalog_category_fields
                        (category_id, field_code, is_visible, is_required, sort_order, dictionary_code)
                    VALUES (@category_id, @code, @visible, @required, @sort, @dictionary_code)
                    """, token, ("category_id", id), ("code", field.FieldCode.Trim()),
                    ("visible", field.IsVisible), ("required", field.IsRequired), ("sort", fieldIndex),
                    ("dictionary_code", Db(field.DictionaryCode)));
            }
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
        for (var index = 0; index < workflows.Count; index++)
        {
            var workflow = workflows[index];
            var id = existing.GetValueOrDefault(workflow.Code, Guid.NewGuid());
            retained.Add(id);
            await ExecuteAsync(connection, transaction, """
                INSERT INTO workflows (id, code, name, sort_order)
                VALUES (@id, @code, @name, @sort)
                ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name,
                                               sort_order = EXCLUDED.sort_order
                """, token, ("id", id), ("code", workflow.Code.Trim()),
                ("name", workflow.Name.Trim()), ("sort", index));

            await ExecuteAsync(connection, transaction,
                "DELETE FROM workflow_transitions WHERE from_column_id IN (SELECT id FROM workflow_columns WHERE workflow_id = @id)",
                token, ("id", id));
            await ExecuteAsync(connection, transaction,
                "DELETE FROM workflow_categories WHERE workflow_id = @id", token, ("id", id));
            var oldWorkflow = oldWorkflows.FirstOrDefault(item => item.Code == workflow.Code);
            var rows = await ReadOrderedRowsAsync(connection, transaction,
                "SELECT id, name FROM workflow_columns WHERE workflow_id = @parent ORDER BY sort_order", token, id);
            var oldColumns = oldWorkflow?.Columns ?? [];
            var matched = MatchByPreviousOrder(oldColumns.Select(item => item.ClientId), rows);
            var columnIds = new Dictionary<string, Guid>(StringComparer.Ordinal);
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
            for (var categoryIndex = 0; categoryIndex < workflowCategories.Count; categoryIndex++)
            {
                var selection = workflowCategories[categoryIndex];
                var categoryId = categoryIds[selection.CategoryClientId];
                await ExecuteAsync(connection, transaction, """
                    INSERT INTO workflow_categories (workflow_id, category_id, sort_order)
                    VALUES (@workflow_id, @category_id, @sort)
                    """, token, ("workflow_id", id), ("category_id", categoryId), ("sort", categoryIndex));
                for (var fieldIndex = 0; fieldIndex < selection.FieldCodes.Count; fieldIndex++)
                    await ExecuteAsync(connection, transaction, """
                        INSERT INTO workflow_category_fields
                            (workflow_id, category_id, field_code, sort_order)
                        VALUES (@workflow_id, @category_id, @code, @sort)
                        """, token, ("workflow_id", id), ("category_id", categoryId),
                        ("code", selection.FieldCodes[fieldIndex]), ("sort", fieldIndex));
            }
        }
        await DeleteMissingAsync(connection, transaction, "workflows", retained, token);
    }

    private static async Task SyncDependenciesAsync(
        DbConnection connection,
        DbTransaction transaction,
        IReadOnlyList<CategoryDependencyDraft> dependencies,
        IReadOnlyDictionary<string, Guid> categoryIds,
        CancellationToken token)
    {
        for (var index = 0; index < dependencies.Count; index++)
        {
            var dependency = dependencies[index];
            await ExecuteAsync(connection, transaction, """
                INSERT INTO catalog_category_dependencies
                    (id, source_category_id, target_category_id, target_field_code, sort_order)
                VALUES (@id, @source, @target, @field, @sort)
                """, token, ("id", Guid.NewGuid()),
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

    private static async Task SyncRolesAsync(
        DbConnection connection,
        DbTransaction transaction,
        IReadOnlyList<OnboardingRoleDraft> oldRoles,
        IReadOnlyList<OnboardingRoleDraft> roles,
        CancellationToken token)
    {
        var rows = await ReadOrderedRowsAsync(connection, transaction,
            "SELECT id, name FROM roles WHERE NOT is_system AND deleted_at IS NULL ORDER BY created_at, id", token);
        var matched = MatchByPreviousOrder(oldRoles.Select(item => item.Name), rows);
        var retained = new HashSet<Guid>();
        for (var index = 0; index < roles.Count; index++)
        {
            var role = roles[index];
            var oldName = index < oldRoles.Count ? oldRoles[index].Name : role.Name;
            var id = matched.GetValueOrDefault(oldName, Guid.NewGuid());
            retained.Add(id);
            await ExecuteAsync(connection, transaction, """
                INSERT INTO roles (id, name, is_system) VALUES (@id, @name, false)
                ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, updated_at = now()
                """, token, ("id", id), ("name", role.Name.Trim()));
            await ExecuteAsync(connection, transaction,
                "DELETE FROM role_permissions WHERE role_id = @id", token, ("id", id));
            foreach (var permission in role.PermissionCodes.Distinct(StringComparer.Ordinal))
                await ExecuteAsync(connection, transaction, """
                    INSERT INTO role_permissions (role_id, permission_id)
                    SELECT @id, id FROM permissions WHERE code = @code AND code <> 'system.full_access'
                    """, token, ("id", id), ("code", permission));
        }
        foreach (var row in rows.Where(item => !retained.Contains(item.Id)))
        {
            await using var check = connection.CreateCommand();
            check.Transaction = transaction;
            check.CommandText = "SELECT EXISTS (SELECT 1 FROM member_roles WHERE role_id = @id)";
            Add(check, "id", row.Id);
            if (await check.ExecuteScalarAsync(token) is true)
                throw new IdentityException(409, "organization_role_in_use",
                    $"Роль «{row.Key}» назначена сотрудникам и не может быть удалена.");
            await ExecuteAsync(connection, transaction, "DELETE FROM roles WHERE id = @id", token, ("id", row.Id));
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
        DbTransaction transaction,
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

    private static CompanyProfileDraft ToDraft(CompanyProfile profile) => new(
        profile.OrganizationName, profile.CompanyType, profile.LegalName, profile.Inn,
        profile.Kpp, profile.Ogrn, profile.Address, profile.Phone, profile.Email);

    private sealed record ExistingRow(Guid Id, string Key);

    private static async Task<CompanyProfile> ReadAsync(
        DbConnection connection,
        CancellationToken token,
        DbTransaction? transaction = null)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            SELECT organization_name, company_type, legal_name, inn, kpp, ogrn,
                   address, phone, email
            FROM organization_profile
            WHERE singleton
            """;
        await using var reader = await command.ExecuteReaderAsync(token);
        if (!await reader.ReadAsync(token))
            throw new IdentityException(404, "company_profile_not_found", "Данные компании не найдены.");
        return new CompanyProfile(
            reader.GetString(0), NullableString(reader, 1), NullableString(reader, 2),
            NullableString(reader, 3), NullableString(reader, 4), NullableString(reader, 5),
            NullableString(reader, 6), NullableString(reader, 7), NullableString(reader, 8));
    }

    private static string? NullableString(DbDataReader reader, int index) =>
        reader.IsDBNull(index) ? null : reader.GetString(index);

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
