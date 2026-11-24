; Inno Setup script for the Windows installer.
;
;   iscc /DAppVersion=0.1.0 /DArch=x64compatible /DArchLabel=x64 \
;        /DSourceDir=..\..\build\windows\x64\runner\Release amped.iss
;
; Arch is Inno Setup's name for the architecture (x64compatible or arm64),
; ArchLabel what the installer's file name says.
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef Arch
  #define Arch "x64compatible"
#endif
#ifndef ArchLabel
  #define ArchLabel "x64"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{6E0C2B7D-5D43-4A57-9B1B-2C8D8D3F1A90}
AppName=Amped
AppVersion={#AppVersion}
AppPublisher=Hans Kokx
DefaultDirName={autopf}\Amped
DefaultGroupName=Amped
UninstallDisplayIcon={app}\amped.exe
SetupIconFile=..\runner\resources\app_icon.ico
OutputDir=..\..\build\installer
OutputBaseFilename=Amped-{#AppVersion}-windows-{#ArchLabel}-setup
ArchitecturesAllowed={#Arch}
ArchitecturesInstallIn64BitMode={#Arch}
Compression=lzma2
SolidCompression=yes
PrivilegesRequiredOverridesAllowed=dialog
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\Amped"; Filename: "{app}\amped.exe"
Name: "{autodesktop}\Amped"; Filename: "{app}\amped.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\amped.exe"; Description: "Start Amped"; Flags: nowait postinstall skipifsilent
