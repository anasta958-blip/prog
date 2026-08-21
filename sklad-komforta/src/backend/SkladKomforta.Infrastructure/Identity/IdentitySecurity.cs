using System.Security.Cryptography;
using System.Text;
using Microsoft.AspNetCore.WebUtilities;

namespace SkladKomforta.Infrastructure.Identity;

/// <summary>Содержит криптографические преобразования, не являющиеся бизнес-правилами.</summary>
internal static class IdentitySecurity
{
    private const string Base32Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

    /// <summary>Создаёт непрогнозируемый URL-safe токен заданной криптографической длины.</summary>
    public static string CreateToken(int byteCount) =>
        WebEncoders.Base64UrlEncode(RandomNumberGenerator.GetBytes(byteCount));

    /// <summary>Хеширует токен SHA-256 перед сохранением или поиском в PostgreSQL.</summary>
    public static byte[] HashToken(string token) => SHA256.HashData(Encoding.UTF8.GetBytes(token));

    /// <summary>Шифрует TOTP-секрет AES-GCM с уникальным nonce и встроенным authentication tag.</summary>
    public static byte[] ProtectSecret(ReadOnlySpan<byte> secret, ReadOnlySpan<byte> key)
    {
        var nonce = RandomNumberGenerator.GetBytes(12);
        var ciphertext = new byte[secret.Length];
        var tag = new byte[16];
        using var aes = new AesGcm(key, tag.Length);
        aes.Encrypt(nonce, secret, ciphertext, tag);
        return [.. nonce, .. tag, .. ciphertext];
    }

    /// <summary>Проверяет authentication tag и расшифровывает ранее сохранённый TOTP-секрет.</summary>
    public static byte[] UnprotectSecret(ReadOnlySpan<byte> protectedSecret, ReadOnlySpan<byte> key)
    {
        if (protectedSecret.Length <= 28)
        {
            throw new CryptographicException("Повреждён зашифрованный TOTP-секрет.");
        }

        var plaintext = new byte[protectedSecret.Length - 28];
        using var aes = new AesGcm(key, 16);
        aes.Decrypt(protectedSecret[..12], protectedSecret.Slice(28), protectedSecret.Slice(12, 16), plaintext);
        return plaintext;
    }

    /// <summary>Кодирует бинарный TOTP-секрет в формат Base32 приложений-аутентификаторов.</summary>
    public static string ToBase32(ReadOnlySpan<byte> bytes)
    {
        var output = new StringBuilder((bytes.Length * 8 + 4) / 5);
        var buffer = 0;
        var bitsLeft = 0;
        foreach (var value in bytes)
        {
            buffer = (buffer << 8) | value;
            bitsLeft += 8;
            while (bitsLeft >= 5)
            {
                output.Append(Base32Alphabet[(buffer >> (bitsLeft - 5)) & 31]);
                bitsLeft -= 5;
            }
        }

        if (bitsLeft > 0)
        {
            output.Append(Base32Alphabet[(buffer << (5 - bitsLeft)) & 31]);
        }

        return output.ToString();
    }
}
