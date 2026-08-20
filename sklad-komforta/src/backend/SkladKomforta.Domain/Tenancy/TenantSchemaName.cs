using System.Text.RegularExpressions;

namespace SkladKomforta.Domain.Tenancy;

/// <summary>
/// Представляет доверенное имя отдельной PostgreSQL-схемы организации.
/// Тип не позволяет создать экземпляр с произвольным SQL-идентификатором:
/// штатное имя выводится из UUID организации, а восстановленное имя проходит
/// строгую проверку формата перед использованием в команде <c>search_path</c>.
/// </summary>
public sealed partial record TenantSchemaName
{
    private const string Prefix = "tenant_";

    private TenantSchemaName(string value) => Value = value;

    /// <summary>Возвращает проверенный PostgreSQL-идентификатор tenant-схемы.</summary>
    public string Value { get; }

    /// <summary>
    /// Детерминированно создаёт имя схемы из UUID организации. Удаление дефисов
    /// оставляет только шестнадцатеричные символы и исключает SQL-инъекцию.
    /// </summary>
    /// <param name="organizationId">Непустой UUID организации из схемы <c>public</c>.</param>
    /// <returns>Имя вида <c>tenant_&lt;32 hex-символа&gt;</c>.</returns>
    public static TenantSchemaName Create(Guid organizationId) =>
        new($"{Prefix}{organizationId:N}");

    /// <summary>
    /// Восстанавливает объект из сохранённой строки только после полной проверки
    /// допустимого префикса, длины и набора символов.
    /// </summary>
    /// <param name="value">Имя схемы, ранее сформированное приложением.</param>
    /// <returns>Проверенное доменное значение.</returns>
    /// <exception cref="ArgumentException">Имя не соответствует безопасному формату.</exception>
    public static TenantSchemaName Parse(string value)
    {
        if (!SchemaNamePattern().IsMatch(value))
        {
            throw new ArgumentException("Недопустимое имя tenant-схемы.", nameof(value));
        }

        return new TenantSchemaName(value);
    }

    /// <summary>Возвращает проверенное имя схемы без дополнительного форматирования.</summary>
    public override string ToString() => Value;

    [GeneratedRegex("^tenant_[a-f0-9]{32}$", RegexOptions.CultureInvariant)]
    private static partial Regex SchemaNamePattern();
}
