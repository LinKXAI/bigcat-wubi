[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'scripts\Bootstrap-Weasel.ps1')
. (Join-Path $repoRoot 'scripts\DaMao.Common.ps1')

$failures = [System.Collections.Generic.List[string]]::new()
$assertionCount = 0
$originalBootstrapLog = $script:DaMaoWeaselBootstrapLog
$testBootstrapLog = Join-Path ([System.IO.Path]::GetTempPath()) "damao-bootstrap-log-$([Guid]::NewGuid().ToString('N')).log"
$script:DaMaoWeaselBootstrapLog = $testBootstrapLog

function Assert-BootstrapInvariant {
    param([bool]$Condition, [string]$Message)

    $script:assertionCount++
    if (-not $Condition) {
        $script:failures.Add($Message)
    }
}

function Invoke-BootstrapScenario {
    param(
        [Parameter(Mandatory = $true)][object[]]$Discoveries,
        [string]$Hash = $script:DaMaoPinnedWeaselInstallerSha256,
        [int]$InstallerExitCode = 0,
        [switch]$StageFails,
        [switch]$SkipStagedFile
    )

    $state = @{
        DiscoveryIndex = 0
        StageCount = 0
        InstallerCount = 0
        DeploymentCount = 0
        DeployedRoot = $null
        DelayCount = 0
        Clock = [DateTime]'2030-01-01T00:00:00Z'
    }
    $discover = {
        $index = $state.DiscoveryIndex
        $state.DiscoveryIndex++
        if ($index -ge $Discoveries.Count) {
            return $Discoveries[-1]
        }
        return $Discoveries[$index]
    }.GetNewClosure()
    $stage = {
        param($source, $destination)
        $state.StageCount++
        if ($StageFails) {
            throw 'simulated bundled-asset staging failure'
        }
        if (-not $SkipStagedFile) {
            [System.IO.File]::WriteAllText($destination, 'deterministic installer fixture')
        }
    }.GetNewClosure()
    $getHash = { param($path) return $Hash }.GetNewClosure()
    $start = {
        param($path)
        $state.InstallerCount++
        return $InstallerExitCode
    }.GetNewClosure()
    $deploy = {
        param($root)
        $state.DeploymentCount++
        $state.DeployedRoot = $root
    }.GetNewClosure()
    $delay = {
        param($milliseconds)
        $state.DelayCount++
        $state.Clock = $state.Clock.AddMilliseconds($milliseconds)
    }.GetNewClosure()
    $utcNow = { return $state.Clock }.GetNewClosure()

    $errorMessage = $null
    $result = $null
    $stagingParent = Join-Path ([System.IO.Path]::GetTempPath()) "damao-bootstrap-test-$([Guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $stagingParent -Force | Out-Null
    try {
        $result = Invoke-DaMaoWeaselBootstrapFlow -DiscoverWeasel $discover `
            -StageInstaller $stage -GetInstallerHash $getHash `
            -StartInstaller $start -DeployBigCat $deploy -StagingParent $stagingParent `
            -BundledInstallerPath 'X:\InnoSetupTemp\weasel-0.17.4.0-installer.exe' `
            -RediscoveryTimeoutSeconds 2 -RediscoveryIntervalMilliseconds 1000 `
            -RediscoveryDelayAction $delay -UtcNowAction $utcNow
    }
    catch {
        $errorMessage = $_.Exception.Message
    }

    $stagingChildrenAfterFlow = @(Get-ChildItem -LiteralPath $stagingParent -Force -ErrorAction SilentlyContinue).Count
    Remove-Item -LiteralPath $stagingParent -Recurse -Force

    return [PSCustomObject]@{
        State = $state
        Result = $result
        ErrorMessage = $errorMessage
        StagingChildrenAfterFlow = $stagingChildrenAfterFlow
    }
}

$usableOldWeasel = [PSCustomObject]@{
    State = 'Usable'
    Root = 'C:\Program Files\Rime\weasel-0.16.3'
    Evidence = $null
}
$absentWeasel = [PSCustomObject]@{ State = 'Absent'; Root = $null; Evidence = $null }
$unusableWeasel = [PSCustomObject]@{ State = 'Unusable'; Root = $null; Evidence = 'REGISTRY_EVIDENCE' }
$installedWeasel = [PSCustomObject]@{
    State = 'Usable'
    Root = 'C:\Program Files\Rime\weasel-0.17.4'
    Evidence = $null
}

# 1 and 9: Any existing usable version wins and enters the validated deployment once.
$existing = Invoke-BootstrapScenario -Discoveries @($usableOldWeasel)
Assert-BootstrapInvariant ($null -eq $existing.ErrorMessage) 'Existing usable Weasel unexpectedly failed.'
Assert-BootstrapInvariant ($existing.State.StageCount -eq 0) 'Existing usable Weasel caused the bundled installer to be accessed or extracted.'
Assert-BootstrapInvariant ($existing.State.InstallerCount -eq 0) 'Existing usable Weasel launched the pinned installer.'
Assert-BootstrapInvariant ($existing.State.DeploymentCount -eq 1) 'Existing usable Weasel did not invoke V1 deployment exactly once.'
Assert-BootstrapInvariant ($existing.State.DeployedRoot -eq $usableOldWeasel.Root) 'Existing non-pinned Weasel was not reused unchanged.'

# 2 and 8: Absence selects bootstrap; rediscovery gates exactly one deployment.
$success = Invoke-BootstrapScenario -Discoveries @($absentWeasel, $installedWeasel)
Assert-BootstrapInvariant ($null -eq $success.ErrorMessage) 'Successful bootstrap unexpectedly failed.'
Assert-BootstrapInvariant ($success.State.StageCount -eq 1) 'Weasel absence did not stage the bundled installer exactly once.'
Assert-BootstrapInvariant ($success.State.InstallerCount -eq 1) 'Verified installer was not launched exactly once.'
Assert-BootstrapInvariant ($success.State.DiscoveryIndex -eq 2) 'Successful bootstrap did not rediscover Weasel.'
Assert-BootstrapInvariant ($success.State.DeploymentCount -eq 1) 'Successful rediscovery did not invoke V1 deployment exactly once.'
Assert-BootstrapInvariant ($success.State.DeployedRoot -eq $installedWeasel.Root) 'V1 deployment did not receive the rediscovered root.'
Assert-BootstrapInvariant ($success.StagingChildrenAfterFlow -eq 0) 'Successful bootstrap left staged files behind.'
Assert-BootstrapInvariant ($success.State.DelayCount -eq 0) 'Immediate usable rediscovery unexpectedly waited.'

# Delayed installation state settles inside the bounded retry window.
$delayedSuccess = Invoke-BootstrapScenario -Discoveries @($absentWeasel, $absentWeasel, $installedWeasel)
Assert-BootstrapInvariant ($null -eq $delayedSuccess.ErrorMessage) 'Delayed usable rediscovery unexpectedly failed.'
Assert-BootstrapInvariant ($delayedSuccess.State.DelayCount -eq 1) 'Delayed rediscovery did not use the explicit retry interval once.'
Assert-BootstrapInvariant ($delayedSuccess.State.DiscoveryIndex -eq 3) 'Delayed rediscovery did not retry V1 discovery.'
Assert-BootstrapInvariant ($delayedSuccess.State.DeploymentCount -eq 1) 'Delayed usable rediscovery did not deploy exactly once.'

# 3: Bundled-asset staging failure fails closed before installer or deployment.
$stageFailure = Invoke-BootstrapScenario -Discoveries @($absentWeasel) -StageFails
Assert-BootstrapInvariant ($stageFailure.ErrorMessage -match '^\[DM-WEASEL-BUNDLED-ASSET-FAILED\]') 'Bundled-asset staging failure was not clearly classified.'
Assert-BootstrapInvariant ($stageFailure.State.InstallerCount -eq 0) 'Staging failure launched the Weasel installer.'
Assert-BootstrapInvariant ($stageFailure.State.DeploymentCount -eq 0) 'Staging failure started BigCat deployment.'
Assert-BootstrapInvariant ($stageFailure.StagingChildrenAfterFlow -eq 0) 'Staging failure left staged files behind.'

# A successful download call that produces no regular file must also fail closed.
$invalidStage = Invoke-BootstrapScenario -Discoveries @($absentWeasel) -SkipStagedFile
Assert-BootstrapInvariant ($invalidStage.ErrorMessage -match '^\[DM-WEASEL-BUNDLED-ASSET-INVALID\]') 'Missing staged regular file was not rejected.'
Assert-BootstrapInvariant ($invalidStage.State.InstallerCount -eq 0) 'Non-file staging result reached installer launch.'
Assert-BootstrapInvariant ($invalidStage.State.DeploymentCount -eq 0) 'Non-file staging result started BigCat deployment.'

# 4: Wrong SHA-256 never reaches either executable boundary.
$wrongHash = Invoke-BootstrapScenario -Discoveries @($absentWeasel) -Hash ('0' * 64)
Assert-BootstrapInvariant ($wrongHash.ErrorMessage -match '^\[DM-WEASEL-HASH-MISMATCH\]') 'Wrong SHA-256 was not fatal.'
Assert-BootstrapInvariant ($wrongHash.State.InstallerCount -eq 0) 'Hash-invalid Weasel installer was launched.'
Assert-BootstrapInvariant ($wrongHash.State.DeploymentCount -eq 0) 'Hash mismatch started BigCat deployment.'

# 5: Correct SHA-256 opens the process boundary.
Assert-BootstrapInvariant ($success.State.InstallerCount -eq 1) 'Correct SHA-256 did not permit installer launch.'

# 6: Child installer non-zero prevents BigCat deployment.
$childFailure = Invoke-BootstrapScenario -Discoveries @($absentWeasel) -InstallerExitCode 7
Assert-BootstrapInvariant ($childFailure.ErrorMessage -match '^\[DM-WEASEL-INSTALL-FAILED\].*7') 'Child failure was not classified with its exit code.'
Assert-BootstrapInvariant ($childFailure.State.DeploymentCount -eq 0) 'Failed child installer started BigCat deployment.'
Assert-BootstrapInvariant ($childFailure.State.DiscoveryIndex -eq 1) 'Failed child installer performed post-install rediscovery.'
Assert-BootstrapInvariant ($childFailure.State.DelayCount -eq 0) 'Failed child installer entered the rediscovery wait.'

# 7: Exit zero without usable rediscovery also fails closed.
$notRediscovered = Invoke-BootstrapScenario -Discoveries @($absentWeasel, $absentWeasel)
Assert-BootstrapInvariant ($notRediscovered.ErrorMessage -match '^\[DM-WEASEL-POST-INSTALL-NOT-FOUND\]') 'Missing post-install Weasel was not classified.'
Assert-BootstrapInvariant ($notRediscovered.State.DeploymentCount -eq 0) 'Missing post-install Weasel started BigCat deployment.'
Assert-BootstrapInvariant ($notRediscovered.State.DelayCount -eq 2) 'Never-usable rediscovery did not stop at its bounded timeout.'

# The exact-process waiter must return while an installer-spawned resident remains alive.
$processTestRoot = Join-Path ([System.IO.Path]::GetTempPath()) "damao-direct-process-$([Guid]::NewGuid().ToString('N'))"
$residentProcess = $null
$parentProcess = $null
try {
    New-Item -ItemType Directory -Path $processTestRoot -Force | Out-Null
    $parentScript = Join-Path $processTestRoot 'installer-parent.ps1'
    $residentPidPath = Join-Path $processTestRoot 'resident.pid'
    [System.IO.File]::WriteAllLines($parentScript, @(
        'param([string]$ResidentPidPath)',
        '$resident = Start-Process powershell.exe -ArgumentList @(''-NoProfile'', ''-Command'', ''Start-Sleep -Seconds 30'') -WindowStyle Hidden -PassThru',
        '[System.IO.File]::WriteAllText($ResidentPidPath, [string]$resident.Id)',
        'exit 0'
    ))
    $parentProcess = Start-Process powershell.exe -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $parentScript,
        '-ResidentPidPath', $residentPidPath
    ) -WindowStyle Hidden -PassThru
    $directWaitStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $directExitCode = Wait-DaMaoDirectInstallerProcess -Process $parentProcess -TimeoutSeconds 10
    $directWaitStopwatch.Stop()
    $residentPidRecorded = Test-Path -LiteralPath $residentPidPath -PathType Leaf
    if ($residentPidRecorded) {
        $residentProcess = Get-Process -Id ([int][System.IO.File]::ReadAllText($residentPidPath)) -ErrorAction SilentlyContinue
    }
    Assert-BootstrapInvariant ($directExitCode -eq 0) 'Direct installer process success exit code was not returned.'
    Assert-BootstrapInvariant ($directWaitStopwatch.Elapsed.TotalSeconds -lt 5) 'Direct installer wait followed the resident descendant.'
    Assert-BootstrapInvariant ($null -ne $residentProcess) 'Simulated resident descendant was not alive after direct installer exit.'
}
finally {
    if ($null -ne $residentProcess -and -not $residentProcess.HasExited) {
        $residentProcess.Kill()
        $residentProcess.WaitForExit(5000) | Out-Null
    }
    if ($null -ne $parentProcess -and -not $parentProcess.HasExited) {
        $parentProcess.Kill()
    }
    if (Test-Path -LiteralPath $processTestRoot) {
        Remove-Item -LiteralPath $processTestRoot -Recurse -Force
    }
}

# Existing but unusable evidence must never be silently overwritten.
$unusable = Invoke-BootstrapScenario -Discoveries @($unusableWeasel)
Assert-BootstrapInvariant ($unusable.ErrorMessage -match '^\[DM-WEASEL-EXISTING-UNUSABLE\]') 'Unusable existing Weasel was not classified explicitly.'
Assert-BootstrapInvariant ($unusable.State.StageCount -eq 0) 'Unusable existing Weasel was silently overwritten by bootstrap.'
Assert-BootstrapInvariant ($unusable.State.DeploymentCount -eq 0) 'Unusable existing Weasel started BigCat deployment.'

# Weasel removal is ownership-aware and is never simulated with hard-coded files.
$installerSource = [System.IO.File]::ReadAllText((Join-Path $repoRoot 'installer\windows\BigCatWubi.iss'))
$bootstrapSource = [System.IO.File]::ReadAllText((Join-Path $repoRoot 'scripts\Bootstrap-Weasel.ps1'))
$uninstallSource = [System.IO.File]::ReadAllText((Join-Path $repoRoot 'scripts\Uninstall-BigCat.ps1'))
Assert-BootstrapInvariant ($installerSource -match '(?ms)^\[UninstallDelete\]\s*Type: files; Name: "\{app\}\\installer-state\.ini"\s*$' -and
    $installerSource -notmatch '(?im)^\[UninstallRun\]') 'The only declarative uninstall deletion must be the exact installer-owned state file.'
Assert-BootstrapInvariant ($uninstallSource -match 'Get-DaMaoWeaselUninstallRegistryEntries' -and
    $uninstallSource -match 'UninstallString' -and
    $uninstallSource -notmatch '(?i)weasel-[0-9.]+\\uninstall\.exe') 'Weasel removal is not discovered from current uninstall registration.'

# Constants and execution arguments must remain pinned and explicit.
Assert-BootstrapInvariant ($script:DaMaoPinnedWeaselVersion -ceq '0.17.4') 'Pinned Weasel version changed.'
Assert-BootstrapInvariant ($script:DaMaoPinnedWeaselInstallerUrl -ceq 'https://github.com/rime/weasel/releases/download/0.17.4/weasel-0.17.4.0-installer.exe') 'Pinned official Weasel URL changed.'
Assert-BootstrapInvariant ($script:DaMaoPinnedWeaselInstallerSha256 -ceq 'CF509534A8F5F8AF9C98ED7CBB8F135439F145A8CBE7E50EDE42BB5B5AB45C29') 'Pinned Weasel SHA-256 changed.'
Assert-BootstrapInvariant ($bootstrapSource -notmatch '(?i)Invoke-WebRequest|Start-BitsTransfer|System\.Net\.WebClient') 'Production bootstrap still contains a live network download path.'
Assert-BootstrapInvariant ($bootstrapSource -match 'Copy-DaMaoBundledWeaselInstaller') 'Production bootstrap does not stage the bundled Weasel asset.'
Assert-BootstrapInvariant ($bootstrapSource -match 'WubiSourcePath\s*=\s*\$BundledWubiSourcePath') 'Installer-driven deployment does not pass the bundled Wubi source.'
Assert-BootstrapInvariant ($bootstrapSource -notmatch '(?i)\bgit\s+clone\b|(?:&|Start-Process)[^\r\n]*rime-install\.bat') 'Bootstrap directly invokes Git or Plum.'
Assert-BootstrapInvariant ($bootstrapSource -match '(?s)function Invoke-DaMaoWeaselBootstrapEntryPoint.*?Assert-DaMaoBundledWubiSource.*?Invoke-DaMaoWeaselBootstrapFlow') 'Bundled Wubi validation does not precede every bootstrap/install/deploy action.'
Assert-BootstrapInvariant ($bootstrapSource -match '(?s)\$initializeFreshRimeState\s*=\s*Test-DaMaoFreshRimeUserState.*?Invoke-DaMaoWeaselBootstrapFlow') 'Fresh Rime state is not captured before the Weasel bootstrap flow can run.'
Assert-BootstrapInvariant ($bootstrapSource -match '(?s)if \(\$initializeFreshRimeState\).*?InitializeFreshRimeState\s*=\s*\$true') 'Captured fresh Rime state is not forwarded only through the installer-driven deployment boundary.'
Assert-BootstrapInvariant ($bootstrapSource -notmatch '(?im)(?:Set-Content|WriteAllText|Copy-Item|Move-Item|Remove-Item)[^\r\n]*user\.yaml') 'Bootstrap added a direct user.yaml mutation.'
Assert-BootstrapInvariant ($bootstrapSource -match "-ArgumentList '/S'") 'Official Weasel installer is not launched with the required single /S argument.'
Assert-BootstrapInvariant ($bootstrapSource -notmatch '(?i)AutoHotkey|/S\s+/S') 'Bootstrap introduced UI automation or an unverified duplicate /S workaround.'
Assert-BootstrapInvariant ($bootstrapSource -notmatch '(?m)Start-Process[^\r\n]*-Wait') 'Production bootstrap still uses Start-Process process-tree waiting.'
Assert-BootstrapInvariant ($bootstrapSource -match '\$Process\.WaitForExit\(\$TimeoutSeconds \* 1000\)') 'Production bootstrap does not wait on the exact direct process with a timeout.'
Assert-BootstrapInvariant ($bootstrapSource -match 'Wait-DaMaoDirectInstallerProcess -Process \$process') 'Production installer launch does not use the exact-process waiter.'
Assert-BootstrapInvariant ($bootstrapSource -notmatch '(?i)WaitForExit\(\s*\)|while\s*\(\s*\$true\s*\)|for\s*\(\s*;\s*;') 'Production bootstrap contains an unbounded wait or loop.'
Assert-BootstrapInvariant ($bootstrapSource -notmatch '(?is)WeaselServer\.exe.{0,200}(?:Kill|WaitForExit|Stop-Process)|(?:Kill|WaitForExit|Stop-Process).{0,200}WeaselServer\.exe') 'Production bootstrap kills or waits for WeaselServer.'
Assert-BootstrapInvariant ($script:DaMaoWeaselInstallerTimeoutSeconds -eq 600) 'Direct installer timeout constant changed.'
Assert-BootstrapInvariant ($script:DaMaoWeaselRediscoveryIntervalMilliseconds -eq 1000) 'Rediscovery interval constant changed.'
Assert-BootstrapInvariant ($script:DaMaoWeaselRediscoveryTimeoutSeconds -eq 60) 'Rediscovery timeout constant changed.'
Assert-BootstrapInvariant ((Get-DaMaoWeaselBootstrapExitCode '[DM-WEASEL-BUNDLED-ASSET-FAILED]') -eq 21) 'Bundled asset failure exit code mapping changed.'
Assert-BootstrapInvariant ((Get-DaMaoWeaselBootstrapExitCode '[DM-WEASEL-HASH-MISMATCH]') -eq 22) 'Hash failure exit code mapping changed.'
Assert-BootstrapInvariant ((Get-DaMaoWeaselBootstrapExitCode '[DM-WEASEL-INSTALL-FAILED]') -eq 23) 'Install failure exit code mapping changed.'
Assert-BootstrapInvariant ((Get-DaMaoWeaselBootstrapExitCode '[DM-WEASEL-POST-INSTALL-NOT-FOUND]') -eq 24) 'Rediscovery failure exit code mapping changed.'
Assert-BootstrapInvariant ((Get-DaMaoWeaselBootstrapExitCode '[DM-WEASEL-EXISTING-UNUSABLE]') -eq 25) 'Unusable-existing exit code mapping changed.'
Assert-BootstrapInvariant ((Get-DaMaoWeaselBootstrapExitCode '[DM-BUNDLED-WUBI-SOURCE-INVALID]') -eq 26) 'Bundled Wubi source failure exit code mapping changed.'

# Freshness is conservative and is evaluated before Weasel can create defaults.
$freshStateRoot = Join-Path ([System.IO.Path]::GetTempPath()) "damao-fresh-state-$([Guid]::NewGuid().ToString('N'))"
try {
    Assert-BootstrapInvariant (Test-DaMaoFreshRimeUserState -RimeUserDir $freshStateRoot) 'A missing Rime user directory was not classified as fresh.'
    New-Item -ItemType Directory -Path $freshStateRoot -Force | Out-Null
    Assert-BootstrapInvariant (Test-DaMaoFreshRimeUserState -RimeUserDir $freshStateRoot) 'A truly empty Rime user directory was not classified as fresh.'
    [System.IO.File]::WriteAllText((Join-Path $freshStateRoot 'user.yaml'), 'var: {}')
    Assert-BootstrapInvariant (-not (Test-DaMaoFreshRimeUserState -RimeUserDir $freshStateRoot)) 'A Rime directory containing one file was incorrectly classified as fresh.'
    Remove-Item -LiteralPath (Join-Path $freshStateRoot 'user.yaml') -Force
    New-Item -ItemType Directory -Path (Join-Path $freshStateRoot 'build') -Force | Out-Null
    Assert-BootstrapInvariant (-not (Test-DaMaoFreshRimeUserState -RimeUserDir $freshStateRoot)) 'A Rime directory containing one subdirectory was incorrectly classified as fresh.'
}
finally {
    if (Test-Path -LiteralPath $freshStateRoot) {
        Remove-Item -LiteralPath $freshStateRoot -Recurse -Force
    }
}

# The checked-in Weasel payload must match the fixed official release digest.
$bundledWeasel = Join-Path $repoRoot 'third_party\weasel\0.17.4\weasel-0.17.4.0-installer.exe'
Assert-BootstrapInvariant ((Get-Item -LiteralPath $bundledWeasel).Length -eq 12431118) 'Bundled Weasel size changed.'
Assert-BootstrapInvariant ((Get-FileHash -LiteralPath $bundledWeasel -Algorithm SHA256).Hash -ceq $script:DaMaoPinnedWeaselInstallerSha256) 'Bundled Weasel digest does not match the pin.'

# Missing/invalid Wubi source fails before installer-driven deployment can begin.
$invalidWubiRoot = Join-Path ([System.IO.Path]::GetTempPath()) "damao-invalid-wubi-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $invalidWubiRoot -Force | Out-Null
$invalidWubiError = $null
try {
    Assert-DaMaoBundledWubiSource -SourcePath $invalidWubiRoot | Out-Null
}
catch {
    $invalidWubiError = $_.Exception.Message
}
finally {
    Remove-Item -LiteralPath $invalidWubiRoot -Recurse -Force
}
Assert-BootstrapInvariant ($invalidWubiError -match '^\[DM-BUNDLED-WUBI-SOURCE-INVALID\]') 'Invalid bundled Wubi source did not fail closed at preflight.'

# The real pinned source deploys through the existing offline contract without Plum/Git.
$offlineTestRoot = Join-Path ([System.IO.Path]::GetTempPath()) "damao-offline-wubi-$([Guid]::NewGuid().ToString('N'))"
$offlineRimeUserDir = Join-Path $offlineTestRoot 'Rime'
$offlineWeaselRoot = Join-Path $offlineTestRoot 'Weasel'
$plumSentinel = Join-Path $offlineTestRoot 'plum-was-invoked.txt'
$originalPath = $env:PATH
try {
    New-Item -ItemType Directory -Path $offlineWeaselRoot -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $offlineWeaselRoot 'WeaselDeployer.exe'), '')
    [System.IO.File]::WriteAllLines((Join-Path $offlineWeaselRoot 'rime-install.bat'), @(
        '@echo off'
        ('echo invoked>"{0}"' -f $plumSentinel)
        'exit /b 99'
    ))
    $env:PATH = ''
    $offlineResult = & (Join-Path $repoRoot 'scripts\Install-DaMao.ps1') `
        -RimeUserDir $offlineRimeUserDir -WeaselRoot $offlineWeaselRoot `
        -InstallWubiDependency -WubiSourcePath (Join-Path $repoRoot 'third_party\rime\rime-wubi') -SkipDeploy
    Assert-BootstrapInvariant ((Test-Path -LiteralPath (Join-Path $offlineRimeUserDir 'wubi86.dict.yaml') -PathType Leaf)) 'Existing offline Wubi contract did not install the pinned dictionary.'
    Assert-BootstrapInvariant ((Test-Path -LiteralPath (Join-Path $offlineRimeUserDir 'LICENSE.rime-wubi.txt') -PathType Leaf)) 'Existing offline Wubi contract did not retain the upstream license.'
    Assert-BootstrapInvariant ($offlineResult.DictionaryDependency -eq (Join-Path $offlineRimeUserDir 'wubi86.dict.yaml')) 'Offline Wubi contract returned an unexpected dependency path.'
    Assert-BootstrapInvariant (-not (Test-Path -LiteralPath $plumSentinel)) 'Installer-driven offline deployment invoked Plum despite a bundled Wubi source.'
}
finally {
    $env:PATH = $originalPath
    if (Test-Path -LiteralPath $offlineTestRoot) {
        Remove-Item -LiteralPath $offlineTestRoot -Recurse -Force
    }
}

$bootstrapLogContent = if (Test-Path -LiteralPath $testBootstrapLog) {
    [System.IO.File]::ReadAllText($testBootstrapLog)
}
else {
    ''
}
Assert-BootstrapInvariant ($bootstrapLogContent -match 'WEASEL_BOOTSTRAP_SUCCEEDED') 'Success event was not emitted.'
Assert-BootstrapInvariant ($bootstrapLogContent -match 'WEASEL_POST_INSTALL_NOT_FOUND') 'Bounded rediscovery timeout event was not emitted.'
$script:DaMaoWeaselBootstrapLog = $originalBootstrapLog
Remove-Item -LiteralPath $testBootstrapLog -Force -ErrorAction SilentlyContinue

if ($failures.Count -gt 0) {
    throw "Weasel bootstrap tests failed:`n - $($failures -join "`n - ")"
}

Write-Host "Weasel bootstrap tests passed ($assertionCount assertions)."
