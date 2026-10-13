namespace SkladKomforta.Application.Onboarding;

/// <summary>Реквизиты и контакты организации, вводимые директором на первом шаге.</summary>
public sealed record CompanyProfileDraft(
    string OrganizationName,
    string? CompanyType,
    string? LegalName,
    string? Inn,
    string? Kpp,
    string? Ogrn,
    string? Address,
    string? Phone,
    string? Email,
    SkladKomforta.Application.Company.SaveLegalEntityRequest? LegalEntity = null);

/// <summary>
/// Цель переноса из столбца-триггера: канбан (по коду) и его столбец (по
/// клиентскому идентификатору). КП/ПКП переносится в комплектацию и обратно.
/// </summary>
public sealed record WorkflowTransferDraft(string WorkflowCode, string ColumnClientId);

/// <summary>Один столбец настраиваемого канбана.</summary>
/// <param name="TransferTo">Если задан, столбец — триггер переноса в другой канбан.</param>
/// <param name="ReorderFrom">
/// Только для канбана комплектации: позиции, добавленные, когда карточка стоит в
/// этом столбце или правее, считаются дозаказом.
/// </param>
public sealed record WorkflowColumnDraft(
    string ClientId,
    string Name,
    string Color,
    IReadOnlyList<string>? CreationActions = null,
    WorkflowTransferDraft? TransferTo = null,
    bool ReorderFrom = false);

/// <summary>Разрешённый переход между двумя клиентскими идентификаторами столбцов.</summary>
public sealed record WorkflowTransitionDraft(string FromClientId, string ToClientId);

/// <summary>Категория канбана и упорядоченные поля, отображаемые в её карточке.</summary>
public sealed record WorkflowCategoryDraft(
    string CategoryClientId,
    IReadOnlyList<string> FieldCodes);

/// <summary>Справочники канбана комплектации.</summary>
/// <param name="ObjectTypes">Типы объекта (квартира, дом и т. п.).</param>
/// <param name="ShipmentStatuses">Значения поля «Статус отгрузки» позиций.</param>
public sealed record WorkflowOrderSettingsDraft(
    IReadOnlyList<string>? ObjectTypes = null,
    IReadOnlyList<string>? ShipmentStatuses = null);

/// <summary>Канбан вместе с упорядоченными столбцами и разрешёнными переходами.</summary>
public sealed record WorkflowDraft(
    string Code,
    string Name,
    IReadOnlyList<WorkflowColumnDraft> Columns,
    IReadOnlyList<WorkflowTransitionDraft> Transitions,
    IReadOnlyList<WorkflowCategoryDraft>? Categories = null,
    string? Specialization = null,
    WorkflowOrderSettingsDraft? OrderSettings = null);

/// <summary>Группа товаров внутри раздела каталога.</summary>
public sealed record CatalogGroupDraft(string Name);

/// <summary>Выбранное системное поле карточки товаров конкретной категории.</summary>
public sealed record CatalogFieldDraft(
    string FieldCode,
    bool IsVisible,
    bool IsRequired,
    string? DictionaryCode = null,
    string? Label = null,
    string? FieldType = null);

/// <summary>Раздел каталога и его группы.</summary>
public sealed record CatalogSectionDraft(string Name, IReadOnlyList<CatalogGroupDraft> Groups);

/// <summary>Категория каталога с устойчивым ключом, структурой и набором поддерживаемых полей.</summary>
public sealed record CatalogCategoryDraft(
    string ClientId,
    string Name,
    IReadOnlyList<CatalogSectionDraft> Sections,
    IReadOnlyList<CatalogFieldDraft> Fields);

/// <summary>
/// Разрешает связывать позицию исходной категории с позицией целевой категории.
/// Связь записывается в выбранное relation-поле целевой карточки.
/// </summary>
public sealed record CategoryDependencyDraft(
    string ClientId,
    string SourceCategoryClientId,
    string TargetCategoryClientId,
    string TargetFieldCode);

/// <summary>Видимость, обязательность и порядок одного поля в заданном контексте.</summary>
public sealed record EntityFieldDraft(
    string ContextCode,
    string FieldCode,
    string Label,
    string FieldType,
    bool IsVisible,
    bool IsRequired,
    string? DictionaryCode = null);

/// <summary>Настраиваемая роль без системного полного доступа директора.</summary>
public sealed record OnboardingRoleDraft(string Name, IReadOnlyList<string> PermissionCodes);

/// <summary>Один элемент справочника.</summary>
public sealed record DictionaryItemDraft(string Value);

/// <summary>Справочник организации, например единицы измерения или поставщики.</summary>
public sealed record DictionaryDraft(string Code, string Name, IReadOnlyList<DictionaryItemDraft> Items);

/// <summary>Один элемент безопасной формулы: поле, число, операция или скобка.</summary>
public sealed record FormulaTokenDraft(
    string TokenType,
    string? FieldCode = null,
    decimal? ConstantValue = null,
    string? Operator = null);

/// <summary>Формула и точность её итогового округления.</summary>
public sealed record FormulaDraft(
    IReadOnlyList<FormulaTokenDraft> Tokens,
    int DecimalPlaces = 2);

/// <summary>Одно проверяемое условие событийного правила.</summary>
public sealed record RuleConditionDraft(
    string FieldCode,
    string Operator,
    string? ComparisonValue = null);

/// <summary>Одно действие, выполняемое после успешной проверки условий.</summary>
public sealed record RuleActionDraft(
    string ActionType,
    string? TargetFieldCode = null,
    string? SourceFieldCode = null,
    string? ConstantValue = null,
    bool? BooleanValue = null,
    string? DependencyClientId = null,
    string? AggregationOperation = null,
    string? AggregationTarget = null,
    bool MultiplyByQuantity = false,
    string? QuantityFieldCode = null,
    string? Message = null,
    FormulaDraft? Formula = null);

/// <summary>Событийное правило одной категории с условиями и действиями.</summary>
public sealed record CalculationRuleDraft(
    string ClientId,
    string Name,
    string CategoryClientId,
    string EventType,
    bool IsEnabled,
    string? EventFieldCode,
    IReadOnlyList<RuleConditionDraft> Conditions,
    IReadOnlyList<RuleActionDraft> Actions);

/// <summary>
/// Один именованный расчёт категории с неизменяемым конвейером:
/// базовая цена, ручная цена, наценка, скидка, количество, округление и итог.
/// </summary>
public sealed record MoneyPipelineDraft(
    string CategoryClientId,
    string BasePriceFieldCode,
    string? ManualPriceFieldCode,
    string? MarkupFieldCode,
    string? DiscountFieldCode,
    string? QuantityFieldCode,
    string ResultFieldCode,
    int DecimalPlaces,
    bool IncludeResultInTotals,
    string? ClientId = null);

/// <summary>
/// Полный серверный черновик десятишаговой настройки. Клиент всегда отправляет
/// агрегат целиком, поэтому сервер может валидировать согласованность связей.
/// </summary>
public sealed record OrganizationOnboardingDraft(
    int CurrentStep,
    CompanyProfileDraft Company,
    IReadOnlyList<WorkflowDraft> Workflows,
    IReadOnlyList<CatalogCategoryDraft> Categories,
    IReadOnlyList<EntityFieldDraft> Fields,
    IReadOnlyList<OnboardingRoleDraft> Roles,
    IReadOnlyList<DictionaryDraft> Dictionaries,
    IReadOnlyList<CategoryDependencyDraft>? Dependencies = null,
    IReadOnlyList<CalculationRuleDraft>? Rules = null,
    IReadOnlyList<MoneyPipelineDraft>? MoneyPipelines = null);

/// <summary>Состояние onboarding и признак окончательной активации организации.</summary>
public sealed record OrganizationOnboardingState(
    OrganizationOnboardingDraft Draft,
    bool IsCompleted,
    DateTimeOffset? CompletedAt);

/// <summary>Сохраняет черновик и атомарно активирует проверенную конфигурацию.</summary>
public interface IOrganizationOnboardingService
{
    /// <summary>Проверяет завершение настройки без раскрытия её содержимого сотруднику.</summary>
    Task<bool> GetCompletionAsync(CancellationToken cancellationToken);

    /// <summary>Возвращает последний черновик текущей организации.</summary>
    Task<OrganizationOnboardingState> GetAsync(Guid userId, CancellationToken cancellationToken);

    /// <summary>Полностью заменяет серверный черновик после проверки структуры.</summary>
    Task<OrganizationOnboardingState> SaveAsync(Guid userId, OrganizationOnboardingDraft draft, CancellationToken cancellationToken);

    /// <summary>Проверяет все шаги и переносит черновик в рабочие tenant-таблицы.</summary>
    Task<OrganizationOnboardingState> ActivateAsync(Guid userId, CancellationToken cancellationToken);
}
