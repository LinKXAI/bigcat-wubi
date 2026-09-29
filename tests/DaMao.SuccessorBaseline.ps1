Set-StrictMode -Version Latest

function Get-DaMaoAcceptanceBaseline {
    param([Parameter(Mandatory=$true)][string]$RepositoryRoot)
    # Bootstrap only the exact verifier selected by the reviewed root lock.
    $lockPath = Join-Path $RepositoryRoot 'contracts/acceptance.lock.json'
    if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) {
        throw '[DM-ACCEPTANCE-LOCK] Explicit acceptance lock is required; no V1 fallback.'
    }
    $lock = [IO.File]::ReadAllText($lockPath) | ConvertFrom-Json
    if ($lock.current_baseline -cne 'bigcat-wubi-public-baseline-v2' -or
        $lock.verifier.path -cne 'tests/DaMao.AcceptancePreflight.ps1') {
        throw '[DM-ACCEPTANCE-LOCK] Unsupported explicit baseline or verifier.'
    }
    $verifier = Join-Path $RepositoryRoot 'tests/DaMao.AcceptancePreflight.ps1'
    if ((Get-FileHash -LiteralPath $verifier -Algorithm SHA256).Hash -cne $lock.verifier.sha256) {
        throw '[DM-ACCEPTANCE-HASH] Verifier digest mismatch.'
    }
    . $verifier
    $result = Assert-DaMaoAcceptance -RepositoryRoot $RepositoryRoot
    # Keep the original V1 validator and identity contract separate and unchanged.
    . (Join-Path $RepositoryRoot 'tests/DaMao.PortabilityBaseline.ps1')
    $baseline = Get-DaMaoPublicBaseline -RepositoryRoot $RepositoryRoot
    $baseline.contract_id = $result.Manifest.contract_id
    $baseline.contract_version = 2
    $baseline.status = 'Public Baseline V2'
    $baseline.current_file_integrity = $result.Manifest.current_file_integrity
    return $baseline
}

# Preserve the legacy integrity probe helper, without redefining its V1 loader.
$null = Get-DaMaoAcceptanceBaseline -RepositoryRoot (Split-Path $PSScriptRoot -Parent)
. (Join-Path $PSScriptRoot 'DaMao.PortabilityBaseline.ps1')
