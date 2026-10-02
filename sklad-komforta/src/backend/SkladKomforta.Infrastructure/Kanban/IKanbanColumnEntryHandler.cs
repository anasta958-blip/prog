using System.Data.Common;

namespace SkladKomforta.Infrastructure.Kanban;

/// <summary>
/// Реакция на попадание карточки в другой столбец. Выполняется в транзакции
/// перемещения: ошибка обработчика отменяет и само перемещение.
/// </summary>
internal interface IKanbanColumnEntryHandler
{
    /// <summary>Вызывается после смены столбца карточки, до фиксации транзакции.</summary>
    Task OnCardEnteredColumnAsync(
        DbConnection connection,
        DbTransaction transaction,
        Guid actorUserId,
        Guid boardId,
        Guid cardId,
        Guid columnId,
        CancellationToken cancellationToken);
}
