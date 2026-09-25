[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$RimeDll,
      [ValidateSet('Dev1','Current')][string]$Policy='Current', [switch]$CustomDefaults)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=Split-Path $PSScriptRoot -Parent
$root=Join-Path ([IO.Path]::GetTempPath()) ('BigCatQuanpinSwitch-'+[guid]::NewGuid().ToString('N'))
$user=Join-Path $root 'user';$weasel=Join-Path $root 'weasel'
New-Item -ItemType Directory -Path $user,(Join-Path $weasel 'data') -Force|Out-Null
[IO.File]::WriteAllText((Join-Path $weasel 'WeaselDeployer.exe'),'not executable')
$count=0
function Check([bool]$ok,[string]$message){if(-not $ok){throw $message};$script:count++;Write-Host "PASS $message"}
function TypeKeys([string]$keys){foreach($c in $keys.ToCharArray()){[void][DaMaoRimeQuanpinNative]::ProcessKey($script:session,[int]$c,0)}}
$results=@()
try {
    if($CustomDefaults){
        $customDefault="patch:`n  schema_list: [{schema: luna_quanpin}, {schema: damao_wubi}]`n  ascii_composer/good_old_caps_lock: false`n  ascii_composer/switch_key/Control_L: commit_code`n"
        [IO.File]::WriteAllText((Join-Path $user 'default.custom.yaml'),$customDefault)
    }
    & (Join-Path $repo 'scripts\Install-DaMaoWithQuanpin.ps1') -RimeUserDir $user -WeaselRoot $weasel -SkipDeploy -DefaultEntry Pinyin|Out-Null
    if($Policy -eq 'Dev1'){
        # Synthetic baseline fixture only; never modify any installed profile.
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'fixtures\quanpin-dev1.custom.yaml') -Destination (Join-Path $user 'luna_quanpin.custom.yaml') -Force
    }
    Add-Type -Path (Join-Path $PSScriptRoot 'DaMaoRimeQuanpinNative.cs')
    [DaMaoRimeQuanpinNative]::Load($RimeDll,(Join-Path $weasel 'data'),$user,(Join-Path $user 'build'))
    Check ([DaMaoRimeQuanpinNative]::DeployWorkspace()) 'native offline deployment'
    [DaMaoRimeQuanpinNative]::StartService()
    $script:session=[DaMaoRimeQuanpinNative]::CreateSession('luna_quanpin')
    $xian=-join @([char]0x897f,[char]0x5b89)
    foreach($action in @('Return','Space','Shift_L','Shift_R','CtrlShift2','SetOption','Caps_Lock','Eisu_toggle')){
        [DaMaoRimeQuanpinNative]::Clear($session)
        [void][DaMaoRimeQuanpinNative]::Commit($session)
        [DaMaoRimeQuanpinNative]::SetOption($session,'ascii_mode',$false)
        TypeKeys "xi'an"
        Check ([DaMaoRimeQuanpinNative]::View($session)[2] -ceq $xian) "$action begins with uncommitted Xian candidate"
        switch($action){
            Return {[void][DaMaoRimeQuanpinNative]::ProcessKey($session,0xff0d,0)}
            Space {[void][DaMaoRimeQuanpinNative]::ProcessKey($session,32,0)}
            Shift_L {[void][DaMaoRimeQuanpinNative]::ProcessKey($session,0xffe1,0);[void][DaMaoRimeQuanpinNative]::ProcessKey($session,0xffe1,0x40000000)}
            Shift_R {[void][DaMaoRimeQuanpinNative]::ProcessKey($session,0xffe2,0);[void][DaMaoRimeQuanpinNative]::ProcessKey($session,0xffe2,0x40000000)}
            CtrlShift2 {[void][DaMaoRimeQuanpinNative]::ProcessKey($session,50,5)}
            SetOption {[DaMaoRimeQuanpinNative]::SetOption($session,'ascii_mode',$true)}
            Caps_Lock {[void][DaMaoRimeQuanpinNative]::ProcessKey($session,0xffe5,0)}
            Eisu_toggle {[void][DaMaoRimeQuanpinNative]::ProcessKey($session,0xff30,0)}
        }
        $commit=[DaMaoRimeQuanpinNative]::Commit($session)
        $preedit=[DaMaoRimeQuanpinNative]::View($session)[0]
        $ascii=[DaMaoRimeQuanpinNative]::Option($session,'ascii_mode')
        $results += [pscustomobject]@{action=$action;commit=$commit;preedit=$preedit;ascii=$ascii}
        Write-Host ($results[-1]|ConvertTo-Json -Compress)
        if($Policy -eq 'Current' -and $action -in @('Shift_L','Shift_R')){
            Check ($commit -ceq "xi'an" -and $preedit -ceq '' -and $ascii) "$action commits exact raw code immediately, without a space, and enters ASCII"
            Check ([DaMaoRimeQuanpinNative]::Commit($session) -ceq '') "$action has no second commit"
        }
        if($action -eq 'Return'){Check ($commit -ceq "xi'an" -and $preedit -ceq '' -and -not $ascii) 'Return remains raw-code commit in Chinese mode'}
        if($action -in @('CtrlShift2','SetOption')){Check ($commit -ceq '' -and $preedit -ceq "xi'an" -and $ascii) "$action retains current native inline behavior"}
        if($action -in @('Caps_Lock','Eisu_toggle')){Check ($commit -ceq '' -and $preedit -ceq '' -and $ascii) "$action retains current native clear behavior"}
        if($Policy -eq 'Dev1' -and $action -eq 'Shift_L'){Check ($commit -ceq '' -and $preedit -ceq "xi'an" -and $ascii) 'dev.1 left Shift baseline inline behavior'}
        if($Policy -eq 'Dev1' -and $action -eq 'Shift_R'){Check ($commit -ceq $xian -and $preedit -ceq '' -and $ascii) 'dev.1 right Shift baseline candidate commit'}
        if($action -eq 'Space'){Check ($commit -ceq $xian -and -not $ascii) 'Chinese Space commits candidate'}
    }
    [DaMaoRimeQuanpinNative]::Clear($session)
    [void][DaMaoRimeQuanpinNative]::Commit($session)
    [DaMaoRimeQuanpinNative]::SetOption($session,'ascii_mode',$true)
    $handled=[DaMaoRimeQuanpinNative]::ProcessKey($session,32,0)
    Check (-not $handled -and [DaMaoRimeQuanpinNative]::Commit($session) -ceq '') 'ordinary English Space is passed to the host unchanged'
    if($Policy -eq 'Current'){
        $compiled=[IO.File]::ReadAllText((Join-Path $user 'build\luna_quanpin.schema.yaml'))
        foreach($key in @('icon','ascii_icon')){
            Check ($compiled -match ('(?m)^\s*'+$key+':\s*["'']?luna_quanpin/branding/bigcat-ime\.ico["'']?\s*$')) "effective $key references cat icon"
        }
        if($CustomDefaults){
            Check ($compiled -match '(?m)^\s*good_old_caps_lock: false\s*$') 'inherits user Caps Lock policy'
            Check ($compiled -match '(?m)^\s*Control_L: commit_code\s*$') 'inherits user non-Shift switch action'
            Check ([IO.File]::ReadAllText((Join-Path $user 'default.custom.yaml')) -ceq $customDefault) 'user default patch unchanged'
        }
        Check ((Get-FileHash -LiteralPath (Join-Path $user 'luna_quanpin\branding\bigcat-ime.ico')).Hash -ceq (Get-FileHash -LiteralPath (Join-Path $repo 'assets\branding\windows\bigcat-ime.ico')).Hash) 'deployed cat asset exact match'
    }
    $results|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $root 'switch-results.json') -Encoding UTF8
    Write-Host "Quanpin switch $Policy`: $count passed; 0 failed; 0 skipped."
} finally {
    if('DaMaoRimeQuanpinNative' -as [type]){[DaMaoRimeQuanpinNative]::Shutdown()}
    Write-Host "Isolated evidence: $root"
}
