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

$kinds = if ($env:BENCH_KINDS) { $env:BENCH_KINDS.Split(',') } else { @('quote') }
$actions = if ($env:BENCH_ACTIONS) { $env:BENCH_ACTIONS.Split(',') } else { @('step') }
$rowCounts = if ($env:BENCH_ROW_COUNTS) { $env:BENCH_ROW_COUNTS.Split(',') | ForEach-Object { [int]$_ } } else { @(100, 500, 1000) }
foreach ($kind in $kinds) {
    foreach ($action in $actions) {
        foreach ($rows in $rowCounts) {
            foreach ($complex in @(0, 1)) {
                $env:BENCH_KIND = $kind
                $env:BENCH_ACTION = $action
                $env:BENCH_ROWS = [string]$rows
                $env:BENCH_COMPLEX = [string]$complex
                $env:BENCH_OUTPUT = Join-Path $outputPath "$kind-$action-$rows-$complex.txt"
                if (Test-Path -LiteralPath $env:BENCH_OUTPUT) {
                    Remove-Item -LiteralPath $env:BENCH_OUTPUT
                }
                $process = Start-Process -FilePath $executablePath -Wait -PassThru -WindowStyle Hidden
                if (-not (Test-Path -LiteralPath $env:BENCH_OUTPUT)) {
                    throw "Benchmark produced no result: kind=$kind action=$action rows=$rows complex=$complex exit=$($process.ExitCode)"
                }
                $result = Get-Content -LiteralPath $env:BENCH_OUTPUT -Raw
                Write-Output $result.Trim()
                if ($process.ExitCode -ne 0 -or $result.StartsWith('BENCH error=')) {
                    throw "Benchmark failed: kind=$kind action=$action rows=$rows complex=$complex exit=$($process.ExitCode)"
                }
            }
        }
    }
}
