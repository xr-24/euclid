# Download and prepare the Poly Haven (CC0) and Sketchfab furnishings and the wall finish textures that house pieces
# use, then index and import them. Only these are fetched and rebuilt; the rest of the art is left alone.
#   powershell -ExecutionPolicy Bypass -File scripts\build-furniture.ps1
param([string]$BlenderPath = 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe')
$ErrorActionPreference = 'Stop'
if ($env:BLENDER_BIN) { $BlenderPath = $env:BLENDER_BIN }
if (-not (Test-Path -LiteralPath $BlenderPath)) { throw 'Set BLENDER_BIN or pass -BlenderPath with the Blender executable path.' }
$projectRoot = Split-Path -Parent $PSScriptRoot
$list = Get-Content -Raw -LiteralPath (Join-Path $projectRoot 'world\data\pieces\house_furnishings.json') | ConvertFrom-Json
$ids = @($list.polyhaven)
Write-Host "Fetching $($ids.Count) Poly Haven furnishings..."
& $BlenderPath --background --factory-startup --python-exit-code 1 --python (Join-Path $PSScriptRoot 'blender\fetch_polyhaven.py') -- @ids
if ($LASTEXITCODE -ne 0) { throw 'Poly Haven download failed' }
& $BlenderPath --background --factory-startup --python-exit-code 1 --python (Join-Path $PSScriptRoot 'blender\optimize_models.py') -- @ids
if ($LASTEXITCODE -ne 0) { throw 'Model optimisation failed' }
Write-Host 'Fetching Poly Haven textures (wall finishes)...'
& $BlenderPath --background --factory-startup --python-exit-code 1 --python (Join-Path $PSScriptRoot 'blender\fetch_polyhaven.py') -- --textures
if ($LASTEXITCODE -ne 0) { throw 'Poly Haven texture download failed' }
$sketchfab = @($list.sketchfab)
if ($sketchfab.Count -gt 0) {
    Write-Host "Fetching $($sketchfab.Count) Sketchfab furnishings (needs .local\sketchfab-key.txt)..."
    & $BlenderPath --background --factory-startup --python-exit-code 1 --python (Join-Path $PSScriptRoot 'assets\fetch_sketchfab.py') -- @sketchfab
    if ($LASTEXITCODE -ne 0) { throw 'Sketchfab download failed' }
    & $BlenderPath --background --factory-startup --python-exit-code 1 --python (Join-Path $PSScriptRoot 'blender\build_library.py') -- @sketchfab --preview
    if ($LASTEXITCODE -ne 0) { throw 'Asset library build failed' }
}
& $BlenderPath --background --factory-startup --python-exit-code 1 --python (Join-Path $PSScriptRoot 'assets\build_catalog.py')
if ($LASTEXITCODE -ne 0) { throw 'Asset catalog build failed' }
$godotPath = Join-Path $projectRoot '.tools\godot\Godot_v4.7.2-stable_win64_console.exe'
if ($env:GODOT_BIN) { $godotPath = $env:GODOT_BIN }
if (Test-Path -LiteralPath $godotPath) {
    & $godotPath --headless --path (Join-Path $projectRoot 'world') --editor --import
    if ($LASTEXITCODE -ne 0) { throw 'Godot import failed' }
}
Write-Host 'Furnishings ready.'
