namespace SkladKomforta.Application.Identity;

/// <summary>Изолирует Application от конкретной JWT-библиотеки и ключа подписи.</summary>
public interface IAccessTokenIssuer
{
    /// <summary>Выпускает access-токен только из серверных идентификаторов.</summary>
    IssuedAccessToken Issue(Guid userId, Guid sessionId, Guid? organizationId, string displayName);
}

/// <summary>Подписанный access-токен и его точный срок действия.</summary>
public sealed record IssuedAccessToken(string Value, DateTimeOffset ExpiresAt);
