FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY . .
RUN dotnet publish src/backend/SkladKomforta.Api/SkladKomforta.Api.csproj -c Release -o /app/publish --no-self-contained

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
RUN sed -i \
      -e 's|URIs: http://archive.ubuntu.com/ubuntu/|URIs: https://archive.ubuntu.com/ubuntu/|' \
      -e 's|URIs: http://security.ubuntu.com/ubuntu/|URIs: https://security.ubuntu.com/ubuntu/|' \
      /etc/apt/sources.list.d/ubuntu.sources \
    && apt-get update \
    && apt-get install -y --no-install-recommends fonts-noto-core \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /app/publish .
USER $APP_UID
EXPOSE 8080
ENTRYPOINT ["dotnet", "SkladKomforta.Api.dll"]
