# -Performance also runs the rendered villa and shore benchmarks against the frame budget
# (60 FPS average, 16.67 ms at the 95th percentile, 1920 x 1080). It opens a window.
param([switch]$Performance)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$godotPath = Join-Path $projectRoot '.tools\godot\Godot_v4.7.2-stable_win64_console.exe'
if ($env:GODOT_BIN) { $godotPath = $env:GODOT_BIN }
$worldPath = Join-Path $projectRoot 'world'
# The Workbench sets this for a draft that changes only gateway code and docs.
$gatewayOnly = $env:EUCLID_CHECK_SCOPE -eq 'gateway'
$worldOnly = $env:EUCLID_CHECK_SCOPE -eq 'world'

function Invoke-GodotCheck([string[]]$CheckArguments, [string]$SuccessMarker) {
    $lines = @(& $godotPath @CheckArguments 2>&1 | ForEach-Object { "$_" })
    $exitCode = $LASTEXITCODE
    $combined = $lines -join "`n"
    if ($exitCode -ne 0 -or $combined -match '(?m)^(SCRIPT ERROR|ERROR):' -or -not $combined.Contains($SuccessMarker)) {
        $logDirectory = Join-Path $projectRoot '.local\checks'
        New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null
        $lines | Set-Content -LiteralPath (Join-Path $logDirectory 'failure.log')
        $lines | Select-Object -First 45 | ForEach-Object { Write-Host $_ }
        throw "Godot check failed: $SuccessMarker"
    }
    $lines | ForEach-Object { Write-Host $_ }
}

Push-Location $projectRoot
try {
    if ($gatewayOnly) {
        Write-Host 'Gateway-only check: skipping the Godot core and smoke tests.'
    } else {
        Invoke-GodotCheck @('--headless','--path',$worldPath,'--script','res://scripts/diagnostics/core_tests.gd','--quit-after','1800') 'CONSTRUCT_CORE_TESTS_OK'
        if ($env:CONSTRUCT_GATEWAY_URL -and $env:CONSTRUCT_GATEWAY_TOKEN) {
            Invoke-GodotCheck @('--headless','--path',$worldPath,'--script','res://scripts/diagnostics/gateway_check.gd','--quit-after','1800') 'CONSTRUCT_GATEWAY_CLIENT_OK'
        }
        Invoke-GodotCheck @('--headless','--path',$worldPath,'--quit-after','3600','--','--smoke') 'CONSTRUCT_SMOKE_OK'
        Invoke-GodotCheck @('--headless','--path',$worldPath,'--quit-after','3600','--','--hot-check') 'HOT_CHECK_OK'
    }
    if ($worldOnly) {
        Write-Host 'World-only check: skipping the gateway tests, which do not read Godot scripts, shaders or scenes.'
    } else {
        & npm.cmd test
        if ($LASTEXITCODE -ne 0) { throw 'Gateway integration tests failed.' }
    }
    if ($Performance) {
        foreach ($zone in @('villa', 'beach')) {
            & powershell -NoProfile -File (Join-Path $PSScriptRoot 'benchmark.ps1') -Zone $zone -Width 1920 -Height 1080 -MinimumFps 60 -MaximumP95Ms 16.67 `
                -OutputDirectory (Join-Path $projectRoot ".local\benchmarks\check-$zone")
            if ($LASTEXITCODE -ne 0) { throw "The $zone missed the frame budget. See .local\benchmarks\check-$zone." }
        }
    }
    Write-Host 'All Euclid checks passed.'
} finally { Pop-Location }
