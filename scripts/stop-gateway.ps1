$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$pidPath = Join-Path $projectRoot '.local\gateway.pid'
if (-not (Test-Path -LiteralPath $pidPath)) { Write-Host 'No launcher-managed gateway recorded.'; return }
$gatewayPid = [int](Get-Content -Raw -LiteralPath $pidPath)
$processInfo = Get-CimInstance Win32_Process -Filter "ProcessId = $gatewayPid"
$expectedServer = Join-Path $projectRoot 'gateway\server.mjs'
if (-not $processInfo) { Write-Host 'Gateway is already stopped.'; return }
if ($processInfo.Name -ne 'node.exe' -or -not $processInfo.CommandLine.Contains($expectedServer)) { throw 'Recorded process does not match this project gateway. Nothing stopped.' }
Stop-Process -Id $gatewayPid
Write-Host 'Euclid gateway stopped.'
