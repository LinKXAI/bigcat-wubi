[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'scripts\DaMao.Common.ps1')
. (Join-Path $repo 'scripts\DaMao.Quanpin.ps1')
. (Join-Path $repo 'scripts\Uninstall-BigCat.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('BigCatQuanpinInstall-'+[guid]::NewGuid().ToString('N'))
$weasel=Join-Path $root 'weasel'
New-Item -ItemType Directory -Path (Join-Path $weasel 'data') -Force|Out-Null
[IO.File]::WriteAllText((Join-Path $weasel 'WeaselDeployer.exe'),'not executable')
$script:count=0
function Check([bool]$ok,[string]$message){if(-not $ok){throw $message};$script:count++;Write-Host "PASS $message"}
function Put([string]$path,[string]$value){New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force|Out-Null;[IO.File]::WriteAllText($path,$value,[Text.UTF8Encoding]::new($false))}
function Install([string]$user,[string]$entry='Wubi'){
    & (Join-Path $repo 'scripts\Install-DaMaoWithQuanpin.ps1') -RimeUserDir $user -WeaselRoot $weasel -SkipDeploy -DefaultEntry $entry
}
function Digest([string]$path){
    if(-not(Test-Path -LiteralPath $path)){return ''}
    return (@(Get-ChildItem -LiteralPath $path -Recurse -File | Sort-Object FullName | ForEach-Object { $_.FullName.Substring($path.Length)+':'+(Get-FileHash -LiteralPath $_.FullName).Hash }) -join "`n")
}
try {
    foreach($entry in @('Wubi','Pinyin')){
        $user=Join-Path $root $entry
        $result=Install $user $entry
        Check ($result.Fresh -and $result.DefaultEntry -ceq $entry) "fresh $entry choice"
        $text=[IO.File]::ReadAllText((Join-Path $user 'default.custom.yaml'))
        Check ([regex]::Matches($text,'schema:').Count -eq 2) "fresh $entry has both entries only"
        $before=Digest $user
        $again=Install $user
        Check (-not $again.Fresh -and $again.DefaultEntry -ceq 'PreserveExisting') 'repeat preserves existing entry'
        Check ([IO.File]::ReadAllText((Join-Path $user 'default.custom.yaml')) -ceq $text) 'repeat menu byte preservation'
    }
    # Existing non-BigCat scheme, custom patches and synthetic DB bytes.
    $user=Join-Path $root 'existing'
    $config="patch:`n  schema_list:`n    - schema: stroke`n    - schema: luna_pinyin`n  menu/page_size: 8`n"
    Put (Join-Path $user 'default.custom.yaml') $config
    Put (Join-Path $user 'user.yaml') "var:`n  previously_selected_schema: stroke`n"
    Put (Join-Path $user 'luna_pinyin.userdb\synthetic') 'fixture learning bytes'
    Put (Join-Path $user 'damao_wubi.custom.yaml') "patch:`n  menu/page_size: 8`n"
    $result=Install $user 'Pinyin'
    $text=[IO.File]::ReadAllText((Join-Path $user 'default.custom.yaml'))
    Check ($text -match '(?s)stroke.*luna_pinyin.*damao_wubi.*luna_quanpin.*menu/page_size: 8') 'existing order and unrelated patch retained'
    Check ($result.DefaultEntry -ceq 'PreserveExisting') 'existing default ignores new-user choice'
    Check ([IO.File]::ReadAllText((Join-Path $user 'user.yaml')).Contains('stroke')) 'user selection untouched'
    Check ([IO.File]::ReadAllText((Join-Path $user 'luna_pinyin.userdb\synthetic')) -ceq 'fixture learning bytes') 'existing learning untouched'
    Check ([IO.File]::ReadAllText((Join-Path $user 'damao_wubi.custom.yaml')).Contains('menu/page_size: 8')) 'Wubi user patch untouched'
    $result=Install $user
    Check ([IO.File]::ReadAllText((Join-Path $user 'default.custom.yaml')) -ceq $text) 'existing repeat no duplicate'
    # Upgrade only the exact dev.1 bytes with its existing install receipt.
    $oldPolicy=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'fixtures\quanpin-dev1.custom.yaml'))
    $oldHash='39DFD375B5D8D2EC36FB4D3D54C829F3A3B30603D2E2C636183E55DFFE085E30'
    Check ((Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'fixtures\quanpin-dev1.custom.yaml')).Hash -ceq $oldHash) 'dev.1 fixture immutable identity'
    $oldReceipt=@{format_version=1;resources=@(@{RelativePath='luna_quanpin.custom.yaml';Action='Add';Kind='QuanpinDefaultPolicy';SHA256=$oldHash})}|ConvertTo-Json -Depth 5
    foreach($case in @('owned','unowned','customized','rollback-new-icon','rollback-existing-icon')){
        $user=Join-Path $root ('dev1-'+$case)
        Put (Join-Path $user 'luna_quanpin.custom.yaml') $oldPolicy
        Put (Join-Path $user 'default.custom.yaml') "patch:`n  schema_list: [{schema: luna_quanpin}, {schema: damao_wubi}]`n  menu/page_size: 8`n"
        Put (Join-Path $user 'luna_pinyin.userdb\synthetic') 'retain learned fixture'
        if($case -ne 'unowned'){Put (Join-Path $user 'damao_wubi\quanpin-install.json') $oldReceipt}
        if($case -eq 'customized'){Put (Join-Path $user 'luna_quanpin.custom.yaml') ($oldPolicy+"# user customization`n")}
        if($case -eq 'rollback-existing-icon'){
            New-Item -ItemType Directory -Path (Join-Path $user 'luna_quanpin\branding') -Force|Out-Null
            Copy-Item -LiteralPath (Join-Path $repo 'assets\branding\windows\bigcat-ime.ico') -Destination (Join-Path $user 'luna_quanpin\branding\bigcat-ime.ico')
        }
        $before=Digest $user
        if($case -eq 'owned'){
            $result=Install $user
            Check (@($result.Resources|Where-Object Action -eq 'UpgradeManagedPolicy').Count -eq 1) 'owned old policy upgraded'
            Check ((Get-FileHash -LiteralPath (Join-Path $user 'luna_quanpin.custom.yaml')).Hash -ceq (Get-FileHash -LiteralPath (Join-Path $repo 'schemas\luna_quanpin.custom.yaml')).Hash) 'upgrade uses exact current policy'
            $receipt=Get-Content -LiteralPath (Join-Path $user 'damao_wubi\quanpin-install.json') -Raw|ConvertFrom-Json
            Check (@($receipt.resources|Where-Object RelativePath -eq 'luna_quanpin.custom.yaml')[0].PreviousSHA256 -ceq $oldHash) 'upgrade records previous hash'
            Check ([IO.File]::ReadAllText((Join-Path $user 'luna_pinyin.userdb\synthetic')) -ceq 'retain learned fixture') 'upgrade preserves learning'
            Check ([IO.File]::ReadAllText((Join-Path $user 'default.custom.yaml')).Contains('menu/page_size: 8')) 'upgrade preserves user patch'
            $again=Install $user
            Check (@($again.Resources|Where-Object Action -eq 'UpgradeManagedPolicy').Count -eq 0) 'repeat upgrade is idempotent'
        }else{
            $failed=$false
            try{
                if($case -like 'rollback-*'){
                    & (Join-Path $repo 'scripts\Install-DaMaoWithQuanpin.ps1') -RimeUserDir $user -WeaselRoot $weasel|Out-Null
                }else{Install $user|Out-Null}
            }catch{$failed=$_.Exception.Message -match 'DM-ISOLATED-DEPLOY|DM-PINYIN-CUSTOM-CONFLICT'}
            Check $failed "expected safe rejection: $case"
            Check ((Digest $user) -ceq $before) "exact file preservation: $case"
        }
    }
    $user=Join-Path $root 'custom-icon'
    Put (Join-Path $user 'luna_quanpin\branding\bigcat-ime.ico') 'custom icon'
    $before=Digest $user;$failed=$false
    try{Install $user|Out-Null}catch{$failed=$_.Exception.Message -match 'DM-PINYIN-ICON-CONFLICT'}
    Check $failed 'customized cat icon rejected'
    Check ((Digest $user) -ceq $before) 'custom icon zero mutations'
    # Complete upstream resources are reused from a synthetic shared directory.
    Copy-Item -Path (Join-Path $repo 'third_party\rime\quanpin-weasel-0.17.4\*') -Destination (Join-Path $weasel 'data') -Recurse
    $result=Install (Join-Path $root 'shared')
    Check (@($result.Resources | Where-Object Action -eq 'ExistingSharedResource').Count -eq 14) 'complete shared dependency reuse'
    foreach($relative in @('luna_pinyin.dict.yaml','luna_quanpin.custom.yaml','luna_pinyin.custom.yaml')){
        $user=Join-Path $root ($relative.Replace('.','-'))
        Put (Join-Path $user $relative) 'customized fixture'
        $before=Digest $user
        $rejected=$false
        try{Install $user |Out-Null}catch{$rejected=$_.Exception.Message -match 'CONFLICT'}
        Check $rejected "custom conflict rejected: $relative"
        Check ((Digest $user) -ceq $before) "conflict has zero mutations: $relative"
    }
    foreach($config in @(
        "patch:`n  schema_list: [{schema: stroke}, {schema: damao_wubi}]`n  menu/page_size: 8`n",
        "patch:`n  schema_list/@before 0: {schema: damao_wubi}`n  menu/page_size: 8`n",
        "patch:`n  schema_list/+: [{schema: damao_wubi}]`n  menu/page_size: 8`n")){
        $merged=Get-DaMaoDualSchemaContent -Content $config -Fresh $false -BaseContent "schema_list:`n  - schema: stroke`n"
        Check ($merged.Contains('menu/page_size: 8')) 'merge preserves unrelated patch'
        Check ((Get-DaMaoDualSchemaContent -Content $merged -Fresh $false -BaseContent "schema_list:`n  - schema: stroke`n") -ceq $merged) 'merge idempotent'
    }
    # Trigger a failure after writes, before any real deployment: explicit alternate user path guard.
    $user=Join-Path $root 'rollback'
    Put (Join-Path $user 'default.custom.yaml') "patch:`n  schema_list: [{schema: stroke}]`n"
    Put (Join-Path $user 'luna_pinyin.userdb\synthetic') 'keep'
    Put (Join-Path $user 'build\default.yaml') 'old compiled fixture'
    $before=Digest $user
    $failed=$false
    try{& (Join-Path $repo 'scripts\Install-DaMaoWithQuanpin.ps1') -RimeUserDir $user -WeaselRoot $weasel|Out-Null}catch{$failed=$_.Exception.Message -match 'DM-ISOLATED-DEPLOY'}
    Check $failed 'injected post-write deployment failure'
    Check ((Digest $user) -ceq $before) 'rollback restores exact original file set and hashes'
    # Both uninstall orchestration branches use mocks, never installed Weasel.
    foreach($remove in @($false,$true)){
        $user=Join-Path $root ('uninstall-'+$remove)
        Install $user|Out-Null
        Put (Join-Path $user 'damao_wubi.userdb\synthetic') 'wubi'
        Put (Join-Path $user 'luna_pinyin.userdb\synthetic') 'pinyin'
        $state=Join-Path $root ('state-'+$remove+'.ini')
        Write-DaMaoInstallerState -Path $state -WeaselOrigin PreExisting -RimeUserDir $user -RimeOwnership @{}
        $command=Join-Path $weasel 'uninstall.exe';Put $command 'mock'
        $result=Invoke-DaMaoBigCatUninstall -InstallerStatePath $state -RimeUserDir $user -RemoveWeasel:$remove -WeaselRootDiscovery {$weasel} -WeaselPreparer {} -DeployerInvoker {} -RegistryReader {,[pscustomobject]@{KeyName='Weasel';DisplayName='Weasel';UninstallString=('"'+$command+'"')}} -UninstallerInvoker {0}
        Check ($result.WeaselStatus -eq $(if($remove){'Removed'}else{'Retained'})) "uninstall branch $remove"
        Check ([IO.File]::ReadAllText((Join-Path $user 'damao_wubi.userdb\synthetic')) -ceq 'wubi') 'uninstall preserves Wubi learning'
        Check ([IO.File]::ReadAllText((Join-Path $user 'luna_pinyin.userdb\synthetic')) -ceq 'pinyin') 'uninstall preserves pinyin learning'
        Check (Test-Path -LiteralPath (Join-Path $user 'luna_quanpin.custom.yaml')) 'uninstall retains pinyin policy for surviving schema'
        Check (Test-Path -LiteralPath (Join-Path $user 'luna_quanpin\branding\bigcat-ime.ico')) 'uninstall retains surviving pinyin cat icon'
        Install $user|Out-Null
        $text=[IO.File]::ReadAllText((Join-Path $user 'default.custom.yaml'))
        Check ([regex]::Matches($text,'schema: damao_wubi\b').Count -eq 1 -and [regex]::Matches($text,'schema: luna_quanpin\b').Count -eq 1) 'reinstall no duplicate entries'
    }
    Write-Host "Quanpin install: $count passed; 0 failed; 0 skipped."
} finally {Write-Host "Isolated evidence: $root"}
