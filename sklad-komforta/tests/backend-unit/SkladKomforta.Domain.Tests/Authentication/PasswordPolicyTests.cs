using SkladKomforta.Domain.Authentication;

namespace SkladKomforta.Domain.Tests.Authentication;

/// <summary>Фиксирует обязательные серверные правила новых паролей.</summary>
public sealed class PasswordPolicyTests
{
    /// <summary>Проверяет отклонение короткого пароля до любых других признаков.</summary>
    [Fact]
    public void ValidateRejectsShortPassword()
    {
        var result = PasswordPolicy.Validate("Aa1!");

        Assert.False(result.IsValid);
        Assert.Equal("password_too_short", result.ErrorCode);
    }

    /// <summary>Проверяет обязательность всех четырёх классов символов.</summary>
    [Theory]
    [InlineData("onlylowercase1!")]
    [InlineData("ONLYUPPERCASE1!")]
    [InlineData("NoDigitsHere!!")]
    [InlineData("NoSpecialChar1")]
    public void ValidateRejectsPasswordWithoutRequiredCharacterClass(string password)
    {
        var result = PasswordPolicy.Validate(password);

        Assert.False(result.IsValid);
        Assert.Equal("password_too_weak", result.ErrorCode);
    }

    /// <summary>Проверяет успешный пример, который UI может использовать как ориентир.</summary>
    [Fact]
    public void ValidateAcceptsStrongPassword()
    {
        var result = PasswordPolicy.Validate("ReliablePass1!");

        Assert.True(result.IsValid);
        Assert.Null(result.ErrorCode);
    }
}
