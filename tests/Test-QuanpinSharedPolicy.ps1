[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$RimeDll,
      [string]$FixtureRoot, [switch]$DeployFixture)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=Split-Path $PSScriptRoot -Parent
$ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if($DeployFixture){
    # One native lifetime per child, always with a synthetic profile.
    Add-Type -Path (Join-Path $PSScriptRoot 'DaMaoRimeQuanpinNative.cs')
    try {
        [DaMaoRimeQuanpinNative]::Load($RimeDll,(Join-Path $FixtureRoot 'weasel\data'),(Join-Path $FixtureRoot 'user'),(Join-Path $FixtureRoot 'user\build'))
        if(-not [DaMaoRimeQuanpinNative]::DeployWorkspace()){throw 'Native deployment failed'}
    } finally {[DaMaoRimeQuanpinNative]::Shutdown()}
    return
}
. (Join-Path $repo 'scripts\Bootstrap-Weasel.ps1')
. (Join-Path $repo 'scripts\DaMao.Quanpin.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('BigCatSharedPolicyTests-'+[guid]::NewGuid().ToString('N'))
$count=0
function Check([bool]$ok,[string]$message){if(-not $ok){throw $message};$script:count++;Write-Host "PASS $message"}
function Put([string]$path,[string]$value){New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force|Out-Null;[IO.File]::WriteAllText($path,$value,[Text.UTF8Encoding]::new($false))}
function Digest([string]$path){
    # Entire synthetic target tree, including timestamps: no rollback may masquerade as preflight.
    return (@(Get-ChildItem -LiteralPath $path -Force -Recurse|Sort-Object FullName|ForEach-Object {
        $rel=$_.FullName.Substring($path.Length)
        if($_.PSIsContainer){'D:'+ $rel}else{'F:'+ $rel+':'+(Get-FileHash -LiteralPath $_.FullName).Hash+':'+$_.LastWriteTimeUtc.Ticks}
    }) -join "`n")
}
function RunChild([string[]]$Arguments,[string]$Log){
    $saved=$ErrorActionPreference
    try {$ErrorActionPreference='Continue'; & $ps @Arguments *> $Log; return $LASTEXITCODE}
    finally {$ErrorActionPreference=$saved}
}
function Deploy([string]$fixture,[string]$label){
    $code=RunChild @('-NoProfile','-ExecutionPolicy','Bypass','-File',$PSCommandPath,'-RimeDll',$RimeDll,'-FixtureRoot',$fixture,'-DeployFixture') (Join-Path $root ($label+'.native.log'))
    Check ($code -eq 0) "$label native deployment"
    return [IO.File]::ReadAllText((Join-Path $fixture 'user\build\luna_quanpin.schema.yaml'))
}
function Page([string]$text){return [int]([regex]::Match($text,'(?m)^\s*page_size:\s*(\d+)').Groups[1].Value)}
# Exercise the exact flat temporary guard payload used by ExtractTemporaryFile.
$staged=Join-Path $root 'setup-staged'
New-Item -ItemType Directory -Path $staged -Force|Out-Null
foreach($name in @('Check-QuanpinSharedPolicy.ps1','DaMao.Common.ps1','DaMao.Quanpin.ps1')){
    Copy-Item -LiteralPath (Join-Path $repo ('scripts\'+$name)) -Destination $staged
}
Copy-Item -LiteralPath (Join-Path $repo 'schemas\luna_quanpin.custom.yaml') -Destination $staged
$policy=Join-Path $repo 'schemas\luna_quanpin.custom.yaml'
Check ((Get-FileHash -LiteralPath $policy).Hash -ceq '62EB4A300BDF01781B8B4C8D845D355D0D1B7A4002306057077EF0A8FF68991F') 'DEV2 policy bytes unchanged in DEV3'
foreach($case in @('page9','equal','unrelated','dev2-owned','dev2-modified')){
    $fixture=Join-Path $root $case;$user=Join-Path $fixture 'user';$weasel=Join-Path $fixture 'weasel';$shared=Join-Path $weasel 'data'
    New-Item -ItemType Directory -Path $user,$shared -Force|Out-Null
    Copy-Item -Path (Join-Path $repo 'third_party\rime\quanpin-weasel-0.17.4\*') -Destination $shared -Recurse
    Put (Join-Path $weasel 'WeaselDeployer.exe') 'never executable; production deployment must not be reached on conflicts'
    Put (Join-Path $user 'default.custom.yaml') "patch:`n  schema_list:`n    - schema: luna_quanpin`n"
    Put (Join-Path $user 'luna_pinyin.userdb\synthetic-learning') 'synthetic learning only, do not read any real profile'
    $state=Join-Path $fixture 'installer-state.ini';Put $state 'original synthetic metadata'
    if($case -eq 'page9'){Put (Join-Path $shared 'luna_quanpin.custom.yaml') "patch:`n  menu/page_size: 9`n"}
    if($case -eq 'unrelated'){Put (Join-Path $shared 'luna_quanpin.custom.yaml') "patch:`n  menu/page_size: 7`n  test_unrelated: preserved`n"}
    if($case -eq 'equal'){Copy-Item -LiteralPath $policy -Destination (Join-Path $shared 'luna_quanpin.custom.yaml')}
    if($case -like 'dev2-*'){
        Copy-Item -LiteralPath $policy -Destination (Join-Path $user 'luna_quanpin.custom.yaml')
        $receipt=@{format_version=1;resources=@(@{RelativePath='luna_quanpin.custom.yaml';Action='Add';Kind='QuanpinDefaultPolicy';SHA256=(Get-FileHash -LiteralPath $policy).Hash})}|ConvertTo-Json -Depth 5
        Put (Join-Path $user 'damao_wubi\quanpin-install.json') $receipt
        if($case -eq 'dev2-modified'){Add-Content -LiteralPath (Join-Path $user 'luna_quanpin.custom.yaml') -Value '# user custom modification' -Encoding UTF8}
    }
    $compiledBefore=Deploy $fixture ($case+'-before')
    $before=Digest $fixture;$sharedBefore=Digest $shared
    if($case -in @('page9','unrelated','dev2-modified')){
        $expected=if($case -eq 'dev2-modified'){'DM-PINYIN-CUSTOM-CONFLICT'}else{'DM-PINYIN-SHARED-POLICY-CONFLICT'}
        foreach($attempt in 1..2){
            $message=''
            try{& (Join-Path $repo 'scripts\Install-DaMaoWithQuanpin.ps1') -RimeUserDir $user -WeaselRoot $weasel -InstallerStatePath $state|Out-Null}catch{$message=$_.Exception.Message}
            Check ($message.Contains($expected)) "$case attempt $attempt explicitly rejected before deployment"
            Check ((Digest $fixture) -ceq $before) "$case attempt $attempt whole target bytes/timestamps unchanged (including metadata and synthetic learning)"
        }
        if($case -ne 'dev2-modified'){
            Check (-not(Test-Path -LiteralPath (Join-Path $user 'luna_quanpin.custom.yaml'))) "$case no local policy created"
            Check (-not(Test-Path -LiteralPath (Join-Path $user 'damao_wubi\quanpin-install.json'))) "$case no ownership receipt created"
            $message=''
            try{Set-DaMaoPreflightedInstallerProvenance -Path $state -WeaselOrigin PreExisting -RimeUserDir $user -WeaselRoot $weasel}catch{$message=$_.Exception.Message}
            Check ($message.Contains($expected)) "$case bootstrap rejects before provenance write"
            Check ((Digest $fixture) -ceq $before) "$case bootstrap preserves metadata and target"
            $code=RunChild @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $staged 'Check-QuanpinSharedPolicy.ps1'),'-WeaselRoot',$weasel,'-PolicyPath',(Join-Path $staged 'luna_quanpin.custom.yaml')) (Join-Path $root ($case+'.guard.log'))
            Check ($code -eq 27) "$case Setup guard returns explicit failure"
            Check ((Digest $fixture) -ceq $before) "$case Setup guard has no target writes"
        }
        $compiledAfter=Deploy $fixture ($case+'-after')
        Check ((Page $compiledAfter) -eq (Page $compiledBefore)) "$case effective native page size preserved after rejected install"
        if($case -eq 'page9'){Check ((Page $compiledAfter) -eq 9) 'blocker regression: native page_size remains 9'}
        if($case -eq 'unrelated'){Check ($compiledAfter -match 'test_unrelated: preserved') 'unrelated native custom key preserved'}
    }else{
        if($case -eq 'equal'){
            $code=RunChild @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $staged 'Check-QuanpinSharedPolicy.ps1'),'-WeaselRoot',$weasel,'-PolicyPath',(Join-Path $staged 'luna_quanpin.custom.yaml')) (Join-Path $root 'equal.guard.log')
            Check ($code -eq 0) 'identical shared policy allowed by Setup guard'
        }
        $result=& (Join-Path $repo 'scripts\Install-DaMaoWithQuanpin.ps1') -RimeUserDir $user -WeaselRoot $weasel -SkipDeploy
        Check ((Digest $shared) -ceq $sharedBefore) "$case shared resources unchanged"
        Check ((Get-FileHash -LiteralPath (Join-Path $user 'luna_quanpin.custom.yaml')).Hash -ceq (Get-FileHash -LiteralPath $policy).Hash) "$case installed DEV3 keeps exact DEV2 behavior policy"
        $entry=@($result.Resources|Where-Object RelativePath -eq 'luna_quanpin.custom.yaml')[0]
        Check ($entry.Target -ceq (Join-Path $user 'luna_quanpin.custom.yaml')) "$case ownership target is local, never shared"
        Check ($entry.Action -ceq $(if($case -eq 'equal'){'Add'}else{'ExistingUserResource'})) "$case local provenance is accurate"
        $compiledAfter=Deploy $fixture ($case+'-after')
        Check ((Page $compiledAfter) -eq (Page $compiledBefore)) "$case effective native page size unchanged"
        Check ($compiledAfter -match 'Shift_L: commit_code' -and $compiledAfter -match 'Shift_R: commit_code') "$case native Shift policy retained"
        $second=& (Join-Path $repo 'scripts\Install-DaMaoWithQuanpin.ps1') -RimeUserDir $user -WeaselRoot $weasel -SkipDeploy
        Check ($second.DefaultEntry -ceq 'PreserveExisting') "$case repeat preserves entry"
    }
}
# The Setup guard is packaged and runs in PrepareToInstall, before app payload copying.
$iss=[IO.File]::ReadAllText((Join-Path $repo 'installer\windows\BigCatWubi.iss'))
Check ($iss -match '(?s)function PrepareToInstall.*?Check-QuanpinSharedPolicy.ps1.*?ResultCode <> 0') 'Setup pre-copy guard wired'
Write-Host "Quanpin shared policy: $count passed; 0 failed; 0 skipped."
Write-Host "Isolated evidence: $root"
