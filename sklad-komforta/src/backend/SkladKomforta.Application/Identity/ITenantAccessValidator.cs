namespace SkladKomforta.Application.Identity;

/// <summary>
/// Проверяет, что подписанный JWT всё ещё относится к активной сессии,
/// пользователю, организации и членству. Имя tenant-схемы из клиента не принимает.
/// </summary>
public interface ITenantAccessValidator
{
    /// <summary>Возвращает true только для полностью действующего tenant-контекста.</summary>
    Task<bool> IsActiveAsync(
        Guid userId,
        Guid sessionId,
        Guid organizationId,
        CancellationToken cancellationToken);
}
