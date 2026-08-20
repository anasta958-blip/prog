using SkladKomforta.Infrastructure;
using SkladKomforta.Worker;

var builder = Host.CreateApplicationBuilder(args);
builder.Services.AddInfrastructure(builder.Configuration);
builder.Services.AddHostedService<Worker>();

await builder.Build().RunAsync();
