namespace SkladKomforta.Api.Middleware;

/// <summary>
/// Сохраняет переданный correlation ID либо создаёт новый, записывает его в
/// trace identifier и возвращает клиенту для сопоставления запроса с журналом.
/// </summary>
internal sealed class CorrelationIdMiddleware(RequestDelegate next)
{
    private const string HeaderName = "X-Correlation-ID";

    /// <summary>Обогащает текущий HTTP-запрос идентификатором и передаёт управление дальше.</summary>
    public async Task InvokeAsync(HttpContext context)
    {
        var correlationId = context.Request.Headers[HeaderName].FirstOrDefault();
        if (string.IsNullOrWhiteSpace(correlationId))
        {
            correlationId = Guid.NewGuid().ToString("N");
        }

        context.TraceIdentifier = correlationId;
        context.Response.Headers[HeaderName] = correlationId;
        await next(context);
    }
}
