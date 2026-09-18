[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'DaMao.PortabilityBaseline.ps1')

function Assert-P0 {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) { throw "[$Code] $Message" }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$baseline = Get-DaMaoPublicBaseline -RepositoryRoot $repoRoot
Assert-P0 ([string]$baseline.status -ceq 'Public Baseline V1') 'DM-P0-001' `
    'The selected contract is not Public Baseline V1.'

$dimensionNames = @($baseline.identity_dimensions | ForEach-Object { [string]$_.field })
Assert-P0 ($dimensionNames.Count -eq 3 -and
    @($dimensionNames | Select-Object -Unique).Count -eq 3) 'DM-P0-002' `
    'The identity contract must keep three distinct dimensions.'
foreach ($requiredDimension in @('logical_role', 'schema_id', 'db_name')) {
    Assert-P0 ($dimensionNames -ccontains $requiredDimension) 'DM-P0-003' `
        "Missing identity dimension: $requiredDimension"
}

$pureWubi = @($baseline.identity_contract.logical_roles | Where-Object {
        [string]$_.logical_role -ceq 'PureWubi'
    })[0]
$physicalIdentities = @($pureWubi.physical_identities)
Assert-P0 ($physicalIdentities.Count -eq 2) 'DM-P0-004' `
    'PureWubi must preserve both current and legacy physical identities.'
$current = @($physicalIdentities | Where-Object {
        [string]$_.schema_id -ceq 'damao_wubi_alpha03' -and
        [string]$_.db_name -ceq 'damao_wubi_alpha03'
    })
$legacy = @($physicalIdentities | Where-Object {
        [string]$_.schema_id -ceq 'damao_wubi' -and
        [string]$_.db_name -ceq 'damao_wubi'
    })
Assert-P0 ($current.Count -eq 1 -and $legacy.Count -eq 1 -and
    [string]$current[0].identity_id -cne [string]$legacy[0].identity_id) 'DM-P0-005' `
    'Current and legacy PureWubi databases must remain distinct.'
Assert-P0 ([string]$pureWubi.coexistence_policy -ceq 'preserve_separate' -and
    -not [bool]$pureWubi.automatic_merge -and
    -not [bool]$pureWubi.automatic_rename) 'DM-P0-006' `
    'PureWubi coexistence must not imply automatic merge or rename.'

$pinyinExclusions = @($baseline.identity_contract.default_exclusions | Where-Object {
        [string]$_.schema_id -ceq 'damao_wubi_pinyin' -and
        [string]$_.db_name -ceq 'damao_wubi_pinyin'
    })
Assert-P0 ($pinyinExclusions.Count -eq 1 -and
    [bool]$pinyinExclusions[0].future_explicit_logical_role_required) 'DM-P0-007' `
    'Pinyin must remain excluded unless a future role explicitly admits it.'
Assert-P0 ([string]$baseline.identity_contract.unknown_db_policy -ceq
    'reject_unclassified') 'DM-P0-008' `
    'Unknown databases must be rejected rather than guessed.'
Assert-P0 (@($baseline.identity_contract.migration_rules).Count -eq 0) 'DM-P0-009' `
    'Public Baseline V1 must not define automatic migration.'

$files = @($baseline.current_file_integrity.files)
Assert-P0 ($files.Count -eq 17) 'DM-P0-010' `
    'Public Baseline V1 must pin exactly 17 current files.'
$failures = @(Test-DaMaoPublicBaselineManifest -RepositoryRoot $repoRoot -Files $files)
Assert-P0 ($failures.Count -eq 0) 'DM-P0-011' `
    "Public Baseline V1 failed: $($failures -join '; ')"

$probeRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
    ('bigcat-public-baseline-' + [guid]::NewGuid().ToString('N'))
$tempRootFull = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
)
$probeRootFull = [System.IO.Path]::GetFullPath($probeRoot)
Assert-P0 ($probeRootFull.StartsWith(
        $tempRootFull + [System.IO.Path]::DirectorySeparatorChar,
        [System.StringComparison]::OrdinalIgnoreCase
    )) 'DM-P0-012' 'The mutation probe directory is outside the system temporary directory.'
try {
    [void](New-Item -ItemType Directory -Path $probeRoot)
    $probeEntry = $files | Where-Object {
        [string]$_.path -ceq 'schemas/damao_wubi.schema.yaml'
    } | Select-Object -First 1
    Assert-P0 ($null -ne $probeEntry) 'DM-P0-013' `
        'The installed schema is absent from Public Baseline V1.'

    $missingFailures = @(Test-DaMaoPublicBaselineManifest -RepositoryRoot $probeRoot `
        -Files @($probeEntry))
    Assert-P0 ($missingFailures.Count -eq 1 -and $missingFailures[0] -like 'missing:*') `
        'DM-P0-014' 'The public baseline did not detect a missing pinned file.'

    $relativePath = ([string]$probeEntry.path).Replace(
        '/', [System.IO.Path]::DirectorySeparatorChar
    )
    $probePath = Join-Path $probeRoot $relativePath
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $probePath))
    Copy-Item -LiteralPath (Join-Path $repoRoot $relativePath) -Destination $probePath
    $bytes = [System.IO.File]::ReadAllBytes($probePath)
    Assert-P0 ($bytes.Length -gt 0) 'DM-P0-015' 'The mutation probe source is empty.'
    $bytes[0] = $bytes[0] -bxor 0x01
    [System.IO.File]::WriteAllBytes($probePath, $bytes)

    $changedFailures = @(Test-DaMaoPublicBaselineManifest -RepositoryRoot $probeRoot `
        -Files @($probeEntry))
    Assert-P0 ($changedFailures.Count -eq 1 -and
        $changedFailures[0] -like 'hash mismatch:*') 'DM-P0-016' `
        'The public baseline did not detect a one-byte modification.'
}
finally {
    if (Test-Path -LiteralPath $probeRoot) {
        Remove-Item -LiteralPath $probeRoot -Recurse -Force
    }
}

Write-Host ("Public Baseline V1 tests passed " +
    "(Identity=valid Integrity=17/17 MutationProbe=passed PowerShell=$($PSVersionTable.PSVersion)).")
