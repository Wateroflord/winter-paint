; Установщик Winter Paint для Windows (Inno Setup 6), ставится в профиль пользователя.
#define BuildNo GetEnv("BUILD_NO")
#if BuildNo == ""
  #define BuildNo "0"
#endif

[Setup]
AppId={{1C99F9EE-7957-4E42-B843-4200C98651BE}
AppName=Winter Paint
AppVersion=1.0.{#BuildNo}
AppPublisher=Winter Hub
DefaultDirName={localappdata}\Programs\Winter Paint
DefaultGroupName=Winter Paint
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=Winter-Paint-Setup
Compression=lzma2
SolidCompression=yes
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\winter_paint.exe
CloseApplications=force
RestartApplications=no
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Winter Paint"; Filename: "{app}\winter_paint.exe"
Name: "{group}\{cm:UninstallProgram,Winter Paint}"; Filename: "{uninstallexe}"
Name: "{userdesktop}\Winter Paint"; Filename: "{app}\winter_paint.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\winter_paint.exe"; Description: "{cm:LaunchProgram,Winter Paint}"; Flags: nowait postinstall skipifsilent
Filename: "{app}\winter_paint.exe"; Flags: nowait; Check: WizardSilent
