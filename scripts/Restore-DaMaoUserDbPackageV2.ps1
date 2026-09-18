[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PackagePath,
    [string]$RimeUserDir = (Join-Path $env:APPDATA 'Rime'),
    [AllowNull()][string]$RimeDll,
    [AllowNull()][string]$RimeSharedDataDir,
    [AllowNull()][string]$WeaselRoot,
    [AllowNull()][string]$SafetyBackupDirectory,
    [AllowNull()][string]$DiagnosticBackupDirectory,
    [ValidateRange(1, 120)][int]$MaintenanceTimeoutSeconds = 15,
    [switch]$Synthetic,
    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'DaMao.UserDbPortabilityP3.ps1')

Write-Warning ('Restore is a merge-style mutation. Any pre-restore backup is a ' +
    'sensitive safety artifact, not a transactional rollback point.')

$receipt = Restore-DaMaoUserDbPackageV2 -PackagePath $PackagePath `
    -RimeUserDir $RimeUserDir -RimeDll $RimeDll `
    -RimeSharedDataDir $RimeSharedDataDir -WeaselRoot $WeaselRoot `
    -SafetyBackupDirectory $SafetyBackupDirectory `
    -DiagnosticBackupDirectory $DiagnosticBackupDirectory `
    -MaintenanceTimeoutSeconds $MaintenanceTimeoutSeconds -Synthetic:$Synthetic

if ($AsJson) {
    ConvertTo-DaMaoP3ReceiptJson -Receipt $receipt -Faults $null
}
else {
    $receipt
}
