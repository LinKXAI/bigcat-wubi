[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$installSource = Join-Path $repoRoot 'scripts\Install-DaMao.ps1'
$failures = [System.Collections.Generic.List[string]]::new()
$assertionCount = 0

function Assert-RedeployInvariant {
    param([bool]$Condition, [string]$Message)

    $script:assertionCount++
    if (-not $Condition) {
        $script:failures.Add($Message)
    }
}

function Invoke-RedeployFixture {
    param(
        [Parameter(Mandatory = $true)][string]$CaseRoot,
        [Parameter(Mandatory = $true)][string]$FailureMessage,
        [Parameter(Mandatory = $true)][bool]$UserFacing
    )

    New-Item -ItemType Directory -Path $CaseRoot -Force | Out-Null
    $fixtureInstall = Join-Path $CaseRoot 'Install-DaMao.ps1'
    Copy-Item -LiteralPath $installSource -Destination $fixtureInstall

    $escapedFailure = $FailureMessage.Replace("'", "''")
    $fakeCommon = @"
function Get-DaMaoRimeUserDir {
    param([string]`$Override)
    return (Join-Path `$env:TEMP 'fixture-rime')
}

function Get-DaMaoWeaselRoot {
    param([string]`$Override)
    throw '$escapedFailure'
}
"@
    [System.IO.File]::WriteAllText(
        (Join-Path $CaseRoot 'DaMao.Common.ps1'),
        $fakeCommon,
        [System.Text.UTF8Encoding]::new($false))

    $fixtureRunner = Join-Path $CaseRoot 'Invoke-RedeployFixture.ps1'
    $runnerSource = @'
[CmdletBinding()]
param([switch]$UserFacing)

# Make the regression hermetic even when the developer machine uses a Chinese OEM code page.
[Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(437)

if ($UserFacing) {
    & $env:DAMAO_REDEPLOY_FIXTURE_INSTALL -InstallWubiDependency -UserFacingRedeploy
}
else {
    & $env:DAMAO_REDEPLOY_FIXTURE_INSTALL -InstallWubiDependency
}
'@
    [System.IO.File]::WriteAllText(
        $fixtureRunner,
        $runnerSource,
        [System.Text.Encoding]::ASCII)

    $powerShell = (Get-Command 'powershell.exe' -ErrorAction Stop).Source
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $powerShell
    $startInfo.Arguments = '-NoProfile -ExecutionPolicy Bypass{0} -File "{1}"{2}' -f `
        $(if ($UserFacing) { ' -NoExit' } else { '' }),
        $fixtureRunner,
        $(if ($UserFacing) { ' -UserFacing' } else { '' })
    $startInfo.WorkingDirectory = $CaseRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    $startInfo.StandardOutputEncoding = $utf8NoBom
    $startInfo.StandardErrorEncoding = $utf8NoBom
    $startInfo.EnvironmentVariables['DAMAO_REDEPLOY_FIXTURE_INSTALL'] = $fixtureInstall
    $startInfo.EnvironmentVariables['TEMP'] = $CaseRoot
    $startInfo.EnvironmentVariables['TMP'] = $CaseRoot

    $process = [System.Diagnostics.Process]::Start($startInfo)
    if ($UserFacing) {
        $process.StandardInput.WriteLine()
    }
    $process.StandardInput.Close()
    $standardOutput = $process.StandardOutput.ReadToEnd()
    $standardError = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    return [PSCustomObject]@{
        ExitCode = $process.ExitCode
        Output = $standardOutput + $standardError
        LogPath = Join-Path $CaseRoot 'BigCatWubi-redeploy.log'
    }
}

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "damao-redeploy-tests-$([Guid]::NewGuid().ToString('N'))"
try {
    $sourceText = [System.IO.File]::ReadAllText($installSource)
    Assert-RedeployInvariant ($sourceText -match '\[switch\]\$UserFacingRedeploy' -and
        $sourceText -match '\\u5927\\u732b\\u4e94\\u7b14\\u91cd\\u65b0\\u90e8\\u7f72\\u672a\\u5b8c\\u6210' -and
        $sourceText -match '\\u672a\\u68c0\\u6d4b\\u5230\\u5c0f\\u72fc\\u6beb') `
        'The user-facing boundary or its concise Chinese no-Weasel message is missing.'

    $noWeaselDetail = '[DM-WEASEL-NOT-FOUND] Developer detail: pass -WeaselRoot C:\internal\weasel.'
    $noWeasel = Invoke-RedeployFixture -CaseRoot (Join-Path $testRoot 'no-weasel') `
        -FailureMessage $noWeaselDetail -UserFacing $true
    Assert-RedeployInvariant ($noWeasel.ExitCode -ne 0) `
        'The user-facing no-Weasel path returned a successful process exit code.'
    Assert-RedeployInvariant ($noWeasel.Output -match 'DM-WEASEL-NOT-FOUND') `
        'The user-facing no-Weasel output lost its structured error code.'
    Assert-RedeployInvariant ($noWeasel.Output -match '\u5927\u732b\u4e94\u7b14\u91cd\u65b0\u90e8\u7f72\u672a\u5b8c\u6210' -and
        $noWeasel.Output -match '\u672a\u68c0\u6d4b\u5230\u5c0f\u72fc\u6beb' -and
        $noWeasel.Output -match '\u8bf7\u5148\u5b89\u88c5\u5c0f\u72fc\u6beb') `
        'The user-facing no-Weasel path did not produce the intended concise Chinese recovery guidance.'
    Assert-RedeployInvariant ($noWeasel.Output -notmatch 'CategoryInfo|FullyQualifiedErrorId|pass -WeaselRoot|\.ps1:\d|C:\\internal') `
        'The user-facing no-Weasel output exposed a raw exception record or developer-only detail.'
    Assert-RedeployInvariant ((($noWeasel.Output -split '\r?\n') | Where-Object { $_.Trim().Length -gt 0 }).Count -le 8) `
        'The user-facing no-Weasel output is not concise.'
    $noWeaselLog = if (Test-Path -LiteralPath $noWeasel.LogPath -PathType Leaf) {
        [System.IO.File]::ReadAllText($noWeasel.LogPath)
    }
    else {
        ''
    }
    Assert-RedeployInvariant ($noWeaselLog -match 'DM-WEASEL-NOT-FOUND' -and
        $noWeaselLog -match 'pass -WeaselRoot') `
        'The no-Weasel diagnostic log did not retain the structured code and underlying detail.'

    $unknownDetail = 'Unexpected fixture failure with private developer detail.'
    $unknown = Invoke-RedeployFixture -CaseRoot (Join-Path $testRoot 'unknown') `
        -FailureMessage $unknownDetail -UserFacing $true
    Assert-RedeployInvariant ($unknown.ExitCode -ne 0 -and
        $unknown.Output -match 'DM-REDEPLOY-FAILED') `
        'An unexpected user-facing failure did not return non-zero with the generic error code.'
    Assert-RedeployInvariant ($unknown.Output -match '\u90e8\u7f72\u8fc7\u7a0b\u4e2d\u53d1\u751f\u9519\u8bef' -and
        $unknown.Output -match '\u8bf7\u68c0\u67e5\u76f8\u5173\u4f9d\u8d56\u540e\u91cd\u8bd5') `
        'The unexpected user-facing path did not produce its concise generic Chinese guidance.'
    Assert-RedeployInvariant ($unknown.Output -notmatch 'Unexpected fixture|CategoryInfo|FullyQualifiedErrorId|\.ps1:\d') `
        'Unexpected user-facing failure output exposed internal error details.'
    Assert-RedeployInvariant ((Test-Path -LiteralPath $unknown.LogPath -PathType Leaf) -and
        ([System.IO.File]::ReadAllText($unknown.LogPath) -match 'Unexpected fixture failure')) `
        'The unexpected-failure diagnostic log did not retain the underlying detail.'

    $automation = Invoke-RedeployFixture -CaseRoot (Join-Path $testRoot 'automation') `
        -FailureMessage $noWeaselDetail -UserFacing $false
    Assert-RedeployInvariant ($automation.ExitCode -ne 0 -and
        $automation.Output -match 'DM-WEASEL-NOT-FOUND' -and
        $automation.Output -match 'pass -WeaselRoot') `
        'The normal automation path no longer exposes its original structured failure or non-zero exit.'

    $successfulRoot = Join-Path $testRoot 'successful-redeploy'
    $successfulUserDir = Join-Path $successfulRoot 'Rime'
    $successfulWeaselRoot = Join-Path $successfulRoot 'Weasel'
    New-Item -ItemType Directory -Path $successfulUserDir, $successfulWeaselRoot -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $successfulWeaselRoot 'WeaselDeployer.exe'), '')
    $appearancePath = Join-Path $successfulUserDir 'weasel.custom.yaml'
    $appearanceContent = "patch:`n  `"style/color_scheme`": user_owned_theme`n"
    [System.IO.File]::WriteAllText($appearancePath, $appearanceContent)
    $wubiSource = Join-Path $repoRoot 'third_party\rime\rime-wubi'
    $authoritativeIcon = Join-Path $repoRoot 'assets\branding\windows\bigcat-ime.ico'
    $deployedIcon = Join-Path $successfulUserDir 'damao_wubi\branding\bigcat-ime.ico'

    & $installSource -RimeUserDir $successfulUserDir -WeaselRoot $successfulWeaselRoot `
        -WubiSourcePath $wubiSource -InstallWubiDependency -SkipDeploy -UserFacingRedeploy | Out-Null
    Assert-RedeployInvariant ((Test-Path -LiteralPath $deployedIcon -PathType Leaf) -and
        (Get-FileHash -LiteralPath $deployedIcon -Algorithm SHA256).Hash -eq
        (Get-FileHash -LiteralPath $authoritativeIcon -Algorithm SHA256).Hash) `
        'A successful user-facing deployment did not install the IME-specific schema icon.'

    [System.IO.File]::WriteAllText($deployedIcon, 'corrupt icon fixture')
    $defaultBeforeRedeploy = [System.IO.File]::ReadAllText((Join-Path $successfulUserDir 'default.custom.yaml'))
    & $installSource -RimeUserDir $successfulUserDir -WeaselRoot $successfulWeaselRoot `
        -WubiSourcePath $wubiSource -InstallWubiDependency -SkipDeploy -UserFacingRedeploy | Out-Null
    Assert-RedeployInvariant ((Get-FileHash -LiteralPath $deployedIcon -Algorithm SHA256).Hash -eq
        (Get-FileHash -LiteralPath $authoritativeIcon -Algorithm SHA256).Hash) `
        'User-facing redeploy did not restore the deterministic BigCat IME schema icon.'
    Assert-RedeployInvariant ([System.IO.File]::ReadAllText($appearancePath) -ceq $appearanceContent) `
        'Schema icon deployment overwrote unrelated user Weasel appearance configuration.'
    Assert-RedeployInvariant ([System.IO.File]::ReadAllText((Join-Path $successfulUserDir 'default.custom.yaml')) -ceq
        $defaultBeforeRedeploy) `
        'Icon redeploy changed an already-correct user schema registration.'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}

if ($failures.Count -gt 0) {
    throw "Redeploy UX tests failed:`n - $($failures -join "`n - ")"
}

Write-Host "Redeploy UX tests passed ($assertionCount assertions)."
