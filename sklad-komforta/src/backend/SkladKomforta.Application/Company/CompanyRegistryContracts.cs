namespace SkladKomforta.Application.Company;

/// <summary>
/// Реквизиты организации или ИП из государственного реестра. Используются только
/// для предзаполнения формы: пользователь проверяет их и сохраняет обычным запросом.
/// </summary>
/// <param name="CompanyType"><c>ooo</c> для юридического лица, <c>ip</c> для индивидуального предпринимателя.</param>
/// <param name="Name">Сокращённое наименование, например <c>ООО "РОМАШКА"</c> или <c>ИП Иванов И. И.</c>.</param>
/// <param name="LegalName">Полное наименование юридического лица либо ФИО предпринимателя.</param>
/// <param name="Inn">ИНН из реестра.</param>
/// <param name="Kpp">КПП; у ИП отсутствует.</param>
/// <param name="Ogrn">ОГРН юридического лица или ОГРНИП.</param>
/// <param name="Address">
/// Адрес юридического лица; <see langword="null" />, если выписку получить не удалось.
/// Место жительства ИП в публичной выписке не публикуется, а «адрес регистрирующего
/// органа» — это адрес инспекции ФНС, поэтому у ИП адрес всегда пустой.
/// </param>
/// <param name="Email">Адрес электронной почты из выписки, если он внесён в реестр.</param>
/// <param name="DirectorName">ФИО руководителя; для ИП совпадает с ФИО предпринимателя.</param>
/// <param name="DirectorTitle">Должность руководителя, например «Генеральный директор».</param>
public sealed record CompanyRegistryRecord(
    string CompanyType,
    string Name,
    string LegalName,
    string Inn,
    string? Kpp,
    string? Ogrn,
    string? Address,
    string? Email,
    string? DirectorName,
    string? DirectorTitle);

/// <summary>Поиск реквизитов по ИНН во внешнем реестре.</summary>
public interface ICompanyRegistryLookup
{
    /// <summary>
    /// Находит организацию или ИП по ИНН.
    /// </summary>
    /// <param name="inn">ИНН из 10 или 12 цифр; допускаются пробелы, они удаляются.</param>
    /// <param name="cancellationToken">Отмена HTTP-запроса клиента.</param>
    /// <returns>Найденные реквизиты.</returns>
    /// <exception cref="Identity.IdentityException">
    /// 400 <c>inn_invalid</c> — неверный ИНН; 404 <c>registry_not_found</c> — запись не найдена;
    /// 503 <c>registry_unavailable</c> — реестр недоступен или требует капчу.
    /// </exception>
    Task<CompanyRegistryRecord> FindByInnAsync(string inn, CancellationToken cancellationToken);
}
