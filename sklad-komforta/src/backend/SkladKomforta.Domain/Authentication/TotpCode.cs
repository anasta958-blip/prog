using System.Buffers.Binary;
using System.Security.Cryptography;

namespace SkladKomforta.Domain.Authentication;

/// <summary>
/// Реализует стандарт RFC 6238 для шестизначных одноразовых кодов. Алгоритм не
/// хранит состояние и одинаково работает на нескольких экземплярах API.
/// </summary>
public static class TotpCode
{
    /// <summary>Продолжительность одного временного окна приложения-аутентификатора.</summary>
    public static readonly TimeSpan TimeStep = TimeSpan.FromSeconds(30);

    /// <summary>
    /// Проверяет код в текущем окне и по одному соседнему окну с каждой стороны,
    /// компенсируя небольшое расхождение часов без чрезмерного расширения атаки.
    /// </summary>
    /// <param name="secret">Случайный бинарный секрет пользователя.</param>
    /// <param name="code">Шестизначный код без пробелов.</param>
    /// <param name="utcNow">Текущее серверное время UTC.</param>
    /// <returns><see langword="true" />, если код корректен в допустимом окне.</returns>
    public static bool Verify(ReadOnlySpan<byte> secret, string? code, DateTimeOffset utcNow)
    {
        if (secret.IsEmpty || code is null || code.Length != 6 || !code.All(char.IsDigit))
        {
            return false;
        }

        var suppliedCode = int.Parse(code, System.Globalization.CultureInfo.InvariantCulture);
        var counter = utcNow.ToUnixTimeSeconds() / (long)TimeStep.TotalSeconds;

        for (var offset = -1; offset <= 1; offset++)
        {
            if (Generate(secret, counter + offset) == suppliedCode)
            {
                return true;
            }
        }

        return false;
    }

    /// <summary>Формирует числовой код для конкретного временного счётчика.</summary>
    private static int Generate(ReadOnlySpan<byte> secret, long counter)
    {
        Span<byte> counterBytes = stackalloc byte[sizeof(long)];
        BinaryPrimitives.WriteInt64BigEndian(counterBytes, counter);

        Span<byte> hash = stackalloc byte[20];
        // RFC 6238 and the common authenticator-app profile require HMAC-SHA1.
        // The algorithm protects a short-lived OTP and is not used for password hashing.
#pragma warning disable CA5350
        HMACSHA1.HashData(secret, counterBytes, hash);
#pragma warning restore CA5350
        var offset = hash[^1] & 0x0f;
        var binaryCode = BinaryPrimitives.ReadInt32BigEndian(hash[offset..(offset + 4)]) & 0x7fffffff;
        return binaryCode % 1_000_000;
    }
}
