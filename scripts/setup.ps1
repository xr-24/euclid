$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$toolDir = Join-Path $projectRoot '.tools\godot'
$version = '4.7.2-stable'
$asset = "Godot_v${version}_win64.exe.zip"
New-Item -ItemType Directory -Force -Path $toolDir | Out-Null
if (-not (Test-Path -LiteralPath (Join-Path $toolDir "Godot_v${version}_win64.exe"))) {
    $releaseUrl = "https://github.com/godotengine/godot-builds/releases/download/$version"
    $archivePath = Join-Path $toolDir $asset
    Invoke-WebRequest "$releaseUrl/$asset" -OutFile $archivePath
    Invoke-WebRequest "$releaseUrl/SHA512-SUMS.txt" -OutFile (Join-Path $toolDir 'SHA512-SUMS.txt')
    $checksum = Get-Content (Join-Path $toolDir 'SHA512-SUMS.txt') | Where-Object { $_.EndsWith($asset) }
    $actualHash = (Get-FileHash -Algorithm SHA512 -LiteralPath $archivePath).Hash.ToLowerInvariant()
    if (-not $checksum -or $actualHash -ne ($checksum -split '\s+')[0]) { throw 'Godot checksum did not match' }
    Expand-Archive -LiteralPath $archivePath -DestinationPath $toolDir -Force
}
Get-Command node -ErrorAction Stop | Out-Null
Write-Host 'Ready. Open Start Euclid.cmd to play, or run scripts\start.ps1 -Editor.'
