param(
    [ValidateSet('balanced','cinematic')][string]$Quality = 'balanced',
    [ValidateSet('villa','beach','construct')][string]$Zone = 'villa',
    [ValidateSet('default','quality','isolate','costs','looks')][string]$Suite = 'default',
    [string]$OutputDirectory,
    [int]$Width = 1440,
    [int]$Height = 900,
    [double]$MinimumFps = 0,
    [double]$MaximumP95Ms = 0,
    [long]$WindowId = 0,
    [string]$ProjectPath
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$godotPath = Join-Path $projectRoot '.tools\godot\Godot_v4.7.2-stable_win64_console.exe'
if ($env:GODOT_BIN) { $godotPath = $env:GODOT_BIN }
if (-not $ProjectPath) { $ProjectPath = Join-Path $projectRoot 'world' }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $projectRoot ".local\benchmarks\$Quality-$Zone" }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$oldDir = $env:CONSTRUCT_BENCHMARK_DIR
$oldZone = $env:CONSTRUCT_BENCHMARK_ZONE
$oldSuite = $env:CONSTRUCT_BENCHMARK_SUITE
$oldRunId = $env:CONSTRUCT_BENCHMARK_RUN_ID
$runId = [guid]::NewGuid().ToString()
$env:CONSTRUCT_BENCHMARK_RUN_ID = $runId
$env:CONSTRUCT_BENCHMARK_DIR = $OutputDirectory
$env:CONSTRUCT_BENCHMARK_ZONE = $Zone
if ($Suite -eq 'default') { Remove-Item Env:CONSTRUCT_BENCHMARK_SUITE -ErrorAction SilentlyContinue } else { $env:CONSTRUCT_BENCHMARK_SUITE = $Suite }
try {
    $embedding = @()
    if ($WindowId -gt 0) { $embedding = @('--wid', "$WindowId", '--audio-driver', 'Dummy') }
    # The costs suite runs about five minutes of uncapped frames; give it room before the frame cap.
    $quitAfter = if ($Suite -eq 'costs') { 400000 } else { 20000 }
    $lines = @(& $godotPath --path $ProjectPath --windowed --resolution "${Width}x${Height}" @embedding --quit-after $quitAfter -- --benchmark "--quality=$Quality" 2>&1 | ForEach-Object { Write-Host $_; "$_" })
    $exitCode = $LASTEXITCODE
    $lines | Set-Content -LiteralPath (Join-Path $OutputDirectory 'run.log')
    if ($exitCode -ne 0) { throw "Benchmark exited with code $exitCode. Inspect run.log." }
    if (($lines -join "`n") -match '(?m)^(SCRIPT ERROR|ERROR):') { throw 'Benchmark failed; inspect run.log.' }
    $results = Get-Content -Raw -LiteralPath (Join-Path $OutputDirectory 'results.json') | ConvertFrom-Json
    if ($results.run_id -ne $runId) { throw 'This run did not complete; refusing stale benchmark results.' }
    if (-not $results.samples.Count) { throw 'Benchmark produced no measurements.' }
    $results.samples | Select-Object variant,view,@{n='FPS';e={[math]::Round($_.fps,1)}},@{n='P95ms';e={[math]::Round($_.p95_ms,2)}},@{n='GPUms';e={[math]::Round($_.gpu_ms,2)}},@{n='RenderCPUms';e={[math]::Round($_.render_cpu_ms,2)}},@{n='Draws';e={[math]::Round($_.draw_calls)}},@{n='MirrorGPUms';e={[math]::Round($_.mirror_gpu_ms,2)}} | Format-Table
    if ($MinimumFps -gt 0 -and @($results.samples | Where-Object { $_.fps -lt $MinimumFps }).Count) { throw "A view averaged below $MinimumFps FPS." }
    if ($MaximumP95Ms -gt 0 -and @($results.samples | Where-Object { $_.p95_ms -gt $MaximumP95Ms }).Count) { throw "A view exceeded $MaximumP95Ms ms at the 95th percentile." }
    Write-Host "Results: $OutputDirectory"
} finally {
    $env:CONSTRUCT_BENCHMARK_DIR = $oldDir
    $env:CONSTRUCT_BENCHMARK_ZONE = $oldZone
    $env:CONSTRUCT_BENCHMARK_SUITE = $oldSuite
    $env:CONSTRUCT_BENCHMARK_RUN_ID = $oldRunId
}
