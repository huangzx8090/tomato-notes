param(
    [string]$Configuration = "Release",
    [string]$Runtime = "win-x64"
)
$ErrorActionPreference = "Stop"

function Assert-PeMachine {
    param([string]$Path, [UInt16]$ExpectedMachine)
    # 直接读取 PE 机器类型，避免依赖不同 runner 上 file 的文字格式。
    $Bytes = [IO.File]::ReadAllBytes($Path)
    if ($Bytes.Length -lt 64 -or $Bytes[0] -ne 0x4D -or $Bytes[1] -ne 0x5A) {
        throw "Invalid DOS header: $Path"
    }
    $PE = [BitConverter]::ToInt32($Bytes, 60)
    if ($PE -lt 64 -or $PE -gt ($Bytes.Length - 6)) { throw "Invalid PE offset: $Path" }
    if ([BitConverter]::ToUInt32($Bytes, $PE) -ne 0x00004550) { throw "Invalid PE signature: $Path" }
    $Machine = [BitConverter]::ToUInt16($Bytes, $PE + 4)
    if ($Machine -ne $ExpectedMachine) {
        throw ("Expected PE Machine 0x{0:X4}, found 0x{1:X4}: {2}" -f $ExpectedMachine, $Machine, $Path)
    }
    Write-Host ("Validated PE Machine 0x{0:X4}: {1}" -f $Machine, $Path)
}

$PlatformRoot = Split-Path -Parent $PSScriptRoot
$Root = Split-Path -Parent (Split-Path -Parent $PlatformRoot)
Set-Location $Root
$Version = (Get-Content -Raw (Join-Path $Root "VERSION")).Trim()
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "VERSION must use X.Y.Z" }
$ProjectVersion = (Select-Xml -Path "apps/windows/TomatoNotes/TomatoNotes.csproj" -XPath "/Project/PropertyGroup/VersionPrefix").Node.InnerText
if ($Version -ne $ProjectVersion) { throw "Windows version $ProjectVersion differs from VERSION $Version" }
if ($Runtime -ne "win-x64") { throw "Only win-x64 is supported" }
$Output = "build/windows/publish"
dotnet publish "apps/windows/TomatoNotes/TomatoNotes.csproj" -c $Configuration -r $Runtime --self-contained true -o $Output -p:DebugType=None -p:DebugSymbols=false
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed" }
$Exe = Join-Path $Output "TomatoNotes.exe"
$Icon = Join-Path $Output "Assets/AppIcon.ico"
if (-not (Test-Path $Exe) -or -not (Test-Path $Icon)) { throw "Publish output is incomplete" }
Assert-PeMachine -Path $Exe -ExpectedMachine 0x8664
$ISCC = Get-Command iscc.exe -ErrorAction SilentlyContinue
if (-not $ISCC) { $ISCC = Get-Command iscc -ErrorAction SilentlyContinue }
if (-not $ISCC) {
    $Default = "${env:ProgramFiles(x86)}/Inno Setup 6/ISCC.exe"
    if (Test-Path $Default) { $ISCC = Get-Item $Default }
}
if (-not $ISCC) { throw "Inno Setup 6 (ISCC.exe) is required" }
& $ISCC.Source "/DAppVersion=$Version" "/DPublishDir=$Root/build/windows/publish" "/DRepoRoot=$Root" "apps/windows/Packaging/TomatoNotes.iss"
if ($LASTEXITCODE -ne 0) { throw "Inno Setup compilation failed" }
$Setup = "build/releases/v$Version/TomatoNotes-v$Version-Windows-x64-setup.exe"
# Inno 安装引导器为 x86，安装的应用本体已单独检查为 x64。
Assert-PeMachine -Path $Setup -ExpectedMachine 0x014C
$Hash = (Get-FileHash $Setup -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText((Join-Path $Root "build/releases/v$Version/WINDOWS-SHA256SUMS.txt"), "$Hash  TomatoNotes-v$Version-Windows-x64-setup.exe`n", [Text.UTF8Encoding]::new($false))
Write-Host "Created: $Setup"
