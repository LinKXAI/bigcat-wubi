[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$failures = [System.Collections.Generic.List[string]]::new()
$assertionCount = 0

function Assert-InstallerInvariant {
    param(
        [bool]$Condition,
        [string]$Message
    )

    $script:assertionCount++
    if (-not $Condition) {
        $script:failures.Add($Message)
    }
}

$relativeRequiredFiles = @(
    'installer\windows\BigCatWubi.iss',
    'installer\windows\VERSION',
    'scripts\Build-WindowsInstaller.ps1',
    'scripts\Get-WindowsInstallerVersion.ps1',
    'scripts\DaMao.InnoCompiler.ps1',
    'scripts\DaMao.WindowsInstallerDependencies.ps1',
    'scripts\Install-DaMao.ps1',
    'scripts\DaMao.Common.ps1',
    'scripts\DaMao.InstallerState.ps1',
    'scripts\Bootstrap-Weasel.ps1',
    'scripts\Uninstall-BigCat.ps1',
    'schemas\damao_wubi.schema.yaml',
    'assets\branding\windows\bigcat.ico',
    'assets\branding\windows\bigcat-ime.ico',
    'dependencies\windows-installer-v2.lock.json',
    'third_party\weasel\0.17.4\weasel-0.17.4.0-installer.exe',
    'third_party\weasel\0.17.4\LICENSE.txt',
    'third_party\weasel\0.17.4\UPSTREAM.md',
    'third_party\rime\rime-wubi\LICENSE',
    'third_party\rime\rime-wubi\README.md',
    'third_party\rime\rime-wubi\wubi86.dict.yaml',
    'third_party\rime\rime-wubi\wubi86.schema.yaml',
    'third_party\rime\rime-wubi\UPSTREAM.md',
    'LICENSE'
)
foreach ($relativePath in $relativeRequiredFiles) {
    Assert-InstallerInvariant -Condition (Test-Path -LiteralPath (Join-Path $repoRoot $relativePath) -PathType Leaf) `
        -Message "Required Windows installer file is missing: $relativePath"
}

$installerPath = Join-Path $repoRoot 'installer\windows\BigCatWubi.iss'
$buildScriptPath = Join-Path $repoRoot 'scripts\Build-WindowsInstaller.ps1'
$compilerSupportPath = Join-Path $repoRoot 'scripts\DaMao.InnoCompiler.ps1'
$bootstrapPath = Join-Path $repoRoot 'scripts\Bootstrap-Weasel.ps1'
$installScriptPath = Join-Path $repoRoot 'scripts\Install-DaMao.ps1'
$schemaPath = Join-Path $repoRoot 'schemas\damao_wubi.schema.yaml'
$applicationIconPath = Join-Path $repoRoot 'assets\branding\windows\bigcat.ico'
$imeIconPath = Join-Path $repoRoot 'assets\branding\windows\bigcat-ime.ico'
if ((Test-Path -LiteralPath $installerPath -PathType Leaf) -and
    (Test-Path -LiteralPath $buildScriptPath -PathType Leaf) -and
    (Test-Path -LiteralPath $compilerSupportPath -PathType Leaf) -and
    (Test-Path -LiteralPath $bootstrapPath -PathType Leaf)) {
    $installer = [System.IO.File]::ReadAllText($installerPath)
    $buildScript = [System.IO.File]::ReadAllText($buildScriptPath)
    $compilerSupport = [System.IO.File]::ReadAllText($compilerSupportPath)
    $bootstrap = [System.IO.File]::ReadAllText($bootstrapPath)
    $installScript = [System.IO.File]::ReadAllText($installScriptPath)
    $schema = [System.IO.File]::ReadAllText($schemaPath)
    $installerDirectory = Split-Path -Parent $installerPath

    $installerBytes = [System.IO.File]::ReadAllBytes($installerPath)
    $strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
    $installerIsUtf8 = $true
    try {
        $null = $strictUtf8.GetString($installerBytes)
    }
    catch {
        $installerIsUtf8 = $false
    }
    $installerHasUtf8Bom = $installerBytes.Length -ge 3 -and
        $installerBytes[0] -eq 0xEF -and
        $installerBytes[1] -eq 0xBB -and
        $installerBytes[2] -eq 0xBF
    Assert-InstallerInvariant ($installerIsUtf8 -and -not $installerHasUtf8Bom) `
        'The installer source must remain valid BOM-less UTF-8.'

    Assert-InstallerInvariant ($installer -match '(?m)^AppId=\{\{3F30C1BD-EA7C-4D57-91F2-A8C7894909D4\}\s*$') `
        'The committed stable Windows installer AppId changed or is missing.'
    Assert-InstallerInvariant ($installer -match '(?m)^AppName=\{#MyAppName\}\s*$' -and
        $installer -match '(?m)^#define MyAppName "\u5927\u732b\u4e94\u7b14"\s*$') `
        'The installer does not use the approved Chinese product name.'
    Assert-InstallerInvariant ($installer -match '(?m)^#include "VERSION"\s*$' -and
        $buildScript -match "installer\\windows\\VERSION") `
        'The installer version is not supplied from installer/windows/VERSION.'
    Assert-InstallerInvariant ($installer -match '(?m)^AppVersion=\{#MyAppVersion\}\s*$' -and
        $installer -match '(?m)^AppVerName=\{#MyAppName\} \{#MyAppVersion\}\s*$' -and
        $installer -notmatch '(?m)^UninstallDisplayName=') `
        'Setup and the default uninstall DisplayName/DisplayVersion must use the human-readable version.'
    Assert-InstallerInvariant ($installer -match '(?m)^VersionInfoVersion=\{#MyAppNumericVersion\}\s*$' -and
        $installer -match '(?m)^VersionInfoProductVersion=\{#MyAppNumericVersion\}\s*$' -and
        $installer -match '(?m)^VersionInfoProductTextVersion=\{#MyAppVersion\}\s*$') `
        'Setup must separate numeric Windows file/product resources from the human-readable product version.'
    $releaseWorkflow = [System.IO.File]::ReadAllText((Join-Path $repoRoot '.github\workflows\build-windows-release.yml'))
    Assert-InstallerInvariant ($buildScript -match 'Get-WindowsInstallerVersion\.ps1' -and
        $buildScript -match '\$packageVersion = & \$versionReader -VersionPath \$versionSource' -and
        $releaseWorkflow -match '\$version = & ./scripts/Get-WindowsInstallerVersion\.ps1') `
        'Build and build metadata must use the shared VERSION reader.'
    foreach ($field in @('releaseTag', 'displayVersion', 'numericVersion')) {
        Assert-InstallerInvariant ($releaseWorkflow -match ('(?mi)^\s+' + $field + ' = \$version\.' + $field + '\s*$')) `
            "Build metadata must record $field from VERSION."
    }
    Assert-InstallerInvariant ($installer -match '(?m)^PrivilegesRequired=lowest\s*$') `
        'The Windows installer must remain a non-administrator per-user install.'
    Assert-InstallerInvariant ($installer -match '(?m)^DefaultDirName=\{localappdata\}\\Programs\\BigCatWubi\s*$') `
        'The Windows installer does not use the approved per-user install root.'
    Assert-InstallerInvariant ($installer -match '(?m)^OutputDir=\.\.\\\.\.\\dist\\windows\s*$') `
        'The Inno output directory must be the repository dist/windows directory.'
    Assert-InstallerInvariant ($installer -match '(?m)^OutputBaseFilename=\{#MyAppExeName\}\s*$' -and
        $installer -match '(?m)^#define MyAppExeName "BigCatWubi-Setup"\s*$') `
        'The setup executable name must remain BigCatWubi-Setup.exe.'
    Assert-InstallerInvariant ($installer -match '(?m)^SetupIconFile=\.\.\\\.\.\\assets\\branding\\windows\\bigcat\.ico\s*$') `
        'The Setup executable does not reference the authoritative BigCat icon.'
    Assert-InstallerInvariant ((Get-FileHash -LiteralPath $applicationIconPath -Algorithm SHA256).Hash -ceq
        '7A23C402C236A8516CFC89CFCE387BB1528C02BC7EC0E6796C763452C732F2C3') `
        'The authoritative installer/application icon was modified.'
    Assert-InstallerInvariant ($schema -match '(?m)^\s*icon:\s*damao_wubi/branding/bigcat-ime\.ico\s*$' -and
        $schema -match '(?m)^\s*ascii_icon:\s*damao_wubi/branding/bigcat-ime\.ico\s*$') `
        'The formal BigCat schema must use the IME-specific cat-head icon in Chinese and ASCII modes.'
    Assert-InstallerInvariant ($installScript -match "assets\\branding\\windows\\bigcat-ime\.ico" -and
        $installScript -match "damao_wubi\\branding\\bigcat-ime\.ico" -and
        $installer -match '(?m)^Source: "\.\.\\\.\.\\assets\\branding\\windows\\bigcat-ime\.ico"; DestDir: "\{app\}\\assets\\branding\\windows";') `
        'The build payload and V1 deployment must connect the packaged IME icon to the schema-relative user-data path.'
    $imeIconBytes = [System.IO.File]::ReadAllBytes($imeIconPath)
    $imeIconEntryCount = if ($imeIconBytes.Length -ge 6) {
        [System.BitConverter]::ToUInt16($imeIconBytes, 4)
    }
    else {
        0
    }
    $imeIconWidths = @()
    for ($entryIndex = 0; $entryIndex -lt $imeIconEntryCount; $entryIndex++) {
        $entryOffset = 6 + (16 * $entryIndex)
        if (($entryOffset + 15) -ge $imeIconBytes.Length) {
            break
        }
        $entryWidth = [int]$imeIconBytes[$entryOffset]
        $imeIconWidths += $(if ($entryWidth -eq 0) { 256 } else { $entryWidth })
    }
    Assert-InstallerInvariant ($imeIconBytes.Length -ge 6 -and
        [System.BitConverter]::ToUInt16($imeIconBytes, 0) -eq 0 -and
        [System.BitConverter]::ToUInt16($imeIconBytes, 2) -eq 1 -and
        $imeIconEntryCount -eq 9) `
        'The dedicated IME asset is not the expected nine-frame Windows ICO.'
    Assert-InstallerInvariant (($imeIconWidths -contains 16) -and
        ($imeIconWidths -contains 20) -and
        ($imeIconWidths -contains 24)) `
        'The dedicated IME icon must contain native 16, 20, and 24 pixel frames.'
    Assert-InstallerInvariant ((Get-FileHash -LiteralPath $imeIconPath -Algorithm SHA256).Hash -cne
        (Get-FileHash -LiteralPath $applicationIconPath -Algorithm SHA256).Hash) `
        'The schema icon must be a dedicated asset rather than the installer/application icon.'
    Assert-InstallerInvariant ($installer -match '(?m)^UninstallDisplayIcon=\{app\}\\assets\\branding\\windows\\bigcat\.ico\s*$') `
        'The Installed Apps/uninstall entry does not use the installed authoritative icon.'
    Assert-InstallerInvariant ($installer -match '(?ms)^\[LangOptions\].*?^DialogFontName=Microsoft YaHei UI\s*$' -and
        $installer -match '(?ms)^\[LangOptions\].*?^WelcomeFontName=Microsoft YaHei UI\s*$') `
        'The Setup/uninstall dialog and welcome fonts must use a Simplified-Chinese-capable Windows UI font.'
    Assert-InstallerInvariant ([regex]::Matches($installer,
        '(?m)^Name:.*IconFilename: "\{app\}\\assets\\branding\\windows\\bigcat\.ico"').Count -eq 2) `
        'Both meaningful redeploy shortcuts must use the authoritative BigCat icon.'
    Assert-InstallerInvariant ($installer -match '(?m)^Name: "\{autoprograms\}.*- \u91cd\u65b0\u90e8\u7f72";') `
        'The Start Menu redeploy shortcut is missing.'
    Assert-InstallerInvariant ($installer -match '(?m)^Name: "\{autodesktop\}.*Tasks: desktopicon\s*$') `
        'The optional Desktop redeploy shortcut is missing or not task-gated.'
    Assert-InstallerInvariant ($installer -match '(?m)^Name: "desktopicon";.*Flags: unchecked\s*$') `
        'The Desktop shortcut task must be optional and unchecked by default.'
    Assert-InstallerInvariant ($installer -match '-WindowStyle Hidden -File' -and
        [regex]::Matches($installer, '-WindowStyle Hidden').Count -eq 4 -and
        $installer -match '\{app\}\\scripts\\Bootstrap-Weasel\.ps1' -and
        $bootstrap -match '& \$installScript @installParameters' -and
        $bootstrap -match '\$installParameters\.InitializeFreshRimeState\s*=\s*\$true') `
        'The automatic Setup/uninstall helpers must remain hidden and Setup must route through the bootstrap gate into authoritative V1 deployment.'
    Assert-InstallerInvariant ($bootstrap -match '(?s)Test-DaMaoFreshRimeUserState.*?Get-ChildItem[^\r\n]*-Force.*?\.Count -eq 0' -and
        $bootstrap -match '(?s)\$initializeFreshRimeState\s*=\s*Test-DaMaoFreshRimeUserState.*?Invoke-DaMaoWeaselBootstrapFlow') `
        'Installer-driven freshness must mean missing or zero-entry Rime data captured before Weasel runs.'
    Assert-InstallerInvariant ($installScript -match 'InitializeFreshRimeState' -and
        $compilerSupport -notmatch 'InitializeFreshRimeState' -and
        $installer -notmatch 'InitializeFreshRimeState' -and
        [System.IO.File]::ReadAllText((Join-Path $repoRoot 'scripts\DaMao.Common.ps1')) -match 'schema_list/@before 0') `
        'Fresh-only schema initialization must stay inside the bootstrap/V1 boundary and use the supported prepend operation.'
    Assert-InstallerInvariant (($bootstrap + $installScript) -notmatch '(?im)(?:Set-Content|WriteAllText|Copy-Item|Move-Item|Remove-Item)[^\r\n]*user\.yaml') `
        'Fresh schema initialization must never mutate user.yaml directly.'
    Assert-InstallerInvariant ($installer -match '(?s)Exec\(PowerShellPath, Parameters, ExpandConstant\(''\{app\}''\),\s+SW_HIDE, ewWaitUntilTerminated, ResultCode\)') `
        'The automatic Setup-time deployment must run synchronously with its PowerShell window hidden.'
    Assert-InstallerInvariant ([regex]::Matches($installer,
        '(?m)^Name: "\{auto(?:programs|desktop)\}.*Filename: "\{sys\}\\WindowsPowerShell\\v1\.0\\powershell\.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -NoExit -File .* -UserFacingRedeploy";.*$').Count -eq 2 -and
        $installer -notmatch '(?m)^Name: "\{auto(?:programs|desktop)\}.*-WindowStyle Hidden') `
        'Both user-initiated redeploy shortcuts must use the concise formatter while remaining visible with -NoExit and no hidden-window option.'
    Assert-InstallerInvariant ($installer -notmatch '(?s)Parameters := .*UserFacingRedeploy.*?Exec\(PowerShellPath') `
        'The automatic Setup deployment must bypass the user-facing redeploy formatter and preserve machine-readable failure behavior.'
    Assert-InstallerInvariant ($installer -match 'ewWaitUntilTerminated' -and
        $installer -match 'ResultCode <> 0' -and
        $installer -match 'RecordDeploymentFailure') `
        'A non-zero PowerShell deployment result must enter the explicit failure path.'
    Assert-InstallerInvariant ($installer -notmatch 'RaiseException') `
        'Expected deployment failures must not use an uncaught exception or Runtime error UX.'
    Assert-InstallerInvariant ($installer -match '(?s)procedure CurPageChanged.*?CurPageID = wpFinished.*?DeploymentFailed.*?FinishedHeadingLabel\.Caption.*?FinishedLabel\.Caption' -and
        $installer -match '(?s)function GetCustomSetupExitCode.*?if DeploymentFailed then.*?Result := DeploymentExitCode.*?else.*?Result := 0') `
        'Deployment failure must show an explicit unsuccessful final state and return a non-zero Setup exit code.'
    Assert-InstallerInvariant ($installer -match '\u5927\u732b\u4e94\u7b14\u5b89\u88c5\u6587\u4ef6\u5df2\u5b8c\u6210\u5b89\u88c5\uff0c\u4f46\u8f93\u5165\u6cd5\u90e8\u7f72\u672a\u5b8c\u6210' -and
        $installer -match '\u95ee\u9898\u89e3\u51b3\u540e\uff0c\u53ef\u4ece\u5f00\u59cb\u83dc\u5355\u8fd0\u884c\u201c\u5927\u732b\u4e94\u7b14\u0020\u002d\u0020\u91cd\u65b0\u90e8\u7f72\u201d' -and
        $installer -match "FinishedHeadingLabel\.Caption := '\u8f93\u5165\u6cd5\u90e8\u7f72\u672a\u5b8c\u6210'") `
        'The failure UX must distinguish the installed package from incomplete deployment and identify the redeploy action.'
    Assert-InstallerInvariant ($installer -match '(?s)if CurStep = ssPostInstall then\s+RunBigCatDeployment' -and
        $installer -match '(?s)if ResultCode <> 0 then.*?RecordDeploymentFailure' -and
        $installer -notmatch '(?s)if ResultCode = 0 then.*?RecordDeploymentFailure') `
        'The successful post-install orchestration point must remain unchanged.'
    Assert-InstallerInvariant ($installer -notmatch '(?im)^\[Registry\]|Rime\\Weasel|default\.custom\.yaml') `
        'The Inno layer must not edit Rime registry/configuration state directly.'
    Assert-InstallerInvariant ($installer -notmatch '(?i)WeaselServer\.exe|WeaselDeployer\.exe|rime\.dll') `
        'The Inno source directly references a third-party Weasel/Rime binary.'
    Assert-InstallerInvariant ($installer -match '(?m)^Source: "\.\.\\\.\.\\third_party\\weasel\\0\.17\.4\\weasel-0\.17\.4\.0-installer\.exe"; Flags: dontcopy noencryption\s*$') `
        'The official Weasel installer must be embedded as an extraction-only payload.'
    Assert-InstallerInvariant ([regex]::Matches($installer, 'ExtractTemporaryFile\(').Count -eq 1 -and
        $installer -match '(?s)10:\s+begin.*?ExtractTemporaryFile\(' -and
        $installer -match '(?s)0:\s+begin.*?bundled Weasel installer will not be extracted or run.*?end;\s+10:') `
        'The bundled Weasel installer must be extracted only after an Absent probe result.'
    Assert-InstallerInvariant ($installer -match '" -ProbeOnly''' -and
        $installer -match '(?s)case ResultCode of\s+0:.*?10:.*?25:') `
        'Inno must classify Weasel before choosing whether to extract the bundled installer.'
    Assert-InstallerInvariant ($installer -match '(?s)0:\s+begin.*?-BundledWubiSourcePath.*?end;\s+10:' -and
        $installer -match '(?s)10:\s+begin.*?-BundledWeaselInstallerPath.*?-BundledWubiSourcePath') `
        'Both installer branches must use bundled Wubi, while only the absent branch receives bundled Weasel.'
    Assert-InstallerInvariant ([regex]::Matches($installer, '(?m)^Name: "\{auto(?:programs|desktop)\}.*-WubiSourcePath ""\{app\}\\third_party\\rime\\rime-wubi"".*$').Count -eq 2) `
        'Both user-facing redeploy shortcuts must use the bundled Wubi source.'
    Assert-InstallerInvariant (($installer + $bootstrap) -notmatch '(?i)Invoke-WebRequest|Start-BitsTransfer|System\.Net\.WebClient') `
        'The production installer/bootstrap path must not depend on a live download.'
    $stateSupport = [System.IO.File]::ReadAllText((Join-Path $repoRoot 'scripts\DaMao.InstallerState.ps1'))
    $uninstallSupport = [System.IO.File]::ReadAllText((Join-Path $repoRoot 'scripts\Uninstall-BigCat.ps1'))
    Assert-InstallerInvariant ($installer -match '(?s)function ReadTrustedWeaselOrigin.*?format_version''.*?<> ''1''.*?function InitializeSetup.*?ReadTrustedWeaselOrigin.*?PreviousBigCatInstall' -and
        $installer -match '-ExistingWeaselOrigin' -and $installer -match '-LegacyInstallPresent' -and
        $bootstrap -match 'Resolve-DaMaoWeaselOrigin' -and $bootstrap -match 'Set-DaMaoInstallerProvenance') `
        'Setup does not capture, preserve, and persist Weasel provenance before bootstrap/deployment.'
    Assert-InstallerInvariant ($stateSupport -match "BigCatBootstrap.*PreExisting.*UnknownLegacy" -and
        $stateSupport -match '\[installer\]' -and $stateSupport -match 'format_version=' -and
        $stateSupport -match 'weasel_origin=' -and $stateSupport -match 'rime_user_dir=') `
        'The versioned installer-state.ini provenance contract is incomplete.'
    Assert-InstallerInvariant ($installer -match '(?s)function InitializeUninstall.*?ShowWeaselUninstallOptions' -and
        $installer -match 'TNewCheckBox' -and $installer -match "WeaselCheckBox\.Checked := UninstallWeaselOrigin = 'BigCatBootstrap'" -and
        $installer -match "UninstallWeaselOrigin <> 'BigCatBootstrap'" -and
        $installer -match '\u53ef\u80fd\u5f71\u54cd\u5176\u4ed6 Rime \u8f93\u5165\u65b9\u6848') `
        'The uninstall UI is not a provenance-aware checkbox with conservative confirmation.'
    Assert-InstallerInvariant ($uninstallSupport -match 'Remove-DaMaoSchemaSelection' -and
        $uninstallSupport -match 'Find-DaMaoWeaselUninstallCommand' -and
        $uninstallSupport -match 'Get-DaMaoWeaselUninstallRegistryEntries' -and
        $uninstallSupport -notmatch 'DeleteTree|APPDATA.*Rime.*(?:Recurse|Force)') `
        'The uninstall helper does not use targeted config cleanup and registered Weasel uninstall discovery.'
    Assert-InstallerInvariant ($uninstallSupport -match 'WEASEL_SERVER_QUIT_TIMEOUT_CONTINUING' -and
        $uninstallSupport -match 'function Get-DaMaoBigCatUninstallExitCode' -and
        $uninstallSupport -notmatch 'WEASEL_CLEANUP_PREPARE_FAILED') `
        'A WeaselServer /quit timeout is not represented as a continuing diagnostic before result aggregation.'

    $sourceMatches = [regex]::Matches($installer, '(?m)^Source:\s*"(?<path>[^"]+)";')
    $actualSources = @()
    foreach ($sourceMatch in $sourceMatches) {
        $sourcePath = $sourceMatch.Groups['path'].Value
        $resolvedSource = [System.IO.Path]::GetFullPath((Join-Path $installerDirectory $sourcePath))
        $actualSources += $resolvedSource
        Assert-InstallerInvariant (Test-Path -LiteralPath $resolvedSource -PathType Leaf) `
            "Inno [Files] source does not exist: $sourcePath"
    }

    $expectedSources = @(
        'scripts\Install-DaMao.ps1',
        'scripts\DaMao.Common.ps1',
        'scripts\DaMao.InstallerState.ps1',
        'scripts\Bootstrap-Weasel.ps1',
        'scripts\Uninstall-BigCat.ps1',
        'schemas\damao_wubi.schema.yaml',
        'assets\branding\windows\bigcat.ico',
        'assets\branding\windows\bigcat-ime.ico',
        'third_party\weasel\0.17.4\weasel-0.17.4.0-installer.exe',
        'third_party\weasel\0.17.4\LICENSE.txt',
        'third_party\weasel\0.17.4\UPSTREAM.md',
        'third_party\rime\rime-wubi\LICENSE',
        'third_party\rime\rime-wubi\README.md',
        'third_party\rime\rime-wubi\wubi86.dict.yaml',
        'third_party\rime\rime-wubi\wubi86.schema.yaml',
        'third_party\rime\rime-wubi\UPSTREAM.md',
        'dependencies\windows-installer-v2.lock.json',
        'LICENSE'
    ) | ForEach-Object { [System.IO.Path]::GetFullPath((Join-Path $repoRoot $_)) }
    Assert-InstallerInvariant ((($actualSources | Sort-Object) -join "`n") -ceq (($expectedSources | Sort-Object) -join "`n")) `
        'The packaged payload is not the exact minimal approved file set.'

    $resolvedOutput = [System.IO.Path]::GetFullPath((Join-Path $installerDirectory '..\..\dist\windows'))
    $sourceDirectories = @('installer', 'scripts', 'schemas', 'assets', 'tests') |
        ForEach-Object { [System.IO.Path]::GetFullPath((Join-Path $repoRoot $_)).TrimEnd('\') + '\' }
    Assert-InstallerInvariant ($resolvedOutput -eq [System.IO.Path]::GetFullPath((Join-Path $repoRoot 'dist\windows'))) `
        'The resolved Inno output path is not dist/windows.'
    foreach ($sourceDirectory in $sourceDirectories) {
        Assert-InstallerInvariant (-not ($resolvedOutput.TrimEnd('\') + '\').StartsWith(
            $sourceDirectory, [System.StringComparison]::OrdinalIgnoreCase)) `
            "The generated installer output path is inside a source directory: $sourceDirectory"
    }

    Assert-InstallerInvariant ($compilerSupport -match "Get-Command 'ISCC\.exe'" -and
        $compilerSupport -match 'DM-INNO-NOT-FOUND' -and
        $buildScript -match '\$LASTEXITCODE -ne 0') `
        'The build wrapper does not locate ISCC and fail clearly on compiler errors.'
    Assert-InstallerInvariant (($buildScript + $compilerSupport) -notmatch '(?i)Invoke-WebRequest|Start-BitsTransfer|winget|choco|scoop') `
        'The build wrapper must not download or install Inno Setup automatically.'
    Assert-InstallerInvariant ($buildScript -match 'Test-DaMaoWindowsInstallerDependencyLock' -and
        $buildScript -match 'windows-installer-v2\.lock\.json') `
        'The real build must verify the pinned third-party dependency lock before compilation.'

    . (Join-Path $repoRoot 'scripts\DaMao.WindowsInstallerDependencies.ps1')
    $verifiedDependencies = @(Test-DaMaoWindowsInstallerDependencyLock -RepoRoot $repoRoot)
    Assert-InstallerInvariant ($verifiedDependencies.Count -eq 6) `
        'The dependency lock must verify the Weasel binary/license and four exact rime-wubi files.'
    $verifiedWeasel = $verifiedDependencies | Where-Object { $_.Path -like '*weasel-0.17.4.0-installer.exe' }
    Assert-InstallerInvariant ($verifiedWeasel.Size -eq 12431118 -and
        $verifiedWeasel.SHA256 -ceq 'CF509534A8F5F8AF9C98ED7CBB8F135439F145A8CBE7E50EDE42BB5B5AB45C29') `
        'The bundled official Weasel asset does not match its pinned identity.'

    . $compilerSupportPath

    $inno71 = Resolve-DaMaoISCCVersion `
        -CommandVersionOutput '7.1.0' `
        -CommandVersionExitCode 0 `
        -ProductVersion '0.0.0.0' `
        -FileVersion '0.0.0.0'
    Assert-InstallerInvariant ($null -ne $inno71 -and
        $inno71.Version -eq [version]'7.1.0.0' -and
        $inno71.DetectionMethod -eq '--version' -and
        (Test-DaMaoISCCVersionSupported -Version $inno71.Version)) `
        'Inno Setup 7.1.0 from --version must override zeroed PE VersionInfo and be accepted.'

    $inno6Fallback = Resolve-DaMaoISCCVersion `
        -CommandVersionOutput 'Unrecognized option: --version' `
        -CommandVersionExitCode 1 `
        -ProductVersion '6.3.3.0' `
        -FileVersion '6.3.3.0'
    Assert-InstallerInvariant ($null -ne $inno6Fallback -and
        $inno6Fallback.Version -eq [version]'6.3.3.0' -and
        $inno6Fallback.DetectionMethod -eq 'ProductVersion' -and
        (Test-DaMaoISCCVersionSupported -Version $inno6Fallback.Version)) `
        'The Inno Setup 6 PE VersionInfo fallback must remain valid when --version is unsupported.'

    $inno6FileVersionFallback = Resolve-DaMaoISCCVersion `
        -CommandVersionOutput $null `
        -CommandVersionExitCode 1 `
        -ProductVersion '0.0.0.0' `
        -FileVersion '6.3.3.0'
    Assert-InstallerInvariant ($null -ne $inno6FileVersionFallback -and
        $inno6FileVersionFallback.Version -eq [version]'6.3.3.0' -and
        $inno6FileVersionFallback.DetectionMethod -eq 'FileVersion') `
        'A zeroed ProductVersion must not hide a valid Inno Setup 6 FileVersion fallback.'

    $unsupportedInno6 = Resolve-DaMaoISCCVersion `
        -CommandVersionOutput $null `
        -CommandVersionExitCode 1 `
        -ProductVersion '6.2.2.0' `
        -FileVersion '6.2.2.0'
    Assert-InstallerInvariant ($null -ne $unsupportedInno6 -and
        -not (Test-DaMaoISCCVersionSupported -Version $unsupportedInno6.Version)) `
        'Unsupported Inno Setup versions must fail closed.'
    Assert-InstallerInvariant (-not (Test-DaMaoISCCVersionSupported -Version ([version]'0.0.0.0'))) `
        'Zeroed PE VersionInfo must not be accepted as a supported compiler version.'

    $candidatePaths = @(Get-DaMaoISCCCandidatePaths -ProgramFilesRoots @(
        'C:\Program Files',
        'C:\Program Files (x86)'
    ))
    Assert-InstallerInvariant ($candidatePaths -contains 'C:\Program Files\Inno Setup 7\ISCC.exe') `
        'Inno Setup 7 under 64-bit Program Files is missing from compiler auto-discovery.'
    Assert-InstallerInvariant ($candidatePaths -contains 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe') `
        'The existing Inno Setup 6 compiler discovery path was not preserved.'

    $explicitPathTestRoot = Join-Path ([System.IO.Path]::GetTempPath()) "damao-iscc-path-$([Guid]::NewGuid().ToString('N'))"
    try {
        $explicitCompiler = Join-Path $explicitPathTestRoot 'ISCC.exe'
        New-Item -ItemType Directory -Path $explicitPathTestRoot -Force | Out-Null
        [System.IO.File]::WriteAllText($explicitCompiler, '')
        $resolvedExplicitCompiler = Find-DaMaoISCC -ExplicitPath $explicitCompiler
        Assert-InstallerInvariant ($resolvedExplicitCompiler -eq [System.IO.Path]::GetFullPath($explicitCompiler)) `
            'An explicit -ISCCPath must remain supported.'
    }
    finally {
        if (Test-Path -LiteralPath $explicitPathTestRoot) {
            Remove-Item -LiteralPath $explicitPathTestRoot -Recurse -Force
        }
    }
}

$versionPath = Join-Path $repoRoot 'installer\windows\VERSION'
if (Test-Path -LiteralPath $versionPath -PathType Leaf) {
    $versionContent = [System.IO.File]::ReadAllText($versionPath)
    $versionReader = Join-Path $repoRoot 'scripts\Get-WindowsInstallerVersion.ps1'
    $defaultVersion = & $versionReader
    $version = & $versionReader -VersionPath $versionPath
    Assert-InstallerInvariant (($defaultVersion | ConvertTo-Json -Compress) -ceq
        ($version | ConvertTo-Json -Compress)) `
        'The default VERSION path must work in both supported PowerShell hosts.'
    Assert-InstallerInvariant ($version.ReleaseTag -ceq 'v0.9.0-rc1' -and
        $version.DisplayVersion -ceq '0.9.0 RC1' -and
        $version.NumericVersion -ceq '0.9.0.0') `
        'The first public release must remain v0.9.0-rc1 / 0.9.0 RC1 / 0.9.0.0.'

    $versionTestRoot = Join-Path ([System.IO.Path]::GetTempPath()) "bigcat-version-tests-$([Guid]::NewGuid().ToString('N'))"
    try {
        New-Item -ItemType Directory -Path $versionTestRoot | Out-Null
        $fixturePath = Join-Path $versionTestRoot 'VERSION'
        $invalidVersions = @(
            ($versionContent.Replace('0.9.0 RC1', '0.1.0')),
            ($versionContent.Replace('0.9.0.0', '0.9.0-rc1')),
            ($versionContent.Replace('0.9.0.0', '0.9.0')),
            ($versionContent.Replace('v0.9.0-rc1', 'v0.9.0-rc2')),
            ($versionContent.Replace('v0.9.0-rc1', 'v0.9.0 RC1')),
            ($versionContent.Replace('0.9.0', '65536.9.0')),
            ($versionContent + "`n#define MyAppVersion `"0.9.0 RC1`"`n"),
            ([regex]::Replace($versionContent, '(?m)^#define MyAppNumericVersion[^\r\n]*\r?\n?', '')),
            ($versionContent + "`n#include `"unexpected.iss`"`n")
        )
        foreach ($invalidVersion in $invalidVersions) {
            [System.IO.File]::WriteAllText($fixturePath, $invalidVersion)
            $rejected = $false
            try { $null = & $versionReader -VersionPath $fixturePath }
            catch { $rejected = $_.Exception.Message -like '[[]DM-INNO-VERSION-INVALID[]]*' }
            Assert-InstallerInvariant $rejected 'Invalid, inconsistent, missing or duplicated VERSION metadata must fail closed.'
        }
        [System.IO.File]::WriteAllText($fixturePath, $versionContent.Replace('-rc1', '').Replace(' RC1', ''))
        $stableVersion = & $versionReader -VersionPath $fixturePath
        Assert-InstallerInvariant ($stableVersion.ReleaseTag -ceq 'v0.9.0' -and
            $stableVersion.DisplayVersion -ceq '0.9.0' -and
            $stableVersion.NumericVersion -ceq '0.9.0.0') `
            'The version reader must also support a consistent stable release.'
    }
    finally {
        if (Test-Path -LiteralPath $versionTestRoot) {
            Remove-Item -LiteralPath $versionTestRoot -Recurse -Force
        }
    }
}

if ($failures.Count -gt 0) {
    throw "Windows installer static validation failed:`n - $($failures -join "`n - ")"
}

Write-Host "Windows installer static tests passed ($assertionCount assertions)."
