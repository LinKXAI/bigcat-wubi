Set-StrictMode -Version Latest

$script:DaMaoInstallerStateFormatVersion = 1
$script:DaMaoWeaselOrigins = @('BigCatBootstrap', 'PreExisting', 'UnknownLegacy')
$script:DaMaoRimeOwnershipPaths = [ordered]@{
    wubi86_dict = 'wubi86.dict.yaml'
    wubi86_license = 'LICENSE.rime-wubi.txt'
    wubi86_source_metadata = 'rime-wubi.source.json'
}

function Test-DaMaoWeaselOrigin {
    param([AllowNull()][AllowEmptyString()][string]$Origin)

    return -not [string]::IsNullOrWhiteSpace($Origin) -and
        $script:DaMaoWeaselOrigins -ccontains $Origin
}

function Read-DaMaoInstallerState {
    param([Parameter(Mandatory = $true)][string]$Path)

    $result = [PSCustomObject]@{
        IsTrusted = $false
        FormatVersion = $null
        WeaselOrigin = $null
        RimeUserDir = $null
        RimeOwnership = @{}
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $result
    }

    try {
        $sections = @{}
        $section = $null
        foreach ($rawLine in [System.IO.File]::ReadAllLines($Path)) {
            $line = $rawLine.Trim()
            if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith(';') -or $line.StartsWith('#')) {
                continue
            }
            if ($line -match '^\[(?<section>[A-Za-z0-9_]+)\]$') {
                $section = $Matches.section.ToLowerInvariant()
                if (-not $sections.ContainsKey($section)) {
                    $sections[$section] = @{}
                }
                continue
            }
            $separator = $rawLine.IndexOf('=')
            if ($null -eq $section -or $separator -le 0) {
                return $result
            }
            $key = $rawLine.Substring(0, $separator).Trim().ToLowerInvariant()
            $value = $rawLine.Substring($separator + 1).Trim()
            if ($sections[$section].ContainsKey($key)) {
                return $result
            }
            $sections[$section][$key] = $value
        }

        if (-not $sections.ContainsKey('installer')) {
            return $result
        }
        $installer = $sections['installer']
        $formatVersion = 0
        if (-not $installer.ContainsKey('format_version') -or
            -not [int]::TryParse([string]$installer['format_version'], [ref]$formatVersion) -or
            $formatVersion -ne $script:DaMaoInstallerStateFormatVersion -or
            -not $installer.ContainsKey('weasel_origin') -or
            -not (Test-DaMaoWeaselOrigin -Origin ([string]$installer['weasel_origin']))) {
            return $result
        }

        $ownership = @{}
        if ($sections.ContainsKey('rime_ownership')) {
            foreach ($key in $sections['rime_ownership'].Keys) {
                if (-not $script:DaMaoRimeOwnershipPaths.Contains($key)) {
                    continue
                }
                $hash = [string]$sections['rime_ownership'][$key]
                if ($hash -cmatch '^[A-F0-9]{64}$') {
                    $ownership[$key] = $hash
                }
            }
        }

        $result.IsTrusted = $true
        $result.FormatVersion = $formatVersion
        $result.WeaselOrigin = [string]$installer['weasel_origin']
        if ($installer.ContainsKey('rime_user_dir') -and
            -not [string]::IsNullOrWhiteSpace([string]$installer['rime_user_dir'])) {
            $result.RimeUserDir = [string]$installer['rime_user_dir']
        }
        $result.RimeOwnership = $ownership
    }
    catch {
        # A malformed, unreadable, or partially written state is untrusted.
    }
    return $result
}

function Assert-DaMaoIniValue {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowNull()][AllowEmptyString()][string]$Value
    )

    if ($null -ne $Value -and ($Value.Contains("`r") -or $Value.Contains("`n"))) {
        throw "[DM-INSTALLER-STATE-INVALID] $Name contains a line break."
    }
}

function Write-DaMaoInstallerState {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][ValidateSet('BigCatBootstrap', 'PreExisting', 'UnknownLegacy')][string]$WeaselOrigin,
        [AllowNull()][AllowEmptyString()][string]$RimeUserDir,
        [hashtable]$RimeOwnership = @{}
    )

    Assert-DaMaoIniValue -Name 'rime_user_dir' -Value $RimeUserDir
    $directory = Split-Path -Parent ([System.IO.Path]::GetFullPath($Path))
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('[installer]')
    $lines.Add("format_version=$script:DaMaoInstallerStateFormatVersion")
    $lines.Add("weasel_origin=$WeaselOrigin")
    if (-not [string]::IsNullOrWhiteSpace($RimeUserDir)) {
        $lines.Add("rime_user_dir=$RimeUserDir")
    }
    $lines.Add('')
    $lines.Add('[rime_ownership]')
    foreach ($key in $script:DaMaoRimeOwnershipPaths.Keys) {
        if (-not $RimeOwnership.ContainsKey($key)) {
            continue
        }
        $hash = ([string]$RimeOwnership[$key]).Trim().ToUpperInvariant()
        if ($hash -cnotmatch '^[A-F0-9]{64}$') {
            throw "[DM-INSTALLER-STATE-INVALID] Invalid SHA-256 for $key."
        }
        $lines.Add("$key=$hash")
    }
    $content = ($lines -join "`r`n") + "`r`n"
    $temporaryPath = "$Path.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        $encoding = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($temporaryPath, $content, $encoding)
        Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
    }
    finally {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }
}

function Set-DaMaoInstallerProvenance {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][ValidateSet('BigCatBootstrap', 'PreExisting', 'UnknownLegacy')][string]$WeaselOrigin,
        [Parameter(Mandatory = $true)][string]$RimeUserDir
    )

    $current = Read-DaMaoInstallerState -Path $Path
    $ownership = if ($current.IsTrusted) { $current.RimeOwnership } else { @{} }
    Write-DaMaoInstallerState -Path $Path -WeaselOrigin $WeaselOrigin `
        -RimeUserDir $RimeUserDir -RimeOwnership $ownership
}

function Resolve-DaMaoWeaselOrigin {
    param(
        [AllowNull()][AllowEmptyString()][string]$ExistingOrigin,
        [Parameter(Mandatory = $true)][ValidateSet('Usable', 'Absent', 'Unusable')][string]$InitialWeaselState,
        [switch]$LegacyInstallPresent,
        [switch]$BootstrapSucceeded
    )

    if ($BootstrapSucceeded) {
        return 'BigCatBootstrap'
    }
    if ($InitialWeaselState -ne 'Usable') {
        return $null
    }
    if (Test-DaMaoWeaselOrigin -Origin $ExistingOrigin) {
        return $ExistingOrigin
    }
    if ($LegacyInstallPresent) {
        return 'UnknownLegacy'
    }
    return 'PreExisting'
}

function Get-DaMaoWeaselUninstallPolicy {
    param([AllowNull()][AllowEmptyString()][string]$Origin)

    if ($Origin -ceq 'BigCatBootstrap') {
        return [PSCustomObject]@{
            Origin = 'BigCatBootstrap'
            DefaultChecked = $true
            ConfirmIfChecked = $false
        }
    }
    $safeOrigin = if ($Origin -ceq 'PreExisting') { 'PreExisting' } else { 'UnknownLegacy' }
    return [PSCustomObject]@{
        Origin = $safeOrigin
        DefaultChecked = $false
        ConfirmIfChecked = $true
    }
}

function Get-DaMaoRimeOwnershipSnapshot {
    param([Parameter(Mandatory = $true)][string]$RimeUserDir)

    $snapshot = @{}
    foreach ($key in $script:DaMaoRimeOwnershipPaths.Keys) {
        $snapshot[$key] = Test-Path -LiteralPath (Join-Path $RimeUserDir $script:DaMaoRimeOwnershipPaths[$key]) -PathType Leaf
    }
    return $snapshot
}

function Update-DaMaoInstallerRimeOwnership {
    param(
        [Parameter(Mandatory = $true)][string]$StatePath,
        [Parameter(Mandatory = $true)][string]$RimeUserDir,
        [Parameter(Mandatory = $true)][hashtable]$ExistedBefore
    )

    $state = Read-DaMaoInstallerState -Path $StatePath
    if (-not $state.IsTrusted) {
        throw '[DM-INSTALLER-STATE-INVALID] Trusted provenance must be recorded before Rime ownership is updated.'
    }
    $ownership = @{}
    foreach ($key in $state.RimeOwnership.Keys) {
        $ownership[$key] = $state.RimeOwnership[$key]
    }
    foreach ($key in $script:DaMaoRimeOwnershipPaths.Keys) {
        $path = Join-Path $RimeUserDir $script:DaMaoRimeOwnershipPaths[$key]
        $wasPreviouslyOwned = $state.RimeOwnership.ContainsKey($key)
        $existedBeforeInstall = $ExistedBefore.ContainsKey($key) -and [bool]$ExistedBefore[$key]
        if (($wasPreviouslyOwned -or -not $existedBeforeInstall) -and
            (Test-Path -LiteralPath $path -PathType Leaf)) {
            $ownership[$key] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        }
    }
    Write-DaMaoInstallerState -Path $StatePath -WeaselOrigin $state.WeaselOrigin `
        -RimeUserDir $RimeUserDir -RimeOwnership $ownership
}
