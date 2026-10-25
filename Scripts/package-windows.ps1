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
if ($Version -ne $ProjectVersion) { throw "Windows 项目版本 $ProjectVersion 与 Info.plist $Version 不一致" }
if ($Runtime -ne "win-x64") { throw "当前发布仅支持 win-x64" }
$Output = "build/windows/publish"
dotnet publish "Windows/TomatoNotes/TomatoNotes.csproj" -c $Configuration -r $Runtime --self-contained true -o $Output -p:DebugType=None -p:DebugSymbols=false
if ($LASTEXITCODE -ne 0) { throw "dotnet publish 失败" }
$Exe = Join-Path $Output "TomatoNotes.exe"
$Icon = Join-Path $Output "Assets/AppIcon.ico"
if (-not (Test-Path $Exe) -or -not (Test-Path $Icon)) { throw "发布文件不完整" }
$ISCC = Get-Command iscc.exe -ErrorAction SilentlyContinue
if (-not $ISCC) { $ISCC = Get-Command iscc -ErrorAction SilentlyContinue }
if (-not $ISCC) {
    $Default = "${env:ProgramFiles(x86)}/Inno Setup 6/ISCC.exe"
    if (Test-Path $Default) { $ISCC = Get-Item $Default }
}
if (-not $ISCC) { throw "需要 Inno Setup 6（ISCC.exe）" }
& $ISCC.Source "/DAppVersion=$Version" "/DPublishDir=$Output" "Windows/Packaging/TomatoNotes.iss"
if ($LASTEXITCODE -ne 0) { throw "Inno Setup 编译失败" }
$Setup = "build/releases/v$Version/TomatoNotes-v$Version-Windows-x64-setup.exe"
$Hash = (Get-FileHash $Setup -Algorithm SHA256).Hash.ToLowerInvariant()
"$Hash  TomatoNotes-v$Version-Windows-x64-setup.exe" | Set-Content "build/releases/v$Version/WINDOWS-SHA256SUMS.txt" -Encoding ascii
Write-Host "已生成：$Setup"
