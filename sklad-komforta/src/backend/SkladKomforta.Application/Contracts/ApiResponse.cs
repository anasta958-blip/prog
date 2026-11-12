namespace SkladKomforta.Application.Contracts;

/// <summary>Единая JSON-обёртка успешных и ошибочных API-ответов.</summary>
public sealed record ApiResponse<T>(bool Ok, T? Data, ApiError? Error);

/// <summary>Создаёт типобезопасные API-ответы без дублирования структуры endpoint-ами.</summary>
public static class ApiResponse
{
    /// <summary>Формирует успешный ответ с данными и без ошибки.</summary>
    public static ApiResponse<T> Success<T>(T data) => new(true, data, null);

    /// <summary>Формирует ошибочный ответ со стабильным машинным кодом и сообщением.</summary>
    public static ApiResponse<T> Failure<T>(string code, string message, string? target = null) =>
        new(false, default, new ApiError(code, message, target));
}

/// <summary>Описывает стабильный код и локализуемый текст API-ошибки.</summary>
public sealed record ApiError(string Code, string Message, string? Target = null);
