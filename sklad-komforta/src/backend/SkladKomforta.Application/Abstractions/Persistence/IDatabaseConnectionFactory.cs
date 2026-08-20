using System.Data.Common;

namespace SkladKomforta.Application.Abstractions.Persistence;

/// <summary>
/// Открывает PostgreSQL-соединения с явно выбранной областью данных. Разделение
/// методов не позволяет tenant-use case случайно выполнить запрос в <c>public</c>
/// или обойти установленный для организации <c>search_path</c>.
/// </summary>
public interface IDatabaseConnectionFactory
{
    /// <summary>Открывает соединение для глобальных таблиц авторизации и организаций.</summary>
    /// <param name="cancellationToken">Отмена ожидания соединения.</param>
    /// <returns>Открытое соединение, которым владеет вызывающий код.</returns>
    ValueTask<DbConnection> OpenPublicConnectionAsync(CancellationToken cancellationToken = default);

    /// <summary>Открывает соединение и устанавливает tenant-схему текущей организации.</summary>
    /// <param name="cancellationToken">Отмена открытия и установки <c>search_path</c>.</param>
    /// <returns>Открытое соединение, которым владеет вызывающий код.</returns>
    ValueTask<DbConnection> OpenTenantConnectionAsync(CancellationToken cancellationToken = default);
}
