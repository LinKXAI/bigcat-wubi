[CmdletBinding()]
param(
    [string]$InstallerStatePath,
    [string]$RimeUserDir,
    [switch]$RemoveWeasel
)

$ErrorActionPreference = 'Stop'
$script:DaMaoUninstallLog = Join-Path ([System.IO.Path]::GetTempPath()) 'BigCatWubi-uninstall.log'
$script:DaMaoWeaselUninstallTimeoutSeconds = 600

. (Join-Path $PSScriptRoot 'DaMao.Common.ps1')
. (Join-Path $PSScriptRoot 'DaMao.InstallerState.ps1')

function Write-DaMaoUninstallEvent {
    param(
        [Parameter(Mandatory = $true)][string]$Event,
        [string]$Detail
    )

    $line = "[$(Get-Date -Format o)] $Event"
    if (-not [string]::IsNullOrWhiteSpace($Detail)) {
        $line += " $Detail"
    }
    try {
        Add-Content -LiteralPath $script:DaMaoUninstallLog -Value $line -Encoding UTF8
    }
    catch {
        # Logging cannot change uninstall semantics.
    }
    Write-Host $line
}

function Get-DaMaoBigCatOwnedArtifactPlan {
    return [PSCustomObject]@{
        Files = @(
            'damao_wubi.schema.yaml',
            'damao_wubi\branding\bigcat-ime.ico',
            'build\damao_wubi.schema.yaml',
            'damao_wubi.userdb.kct'
        )
        Directories = @('damao_wubi.userdb')
        EmptyDirectories = @('damao_wubi\branding', 'damao_wubi')
        SharedFiles = @($script:DaMaoRimeOwnershipPaths.Values)
        Preserved = @(
            'sync',
            'backup',
            'damao_wubi.custom.yaml',
            'all unrelated schemas, dictionaries, configuration, and userdb artifacts'
        )
    }
}

function Test-DaMaoOtherSchemaUsesWubi86 {
    param([Parameter(Mandatory = $true)][string]$RimeUserDir)

    if (-not (Test-Path -LiteralPath $RimeUserDir -PathType Container)) {
        return $false
    }
    foreach ($schemaFile in @(Get-ChildItem -LiteralPath $RimeUserDir -File -Filter '*.schema.yaml' -ErrorAction SilentlyContinue)) {
        if ($schemaFile.Name -ceq 'damao_wubi.schema.yaml') {
            continue
        }
        try {
            if ([System.IO.File]::ReadAllText($schemaFile.FullName) -match
                '(?m)^\s*dictionary:\s*["'']?wubi86["'']?\s*(?:#.*)?$') {
                return $true
            }
        }
        catch {
            return $true
        }
    }
    return $false
}

function Remove-DaMaoBigCatOwnedArtifacts {
    param(
        [Parameter(Mandatory = $true)][string]$RimeUserDir,
        [Parameter(Mandatory = $true)]$InstallerState
    )

    $failures = [System.Collections.Generic.List[string]]::new()
    $removed = [System.Collections.Generic.List[string]]::new()
    $resolvedRimeUserDir = [System.IO.Path]::GetFullPath($RimeUserDir)
    $plan = Get-DaMaoBigCatOwnedArtifactPlan
    if (-not (Test-Path -LiteralPath $resolvedRimeUserDir -PathType Container)) {
        return [PSCustomObject]@{ Removed = @(); Failures = @() }
    }

    $defaultCustomPath = Join-Path $resolvedRimeUserDir 'default.custom.yaml'
    try {
        if (Remove-DaMaoSchemaSelection -DefaultCustomPath $defaultCustomPath) {
            $removed.Add('default.custom.yaml:damao_wubi schema registration')
        }
    }
    catch {
        $failures.Add("default.custom.yaml: $($_.Exception.Message)")
    }

    foreach ($relativePath in $plan.Files) {
        $path = Join-Path $resolvedRimeUserDir $relativePath
        try {
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                Remove-Item -LiteralPath $path -Force
                $removed.Add($relativePath)
            }
        }
        catch {
            $failures.Add("${relativePath}: $($_.Exception.Message)")
        }
    }
    foreach ($relativePath in $plan.Directories) {
        $path = Join-Path $resolvedRimeUserDir $relativePath
        try {
            if ((Test-DaMaoPathWithin -Path $path -Parent $resolvedRimeUserDir) -and
                (Test-Path -LiteralPath $path -PathType Container)) {
                Remove-Item -LiteralPath $path -Recurse -Force
                $removed.Add($relativePath)
            }
        }
        catch {
            $failures.Add("${relativePath}: $($_.Exception.Message)")
        }
    }

    $stateMatchesRimeDir = $InstallerState.IsTrusted -and
        -not [string]::IsNullOrWhiteSpace([string]$InstallerState.RimeUserDir) -and
        [string]::Equals([System.IO.Path]::GetFullPath([string]$InstallerState.RimeUserDir),
            $resolvedRimeUserDir, [System.StringComparison]::OrdinalIgnoreCase)
    $otherSchemaUsesWubi = Test-DaMaoOtherSchemaUsesWubi86 -RimeUserDir $resolvedRimeUserDir
    if ($stateMatchesRimeDir -and -not $otherSchemaUsesWubi) {
        foreach ($key in $script:DaMaoRimeOwnershipPaths.Keys) {
            if (-not $InstallerState.RimeOwnership.ContainsKey($key)) {
                continue
            }
            $relativePath = $script:DaMaoRimeOwnershipPaths[$key]
            $path = Join-Path $resolvedRimeUserDir $relativePath
            try {
                if ((Test-Path -LiteralPath $path -PathType Leaf) -and
                    (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ceq
                        [string]$InstallerState.RimeOwnership[$key]) {
                    Remove-Item -LiteralPath $path -Force
                    $removed.Add($relativePath)
                }
            }
            catch {
                $failures.Add("${relativePath}: $($_.Exception.Message)")
            }
        }
    }

    foreach ($relativePath in $plan.EmptyDirectories) {
        $path = Join-Path $resolvedRimeUserDir $relativePath
        try {
            if ((Test-Path -LiteralPath $path -PathType Container) -and
                @(Get-ChildItem -LiteralPath $path -Force).Count -eq 0) {
                Remove-Item -LiteralPath $path -Force
                $removed.Add("$relativePath (empty directory)")
            }
        }
        catch {
            $failures.Add("${relativePath}: $($_.Exception.Message)")
        }
    }
    return [PSCustomObject]@{ Removed = $removed.ToArray(); Failures = $failures.ToArray() }
}

function Split-DaMaoRegisteredUninstallString {
    param([Parameter(Mandatory = $true)][string]$CommandLine)

    $match = [regex]::Match($CommandLine, '^\s*"(?<exe>[^"]+\.exe)"\s*(?<args>.*)$',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) {
        $match = [regex]::Match($CommandLine, '^\s*(?<exe>.+?\.exe)\s*(?<args>.*)$',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }
    if (-not $match.Success) {
        return $null
    }
    return [PSCustomObject]@{
        Executable = [Environment]::ExpandEnvironmentVariables($match.Groups['exe'].Value.Trim())
        Arguments = $match.Groups['args'].Value.Trim()
    }
}

function Get-DaMaoPropertyString {
    param(
        [Parameter(Mandatory = $true)]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) {
        return ''
    }
    return [string]$property.Value
}

function Get-DaMaoWeaselUninstallRegistryEntries {
    $roots = @(
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }
        foreach ($key in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            $values = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
            if ($null -eq $values) {
                continue
            }
            $entries.Add([PSCustomObject]@{
                KeyName = $key.PSChildName
                DisplayName = Get-DaMaoPropertyString -InputObject $values -Name DisplayName
                Publisher = Get-DaMaoPropertyString -InputObject $values -Name Publisher
                UninstallString = Get-DaMaoPropertyString -InputObject $values -Name UninstallString
                QuietUninstallString = Get-DaMaoPropertyString -InputObject $values -Name QuietUninstallString
                RegistryPath = $key.PSPath
            })
        }
    }
    return $entries.ToArray()
}

function Find-DaMaoWeaselUninstallCommand {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$RegistryEntries)

    foreach ($entry in $RegistryEntries) {
        $keyName = Get-DaMaoPropertyString -InputObject $entry -Name KeyName
        $displayName = Get-DaMaoPropertyString -InputObject $entry -Name DisplayName
        $identityMatches = [string]::Equals($keyName, 'Weasel',
            [System.StringComparison]::OrdinalIgnoreCase) -or
            $displayName -match '(?i)\bWeasel\b|\u5c0f\u72fc\u6beb'
        if (-not $identityMatches) {
            continue
        }
        foreach ($propertyName in @('UninstallString', 'QuietUninstallString')) {
            $commandLine = Get-DaMaoPropertyString -InputObject $entry -Name $propertyName
            if ([string]::IsNullOrWhiteSpace($commandLine)) {
                continue
            }
            $command = Split-DaMaoRegisteredUninstallString -CommandLine $commandLine
            if ($null -ne $command -and
                (Test-Path -LiteralPath $command.Executable -PathType Leaf)) {
                return [PSCustomObject]@{
                    Executable = $command.Executable
                    Arguments = $command.Arguments
                    RegistryPath = Get-DaMaoPropertyString -InputObject $entry -Name RegistryPath
                    SourceValue = $propertyName
                }
            }
        }
    }
    return $null
}

function Invoke-DaMaoRegisteredWeaselUninstaller {
    param([Parameter(Mandatory = $true)]$Command)

    $startParameters = @{
        FilePath = $Command.Executable
        PassThru = $true
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Command.Arguments)) {
        $startParameters.ArgumentList = [string]$Command.Arguments
    }
    $process = Start-Process @startParameters
    if ($null -eq $process) {
        throw 'Start-Process returned no process object.'
    }
    if (-not $process.WaitForExit($script:DaMaoWeaselUninstallTimeoutSeconds * 1000)) {
        throw "The registered Weasel uninstaller did not exit within $script:DaMaoWeaselUninstallTimeoutSeconds second(s)."
    }
    $process.Refresh()
    return $process.ExitCode
}

function Stop-DaMaoWeaselForCleanup {
    param([Parameter(Mandatory = $true)][string]$WeaselRoot)

    $server = Join-Path $WeaselRoot 'WeaselServer.exe'
    if (-not (Test-Path -LiteralPath $server -PathType Leaf)) {
        throw "WeaselServer.exe was not found for the cleanup preparation step: $server"
    }
    $process = Start-Process -FilePath $server -ArgumentList '/quit' -PassThru -WindowStyle Hidden
    if ($null -eq $process -or -not $process.WaitForExit(30000)) {
        throw 'WeaselServer.exe /quit did not finish within 30 seconds.'
    }
    $process.Refresh()
    if ($process.ExitCode -ne 0) {
        throw "WeaselServer.exe /quit returned exit code $($process.ExitCode)."
    }
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    while (@(Get-Process -Name 'WeaselServer' -ErrorAction SilentlyContinue).Count -gt 0 -and
        [DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 250
    }
    if (@(Get-Process -Name 'WeaselServer' -ErrorAction SilentlyContinue).Count -gt 0) {
        throw 'WeaselServer remained active after the official /quit request.'
    }
}

function Invoke-DaMaoBigCatUninstall {
    param(
        [Parameter(Mandatory = $true)][string]$InstallerStatePath,
        [string]$RimeUserDir,
        [switch]$RemoveWeasel,
        [scriptblock]$RegistryReader = { Get-DaMaoWeaselUninstallRegistryEntries },
        [scriptblock]$UninstallerInvoker = { param($command) Invoke-DaMaoRegisteredWeaselUninstaller -Command $command },
        [scriptblock]$WeaselRootDiscovery = {
            try { Get-DaMaoWeaselRoot } catch { return $null }
        },
        [scriptblock]$WeaselPreparer = { param($root) Stop-DaMaoWeaselForCleanup -WeaselRoot $root },
        [scriptblock]$DeployerInvoker = { param($root) Invoke-DaMaoDeployer -WeaselRoot $root -Command '/deploy' -TimeoutSeconds 120 }
    )

    $state = Read-DaMaoInstallerState -Path $InstallerStatePath
    $resolvedRimeUserDir = $RimeUserDir
    if ([string]::IsNullOrWhiteSpace($resolvedRimeUserDir) -and $state.IsTrusted) {
        $resolvedRimeUserDir = $state.RimeUserDir
    }
    if ([string]::IsNullOrWhiteSpace($resolvedRimeUserDir)) {
        $resolvedRimeUserDir = Get-DaMaoRimeUserDir
    }

    $cleanup = $null
    $weaselStatus = 'Retained'
    $weaselFailure = $null
    $preparationFailure = $null
    $redeployFailure = $null
    try {
        $weaselRoot = & $WeaselRootDiscovery
        if (-not [string]::IsNullOrWhiteSpace([string]$weaselRoot)) {
            try {
                & $WeaselPreparer $weaselRoot
                Write-DaMaoUninstallEvent -Event 'WEASEL_CLEANUP_PREPARED'
            }
            catch {
                $preparationFailure = $_.Exception.Message
                $preparationEvent = if ($preparationFailure -match
                    'did not finish within|remained active after the official /quit request') {
                    'WEASEL_SERVER_QUIT_TIMEOUT_CONTINUING'
                }
                else {
                    'WEASEL_SERVER_QUIT_FAILED_CONTINUING'
                }
                Write-DaMaoUninstallEvent -Event $preparationEvent -Detail $preparationFailure
            }
        }
        $cleanup = Remove-DaMaoBigCatOwnedArtifacts -RimeUserDir $resolvedRimeUserDir `
            -InstallerState $state
        if ($RemoveWeasel) {
            try {
                $command = Find-DaMaoWeaselUninstallCommand -RegistryEntries @(& $RegistryReader)
                if ($null -eq $command) {
                    throw 'No usable Weasel uninstall command was found in Windows uninstall registration.'
                }
                Write-DaMaoUninstallEvent -Event 'WEASEL_UNINSTALL_STARTED' -Detail $command.RegistryPath
                $exitCode = [int](& $UninstallerInvoker $command)
                if ($exitCode -ne 0) {
                    throw "The registered Weasel uninstaller returned exit code $exitCode."
                }
                $weaselStatus = 'Removed'
                Write-DaMaoUninstallEvent -Event 'WEASEL_UNINSTALL_SUCCEEDED'
            }
            catch {
                $weaselStatus = 'Failed'
                $weaselFailure = $_.Exception.Message
                Write-DaMaoUninstallEvent -Event 'WEASEL_UNINSTALL_FAILED' -Detail $weaselFailure
            }
        }

        if (-not $RemoveWeasel -or $weaselStatus -eq 'Failed') {
            $weaselRoot = & $WeaselRootDiscovery
            if (-not [string]::IsNullOrWhiteSpace([string]$weaselRoot)) {
                try {
                    & $DeployerInvoker $weaselRoot
                    Write-DaMaoUninstallEvent -Event 'RIME_REDEPLOY_SUCCEEDED'
                }
                catch {
                    $redeployFailure = $_.Exception.Message
                    Write-DaMaoUninstallEvent -Event 'RIME_REDEPLOY_FAILED' -Detail $redeployFailure
                }
            }
        }
    }
    finally {
        Remove-Item -LiteralPath $InstallerStatePath -Force -ErrorAction SilentlyContinue
    }

    return [PSCustomObject]@{
        RimeUserDir = $resolvedRimeUserDir
        Cleanup = $cleanup
        WeaselStatus = $weaselStatus
        WeaselFailure = $weaselFailure
        PreparationFailure = $preparationFailure
        RedeployFailure = $redeployFailure
    }
}

function Get-DaMaoBigCatUninstallExitCode {
    param(
        [Parameter(Mandatory = $true)]$Result,
        [switch]$RemoveWeasel
    )

    if ($null -eq $Result.Cleanup -or $Result.Cleanup.Failures.Count -gt 0) {
        return 42
    }
    if ($RemoveWeasel) {
        if ($Result.WeaselStatus -eq 'Failed') {
            return 41
        }
        # Server /quit is only preparation. A successful official Weasel
        # uninstall is authoritative and clears any earlier preparation warning.
        return 0
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Result.RedeployFailure)) {
        return 42
    }
    return 0
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        $result = Invoke-DaMaoBigCatUninstall -InstallerStatePath $InstallerStatePath `
            -RimeUserDir $RimeUserDir -RemoveWeasel:$RemoveWeasel
        $Host.SetShouldExit((Get-DaMaoBigCatUninstallExitCode -Result $result `
            -RemoveWeasel:$RemoveWeasel))
    }
    catch {
        Write-DaMaoUninstallEvent -Event 'BIGCAT_UNINSTALL_HELPER_FAILED' -Detail $_.Exception.Message
        Remove-Item -LiteralPath $InstallerStatePath -Force -ErrorAction SilentlyContinue
        $Host.SetShouldExit(42)
    }
}
