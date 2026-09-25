[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$RimeDll,
      [ValidateSet('Wubi','Pinyin')][string]$DefaultEntry='Pinyin',
      [switch]$BootstrapFresh,
      [switch]$UpgradeDev1)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'scripts\DaMao.Common.ps1')
. (Join-Path $repo 'scripts\DaMao.Quanpin.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('BigCatQuanpinNative-'+[guid]::NewGuid().ToString('N'))
# Stage exactly the Inno [Files] application payload; no repository fallback is available.
$sourceRepo=$repo
$repo=Join-Path $root 'app'
$iss=[IO.File]::ReadAllText((Join-Path $sourceRepo 'installer\windows\BigCatWubi.iss'))
foreach($match in [regex]::Matches($iss,'(?m)^Source: "([^"]+)"; DestDir: "\{app\}([^\r\n"]*)";')){
    $source=[IO.Path]::GetFullPath((Join-Path (Join-Path $sourceRepo 'installer\windows') $match.Groups[1].Value))
    $destination=$repo+$match.Groups[2].Value
    New-Item -ItemType Directory -Path $destination -Force|Out-Null
    Copy-Item -LiteralPath $source -Destination $destination
}
$user=Join-Path $root 'user';$shared=Join-Path $root 'weasel\data'
New-Item -ItemType Directory -Path $user,$shared -Force|Out-Null
[IO.File]::WriteAllText((Join-Path $root 'weasel\WeaselDeployer.exe'),'never executed')
$count=0
function Check([bool]$ok,[string]$message){if(-not $ok){throw $message};$script:count++;Write-Host "PASS $message"}
function TypeKeys([string]$keys){foreach($c in $keys.ToCharArray()){[void][DaMaoRimeQuanpinNative]::ProcessKey($script:session,[int]$c,0)}}
try {
    if($UpgradeDev1){
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'fixtures\quanpin-dev1.custom.yaml') -Destination (Join-Path $user 'luna_quanpin.custom.yaml')
        New-Item -ItemType Directory -Path (Join-Path $user 'damao_wubi') -Force|Out-Null
        @{format_version=1;resources=@(@{RelativePath='luna_quanpin.custom.yaml';Action='Add';Kind='QuanpinDefaultPolicy';SHA256='39DFD375B5D8D2EC36FB4D3D54C829F3A3B30603D2E2C636183E55DFFE085E30'})}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $user 'damao_wubi\quanpin-install.json') -Encoding UTF8
        [IO.File]::WriteAllText((Join-Path $user 'default.custom.yaml'),(Get-DaMaoDualSchemaContent -Content '' -Fresh $true -DefaultEntry $DefaultEntry))
    }
    if($BootstrapFresh){
        [IO.File]::WriteAllText((Join-Path $user 'user.yaml'),"var:`n  previously_selected_schema: luna_pinyin`n")
        [IO.File]::WriteAllText((Join-Path $user 'default.custom.yaml'),"patch:`n  schema_list:`n    - schema: luna_pinyin`n")
    }
    & (Join-Path $repo 'scripts\Install-DaMaoWithQuanpin.ps1') -RimeUserDir $user -WeaselRoot (Split-Path $shared -Parent) -SkipDeploy -DefaultEntry $DefaultEntry -InitializeFreshRimeState:$BootstrapFresh|Out-Null
    Check (@(Get-ChildItem -LiteralPath $shared -Force).Count -eq 0) 'empty shared-data directory (no developer resources)'
    Add-Type -Path (Join-Path $PSScriptRoot 'DaMaoRimeQuanpinNative.cs')
    [DaMaoRimeQuanpinNative]::Load($RimeDll,$shared,$user,(Join-Path $user 'build'))
    Check ([DaMaoRimeQuanpinNative]::DeployWorkspace()) 'native offline deployment'
    Assert-DaMaoFormalDeployment -RimeUserDir $user
    Assert-DaMaoQuanpinDeployment -RimeUserDir $user
    [DaMaoRimeQuanpinNative]::StartService()
    $script:session=[DaMaoRimeQuanpinNative]::CreateDefaultSession()
    $expected=if($DefaultEntry -eq 'Pinyin'){'luna_quanpin'}else{'damao_wubi'}
    Check ([DaMaoRimeQuanpinNative]::CurrentSchema($session) -ceq $expected) 'first native session uses requested default without select_schema'
    Check ([DaMaoRimeQuanpinNative]::Select($session,'damao_wubi')) 'Wubi selectable'
    Check ([DaMaoRimeQuanpinNative]::Select($session,'luna_quanpin')) 'full pinyin selectable'
    Check ([DaMaoRimeQuanpinNative]::Option($session,'simplification')) 'simplified default'
    foreach($input in @('chuang','zhongguo','woaizhongguo',"xi'an")){
        [DaMaoRimeQuanpinNative]::Clear($session);TypeKeys $input
        $view=[DaMaoRimeQuanpinNative]::View($session)
        Check ($view[0].Length -gt 4 -and $view.Count -gt 2 -and [DaMaoRimeQuanpinNative]::Commit($session) -eq '') "keystroke composition/candidates: $input"
        [void][DaMaoRimeQuanpinNative]::ProcessKey($session,32,0)
        Check ([DaMaoRimeQuanpinNative]::Commit($session).Length -gt 0) "candidate commit: $input"
    }
    [DaMaoRimeQuanpinNative]::Clear($session);TypeKeys 'shi'
    [void][DaMaoRimeQuanpinNative]::ProcessKey($session,0xff56,0)
    Check ([DaMaoRimeQuanpinNative]::View($session)[1] -eq '1') 'page down'
    [void][DaMaoRimeQuanpinNative]::ProcessKey($session,0xff55,0)
    Check ([DaMaoRimeQuanpinNative]::View($session)[1] -eq '0') 'page up'
    [void][DaMaoRimeQuanpinNative]::ProcessKey($session,0xff08,0)
    Check ([DaMaoRimeQuanpinNative]::View($session)[0] -eq 'sh') 'backspace'
    [DaMaoRimeQuanpinNative]::Clear($session);TypeKeys 'guo'
    $simple=[DaMaoRimeQuanpinNative]::View($session)[2]
    [void][DaMaoRimeQuanpinNative]::ProcessKey($session,52,5)
    $traditional=[DaMaoRimeQuanpinNative]::View($session)[2]
    Check ($simple -cne $traditional) 'simplified/traditional conversion'
    [DaMaoRimeQuanpinNative]::Clear($session);TypeKeys ','
    Check ([DaMaoRimeQuanpinNative]::Commit($session).Length -gt 0) 'Chinese punctuation'
    [void][DaMaoRimeQuanpinNative]::ProcessKey($session,50,5)
    Check ([DaMaoRimeQuanpinNative]::Option($session,'ascii_mode')) 'ASCII mode switch'
    Check (-not [DaMaoRimeQuanpinNative]::ProcessKey($session,97,0)) 'ASCII key passed to host'
    [DaMaoRimeQuanpinNative]::SetOption($session,'ascii_mode',$false)
    [DaMaoRimeQuanpinNative]::Clear($session);TypeKeys 'nihaoshijie'
    $learned=[DaMaoRimeQuanpinNative]::View($session)[2]
    [void][DaMaoRimeQuanpinNative]::ProcessKey($session,32,0)
    Check ([DaMaoRimeQuanpinNative]::Commit($session) -ceq $learned) 'learning commit'
    [DaMaoRimeQuanpinNative]::DestroySession($session)
    Check ([DaMaoRimeQuanpinNative]::SyncUserData()) 'synthetic learning sync'
    [DaMaoRimeQuanpinNative]::Restart()
    $script:session=[DaMaoRimeQuanpinNative]::CreateDefaultSession()
    Check ([DaMaoRimeQuanpinNative]::CurrentSchema($session) -ceq 'luna_quanpin') 'selected pinyin survives service restart'
    TypeKeys 'nihaoshijie'
    Check ([DaMaoRimeQuanpinNative]::View($session)[2] -ceq $learned) 'learned candidate after restart'
    Check (Test-Path -LiteralPath (Join-Path $user 'luna_pinyin.userdb')) 'actual native DB is luna_pinyin.userdb'
    Check (-not (Test-Path -LiteralPath (Join-Path $user 'luna_quanpin.userdb'))) 'no guessed schema-named learning DB'
    $snapshots=@(Get-ChildItem -LiteralPath (Join-Path $user 'sync') -Filter 'luna_pinyin.userdb.txt' -Recurse -File)
    Check ($snapshots.Count -eq 1) 'native sync exports actual luna_pinyin DB'
    # Only synthetic fixture content is inspected, never the Windows Rime profile.
    Check ([IO.File]::ReadAllText($snapshots[0].FullName).Contains($learned)) 'learned phrase persisted in native DB export'
    [DaMaoRimeQuanpinNative]::Clear($session)
    [DaMaoRimeQuanpinNative]::DestroySession($session)
    [DaMaoRimeQuanpinNative]::Shutdown()
    $menuBefore=[IO.File]::ReadAllText((Join-Path $user 'default.custom.yaml'))
    $selectionBefore=(Get-FileHash -LiteralPath (Join-Path $user 'user.yaml')).Hash
    & (Join-Path $repo 'scripts\Install-DaMaoWithQuanpin.ps1') -RimeUserDir $user -WeaselRoot (Split-Path $shared -Parent) -SkipDeploy -DefaultEntry Wubi |Out-Null
    Check ([IO.File]::ReadAllText((Join-Path $user 'default.custom.yaml')) -ceq $menuBefore) 'upgrade retains scheme order'
    Check ((Get-FileHash -LiteralPath (Join-Path $user 'user.yaml')).Hash -ceq $selectionBefore) 'upgrade does not rewrite native user selection'
    [DaMaoRimeQuanpinNative]::Load($RimeDll,$shared,$user,(Join-Path $user 'build'))
    Check ([DaMaoRimeQuanpinNative]::DeployWorkspace()) 'upgrade native redeployment'
    [DaMaoRimeQuanpinNative]::StartService()
    $script:session=[DaMaoRimeQuanpinNative]::CreateDefaultSession()
    Check ([DaMaoRimeQuanpinNative]::CurrentSchema($session) -ceq 'luna_quanpin') 'upgrade retains actual selected scheme'
    [DaMaoRimeQuanpinNative]::SetOption($session,'simplification',$false)
    TypeKeys 'nihaoshijie'
    Check ([DaMaoRimeQuanpinNative]::View($session)[2] -ceq $learned) 'upgrade retains learned phrase'
    Write-Host "Quanpin native: $count passed; 0 failed; 0 skipped ($DefaultEntry)."
} finally {
    if('DaMaoRimeQuanpinNative' -as [type]){[DaMaoRimeQuanpinNative]::Shutdown()}
    Write-Host "Isolated evidence: $root"
}
