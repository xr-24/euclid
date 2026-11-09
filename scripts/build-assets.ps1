param([string]$BlenderPath = 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe', [switch]$NoDownload)
$ErrorActionPreference = 'Stop'
if ($env:BLENDER_BIN) { $BlenderPath = $env:BLENDER_BIN }
if (-not (Test-Path -LiteralPath $BlenderPath)) { throw 'Set BLENDER_BIN or pass -BlenderPath with the Blender executable path.' }
& $BlenderPath --background --factory-startup --python-exit-code 1 --python (Join-Path $PSScriptRoot 'blender\build_column.py')
if ($LASTEXITCODE -ne 0) { throw 'Asset build failed' }
& $BlenderPath --background --factory-startup --python-exit-code 1 --python (Join-Path $PSScriptRoot 'blender\build_villa.py')
if ($LASTEXITCODE -ne 0) { throw 'Villa asset build failed' }
& $BlenderPath --background --factory-startup --python-exit-code 1 --python (Join-Path $PSScriptRoot 'blender\build_coast.py')
if ($LASTEXITCODE -ne 0) { throw 'Coast build failed' }
& $BlenderPath --background --factory-startup --python-exit-code 1 --python (Join-Path $PSScriptRoot 'blender\build_beach.py')
if ($LASTEXITCODE -ne 0) { throw 'Shore terrain build failed' }
# CC0 Poly Haven assets: cached downloads, then real-time reduction of the scanned models.
# Skip with -NoDownload to rebuild offline from what is already cached.
if (-not $NoDownload) {
    & $BlenderPath --background --factory-startup --python-exit-code 1 --python (Join-Path $PSScriptRoot 'blender\fetch_polyhaven.py')
    if ($LASTEXITCODE -ne 0) { throw 'Poly Haven download failed' }
}
& $BlenderPath --background --factory-startup --python-exit-code 1 --python (Join-Path $PSScriptRoot 'blender\optimize_models.py')
if ($LASTEXITCODE -ne 0) { throw 'Model optimisation failed' }
# Asset library: Sketchfab scans listed in scripts/assets/sketchfab.json. Downloading needs a
# Sketchfab API token (SKETCHFAB_API_TOKEN or .local\sketchfab-key.txt); without one, already
# downloaded models are still rebuilt. The catalog then indexes every placeable model.
$projectRoot = Split-Path -Parent $PSScriptRoot
$hasToken = $env:SKETCHFAB_API_TOKEN -or (Test-Path -LiteralPath (Join-Path $projectRoot '.local\sketchfab-key.txt'))
if (-not $NoDownload -and $hasToken) {
    & $BlenderPath --background --factory-startup --python-exit-code 1 --python (Join-Path $PSScriptRoot 'assets\fetch_sketchfab.py')
    if ($LASTEXITCODE -ne 0) { throw 'Sketchfab download failed' }
}
& $BlenderPath --background --factory-startup --python-exit-code 1 --python (Join-Path $PSScriptRoot 'blender\build_library.py')
if ($LASTEXITCODE -ne 0) { throw 'Asset library build failed' }
& $BlenderPath --background --factory-startup --python-exit-code 1 --python (Join-Path $PSScriptRoot 'assets\build_catalog.py')
if ($LASTEXITCODE -ne 0) { throw 'Asset catalog build failed' }
$godotPath = Join-Path $projectRoot '.tools\godot\Godot_v4.7.2-stable_win64_console.exe'
if ($env:GODOT_BIN) { $godotPath = $env:GODOT_BIN }
if (Test-Path -LiteralPath $godotPath) {
    & $godotPath --headless --path (Join-Path $projectRoot 'world') --editor --import
    if ($LASTEXITCODE -ne 0) { throw 'Godot import failed' }
}
