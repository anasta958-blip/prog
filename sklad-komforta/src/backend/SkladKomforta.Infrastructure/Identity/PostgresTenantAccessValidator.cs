using Npgsql;
using SkladKomforta.Application.Identity;

namespace SkladKomforta.Infrastructure.Identity;

/// <summary>
/// Проверяет tenant-доступ по public-таблицам на каждом запросе. Намеренно не
/// кэширует результат: отзыв сессии и отключение сотрудника действуют сразу.
/// </summary>
internal sealed class PostgresTenantAccessValidator(NpgsqlDataSource dataSource) : ITenantAccessValidator
{
    /// <inheritdoc />
    public async Task<bool> IsActiveAsync(
        Guid userId,
        Guid sessionId,
        Guid organizationId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT EXISTS (
                SELECT 1
                FROM public.users AS u
                JOIN public.organization_members AS member
                  ON member.user_id = u.id
                 AND member.organization_id = @organization_id
                JOIN public.organizations AS organization
                  ON organization.id = member.organization_id
                JOIN public.refresh_sessions AS session
                  ON session.id = @session_id
                 AND session.user_id = u.id
                 AND session.organization_id = organization.id
                WHERE u.id = @user_id
                  AND u.is_active
                  AND u.deleted_at IS NULL
                  AND member.is_active
                  AND member.deleted_at IS NULL
                  AND organization.is_active
                  AND organization.deleted_at IS NULL
                  AND session.revoked_at IS NULL
                  AND session.expires_at > now()
            )
            """;
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("user_id", userId);
        command.Parameters.AddWithValue("session_id", sessionId);
        command.Parameters.AddWithValue("organization_id", organizationId);
        return await command.ExecuteScalarAsync(cancellationToken) is true;
    }
}
