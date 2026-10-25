param(
    [string]$Configuration = "Release",
    [string]$Runtime = "win-x64"
)
$ErrorActionPreference = "Stop"
& (Join-Path $PSScriptRoot "../apps/windows/Scripts/package-windows.ps1") @PSBoundParameters
exit $LASTEXITCODE
