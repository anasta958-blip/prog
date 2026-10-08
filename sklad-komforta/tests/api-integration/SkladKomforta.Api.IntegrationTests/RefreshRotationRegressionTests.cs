using System.Net;
using System.Net.Http.Headers;
using System.Text.Json.Nodes;

namespace SkladKomforta.Api.IntegrationTests;

public sealed partial class DatabaseRegressionTests
{
    /// <summary>
    /// Ротация refresh-токена: только что заменённый токен ещё принимается
    /// (ответ мог не дойти до браузера), «потерянная» пара при этом отзывается,
    /// а после выхода повтор старого токена сессию не восстанавливает.
    /// </summary>
    [DatabaseFact]
    public async Task ReplacedRefreshTokenIsAcceptedShortlyAfterRotation()
    {
        await using var database = await RegressionDatabase.CreateAsync();
        await using var factory = new RegressionFactory(database.ConnectionString);
        using var staff = factory.CreateClient();
        using var anonymous = factory.CreateClient();

        staff.DefaultRequestHeaders.Add("X-Bootstrap-Token", RegressionFactory.BootstrapToken);
        await Send(staff, HttpMethod.Post, "/auth/bootstrap/director", new
        {
            login = "refresh-director", displayName = "Директор", temporaryPassword = "Regression-test-123!",
        });
        staff.DefaultRequestHeaders.Remove("X-Bootstrap-Token");
        var started = await Send(staff, HttpMethod.Post, "/auth/login", new
        {
            login = "refresh-director", password = "Regression-test-123!", deviceType = 2,
        });
        var changed = await Send(staff, HttpMethod.Post, "/auth/initial-password", new
        {
            challengeToken = Text(started, "challengeToken"), newPassword = "Regression-final-456!",
        });
        var challenge = Text(changed, "challengeToken");
        var totp = await Send(staff, HttpMethod.Post, "/auth/totp/setup", new { challengeToken = challenge });
        var authenticated = await Send(staff, HttpMethod.Post, "/auth/totp/confirm", new
        {
            challengeToken = challenge, code = Totp(Text(totp, "secret")),
        });
        var original = Text(authenticated["tokens"]!, "refreshToken");

        Task<JsonNode> Refresh(string token, HttpStatusCode expected = HttpStatusCode.OK) =>
            Send(anonymous, HttpMethod.Post, "/auth/refresh", new { refreshToken = token }, expected);

        // Первое обновление прошло, но ответ «не дошёл»: повтор того же токена
        // принимается и выдаёт новую пару, а недошедшая пара отзывается.
        var lost = Text(await Refresh(original), "refreshToken");
        var retried = await Refresh(original);
        var current = Text(retried, "refreshToken");
        Assert.NotEqual(lost, current);

        // Окно ожидания прошло (сдвигаем время отзыва в базе): заменённые
        // токены больше не принимаются, действующий работает обычной ротацией.
        await using (var connection = new Npgsql.NpgsqlConnection(database.ConnectionString))
        {
            await connection.OpenAsync();
            await using var age = new Npgsql.NpgsqlCommand(
                "UPDATE public.refresh_sessions SET revoked_at = revoked_at - interval '2 minutes' WHERE revoked_at IS NOT NULL",
                connection);
            await age.ExecuteNonQueryAsync();
        }
        await Refresh(original, HttpStatusCode.Unauthorized);
        await Refresh(lost, HttpStatusCode.Unauthorized);
        var next = await Refresh(current);
        var latest = Text(next, "refreshToken");

        // После выхода цепочка закрыта: повтор недавно заменённого токена
        // не восстанавливает сессию.
        staff.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue(
            "Bearer", Text(next, "accessToken"));
        await Send(staff, HttpMethod.Post, "/identity/logout");
        await Refresh(current, HttpStatusCode.Unauthorized);
        await Refresh(latest, HttpStatusCode.Unauthorized);
        await Refresh("не-токен", HttpStatusCode.Unauthorized);
    }
}
