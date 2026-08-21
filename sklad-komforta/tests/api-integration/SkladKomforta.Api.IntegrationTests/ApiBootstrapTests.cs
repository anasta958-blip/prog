using System.Net;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Logging;
using SkladKomforta.Application.Contracts;
using SkladKomforta.Application.Identity;

namespace SkladKomforta.Api.IntegrationTests;

public sealed class ApiBootstrapTests : IClassFixture<ApiFactory>
{
    private readonly HttpClient _client;

    public ApiBootstrapTests(ApiFactory factory) =>
        _client = factory.CreateClient();

    [Fact]
    public async Task LiveHealthEndpointReturnsSuccess()
    {
        var response = await _client.GetAsync("/health/live");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task ApiRootUsesUnifiedResponseContract()
    {
        var response = await _client.GetFromJsonAsync<ApiResponse<object>>("/api/v1");

        Assert.NotNull(response);
        Assert.True(response.Ok);
        Assert.Null(response.Error);
        Assert.NotNull(response.Data);
    }

    [Fact]
    public async Task SessionsEndpointRequiresAccessToken()
    {
        var response = await _client.GetAsync("/api/v1/identity/sessions");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task RoleSettingsEndpointRequiresAccessToken()
    {
        var response = await _client.GetAsync("/api/v1/settings/access/roles");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task OnboardingEndpointRequiresAccessToken()
    {
        var response = await _client.GetAsync("/api/v1/onboarding/");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task LogoutEndpointRequiresAccessToken()
    {
        var response = await _client.PostAsJsonAsync("/api/v1/identity/logout", new { });

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task BootstrapEndpointDoesNotRevealItselfWithoutSecret()
    {
        var response = await _client.PostAsJsonAsync(
            "/api/v1/auth/bootstrap/director",
            new BootstrapDirectorRequest("director", "Директор", "ReliablePass1!"));
        var body = await response.Content.ReadFromJsonAsync<ApiResponse<object>>();

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        Assert.NotNull(body);
        Assert.False(body.Ok);
        Assert.Equal("not_found", body.Error?.Code);
    }

    [Fact]
    public async Task DevelopmentCorsAllowsFlutterWebOnRandomLoopbackPort()
    {
        using var request = CreatePreflightRequest("http://localhost:51758");

        var response = await _client.SendAsync(request);

        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
        Assert.Equal(
            "http://localhost:51758",
            response.Headers.GetValues("Access-Control-Allow-Origin").Single());
    }

    [Fact]
    public async Task DevelopmentCorsDoesNotAllowExternalOrigin()
    {
        using var request = CreatePreflightRequest("https://untrusted.example");

        var response = await _client.SendAsync(request);

        Assert.False(response.Headers.Contains("Access-Control-Allow-Origin"));
    }

    private static HttpRequestMessage CreatePreflightRequest(string origin)
    {
        var request = new HttpRequestMessage(HttpMethod.Options, "/api/v1/auth/login");
        request.Headers.TryAddWithoutValidation("Origin", origin);
        request.Headers.TryAddWithoutValidation("Access-Control-Request-Method", "POST");
        request.Headers.TryAddWithoutValidation("Access-Control-Request-Headers", "content-type");
        return request;
    }
}

public sealed class ApiFactory : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureLogging(logging => logging.ClearProviders());
    }
}
