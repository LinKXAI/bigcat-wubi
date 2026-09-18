[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$failures = [System.Collections.Generic.List[string]]::new()

$requiredFiles = @(
    'README.md',
    'LICENSE',
    'SECURITY.md',
    'CONTRIBUTING.md',
    'CODE_SIGNING.md',
    'CHANGELOG.md',
    'contracts/public-baseline-v1.json',
    'docs/architecture.md',
    'docs/roadmap.md',
    'docs/privacy-architecture.md',
    'docs/licensing.md',
    'docs/install-windows.md',
    'docs/user-data.md',
    'docs/manual-testing.md',
    'docs/rime-wubi-dependency.md',
    'docs/schema-deployment-diagnostics.md',
    'docs/windows-installer.md',
    'docs/signpath-readiness.md',
    'docs/userdb-portability-acceptance-baseline.md',
    '.github/workflows/validate.yml',
    '.github/workflows/build-windows-release.yml',
    'dependencies/windows-installer-v2.lock.json',
    'schemas/default.custom.yaml',
    'schemas/damao_wubi.schema.yaml',
    'assets/branding/windows/bigcat.ico',
    'assets/branding/windows/bigcat-ime.ico',
    'installer/windows/BigCatWubi.iss',
    'installer/windows/VERSION',
    'scripts/DaMao.Common.ps1',
    'scripts/DaMao.InstallerState.ps1',
    'scripts/Bootstrap-Weasel.ps1',
    'scripts/Install-DaMao.ps1',
    'scripts/Uninstall-BigCat.ps1',
    'scripts/Build-WindowsInstaller.ps1',
    'scripts/DaMao.WindowsInstallerDependencies.ps1',
    'scripts/DaMao.InnoCompiler.ps1',
    'scripts/Backup-DaMaoUserDictionary.ps1',
    'scripts/Restore-DaMaoUserDictionary.ps1',
    'scripts/Test-DaMaoEnvironment.ps1',
    'scripts/Test-DaMaoSchemaVariant.ps1',
    'tests/Run-DaMaoTests.ps1',
    'tests/Test-DaMaoRedeploy.ps1',
    'tests/Test-WindowsInstaller.ps1',
    'tests/Test-WeaselBootstrap.ps1',
    'tests/Test-InstallerUninstall.ps1',
    'third_party/weasel/0.17.4/weasel-0.17.4.0-installer.exe',
    'third_party/weasel/0.17.4/LICENSE.txt',
    'third_party/weasel/0.17.4/UPSTREAM.md',
    'third_party/rime/rime-wubi/LICENSE',
    'third_party/rime/rime-wubi/README.md',
    'third_party/rime/rime-wubi/wubi86.dict.yaml',
    'third_party/rime/rime-wubi/wubi86.schema.yaml',
    'third_party/rime/rime-wubi/UPSTREAM.md'
)

foreach ($relativePath in $requiredFiles) {
    $fullPath = Join-Path $repoRoot $relativePath
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        $failures.Add("Missing required file: $relativePath")
    }
}

$trackedFiles = Get-ChildItem -LiteralPath $repoRoot -Recurse -File |
    Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' }
$textExtensions = @('.md', '.yaml', '.yml', '.ps1', '.txt', '.iss')
$extensionlessTextFiles = @('.editorconfig', '.gitattributes', '.gitignore', 'LICENSE', 'VERSION')
$textFiles = $trackedFiles | Where-Object {
    ($_.Extension -in $textExtensions -or $_.Name -in $extensionlessTextFiles) -and
    ($_.FullName -notmatch '[\\/]third_party[\\/]' -or $_.Name -eq 'UPSTREAM.md')
}

foreach ($file in $textFiles) {
    $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $failures.Add("UTF-8 BOM is not allowed: $($file.FullName.Substring($repoRoot.Length + 1))")
    }

    $text = [System.IO.File]::ReadAllText($file.FullName)
    if ($text.Contains("`t")) {
        $failures.Add("Tab character found: $($file.FullName.Substring($repoRoot.Length + 1))")
    }
    if ($text -match '(?m)[ \t]+$') {
        $failures.Add("Trailing whitespace found: $($file.FullName.Substring($repoRoot.Length + 1))")
    }

    if ($file.Extension -eq '.md') {
        $relativeLinks = [regex]::Matches($text, '\[[^\]]+\]\((?!https?://|#)([^)]+)\)')
        foreach ($link in $relativeLinks) {
            $target = $link.Groups[1].Value.Split('#')[0]
            if ([string]::IsNullOrWhiteSpace($target)) {
                continue
            }
            $targetPath = Join-Path $file.DirectoryName $target
            if (-not (Test-Path -LiteralPath $targetPath)) {
                $source = $file.FullName.Substring($repoRoot.Length + 1)
                $failures.Add("Broken relative link in ${source}: $($link.Groups[1].Value)")
            }
        }
    }
}

$legacyTokens = @(
    ('modern' + '_' + 'wubi'),
    ('MODERN' + '_' + 'WUBI'),
    ('Modern' + ' Wubi'),
    ('Modern' + 'Wubi'),
    ('modern' + '-' + 'wubi'),
    ('M' + 'W-')
)
foreach ($file in $textFiles) {
    $text = [System.IO.File]::ReadAllText($file.FullName)
    foreach ($legacyToken in $legacyTokens) {
        if ($text.Contains($legacyToken)) {
            $failures.Add("Legacy project identifier '$legacyToken' found in $($file.FullName.Substring($repoRoot.Length + 1))")
        }
    }
}
foreach ($file in $trackedFiles) {
    foreach ($legacyToken in $legacyTokens) {
        if ($file.Name.IndexOf($legacyToken, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $failures.Add("Legacy project identifier found in file name: $($file.FullName.Substring($repoRoot.Length + 1))")
            break
        }
    }
}

$defaultConfig = [System.IO.File]::ReadAllText((Join-Path $repoRoot 'schemas/default.custom.yaml'))
$wubiConfig = [System.IO.File]::ReadAllText((Join-Path $repoRoot 'schemas/damao_wubi.schema.yaml'))
$installScript = [System.IO.File]::ReadAllText((Join-Path $repoRoot 'scripts/Install-DaMao.ps1'))
$commonScript = [System.IO.File]::ReadAllText((Join-Path $repoRoot 'scripts/DaMao.Common.ps1'))
$environmentScript = [System.IO.File]::ReadAllText((Join-Path $repoRoot 'scripts/Test-DaMaoEnvironment.ps1'))
$diagnosticScript = [System.IO.File]::ReadAllText((Join-Path $repoRoot 'scripts/Test-DaMaoSchemaVariant.ps1'))
$minimalDiagnostic = [System.IO.File]::ReadAllText((Join-Path $repoRoot 'schemas/diagnostics/damao_wubi.00-minimal.schema.yaml'))
$codeSigningPolicy = [System.IO.File]::ReadAllText((Join-Path $repoRoot 'CODE_SIGNING.md'))
$signPathReadiness = [System.IO.File]::ReadAllText((Join-Path $repoRoot 'docs/signpath-readiness.md'))
$releaseWorkflow = [System.IO.File]::ReadAllText((Join-Path $repoRoot '.github/workflows/build-windows-release.yml'))
$damaoDisplayName = -join @([char]0x5927, [char]0x732b, [char]0x8f93, [char]0x5165, [char]0x6cd5)
$damaoDisplayNamePattern = '(?m)^\s*name:\s*"{0}"\s*$' -f [regex]::Escape($damaoDisplayName)

$requiredPatterns = @(
    @{ Name = 'DaMao Input Method schema selection'; Text = $defaultConfig; Pattern = 'schema:\s*damao_wubi\b' },
    @{ Name = 'DaMao schema id'; Text = $wubiConfig; Pattern = '(?m)^\s*schema_id:\s*damao_wubi\s*$' },
    @{ Name = 'DaMao Chinese display name'; Text = $wubiConfig; Pattern = $damaoDisplayNamePattern },
    @{ Name = 'BigCat schema icon'; Text = $wubiConfig; Pattern = '(?m)^\s*icon:\s*damao_wubi/branding/bigcat-ime\.ico\s*$' },
    @{ Name = 'BigCat ASCII schema icon'; Text = $wubiConfig; Pattern = '(?m)^\s*ascii_icon:\s*damao_wubi/branding/bigcat-ime\.ico\s*$' },
    @{ Name = 'wubi86 dictionary dependency'; Text = $wubiConfig; Pattern = '(?m)^\s*dictionary:\s*wubi86\s*$' },
    @{ Name = 'isolated user dictionary'; Text = $wubiConfig; Pattern = '(?m)^\s*user_dict:\s*damao_wubi\s*$' },
    @{ Name = 'four-code Wubi limit'; Text = $wubiConfig; Pattern = '(?m)^\s*max_code_length:\s*4\s*$' },
    @{ Name = 'maximum-code auto selection'; Text = $wubiConfig; Pattern = '(?m)^\s*auto_select:\s*true\s*$' },
    @{ Name = 'local user dictionary enabled'; Text = $wubiConfig; Pattern = '(?m)^\s*enable_user_dict:\s*true\s*$' },
    @{ Name = 'sentence generation disabled'; Text = $wubiConfig; Pattern = '(?m)^\s*enable_sentence:\s*false\s*$' },
    @{ Name = 'phrase encoder disabled'; Text = $wubiConfig; Pattern = '(?m)^\s*enable_encoder:\s*false\s*$' },
    @{ Name = 'commit history encoding disabled'; Text = $wubiConfig; Pattern = '(?m)^\s*encode_commit_history:\s*false\s*$' },
    @{ Name = 'composing Return cancellation'; Text = $wubiConfig; Pattern = '(?m)^\s*-\s*\{\s*when:\s*composing,\s*accept:\s*Return,\s*send:\s*Escape\s*\}\s*$' },
    @{ Name = 'semicolon second-candidate shortcut'; Text = $wubiConfig; Pattern = '(?m)^\s*-\s*\{\s*when:\s*has_menu,\s*accept:\s*semicolon,\s*send:\s*2\s*\}\s*$' },
    @{ Name = 'apostrophe third-candidate shortcut'; Text = $wubiConfig; Pattern = '(?m)^\s*-\s*\{\s*when:\s*has_menu,\s*accept:\s*apostrophe,\s*send:\s*3\s*\}\s*$' },
    @{ Name = 'semicolon/apostrophe speller delimiter'; Text = $wubiConfig; Pattern = '(?m)^\s*delimiter:\s*" ;''"\s*$' },
    @{ Name = 'punctuation segmentor'; Text = $wubiConfig; Pattern = '(?m)^\s*-\s*punct_segmentor\s*$' },
    @{ Name = 'punctuation translator'; Text = $wubiConfig; Pattern = '(?m)^\s*-\s*punct_translator\s*$' },
    @{ Name = 'default punctuation preset'; Text = $wubiConfig; Pattern = '(?ms)^punctuator:\s*\r?\n\s+import_preset:\s*default\s*$' },
    @{ Name = 'default emacs key bindings retained'; Text = $wubiConfig; Pattern = 'key_bindings:/emacs_editing' },
    @{ Name = 'default word movement bindings retained'; Text = $wubiConfig; Pattern = 'key_bindings:/move_by_word_with_tab' },
    @{ Name = 'minus/equal paging bindings retained'; Text = $wubiConfig; Pattern = 'key_bindings:/paging_with_minus_equal' },
    @{ Name = 'numbered mode bindings retained'; Text = $wubiConfig; Pattern = 'key_bindings:/numbered_mode_switch' },
    @{ Name = 'offline wubi source parameter'; Text = $installScript; Pattern = '\$WubiSourcePath\b' },
    @{ Name = 'IME-specific schema icon source'; Text = $installScript; Pattern = "assets\\branding\\windows\\bigcat-ime\.ico" },
    @{ Name = 'schema-scoped IME icon destination'; Text = $installScript; Pattern = "damao_wubi\\branding\\bigcat-ime\.ico" },
    @{ Name = 'normal installer formal schema source'; Text = $installScript; Pattern = 'schemas\\damao_wubi\.schema\.yaml' },
    @{ Name = 'normal installer formal deployment validation'; Text = $installScript; Pattern = 'Assert-DaMaoFormalDeployment\s+-RimeUserDir\s+\$resolvedUserDir' },
    @{ Name = 'environment check PASS output'; Text = $environmentScript; Pattern = '''PASS''' },
    @{ Name = 'environment check overall success'; Text = $environmentScript; Pattern = 'Result: success' },
    @{ Name = 'environment check failure classification'; Text = $environmentScript; Pattern = 'DM-SMOKE-FAILED' },
    @{ Name = 'official rime-wubi clone source'; Text = $commonScript; Pattern = 'https://github\.com/rime/rime-wubi\.git' },
    @{ Name = 'existing-user schema list append operation'; Text = $commonScript; Pattern = '\$selectionKey\s*=\s*''"schema_list/\+":''' },
    @{ Name = 'fresh-only schema preference'; Text = $commonScript; Pattern = 'schema_list/@before 0' },
    @{ Name = 'fresh state installer boundary'; Text = $installScript; Pattern = '\$InitializeFreshRimeState' },
    @{ Name = 'deployment timeout classification'; Text = $commonScript; Pattern = 'DM-DEPLOY-TIMEOUT' },
    @{ Name = 'post-deployment default build verification'; Text = $commonScript; Pattern = 'build\\default\.yaml does not register damao_wubi' },
    @{ Name = 'deployment busy guard'; Text = $commonScript; Pattern = 'DM-DEPLOY-BUSY' },
    @{ Name = 'process-tree termination'; Text = $commonScript; Pattern = 'taskKill /PID \$Process\.Id /T /F' },
    @{ Name = 'deployer executable working directory'; Text = $commonScript; Pattern = '\$startInfo\.WorkingDirectory\s*=\s*Split-Path\s+-Parent\s+\$DeployerPath' },
    @{ Name = 'exact ProcessStartInfo arguments'; Text = $commonScript; Pattern = '\$startInfo\.Arguments\s*=\s*\$Command' },
    @{ Name = 'direct ProcessStartInfo launch'; Text = $commonScript; Pattern = '\[System\.Diagnostics\.Process\]::Start\(\$startInfo\)' },
    @{ Name = 'ordinal deploy command validation'; Text = $commonScript; Pattern = '\[string\]::Equals\(\$Command, ''/deploy'', \[System\.StringComparison\]::Ordinal\)' },
    @{ Name = 'deployer command diagnostics'; Text = $commonScript; Pattern = 'Command=\[\{0\}\] Length=\{1\} CodePoints=\[\{2\}\]' },
    @{ Name = 'direct deployer main-process wait'; Text = $commonScript; Pattern = '\$mainProcessExited\s*=\s*\$Process\.WaitForExit\(\$TimeoutSeconds\s*\*\s*1000\)' },
    @{ Name = 'minimal diagnostic control'; Text = $diagnosticScript; Pattern = '''00-minimal''' },
    @{ Name = 'full Alpha diagnostic variant'; Text = $diagnosticScript; Pattern = '''04-full-alpha''' },
    @{ Name = 'formal Alpha diagnostic source'; Text = $diagnosticScript; Pattern = 'Join-Path\s+\$repoRoot\s+''schemas\\damao_wubi\.schema\.yaml''' },
    @{ Name = 'full Alpha diagnostic projection'; Text = $diagnosticScript; Pattern = 'ConvertTo-DaMaoFullAlphaDiagnosticSchema\s+-SchemaContent\s+\$sourceContent' },
    @{ Name = 'structured diagnostic schema registration detection'; Text = $diagnosticScript; Pattern = 'Test-DaMaoSchemaRegistered\s+-DefaultCustomPath\s+\$defaultCustom' },
    @{ Name = 'old development schema cleanup'; Text = $commonScript; Pattern = '\$legacyProjectSchemaId\s*=\s*''modern''\s*\+\s*''_''\s*\+\s*''wubi''' },
    @{ Name = 'failed diagnostic schema restoration'; Text = $diagnosticScript; Pattern = 'restored the schema that was present before this test' },
    @{ Name = 'diagnostic target timestamp refresh'; Text = $diagnosticScript; Pattern = 'SetLastWriteTimeUtc\(\$targetSchema,\s*\[DateTime\]::UtcNow\)' },
    @{ Name = 'single diagnostic build invalidation'; Text = $diagnosticScript; Pattern = 'Remove-Item\s+-LiteralPath\s+\$builtSchema\s+-Force' },
    @{ Name = 'workspace deployment log verification'; Text = $diagnosticScript; Pattern = 'Assert-DaMaoWorkspaceDeploymentLog\s+-BeforeSnapshot\s+\$rimeLogSnapshot\s+-SchemaId\s+''damao_wubi''' },
    @{ Name = 'minimal control dictionary'; Text = $minimalDiagnostic; Pattern = '(?m)^\s*dictionary:\s*wubi86\s*$' }
    @{ Name = 'Code signing policy heading'; Text = $codeSigningPolicy; Pattern = '(?m)^# Code signing policy\s*$' },
    @{ Name = 'truthful current unsigned status'; Text = $codeSigningPolicy; Pattern = 'currently \*\*unsigned\*\*' },
    @{ Name = 'conditional SignPath attribution'; Text = $codeSigningPolicy; Pattern = 'Free code signing provided by SignPath\.io, certificate by SignPath Foundation' },
    @{ Name = 'signing Authors role'; Text = $codeSigningPolicy; Pattern = '\*\*Authors:\*\*' },
    @{ Name = 'signing Reviewers role'; Text = $codeSigningPolicy; Pattern = '\*\*Reviewers:\*\*' },
    @{ Name = 'signing Approvers role'; Text = $codeSigningPolicy; Pattern = '\*\*Approvers:\*\*' },
    @{ Name = 'signing MFA requirement'; Text = $codeSigningPolicy; Pattern = 'multi-factor\s+authentication \(MFA\)' },
    @{ Name = 'release page policy snippet'; Text = $signPathReadiness; Pattern = 'Code signing policy:' },
    @{ Name = 'manual unsigned release workflow'; Text = $releaseWorkflow; Pattern = '(?m)^\s{2}workflow_dispatch:\s*$' },
    @{ Name = 'GitHub-hosted Windows release build'; Text = $releaseWorkflow; Pattern = '(?m)^\s{4}runs-on:\s*windows-latest\s*$' },
    @{ Name = 'pinned Inno Setup release source'; Text = $releaseWorkflow; Pattern = 'releases/download/is-7_1_0/innosetup-7\.1\.0-x64\.exe' },
    @{ Name = 'pinned Inno Setup SHA-256'; Text = $releaseWorkflow; Pattern = '0362A383ED217D4C4239B5933866DD96D3EB2102737DA92F80F6057A4B40DF2F' },
    @{ Name = 'non-admin portable Inno Setup bootstrap'; Text = $releaseWorkflow; Pattern = '''/CURRENTUSER''[\s\S]+''/PORTABLE=1''' },
    @{ Name = 'authoritative Windows installer build'; Text = $releaseWorkflow; Pattern = 'scripts/Build-WindowsInstaller\.ps1' },
    @{ Name = 'unsigned artifact upload v4'; Text = $releaseWorkflow; Pattern = 'actions/upload-artifact@v4' },
    @{ Name = 'stable unsigned artifact name'; Text = $releaseWorkflow; Pattern = 'name:\s*bigcat-wubi-windows-unsigned' },
    @{ Name = 'installer checksum output'; Text = $releaseWorkflow; Pattern = 'SHA256SUMS\.txt' }
)

foreach ($check in $requiredPatterns) {
    if ($check.Text -notmatch $check.Pattern) {
        $failures.Add("Missing configuration invariant: $($check.Name)")
    }
}

if ($releaseWorkflow -match '(?m)^\s+push:\s*$|(?m)^\s+pull_request:\s*$') {
    $failures.Add('The Phase 1 unsigned release workflow must remain workflow_dispatch-only.')
}

if ($releaseWorkflow -match '(?m)^\s+fetch-depth:\s*0\s*$') {
    $failures.Add('The public release workflow must not require private Git history.')
}

if ($releaseWorkflow -match '(?i)self-hosted') {
    $failures.Add('The release workflow must not use self-hosted runners.')
}

if ($releaseWorkflow -match '(?i)signpath/github-action-submit-signing-request') {
    $failures.Add('Phase 1 must not submit a SignPath signing request.')
}

if ($releaseWorkflow -match '(?m)^\s+uses:\s*actions/cache@') {
    $failures.Add('The Phase 1 release workflow must not use a build cache.')
}

$buildStepIndex = $releaseWorkflow.IndexOf('scripts/Build-WindowsInstaller.ps1', [System.StringComparison]::Ordinal)
$uploadStepIndex = $releaseWorkflow.IndexOf('actions/upload-artifact@v4', [System.StringComparison]::Ordinal)
if ($buildStepIndex -lt 0 -or $uploadStepIndex -lt 0 -or $uploadStepIndex -le $buildStepIndex) {
    $failures.Add('The unsigned GitHub artifact must be uploaded after the authoritative installer build.')
}

if ($commonScript -match '\$startInfo\.WindowStyle\s*=.*Hidden|\$startInfo\.CreateNoWindow\s*=\s*\$true') {
    $failures.Add('WeaselDeployer must not be launched in a hidden window because /deploy can show interactive UI.')
}

if (($installScript + $commonScript) -match 'raw\.githubusercontent\.com') {
    $failures.Add('Installer scripts must not depend directly on raw.githubusercontent.com.')
}

if ($installScript -match 'schemas\\diagnostics|schemas/diagnostics') {
    $failures.Add('The normal installer must not reference development-only diagnostic schema paths.')
}

if ($wubiConfig -match '(?m)^\s*auto_select_unique_candidate:\s*true\s*$') {
    $failures.Add('The installed schema must not enable auto_select_unique_candidate.')
}

$expectedProcessorOrder = @('ascii_composer', 'recognizer', 'key_binder', 'speller', 'punctuator', 'selector', 'navigator', 'express_editor')
$processorMatch = [regex]::Match($wubiConfig, '(?ms)^  processors:\r?\n(?<items>(?:    - [^\r\n]+\r?\n)+)')
$actualProcessorOrder = if ($processorMatch.Success) { @([regex]::Matches($processorMatch.Groups['items'].Value, '(?m)^\s*-\s*(?<name>\S+)\s*$') | ForEach-Object { $_.Groups['name'].Value }) } else { @() }
if (($actualProcessorOrder -join ',') -cne ($expectedProcessorOrder -join ',')) {
    $failures.Add('Formal schema processor order must remain ascii_composer, recognizer, key_binder, speller, punctuator, selector, navigator, express_editor.')
}

if ($wubiConfig -match 'key_bindings:/paging_with_comma_period') {
    $failures.Add('Comma/period paging bindings bypass native punctuation commit behavior and must not be imported.')
}

if ($wubiConfig -match '(?m)^\s*-\s*lua_processor(?:@\S+)?\s*$') {
    $failures.Add('Native input behavior fixes must not introduce a Lua processor.')
}

$forbiddenNames = @('*.userdb', '*.userdb.kct', '*.userdb.txt', 'installation.yaml', 'user.yaml')
foreach ($pattern in $forbiddenNames) {
    $matches = Get-ChildItem -LiteralPath $repoRoot -Recurse -Force -Filter $pattern |
        Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' }
    foreach ($match in $matches) {
        $failures.Add("User data must not be committed: $($match.FullName.Substring($repoRoot.Length + 1))")
    }
}

try {
    . (Join-Path $repoRoot 'scripts\DaMao.WindowsInstallerDependencies.ps1')
    Test-DaMaoWindowsInstallerDependencyLock -RepoRoot $repoRoot | Out-Null
}
catch {
    $failures.Add($_.Exception.Message)
}

try {
    & (Join-Path $repoRoot 'tests\Test-DaMaoRedeploy.ps1')
}
catch {
    $failures.Add($_.Exception.Message)
}

try {
    & (Join-Path $repoRoot 'tests\Test-WindowsInstaller.ps1')
}
catch {
    $failures.Add($_.Exception.Message)
}

try {
    & (Join-Path $repoRoot 'tests\Test-WeaselBootstrap.ps1')
}
catch {
    $failures.Add($_.Exception.Message)
}

try {
    & (Join-Path $repoRoot 'tests\Test-InstallerUninstall.ps1')
}
catch {
    $failures.Add($_.Exception.Message)
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "Repository verification passed ($($trackedFiles.Count) files checked)."
