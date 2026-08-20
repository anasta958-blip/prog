using SkladKomforta.Domain.Tenancy;

namespace SkladKomforta.Application.Abstractions.Tenancy;

/// <summary>
/// Хранит проверенную организацию в пределах одного HTTP-запроса или фоновой
/// операции. Контекст заполняется только после проверки JWT и членства.
/// </summary>
public interface ITenantContext
{
    /// <summary>UUID выбранной организации из схемы <c>public</c>.</summary>
    Guid OrganizationId { get; }

    /// <summary>Безопасное имя PostgreSQL-схемы выбранной организации.</summary>
    TenantSchemaName SchemaName { get; }

    /// <summary>Показывает, была ли организация успешно определена.</summary>
    bool IsResolved { get; }

    /// <summary>Устанавливает организацию и вычисляет её безопасное имя схемы.</summary>
    /// <param name="organizationId">Проверенный UUID организации.</param>
    void Resolve(Guid organizationId);

    /// <summary>Удаляет tenant-данные после завершения области выполнения.</summary>
    void Clear();
}
