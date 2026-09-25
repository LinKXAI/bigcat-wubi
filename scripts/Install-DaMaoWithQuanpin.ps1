[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string]$RimeUserDir, [string]$WeaselRoot, [string]$WubiSourcePath,
    [switch]$InstallWubiDependency, [switch]$SkipDeploy, [switch]$UserFacingRedeploy,
    [switch]$InitializeFreshRimeState, [string]$InstallerStatePath,
    [ValidateSet('Wubi','Pinyin')][string]$DefaultEntry='Wubi'
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'DaMao.Common.ps1')
. (Join-Path $PSScriptRoot 'DaMao.Quanpin.ps1')
$repoRoot=Split-Path $PSScriptRoot -Parent
$user=Get-DaMaoRimeUserDir -Override $RimeUserDir
$weasel=Get-DaMaoWeaselRoot -Override $WeaselRoot
if(Test-DaMaoPathWithin -Path $user -Parent $weasel){throw '[DM-PINYIN-PATH] User and program directories must be separate.'}
$fresh=($InitializeFreshRimeState -or -not(Test-Path -LiteralPath $user) -or @(Get-ChildItem -LiteralPath $user -Force).Count -eq 0)
$plan=@(Get-DaMaoQuanpinPlan -RepoRoot $repoRoot -RimeUserDir $user -WeaselRoot $weasel)
$defaultPath=Join-Path $user 'default.custom.yaml'
Assert-DaMaoQuanpinPlainPath -Path $defaultPath
$oldContent=if(Test-Path -LiteralPath $defaultPath){[IO.File]::ReadAllText($defaultPath)}else{''}
$basePath=Join-Path $user 'default.yaml'
if(-not(Test-Path -LiteralPath $basePath)){$basePath=Join-Path $weasel 'data\default.yaml'}
if(-not(Test-Path -LiteralPath $basePath)){$basePath=Join-Path $repoRoot 'third_party\rime\quanpin-weasel-0.17.4\default.yaml'}
$newContent=Get-DaMaoDualSchemaContent -Content $oldContent -Fresh $fresh -DefaultEntry $DefaultEntry -BaseContent ([IO.File]::ReadAllText($basePath))
# All preflight conflicts are found before the first write. Never overwrite custom source resources.
foreach($pair in @(@('damao_wubi.schema.yaml','schemas\damao_wubi.schema.yaml'),@('wubi86.dict.yaml','third_party\rime\rime-wubi\wubi86.dict.yaml'))){
    $target=Join-Path $user $pair[0];$source=Join-Path $repoRoot $pair[1]
    if((Test-Path -LiteralPath $target) -and (Get-FileHash -LiteralPath $target).Hash -ne (Get-FileHash -LiteralPath $source).Hash){throw "[DM-RESOURCE-CONFLICT] Existing customized resource preserved: $($pair[0])"}
}
if(-not $PSCmdlet.ShouldProcess($user,'Install offline Wubi and full pinyin, preserving existing selection and learning data')){return}
$transaction=Join-Path ([IO.Path]::GetTempPath()) ('BigCatQuanpin-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $transaction|Out-Null
$targets=@($plan|Where-Object { $_.Action -in @('Add','UpgradeManagedPolicy') }|ForEach-Object Target)
$targets+=@('default.custom.yaml','damao_wubi.schema.yaml','damao_wubi\branding\bigcat-ime.ico','wubi86.dict.yaml','LICENSE.rime-wubi.txt','rime-wubi.source.json','damao_wubi\quanpin-install.json'|ForEach-Object {Join-Path $user $_})
if($InstallerStatePath){$targets+=$InstallerStatePath}
$backupRoot=Join-Path $user 'backup'
$backupBefore=@()
if(Test-Path -LiteralPath $backupRoot){$backupBefore=@(Get-ChildItem -LiteralPath $backupRoot -Directory -Filter 'damao-ime-config-*' | ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -File | Where-Object Name -in @('default.custom.yaml','damao_wubi.schema.yaml') } | ForEach-Object FullName);$targets+=$backupBefore}
$directoriesBefore=@()
if(Test-Path -LiteralPath $user){$directoriesBefore=@($user)+@(Get-ChildItem -LiteralPath $user -Directory -Recurse | ForEach-Object FullName)}
$built=Join-Path $user 'build'
$builtBefore=@()
if(Test-Path -LiteralPath $built){$builtBefore=@(Get-ChildItem -LiteralPath $built -File -Recurse|ForEach-Object FullName);$targets+=$builtBefore}
$snapshots=@();$index=0
foreach($target in @($targets|Select-Object -Unique)){
    Assert-DaMaoQuanpinPlainPath -Path $target
    $copy=Join-Path $transaction ([string]$index);$index++
    $exists=Test-Path -LiteralPath $target -PathType Leaf
    if($exists){Copy-Item -LiteralPath $target -Destination $copy}
    $snapshots += [pscustomobject]@{Target=$target;Existed=$exists;Copy=$copy}
}
try {
    foreach($item in $plan|Where-Object { $_.Action -in @('Add','UpgradeManagedPolicy') }){
        New-Item -ItemType Directory -Path (Split-Path $item.Target -Parent) -Force|Out-Null
        Copy-Item -LiteralPath $item.Source -Destination $item.Target
    }
    # Reuse stable formal Wubi installation; it never performs deployment here.
    $installArgs=@{RimeUserDir=$user;WeaselRoot=$weasel;SkipDeploy=$true}
    if($InstallerStatePath){$installArgs.InstallerStatePath=$InstallerStatePath}
    if($null -eq (Get-DaMaoDependencyFile -RimeUserDir $user -WeaselRoot $weasel)){
        $installArgs.WubiSourcePath=Join-Path $repoRoot 'third_party\rime\rime-wubi'
    }
    & (Join-Path $PSScriptRoot 'Install-DaMao.ps1') @installArgs | Out-Null
    # The dual-entry merger starts from the original configuration, not legacy normalization.
    Write-DaMaoUtf8File -Path $defaultPath -Content $newContent
    if(-not $SkipDeploy){
        # A custom fixture directory must never accidentally deploy the real Windows profile.
        if($RimeUserDir -and -not [string]::Equals($user,(Get-DaMaoRimeUserDir),[StringComparison]::OrdinalIgnoreCase)){
            throw '[DM-ISOLATED-DEPLOY] Explicit alternate directories require SkipDeploy plus the isolated native test runner.'
        }
        Invoke-DaMaoDeployer -WeaselRoot $weasel -Command '/deploy' -TimeoutSeconds 120
        Assert-DaMaoFormalDeployment -RimeUserDir $user
        Assert-DaMaoQuanpinDeployment -RimeUserDir $user
    }
    $ledger=Join-Path $user 'damao_wubi\quanpin-install.json'
    $history=@()
    if(Test-Path -LiteralPath $ledger){$history=@((Get-Content -LiteralPath $ledger -Raw|ConvertFrom-Json).resources)}
    foreach($item in $plan | Where-Object Action -eq 'UpgradeManagedPolicy'){
        $prior=@($history | Where-Object RelativePath -eq $item.RelativePath)[0]
        $history=@($history | Where-Object RelativePath -ne $item.RelativePath)
        $history+=[pscustomobject]@{RelativePath=$item.RelativePath;Action=$item.Action;Kind=$item.Kind;SHA256=$item.SHA256;PreviousSHA256=$prior.SHA256}
    }
    foreach($item in $plan){if(@($history | ForEach-Object RelativePath) -notcontains $item.RelativePath){$history+=[pscustomobject]@{RelativePath=$item.RelativePath;Action=$item.Action;Kind=$item.Kind;SHA256=$item.SHA256}}}
    New-Item -ItemType Directory -Path (Split-Path $ledger -Parent) -Force|Out-Null
    [ordered]@{format_version=1;resources=$history;uninstall_policy='Preserve shared full-pinyin resources and all personal learning data';default_entry_applied=if($fresh){$DefaultEntry}else{'PreserveExisting'};pinyin_portability='Not covered by PureWubi backup/restore'}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $ledger -Encoding UTF8
    [pscustomobject]@{Schemas=@('damao_wubi','luna_quanpin');Fresh=$fresh;DefaultEntry=if($fresh){$DefaultEntry}else{'PreserveExisting'};Deployed=(-not $SkipDeploy);Resources=$plan}
}
catch {
    $original=$_
    # Only this transaction's exact source targets and deploy cache changes are rolled back.
    if(Test-Path -LiteralPath $built){foreach($file in @(Get-ChildItem -LiteralPath $built -File -Recurse)){if($builtBefore -notcontains $file.FullName){Remove-Item -LiteralPath $file.FullName -Force}}}
    if(Test-Path -LiteralPath $backupRoot){foreach($file in @(Get-ChildItem -LiteralPath $backupRoot -Directory -Filter 'damao-ime-config-*' | ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -File | Where-Object Name -in @('default.custom.yaml','damao_wubi.schema.yaml') })){if($backupBefore -notcontains $file.FullName){Remove-Item -LiteralPath $file.FullName -Force}}}
    foreach($item in $snapshots){
        if($item.Existed){Copy-Item -LiteralPath $item.Copy -Destination $item.Target -Force}
        elseif(Test-Path -LiteralPath $item.Target -PathType Leaf){Remove-Item -LiteralPath $item.Target -Force}
    }
    if(Test-Path -LiteralPath $user){
        $dirs=@(Get-ChildItem -LiteralPath $user -Directory -Recurse | ForEach-Object FullName)+@($user)
        foreach($dir in @($dirs | Sort-Object Length -Descending)){
            if($directoriesBefore -notcontains $dir -and @(Get-ChildItem -LiteralPath $dir -Force).Count -eq 0){Remove-Item -LiteralPath $dir -Force}
        }
    }
    if($UserFacingRedeploy){Write-Host 'Deployment failed; this attempt was rolled back. Existing configuration and learning data are retained.';Write-Host $original.Exception.Message}
    throw $original
}
finally {
    $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if([IO.Path]::GetFullPath($transaction).StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $transaction -Recurse -Force}
}