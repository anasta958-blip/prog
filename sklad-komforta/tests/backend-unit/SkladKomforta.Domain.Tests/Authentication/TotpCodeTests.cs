using SkladKomforta.Domain.Authentication;

namespace SkladKomforta.Domain.Tests.Authentication;

/// <summary>Проверяет реализацию TOTP по опубликованным контрольным векторам RFC 6238.</summary>
public sealed class TotpCodeTests
{
    private static readonly byte[] Secret = "12345678901234567890"u8.ToArray();

    /// <summary>Шестизначная форма контрольного кода должна приниматься в точном окне.</summary>
    [Fact]
    public void VerifyAcceptsRfcCounterValue()
    {
        var timestamp = DateTimeOffset.FromUnixTimeSeconds(59);

        Assert.True(TotpCode.Verify(Secret, "287082", timestamp));
    }

    /// <summary>Соседнее окно допускается только для небольшого рассогласования часов.</summary>
    [Fact]
    public void VerifyAcceptsOneAdjacentWindowAndRejectsDistantWindow()
    {
        var timestamp = DateTimeOffset.FromUnixTimeSeconds(59);

        Assert.True(TotpCode.Verify(Secret, "287082", timestamp.AddSeconds(30)));
        Assert.False(TotpCode.Verify(Secret, "287082", timestamp.AddSeconds(90)));
    }

    /// <summary>Некорректный формат не должен приводить к исключению или частичному сравнению.</summary>
    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("12345")]
    [InlineData("ABCDEF")]
    public void VerifyRejectsMalformedCode(string? code)
    {
        Assert.False(TotpCode.Verify(Secret, code, DateTimeOffset.UtcNow));
    }
}
