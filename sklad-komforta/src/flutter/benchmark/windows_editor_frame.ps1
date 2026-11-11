param(
    [Parameter(Mandatory = $true)]
    [string]$Executable,
    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$executablePath = (Resolve-Path -LiteralPath $Executable).Path
$outputPath = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $outputPath -Force | Out-Null

foreach ($rows in @(100, 500, 1000)) {
    foreach ($complex in @(0, 1)) {
        $env:BENCH_ROWS = [string]$rows
        $env:BENCH_COMPLEX = [string]$complex
        $env:BENCH_OUTPUT = Join-Path $outputPath "$rows-$complex.txt"
        if (Test-Path -LiteralPath $env:BENCH_OUTPUT) {
            Remove-Item -LiteralPath $env:BENCH_OUTPUT
        }
        $process = Start-Process -FilePath $executablePath -Wait -PassThru -WindowStyle Hidden
        if (-not (Test-Path -LiteralPath $env:BENCH_OUTPUT)) {
            throw "Benchmark produced no result: rows=$rows complex=$complex exit=$($process.ExitCode)"
        }
        $result = Get-Content -LiteralPath $env:BENCH_OUTPUT -Raw
        Write-Output $result.Trim()
        if ($process.ExitCode -ne 0 -or $result.StartsWith('BENCH error=')) {
            throw "Benchmark failed: rows=$rows complex=$complex exit=$($process.ExitCode)"
        }
    }
}
