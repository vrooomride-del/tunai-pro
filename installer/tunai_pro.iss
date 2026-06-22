[Setup]
AppName=TUNAI Pro
AppVersion=1.0.0
AppPublisher=TUNAI
AppPublisherURL=https://tunai.app
AppSupportURL=https://tunai.app
AppUpdatesURL=https://tunai.app
DefaultDirName={autopf}\TUNAI Pro
DefaultGroupName=TUNAI Pro
AllowNoIcons=yes
OutputDir={#SourcePath}\output
OutputBaseFilename=TUNAIPro_Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupIconFile={#SourcePath}\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\tunai_pro.exe
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "startmenuicon"; Description: "Create Start Menu shortcut"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce

[Files]
Source: "{#SourcePath}\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#SourcePath}\vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{group}\TUNAI Pro"; Filename: "{app}\tunai_pro.exe"
Name: "{group}\{cm:UninstallProgram,TUNAI Pro}"; Filename: "{uninstallexe}"
Name: "{commondesktop}\TUNAI Pro"; Filename: "{app}\tunai_pro.exe"; Tasks: desktopicon

[Run]
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/passive /norestart"; StatusMsg: "Installing Visual C++ Redistributable..."; Flags: waituntilterminated
Filename: "{app}\tunai_pro.exe"; Description: "{cm:LaunchProgram,TUNAI Pro}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
