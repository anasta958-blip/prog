using System.Data.Common;
using System.Text.Json;
using SkladKomforta.Application.Abstractions.Persistence;
using SkladKomforta.Application.Abstractions.Tenancy;
using SkladKomforta.Application.Identity;
using SkladKomforta.Application.Onboarding;

namespace SkladKomforta.Infrastructure.Onboarding;

/// <summary>
/// Хранит незавершённый onboarding одним JSON-агрегатом и только после финальной
/// проверки атомарно заполняет нормализованные рабочие таблицы tenant-схемы.
/// </summary>
internal sealed class PostgresOrganizationOnboardingService(
    IDatabaseConnectionFactory connectionFactory,
    ITenantContext tenantContext) : IOrganizationOnboardingService
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private static readonly string[] DefaultFieldContexts = ["quote", "preliminary_quote", "order"];

    /// <inheritdoc />
    public async Task<OrganizationOnboardingState> GetAsync(Guid userId, CancellationToken cancellationToken)
    {
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        await EnsureDirectorAsync(connection, userId, cancellationToken);
        return await ReadStateAsync(connection, cancellationToken);
    }

    /// <inheritdoc />
    public async Task<OrganizationOnboardingState> SaveAsync(
        Guid userId,
        OrganizationOnboardingDraft draft,
        CancellationToken cancellationToken)
    {
        OnboardingValidator.Validate(draft, false);
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        await EnsureDirectorAsync(connection, userId, cancellationToken);
        if (await IsCompletedAsync(connection, cancellationToken))
            throw new IdentityException(409, "onboarding_completed", "Первичная настройка уже завершена.");

        await using var command = connection.CreateCommand();
        command.CommandText = """
            INSERT INTO onboarding_draft (singleton, current_step, payload, updated_by, updated_at)
            VALUES (true, @current_step, CAST(@payload AS jsonb), @updated_by, now())
            ON CONFLICT (singleton) DO UPDATE
            SET current_step = EXCLUDED.current_step,
                payload = EXCLUDED.payload,
                updated_by = EXCLUDED.updated_by,
                updated_at = now()
            """;
        AddParameter(command, "current_step", draft.CurrentStep);
        AddParameter(command, "payload", JsonSerializer.Serialize(draft, JsonOptions));
        AddParameter(command, "updated_by", userId);
        await command.ExecuteNonQueryAsync(cancellationToken);
        return new OrganizationOnboardingState(draft, false, null);
    }

    /// <inheritdoc />
    public async Task<OrganizationOnboardingState> ActivateAsync(Guid userId, CancellationToken cancellationToken)
    {
        await using var connection = await connectionFactory.OpenTenantConnectionAsync(cancellationToken);
        await EnsureDirectorAsync(connection, userId, cancellationToken);
        var state = await ReadStateAsync(connection, cancellationToken);
        if (state.IsCompleted) return state;

        var draft = state.Draft with { CurrentStep = 8 };
        OnboardingValidator.Validate(draft, true);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        await ClearMaterializedConfigurationAsync(connection, transaction, cancellationToken);
        await SaveProfileAsync(connection, transaction, userId, draft.Company, cancellationToken);
        var categoryIds = await SaveCatalogAsync(connection, transaction, draft.Categories, cancellationToken);
        await SaveWorkflowsAsync(
            connection,
            transaction,
            draft.Workflows,
            categoryIds,
            cancellationToken);
        await SaveDependenciesAsync(
            connection,
            transaction,
            draft.Dependencies ?? [],
            categoryIds,
            cancellationToken);
        await SaveFieldsAsync(connection, transaction, draft.Fields, cancellationToken);
        await SaveRolesAsync(connection, transaction, draft.Roles, cancellationToken);
        await SaveDictionariesAsync(connection, transaction, draft.Dictionaries, cancellationToken);

        await ExecuteAsync(connection, transaction,
            "UPDATE public.organizations SET name = @name, onboarding_completed_at = now(), updated_at = now() WHERE id = @organization_id",
            cancellationToken,
            ("name", draft.Company.OrganizationName.Trim()),
            ("organization_id", tenantContext.OrganizationId));
        await ExecuteAsync(connection, transaction,
            "UPDATE onboarding_draft SET current_step = 8, payload = CAST(@payload AS jsonb), updated_by = @user_id, updated_at = now() WHERE singleton",
            cancellationToken,
            ("payload", JsonSerializer.Serialize(draft, JsonOptions)),
            ("user_id", userId));
        await ExecuteAsync(connection, transaction,
            "INSERT INTO audit_log (actor_user_id, entity_type, entity_id, action, metadata) VALUES (@user_id, 'organization', @organization_id, 'onboarding_completed', '{}'::jsonb)",
            cancellationToken,
            ("user_id", userId),
            ("organization_id", tenantContext.OrganizationId));

        await transaction.CommitAsync(cancellationToken);
        return new OrganizationOnboardingState(draft, true, DateTimeOffset.UtcNow);
    }

    /// <summary>Возвращает сохранённый draft либо безопасный стартовый набор.</summary>
    private async Task<OrganizationOnboardingState> ReadStateAsync(DbConnection connection, CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT organization.name, organization.onboarding_completed_at, draft.payload
            FROM public.organizations AS organization
            LEFT JOIN onboarding_draft AS draft ON draft.singleton
            WHERE organization.id = @organization_id AND organization.deleted_at IS NULL
            """;
        AddParameter(command, "organization_id", tenantContext.OrganizationId);
        await using var reader = await command.ExecuteReaderAsync(token);
        if (!await reader.ReadAsync(token))
            throw new IdentityException(404, "organization_not_found", "Организация не найдена.");

        var name = reader.GetString(0);
        DateTimeOffset? completedAt = reader.IsDBNull(1)
            ? null
            : new DateTimeOffset(reader.GetFieldValue<DateTime>(1));
        var draft = reader.IsDBNull(2)
            ? CreateDefaultDraft(name)
            : JsonSerializer.Deserialize<OrganizationOnboardingDraft>(reader.GetString(2), JsonOptions)
              ?? CreateDefaultDraft(name);
        draft = RemoveRetiredFields(draft);
        return new OrganizationOnboardingState(draft, completedAt.HasValue, completedAt);
    }

    /// <summary>Удаляет поля, исключённые из актуальной модели, из ранее сохранённых черновиков.</summary>
    private static OrganizationOnboardingDraft RemoveRetiredFields(OrganizationOnboardingDraft draft)
    {
        const string retailPrice = "retail_price";
        var categories = draft.Categories
            .Select(category => category with
            {
                Fields = category.Fields
                    .Where(field => field.FieldCode != retailPrice)
                    .ToArray(),
            })
            .ToArray();
        var workflows = draft.Workflows
            .Select(workflow => workflow with
            {
                Categories = (workflow.Categories ?? [])
                    .Select(category => category with
                    {
                        FieldCodes = category.FieldCodes
                            .Where(code => code != retailPrice)
                            .ToArray(),
                    })
                    .ToArray(),
            })
            .ToArray();

        return draft with
        {
            Categories = categories,
            Workflows = workflows,
            Fields = draft.Fields
                .Where(field => field.FieldCode != retailPrice)
                .ToArray(),
        };
    }

    /// <summary>Гарантирует, что onboarding меняет только директор организации.</summary>
    private async Task EnsureDirectorAsync(DbConnection connection, Guid userId, CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT EXISTS (
                SELECT 1 FROM public.organization_members
                WHERE organization_id = @organization_id AND user_id = @user_id
                  AND is_director AND is_active AND deleted_at IS NULL)
            """;
        AddParameter(command, "organization_id", tenantContext.OrganizationId);
        AddParameter(command, "user_id", userId);
        if (await command.ExecuteScalarAsync(token) is not true)
            throw new IdentityException(403, "onboarding_director_required", "Первичную настройку может выполнить только директор.");
    }

    private async Task<bool> IsCompletedAsync(DbConnection connection, CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.CommandText = "SELECT onboarding_completed_at IS NOT NULL FROM public.organizations WHERE id = @organization_id";
        AddParameter(command, "organization_id", tenantContext.OrganizationId);
        return await command.ExecuteScalarAsync(token) is true;
    }

    private static async Task ClearMaterializedConfigurationAsync(DbConnection connection, DbTransaction transaction, CancellationToken token)
    {
        foreach (var table in new[] { "dictionary_types", "entity_field_definitions", "catalog_categories", "workflows" })
            await ExecuteAsync(connection, transaction, $"DELETE FROM {table}", token);
        await ExecuteAsync(connection, transaction, "DELETE FROM roles WHERE NOT is_system", token);
    }

    private static Task SaveProfileAsync(DbConnection connection, DbTransaction transaction, Guid userId, CompanyProfileDraft profile, CancellationToken token) =>
        ExecuteAsync(connection, transaction, """
            INSERT INTO organization_profile
                (singleton, organization_name, company_type, legal_name, inn, kpp, ogrn, address, phone, email, updated_by, updated_at)
            VALUES (true, @name, @type, @legal, @inn, @kpp, @ogrn, @address, @phone, @email, @user_id, now())
            ON CONFLICT (singleton) DO UPDATE SET
                organization_name = EXCLUDED.organization_name, company_type = EXCLUDED.company_type,
                legal_name = EXCLUDED.legal_name, inn = EXCLUDED.inn, kpp = EXCLUDED.kpp,
                ogrn = EXCLUDED.ogrn, address = EXCLUDED.address, phone = EXCLUDED.phone,
                email = EXCLUDED.email, updated_by = EXCLUDED.updated_by, updated_at = now()
            """, token,
            ("name", profile.OrganizationName.Trim()), ("type", Db(profile.CompanyType)),
            ("legal", Db(profile.LegalName)), ("inn", Db(profile.Inn)), ("kpp", Db(profile.Kpp)),
            ("ogrn", Db(profile.Ogrn)), ("address", Db(profile.Address)), ("phone", Db(profile.Phone)),
            ("email", Db(profile.Email)), ("user_id", userId));

    private static async Task SaveWorkflowsAsync(
        DbConnection connection,
        DbTransaction transaction,
        IReadOnlyList<WorkflowDraft> workflows,
        IReadOnlyDictionary<string, Guid> categoryIds,
        CancellationToken token)
    {
        for (var workflowIndex = 0; workflowIndex < workflows.Count; workflowIndex++)
        {
            var workflow = workflows[workflowIndex];
            var workflowId = Guid.NewGuid();
            await ExecuteAsync(connection, transaction,
                "INSERT INTO workflows (id, code, name, sort_order) VALUES (@id, @code, @name, @sort)", token,
                ("id", workflowId), ("code", workflow.Code.Trim()), ("name", workflow.Name.Trim()), ("sort", workflowIndex));
            var columns = new Dictionary<string, Guid>(StringComparer.Ordinal);
            for (var columnIndex = 0; columnIndex < workflow.Columns.Count; columnIndex++)
            {
                var column = workflow.Columns[columnIndex];
                var columnId = Guid.NewGuid();
                columns.Add(column.ClientId, columnId);
                await ExecuteAsync(connection, transaction,
                    "INSERT INTO workflow_columns (id, workflow_id, name, color, sort_order) VALUES (@id, @workflow_id, @name, @color, @sort)", token,
                    ("id", columnId), ("workflow_id", workflowId), ("name", column.Name.Trim()), ("color", column.Color), ("sort", columnIndex));
            }
            foreach (var transition in workflow.Transitions)
                await ExecuteAsync(connection, transaction,
                    "INSERT INTO workflow_transitions (from_column_id, to_column_id) VALUES (@from, @to)", token,
                    ("from", columns[transition.FromClientId]), ("to", columns[transition.ToClientId]));

            var workflowCategories = workflow.Categories ?? [];
            for (var categoryIndex = 0; categoryIndex < workflowCategories.Count; categoryIndex++)
            {
                var category = workflowCategories[categoryIndex];
                var categoryId = categoryIds[category.CategoryClientId];
                await ExecuteAsync(connection, transaction, """
                    INSERT INTO workflow_categories (workflow_id, category_id, sort_order)
                    VALUES (@workflow_id, @category_id, @sort)
                    """, token,
                    ("workflow_id", workflowId), ("category_id", categoryId), ("sort", categoryIndex));

                for (var fieldIndex = 0; fieldIndex < category.FieldCodes.Count; fieldIndex++)
                    await ExecuteAsync(connection, transaction, """
                        INSERT INTO workflow_category_fields
                            (workflow_id, category_id, field_code, sort_order)
                        VALUES (@workflow_id, @category_id, @field_code, @sort)
                        """, token,
                        ("workflow_id", workflowId), ("category_id", categoryId),
                        ("field_code", category.FieldCodes[fieldIndex]), ("sort", fieldIndex));
            }
        }
    }

    private static async Task<IReadOnlyDictionary<string, Guid>> SaveCatalogAsync(
        DbConnection connection,
        DbTransaction transaction,
        IReadOnlyList<CatalogCategoryDraft> categories,
        CancellationToken token)
    {
        var categoryIds = new Dictionary<string, Guid>(StringComparer.Ordinal);
        for (var categoryIndex = 0; categoryIndex < categories.Count; categoryIndex++)
        {
            var category = categories[categoryIndex];
            var categoryId = Guid.NewGuid();
            categoryIds.Add(category.ClientId, categoryId);
            await ExecuteAsync(connection, transaction,
                "INSERT INTO catalog_categories (id, name, sort_order) VALUES (@id, @name, @sort)", token,
                ("id", categoryId), ("name", category.Name.Trim()), ("sort", categoryIndex));
            for (var fieldIndex = 0; fieldIndex < category.Fields.Count; fieldIndex++)
            {
                var field = category.Fields[fieldIndex];
                await ExecuteAsync(connection, transaction, """
                    INSERT INTO catalog_category_fields
                        (category_id, field_code, is_visible, is_required, sort_order)
                    VALUES (@category_id, @field_code, @visible, @required, @sort)
                    """, token,
                    ("category_id", categoryId), ("field_code", field.FieldCode.Trim()),
                    ("visible", field.IsVisible), ("required", field.IsRequired), ("sort", fieldIndex));
            }
            for (var sectionIndex = 0; sectionIndex < category.Sections.Count; sectionIndex++)
            {
                var section = category.Sections[sectionIndex];
                var sectionId = Guid.NewGuid();
                await ExecuteAsync(connection, transaction,
                    "INSERT INTO catalog_sections (id, category_id, name, sort_order) VALUES (@id, @category_id, @name, @sort)", token,
                    ("id", sectionId), ("category_id", categoryId), ("name", section.Name.Trim()), ("sort", sectionIndex));
                for (var groupIndex = 0; groupIndex < section.Groups.Count; groupIndex++)
                    await ExecuteAsync(connection, transaction,
                        "INSERT INTO catalog_groups (id, section_id, name, sort_order) VALUES (@id, @section_id, @name, @sort)", token,
                        ("id", Guid.NewGuid()), ("section_id", sectionId), ("name", section.Groups[groupIndex].Name.Trim()), ("sort", groupIndex));
            }
        }
        return categoryIds;
    }

    /// <summary>Материализует проверенные зависимости после создания категорий.</summary>
    private static async Task SaveDependenciesAsync(
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
                VALUES (@id, @source_id, @target_id, @field_code, @sort)
                """, token,
                ("id", Guid.NewGuid()),
                ("source_id", categoryIds[dependency.SourceCategoryClientId]),
                ("target_id", categoryIds[dependency.TargetCategoryClientId]),
                ("field_code", dependency.TargetFieldCode.Trim()),
                ("sort", index));
        }
    }

    private static async Task SaveFieldsAsync(DbConnection connection, DbTransaction transaction, IReadOnlyList<EntityFieldDraft> fields, CancellationToken token)
    {
        var contextOrder = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        foreach (var field in fields)
        {
            var order = contextOrder.GetValueOrDefault(field.ContextCode);
            contextOrder[field.ContextCode] = order + 1;
            await ExecuteAsync(connection, transaction, """
                INSERT INTO entity_field_definitions
                    (id, context_code, field_code, label, field_type, is_visible, is_required, sort_order)
                VALUES (@id, @context, @code, @label, @type, @visible, @required, @sort)
                """, token,
                ("id", Guid.NewGuid()), ("context", field.ContextCode.Trim()), ("code", field.FieldCode.Trim()),
                ("label", field.Label.Trim()), ("type", field.FieldType.Trim()), ("visible", field.IsVisible),
                ("required", field.IsRequired), ("sort", order));
        }
    }

    private static async Task SaveRolesAsync(DbConnection connection, DbTransaction transaction, IReadOnlyList<OnboardingRoleDraft> roles, CancellationToken token)
    {
        foreach (var role in roles)
        {
            var roleId = Guid.NewGuid();
            await ExecuteAsync(connection, transaction,
                "INSERT INTO roles (id, name, is_system) VALUES (@id, @name, false)", token,
                ("id", roleId), ("name", role.Name.Trim()));
            foreach (var permissionCode in role.PermissionCodes.Distinct(StringComparer.Ordinal))
            {
                await using var command = connection.CreateCommand();
                command.Transaction = transaction;
                command.CommandText = "INSERT INTO role_permissions (role_id, permission_id) SELECT @role_id, id FROM permissions WHERE code = @code AND code <> 'system.full_access'";
                AddParameter(command, "role_id", roleId);
                AddParameter(command, "code", permissionCode);
                if (await command.ExecuteNonQueryAsync(token) != 1)
                    throw new IdentityException(400, "permission_invalid", $"Неизвестное право роли: {permissionCode}.");
            }
        }
    }

    private static async Task SaveDictionariesAsync(DbConnection connection, DbTransaction transaction, IReadOnlyList<DictionaryDraft> dictionaries, CancellationToken token)
    {
        for (var typeIndex = 0; typeIndex < dictionaries.Count; typeIndex++)
        {
            var dictionary = dictionaries[typeIndex];
            var typeId = Guid.NewGuid();
            await ExecuteAsync(connection, transaction,
                "INSERT INTO dictionary_types (id, code, name, sort_order) VALUES (@id, @code, @name, @sort)", token,
                ("id", typeId), ("code", dictionary.Code.Trim()), ("name", dictionary.Name.Trim()), ("sort", typeIndex));
            for (var itemIndex = 0; itemIndex < dictionary.Items.Count; itemIndex++)
                await ExecuteAsync(connection, transaction,
                    "INSERT INTO dictionary_items (id, dictionary_type_id, value, sort_order) VALUES (@id, @type_id, @value, @sort)", token,
                    ("id", Guid.NewGuid()), ("type_id", typeId), ("value", dictionary.Items[itemIndex].Value.Trim()), ("sort", itemIndex));
        }
    }

    private static OrganizationOnboardingDraft CreateDefaultDraft(string name)
    {
        static WorkflowDraft Workflow(
            string code,
            string title,
            IReadOnlyList<CatalogCategoryDraft> categories,
            params string[] columns)
        {
            var items = columns.Select((column, index) => new WorkflowColumnDraft($"{code}-{index + 1}", column, "#4D8DFF")).ToArray();
            var transitions = items.Zip(items.Skip(1), (from, to) => new WorkflowTransitionDraft(from.ClientId, to.ClientId)).ToArray();
            var workflowCategories = categories
                .Select(category => new WorkflowCategoryDraft(
                    category.ClientId,
                    category.Fields.Where(field => field.IsVisible).Select(field => field.FieldCode).ToArray()))
                .ToArray();
            return new WorkflowDraft(code, title, items, transitions, workflowCategories);
        }

        var fields = DefaultFieldContexts
            .SelectMany(context => OnboardingFieldRegistry.DefaultCatalogFields()
                .Where(field => field.FieldCode != "linked_services")
                .Select(field => OnboardingFieldRegistry.CreateContextField(
                    context,
                    field.FieldCode,
                    field.IsVisible,
                    field.IsRequired)))
            .ToArray();

        static CatalogCategoryDraft Category(string clientId, string title, bool supportsRelations) =>
            new(
                clientId,
                title,
                [],
                OnboardingFieldRegistry.DefaultCatalogFields()
                    .Where(field => supportsRelations || field.FieldCode != "linked_services")
                    .ToArray());

        var categories = new[]
        {
            Category("equipment", "Оборудование", true),
            Category("materials", "Материалы", true),
            Category("works", "Работы", false),
        };

        return new OrganizationOnboardingDraft(
            1,
            new CompanyProfileDraft(name, null, null, null, null, null, null, null, null),
            [
                Workflow("quote", "Коммерческие предложения", categories, "Составить КП", "Согласовать", "Договор"),
                Workflow("preliminary_quote", "Предварительные КП", categories, "Составить ПКП", "ПКП согласовано"),
                Workflow("order", "Комплектация объекта", categories, "Составление", "Монтаж", "Завершено"),
            ],
            categories,
            fields,
            [],
            [new DictionaryDraft("units", "Единицы измерения", [new("шт"), new("м"), new("м²")])],
            [
                new CategoryDependencyDraft("works-equipment", "works", "equipment", "linked_services"),
                new CategoryDependencyDraft("works-materials", "works", "materials", "linked_services"),
            ]);
    }

    private static object Db(string? value) => string.IsNullOrWhiteSpace(value) ? DBNull.Value : value.Trim();

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
        foreach (var parameter in parameters) AddParameter(command, parameter.Name, parameter.Value);
        await command.ExecuteNonQueryAsync(token);
    }

    private static void AddParameter(DbCommand command, string name, object value)
    {
        var parameter = command.CreateParameter();
        parameter.ParameterName = name;
        parameter.Value = value;
        command.Parameters.Add(parameter);
    }
}
