namespace SkladKomforta.Application.Company;

using System.Text.Json;
using SkladKomforta.Application.Onboarding;

/// <summary>Рабочие реквизиты организации после завершения первичной настройки.</summary>
public sealed record CompanyProfile(
    string OrganizationName,
    string? CompanyType,
    string? LegalName,
    string? Inn,
    string? Kpp,
    string? Ogrn,
    string? Address,
    string? Phone,
    string? Email);

/// <summary>Общий срок действия организации, применяемый ко всем её аккаунтам.</summary>
public sealed record OrganizationLifecycle(DateTimeOffset ActiveUntil, bool IsFrozen);

/// <summary>Одна пользовательская операция из журнала текущей организации.</summary>
public sealed record CompanyAuditEntry(
    long Id,
    Guid? ActorUserId,
    string? ActorName,
    string EntityType,
    Guid? EntityId,
    string Action,
    DateTimeOffset CreatedAt,
    JsonElement Diff);

/// <summary>Юридическое лицо, которое можно выбрать исполнителем в будущих документах.</summary>
public sealed record LegalEntity(
    Guid Id,
    string Name,
    string CompanyType,
    string? LegalName,
    string? Inn,
    string? Kpp,
    string? Ogrn,
    string? Address,
    string? Phone,
    string? Email,
    string? Website,
    string? DirectorName,
    string? SignatoryName,
    string? SignatoryTitle,
    string? BankName,
    string? BankBik,
    string? BankAccount,
    string? CorrAccount,
    string? IntroDefault,
    string? FooterDefault,
    bool IsDefault);

/// <summary>Данные создания или изменения юридического лица.</summary>
public sealed record SaveLegalEntityRequest(
    string Name,
    string CompanyType,
    string? LegalName,
    string? Inn,
    string? Kpp,
    string? Ogrn,
    string? Address,
    string? Phone,
    string? Email,
    string? Website,
    string? DirectorName,
    string? SignatoryName,
    string? SignatoryTitle,
    string? BankName,
    string? BankBik,
    string? BankAccount,
    string? CorrAccount,
    string? IntroDefault,
    string? FooterDefault,
    bool IsDefault);

/// <summary>Клиент текущей организации.</summary>
public sealed record CompanyClient(
    Guid Id,
    string Name,
    string CompanyType,
    string? CompanyName,
    string? LegalName,
    string? Inn,
    string? Kpp,
    string? Ogrn,
    string? ContactName,
    string? Phone,
    string? Email,
    string? Address,
    string? ObjectType,
    string? ObjectAddress,
    string? RecipientName,
    string? Salutation,
    string? ProposalTitle,
    string? IntroText,
    string? BankName,
    string? BankBik,
    string? BankAccount,
    string? CorrAccount,
    string? PassportSeries,
    string? PassportNumber,
    string? PassportIssuedBy,
    string? Note);

/// <summary>Данные создания или изменения клиента.</summary>
public sealed record SaveCompanyClientRequest(
    string Name,
    string CompanyType,
    string? CompanyName,
    string? LegalName,
    string? Inn,
    string? Kpp,
    string? Ogrn,
    string? ContactName,
    string? Phone,
    string? Email,
    string? Address,
    string? ObjectType,
    string? ObjectAddress,
    string? RecipientName,
    string? Salutation,
    string? ProposalTitle,
    string? IntroText,
    string? BankName,
    string? BankBik,
    string? BankAccount,
    string? CorrAccount,
    string? PassportSeries,
    string? PassportNumber,
    string? PassportIssuedBy,
    string? Note);

/// <summary>Сотрудник и его место в иерархии организации.</summary>
public sealed record EmployeeSummary(
    Guid MembershipId,
    Guid UserId,
    string Login,
    string DisplayName,
    Guid RoleId,
    string RoleName,
    Guid? SupervisorMembershipId,
    bool IsDirector,
    bool IsActive,
    string? Email,
    string? Phone,
    string? Telegram,
    Guid? CreatedBy,
    DateTimeOffset CreatedAt,
    DateTimeOffset ActiveUntil);

/// <summary>Создаёт обязательную учётную запись и профиль сотрудника.</summary>
public sealed record CreateEmployeeRequest(
    string Login,
    string DisplayName,
    string TemporaryPassword,
    Guid RoleId,
    Guid? SupervisorMembershipId,
    string? Email,
    string? Phone,
    string? Telegram);

/// <summary>Изменяет профиль, роль, руководителя и доступность сотрудника.</summary>
public sealed record UpdateEmployeeRequest(
    string DisplayName,
    Guid RoleId,
    Guid? SupervisorMembershipId,
    bool IsActive,
    string? Email,
    string? Phone,
    string? Telegram);

/// <summary>Читает и обновляет единственный профиль текущей tenant-организации.</summary>
public interface ICompanyService
{
    Task<CompanyProfile> GetAsync(CancellationToken cancellationToken);
    Task<CompanyProfile> UpdateAsync(Guid userId, CompanyProfile profile, CancellationToken cancellationToken);
    Task<OrganizationOnboardingDraft> GetConfigurationAsync(CancellationToken cancellationToken);
    Task<OrganizationOnboardingDraft> UpdateConfigurationAsync(
        Guid userId,
        OrganizationOnboardingDraft draft,
        CancellationToken cancellationToken);
}

/// <summary>Рабочие операции пространства «Компания», не смешанные с onboarding.</summary>
public interface ICompanyWorkspaceService
{
    Task<OrganizationLifecycle> GetLifecycleAsync(CancellationToken cancellationToken);
    Task<IReadOnlyList<CompanyAuditEntry>> GetAuditAsync(int limit, CancellationToken cancellationToken);
    Task<IReadOnlyList<LegalEntity>> GetLegalEntitiesAsync(CancellationToken cancellationToken);
    Task<LegalEntity> CreateLegalEntityAsync(Guid actorUserId, SaveLegalEntityRequest request, CancellationToken cancellationToken);
    Task<LegalEntity> UpdateLegalEntityAsync(Guid actorUserId, Guid id, SaveLegalEntityRequest request, CancellationToken cancellationToken);
    Task DeleteLegalEntityAsync(Guid actorUserId, Guid id, CancellationToken cancellationToken);
    Task<IReadOnlyList<CompanyClient>> GetClientsAsync(CancellationToken cancellationToken);
    Task<CompanyClient> CreateClientAsync(Guid actorUserId, SaveCompanyClientRequest request, CancellationToken cancellationToken);
    Task<CompanyClient> UpdateClientAsync(Guid actorUserId, Guid id, SaveCompanyClientRequest request, CancellationToken cancellationToken);
    Task DeleteClientAsync(Guid actorUserId, Guid id, CancellationToken cancellationToken);
    Task<IReadOnlyList<EmployeeSummary>> GetEmployeesAsync(CancellationToken cancellationToken);
    Task<EmployeeSummary> CreateEmployeeAsync(Guid actorUserId, CreateEmployeeRequest request, CancellationToken cancellationToken);
    Task<EmployeeSummary> UpdateEmployeeAsync(Guid actorUserId, Guid membershipId, UpdateEmployeeRequest request, CancellationToken cancellationToken);
    Task DeleteEmployeeAsync(Guid actorUserId, Guid membershipId, CancellationToken cancellationToken);
}
