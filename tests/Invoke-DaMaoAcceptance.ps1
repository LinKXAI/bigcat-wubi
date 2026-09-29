[CmdletBinding()]
param([string]$RepositoryRoot = (Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference = 'Stop'
# This reviewed bootstrap authenticates the loader BEFORE executing it. The
# external review of this bootstrap and the lock is the root of trust.
$lock = [IO.File]::ReadAllText((Join-Path $RepositoryRoot 'contracts/acceptance.lock.json')) | ConvertFrom-Json
$loader = Join-Path $PSScriptRoot 'DaMao.SuccessorBaseline.ps1'
if ($lock.loader.path -cne 'tests/DaMao.SuccessorBaseline.ps1' -or
    (Get-FileHash -LiteralPath $loader).Hash -cne $lock.loader.sha256) { throw '[DM-ACCEPTANCE-HASH] Loader digest mismatch.' }
. (Join-Path $PSScriptRoot 'DaMao.SuccessorBaseline.ps1')
$null = Get-DaMaoAcceptanceBaseline -RepositoryRoot $RepositoryRoot
Write-Host 'Public Baseline V2 preflight passed: explicit lock, historical chain, 5 exact transitions, 12 unchanged, full support integrity.'
