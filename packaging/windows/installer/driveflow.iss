#define AppName "DriveFlow"
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#define AppPublisher "DriveFlow"
#define AppExeName "driveflow.exe"

[Setup]
AppId={{9E9C4BA5-7634-4A13-9AA4-8A52B7C0179D}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\DriveFlow
DefaultGroupName=DriveFlow
OutputDir=..\..\..\build\installer
OutputBaseFilename=DriveFlow-Setup-v{#AppVersion}-x64
ArchitecturesInstallIn64BitMode=x64
ArchitecturesAllowed=x64
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
UninstallDisplayIcon={app}\{#AppExeName}

[Files]
Source: "..\..\..\apps\flutter_app\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\DriveFlow"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\DriveFlow"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional icons:"

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Launch DriveFlow"; Flags: nowait postinstall skipifsilent
