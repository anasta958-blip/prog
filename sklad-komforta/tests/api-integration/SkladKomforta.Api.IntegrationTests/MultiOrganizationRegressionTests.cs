using System.Net;
using System.Net.Http.Headers;
using System.Text.Json.Nodes;

namespace SkladKomforta.Api.IntegrationTests;

public sealed partial class DatabaseRegressionTests
{
    /// <summary>
    /// Две организации в одной базе: закрытый endpoint создаёт нескольких
    /// директоров (логин уникален), каждый проходит первичную настройку своей
    /// организации и не видит данных другой.
    /// </summary>
    [DatabaseFact]
    public async Task SeveralDirectorsCreateIsolatedOrganizations()
    {
        await using var database = await RegressionDatabase.CreateAsync();
        await using var factory = new RegressionFactory(database.ConnectionString);
        using var first = factory.CreateClient();
        using var second = factory.CreateClient();
        using var anonymous = factory.CreateClient();

        await SignInNewDirectorAsync(first, "director-one", "Первая организация");
        await SignInNewDirectorAsync(second, "director-two", "Вторая организация");

        // Логин уникален без учёта регистра; без секретного токена endpoint скрыт.
        anonymous.DefaultRequestHeaders.Add("X-Bootstrap-Token", RegressionFactory.BootstrapToken);
        await Send(anonymous, HttpMethod.Post, "/auth/bootstrap/director", new
        {
            login = "Director-One", displayName = "Повтор", temporaryPassword = "Regression-test-123!",
        }, HttpStatusCode.Conflict);
        anonymous.DefaultRequestHeaders.Remove("X-Bootstrap-Token");
        await Send(anonymous, HttpMethod.Post, "/auth/bootstrap/director", new
        {
            login = "director-three", displayName = "Без токена", temporaryPassword = "Regression-test-123!",
        }, HttpStatusCode.NotFound);

        // Второй директор не может создать ещё одну организацию.
        await Send(second, HttpMethod.Post, "/identity/organization",
            new { name = "Ещё одна" }, HttpStatusCode.Conflict);

        // Данные каждой организации видны только её сотрудникам.
        await Send(second, HttpMethod.Post, "/company/clients", new
        {
            name = "Клиент второй", companyName = "Клиент второй", companyType = "person", phone = "+79990000001",
            passportSeries = "1234", passportNumber = "654321", passportIssuedBy = "Тестовый отдел",
        });
        Assert.Single((await Send(second, HttpMethod.Get, "/company/clients")).AsArray());
        Assert.Empty((await Send(first, HttpMethod.Get, "/company/clients")).AsArray());

        var secondBoard = Text((await Send(second, HttpMethod.Get, "/kanbans/")).AsArray()[0]!, "id");
        var firstBoards = (await Send(first, HttpMethod.Get, "/kanbans/")).AsArray();
        Assert.DoesNotContain(firstBoards, board => Text(board!, "id") == secondBoard);
        using var foreign = await first.GetAsync($"/api/v1/kanbans/{secondBoard}");
        Assert.False(foreign.IsSuccessStatusCode, "Канбан другой организации не должен открываться.");

        Assert.Equal("Первая организация", Text(await Send(first, HttpMethod.Get, "/company/profile"), "organizationName"));
        Assert.Equal("Вторая организация", Text(await Send(second, HttpMethod.Get, "/company/profile"), "organizationName"));
    }

    /// <summary>Новый директор: создание, первый вход, своя организация и активация.</summary>
    private static async Task SignInNewDirectorAsync(HttpClient staff, string login, string organizationName)
    {
        staff.DefaultRequestHeaders.Add("X-Bootstrap-Token", RegressionFactory.BootstrapToken);
        await Send(staff, HttpMethod.Post, "/auth/bootstrap/director", new
        {
            login, displayName = "Директор " + login, temporaryPassword = "Regression-test-123!", employeeLimit = 2,
        });
        staff.DefaultRequestHeaders.Remove("X-Bootstrap-Token");
        var started = await Send(staff, HttpMethod.Post, "/auth/login", new
        {
            login, password = "Regression-test-123!", deviceType = 2,
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
        staff.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue(
            "Bearer", Text(authenticated["tokens"]!, "accessToken"));
        var organization = await Send(staff, HttpMethod.Post, "/identity/organization", new { name = organizationName });
        staff.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", Text(organization, "accessToken"));
        var draft = OrderDraft() with { Company = OrderDraft().Company with { OrganizationName = organizationName } };
        await Send(staff, HttpMethod.Post, "/onboarding/draft", draft);
        await Send(staff, HttpMethod.Post, "/onboarding/activate");
        Assert.Equal(2, (await Send(staff, HttpMethod.Get, "/company/lifecycle"))["employeeLimit"]!.GetValue<int>());
    }
}
