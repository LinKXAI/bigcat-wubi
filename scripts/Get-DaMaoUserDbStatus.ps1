[CmdletBinding()]
param(
    [string]$RimeUserDir = (Join-Path $env:APPDATA 'Rime'),
    [ValidateSet('PureWubi')][string]$LogicalRole = 'PureWubi',
    [string]$WeaselRoot,
    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'DaMao.UserDbSnapshot.ps1')

$parameters = @{
    RimeUserDir = $RimeUserDir
    LogicalRole = $LogicalRole
}
if (-not [string]::IsNullOrWhiteSpace($WeaselRoot)) {
    $parameters.WeaselRoot = $WeaselRoot
}

$status = Get-DaMaoUserDbEnvironmentStatus @parameters
if ($AsJson) {
    $status | ConvertTo-Json -Depth 12
}
else {
    $status
}
