[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'scripts\DaMao.InstallerState.ps1')
. (Join-Path $repoRoot 'scripts\DaMao.Common.ps1')
. (Join-Path $repoRoot 'scripts\Uninstall-BigCat.ps1')

$failures = [System.Collections.Generic.List[string]]::new()
$assertionCount = 0
function Assert-UninstallInvariant {
    param([bool]$Condition, [string]$Message)
    $script:assertionCount++
    if (-not $Condition) {
        $script:failures.Add($Message)
    }
}

function Write-TestText {
    param([string]$Path, [string]$Content)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "damao-uninstall-$([Guid]::NewGuid().ToString('N'))"
try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

    # Install-time classification and immutable upgrade inheritance.
    Assert-UninstallInvariant ((Resolve-DaMaoWeaselOrigin -InitialWeaselState Usable) -ceq 'PreExisting') `
        'A first install with usable Weasel was not classified PreExisting.'
    Assert-UninstallInvariant ((Resolve-DaMaoWeaselOrigin -InitialWeaselState Usable -LegacyInstallPresent) -ceq 'UnknownLegacy') `
        'A legacy install without trustworthy state was not classified UnknownLegacy.'
    Assert-UninstallInvariant ((Resolve-DaMaoWeaselOrigin -InitialWeaselState Absent -BootstrapSucceeded) -ceq 'BigCatBootstrap') `
        'A successful absent-machine bootstrap was not classified BigCatBootstrap.'
    Assert-UninstallInvariant ((Resolve-DaMaoWeaselOrigin -ExistingOrigin BigCatBootstrap -InitialWeaselState Usable) -ceq 'BigCatBootstrap') `
        'Upgrade changed BigCatBootstrap ownership merely because Weasel now exists.'
    Assert-UninstallInvariant ((Resolve-DaMaoWeaselOrigin -ExistingOrigin PreExisting -InitialWeaselState Usable) -ceq 'PreExisting') `
        'Upgrade did not preserve PreExisting provenance.'

    $bootstrapStatePath = Join-Path $testRoot 'bootstrap\installer-state.ini'
    $bootstrapRime = Join-Path $testRoot 'bootstrap\Rime'
    Write-DaMaoInstallerState -Path $bootstrapStatePath -WeaselOrigin BigCatBootstrap -RimeUserDir $bootstrapRime
    $bootstrapState = Read-DaMaoInstallerState -Path $bootstrapStatePath
    Assert-UninstallInvariant ($bootstrapState.IsTrusted -and
        $bootstrapState.WeaselOrigin -ceq 'BigCatBootstrap' -and
        $bootstrapState.FormatVersion -eq 1) 'Installer provenance did not round-trip in the versioned INI state.'
    $untrustedStatePath = Join-Path $testRoot 'untrusted\installer-state.ini'
    Write-TestText -Path $untrustedStatePath -Content "[installer]`nformat_version=0`nweasel_origin=BigCatBootstrap`n"
    Assert-UninstallInvariant (-not (Read-DaMaoInstallerState -Path $untrustedStatePath).IsTrusted) `
        'An unsupported state version was incorrectly trusted as BigCat ownership.'

    $bootstrapPolicy = Get-DaMaoWeaselUninstallPolicy -Origin $bootstrapState.WeaselOrigin
    $preExistingPolicy = Get-DaMaoWeaselUninstallPolicy -Origin PreExisting
    $legacyPolicy = Get-DaMaoWeaselUninstallPolicy -Origin UnknownLegacy
    Assert-UninstallInvariant ($bootstrapPolicy.DefaultChecked -and -not $bootstrapPolicy.ConfirmIfChecked) `
        'BigCatBootstrap uninstall policy is not checked by default.'
    Assert-UninstallInvariant (-not $preExistingPolicy.DefaultChecked -and $preExistingPolicy.ConfirmIfChecked) `
        'PreExisting uninstall policy is not conservative.'
    Assert-UninstallInvariant (-not $legacyPolicy.DefaultChecked -and $legacyPolicy.ConfirmIfChecked) `
        'UnknownLegacy uninstall policy is not conservative.'

    # Shared dependency ownership begins only when the first tracked install created the file.
    New-Item -ItemType Directory -Path $bootstrapRime -Force | Out-Null
    $createdSnapshot = Get-DaMaoRimeOwnershipSnapshot -RimeUserDir $bootstrapRime
    foreach ($relativePath in $script:DaMaoRimeOwnershipPaths.Values) {
        Write-TestText -Path (Join-Path $bootstrapRime $relativePath) -Content "created:$relativePath"
    }
    Update-DaMaoInstallerRimeOwnership -StatePath $bootstrapStatePath -RimeUserDir $bootstrapRime `
        -ExistedBefore $createdSnapshot
    $ownedState = Read-DaMaoInstallerState -Path $bootstrapStatePath
    Assert-UninstallInvariant ($ownedState.RimeOwnership.Count -eq 3) `
        'Created shared Rime files were not recorded with hashes.'
    $upgradeSnapshot = Get-DaMaoRimeOwnershipSnapshot -RimeUserDir $bootstrapRime
    Update-DaMaoInstallerRimeOwnership -StatePath $bootstrapStatePath -RimeUserDir $bootstrapRime `
        -ExistedBefore $upgradeSnapshot
    Assert-UninstallInvariant ((Read-DaMaoInstallerState -Path $bootstrapStatePath).RimeOwnership.Count -eq 3) `
        'Upgrade did not preserve tracked shared-file ownership.'

    $preExistingStatePath = Join-Path $testRoot 'preexisting\installer-state.ini'
    $preExistingRime = Join-Path $testRoot 'preexisting\Rime'
    New-Item -ItemType Directory -Path $preExistingRime -Force | Out-Null
    foreach ($relativePath in $script:DaMaoRimeOwnershipPaths.Values) {
        Write-TestText -Path (Join-Path $preExistingRime $relativePath) -Content "user:$relativePath"
    }
    $preExistingSnapshot = Get-DaMaoRimeOwnershipSnapshot -RimeUserDir $preExistingRime
    Write-DaMaoInstallerState -Path $preExistingStatePath -WeaselOrigin PreExisting -RimeUserDir $preExistingRime
    Update-DaMaoInstallerRimeOwnership -StatePath $preExistingStatePath -RimeUserDir $preExistingRime `
        -ExistedBefore $preExistingSnapshot
    Assert-UninstallInvariant ((Read-DaMaoInstallerState -Path $preExistingStatePath).RimeOwnership.Count -eq 0) `
        'Pre-existing shared Rime files were incorrectly claimed by BigCat.'

    # Targeted inverse YAML mutation keeps unrelated keys, schemas, comments, and order.
    $yamlPath = Join-Path $testRoot 'yaml\default.custom.yaml'
    $yaml = @"
customization: 42
patch:
  schema_list:
    - schema: luna # keep-a
    - schema: damao_wubi # remove-only-this
    - schema: terra
  menu/page_size: 9
other: keep
"@
    Write-TestText -Path $yamlPath -Content $yaml
    Assert-UninstallInvariant (Remove-DaMaoSchemaSelection -DefaultCustomPath $yamlPath) `
        'Targeted default.custom.yaml removal reported no change.'
    $cleanYaml = [System.IO.File]::ReadAllText($yamlPath)
    Assert-UninstallInvariant ($cleanYaml -notmatch 'damao_wubi' -and
        $cleanYaml -match 'luna # keep-a' -and $cleanYaml -match 'terra' -and
        $cleanYaml -match 'menu/page_size: 9' -and $cleanYaml -match 'customization: 42' -and
        $cleanYaml -match 'other: keep') 'Targeted YAML removal changed or lost unrelated content.'

    $flowYamlPath = Join-Path $testRoot 'yaml\flow.default.custom.yaml'
    Write-TestText -Path $flowYamlPath -Content "patch:`n  schema_list: [ { schema: luna }, { schema: damao_wubi }, { schema: terra } ]`n"
    [void](Remove-DaMaoSchemaSelection -DefaultCustomPath $flowYamlPath)
    $flowYaml = [System.IO.File]::ReadAllText($flowYamlPath)
    Assert-UninstallInvariant ($flowYaml -notmatch 'damao_wubi' -and $flowYaml -match 'luna' -and $flowYaml -match 'terra') `
        'Inline schema_list cleanup did not preserve unrelated entries.'

    # Exact cleanup removes only BigCat artifacts and leaves unrelated/sync/custom data intact.
    $cleanupRoot = Join-Path $testRoot 'cleanup'
    $cleanupRime = Join-Path $cleanupRoot 'Rime'
    $cleanupStatePath = Join-Path $cleanupRoot 'installer-state.ini'
    New-Item -ItemType Directory -Path $cleanupRime -Force | Out-Null
    $ownership = @{}
    foreach ($key in $script:DaMaoRimeOwnershipPaths.Keys) {
        $path = Join-Path $cleanupRime $script:DaMaoRimeOwnershipPaths[$key]
        Write-TestText -Path $path -Content "owned:$key"
        $ownership[$key] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }
    Write-DaMaoInstallerState -Path $cleanupStatePath -WeaselOrigin BigCatBootstrap `
        -RimeUserDir $cleanupRime -RimeOwnership $ownership
    Write-TestText -Path (Join-Path $cleanupRime 'default.custom.yaml') -Content `
        "patch:`n  `"schema_list/+`":`n    - schema: luna`n    - schema: damao_wubi`n  menu/page_size: 8`n"
    foreach ($relativePath in @(
        'damao_wubi.schema.yaml', 'damao_wubi\branding\bigcat-ime.ico',
        'build\damao_wubi.schema.yaml', 'damao_wubi.userdb.kct',
        'damao_wubi.userdb\CURRENT')) {
        Write-TestText -Path (Join-Path $cleanupRime $relativePath) -Content 'bigcat'
    }
    foreach ($relativePath in @(
        'luna.schema.yaml', 'luna.userdb\CURRENT', 'sync\machine\damao_wubi.userdb.txt',
        'backup\damao-ime-config-20300101\default.custom.yaml',
        'damao_wubi.custom.yaml', 'user.yaml', 'unrelated.dict.yaml')) {
        Write-TestText -Path (Join-Path $cleanupRime $relativePath) -Content 'preserve'
    }
    $cleanupState = Read-DaMaoInstallerState -Path $cleanupStatePath
    $cleanupResult = Remove-DaMaoBigCatOwnedArtifacts -RimeUserDir $cleanupRime -InstallerState $cleanupState
    Assert-UninstallInvariant ($cleanupResult.Failures.Count -eq 0) 'Exact BigCat cleanup returned unexpected failures.'
    foreach ($relativePath in @(
        'damao_wubi.schema.yaml', 'damao_wubi\branding\bigcat-ime.ico',
        'build\damao_wubi.schema.yaml', 'damao_wubi.userdb.kct', 'damao_wubi.userdb')) {
        Assert-UninstallInvariant (-not (Test-Path -LiteralPath (Join-Path $cleanupRime $relativePath))) `
            "BigCat-owned artifact survived cleanup: $relativePath"
    }
    foreach ($relativePath in $script:DaMaoRimeOwnershipPaths.Values) {
        Assert-UninstallInvariant (-not (Test-Path -LiteralPath (Join-Path $cleanupRime $relativePath))) `
            "Hash-proven BigCat-created shared artifact survived cleanup: $relativePath"
    }
    foreach ($relativePath in @(
        'luna.schema.yaml', 'luna.userdb\CURRENT', 'sync\machine\damao_wubi.userdb.txt',
        'backup\damao-ime-config-20300101\default.custom.yaml',
        'damao_wubi.custom.yaml', 'user.yaml', 'unrelated.dict.yaml')) {
        Assert-UninstallInvariant (Test-Path -LiteralPath (Join-Path $cleanupRime $relativePath)) `
            "Unrelated or deliberately preserved Rime artifact was deleted: $relativePath"
    }
    $postCleanupYaml = [System.IO.File]::ReadAllText((Join-Path $cleanupRime 'default.custom.yaml'))
    Assert-UninstallInvariant ($postCleanupYaml -notmatch 'damao_wubi' -and
        $postCleanupYaml -match 'luna' -and $postCleanupYaml -match 'menu/page_size: 8') `
        'Cleanup did not apply a targeted inverse default.custom mutation.'

    # Another schema referencing wubi86 prevents shared dependency deletion.
    $sharedRoot = Join-Path $testRoot 'shared'
    $sharedRime = Join-Path $sharedRoot 'Rime'
    $sharedStatePath = Join-Path $sharedRoot 'installer-state.ini'
    New-Item -ItemType Directory -Path $sharedRime -Force | Out-Null
    $sharedOwnership = @{}
    foreach ($key in $script:DaMaoRimeOwnershipPaths.Keys) {
        $path = Join-Path $sharedRime $script:DaMaoRimeOwnershipPaths[$key]
        Write-TestText -Path $path -Content "owned:$key"
        $sharedOwnership[$key] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }
    Write-TestText -Path (Join-Path $sharedRime 'other.schema.yaml') -Content "translator:`n  dictionary: wubi86`n"
    Write-DaMaoInstallerState -Path $sharedStatePath -WeaselOrigin PreExisting `
        -RimeUserDir $sharedRime -RimeOwnership $sharedOwnership
    [void](Remove-DaMaoBigCatOwnedArtifacts -RimeUserDir $sharedRime `
        -InstallerState (Read-DaMaoInstallerState -Path $sharedStatePath))
    foreach ($relativePath in $script:DaMaoRimeOwnershipPaths.Values) {
        Assert-UninstallInvariant (Test-Path -LiteralPath (Join-Path $sharedRime $relativePath)) `
            "Shared wubi86 dependency was removed while another schema still referenced it: $relativePath"
    }

    # Registry discovery uses the registered current command; cancellation/failure never blocks BigCat cleanup.
    $fakeUninstaller = Join-Path $testRoot 'weasel current\uninstall.exe'
    Write-TestText -Path $fakeUninstaller -Content 'fixture'
    $registryEntries = @(
        [PSCustomObject]@{ KeyName='Other'; DisplayName='Other'; UninstallString='C:\missing.exe'; QuietUninstallString=''; RegistryPath='mock:other' },
        [PSCustomObject]@{ KeyName='Weasel'; DisplayName='小狼毫 Weasel 9.9'; UninstallString=('"' + $fakeUninstaller + '" /current'); QuietUninstallString=''; RegistryPath='mock:weasel' }
    )
    $command = Find-DaMaoWeaselUninstallCommand -RegistryEntries $registryEntries
    Assert-UninstallInvariant ($null -ne $command -and $command.Executable -ceq $fakeUninstaller -and
        $command.Arguments -ceq '/current' -and $command.RegistryPath -ceq 'mock:weasel') `
        'Weasel uninstall discovery did not return the current registered command.'

    $failureRoot = Join-Path $testRoot 'failure'
    $failureRime = Join-Path $failureRoot 'Rime'
    $failureStatePath = Join-Path $failureRoot 'installer-state.ini'
    New-Item -ItemType Directory -Path $failureRime -Force | Out-Null
    Write-TestText -Path (Join-Path $failureRime 'damao_wubi.schema.yaml') -Content 'bigcat'
    Write-DaMaoInstallerState -Path $failureStatePath -WeaselOrigin PreExisting -RimeUserDir $failureRime
    $failureCounters = @{ Redeploy = 0 }
    $failureResult = Invoke-DaMaoBigCatUninstall -InstallerStatePath $failureStatePath `
        -RimeUserDir $failureRime -RemoveWeasel `
        -RegistryReader { return $registryEntries }.GetNewClosure() `
        -UninstallerInvoker { param($registeredCommand) return 1602 } `
        -WeaselRootDiscovery { return 'X:\MockWeasel' } `
        -WeaselPreparer { param($root) } `
        -DeployerInvoker { param($root) $failureCounters.Redeploy++ }.GetNewClosure()
    Assert-UninstallInvariant ($failureResult.WeaselStatus -ceq 'Failed' -and
        $failureResult.WeaselFailure -match '1602') 'Weasel cancellation/failure was not surfaced distinctly.'
    Assert-UninstallInvariant (-not (Test-Path -LiteralPath (Join-Path $failureRime 'damao_wubi.schema.yaml'))) `
        'Weasel uninstall failure prevented BigCat cleanup.'
    Assert-UninstallInvariant (-not (Test-Path -LiteralPath $failureStatePath)) `
        'Installer state survived the completed BigCat uninstall flow.'
    Assert-UninstallInvariant ($failureCounters.Redeploy -eq 1) `
        'A retained Weasel was not redeployed after its official uninstaller failed.'
    Assert-UninstallInvariant ((Get-DaMaoBigCatUninstallExitCode -Result $failureResult -RemoveWeasel) -eq 41) `
        'A failed or cancelled official Weasel uninstall did not retain its actionable warning exit code.'

    $successRoot = Join-Path $testRoot 'success'
    $successRime = Join-Path $successRoot 'Rime'
    $successStatePath = Join-Path $successRoot 'installer-state.ini'
    New-Item -ItemType Directory -Path $successRime -Force | Out-Null
    Write-TestText -Path (Join-Path $successRime 'damao_wubi.schema.yaml') -Content 'bigcat'
    Write-DaMaoInstallerState -Path $successStatePath -WeaselOrigin BigCatBootstrap -RimeUserDir $successRime
    $successCounters = @{ Invoke = 0 }
    $successResult = Invoke-DaMaoBigCatUninstall -InstallerStatePath $successStatePath `
        -RimeUserDir $successRime -RemoveWeasel `
        -RegistryReader { return $registryEntries }.GetNewClosure() `
        -UninstallerInvoker { param($registeredCommand) $successCounters.Invoke++; return 0 }.GetNewClosure() `
        -WeaselRootDiscovery { return 'X:\MockWeasel' } `
        -WeaselPreparer { param($root) } `
        -DeployerInvoker { throw 'must not redeploy after successful Weasel removal' }
    Assert-UninstallInvariant ($successResult.WeaselStatus -ceq 'Removed' -and $successCounters.Invoke -eq 1) `
        'BigCatBootstrap default removal path did not invoke the registered Weasel uninstaller exactly once.'

    # Regression: a server /quit timeout is diagnostic only when the official
    # Weasel uninstaller subsequently succeeds.
    $quitTimeoutRoot = Join-Path $testRoot 'quit-timeout-success'
    $quitTimeoutRime = Join-Path $quitTimeoutRoot 'Rime'
    $quitTimeoutStatePath = Join-Path $quitTimeoutRoot 'installer-state.ini'
    $quitTimeoutLog = Join-Path $quitTimeoutRoot 'uninstall.log'
    New-Item -ItemType Directory -Path $quitTimeoutRime -Force | Out-Null
    Write-TestText -Path (Join-Path $quitTimeoutRime 'damao_wubi.schema.yaml') -Content 'bigcat'
    Write-DaMaoInstallerState -Path $quitTimeoutStatePath -WeaselOrigin BigCatBootstrap `
        -RimeUserDir $quitTimeoutRime
    $quitTimeoutCounters = @{ Invoke = 0 }
    $previousUninstallLog = $script:DaMaoUninstallLog
    try {
        $script:DaMaoUninstallLog = $quitTimeoutLog
        $quitTimeoutResult = Invoke-DaMaoBigCatUninstall `
            -InstallerStatePath $quitTimeoutStatePath -RimeUserDir $quitTimeoutRime -RemoveWeasel `
            -RegistryReader { return $registryEntries }.GetNewClosure() `
            -UninstallerInvoker {
                param($registeredCommand)
                $quitTimeoutCounters.Invoke++
                return 0
            }.GetNewClosure() `
            -WeaselRootDiscovery { return 'X:\MockWeasel' } `
            -WeaselPreparer { throw 'WeaselServer.exe /quit did not finish within 30 seconds.' } `
            -DeployerInvoker { throw 'must not redeploy after successful Weasel removal' }
        $quitTimeoutLogText = [System.IO.File]::ReadAllText($quitTimeoutLog)
    }
    finally {
        $script:DaMaoUninstallLog = $previousUninstallLog
    }
    Assert-UninstallInvariant ($quitTimeoutResult.WeaselStatus -ceq 'Removed' -and
        $quitTimeoutCounters.Invoke -eq 1) `
        'A /quit timeout prevented the official Weasel uninstaller from succeeding.'
    Assert-UninstallInvariant ($quitTimeoutResult.PreparationFailure -match 'did not finish within 30 seconds') `
        'The /quit timeout was not retained as diagnostic information.'
    Assert-UninstallInvariant ((Get-DaMaoBigCatUninstallExitCode `
        -Result $quitTimeoutResult -RemoveWeasel) -eq 0) `
        'A /quit timeout followed by successful official Weasel removal produced a partial-cleanup warning exit code.'
    Assert-UninstallInvariant ($quitTimeoutLogText -match 'WEASEL_SERVER_QUIT_TIMEOUT_CONTINUING' -and
        $quitTimeoutLogText -notmatch 'WEASEL_CLEANUP_PREPARE_FAILED') `
        'The continuing /quit timeout was not logged with non-final diagnostic semantics.'

    $explicitRoot = Join-Path $testRoot 'explicit-preexisting'
    $explicitRime = Join-Path $explicitRoot 'Rime'
    $explicitStatePath = Join-Path $explicitRoot 'installer-state.ini'
    New-Item -ItemType Directory -Path $explicitRime -Force | Out-Null
    Write-TestText -Path (Join-Path $explicitRime 'damao_wubi.schema.yaml') -Content 'bigcat'
    Write-DaMaoInstallerState -Path $explicitStatePath -WeaselOrigin PreExisting -RimeUserDir $explicitRime
    $explicitCounters = @{ Invoke = 0 }
    $explicitResult = Invoke-DaMaoBigCatUninstall -InstallerStatePath $explicitStatePath `
        -RimeUserDir $explicitRime -RemoveWeasel `
        -RegistryReader { return $registryEntries }.GetNewClosure() `
        -UninstallerInvoker { param($registeredCommand) $explicitCounters.Invoke++; return 0 }.GetNewClosure() `
        -WeaselRootDiscovery { return 'X:\MockWeasel' } `
        -WeaselPreparer { param($root) } `
        -DeployerInvoker { throw 'must not redeploy after successful Weasel removal' }
    Assert-UninstallInvariant ($explicitResult.WeaselStatus -ceq 'Removed' -and $explicitCounters.Invoke -eq 1) `
        'Explicit PreExisting removal did not invoke the registered Weasel uninstaller.'

    $retainedRoot = Join-Path $testRoot 'retained-bootstrap'
    $retainedRime = Join-Path $retainedRoot 'Rime'
    $retainedStatePath = Join-Path $retainedRoot 'installer-state.ini'
    New-Item -ItemType Directory -Path $retainedRime -Force | Out-Null
    Write-TestText -Path (Join-Path $retainedRime 'damao_wubi.schema.yaml') -Content 'bigcat'
    Write-DaMaoInstallerState -Path $retainedStatePath -WeaselOrigin BigCatBootstrap -RimeUserDir $retainedRime
    $retainedCounters = @{ Redeploy = 0 }
    $retainedResult = Invoke-DaMaoBigCatUninstall -InstallerStatePath $retainedStatePath `
        -RimeUserDir $retainedRime `
        -RegistryReader { throw 'registry must not be read when the checkbox is clear' } `
        -UninstallerInvoker { throw 'uninstaller must not run when the checkbox is clear' } `
        -WeaselRootDiscovery { return 'X:\MockWeasel' } `
        -WeaselPreparer { param($root) } `
        -DeployerInvoker { param($root) $retainedCounters.Redeploy++ }.GetNewClosure()
    Assert-UninstallInvariant ($retainedResult.WeaselStatus -ceq 'Retained' -and
        $retainedCounters.Redeploy -eq 1) `
        'Clearing the BigCatBootstrap checkbox did not retain and redeploy Weasel.'
    Assert-UninstallInvariant ((Get-DaMaoBigCatUninstallExitCode -Result $retainedResult) -eq 0) `
        'A successful keep-Weasel cleanup and redeploy did not return success.'
    $keepWeaselRedeployFailure = [PSCustomObject]@{
        Cleanup = [PSCustomObject]@{ Failures = @() }
        WeaselStatus = 'Retained'
        RedeployFailure = 'mock deploy failure'
    }
    Assert-UninstallInvariant ((Get-DaMaoBigCatUninstallExitCode `
        -Result $keepWeaselRedeployFailure) -eq 42) `
        'The keep-Weasel path stopped strictly reporting an actual redeploy failure.'

    $modifiedRoot = Join-Path $testRoot 'modified-shared'
    $modifiedRime = Join-Path $modifiedRoot 'Rime'
    $modifiedStatePath = Join-Path $modifiedRoot 'installer-state.ini'
    New-Item -ItemType Directory -Path $modifiedRime -Force | Out-Null
    $modifiedOwnership = @{}
    foreach ($key in $script:DaMaoRimeOwnershipPaths.Keys) {
        $path = Join-Path $modifiedRime $script:DaMaoRimeOwnershipPaths[$key]
        Write-TestText -Path $path -Content "owned:$key"
        $modifiedOwnership[$key] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }
    Write-DaMaoInstallerState -Path $modifiedStatePath -WeaselOrigin BigCatBootstrap `
        -RimeUserDir $modifiedRime -RimeOwnership $modifiedOwnership
    Write-TestText -Path (Join-Path $modifiedRime 'wubi86.dict.yaml') -Content 'user modified after install'
    [void](Remove-DaMaoBigCatOwnedArtifacts -RimeUserDir $modifiedRime `
        -InstallerState (Read-DaMaoInstallerState -Path $modifiedStatePath))
    Assert-UninstallInvariant (Test-Path -LiteralPath (Join-Path $modifiedRime 'wubi86.dict.yaml')) `
        'A user-modified shared dictionary was deleted despite its hash mismatch.'

    $plan = Get-DaMaoBigCatOwnedArtifactPlan
    Assert-UninstallInvariant ((@($plan.Files + $plan.Directories) -join "`n") -notmatch '\*|\?') `
        'BigCat cleanup plan contains a wildcard path.'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}

if ($failures.Count -gt 0) {
    throw "Installer uninstall tests failed:`n - $($failures -join "`n - ")"
}

Write-Host "Installer uninstall tests passed ($assertionCount assertions)."
