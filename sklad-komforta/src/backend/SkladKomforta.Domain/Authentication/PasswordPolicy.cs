namespace SkladKomforta.Domain.Authentication;

/// <summary>
/// Централизует минимальные требования к паролю. Клиенты могут повторять эти
/// проверки для удобства, но сервер всегда остаётся окончательным источником
/// правил и не принимает пароль, не соответствующий политике.
/// </summary>
public static class PasswordPolicy
{
    /// <summary>Минимальная длина нового пароля.</summary>
    public const int MinimumLength = 12;

    /// <summary>
    /// Проверяет длину и наличие букв разных регистров, цифры и специального
    /// символа. Метод возвращает стабильный код ошибки для API и UI.
    /// </summary>
    /// <param name="password">Новый пароль в исходном виде.</param>
    /// <returns>Результат проверки без сохранения или логирования пароля.</returns>
    public static PasswordValidationResult Validate(string? password)
    {
        if (string.IsNullOrWhiteSpace(password) || password.Length < MinimumLength)
        {
            return PasswordValidationResult.Invalid(
                "password_too_short",
                $"Пароль должен содержать не менее {MinimumLength} символов.");
        }

        if (!password.Any(char.IsUpper) ||
            !password.Any(char.IsLower) ||
            !password.Any(char.IsDigit) ||
            !password.Any(character => !char.IsLetterOrDigit(character)))
        {
            return PasswordValidationResult.Invalid(
                "password_too_weak",
                "Пароль должен содержать строчную и заглавную буквы, цифру и специальный символ.");
        }

        return PasswordValidationResult.Valid();
    }
}

/// <summary>Неизменяемый результат серверной проверки нового пароля.</summary>
public sealed record PasswordValidationResult(bool IsValid, string? ErrorCode, string? ErrorMessage)
{
    /// <summary>Создаёт успешный результат.</summary>
    public static PasswordValidationResult Valid() => new(true, null, null);

    /// <summary>Создаёт неуспешный результат с кодом и русским сообщением.</summary>
    public static PasswordValidationResult Invalid(string code, string message) =>
        new(false, code, message);
}
