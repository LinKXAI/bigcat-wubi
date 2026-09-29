[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'DaMao.SuccessorBaseline.ps1')
. (Join-Path $PSScriptRoot 'DaMao.AcceptancePreflight.ps1')
$verified = Assert-DaMaoAcceptance $repo
$root = Join-Path ([IO.Path]::GetTempPath()) ('BigCatSuccessorTests-' + [guid]::NewGuid().ToString('N'))
$script:count = 0
function Check([bool]$Value, [string]$Name) {
    if (-not $Value) { throw "Contract assertion failed: $Name" }
    $script:count++; Write-Host "PASS $Name"
}
function PutJson([string]$Path, $Value) {
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 30), [Text.UTF8Encoding]::new($false))
}
$paths = @('contracts/acceptance.lock.json') + @($verified.Lock.PSObject.Properties | Where-Object { $_.Value -is [pscustomobject] } | ForEach-Object { $_.Value.path }) +
    @($verified.Manifest.current_file_integrity.files | ForEach-Object path) + @($verified.Manifest.support_file_integrity.files | ForEach-Object path)
function New-Case([string]$Name) {
    $case = Join-Path $root $Name
    foreach ($relative in @($paths | Select-Object -Unique)) {
        $to = Join-Path $case $relative
        [void](New-Item -ItemType Directory -Path (Split-Path $to -Parent) -Force)
        Copy-Item -LiteralPath (Join-Path $repo $relative) -Destination $to
    }
    return $case
}
function Reject([string]$Name, [scriptblock]$Mutation, [string]$Code) {
    $case = New-Case $Name
    & $Mutation $case
    $caught = ''
    try { $null = Assert-DaMaoAcceptance $case } catch { $caught = $_.Exception.Message }
    Check ($caught -match [regex]::Escape($Code)) $Name
}
function MutateByte([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path); $bytes[0] = $bytes[0] -bxor 1
    [IO.File]::WriteAllBytes($Path, $bytes)
}
# Only negative synthetic fixtures use a rewritten root, to reach structural
# validation behind digest checks. Production acceptance never writes any pin.
function RewriteSyntheticManifest([string]$Case, [scriptblock]$Change) {
    $path = Join-Path $Case 'contracts/public-baseline-v2.json'
    $value = [IO.File]::ReadAllText($path) | ConvertFrom-Json
    & $Change $value
    PutJson $path $value
    $lockPath = Join-Path $Case 'contracts/acceptance.lock.json'
    $lock = [IO.File]::ReadAllText($lockPath) | ConvertFrom-Json
    $lock.manifest.sha256 = (Get-FileHash $path).Hash
    PutJson $lockPath $lock
}
Check ($verified.Manifest.contract_id -ceq 'bigcat-wubi-public-baseline-v2' -and $verified.Unchanged -eq 12 -and $verified.Changed -eq 5) 'explicit V2 selection and full integrity'
Reject 'missing-lock-no-V1-fallback' { param($c) Remove-Item -LiteralPath (Join-Path $c 'contracts/acceptance.lock.json') } 'DM-ACCEPTANCE-LOCK'
Reject 'unknown-baseline' { param($c)
    $p=Join-Path $c 'contracts/acceptance.lock.json'; $l=[IO.File]::ReadAllText($p)|ConvertFrom-Json
    $l.current_baseline='bigcat-wubi-public-baseline-v99'; PutJson $p $l
} 'DM-ACCEPTANCE-LOCK'
foreach ($artifact in @('manifest','transition','verifier','loader','evidence')) {
    $relative = $verified.Lock.$artifact.path
    Reject ($artifact+'-digest-mismatch') { param($c) MutateByte (Join-Path $c $relative) } 'DM-ACCEPTANCE-HASH'
}
Reject 'path-escape' { param($c)
    RewriteSyntheticManifest $c { param($m) $m.current_file_integrity.files[0].path='../escaped' }
} 'DM-ACCEPTANCE-PATH'
Reject 'duplicate-manifest-path' { param($c)
    RewriteSyntheticManifest $c { param($m) $m.current_file_integrity.files[1].path=$m.current_file_integrity.files[0].path }
} 'DM-ACCEPTANCE-DUPLICATE'
$changes = @('schemas/damao_wubi.schema.yaml') + @(0..3 | ForEach-Object { "tests/Test-DaMaoUserDbPortabilityP$_.ps1" })
foreach ($pin in $verified.Manifest.current_file_integrity.files) {
    $relative = $pin.path
    $name = if ($changes -contains $relative) { 'changed-protected-' } else { 'unchanged-protected-' }
    Reject ($name + [IO.Path]::GetFileName($relative)) { param($c) MutateByte (Join-Path $c $relative) } 'DM-ACCEPTANCE-HASH'
}
Reject 'rehashed-child-root-not-authorized' { param($c)
    $p=Join-Path $c 'schemas/damao_wubi.schema.yaml'; MutateByte $p
    $m=Join-Path $c 'contracts/public-baseline-v2.json'; $v=[IO.File]::ReadAllText($m)|ConvertFrom-Json
    $v.current_file_integrity.files[0].sha256=(Get-FileHash $p).Hash; PutJson $m $v
} 'DM-ACCEPTANCE-HASH'
foreach ($relative in $changes) {
    Reject ('out-of-recipe-'+[IO.Path]::GetFileName($relative)) { param($c)
        $p=Join-Path $c $relative
        [IO.File]::AppendAllText($p, "# unauthorized outside wiring`n", [Text.UTF8Encoding]::new($false))
        $newHash=(Get-FileHash $p).Hash
        RewriteSyntheticManifest $c { param($m) ($m.current_file_integrity.files|Where-Object path -eq $relative).sha256=$newHash }
        $t=Join-Path $c 'contracts/dev4-transition.json'; $v=[IO.File]::ReadAllText($t)|ConvertFrom-Json
        ($v.changes|Where-Object path -eq $relative).after_sha256=$newHash; PutJson $t $v
        $l=Join-Path $c 'contracts/acceptance.lock.json'; $v=[IO.File]::ReadAllText($l)|ConvertFrom-Json
        $v.transition.sha256=(Get-FileHash $t).Hash; PutJson $l $v
    } 'DM-ACCEPTANCE-TRANSITION'
}
Write-Host "Successor contract: $count passed; 0 failed. Synthetic evidence: $root"
