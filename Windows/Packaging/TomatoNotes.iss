; Build from the repository root:
; dotnet publish Windows/TomatoNotes -c Release -r win-x64 --self-contained true -o build/windows/publish
; iscc /DAppVersion=1.5.0 /DPublishDir=build/windows/publish Windows/Packaging/TomatoNotes.iss
#define AppName "番茄小记"
#define AppId "{{A36F99B0-1F70-42F9-9F1C-C7B80E975244}"
#ifndef AppVersion
  #define AppVersion "1.5.0"
#endif
#ifndef PublishDir
  #define PublishDir "build\windows\publish"
#endif
[Setup]
AppId={#AppId}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=TomatoNotes
DefaultDirName={autopf}\TomatoNotes
DefaultGroupName=番茄小记
OutputDir=build\releases\v{#AppVersion}
OutputBaseFilename=TomatoNotes-v{#AppVersion}-Windows-x64-setup
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog
SetupIconFile=Windows\TomatoNotes\Assets\AppIcon.ico
UninstallDisplayIcon={app}\TomatoNotes.exe
DisableProgramGroupPage=yes
CloseApplications=yes
RestartApplications=no
VersionInfoVersion={#AppVersion}.0
VersionInfoDescription=番茄小记 Windows 安装程序
LicenseFile=Windows\Packaging\安装说明.txt

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务："

[Files]
Source: "{#PublishDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\番茄小记"; Filename: "{app}\TomatoNotes.exe"
Name: "{autodesktop}\番茄小记"; Filename: "{app}\TomatoNotes.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\TomatoNotes.exe"; Description: "启动番茄小记"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "powershell.exe"; Parameters: "-NoProfile -Command ""& '{app}\TomatoNotes.exe' --shutdown; Wait-Process -Name TomatoNotes -Timeout 15 -ErrorAction SilentlyContinue; if (Get-Process -Name TomatoNotes -ErrorAction SilentlyContinue) {{ exit 1 }}"""; Flags: runhidden waituntilterminated; RunOnceId: "StopTomatoNotes"
