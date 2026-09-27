namespace SkladKomforta.Application.Quotes;

/// <summary>Параметры новой парольной ссылки на одно сохранённое КП или ПКП.</summary>
public sealed record CreateQuoteClientAccessRequest(int LifetimeDays = 7);

/// <summary>
/// Секреты новой ссылки. В базе они хранятся хешами для проверки и зашифрованными
/// копиями для повторного показа сотруднику; в открытом виде не сохраняются.
/// </summary>
public sealed record CreatedQuoteClientAccess(
    string AccessToken,
    string Password,
    DateTimeOffset ExpiresAt);

/// <summary>
/// Состояние действующей клиентской ссылки. Для сотрудника с правом
/// <c>quotes.manage</c> включает токен и пароль, чтобы их можно было скопировать повторно.
/// </summary>
/// <param name="AccessToken">
/// Открытый токен ссылки; <see langword="null" />, если ссылки нет или она создана
/// до появления зашифрованного хранения и её нужно пересоздать.
/// </param>
/// <param name="Password">Пароль клиента; <see langword="null" /> в тех же случаях.</param>
public sealed record QuoteClientAccessStatus(
    bool IsActive,
    DateTimeOffset? CreatedAt,
    DateTimeOffset? ExpiresAt,
    DateTimeOffset? LastAccessedAt,
    string? AccessToken = null,
    string? Password = null);

/// <summary>Парольный вход клиента, который не создаёт пользователя организации.</summary>
public sealed record QuoteClientLoginRequest(string AccessToken, string Password);

/// <summary>Отдельная короткая сессия клиента и доступное ему предложение.</summary>
public sealed record QuoteClientLoginResult(
    string SessionToken,
    DateTimeOffset ExpiresAt,
    QuoteClientView Quote);

/// <summary>Выбор клиента согласно режиму конкретного предложения.</summary>
public sealed record SubmitQuoteClientSelectionRequest(
    Guid? ProposalTypeId,
    IReadOnlyList<QuoteClientVariantSelection> Variants);

/// <summary>Один выбранный вариант внутри указанного типа предложения.</summary>
public sealed record QuoteClientVariantSelection(Guid ProposalTypeId, Guid VariantId);

/// <summary>Безопасное клиентское представление без закупки, маржи и служебных полей.</summary>
public sealed record QuoteClientView(
    Guid Id,
    string QuoteKind,
    string Title,
    string ExecutorName,
    string SelectionMode,
    string? AdditionalInformation,
    Guid? SelectedProposalTypeId,
    IReadOnlyList<QuoteClientProposalType> ProposalTypes,
    DateTimeOffset? SelectionSubmittedAt,
    DateTimeOffset UpdatedAt);

/// <summary>Тип предложения и доступные клиенту варианты.</summary>
public sealed record QuoteClientProposalType(
    Guid Id,
    string Name,
    Guid? SelectedVariantId,
    IReadOnlyList<QuoteClientVariant> Variants);

/// <summary>Вариант с итогами для клиента и публичным составом.</summary>
public sealed record QuoteClientVariant(
    Guid Id,
    string Name,
    string? Subtitle,
    decimal? VatRate,
    decimal Subtotal,
    decimal VatAmount,
    decimal Total,
    IReadOnlyList<QuoteClientCategory> Categories);

public sealed record QuoteClientCategory(
    Guid Id,
    string Name,
    IReadOnlyList<QuoteClientSection> Sections);

public sealed record QuoteClientSection(
    Guid Id,
    string Name,
    IReadOnlyList<QuoteClientPosition> Positions);

public sealed record QuoteClientPosition(
    Guid Id,
    string Name,
    string Marking,
    string Unit,
    decimal Quantity,
    decimal UnitPrice,
    decimal LineTotal);

/// <summary>Изолированный use case парольного доступа внешнего клиента.</summary>
public interface IQuoteClientAccessService
{
    Task<QuoteClientAccessStatus> GetStatusAsync(
        Guid actorUserId,
        Guid boardId,
        Guid cardId,
        CancellationToken cancellationToken);

    Task<CreatedQuoteClientAccess> CreateAsync(
        Guid actorUserId,
        Guid boardId,
        Guid cardId,
        CreateQuoteClientAccessRequest request,
        CancellationToken cancellationToken);

    Task RevokeAsync(
        Guid actorUserId,
        Guid boardId,
        Guid cardId,
        CancellationToken cancellationToken);

    Task<QuoteClientLoginResult> LoginAsync(
        QuoteClientLoginRequest request,
        string? ipAddress,
        CancellationToken cancellationToken);

    Task<QuoteClientView> GetAsync(string sessionToken, CancellationToken cancellationToken);

    Task<QuoteClientView> SubmitSelectionAsync(
        string sessionToken,
        SubmitQuoteClientSelectionRequest request,
        CancellationToken cancellationToken);
}
