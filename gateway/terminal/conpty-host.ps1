# Starts one command under a Windows pseudoconsole for Euclid's gateway. See conpty.cs for the
# byte protocol on stdin and stdout. The C# compiles with the compiler Windows PowerShell already
# has, so nothing is downloaded or installed.
param(
    [Parameter(Mandatory = $true)] [string]$CommandLine,
    [Parameter(Mandatory = $true)] [string]$Cwd,
    [int]$Cols = 120,
    [int]$Rows = 32
)
$ErrorActionPreference = 'Stop'
try {
    if (-not ('EuclidPty.Host' -as [type])) {
        Add-Type -TypeDefinition (Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'conpty.cs')) -Language CSharp
    }
    $code = [EuclidPty.Host]::Run($CommandLine, $Cwd, [int16]$Cols, [int16]$Rows)
    exit $code
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
