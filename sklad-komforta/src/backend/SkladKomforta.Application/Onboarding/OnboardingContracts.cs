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
    string? Email);

/// <summary>Один столбец настраиваемого канбана.</summary>
public sealed record WorkflowColumnDraft(string ClientId, string Name, string Color);

/// <summary>Разрешённый переход между двумя клиентскими идентификаторами столбцов.</summary>
public sealed record WorkflowTransitionDraft(string FromClientId, string ToClientId);

/// <summary>Категория канбана и упорядоченные поля, отображаемые в её карточке.</summary>
public sealed record WorkflowCategoryDraft(
    string CategoryClientId,
    IReadOnlyList<string> FieldCodes);

/// <summary>Канбан вместе с упорядоченными столбцами и разрешёнными переходами.</summary>
public sealed record WorkflowDraft(
    string Code,
    string Name,
    IReadOnlyList<WorkflowColumnDraft> Columns,
    IReadOnlyList<WorkflowTransitionDraft> Transitions,
    IReadOnlyList<WorkflowCategoryDraft>? Categories = null);

/// <summary>Группа товаров внутри раздела каталога.</summary>
public sealed record CatalogGroupDraft(string Name);

/// <summary>Выбранное системное поле карточки товаров конкретной категории.</summary>
public sealed record CatalogFieldDraft(
    string FieldCode,
    bool IsVisible,
    bool IsRequired,
    string? DictionaryCode = null);

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

/// <summary>
/// Полный серверный черновик восьмишаговой настройки. Клиент всегда отправляет
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
    IReadOnlyList<CategoryDependencyDraft>? Dependencies = null);

/// <summary>Состояние onboarding и признак окончательной активации организации.</summary>
public sealed record OrganizationOnboardingState(
    OrganizationOnboardingDraft Draft,
    bool IsCompleted,
    DateTimeOffset? CompletedAt);

/// <summary>Сохраняет черновик и атомарно активирует проверенную конфигурацию.</summary>
public interface IOrganizationOnboardingService
{
    /// <summary>Возвращает последний черновик текущей организации.</summary>
    Task<OrganizationOnboardingState> GetAsync(Guid userId, CancellationToken cancellationToken);

    /// <summary>Полностью заменяет серверный черновик после проверки структуры.</summary>
    Task<OrganizationOnboardingState> SaveAsync(Guid userId, OrganizationOnboardingDraft draft, CancellationToken cancellationToken);

    /// <summary>Проверяет все шаги и переносит черновик в рабочие tenant-таблицы.</summary>
    Task<OrganizationOnboardingState> ActivateAsync(Guid userId, CancellationToken cancellationToken);
}
