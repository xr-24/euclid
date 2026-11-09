param([Parameter(Mandatory = $true)][ValidatePattern('^[a-f0-9]{32}$')][string]$WorldSession)
$ErrorActionPreference = 'Stop'
try { $Host.UI.RawUI.WindowTitle = 'Euclid | Codex' } catch {}
$projectRoot = Split-Path -Parent $PSScriptRoot
try {
    $url = $env:CONSTRUCT_GATEWAY_URL
    if ($url -notmatch '^http://127\.0\.0\.1:[0-9]+$' -or -not $env:CONSTRUCT_GATEWAY_TOKEN) {
        throw 'Launch Euclid with its local gateway first.'
    }
    $cli = & node (Join-Path $projectRoot 'gateway\codex-cli.mjs')
    if ($LASTEXITCODE -ne 0 -or -not $cli) { throw 'Install the Codex CLI or set EUCLID_CODEX_BIN to its executable.' }
    Write-Host 'EUCLID  /  CODEX UPLINK' -ForegroundColor Cyan
    Write-Host 'Ask Codex to list environments, travel, create a Grid space, follow, or stay.'
    $options = @('--cd', $projectRoot, '--sandbox', 'read-only', '-a', 'on-request',
        '-c', "mcp_servers.euclid.url=$url/mcp/$WorldSession",
        '-c', 'mcp_servers.euclid.bearer_token_env_var=CONSTRUCT_GATEWAY_TOKEN',
        '-c', 'mcp_servers.euclid.default_tools_approval_mode=writes')
    & $cli @options
    if ($LASTEXITCODE -ne 0) { throw "Codex exited with code $LASTEXITCODE." }
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    Read-Host 'Press Enter to close'
}
