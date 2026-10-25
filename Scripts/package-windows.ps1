param(
    [string]$Configuration = "Release",
    [string]$Runtime = "win-x64"
)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
$Plist = [xml](Get-Content -Raw "Packaging/Info.plist")
$Keys = @($Plist.plist.dict.ChildNodes)
$Version = ($Keys[([array]::IndexOf($Keys, ($Keys | Where-Object { $_.Name -eq "key" -and $_.InnerText -eq "CFBundleShortVersionString" })) + 1)]).InnerText
$ProjectVersion = (Select-Xml -Path "Windows/TomatoNotes/TomatoNotes.csproj" -XPath "/Project/PropertyGroup/VersionPrefix").Node.InnerText
if ($Version -ne $ProjectVersion) { throw "Windows version $ProjectVersion differs from Info.plist $Version" }
if ($Runtime -ne "win-x64") { throw "Only win-x64 is supported" }
$Output = "build/windows/publish"
dotnet publish "Windows/TomatoNotes/TomatoNotes.csproj" -c $Configuration -r $Runtime --self-contained true -o $Output -p:DebugType=None -p:DebugSymbols=false
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed" }
$Exe = Join-Path $Output "TomatoNotes.exe"
$Icon = Join-Path $Output "Assets/AppIcon.ico"
if (-not (Test-Path $Exe) -or -not (Test-Path $Icon)) { throw "Publish output is incomplete" }
$ISCC = Get-Command iscc.exe -ErrorAction SilentlyContinue
if (-not $ISCC) { $ISCC = Get-Command iscc -ErrorAction SilentlyContinue }
if (-not $ISCC) {
    $Default = "${env:ProgramFiles(x86)}/Inno Setup 6/ISCC.exe"
    if (Test-Path $Default) { $ISCC = Get-Item $Default }
}
if (-not $ISCC) { throw "Inno Setup 6 (ISCC.exe) is required" }
& $ISCC.Source "/DAppVersion=$Version" "/DPublishDir=$Root/build/windows/publish" "/DRepoRoot=$Root" "Windows/Packaging/TomatoNotes.iss"
if ($LASTEXITCODE -ne 0) { throw "Inno Setup compilation failed" }
$Setup = "build/releases/v$Version/TomatoNotes-v$Version-Windows-x64-setup.exe"
$Hash = (Get-FileHash $Setup -Algorithm SHA256).Hash.ToLowerInvariant()
"$Hash  TomatoNotes-v$Version-Windows-x64-setup.exe" | Set-Content "build/releases/v$Version/WINDOWS-SHA256SUMS.txt" -Encoding ascii
Write-Host "Created: $Setup"
