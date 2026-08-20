using System.Net;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Logging;
using SkladKomforta.Application.Contracts;

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
}

public sealed class ApiFactory : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureLogging(logging => logging.ClearProviders());
    }
}
