using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.IdentityModel.Tokens;
using SkladKomforta.Api.Middleware;
using SkladKomforta.Api.Identity;
using SkladKomforta.Api.Authorization;
using SkladKomforta.Api.Catalog;
using SkladKomforta.Api.Company;
using SkladKomforta.Api.Kanban;
using SkladKomforta.Api.Onboarding;
using SkladKomforta.Api.Orders;
using SkladKomforta.Api.Outbound;
using SkladKomforta.Api.Quotes;
using SkladKomforta.Api.Realtime;
using SkladKomforta.Application.Contracts;
using SkladKomforta.Application.Identity;
using SkladKomforta.Infrastructure;
using SkladKomforta.Infrastructure.Configuration;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddProblemDetails();
builder.Services.AddInfrastructure(builder.Configuration);
builder.Services.AddIdentityInfrastructure(builder.Configuration);
builder.Services.AddSingleton<IAccessTokenIssuer, JwtAccessTokenIssuer>();
builder.Services.AddSingleton<RealtimeHub>();

var trustForwardedHeaders = builder.Configuration.GetValue<bool>("ReverseProxy:TrustForwardedHeaders");
if (trustForwardedHeaders)
{
    builder.Services.Configure<ForwardedHeadersOptions>(options =>
    {
        options.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
        options.ForwardLimit = 1;

        // Production Compose не публикует порт API. Доступ имеет только контейнер
        // reverse proxy, поэтому заголовкам от одного промежуточного узла можно доверять.
        options.KnownIPNetworks.Clear();
        options.KnownProxies.Clear();
    });
}

var allowedOrigins = builder.Configuration
    .GetSection("Cors:AllowedOrigins")
    .Get<string[]>() ?? [];
var configuredOrigins = allowedOrigins.ToHashSet(StringComparer.OrdinalIgnoreCase);
var allowDevelopmentLoopbackOrigins = builder.Environment.IsDevelopment();
builder.Services.AddCors(options => options.AddPolicy("FlutterClients", policy =>
{
    policy.SetIsOriginAllowed(origin =>
        configuredOrigins.Contains(origin) ||
        (allowDevelopmentLoopbackOrigins &&
         Uri.TryCreate(origin, UriKind.Absolute, out var uri) &&
         uri.IsLoopback &&
         (uri.Scheme == Uri.UriSchemeHttp || uri.Scheme == Uri.UriSchemeHttps)))
        .AllowAnyHeader()
        .AllowAnyMethod()
        .AllowCredentials();
}));

var jwt = builder.Configuration.GetRequiredSection(JwtOptions.SectionName).Get<JwtOptions>()
    ?? throw new InvalidOperationException("JWT configuration is missing.");

builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.MapInboundClaims = false;
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = jwt.Issuer,
            ValidateAudience = true,
            ValidAudience = jwt.Audience,
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwt.SigningKey)),
            ValidateLifetime = true,
            ClockSkew = TimeSpan.FromMinutes(1),
        };
    });
builder.Services.AddAuthorization();

var app = builder.Build();

if (trustForwardedHeaders)
{
    app.UseForwardedHeaders();
}

app.UseExceptionHandler(errorApp => errorApp.Run(async context =>
{
    var exception = context.Features.Get<Microsoft.AspNetCore.Diagnostics.IExceptionHandlerFeature>()?.Error;
    var identityError = exception as IdentityException;
    var requestError = exception as BadHttpRequestException;
    context.Response.StatusCode = identityError?.StatusCode ?? requestError?.StatusCode ?? StatusCodes.Status500InternalServerError;
    await context.Response.WriteAsJsonAsync(
        ApiResponse.Failure<object>(
            identityError?.Code ?? (requestError is null ? "internal_error" : "invalid_request"),
            identityError?.Message ?? (requestError is null
                ? "Внутренняя ошибка сервера."
                : requestError.StatusCode switch
                {
                    StatusCodes.Status413PayloadTooLarge => "Размер запроса превышает допустимый предел.",
                    StatusCodes.Status415UnsupportedMediaType => "Неподдерживаемый формат запроса.",
                    _ => "Запрос содержит некорректные данные. Проверьте заполненные поля.",
                })));
}));
app.UseMiddleware<CorrelationIdMiddleware>();
app.UseCors("FlutterClients");
app.UseWebSockets(new WebSocketOptions { KeepAliveInterval = TimeSpan.FromSeconds(30) });
app.UseAuthentication();
app.UseMiddleware<TenantResolutionMiddleware>();
app.UseMiddleware<TenantPermissionMiddleware>();
app.UseMiddleware<RealtimeChangeMiddleware>();
app.UseAuthorization();

app.MapGet("/api/v1", () => ApiResponse.Success<object>(new
{
    service = "Sklad Komforta API",
    version = "v1",
}));
app.MapIdentityEndpoints();
app.MapOnboardingEndpoints();
app.MapRoleEndpoints();
app.MapCatalogEndpoints();
app.MapKanbanEndpoints();
app.MapQuoteEndpoints();
app.MapOrderEndpoints();
app.MapOutboundEndpoints();
app.MapCompanyEndpoints();
app.MapRealtimeEndpoints();
app.MapHealthChecks("/health/live", new HealthCheckOptions
{
    Predicate = _ => false,
});
app.MapHealthChecks("/health/ready", new HealthCheckOptions
{
    Predicate = registration => registration.Tags.Contains("ready"),
});

app.Run();

public partial class Program;
