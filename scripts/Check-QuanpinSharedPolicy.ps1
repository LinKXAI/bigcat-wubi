[CmdletBinding()]
param([string]$WeaselRoot, [string]$PolicyPath=(Join-Path $PSScriptRoot '..\schemas\luna_quanpin.custom.yaml'))
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'DaMao.Common.ps1')
. (Join-Path $PSScriptRoot 'DaMao.Quanpin.ps1')
try {
    if(-not $WeaselRoot){
        try { $WeaselRoot=Get-DaMaoWeaselRoot }
        catch { if($_.Exception.Message -match '^\[DM-WEASEL-NOT-FOUND\]'){exit 0};throw }
    }
    Assert-DaMaoQuanpinSharedPolicy -PolicyPath $PolicyPath -WeaselRoot $WeaselRoot
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 27
}
