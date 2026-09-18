[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$DbName,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [string]$RimeUserDir = (Join-Path $env:APPDATA 'Rime'),
    [AllowNull()][string]$RimeDll,
    [string]$RimeSharedDataDir,
    [string]$WeaselRoot,
    [ValidateRange(1, 120)][int]$MaintenanceTimeoutSeconds = 15,
    [switch]$AsJson,
    [switch]$Synthetic
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'DaMao.UserDbPortabilityP2.ps1')

Write-Warning 'The resulting package contains complete user dictionary data and must be handled as sensitive data.'
try {
    $parameters = @{
        DbName = $DbName
        OutputDirectory = $OutputDirectory
        RimeUserDir = $RimeUserDir
        RimeDll = $RimeDll
        MaintenanceTimeoutSeconds = $MaintenanceTimeoutSeconds
        Synthetic = $Synthetic
    }
    if (-not [string]::IsNullOrWhiteSpace($RimeSharedDataDir)) {
        $parameters.RimeSharedDataDir = $RimeSharedDataDir
    }
    if (-not [string]::IsNullOrWhiteSpace($WeaselRoot)) {
        $parameters.WeaselRoot = $WeaselRoot
    }
    $result = Backup-DaMaoUserDbPackageV2 @parameters
    if ($AsJson) {
        $result | ConvertTo-Json -Depth 8
    }
    else {
        $result
    }
}
catch {
    $code = 'P2_OPERATION_FAILED'
    if ($_.Exception.Message -match '^\[(P2_[A-Z0-9_]+)\]') {
        $code = $Matches[1]
    }
    $failure = [pscustomobject][ordered]@{
        Status = 'Failed'
        ErrorCode = $code
        DbName = $DbName
        ContainsUserDictionaryData = $true
        Sensitive = $true
    }
    if ($AsJson) {
        $failure | ConvertTo-Json -Depth 4
    }
    else {
        Write-Error "[$code] UserDB Package V2 backup failed. No dictionary content was printed."
    }
    exit 1
}
