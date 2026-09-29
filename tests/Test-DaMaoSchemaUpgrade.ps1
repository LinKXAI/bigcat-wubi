[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'DaMao.AcceptancePreflight.ps1')
. (Join-Path $repo 'scripts/DaMao.SchemaUpgrade.ps1')
. (Join-Path $repo 'scripts/DaMao.InstallerState.ps1')
$verified = Assert-DaMaoAcceptance $repo
$predecessor = $verified.History['schemas/damao_wubi.schema.yaml']
$root = Join-Path ([IO.Path]::GetTempPath()) ('BigCatSchemaUpgrade-' + [guid]::NewGuid().ToString('N'))
$weasel = Join-Path $root 'weasel'
[void](New-Item -ItemType Directory -Path (Join-Path $weasel 'data') -Force)
[IO.File]::WriteAllText((Join-Path $weasel 'WeaselDeployer.exe'), 'non-executable fixture')
$script:count = 0
function Check([bool]$Value, [string]$Name) { if (-not $Value) { throw "Upgrade assertion failed: $Name" }; $script:count++; Write-Host "PASS $Name" }
function Put([string]$Path, [byte[]]$Bytes) {
    [void](New-Item -ItemType Directory -Path (Split-Path $Path -Parent) -Force)
    [IO.File]::WriteAllBytes($Path, $Bytes)
}
function Digest([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return 'ABSENT' }
    return (@(Get-ChildItem -LiteralPath $Path -Force -Recurse | Sort-Object FullName | ForEach-Object {
        $h = if ($_.PSIsContainer) { 'directory' } else { (Get-FileHash -LiteralPath $_.FullName).Hash }
        $_.FullName.Substring($Path.Length) + ':' + $h
    }) -join "`n")
}
function Install([string]$Entry, [string]$User, [string]$SourceRoot=$repo) {
    $argsMap = @{RimeUserDir=$User;WeaselRoot=$weasel;SkipDeploy=$true;InstallerStatePath=(Join-Path $User 'fixture-installer-state.ini')}
    if ($Entry -eq 'Install-DaMao.ps1' -and -not (Test-Path -LiteralPath (Join-Path $User 'wubi86.dict.yaml'))) {
        $argsMap.WubiSourcePath=Join-Path $SourceRoot 'third_party/rime/rime-wubi'
    }
    & (Join-Path $SourceRoot ('scripts/'+$Entry)) @argsMap
}
foreach ($entry in @('Install-DaMao.ps1','Install-DaMaoWithQuanpin.ps1')) {
    foreach ($mode in @('absent','predecessor','successor','customized','fake-identity','alpha03','unknown')) {
        $user = Join-Path $root ($entry+'-'+$mode)
        $target = Join-Path $user 'damao_wubi.schema.yaml'
        foreach ($db in @('damao_wubi.userdb','damao_wubi_alpha03.userdb','luna_pinyin.userdb')) {
            Put (Join-Path $user ($db+'/synthetic-marker')) ([Text.Encoding]::UTF8.GetBytes('unchanged synthetic sentinel'))
        }
        Put (Join-Path $user 'default.custom.yaml') ([Text.Encoding]::UTF8.GetBytes("patch:`n  menu/page_size: 7`n"))
        Write-DaMaoInstallerState -Path (Join-Path $user 'fixture-installer-state.ini') -WeaselOrigin PreExisting -RimeUserDir $user -RimeOwnership @{}
        $bytes = switch ($mode) {
            'predecessor' { $predecessor }
            'successor' { [IO.File]::ReadAllBytes((Join-Path $repo 'schemas/damao_wubi.schema.yaml')) }
            'customized' { $b=$predecessor.Clone();$b[0]=$b[0] -bxor 1;$b }
            'fake-identity' { [Text.Encoding]::UTF8.GetBytes("schema:`n  schema_id: damao_wubi`n  version: '0.9.1-dev.4'`n") }
            'alpha03' { [IO.File]::ReadAllBytes((Join-Path $repo 'schemas/damao_wubi_alpha03.schema.yaml')) }
            'unknown' { [Text.Encoding]::UTF8.GetBytes('unknown resource') }
        }
        if ($mode -ne 'absent') { Put $target $bytes }
        $before = Digest $user
        $dbBefore = @('damao_wubi.userdb','damao_wubi_alpha03.userdb','luna_pinyin.userdb') | ForEach-Object { Digest (Join-Path $user $_) }
        if ($mode -in @('absent','predecessor','successor')) {
            $result = Install $entry $user
            Check ((Get-FileHash $target).Hash -ceq 'A618CEAC52FA428C52172FE8042B3CC61F275C25445C74F32A57B5D054457CFA') "$entry $mode official successor"
            $expectedAction=@{absent='Install';predecessor='UpgradeExactPredecessor';successor='Reuse'}[$mode]
            Check ($result.SchemaUpgradeAction -ceq $expectedAction) "$entry $mode action"
            $afterFirst=Digest $user; $null=Install $entry $user
            Check ((Digest $user) -ceq $afterFirst) "$entry repeat idempotent"
        }
        else {
            foreach ($attempt in 1..2) {
                $caught=''; try { $null=Install $entry $user } catch { $caught=$_.Exception.Message }
                Check ($caught -match 'DM-RESOURCE-CONFLICT') "$entry $mode rejection $attempt"
                Check ((Digest $user) -ceq $before) "$entry $mode zero config/metadata/ownership mutation $attempt"
            }
        }
        $dbAfter=@('damao_wubi.userdb','damao_wubi_alpha03.userdb','luna_pinyin.userdb') | ForEach-Object { Digest (Join-Path $user $_) }
        Check (($dbAfter -join '|') -ceq ($dbBefore -join '|')) "$entry $mode DB identity sentinels unchanged"
    }
    $user=Join-Path $root ($entry+'-patch')
    $patch=Join-Path $user 'damao_wubi.custom.yaml'
    Put $patch ([Text.Encoding]::UTF8.GetBytes("patch:`n  translator/enable_encoder: false`n"))
    $patchHash=(Get-FileHash $patch).Hash
    Write-DaMaoInstallerState -Path (Join-Path $user 'fixture-installer-state.ini') -WeaselOrigin PreExisting -RimeUserDir $user -RimeOwnership @{}
    $result=Install $entry $user
    Check ($result.LearningPatchStatus -ceq 'ConflictingLearningOverride' -and (Get-FileHash $patch).Hash -ceq $patchHash) "$entry patch retained and diagnosed without functional success claim"
}
# Exercise a non-official source through BOTH actual entry points in a synthetic payload.
$payload=Join-Path $root 'payload'
foreach ($relative in @('scripts','schemas','contracts','assets/branding/windows','third_party/rime','dependencies')) {
    $to=Join-Path $payload $relative
    [void](New-Item -ItemType Directory -Path (Split-Path $to -Parent) -Force)
    Copy-Item -LiteralPath (Join-Path $repo $relative) -Destination $to -Recurse
}
[IO.File]::AppendAllText((Join-Path $payload 'schemas/damao_wubi.schema.yaml'), '# not official')
foreach ($entry in @('Install-DaMao.ps1','Install-DaMaoWithQuanpin.ps1')) {
    $user=Join-Path $root ($entry+'-bad-source');$before=Digest $user;$caught=''
    try { $null=Install $entry $user $payload } catch { $caught=$_.Exception.Message }
    Check ($caught -match 'DM-RESOURCE-CONFLICT' -and (Digest $user) -ceq $before) "$entry non-official source rejected before user directory creation"
}
$user=Join-Path $root 'recheck'
# Even a rehashed synthetic policy cannot authorize an arbitrary source. The
# shared installer helper admits exactly the two reviewed official digests.
$policyPath=Join-Path $payload 'contracts/wubi-schema-upgrade-v1.json'
$policy=[IO.File]::ReadAllText($policyPath)|ConvertFrom-Json
$policy.successor_sha256=(Get-FileHash (Join-Path $payload 'schemas/damao_wubi.schema.yaml')).Hash
[IO.File]::WriteAllText($policyPath,($policy|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
foreach($entry in @('Install-DaMao.ps1','Install-DaMaoWithQuanpin.ps1')) {
    $tamperedUser=Join-Path $root ($entry+'-tampered-policy');$caught=''
    try{$null=Install $entry $tamperedUser $payload}catch{$caught=$_.Exception.Message}
    Check ($caught -match 'DM-RESOURCE-CONFLICT' -and (Digest $tamperedUser) -ceq 'ABSENT') "$entry rehashed unknown source policy rejected"
}
$plan=Get-DaMaoSchemaUpgradePlan $repo $user
Put $plan.Target $predecessor
$caught='';try{Assert-DaMaoSchemaUpgradeUnchanged $plan}catch{$caught=$_.Exception.Message}
Check ($caught -match 'DM-RESOURCE-CONFLICT') 'target identity rechecked after preflight'
Write-Host "Schema predecessor contract: $count passed; 0 failed. Evidence: $root"
