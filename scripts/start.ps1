param([switch]$Editor, [switch]$NoGateway, [switch]$Compatibility, [ValidateSet('balanced','cinematic')][string]$Quality, [switch]$Windowed, [switch]$Workbench, [switch]$Recovery)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$godotPath = Join-Path $projectRoot '.tools\godot\Godot_v4.7.2-stable_win64.exe'
if ($env:GODOT_BIN) { $godotPath = $env:GODOT_BIN }
if (-not (Test-Path -LiteralPath $godotPath)) { throw 'Run scripts\setup.ps1 first, or set GODOT_BIN to your Godot 4 executable.' }
$godotPath = (Resolve-Path -LiteralPath $godotPath).Path
$supervisor = Join-Path $PSScriptRoot 'recovery.mjs'
if ($Recovery) {
    & node $supervisor recovery $godotPath
    exit $LASTEXITCODE
}
$worldPath = Join-Path $projectRoot 'world'
Remove-Item Env:EUCLID_WORKBENCH_TOKEN -ErrorAction SilentlyContinue
if (-not (Test-Path -LiteralPath (Join-Path $worldPath '.godot\imported'))) {
    & $godotPath --headless --path $worldPath --editor --import
    if ($LASTEXITCODE -ne 0) { throw 'Initial Godot asset import failed.' }
}
$localDir = Join-Path $projectRoot '.local'
New-Item -ItemType Directory -Force -Path $localDir | Out-Null
if (-not $NoGateway) {
    $gatewayReady = $false
    $health = $null
    try { $health = Invoke-RestMethod 'http://127.0.0.1:4317/health' -TimeoutSec 2 } catch {}
    if ($health.service -eq 'construct-gateway') {
        if ($health.version -ge 17) {
            $gatewayReady = $true
        } else {
            & (Join-Path $PSScriptRoot 'stop-gateway.ps1')
        }
    }
    if (-not $gatewayReady) {
        $nodePath = (Get-Command node -ErrorAction Stop).Source
        $serverPath = Join-Path $projectRoot 'gateway\server.mjs'
        $gatewayProcess = Start-Process -FilePath $nodePath -ArgumentList @('"' + $serverPath + '"') -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $localDir 'gateway.log') -RedirectStandardError (Join-Path $localDir 'gateway-error.log')
        $gatewayProcess.Id | Set-Content (Join-Path $localDir 'gateway.pid')
        for ($attempt = 0; $attempt -lt 40; $attempt++) {
            Start-Sleep -Milliseconds 150
            try {
                $candidate = Get-Content -Raw -LiteralPath (Join-Path $localDir 'gateway.json') | ConvertFrom-Json
                $snapshot = Invoke-RestMethod 'http://127.0.0.1:4317/v1/world' -Headers @{ Authorization = 'Bearer ' + $candidate.token } -TimeoutSec 1
                if ($snapshot.schema_version -eq 1) { $gatewayReady = $true; break }
            } catch {}
            if ($gatewayProcess.HasExited) { break }
        }
    }
    if (-not $gatewayReady) { throw 'Gateway did not start. See .local\gateway-error.log.' }
    $gatewayConfig = Get-Content -Raw -LiteralPath (Join-Path $localDir 'gateway.json') | ConvertFrom-Json
    $env:CONSTRUCT_GATEWAY_URL = $gatewayConfig.url
    $env:CONSTRUCT_GATEWAY_TOKEN = $gatewayConfig.token
} else {
    Remove-Item Env:CONSTRUCT_GATEWAY_URL -ErrorAction SilentlyContinue
    Remove-Item Env:CONSTRUCT_GATEWAY_TOKEN -ErrorAction SilentlyContinue
}
if ($Editor) {
    $editorArguments = @('--path', ('"' + $worldPath + '"'), '--editor')
    if ($Compatibility) { $editorArguments += @('--rendering-method', 'gl_compatibility') }
    Start-Process -FilePath $godotPath -ArgumentList $editorArguments -WorkingDirectory $projectRoot
    return
}
$godotArguments = @('--path', $worldPath, '--resolution', '1920x1080')
if ($Windowed) {
    $godotArguments += '--windowed'
} else {
    $godotArguments += '--fullscreen'
}
if ($Compatibility) { $godotArguments += @('--rendering-method', 'gl_compatibility') }
if (-not $NoGateway) {
    # Workbench access belongs to the launched desktop app. Older shortcuts may still pass -Workbench.
    $env:EUCLID_WORKBENCH_TOKEN = $gatewayConfig.workbench_token
}
if ($Quality) { $godotArguments += @('--', "--quality=$Quality") }
& node $supervisor start $godotPath @godotArguments
exit $LASTEXITCODE
