using SkladKomforta.Application.Abstractions.Tenancy;
using SkladKomforta.Domain.Tenancy;

namespace SkladKomforta.Infrastructure.Tenancy;

/// <summary>
/// Scoped-реализация tenant-контекста. Экземпляр не разделяется между запросами,
/// поэтому выбранная организация одного пользователя не протекает в другой запрос.
/// </summary>
internal sealed class TenantContext : ITenantContext
{
    private Guid? _organizationId;
    private TenantSchemaName? _schemaName;

    public Guid OrganizationId => _organizationId ??
        throw new InvalidOperationException("Контекст организации не определён.");

    public TenantSchemaName SchemaName => _schemaName ??
        throw new InvalidOperationException("Контекст организации не определён.");

    public bool IsResolved => _organizationId.HasValue;

    /// <inheritdoc />
    public void Resolve(Guid organizationId)
    {
        if (organizationId == Guid.Empty)
        {
            throw new ArgumentException("Идентификатор организации не может быть пустым.", nameof(organizationId));
        }

        _organizationId = organizationId;
        _schemaName = TenantSchemaName.Create(organizationId);
    }

    /// <inheritdoc />
    public void Clear()
    {
        _organizationId = null;
        _schemaName = null;
    }
}
