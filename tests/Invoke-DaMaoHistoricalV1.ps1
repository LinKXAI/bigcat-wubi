[CmdletBinding()]
param([string]$RimeDll, [switch]$HermeticOnly)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
# Historical verification deliberately does not require current V2 source bytes.
$lock = [IO.File]::ReadAllText((Join-Path $repoRoot 'contracts/acceptance.lock.json')) | ConvertFrom-Json
$verifier = Join-Path $PSScriptRoot 'DaMao.AcceptancePreflight.ps1'
if ($lock.verifier.path -cne 'tests/DaMao.AcceptancePreflight.ps1' -or
    (Get-FileHash -LiteralPath $verifier).Hash -cne $lock.verifier.sha256) { throw 'Historical verifier digest mismatch.' }
. $verifier
if ($lock.evidence.path -cne 'tests/fixtures/public-baseline-v1/source.zip') { throw 'Unexpected historical evidence path.' }
$history = Read-AcceptanceSnapshot $repoRoot $lock.evidence
if ((Get-AcceptanceByteHash $history['contracts/public-baseline-v1.json']) -cne $lock.predecessor.sha256) { throw 'Historical manifest digest mismatch.' }
$root = Join-Path ([IO.Path]::GetTempPath()) ('BigCatHistoricalV1-' + [guid]::NewGuid().ToString('N'))
foreach ($relative in $history.Keys) {
    $path = Resolve-AcceptancePath $root $relative
    [void](New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force)
    [IO.File]::WriteAllBytes($path, $history[$relative])
}
$hostExe = (Get-Process -Id $PID).Path
foreach ($phase in 0..3) {
    $arguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $root "tests/Test-DaMaoUserDbPortabilityP$phase.ps1"))
    if ($phase -ge 2) {
        if ($HermeticOnly) { $arguments += '-HermeticOnly' }
        elseif ($RimeDll) { $arguments += @('-RimeDll', $RimeDll) }
        else { throw 'Specify locked RimeDll or explicitly request HermeticOnly; native work is not silently skipped.' }
    }
    & $hostExe @arguments
    if ($LASTEXITCODE -ne 0) { throw "Historical V1 P$phase failed." }
}
Write-Host "Historical V1 acceptance passed. Independent snapshot: $root"
