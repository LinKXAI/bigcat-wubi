#include "VERSION"
#ifdef QuanpinCandidate
  #undef MyAppVersion
  #undef MyAppNumericVersion
  #define MyAppVersion "0.9.1 Dev 3 - Quanpin candidate"
  #define MyAppNumericVersion "0.9.1.3"
#endif

#define MyAppName "大猫五笔"
#define MyAppEnglishName "BigCat Wubi"
#define MyAppExeName "BigCatWubi-Setup"
#define MyBundledWeaselInstaller "weasel-0.17.4.0-installer.exe"

[Setup]
AppId={{3F30C1BD-EA7C-4D57-91F2-A8C7894909D4}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
DefaultDirName={localappdata}\Programs\BigCatWubi
DefaultGroupName={#MyAppName}
PrivilegesRequired=lowest
DisableProgramGroupPage=yes
OutputDir=..\..\dist\windows
OutputBaseFilename={#MyAppExeName}
SetupIconFile=..\..\assets\branding\windows\bigcat.ico
UninstallDisplayIcon={app}\assets\branding\windows\bigcat.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupLogging=yes
VersionInfoDescription={#MyAppEnglishName} Setup
VersionInfoProductName={#MyAppEnglishName}
VersionInfoVersion={#MyAppNumericVersion}
VersionInfoProductVersion={#MyAppNumericVersion}
VersionInfoProductTextVersion={#MyAppVersion}

[LangOptions]
DialogFontName=Microsoft YaHei UI
WelcomeFontName=Microsoft YaHei UI

[Tasks]
Name: "desktopicon"; Description: "创建“大猫五笔 - 重新部署”桌面快捷方式"; GroupDescription: "附加快捷方式："; Flags: unchecked

[Files]
Source: "..\..\scripts\Check-QuanpinSharedPolicy.ps1"; DestDir: "{app}\scripts"; Flags: ignoreversion
; Keep the large temporary payload first for efficient solid-stream extraction.
Source: "..\..\third_party\weasel\0.17.4\weasel-0.17.4.0-installer.exe"; Flags: dontcopy noencryption
Source: "..\..\scripts\Install-DaMao.ps1"; DestDir: "{app}\scripts"; Flags: ignoreversion
Source: "..\..\scripts\DaMao.Common.ps1"; DestDir: "{app}\scripts"; Flags: ignoreversion
Source: "..\..\scripts\DaMao.InstallerState.ps1"; DestDir: "{app}\scripts"; Flags: ignoreversion
Source: "..\..\scripts\Bootstrap-Weasel.ps1"; DestDir: "{app}\scripts"; Flags: ignoreversion
Source: "..\..\scripts\Uninstall-BigCat.ps1"; DestDir: "{app}\scripts"; Flags: ignoreversion
Source: "..\..\schemas\damao_wubi.schema.yaml"; DestDir: "{app}\schemas"; Flags: ignoreversion
Source: "..\..\assets\branding\windows\bigcat.ico"; DestDir: "{app}\assets\branding\windows"; Flags: ignoreversion
Source: "..\..\assets\branding\windows\bigcat-ime.ico"; DestDir: "{app}\assets\branding\windows"; Flags: ignoreversion
Source: "..\..\third_party\weasel\0.17.4\LICENSE.txt"; DestDir: "{app}\third_party\weasel\0.17.4"; Flags: ignoreversion
Source: "..\..\third_party\weasel\0.17.4\UPSTREAM.md"; DestDir: "{app}\third_party\weasel\0.17.4"; Flags: ignoreversion
Source: "..\..\third_party\rime\rime-wubi\LICENSE"; DestDir: "{app}\third_party\rime\rime-wubi"; Flags: ignoreversion
Source: "..\..\third_party\rime\rime-wubi\README.md"; DestDir: "{app}\third_party\rime\rime-wubi"; Flags: ignoreversion
Source: "..\..\third_party\rime\rime-wubi\wubi86.dict.yaml"; DestDir: "{app}\third_party\rime\rime-wubi"; Flags: ignoreversion
Source: "..\..\third_party\rime\rime-wubi\wubi86.schema.yaml"; DestDir: "{app}\third_party\rime\rime-wubi"; Flags: ignoreversion
Source: "..\..\third_party\rime\rime-wubi\UPSTREAM.md"; DestDir: "{app}\third_party\rime\rime-wubi"; Flags: ignoreversion
Source: "..\..\dependencies\windows-installer-v2.lock.json"; DestDir: "{app}\dependencies"; Flags: ignoreversion
Source: "..\..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion

Source: "..\..\scripts\DaMao.Quanpin.ps1"; DestDir: "{app}\scripts"; Flags: ignoreversion
Source: "..\..\scripts\Install-DaMaoWithQuanpin.ps1"; DestDir: "{app}\scripts"; Flags: ignoreversion
Source: "..\..\schemas\luna_quanpin.custom.yaml"; DestDir: "{app}\schemas"; Flags: ignoreversion
Source: "..\..\dependencies\quanpin.lock.json"; DestDir: "{app}\dependencies"; Flags: ignoreversion
Source: "..\..\third_party\rime\quanpin-weasel-0.17.4\default.yaml"; DestDir: "{app}\third_party\rime\quanpin-weasel-0.17.4"; Flags: ignoreversion
Source: "..\..\third_party\rime\quanpin-weasel-0.17.4\essay.txt"; DestDir: "{app}\third_party\rime\quanpin-weasel-0.17.4"; Flags: ignoreversion
Source: "..\..\third_party\rime\quanpin-weasel-0.17.4\key_bindings.yaml"; DestDir: "{app}\third_party\rime\quanpin-weasel-0.17.4"; Flags: ignoreversion
Source: "..\..\third_party\rime\quanpin-weasel-0.17.4\LICENSE.GPL-3.0.txt"; DestDir: "{app}\third_party\rime\quanpin-weasel-0.17.4"; Flags: ignoreversion
Source: "..\..\third_party\rime\quanpin-weasel-0.17.4\LICENSE.LGPL-3.0.txt"; DestDir: "{app}\third_party\rime\quanpin-weasel-0.17.4"; Flags: ignoreversion
Source: "..\..\third_party\rime\quanpin-weasel-0.17.4\luna_pinyin.dict.yaml"; DestDir: "{app}\third_party\rime\quanpin-weasel-0.17.4"; Flags: ignoreversion
Source: "..\..\third_party\rime\quanpin-weasel-0.17.4\luna_pinyin.schema.yaml"; DestDir: "{app}\third_party\rime\quanpin-weasel-0.17.4"; Flags: ignoreversion
Source: "..\..\third_party\rime\quanpin-weasel-0.17.4\luna_quanpin.schema.yaml"; DestDir: "{app}\third_party\rime\quanpin-weasel-0.17.4"; Flags: ignoreversion
Source: "..\..\third_party\rime\quanpin-weasel-0.17.4\opencc\t2s.json"; DestDir: "{app}\third_party\rime\quanpin-weasel-0.17.4\opencc"; Flags: ignoreversion
Source: "..\..\third_party\rime\quanpin-weasel-0.17.4\opencc\TSCharacters.ocd2"; DestDir: "{app}\third_party\rime\quanpin-weasel-0.17.4\opencc"; Flags: ignoreversion
Source: "..\..\third_party\rime\quanpin-weasel-0.17.4\opencc\TSPhrases.ocd2"; DestDir: "{app}\third_party\rime\quanpin-weasel-0.17.4\opencc"; Flags: ignoreversion
Source: "..\..\third_party\rime\quanpin-weasel-0.17.4\pinyin.yaml"; DestDir: "{app}\third_party\rime\quanpin-weasel-0.17.4"; Flags: ignoreversion
Source: "..\..\third_party\rime\quanpin-weasel-0.17.4\punctuation.yaml"; DestDir: "{app}\third_party\rime\quanpin-weasel-0.17.4"; Flags: ignoreversion
Source: "..\..\third_party\rime\quanpin-weasel-0.17.4\stroke.dict.yaml"; DestDir: "{app}\third_party\rime\quanpin-weasel-0.17.4"; Flags: ignoreversion
Source: "..\..\third_party\rime\quanpin-weasel-0.17.4\stroke.schema.yaml"; DestDir: "{app}\third_party\rime\quanpin-weasel-0.17.4"; Flags: ignoreversion
Source: "..\..\third_party\rime\quanpin-weasel-0.17.4\symbols.yaml"; DestDir: "{app}\third_party\rime\quanpin-weasel-0.17.4"; Flags: ignoreversion
Source: "..\..\third_party\rime\quanpin-weasel-0.17.4\UPSTREAM.md"; DestDir: "{app}\third_party\rime\quanpin-weasel-0.17.4"; Flags: ignoreversion

Source: "..\..\third_party\rime\quanpin-weasel-0.17.4\LICENSE.Apache-2.0.txt"; DestDir: "{app}\third_party\rime\quanpin-weasel-0.17.4"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#MyAppName}\{#MyAppName} - 重新部署"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -NoExit -File ""{app}\scripts\Install-DaMaoWithQuanpin.ps1"" -InstallWubiDependency -WubiSourcePath ""{app}\third_party\rime\rime-wubi"" -UserFacingRedeploy"; WorkingDir: "{app}"; IconFilename: "{app}\assets\branding\windows\bigcat.ico"; Comment: "通过大猫五笔安全安装脚本重新部署 Rime 配置"
Name: "{autodesktop}\{#MyAppName} - 重新部署"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -NoExit -File ""{app}\scripts\Install-DaMaoWithQuanpin.ps1"" -InstallWubiDependency -WubiSourcePath ""{app}\third_party\rime\rime-wubi"" -UserFacingRedeploy"; WorkingDir: "{app}"; IconFilename: "{app}\assets\branding\windows\bigcat.ico"; Comment: "通过大猫五笔安全安装脚本重新部署 Rime 配置"; Tasks: desktopicon

[UninstallDelete]
Type: files; Name: "{app}\installer-state.ini"

[Code]
var
  EntryPage: TInputOptionWizardPage;
  ExistingRimeEnvironment: Boolean;
  DeploymentFailed: Boolean;
  DeploymentExitCode: Integer;
  DeploymentFailureMessage: String;
  PreviousBigCatInstall: Boolean;
  PreservedWeaselOrigin: String;
  UninstallWeaselRequested: Boolean;
  UninstallWeaselOrigin: String;

function IsTrustedWeaselOrigin(const Origin: String): Boolean;
begin
  Result := (Origin = 'BigCatBootstrap') or (Origin = 'PreExisting') or
    (Origin = 'UnknownLegacy');
end;

function ReadTrustedWeaselOrigin(const StatePath: String): String;
begin
  Result := GetIniString('installer', 'weasel_origin', '', StatePath);
  if (GetIniString('installer', 'format_version', '', StatePath) <> '1') or
    (not IsTrustedWeaselOrigin(Result)) then
    Result := '';
end;

function InitializeSetup: Boolean;
var
  PreviousAppDir: String;
  StatePath: String;
begin
  PreviousAppDir := ExpandConstant('{localappdata}\Programs\BigCatWubi');
  RegQueryStringValue(HKCU,
    'Software\Microsoft\Windows\CurrentVersion\Uninstall\{3F30C1BD-EA7C-4D57-91F2-A8C7894909D4}_is1',
    'InstallLocation', PreviousAppDir);
  StatePath := AddBackslash(PreviousAppDir) + 'installer-state.ini';
  PreservedWeaselOrigin := ReadTrustedWeaselOrigin(StatePath);
  PreviousBigCatInstall := IsTrustedWeaselOrigin(PreservedWeaselOrigin) or
    FileExists(AddBackslash(PreviousAppDir) + 'unins000.exe') or
    RegKeyExists(HKCU,
      'Software\Microsoft\Windows\CurrentVersion\Uninstall\{3F30C1BD-EA7C-4D57-91F2-A8C7894909D4}_is1');
  Result := True;
end;

procedure InitializeWizard;
var
  UserDir: String;
  RegistryUserDir: String;
  Entry: TFindRec;
begin
  UserDir := ExpandConstant('{userappdata}\Rime');
  if RegQueryStringValue(HKCU, 'Software\Rime\Weasel', 'RimeUserDir', RegistryUserDir) and
    (Trim(RegistryUserDir) <> '') then UserDir := RegistryUserDir;
  UserDir := ExpandFileName(UserDir);
  ExistingRimeEnvironment := False;
  if FindFirst(AddBackslash(UserDir) + '*', Entry) then
  begin
    try
      repeat
        if (Entry.Name <> '.') and (Entry.Name <> '..') then
          ExistingRimeEnvironment := True;
      until not FindNext(Entry);
    finally
      FindClose(Entry);
    end;
  end;
  EntryPage := CreateInputOptionPage(wpSelectDir, '首次默认输入方案',
    '同时安装五笔与全拼',
    '全拼默认简体，可切换繁体。大猫五笔备份工具不包含拼音学习数据。', True, False);
  if ExistingRimeEnvironment then
  begin
    EntryPage.Add('保留当前方案、已有方案顺序和用户设置');
    EntryPage.Values[0] := True;
    EntryPage.CheckListBox.Enabled := False;
  end
  else
  begin
    EntryPage.Add('五笔（默认）');
    EntryPage.Add('拼音（全拼）');
    EntryPage.Values[0] := True;
  end;
end;

function GetBootstrapStateParameters: String;
begin
  Result := ' -InstallerStatePath "' +
    ExpandConstant('{app}\installer-state.ini') + '"';
  if not ExistingRimeEnvironment then
    if EntryPage.Values[1] then
      Result := Result + ' -DefaultEntry Pinyin';
  if IsTrustedWeaselOrigin(PreservedWeaselOrigin) then
    Result := Result + ' -ExistingWeaselOrigin "' + PreservedWeaselOrigin + '"';
  if PreviousBigCatInstall then
    Result := Result + ' -LegacyInstallPresent';
end;

procedure RecordDeploymentFailure(const FailureMessage: String;
  const ExitCode: Integer);
begin
  DeploymentFailed := True;
  DeploymentExitCode := ExitCode;
  DeploymentFailureMessage := FailureMessage;

  Log(Format('BigCat deployment did not complete (exit/error code %d).', [ExitCode]));
  MsgBox(FailureMessage, mbError, MB_OK);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
  Parameters: String;
begin
  Result := '';
  { Stage only the read-only guard and policy before Setup writes application files. }
  ExtractTemporaryFile('Check-QuanpinSharedPolicy.ps1');
  ExtractTemporaryFile('DaMao.Common.ps1');
  ExtractTemporaryFile('DaMao.Quanpin.ps1');
  ExtractTemporaryFile('luna_quanpin.custom.yaml');
  Parameters := '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' +
    ExpandConstant('{tmp}\Check-QuanpinSharedPolicy.ps1') + '" -PolicyPath "' +
    ExpandConstant('{tmp}\luna_quanpin.custom.yaml') + '"';
  if not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    Parameters, ExpandConstant('{tmp}'), SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    Result := '无法执行全拼共享配置检查，安装未开始。'
  else if ResultCode <> 0 then
    Result := '[DM-PINYIN-SHARED-POLICY-CONFLICT] 检测到共享全拼定制或无法安全检查。' +
      '安装已停止，未修改现有配置。请核对小狼毫共享 data\luna_quanpin.custom.yaml；不要直接删除个人定制。';
end;

procedure RunBigCatDeployment;
var
  ResultCode: Integer;
  PowerShellPath: String;
  ScriptPath: String;
  WubiSourcePath: String;
  BundledWeaselPath: String;
  Parameters: String;
  StateParameters: String;
begin
  PowerShellPath := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  ScriptPath := ExpandConstant('{app}\scripts\Bootstrap-Weasel.ps1');
  WubiSourcePath := ExpandConstant('{app}\third_party\rime\rime-wubi');
  StateParameters := GetBootstrapStateParameters;
  Parameters := '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + ScriptPath +
    '" -ProbeOnly';

  Log('Probing Weasel state before conditionally extracting the bundled installer.');
  if not Exec(PowerShellPath, Parameters, ExpandConstant('{app}'),
    SW_HIDE, ewWaitUntilTerminated, ResultCode) then
  begin
    RecordDeploymentFailure(
      '大猫五笔安装文件已完成安装，但输入法部署未能启动。'#13#10#13#10 +
      '无法启动 Windows PowerShell。请查看安装日志中的错误信息。'#13#10#13#10 +
      '问题解决后，可重新运行大猫五笔安装程序。'#13#10#13#10 +
      Format('系统错误代码：%d（%s）', [ResultCode, SysErrorMessage(ResultCode)]),
      ResultCode);
    exit;
  end;

  case ResultCode of
    0:
      begin
        Log('Usable Weasel exists; bundled Weasel installer will not be extracted or run.');
        Parameters := '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' +
          ScriptPath + '" -BundledWubiSourcePath "' + WubiSourcePath + '"' +
          StateParameters;
      end;
    10:
      begin
        Log('Weasel is absent; extracting the bundled pinned installer to Setup temporary storage.');
        ExtractTemporaryFile('{#MyBundledWeaselInstaller}');
        BundledWeaselPath := ExpandConstant('{tmp}\{#MyBundledWeaselInstaller}');
        Parameters := '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' +
          ScriptPath + '" -BundledWeaselInstallerPath "' + BundledWeaselPath +
          '" -BundledWubiSourcePath "' + WubiSourcePath + '"' + StateParameters;
      end;
    25:
      begin
        RecordDeploymentFailure(
          '检测到已有小狼毫安装信息，但现有安装缺少部署所需文件。'#13#10#13#10 +
          '为避免覆盖、升级或降级现有安装，自动安装已停止。请先修复现有小狼毫。',
          ResultCode);
        exit;
      end;
  else
    RecordDeploymentFailure(
      '无法可靠判断小狼毫（Weasel）的安装状态。'#13#10#13#10 +
      '为避免改变现有安装，大猫五笔输入法尚未部署。'#13#10#13#10 +
      Format('探测进程退出代码：%d', [ResultCode]),
      ResultCode);
    exit;
  end;

  Log('Invoking the offline Weasel gate and authoritative BigCat PowerShell installer.');
  if not Exec(PowerShellPath, Parameters, ExpandConstant('{app}'),
    SW_HIDE, ewWaitUntilTerminated, ResultCode) then
  begin
    RecordDeploymentFailure(
      '大猫五笔安装文件已完成安装，但输入法部署未能启动。'#13#10#13#10 +
      '无法启动 Windows PowerShell。请查看安装日志中的错误信息。'#13#10#13#10 +
      Format('系统错误代码：%d（%s）', [ResultCode, SysErrorMessage(ResultCode)]),
      ResultCode);
    exit;
  end;

  if ResultCode <> 0 then
  begin
    case ResultCode of
      21:
        RecordDeploymentFailure(
          '安装大猫五笔需要小狼毫（Weasel），但内置的官方安装包无法安全提取。'#13#10#13#10 +
          '大猫五笔输入法尚未部署。请重新获取完整的大猫五笔安装程序。',
          ResultCode);
      22:
        RecordDeploymentFailure(
          '小狼毫官方安装包未通过 SHA-256 完整性验证。'#13#10#13#10 +
          '为保证安全，该文件没有运行，大猫五笔输入法也尚未部署。',
          ResultCode);
      23:
        RecordDeploymentFailure(
          '小狼毫官方安装程序未能正常完成。'#13#10#13#10 +
          '大猫五笔输入法尚未部署。请查看安装日志后重试。',
          ResultCode);
      24:
        RecordDeploymentFailure(
          '小狼毫安装程序已经返回，但系统中仍未发现可用的小狼毫。'#13#10#13#10 +
          '大猫五笔输入法尚未部署。请检查小狼毫安装状态后重试。',
          ResultCode);
      25:
        RecordDeploymentFailure(
          '检测到已有小狼毫安装信息，但现有安装缺少部署所需文件。'#13#10#13#10 +
          '为避免覆盖、升级或降级现有安装，自动安装已停止。请先修复现有小狼毫。',
          ResultCode);
      26:
        RecordDeploymentFailure(
          '内置的五笔依赖源码缺失或未通过验证。'#13#10#13#10 +
          '为避免不完整部署，大猫五笔输入法尚未写入 Rime 用户目录。请重新获取完整安装程序。',
          ResultCode);
    else
      RecordDeploymentFailure(
        '大猫五笔安装文件已完成安装，但输入法部署未完成。'#13#10#13#10 +
        '请根据部署错误信息检查小狼毫（Weasel）及相关依赖。'#13#10 +
        '问题解决后，可从开始菜单运行“大猫五笔 - 重新部署”。'#13#10#13#10 +
        Format('部署进程退出代码：%d', [ResultCode]),
        ResultCode);
    end;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
    RunBigCatDeployment;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if (CurPageID = wpFinished) and DeploymentFailed then
  begin
    WizardForm.FinishedHeadingLabel.Caption := '输入法部署未完成';
    WizardForm.FinishedLabel.Caption := DeploymentFailureMessage;
    WizardForm.NextButton.Caption := '关闭';
    WizardForm.RunList.Visible := False;
  end;
end;

function GetCustomSetupExitCode: Integer;
begin
  if DeploymentFailed then
    Result := DeploymentExitCode
  else
    Result := 0;
end;

function ShowWeaselUninstallOptions: Boolean;
var
  OptionsForm: TSetupForm;
  PromptLabel: TNewStaticText;
  DetailLabel: TNewStaticText;
  WeaselCheckBox: TNewCheckBox;
  OkButton: TNewButton;
  CancelButton: TNewButton;
begin
  OptionsForm := CreateCustomForm(ScaleX(520), ScaleY(230), False, False);
  try
    OptionsForm.Caption := '卸载大猫五笔';

    PromptLabel := TNewStaticText.Create(OptionsForm);
    PromptLabel.Parent := OptionsForm;
    PromptLabel.Left := ScaleX(20);
    PromptLabel.Top := ScaleY(20);
    PromptLabel.Width := ScaleX(480);
    PromptLabel.AutoSize := False;
    PromptLabel.WordWrap := True;
    PromptLabel.Caption := '移除大猫五笔程序及五笔入口；保留个人学习数据、全拼和公共依赖。';

    WeaselCheckBox := TNewCheckBox.Create(OptionsForm);
    WeaselCheckBox.Parent := OptionsForm;
    WeaselCheckBox.Left := ScaleX(20);
    WeaselCheckBox.Top := ScaleY(65);
    WeaselCheckBox.Width := ScaleX(480);
    WeaselCheckBox.Caption := '同时卸载小狼毫';
    WeaselCheckBox.Checked := UninstallWeaselOrigin = 'BigCatBootstrap';

    DetailLabel := TNewStaticText.Create(OptionsForm);
    DetailLabel.Parent := OptionsForm;
    DetailLabel.Left := ScaleX(40);
    DetailLabel.Top := ScaleY(100);
    DetailLabel.Width := ScaleX(450);
    DetailLabel.Height := ScaleY(60);
    DetailLabel.AutoSize := False;
    DetailLabel.WordWrap := True;
    if UninstallWeaselOrigin = 'BigCatBootstrap' then
      DetailLabel.Caption :=
        '小狼毫由大猫五笔安装程序安装。若您不再使用其他 Rime 输入方案，建议一并卸载。'
    else if UninstallWeaselOrigin = 'PreExisting' then
      DetailLabel.Caption :=
        '检测到小狼毫在安装大猫五笔之前已经存在。保留它不会影响大猫五笔的卸载。'
    else
      DetailLabel.Caption :=
        '无法可靠确认小狼毫最初的安装来源，因此默认保留。';

    OkButton := TNewButton.Create(OptionsForm);
    OkButton.Parent := OptionsForm;
    OkButton.Width := ScaleX(90);
    OkButton.Height := ScaleY(28);
    OkButton.Left := OptionsForm.ClientWidth - ScaleX(200);
    OkButton.Top := OptionsForm.ClientHeight - ScaleY(48);
    OkButton.Caption := '继续';
    OkButton.Default := True;
    OkButton.ModalResult := mrOk;

    CancelButton := TNewButton.Create(OptionsForm);
    CancelButton.Parent := OptionsForm;
    CancelButton.Width := ScaleX(90);
    CancelButton.Height := ScaleY(28);
    CancelButton.Left := OptionsForm.ClientWidth - ScaleX(100);
    CancelButton.Top := OptionsForm.ClientHeight - ScaleY(48);
    CancelButton.Caption := '取消';
    CancelButton.Cancel := True;
    CancelButton.ModalResult := mrCancel;

    Result := OptionsForm.ShowModal = mrOk;
    if Result then
      UninstallWeaselRequested := WeaselCheckBox.Checked;
  finally
    OptionsForm.Free;
  end;
end;

function InitializeUninstall: Boolean;
begin
  UninstallWeaselOrigin := ReadTrustedWeaselOrigin(
    ExpandConstant('{app}\installer-state.ini'));
  if not IsTrustedWeaselOrigin(UninstallWeaselOrigin) then
    UninstallWeaselOrigin := 'UnknownLegacy';
  UninstallWeaselRequested := False;
  Result := ShowWeaselUninstallOptions;
  if Result and UninstallWeaselRequested and
    (UninstallWeaselOrigin <> 'BigCatBootstrap') then
  begin
    if MsgBox(
      '此小狼毫并非已确认由大猫五笔安装。继续卸载可能影响其他 Rime 输入方案。'#13#10#13#10 +
      '确定仍要同时卸载小狼毫吗？', mbConfirmation, MB_YESNO) <> IDYES then
      UninstallWeaselRequested := False;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  PowerShellPath: String;
  ScriptPath: String;
  Parameters: String;
  ResultCode: Integer;
begin
  if CurUninstallStep <> usUninstall then
    exit;

  PowerShellPath := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  ScriptPath := ExpandConstant('{app}\scripts\Uninstall-BigCat.ps1');
  Parameters := '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' +
    ScriptPath + '" -InstallerStatePath "' +
    ExpandConstant('{app}\installer-state.ini') + '"';
  if UninstallWeaselRequested then
    Parameters := Parameters + ' -RemoveWeasel';

  if not Exec(PowerShellPath, Parameters, ExpandConstant('{app}'), SW_HIDE,
    ewWaitUntilTerminated, ResultCode) then
  begin
    MsgBox(
      '大猫五笔的卸载清理程序未能启动。应用程序文件仍会继续卸载，但部分 Rime 数据可能需要手动清理。',
      mbError, MB_OK);
    exit;
  end;
  if ResultCode = 41 then
    MsgBox(
      '小狼毫未能完成卸载，大猫五笔已成功移除。若小狼毫仍在运行，已尝试重新部署剩余的 Rime 配置。',
      mbInformation, MB_OK)
  else if ResultCode <> 0 then
    MsgBox(
      '大猫五笔应用程序已移除，但部分 Rime 清理或重新部署步骤未能完成。详情请查看临时目录中的 BigCatWubi-uninstall.log。',
      mbInformation, MB_OK);
end;
