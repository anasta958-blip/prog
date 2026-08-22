namespace SkladKomforta.Application.Company;

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

/// <summary>Читает и обновляет единственный профиль текущей tenant-организации.</summary>
public interface ICompanyService
{
    Task<CompanyProfile> GetAsync(CancellationToken cancellationToken);
    Task<CompanyProfile> UpdateAsync(Guid userId, CompanyProfile profile, CancellationToken cancellationToken);
}
