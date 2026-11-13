param([string]$Archive)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$addon = Join-Path $root 'world/addons/godot_cef'
$platform = 'x86_64-pc-windows-msvc'
if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { $platform = 'aarch64-pc-windows-msvc' }
if (Test-Path -LiteralPath (Join-Path $addon 'godot_cef.gdextension')) {
    if (Test-Path -LiteralPath (Join-Path $addon "bin/$platform/gdcef.dll")) {
        Write-Host 'The Euclid browser runtime is already installed.'
        return
    }
}
$asset = 'godot_cef-store-v2.1.3.zip'
if (-not $Archive) {
    $tools = Join-Path $root '.tools'
    New-Item -ItemType Directory -Force -Path $tools | Out-Null
    $Archive = Join-Path $tools $asset
    if (-not (Test-Path -LiteralPath $Archive)) {
        $download = "$Archive.part"
        & curl.exe -fL --retry 2 --output $download "https://github.com/dsh0416/godot-cef/releases/download/v2.1.3/$asset"
        if ($LASTEXITCODE -ne 0) { throw 'Could not download the Euclid browser runtime.' }
        Move-Item -LiteralPath $download -Destination $Archive -Force
    }
}
$expected = '610dae1781e266ee7d1010e0370d8712d27f81cc5c8f9d7fe5deb1b04ccd91fd'
if ((Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash -ne $expected) {
    throw "Browser runtime checksum did not match. Remove the downloaded archive and retry."
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $Archive).Path)
$addon = [IO.Path]::GetFullPath($addon)
$prefix = 'dist/addons/godot_cef/'
try {
    # Extract the current architecture only. Publish the descriptor after its binaries.
    $entries = $zip.Entries | Where-Object {
        $_.FullName.StartsWith($prefix) -and $_.Name -and
        (-not $_.FullName.StartsWith($prefix + 'bin/') -or $_.FullName.StartsWith($prefix + "bin/$platform/"))
    } | Sort-Object { $_.Name -eq 'godot_cef.gdextension' }
    foreach ($entry in $entries) {
        $relative = $entry.FullName.Substring($prefix.Length)
        $target = [IO.Path]::GetFullPath((Join-Path $addon $relative))
        if (-not $target.StartsWith($addon + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Unexpected browser archive path.'
        }
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true)
    }
} finally { $zip.Dispose() }
if (-not (Test-Path -LiteralPath (Join-Path $addon "bin/$platform/gdcef.dll"))) { throw 'Browser binary is missing.' }
Write-Host 'YouTube screens are ready. Start Euclid normally.'
