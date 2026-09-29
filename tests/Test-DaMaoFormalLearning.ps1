[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$RimeDll,
    [ValidateSet('Fresh','Upgrade','PatchEncoder','PatchHistory')][string]$Mode='Fresh'
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=Split-Path $PSScriptRoot -Parent
$root=Join-Path ([IO.Path]::GetTempPath()) ('BigCatFormalLearning-'+$Mode+'-'+[guid]::NewGuid().ToString('N'))
$app=Join-Path $root 'app';$user=Join-Path $root 'user';$weasel=Join-Path $root 'weasel';$shared=Join-Path $weasel 'data'
$script:checks=0;$script:keyEvidence=[Collections.Generic.List[object]]::new()
$result=[ordered]@{Mode=$Mode;Root=$root;Passed=$false;SchemaId='damao_wubi';UserDb='damao_wubi.userdb';InputMethod='rime_process_key only; page/number keys for selection'}
function Check([bool]$Value,[string]$Name){if(-not $Value){throw "[DM-FORMAL-LEARNING] $Name"};$script:checks++;Write-Host "PASS $Name"}
function WriteFixture([string]$Path,[string]$Text){[void](New-Item -ItemType Directory -Path (Split-Path $Path -Parent) -Force);[IO.File]::WriteAllText($Path,$Text,[Text.UTF8Encoding]::new($false))}
function DbDigest {
    $db=Join-Path $user 'damao_wubi.userdb'
    return (@(Get-ChildItem -LiteralPath $db -File -Recurse|Sort-Object FullName|ForEach-Object {$_.FullName.Substring($db.Length)+':'+(Get-FileHash -LiteralPath $_.FullName).Hash}) -join "`n")
}
function InstallPayload([bool]$Fresh){
    # The actual packaged Bootstrap orchestration uses synthetic discovery only;
    # no OS installer, registry, profile discovery or host deployer is invoked.
    $flow=Invoke-DaMaoWeaselBootstrapFlow -DiscoverWeasel {[pscustomobject]@{State='Usable';Root=$weasel}} `
        -StageInstaller {throw 'No external installer permitted'} -GetInstallerHash {throw 'No external installer permitted'} `
        -StartInstaller {throw 'No external installer permitted'} -DeployBigCat {
            param($nativeRoot)
            $script:installResult=& (Join-Path $app 'scripts/Install-DaMaoWithQuanpin.ps1') -RimeUserDir $user -WeaselRoot $nativeRoot -SkipDeploy -DefaultEntry Wubi -InitializeFreshRimeState:$Fresh
        }
    Check (-not $flow.Bootstrap -and $flow.WeaselRoot -ceq $weasel) 'packaged Bootstrap flow -> dual installer -> formal installer'
}
function StartEngine {
    [DaMaoRimeWubiLearningNative]::Load($RimeDll,$shared,$user,(Join-Path $user 'build'))
    Check ([DaMaoRimeWubiLearningNative]::DeployWorkspace()) 'native payload deployment'
    [DaMaoRimeWubiLearningNative]::StartService()
}
function Session {
    $session=[DaMaoRimeWubiLearningNative]::CreateDefaultSession()
    Check ([DaMaoRimeWubiLearningNative]::CurrentSchema($session) -ceq 'damao_wubi') 'actual default native schema = damao_wubi (no select_schema override)'
    return $session
}
function Query([UInt64]$Session,[string]$Code){
    [DaMaoRimeWubiLearningNative]::Clear($Session)
    $committed=''
    foreach($character in $Code.ToCharArray()){
        [void][DaMaoRimeWubiLearningNative]::ProcessKey($Session,[int]$character,0)
        $committed+=[DaMaoRimeWubiLearningNative]::ReadPendingCommit($Session)
    }
    $items=@([DaMaoRimeWubiLearningNative]::CurrentCandidates($Session,100))
    if($committed){$items=@($committed)}
    return [pscustomobject]@{Code=$Code;AutoCommit=$committed;Candidates=$items}
}
function CommitKeys([UInt64]$Session,[string]$Code,[string]$Text){
    $q=Query $Session $Code;$rank=[Array]::IndexOf([object[]]$q.Candidates,$Text);$keys=$Code
    Check ($rank -ge 0) "normal-key candidate available: $Code/$Text"
    $commit=$q.AutoCommit
    if(-not $commit){
        $view=[DaMaoRimeWubiLearningNative]::View($Session);$size=[int]$view[1]
        Check ($size -ge 1 -and $size -le 9) 'numeric selection page size'
        for($page=0;$page -lt [math]::Floor($rank/$size);$page++){
            [void][DaMaoRimeWubiLearningNative]::ProcessKey($Session,0xff56,0);$keys+='<PageDown>'
        }
        $digit=1+($rank%$size)
        [void][DaMaoRimeWubiLearningNative]::ProcessKey($Session,(48+$digit),0);$keys+=[string]$digit
        $commit=[DaMaoRimeWubiLearningNative]::ReadPendingCommit($Session)
    }
    Check ($commit -ceq $Text) "normal-key exact commit: $Text"
    $script:keyEvidence.Add([pscustomobject]@{RequestedCode=$Code;Keys=$keys;CandidateRank=$rank;Commit=$commit})
}
function Snapshot {
    Check ([DaMaoRimeWubiLearningNative]::SyncUserData()) 'native sync of isolated learning state'
    $exports=@(Get-ChildItem -LiteralPath (Join-Path $user 'sync') -Filter 'damao_wubi.userdb.txt' -Recurse -File)
    Check ($exports.Count -eq 1) 'exact formal DB export identity'
    $rows=@(foreach($line in [IO.File]::ReadLines($exports[0].FullName)){
        if($line.StartsWith('#')){continue};$f=$line.Split([char]9)
        if($f.Count -ge 3 -and $f[2] -match '(?:^|\s)c=(-?\d+)(?:\s|$)'){
            [pscustomobject]@{Code=$f[0];Text=$f[1];Commits=[int]$Matches[1];Value=$f[2]}
        }
    })
    return $rows
}
function TrainExisting([int]$Length){
    foreach($code in @('tf','wy','dd','a','g','w','f','i')){
        $s=Session
        try {
            $cold=Query $s $code
            $targets=@($cold.Candidates|Where-Object {$n=[Globalization.StringInfo]::ParseCombiningCharacters($_).Count;if($Length -eq 1){$n -eq 1}else{$n -ge 2 -and $n -le 4}})
            if($targets.Count -lt 3){continue}
            $target=$targets[2];$before=[Array]::IndexOf([object[]]$cold.Candidates,$target)
            Check ($script:words.Contains($target)) 'training target is an existing base-dictionary entry'
            $characterCount=[Globalization.StringInfo]::ParseCombiningCharacters($target).Count
            Check (($Length -eq 1 -and $characterCount -eq 1) -or ($Length -ne 1 -and $characterCount -ge 2 -and $characterCount -le 4)) 'existing phrase uses Unicode characters, not UTF-16 code units'
            for($round=0;$round -lt 20;$round++){CommitKeys $s $code $target}
            $after=Query $s $code;$rank=[Array]::IndexOf([object[]]$after.Candidates,$target)
            if($rank -ge 0 -and $rank -lt $before){
                return [pscustomobject]@{Code=$code;Target=$target;CharacterCount=$characterCount;BeforeRank=$before;LearnedRank=$rank;Rounds=20}
            }
        }finally{[DaMaoRimeWubiLearningNative]::DestroySession($s)}
    }
    throw 'No existing-entry frequency improvement found through normal keys.'
}
function CheckOldLearning($Cases,$Rows,[string]$Phase){
    $s=Session
    try {
        foreach($case in $Cases){
            $menu=Query $s $case.Code;$rank=[Array]::IndexOf([object[]]$menu.Candidates,$case.Target)
            Check ($rank -ge 0 -and $rank -lt $case.BeforeRank) "$Phase old frequency effect retained"
            Check (@($Rows|Where-Object {$_.Text -ceq $case.Target -and $_.Commits -ge 20}).Count -gt 0) "$Phase old positive learning state retained"
        }
    }finally{[DaMaoRimeWubiLearningNative]::DestroySession($s)}
}
$muscle=-join @([char]0x808C,[char]0x9187)
$four=-join @([char]0x9701,[char]0x4E91,[char]0x661F,[char]0x6E2F)
$five=$four+[char]0x9CB8
$phraseCases=@(
    [pscustomobject]@{Text=$muscle;Code='emsg';Chars=@(@([string][char]0x808C,'em'),@([string][char]0x9187,'sgyb'));Length=2},
    [pscustomobject]@{Text=$four;Code='ffji';Chars=@(@([string][char]0x9701,'fyj'),@([string][char]0x4E91,'fcu'),@([string][char]0x661F,'jtg'),@([string][char]0x6E2F,'iawn'));Length=4},
    [pscustomobject]@{Text=$five;Code='ffjq';Chars=@(@([string][char]0x9701,'fyj'),@([string][char]0x4E91,'fcu'),@([string][char]0x661F,'jtg'),@([string][char]0x6E2F,'iawn'),@([string][char]0x9CB8,'qgyi'));Length=5}
)
try {
    Check ((Get-FileHash -LiteralPath $RimeDll).Hash -ceq '2D8F1BC3737635A11D9FB1BFCA4DC9E70533633930A8A0142A81CA879C39C45B') 'locked local librime raw bytes'
    # Copy exactly the [Files] application payload, not arbitrary repository files.
    $iss=[IO.File]::ReadAllText((Join-Path $repo 'installer/windows/BigCatWubi.iss'))
    foreach($match in [regex]::Matches($iss,'(?m)^Source: "([^"]+)"; DestDir: "\{app\}([^\r\n"]*)";')){
        $source=[IO.Path]::GetFullPath((Join-Path (Join-Path $repo 'installer/windows') $match.Groups[1].Value))
        $to=$app+$match.Groups[2].Value;[void](New-Item -ItemType Directory -Path $to -Force);Copy-Item -LiteralPath $source -Destination $to
    }
    [void](New-Item -ItemType Directory -Path $shared -Force)
    WriteFixture (Join-Path $weasel 'WeaselDeployer.exe') 'synthetic; never executed'
    . (Join-Path $app 'scripts/Bootstrap-Weasel.ps1')
    . (Join-Path $app 'scripts/DaMao.SchemaUpgrade.ps1')
    if($Mode -like 'Patch*'){
        $key=if($Mode -eq 'PatchEncoder'){'enable_encoder'}else{'encode_commit_history'}
        $patch=Join-Path $user 'damao_wubi.custom.yaml';WriteFixture $patch "patch:`n  translator/${key}: false`n"
        $patchHash=(Get-FileHash $patch).Hash
    }
    InstallPayload $true
    Check (@(Get-ChildItem -LiteralPath $shared -Force).Count -eq 0) 'empty shared directory; no developer data fallback'
    Check (-not(Test-Path -LiteralPath (Join-Path $user 'damao_wubi.userdb'))) 'fresh formal userdb absent before first engine initialization'
    $dictionary=Join-Path $user 'wubi86.dict.yaml'
    $script:words=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($line in [IO.File]::ReadLines($dictionary)){if($line.Contains("`t")){[void]$script:words.Add($line.Split([char]9)[0])}}
    foreach($case in $phraseCases){Check (-not $words.Contains($case.Text)) "base dictionary excludes new $($case.Length)-character phrase"}
    $native=Join-Path $PSScriptRoot 'DaMaoRimeWubiLearningNative.cs'
    Check ([IO.File]::ReadAllText($native) -notmatch 'SetInputDelegate|commitComposition|selectCandidate') 'formal harness has no direct composition/candidate injection'
    Add-Type -Path $native
    if($Mode -eq 'Upgrade'){
        # Only source configuration is restored from immutable history, never a DB.
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip=[IO.Compression.ZipFile]::OpenRead((Join-Path $repo 'tests/fixtures/public-baseline-v1/source.zip'))
        try{$stream=$zip.GetEntry('schemas/damao_wubi.schema.yaml').Open();$memory=[IO.MemoryStream]::new();$stream.CopyTo($memory);[IO.File]::WriteAllBytes((Join-Path $user 'damao_wubi.schema.yaml'),$memory.ToArray());$stream.Dispose();$memory.Dispose()}finally{$zip.Dispose()}
        Check ((Get-FileHash (Join-Path $user 'damao_wubi.schema.yaml')).Hash -ceq '651A0EA5EE42CABD39F4D38A2C580AA04D7C95604DAC2AE6D67547470536080C') 'DEV3 exact source before learning'
    }
    StartEngine
    $oldCases=@()
    if($Mode -eq 'Upgrade'){
        $oldBuilt=[IO.File]::ReadAllText((Join-Path $user 'build/damao_wubi.schema.yaml'))
        Check ($oldBuilt -match 'enable_encoder: false' -and $oldBuilt -match 'encode_commit_history: false') 'DEV3 effective learning configuration'
        $oldCases=@((TrainExisting 2),(TrainExisting 1));$rows=@(Snapshot)
        CheckOldLearning $oldCases $rows 'DEV3'
        [DaMaoRimeWubiLearningNative]::Shutdown()
        $db=Join-Path $user 'damao_wubi.userdb';$dbIdentity=[DaMaoRimeWubiLearningNative]::DirectoryIdentity($db);$dbBefore=DbDigest
        InstallPayload $false
        Check ($script:installResult.SchemaUpgradeAction -ceq 'UpgradeExactPredecessor') 'actual installer recognized exact DEV3 predecessor'
        Check ((DbDigest) -ceq $dbBefore -and [DaMaoRimeWubiLearningNative]::DirectoryIdentity($db) -ceq $dbIdentity) 'installer preserves DB bytes and volume/file ID (no copy/rename)'
        $result.Upgrade=[ordered]@{OldCases=$oldCases;DirectoryIdentityBefore=$dbIdentity;InstallerAction=$script:installResult.SchemaUpgradeAction;InstallerDbBytesUnchanged=$true}
        StartEngine
        CheckOldLearning $oldCases @(Snapshot) 'DEV4 immediately after upgrade'
    }
    $effective=Get-DaMaoEffectiveLearningStatus -RimeUserDir $user;$result.Effective=$effective
    $disabled=$Mode -like 'Patch*'
    Check ($effective.CapabilityEnabled -eq (-not $disabled)) 'compiled effective config agrees with expected capability'
    if($disabled){Check ((Get-FileHash $patch).Hash -ceq $patchHash -and $effective.Status -ceq 'InstalledPreservedAutoPhraseDisabledByUserPatch') 'user patch preserved and effective disabled state diagnosed'}
    $observations=@()
    foreach($case in $phraseCases){
        $s=Session
        try {
            $cold=Query $s $case.Code
            Check ([Array]::IndexOf([object[]]$cold.Candidates,$case.Text) -lt 0) "cold candidate absence length $($case.Length)"
            if($case.Length -eq 2){Check ($cold.Candidates.Count -eq 1 -and $cold.Candidates[0] -ceq (-join @([char]0x80A1,[char]0x672C))) 'cold emsg is only base word gu-ben'}
            foreach($character in $case.Chars){CommitKeys $s $character[1] $character[0]}
            $after=Query $s $case.Code;$rank=[Array]::IndexOf([object[]]$after.Candidates,$case.Text)
            $expect=(-not $disabled -and $case.Length -le 4)
            Check (($rank -ge 0) -eq $expect) "automatic phrase boundary length $($case.Length), enabled=$(-not $disabled)"
            $observations+=[ordered]@{Text=$case.Text;Code=$case.Code;Length=$case.Length;Cold=$cold;After=$after;ExpectedPresent=$expect}
        }finally{[DaMaoRimeWubiLearningNative]::DestroySession($s)}
    }
    [DaMaoRimeWubiLearningNative]::Restart()
    foreach($observation in $observations){
        $s=Session
        try{$again=Query $s $observation.Code;$rank=[Array]::IndexOf([object[]]$again.Candidates,$observation.Text);Check (($rank -ge 0) -eq $observation.ExpectedPresent) "restart persistence/boundary length $($observation.Length)";$observation.Restart=$again}
        finally{[DaMaoRimeWubiLearningNative]::DestroySession($s)}
    }
    $rows=@(Snapshot)
    Check (@($rows|Where-Object Text -ceq $five).Count -eq 0) 'no whole five-character userdb entry'
    if($oldCases.Count){CheckOldLearning $oldCases $rows 'DEV4 final restart';Check ([DaMaoRimeWubiLearningNative]::DirectoryIdentity((Join-Path $user 'damao_wubi.userdb')) -ceq $dbIdentity) 'same physical DB directory after final restart'}
    if($Mode -eq 'Fresh'){
        $currentCases=@((TrainExisting 2),(TrainExisting 1));$currentRows=@(Snapshot)
        CheckOldLearning $currentCases $currentRows 'DEV4 new frequency training'
        [DaMaoRimeWubiLearningNative]::Restart()
        CheckOldLearning $currentCases @(Snapshot) 'DEV4 new frequency restart'
        $result.CurrentFrequency=$currentCases
        # Negative diagnostic control: correct installed source cannot excuse a
        # contradictory compiled config without a user patch.
        $bad=Join-Path $root 'bad-effective'
        $text=[IO.File]::ReadAllText((Join-Path $user 'build/damao_wubi.schema.yaml')).Replace('enable_encoder: true','enable_encoder: false')
        WriteFixture (Join-Path $bad 'build/damao_wubi.schema.yaml') $text
        $caught='';try{$null=Get-DaMaoEffectiveLearningStatus $bad}catch{$caught=$_.Exception.Message}
        Check ($caught -match 'DM-LEARNING-EFFECTIVE-MISMATCH') 'source correctness cannot mask contradictory compiled config'
    }
    # Unchanged punctuation, single-character, four-code composing and cancellation.
    $s=Session
    try{
        CommitKeys $s 'g' ([string][char]0x4E00)
        $q=Query $s 'gggg';Check ($q.AutoCommit -eq '' -and $q.Candidates -contains ([string][char]0x738B)) 'four-code candidate remains selectable without premature commit'
        [void][DaMaoRimeWubiLearningNative]::ProcessKey($s,32,0);Check ([DaMaoRimeWubiLearningNative]::ReadPendingCommit($s) -ceq ([string][char]0x738B)) 'four-code normal space commit'
        $q=Query $s 'em';[void][DaMaoRimeWubiLearningNative]::ProcessKey($s,0xff0d,0)
        Check ([DaMaoRimeWubiLearningNative]::ReadPendingCommit($s) -eq '' -and [DaMaoRimeWubiLearningNative]::View($s)[0] -eq '') 'composing Return still cancels'
        $q=Query $s ',';Check ($q.AutoCommit -ceq ([string][char]0xFF0C)) 'Chinese punctuation unchanged'
    }finally{[DaMaoRimeWubiLearningNative]::DestroySession($s)}
    Check (Test-Path -LiteralPath (Join-Path $user 'damao_wubi.userdb')) 'actual native DB is damao_wubi.userdb'
    Check (@(Get-ChildItem -LiteralPath $user -Recurse -Force|Where-Object Name -like 'damao_wubi_alpha03*').Count -eq 0) 'no Alpha03 schema or DB exists in isolated runtime'
    $result.Phrases=$observations;$result.Keys=$script:keyEvidence.ToArray();$result.Passed=$true
}finally{
    if('DaMaoRimeWubiLearningNative' -as [type]){[DaMaoRimeWubiLearningNative]::Shutdown()}
    $result.Assertions=$script:checks
    [void](New-Item -ItemType Directory -Path $root -Force)
    [IO.File]::WriteAllText((Join-Path $root 'result.json'),($result|ConvertTo-Json -Depth 15),[Text.UTF8Encoding]::new($false))
    Write-Host "Formal learning evidence: $root"
}
Write-Host "Formal damao_wubi native $Mode`: $script:checks passed; 0 failed; 0 skipped."
