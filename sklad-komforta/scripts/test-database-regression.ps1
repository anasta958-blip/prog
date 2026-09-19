param(
    [string]$RedisConnection = '127.0.0.1:16379,abortConnect=false',
    [string]$Filter = 'FullyQualifiedName~DatabaseRegressionTests'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$settings = @{}
foreach ($line in Get-Content -LiteralPath (Join-Path $projectRoot '.env')) {
    if ($line -match '^([A-Z_]+)=(.*)$') {
        $settings[$Matches[1]] = $Matches[2].Trim().Trim('"').Trim("'")
    }
}
if (!$settings['POSTGRES_USER'] -or !$settings['POSTGRES_PASSWORD']) {
    throw 'POSTGRES_USER and POSTGRES_PASSWORD must be configured in .env.'
}

$previousPostgres = $env:SKLAD_TEST_POSTGRES
$previousRedis = $env:SKLAD_TEST_REDIS
try {
    $env:SKLAD_TEST_POSTGRES = 'Host=127.0.0.1;Port=5432;Username="' +
        $settings['POSTGRES_USER'].Replace('"', '""') + '";Password="' +
        $settings['POSTGRES_PASSWORD'].Replace('"', '""') + '"'
    $env:SKLAD_TEST_REDIS = $RedisConnection
    dotnet test (Join-Path $projectRoot 'tests/api-integration/SkladKomforta.Api.IntegrationTests/SkladKomforta.Api.IntegrationTests.csproj') --no-restore --filter $Filter --verbosity minimal
    if ($LASTEXITCODE -ne 0) { throw 'Database regression tests failed.' }
} finally {
    $env:SKLAD_TEST_POSTGRES = $previousPostgres
    $env:SKLAD_TEST_REDIS = $previousRedis
}
