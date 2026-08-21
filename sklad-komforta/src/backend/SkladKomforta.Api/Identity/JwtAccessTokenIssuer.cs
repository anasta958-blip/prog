using System.Security.Claims;
using System.Text;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;
using SkladKomforta.Application.Identity;
using SkladKomforta.Domain.Authentication;
using SkladKomforta.Infrastructure.Configuration;

namespace SkladKomforta.Api.Identity;

/// <summary>Выпускает короткоживущий JWT без хранения серверной сессии в памяти API.</summary>
internal sealed class JwtAccessTokenIssuer(IOptions<JwtOptions> options) : IAccessTokenIssuer
{
    private readonly JwtOptions _options = options.Value;

    /// <inheritdoc />
    public IssuedAccessToken Issue(Guid userId, Guid sessionId, Guid? organizationId, string displayName)
    {
        var now = DateTimeOffset.UtcNow;
        var expiresAt = now + TokenLifetimePolicy.AccessTokenLifetime;
        var claims = new List<Claim>
        {
            new(JwtRegisteredClaimNames.Sub, userId.ToString()),
            new("session_id", sessionId.ToString()),
            new("display_name", displayName),
        };
        if (organizationId.HasValue)
        {
            claims.Add(new Claim("organization_id", organizationId.Value.ToString()));
        }

        var descriptor = new SecurityTokenDescriptor
        {
            Issuer = _options.Issuer,
            Audience = _options.Audience,
            Subject = new ClaimsIdentity(claims),
            IssuedAt = now.UtcDateTime,
            NotBefore = now.UtcDateTime,
            Expires = expiresAt.UtcDateTime,
            SigningCredentials = new SigningCredentials(
                new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_options.SigningKey)),
                SecurityAlgorithms.HmacSha256),
        };
        return new IssuedAccessToken(new JsonWebTokenHandler().CreateToken(descriptor), expiresAt);
    }
}
