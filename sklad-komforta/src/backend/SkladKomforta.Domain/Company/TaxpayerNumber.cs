namespace SkladKomforta.Domain.Company;

/// <summary>
/// Проверка ИНН по алгоритму ФНС. Используется до обращения к внешнему реестру,
/// чтобы опечатка не расходовала лимит запросов и не попадала в кэш.
/// </summary>
public static class TaxpayerNumber
{
    private static readonly int[] LegalEntityWeights = [2, 4, 10, 3, 5, 9, 4, 6, 8];
    private static readonly int[] PersonFirstWeights = [7, 2, 4, 10, 3, 5, 9, 4, 6, 8];
    private static readonly int[] PersonSecondWeights = [3, 7, 2, 4, 10, 3, 5, 9, 4, 6, 8];

    /// <summary>
    /// Проверяет 10-значный ИНН организации или 12-значный ИНН физического лица/ИП.
    /// </summary>
    /// <param name="value">Строка только из цифр без пробелов.</param>
    /// <returns><see langword="true" />, если длина и контрольные цифры корректны.</returns>
    public static bool IsValid(string? value)
    {
        if (value is null || !value.All(char.IsAsciiDigit))
        {
            return false;
        }

        return value.Length switch
        {
            10 => CheckDigit(value, LegalEntityWeights) == value[9] - '0',
            12 => CheckDigit(value, PersonFirstWeights) == value[10] - '0' &&
                  CheckDigit(value, PersonSecondWeights) == value[11] - '0',
            _ => false,
        };
    }

    /// <summary>Возвращает <see langword="true" /> для 12-значного ИНН физического лица или ИП.</summary>
    public static bool IsIndividual(string value) => value.Length == 12;

    /// <summary>Контрольная цифра: взвешенная сумма первых разрядов по модулю 11, затем по модулю 10.</summary>
    private static int CheckDigit(string value, int[] weights)
    {
        var sum = 0;
        for (var index = 0; index < weights.Length; index++)
        {
            sum += (value[index] - '0') * weights[index];
        }

        return sum % 11 % 10;
    }
}
