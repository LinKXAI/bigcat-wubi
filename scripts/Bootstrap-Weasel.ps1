[CmdletBinding()]
param(
    [switch]$ProbeOnly,
    [string]$BundledWeaselInstallerPath,
    [string]$BundledWubiSourcePath,
    [string]$InstallerStatePath,
    [string]$ExistingWeaselOrigin,
    [switch]$LegacyInstallPresent,
    [ValidateSet('Wubi','Pinyin')][string]$DefaultEntry = 'Wubi'
)

$ErrorActionPreference = 'Stop'

$script:DaMaoPinnedWeaselVersion = '0.17.4'
$script:DaMaoPinnedWeaselInstallerUrl = 'https://github.com/rime/weasel/releases/download/0.17.4/weasel-0.17.4.0-installer.exe'
$script:DaMaoPinnedWeaselInstallerSha256 = 'CF509534A8F5F8AF9C98ED7CBB8F135439F145A8CBE7E50EDE42BB5B5AB45C29'
$script:DaMaoWeaselBootstrapLog = Join-Path ([System.IO.Path]::GetTempPath()) 'BigCatWubi-bootstrap.log'
$script:DaMaoWeaselInstallerTimeoutSeconds = 600
$script:DaMaoWeaselRediscoveryIntervalMilliseconds = 1000
$script:DaMaoWeaselRediscoveryTimeoutSeconds = 60

. (Join-Path $PSScriptRoot 'DaMao.InstallerState.ps1')

function Write-DaMaoWeaselBootstrapEvent {
    param(
        [Parameter(Mandatory = $true)][string]$Event,
        [string]$Detail
    )

    $line = "[$(Get-Date -Format o)] $Event"
    if (-not [string]::IsNullOrWhiteSpace($Detail)) {
        $line += " $Detail"
    }
    try {
        Add-Content -LiteralPath $script:DaMaoWeaselBootstrapLog -Value $line -Encoding UTF8
    }
    catch {
        # Diagnostic logging must never replace the original bootstrap outcome.
    }
    Write-Host $line
}

function Get-DaMaoWeaselInstallationEvidence {
    $registryPaths = @(
        'HKLM:\SOFTWARE\Rime\Weasel',
        'HKLM:\SOFTWARE\WOW6432Node\Rime\Weasel'
    )
    foreach ($registryPath in $registryPaths) {
        $settings = Get-ItemProperty -LiteralPath $registryPath -ErrorAction SilentlyContinue
        if ($null -eq $settings) {
            continue
        }
        foreach ($propertyName in @('WeaselRoot', 'InstallDir')) {
            $property = $settings.PSObject.Properties[$propertyName]
            if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
                return 'REGISTRY_EVIDENCE'
            }
        }
        return 'REGISTRY_EVIDENCE'
    }

    foreach ($uninstallRegistryPath in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Weasel',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Weasel'
    )) {
        if (Test-Path -LiteralPath $uninstallRegistryPath) {
            return 'REGISTRY_EVIDENCE'
        }
    }

    foreach ($programFilesPath in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ([string]::IsNullOrWhiteSpace($programFilesPath)) {
            continue
        }
        $rimeRoot = Join-Path $programFilesPath 'Rime'
        if (-not (Test-Path -LiteralPath $rimeRoot -PathType Container)) {
            continue
        }
        $versionDirectories = @(Get-ChildItem -LiteralPath $rimeRoot -Directory -Filter 'weasel-*' -ErrorAction SilentlyContinue)
        if ($versionDirectories.Count -gt 0) {
            return 'FILESYSTEM_EVIDENCE'
        }
        $candidateDirectories = @($rimeRoot)
        foreach ($candidateDirectory in $candidateDirectories) {
            $candidatePath = if ($candidateDirectory -is [System.IO.DirectoryInfo]) {
                $candidateDirectory.FullName
            }
            else {
                [string]$candidateDirectory
            }
            foreach ($marker in @('WeaselServer.exe', 'WeaselSetup.exe', 'rime.dll', 'rime-install.bat')) {
                if (Test-Path -LiteralPath (Join-Path $candidatePath $marker) -PathType Leaf) {
                    return 'FILESYSTEM_EVIDENCE'
                }
            }
        }
    }

    return $null
}

function Find-DaMaoWeaselInstallation {
    try {
        $root = Get-DaMaoWeaselRoot
        return [PSCustomObject]@{
            State = 'Usable'
            Root = $root
            Evidence = $null
        }
    }
    catch {
        if ($_.Exception.Message -notmatch '^\[DM-WEASEL-NOT-FOUND\]') {
            throw
        }
    }

    $evidence = Get-DaMaoWeaselInstallationEvidence
    if (-not [string]::IsNullOrWhiteSpace($evidence)) {
        return [PSCustomObject]@{
            State = 'Unusable'
            Root = $null
            Evidence = $evidence
        }
    }

    return [PSCustomObject]@{
        State = 'Absent'
        Root = $null
        Evidence = $null
    }
}

function Test-DaMaoRegularFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    return $item -is [System.IO.FileInfo] -and
        ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0
}

function Copy-DaMaoBundledWeaselInstaller {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    if (-not (Test-DaMaoRegularFile -Path $Source)) {
        throw "Bundled Weasel source is not a regular file: $Source"
    }
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

function Wait-DaMaoDirectInstallerProcess {
    param(
        [Parameter(Mandatory = $true)][System.Diagnostics.Process]$Process,
        [ValidateRange(1, 3600)][int]$TimeoutSeconds = $script:DaMaoWeaselInstallerTimeoutSeconds
    )

    $directProcessExited = $Process.WaitForExit($TimeoutSeconds * 1000)
    if (-not $directProcessExited) {
        throw "The direct Weasel installer process did not exit within $TimeoutSeconds second(s)."
    }
    $Process.Refresh()
    return $Process.ExitCode
}

function Invoke-DaMaoDefaultWeaselInstaller {
    param([Parameter(Mandatory = $true)][string]$InstallerPath)

    $process = Start-Process -FilePath $InstallerPath -ArgumentList '/S' -PassThru
    if ($null -eq $process) {
        throw 'Start-Process returned no process object.'
    }
    return Wait-DaMaoDirectInstallerProcess -Process $process `
        -TimeoutSeconds $script:DaMaoWeaselInstallerTimeoutSeconds
}

function Wait-DaMaoForUsableWeasel {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$DiscoverWeasel,
        [ValidateRange(1, 60)][int]$TimeoutSeconds = $script:DaMaoWeaselRediscoveryTimeoutSeconds,
        [ValidateRange(1, 60000)][int]$RetryIntervalMilliseconds = $script:DaMaoWeaselRediscoveryIntervalMilliseconds,
        [scriptblock]$DelayAction = { param($milliseconds) Start-Sleep -Milliseconds $milliseconds },
        [scriptblock]$UtcNowAction = { [DateTime]::UtcNow }
    )

    $deadline = (& $UtcNowAction).AddSeconds($TimeoutSeconds)
    $installed = & $DiscoverWeasel
    $now = & $UtcNowAction
    while (($null -eq $installed -or $installed.State -ne 'Usable') -and $now -lt $deadline) {
        $remainingMilliseconds = [int][Math]::Ceiling(($deadline - $now).TotalMilliseconds)
        $delayMilliseconds = [Math]::Min($RetryIntervalMilliseconds, $remainingMilliseconds)
        & $DelayAction $delayMilliseconds
        $installed = & $DiscoverWeasel
        $now = & $UtcNowAction
    }

    if ($null -ne $installed -and $installed.State -eq 'Usable') {
        return $installed
    }
    return $null
}

function Invoke-DaMaoWeaselBootstrapFlow {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$DiscoverWeasel,
        [Parameter(Mandatory = $true)][scriptblock]$StageInstaller,
        [Parameter(Mandatory = $true)][scriptblock]$GetInstallerHash,
        [Parameter(Mandatory = $true)][scriptblock]$StartInstaller,
        [Parameter(Mandatory = $true)][scriptblock]$DeployBigCat,
        [scriptblock]$RecordOrigin = { param($origin, $root) },
        [AllowNull()][AllowEmptyString()][string]$ExistingOrigin,
        [switch]$LegacyInstallPresent,
        [string]$BundledInstallerPath,
        [string]$StagingParent = ([System.IO.Path]::GetTempPath()),
        [ValidateRange(1, 60)][int]$RediscoveryTimeoutSeconds = $script:DaMaoWeaselRediscoveryTimeoutSeconds,
        [ValidateRange(1, 60000)][int]$RediscoveryIntervalMilliseconds = $script:DaMaoWeaselRediscoveryIntervalMilliseconds,
        [scriptblock]$RediscoveryDelayAction = { param($milliseconds) Start-Sleep -Milliseconds $milliseconds },
        [scriptblock]$UtcNowAction = { [DateTime]::UtcNow }
    )

    $initial = & $DiscoverWeasel
    if ($null -eq $initial -or [string]::IsNullOrWhiteSpace([string]$initial.State)) {
        throw '[DM-WEASEL-DISCOVERY-INVALID] Weasel discovery returned no classified state.'
    }

    if ($initial.State -eq 'Usable') {
        $origin = Resolve-DaMaoWeaselOrigin -ExistingOrigin $ExistingOrigin `
            -InitialWeaselState Usable -LegacyInstallPresent:$LegacyInstallPresent
        Write-DaMaoWeaselBootstrapEvent -Event 'EXISTING_WEASEL' -Detail "ORIGIN=$origin"
        & $RecordOrigin $origin $initial.Root
        & $DeployBigCat $initial.Root
        return [PSCustomObject]@{ Bootstrap = $false; WeaselRoot = $initial.Root; WeaselOrigin = $origin }
    }

    if ($initial.State -eq 'Unusable') {
        Write-DaMaoWeaselBootstrapEvent -Event 'WEASEL_EXISTING_UNUSABLE' -Detail ([string]$initial.Evidence)
        throw '[DM-WEASEL-EXISTING-UNUSABLE] Existing Weasel evidence is present, but the V1-required deployer is unusable. Bootstrap stopped to avoid replacing or changing that installation.'
    }

    if ($initial.State -ne 'Absent') {
        throw "[DM-WEASEL-DISCOVERY-INVALID] Unknown Weasel discovery state: $($initial.State)"
    }

    if ([string]::IsNullOrWhiteSpace($BundledInstallerPath)) {
        throw '[DM-WEASEL-BUNDLED-ASSET-INVALID] Weasel is absent, but no bundled official installer path was provided. BigCat deployment did not start.'
    }

    Write-DaMaoWeaselBootstrapEvent -Event 'WEASEL_ABSENT'
    $stage = Join-Path $StagingParent "BigCatWubi-Weasel-$([Guid]::NewGuid().ToString('N'))"
    $installerPath = Join-Path $stage 'weasel-0.17.4.0-installer.exe'
    try {
        New-Item -ItemType Directory -Path $stage -Force | Out-Null
        Write-DaMaoWeaselBootstrapEvent -Event 'WEASEL_BUNDLED_ASSET_STAGING_STARTED' -Detail "VERSION=$script:DaMaoPinnedWeaselVersion"
        try {
            & $StageInstaller $BundledInstallerPath $installerPath
        }
        catch {
            Write-DaMaoWeaselBootstrapEvent -Event 'WEASEL_BUNDLED_ASSET_STAGING_FAILED'
            throw '[DM-WEASEL-BUNDLED-ASSET-FAILED] Weasel is required, but the bundled pinned official installer could not be staged. BigCat deployment did not start.'
        }

        if (-not (Test-DaMaoRegularFile -Path $installerPath)) {
            Write-DaMaoWeaselBootstrapEvent -Event 'WEASEL_BUNDLED_ASSET_STAGING_FAILED' -Detail 'NOT_REGULAR_FILE'
            throw '[DM-WEASEL-BUNDLED-ASSET-INVALID] The staged bundled Weasel installer is not a verifiable regular file. It will not be executed.'
        }

        try {
            $actualHash = [string](& $GetInstallerHash $installerPath)
        }
        catch {
            Write-DaMaoWeaselBootstrapEvent -Event 'WEASEL_HASH_MISMATCH' -Detail 'HASH_READ_FAILED'
            throw '[DM-WEASEL-HASH-MISMATCH] The Weasel installer SHA-256 could not be read. It will not be executed.'
        }
        if (-not [string]::Equals($actualHash.Trim(), $script:DaMaoPinnedWeaselInstallerSha256,
            [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-DaMaoWeaselBootstrapEvent -Event 'WEASEL_HASH_MISMATCH'
            throw '[DM-WEASEL-HASH-MISMATCH] The Weasel installer SHA-256 does not match the pin. It will not be executed.'
        }

        Write-DaMaoWeaselBootstrapEvent -Event 'WEASEL_HASH_VERIFIED'
        Write-DaMaoWeaselBootstrapEvent -Event 'WEASEL_INSTALL_STARTED' -Detail "VERSION=$script:DaMaoPinnedWeaselVersion"
        try {
            $installExitCode = & $StartInstaller $installerPath
        }
        catch {
            Write-DaMaoWeaselBootstrapEvent -Event 'WEASEL_INSTALL_FAILED'
            throw '[DM-WEASEL-INSTALL-FAILED] The official Weasel installer could not be started or completed. BigCat deployment did not start.'
        }
        if ([int]$installExitCode -ne 0) {
            Write-DaMaoWeaselBootstrapEvent -Event 'WEASEL_INSTALL_FAILED' -Detail "EXIT_CODE=$installExitCode"
            throw "[DM-WEASEL-INSTALL-FAILED] The official Weasel installer returned exit code $installExitCode. BigCat deployment did not start."
        }

        $installed = Wait-DaMaoForUsableWeasel -DiscoverWeasel $DiscoverWeasel `
            -TimeoutSeconds $RediscoveryTimeoutSeconds `
            -RetryIntervalMilliseconds $RediscoveryIntervalMilliseconds `
            -DelayAction $RediscoveryDelayAction -UtcNowAction $UtcNowAction
        if ($null -eq $installed) {
            Write-DaMaoWeaselBootstrapEvent -Event 'WEASEL_POST_INSTALL_NOT_FOUND'
            throw '[DM-WEASEL-POST-INSTALL-NOT-FOUND] The Weasel installer returned, but V1 discovery still found no usable deployer. BigCat deployment did not start.'
        }

        Write-DaMaoWeaselBootstrapEvent -Event 'WEASEL_BOOTSTRAP_SUCCEEDED'
        $origin = Resolve-DaMaoWeaselOrigin -ExistingOrigin $ExistingOrigin `
            -InitialWeaselState Absent -LegacyInstallPresent:$LegacyInstallPresent -BootstrapSucceeded
        & $RecordOrigin $origin $installed.Root
        & $DeployBigCat $installed.Root
        return [PSCustomObject]@{ Bootstrap = $true; WeaselRoot = $installed.Root; WeaselOrigin = $origin }
    }
    finally {
        $safeTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\') + '\'
        $resolvedStage = [System.IO.Path]::GetFullPath($stage)
        if ($resolvedStage.StartsWith($safeTempRoot, [System.StringComparison]::OrdinalIgnoreCase) -and
            (Test-Path -LiteralPath $resolvedStage)) {
            Remove-Item -LiteralPath $resolvedStage -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Assert-DaMaoBundledWubiSource {
    param([string]$SourcePath)

    if ([string]::IsNullOrWhiteSpace($SourcePath)) {
        throw '[DM-BUNDLED-WUBI-SOURCE-INVALID] The installer did not provide its bundled rime-wubi source. BigCat deployment did not start.'
    }
    try {
        return Get-DaMaoWubiSourceInfo -SourcePath $SourcePath
    }
    catch {
        throw "[DM-BUNDLED-WUBI-SOURCE-INVALID] The bundled rime-wubi source failed validation. BigCat deployment did not start. $($_.Exception.Message)"
    }
}

function Test-DaMaoFreshRimeUserState {
    param([Parameter(Mandatory = $true)][string]$RimeUserDir)

    if (-not (Test-Path -LiteralPath $RimeUserDir)) {
        return $true
    }
    if (-not (Test-Path -LiteralPath $RimeUserDir -PathType Container)) {
        return $false
    }
    return @(Get-ChildItem -LiteralPath $RimeUserDir -Force -ErrorAction Stop).Count -eq 0
}

function Get-DaMaoWeaselProbeExitCode {
    $probe = Find-DaMaoWeaselInstallation
    switch ($probe.State) {
        'Usable' {
            Write-DaMaoWeaselBootstrapEvent -Event 'WEASEL_PROBE_USABLE'
            return 0
        }
        'Absent' {
            Write-DaMaoWeaselBootstrapEvent -Event 'WEASEL_PROBE_ABSENT'
            return 10
        }
        'Unusable' {
            Write-DaMaoWeaselBootstrapEvent -Event 'WEASEL_PROBE_UNUSABLE' -Detail ([string]$probe.Evidence)
            return 25
        }
        default {
            throw "[DM-WEASEL-DISCOVERY-INVALID] Unknown Weasel discovery state: $($probe.State)"
        }
    }
}

function Set-DaMaoPreflightedInstallerProvenance {
    param([string]$Path, [string]$WeaselOrigin, [string]$RimeUserDir, [string]$WeaselRoot)
    . (Join-Path $PSScriptRoot 'DaMao.Quanpin.ps1')
    Assert-DaMaoQuanpinSharedPolicy -PolicyPath (Join-Path $PSScriptRoot '..\schemas\luna_quanpin.custom.yaml') -WeaselRoot $WeaselRoot
    if(-not [string]::IsNullOrWhiteSpace($Path)){
        Set-DaMaoInstallerProvenance -Path $Path -WeaselOrigin $WeaselOrigin -RimeUserDir $RimeUserDir
    }
}

function Invoke-DaMaoWeaselBootstrapEntryPoint {
    . (Join-Path $PSScriptRoot 'DaMao.Common.ps1')
    $installScript = Join-Path $PSScriptRoot 'Install-DaMaoWithQuanpin.ps1'

    Assert-DaMaoBundledWubiSource -SourcePath $BundledWubiSourcePath | Out-Null
    $rimeUserDir = Get-DaMaoRimeUserDir
    $initializeFreshRimeState = Test-DaMaoFreshRimeUserState -RimeUserDir $rimeUserDir
    $preservedOrigin = $ExistingWeaselOrigin
    if (-not (Test-DaMaoWeaselOrigin -Origin $preservedOrigin) -and
        -not [string]::IsNullOrWhiteSpace($InstallerStatePath)) {
        $existingState = Read-DaMaoInstallerState -Path $InstallerStatePath
        if ($existingState.IsTrusted) {
            $preservedOrigin = $existingState.WeaselOrigin
        }
    }

    $discover = { Find-DaMaoWeaselInstallation }
    $stage = { param($source, $destination) Copy-DaMaoBundledWeaselInstaller -Source $source -Destination $destination }
    $hash = { param($path) (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
    $start = { param($path) Invoke-DaMaoDefaultWeaselInstaller -InstallerPath $path }
    $deploy = {
        param($weaselRoot)
        $installParameters = @{
            InstallWubiDependency = $true
            WubiSourcePath = $BundledWubiSourcePath
            WeaselRoot = $weaselRoot
            DefaultEntry = $DefaultEntry
        }
        if ($initializeFreshRimeState) {
            $installParameters.InitializeFreshRimeState = $true
        }
        if (-not [string]::IsNullOrWhiteSpace($InstallerStatePath)) {
            $installParameters.InstallerStatePath = $InstallerStatePath
        }
        & $installScript @installParameters
    }
    $recordOrigin = {
        param($origin, $weaselRoot)
        Set-DaMaoPreflightedInstallerProvenance -Path $InstallerStatePath `
            -WeaselOrigin $origin -RimeUserDir $rimeUserDir -WeaselRoot $weaselRoot
    }

    Invoke-DaMaoWeaselBootstrapFlow -DiscoverWeasel $discover -StageInstaller $stage `
        -GetInstallerHash $hash -StartInstaller $start -DeployBigCat $deploy `
        -RecordOrigin $recordOrigin -ExistingOrigin $preservedOrigin `
        -LegacyInstallPresent:$LegacyInstallPresent `
        -BundledInstallerPath $BundledWeaselInstallerPath
}

function Get-DaMaoWeaselBootstrapExitCode {
    param([Parameter(Mandatory = $true)][string]$Message)

    $exitCode = switch -Regex ($Message) {
        '^\[DM-WEASEL-BUNDLED-ASSET-(?:FAILED|INVALID)\]' { 21; break }
        '^\[DM-WEASEL-HASH-MISMATCH\]' { 22; break }
        '^\[DM-WEASEL-INSTALL-FAILED\]' { 23; break }
        '^\[DM-WEASEL-POST-INSTALL-NOT-FOUND\]' { 24; break }
        '^\[DM-WEASEL-EXISTING-UNUSABLE\]' { 25; break }
        '^\[DM-BUNDLED-WUBI-SOURCE-INVALID\]' { 26; break }
        default { 1 }
    }
    return $exitCode
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        if ($ProbeOnly) {
            . (Join-Path $PSScriptRoot 'DaMao.Common.ps1')
            $probeExitCode = Get-DaMaoWeaselProbeExitCode
            $Host.SetShouldExit($probeExitCode)
            return
        }
        Invoke-DaMaoWeaselBootstrapEntryPoint
    }
    catch {
        $message = $_.Exception.Message
        [Console]::Error.WriteLine($message)
        $exitCode = Get-DaMaoWeaselBootstrapExitCode -Message $message
        $Host.SetShouldExit($exitCode)
        return
    }
}
