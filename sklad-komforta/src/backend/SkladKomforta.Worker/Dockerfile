FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY . .
RUN dotnet publish src/backend/SkladKomforta.Worker/SkladKomforta.Worker.csproj -c Release -o /app/publish --no-self-contained

# Infrastructure использует health/options типы из Microsoft.AspNetCore.App,
# поэтому Worker должен запускаться на общем ASP.NET Core runtime.
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
COPY --from=build /app/publish .
USER $APP_UID
ENTRYPOINT ["dotnet", "SkladKomforta.Worker.dll"]
