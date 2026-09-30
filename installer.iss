; Inno Setup Script for Antigravity Fleet Station
; High-performance, self-contained Windows installer for any user, any path, any PC.

#define MyAppName "Antigravity Fleet Station"
#define MyAppVersion "1.0.4"
#define MyAppPublisher "Antigravity Community Research"
#define MyAppURL "https://github.com/mohgomaa-art/antigravity-mobile"
#define MyAppExeName "antigravity_mobile.exe"

[Setup]
AppId={{C24F3169-E5C7-4A44-884A-95D0A1FF2872}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\Antigravity Fleet Station
DefaultGroupName=Antigravity Fleet Station
AllowNoIcons=yes
LicenseFile={#SourcePath}\LICENSE
InfoBeforeFile={#SourcePath}\DISCLAIMER.md
OutputDir={#SourcePath}\dist\release
OutputBaseFilename=Antigravity-FleetStation-Setup-v1.0.4
SetupIconFile={#SourcePath}\flutter_app\windows\runner\resources\app_icon.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog commandline
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=force
CloseApplicationsFilter=*.exe,*.dll
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Flutter Windows Release Core & Assets (Excludes bridge so it never duplicates)
Source: "{#SourcePath}\flutter_app\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "bridge,bridge\*"
; Bundled Standalone Python Bridge Gateway
Source: "{#SourcePath}\dist\antigravity_bridge\*"; DestDir: "{app}\bridge"; Flags: ignoreversion recursesubdirs createallsubdirs
; Bundled Cloudflare Quick Tunnel tool for worldwide remote access
Source: "{#SourcePath}\tools\cloudflared.exe"; DestDir: "{app}\tools"; Flags: ignoreversion
Source: "{#SourcePath}\tools\cloudflared.exe"; DestDir: "{app}\bridge"; Flags: ignoreversion
; Silent Firewall Setup Script
Source: "{#SourcePath}\tools\silent_firewall_setup.ps1"; DestDir: "{app}\tools"; Flags: ignoreversion
; Legal & Documentation Artifacts
Source: "{#SourcePath}\DISCLAIMER.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourcePath}\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourcePath}\README.md"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}\bridge"
Type: filesandordirs; Name: "{app}\tools"
Type: filesandordirs; Name: "{app}\data"
Type: files; Name: "{app}\*.log"
Type: files; Name: "{app}\*.json"
Type: files; Name: "{app}\*.tmp"
Type: files; Name: "{app}\*.txt"
Type: files; Name: "{app}\*.dll"

[UninstallRun]
Filename: "{sys}\taskkill.exe"; Parameters: "/F /T /IM {#MyAppExeName}"; Flags: runhidden
Filename: "{sys}\taskkill.exe"; Parameters: "/F /T /IM antigravity_bridge.exe"; Flags: runhidden
Filename: "{sys}\taskkill.exe"; Parameters: "/F /T /IM cloudflared.exe"; Flags: runhidden
Filename: "{sys}\taskkill.exe"; Parameters: "/F /T /IM adb.exe"; Flags: runhidden
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-ExecutionPolicy Bypass -NoProfile -File ""{app}\tools\silent_firewall_setup.ps1"" -Uninstall"; Flags: runhidden
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""Antigravity Fleet Station Port 8765"""; Flags: runhidden
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""Antigravity Fleet Station Port 8765 Out"""; Flags: runhidden
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""Antigravity Fleet Station UDP Beacon"""; Flags: runhidden
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""Antigravity Fleet Station UDP Beacon Out"""; Flags: runhidden
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""Antigravity Fleet Station UDP Beacon 8766"""; Flags: runhidden
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""Antigravity Fleet Station UDP Beacon 8766 Out"""; Flags: runhidden
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""Antigravity Fleet Station ADB Port"""; Flags: runhidden
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""Antigravity Fleet Station ADB Port Out"""; Flags: runhidden
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""Antigravity Fleet Station Bridge"""; Flags: runhidden
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""Antigravity Fleet Station Bridge Out"""; Flags: runhidden
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""Antigravity Fleet Station App"""; Flags: runhidden
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""Antigravity Fleet Station App Out"""; Flags: runhidden
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""Antigravity Fleet Station Cloudflared"""; Flags: runhidden
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""Antigravity Fleet Station Cloudflared Out"""; Flags: runhidden
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""Antigravity Fleet Station ADB"""; Flags: runhidden
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""Antigravity Fleet Station ADB Out"""; Flags: runhidden
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""Antigravity Fleet Station ADB Internal"""; Flags: runhidden
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""Antigravity Fleet Station ADB Internal Out"""; Flags: runhidden

[Code]
// Repeatedly taskkill process until verified gone
function ForceTerminateProcess(const ExeName: String): Boolean;
var
  ResultCode: Integer;
  i: Integer;
begin
  Result := True;
  for i := 1 to 5 do
  begin
    Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /T /IM ' + ExeName, '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    if ResultCode = 128 then
    begin
      Break;
    end;
    Sleep(250);
  end;
end;

procedure KillConflictingProcesses();
begin
  ForceTerminateProcess('{#MyAppExeName}');
  ForceTerminateProcess('antigravity_bridge.exe');
  ForceTerminateProcess('cloudflared.exe');
  ForceTerminateProcess('adb.exe');
  // Settle time for Windows file handles
  Sleep(1000);
end;

function SafeDelTree(const DirPath: String): Boolean;
var
  i: Integer;
begin
  Result := False;
  if not DirExists(DirPath) then
  begin
    Result := True;
    Exit;
  end;

  for i := 1 to 5 do
  begin
    if DelTree(DirPath, True, True, True) then
    begin
      Result := True;
      Exit;
    end;
    KillConflictingProcesses();
    Sleep(500);
  end;
end;

function InitializeSetup(): Boolean;
begin
  KillConflictingProcesses();
  Result := True;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  KillConflictingProcesses();
  SafeDelTree(ExpandConstant('{app}\bridge'));
  Result := '';
end;

function InitializeUninstall(): Boolean;
begin
  KillConflictingProcesses();
  Result := True;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ResultCode: Integer;
  AppPath: String;
begin
  if CurUninstallStep = usUninstall then
  begin
    KillConflictingProcesses();
    AppPath := ExpandConstant('{app}');
    if FileExists(AppPath + '\tools\silent_firewall_setup.ps1') then
    begin
      Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), '-ExecutionPolicy Bypass -NoProfile -File "' + AppPath + '\tools\silent_firewall_setup.ps1" -Uninstall', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    end;
  end;
  if CurUninstallStep = usPostUninstall then
  begin
    KillConflictingProcesses();
    SafeDelTree(ExpandConstant('{app}\bridge'));
    SafeDelTree(ExpandConstant('{app}\tools'));
    SafeDelTree(ExpandConstant('{app}\data'));
    SafeDelTree(ExpandConstant('{app}'));
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
  AppPath: String;
  BridgeExe: String;
  MainExe: String;
begin
  if CurStep = ssInstall then
  begin
    KillConflictingProcesses();
    SafeDelTree(ExpandConstant('{app}\bridge'));
  end;

  if CurStep = ssPostInstall then
  begin
    AppPath := ExpandConstant('{app}');
    BridgeExe := AppPath + '\bridge\antigravity_bridge.exe';
    MainExe := AppPath + '\{#MyAppExeName}';

    // 1. Run comprehensive PowerShell firewall setup script passing exact -InstallDir
    Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), '-ExecutionPolicy Bypass -NoProfile -File "' + AppPath + '\tools\silent_firewall_setup.ps1" -InstallDir "' + AppPath + '"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);

    // 2. Direct netsh fallback with absolute {sys} path to guarantee port 8765 is allowed on ALL profiles
    Exec(ExpandConstant('{sys}\netsh.exe'), 'advfirewall firewall delete rule name="Antigravity Fleet Station Port 8765"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec(ExpandConstant('{sys}\netsh.exe'), 'advfirewall firewall add rule name="Antigravity Fleet Station Port 8765" dir=in action=allow protocol=TCP localport=8765 profile=any', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec(ExpandConstant('{sys}\netsh.exe'), 'advfirewall firewall delete rule name="Antigravity Fleet Station Port 8765 Out"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec(ExpandConstant('{sys}\netsh.exe'), 'advfirewall firewall add rule name="Antigravity Fleet Station Port 8765 Out" dir=out action=allow protocol=TCP localport=8765 profile=any', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);

    // Allow ADB Port 5037 Inbound & Outbound on ALL profiles
    Exec(ExpandConstant('{sys}\netsh.exe'), 'advfirewall firewall delete rule name="Antigravity Fleet Station ADB Port"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec(ExpandConstant('{sys}\netsh.exe'), 'advfirewall firewall add rule name="Antigravity Fleet Station ADB Port" dir=in action=allow protocol=TCP localport=5037 profile=any', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);

    // Whitelist Bridge Gateway (Backend) - Inbound & Outbound
    Exec(ExpandConstant('{sys}\netsh.exe'), 'advfirewall firewall delete rule name="Antigravity Fleet Station Bridge"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec(ExpandConstant('{sys}\netsh.exe'), 'advfirewall firewall add rule name="Antigravity Fleet Station Bridge" dir=in action=allow program="' + BridgeExe + '" enable=yes profile=any', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec(ExpandConstant('{sys}\netsh.exe'), 'advfirewall firewall delete rule name="Antigravity Fleet Station Bridge Out"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec(ExpandConstant('{sys}\netsh.exe'), 'advfirewall firewall add rule name="Antigravity Fleet Station Bridge Out" dir=out action=allow program="' + BridgeExe + '" enable=yes profile=any', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);

    // Whitelist Frontend App - Inbound & Outbound
    Exec(ExpandConstant('{sys}\netsh.exe'), 'advfirewall firewall delete rule name="Antigravity Fleet Station App"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec(ExpandConstant('{sys}\netsh.exe'), 'advfirewall firewall add rule name="Antigravity Fleet Station App" dir=in action=allow program="' + MainExe + '" enable=yes profile=any', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec(ExpandConstant('{sys}\netsh.exe'), 'advfirewall firewall delete rule name="Antigravity Fleet Station App Out"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec(ExpandConstant('{sys}\netsh.exe'), 'advfirewall firewall add rule name="Antigravity Fleet Station App Out" dir=out action=allow program="' + MainExe + '" enable=yes profile=any', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);

    // Whitelist Cloudflared Tunnel Tool - Inbound & Outbound
    Exec(ExpandConstant('{sys}\netsh.exe'), 'advfirewall firewall delete rule name="Antigravity Fleet Station Cloudflared"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec(ExpandConstant('{sys}\netsh.exe'), 'advfirewall firewall add rule name="Antigravity Fleet Station Cloudflared" dir=in action=allow program="' + AppPath + '\tools\cloudflared.exe" enable=yes profile=any', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec(ExpandConstant('{sys}\netsh.exe'), 'advfirewall firewall delete rule name="Antigravity Fleet Station Cloudflared Out"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec(ExpandConstant('{sys}\netsh.exe'), 'advfirewall firewall add rule name="Antigravity Fleet Station Cloudflared Out" dir=out action=allow program="' + AppPath + '\tools\cloudflared.exe" enable=yes profile=any', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);

    // Whitelist Bundled ADB Daemon - Inbound & Outbound
    Exec(ExpandConstant('{sys}\netsh.exe'), 'advfirewall firewall delete rule name="Antigravity Fleet Station ADB"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec(ExpandConstant('{sys}\netsh.exe'), 'advfirewall firewall add rule name="Antigravity Fleet Station ADB" dir=in action=allow program="' + AppPath + '\bridge\adb.exe" enable=yes profile=any', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec(ExpandConstant('{sys}\netsh.exe'), 'advfirewall firewall delete rule name="Antigravity Fleet Station ADB Out"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec(ExpandConstant('{sys}\netsh.exe'), 'advfirewall firewall add rule name="Antigravity Fleet Station ADB Out" dir=out action=allow program="' + AppPath + '\bridge\adb.exe" enable=yes profile=any', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec(ExpandConstant('{sys}\netsh.exe'), 'advfirewall firewall delete rule name="Antigravity Fleet Station ADB Internal"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec(ExpandConstant('{sys}\netsh.exe'), 'advfirewall firewall add rule name="Antigravity Fleet Station ADB Internal" dir=in action=allow program="' + AppPath + '\bridge\_internal\adb.exe" enable=yes profile=any', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec(ExpandConstant('{sys}\netsh.exe'), 'advfirewall firewall delete rule name="Antigravity Fleet Station ADB Internal Out"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec(ExpandConstant('{sys}\netsh.exe'), 'advfirewall firewall add rule name="Antigravity Fleet Station ADB Internal Out" dir=out action=allow program="' + AppPath + '\bridge\_internal\adb.exe" enable=yes profile=any', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
end;
