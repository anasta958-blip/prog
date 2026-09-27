using System.Security.Cryptography;
using System.Text;
using SkladKomforta.Infrastructure.Identity;

namespace SkladKomforta.Api.IntegrationTests;

public sealed class IdentitySecurityTests
{
    private static readonly byte[] MasterKey = Enumerable.Range(1, 32).Select(value => (byte)value).ToArray();

    [Fact]
    public void DerivedKeysAreStableAndSeparatedByPurpose()
    {
        var quoteKey = IdentitySecurity.DeriveKey(MasterKey, "quote-client-access");

        Assert.Equal(32, quoteKey.Length);
        Assert.Equal(quoteKey, IdentitySecurity.DeriveKey(MasterKey, "quote-client-access"));
        Assert.NotEqual(quoteKey, IdentitySecurity.DeriveKey(MasterKey, "other-purpose"));
        Assert.NotEqual(quoteKey, MasterKey);
    }

    [Fact]
    public void SecretEncryptedWithDerivedKeyCannotBeReadWithMasterKey()
    {
        var quoteKey = IdentitySecurity.DeriveKey(MasterKey, "quote-client-access");
        var protectedPassword = IdentitySecurity.ProtectSecret(Encoding.UTF8.GetBytes("Pa55word"), quoteKey);

        Assert.Equal("Pa55word", Encoding.UTF8.GetString(IdentitySecurity.UnprotectSecret(protectedPassword, quoteKey)));
        Assert.ThrowsAny<CryptographicException>(() => IdentitySecurity.UnprotectSecret(protectedPassword, MasterKey));
    }
}
