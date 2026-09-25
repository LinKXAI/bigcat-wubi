function Assert-DaMaoQuanpinPlainPath {
    param([string]$Path)
    $cursor=[IO.Path]::GetFullPath($Path)
    while($cursor){
        if(Test-Path -LiteralPath $cursor){
            if((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){
                throw "[DM-PINYIN-PATH] Reparse points are not supported: $cursor"
            }
        }
        $cursor=Split-Path $cursor -Parent
    }
}

function Assert-DaMaoQuanpinSharedPolicy {
    param([Parameter(Mandatory=$true)][string]$PolicyPath,
          [Parameter(Mandatory=$true)][string]$WeaselRoot)
    $shared=Join-Path (Join-Path $WeaselRoot 'data') 'luna_quanpin.custom.yaml'
    Assert-DaMaoQuanpinPlainPath -Path $shared
    if(Test-Path -LiteralPath $shared){
        # Native resolution replaces the shared custom wholesale with the local custom.
        # Byte equality is the only compatibility proof supported here; no merge/ownership claim.
        if(-not(Test-Path -LiteralPath $shared -PathType Leaf) -or
           (Get-FileHash -LiteralPath $shared).Hash -ne (Get-FileHash -LiteralPath $PolicyPath).Hash){
            throw "[DM-PINYIN-SHARED-POLICY-CONFLICT] Shared full-pinyin customization would be shadowed; unchanged: $shared"
        }
    }
}

# Offline full-pinyin policy. Existing input/portability implementations stay unchanged.
function Get-DaMaoQuanpinPlan {
    param([string]$RepoRoot, [string]$RimeUserDir, [string]$WeaselRoot)
    Assert-DaMaoQuanpinSharedPolicy -PolicyPath (Join-Path $RepoRoot 'schemas\luna_quanpin.custom.yaml') -WeaselRoot $WeaselRoot
    $lock = Get-Content -LiteralPath (Join-Path $RepoRoot 'dependencies\quanpin.lock.json') -Raw | ConvertFrom-Json
    if ($lock.format_version -ne 1 -or $lock.source.sha256 -ne 'CF509534A8F5F8AF9C98ED7CBB8F135439F145A8CBE7E50EDE42BB5B5AB45C29') {
        throw '[DM-PINYIN-LOCK] Unsupported full-pinyin lock.'
    }
    foreach($notice in $lock.notices) {
        $noticePath=Join-Path $RepoRoot ('third_party\rime\quanpin-weasel-0.17.4\'+$notice.path)
        if((Get-FileHash -LiteralPath $noticePath).Hash -ne $notice.sha256){throw '[DM-PINYIN-LOCK] Attribution integrity failed.'}
    }
    Assert-DaMaoQuanpinPlainPath -Path $RimeUserDir
    foreach($name in @('luna_pinyin','stroke','pinyin','key_bindings','punctuation','symbols')) {
        foreach($root in @($RimeUserDir,(Join-Path $WeaselRoot 'data'))) {
            if(Test-Path -LiteralPath (Join-Path $root ($name+'.custom.yaml'))) {
                throw "[DM-PINYIN-CUSTOM-CONFLICT] Existing dependency patch is preserved: $name.custom.yaml"
            }
        }
    }
    $result = @()
    foreach ($entry in $lock.files) {
        $relative = [string]$entry.path
        if ([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[\\/])\.\.([\\/]|$)') { throw '[DM-PINYIN-LOCK] Unsafe resource path.' }
        $source = Join-Path $RepoRoot ('third_party\rime\quanpin-weasel-0.17.4\' + $relative)
        if (-not (Test-Path -LiteralPath $source -PathType Leaf) -or
            (Get-FileHash -LiteralPath $source).Hash -ne $entry.sha256 -or
            (Get-Item -LiteralPath $source).Length -ne $entry.size) { throw "[DM-PINYIN-LOCK] Resource integrity failed: $relative" }
        $target = Join-Path $RimeUserDir $relative
        Assert-DaMaoQuanpinPlainPath -Path $target
        $shared = Join-Path (Join-Path $WeaselRoot 'data') $relative
        Assert-DaMaoQuanpinPlainPath -Path $shared
        $action = 'Add'
        $effective = $null
        if (Test-Path -LiteralPath $target) { $effective = $target; $action = 'ExistingUserResource' }
        elseif (Test-Path -LiteralPath $shared) { $effective = $shared; $action = 'ExistingSharedResource' }
        if ($null -ne $effective) {
            if (-not (Test-Path -LiteralPath $effective -PathType Leaf) -or
                ((Get-Item -LiteralPath $effective -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -or
                (Get-FileHash -LiteralPath $effective).Hash -ne $entry.sha256) {
                throw "[DM-PINYIN-RESOURCE-CONFLICT] Customized or incompatible resource; unchanged: $relative"
            }
        }
        $result += [pscustomobject]@{ RelativePath=$relative; Source=$source; Target=$target; Action=$action; SHA256=$entry.sha256; Kind='SharedDependency' }
    }
    $relative = 'luna_quanpin.custom.yaml'
    $source = Join-Path $RepoRoot ('schemas\' + $relative)
    $target = Join-Path $RimeUserDir $relative
    Assert-DaMaoQuanpinPlainPath -Path $target
    $hash = (Get-FileHash -LiteralPath $source).Hash
    $action = 'Add'
    if (Test-Path -LiteralPath $target) {
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw '[DM-PINYIN-CUSTOM-CONFLICT] Full-pinyin policy is not a regular file.' }
        $existingHash=(Get-FileHash -LiteralPath $target).Hash
        if ($existingHash -eq $hash) { $action='ExistingUserResource' }
        else {
            # Only the byte-exact dev.1 policy AND its ownership receipt may be upgraded.
            $dev1='39DFD375B5D8D2EC36FB4D3D54C829F3A3B30603D2E2C636183E55DFFE085E30'
            $ledger=Join-Path $RimeUserDir 'damao_wubi\quanpin-install.json'
            Assert-DaMaoQuanpinPlainPath -Path $ledger
            $owned=$false
            if ($existingHash -eq $dev1 -and (Test-Path -LiteralPath $ledger -PathType Leaf)) {
                try {
                    $receipt=Get-Content -LiteralPath $ledger -Raw | ConvertFrom-Json
                    $matches=@($receipt.resources | Where-Object { $_.RelativePath -ceq $relative })
                    $owned=($receipt.format_version -eq 1 -and $matches.Count -eq 1 -and
                        $matches[0].Kind -ceq 'QuanpinDefaultPolicy' -and $matches[0].Action -ceq 'Add' -and $matches[0].SHA256 -ceq $dev1)
                } catch { $owned=$false }
            }
            if (-not $owned) { throw '[DM-PINYIN-CUSTOM-CONFLICT] Existing luna_quanpin.custom.yaml is preserved; it is not an unchanged, installer-owned dev.1 policy.' }
            $action='UpgradeManagedPolicy'
        }
    }
    $result += [pscustomobject]@{ RelativePath=$relative; Source=$source; Target=$target; Action=$action; SHA256=$hash; Kind='QuanpinDefaultPolicy' }
    # Reuse the existing asset bytes under the surviving pinyin schema, independent of Wubi uninstall.
    $relative='luna_quanpin/branding/bigcat-ime.ico'
    $source=Join-Path $RepoRoot 'assets\branding\windows\bigcat-ime.ico'
    $target=Join-Path $RimeUserDir $relative
    Assert-DaMaoQuanpinPlainPath -Path $target
    $hash=(Get-FileHash -LiteralPath $source).Hash
    $action='Add'
    if(Test-Path -LiteralPath $target){
        if(-not(Test-Path -LiteralPath $target -PathType Leaf) -or (Get-FileHash -LiteralPath $target).Hash -ne $hash){
            throw '[DM-PINYIN-ICON-CONFLICT] Customized full-pinyin icon is preserved.'
        }
        $action='ExistingUserResource'
    }
    $result += [pscustomobject]@{RelativePath=$relative;Source=$source;Target=$target;Action=$action;SHA256=$hash;Kind='QuanpinBranding'}
    return $result
}

function Get-DaMaoDualSchemaContent {
    param([AllowEmptyString()][string]$Content, [bool]$Fresh, [ValidateSet('Wubi','Pinyin')][string]$DefaultEntry='Wubi', [string]$BaseContent='')
    if ($Fresh) {
        $first = if ($DefaultEntry -eq 'Pinyin') { 'luna_quanpin' } else { 'damao_wubi' }
        $second = if ($DefaultEntry -eq 'Pinyin') { 'damao_wubi' } else { 'luna_quanpin' }
        return "patch:`n  schema_list:`n    - schema: $first`n    - schema: $second`n"
    }
    if ([string]::IsNullOrWhiteSpace($Content)) { $Content = "patch:`n" }
    if ($Content.Contains("`t")) { throw '[DM-CONFIG-MERGE-UNSAFE] Tab-indented configuration is preserved.' }
    $lines = [Collections.Generic.List[string]]::new()
    foreach ($line in ($Content.TrimStart([char]0xFEFF).TrimEnd("`r","`n") -split "`r?`n")) { $lines.Add($line) }
    $indices = @(0..($lines.Count-1) | Where-Object { $lines[$_] -match '^patch:\s*(#.*)?$' })
    if ($indices.Count -ne 1) { throw '[DM-CONFIG-MERGE-UNSAFE] Expected one block patch; original configuration unchanged.' }
    $start = $indices[0]; $end = $lines.Count
    for ($i=$start+1; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^[^\s#]') { $end=$i; break } }
    $structures = @(Get-DaMaoPatchSchemaStructures -Lines $lines -PatchIndex $start -PatchEnd $end -ContextPath 'default.custom.yaml')
    $known = @($structures | ForEach-Object { $_.Entries } | ForEach-Object { $_.SchemaId })
    if (@($known | Group-Object | Where-Object Count -gt 1).Count -gt 0) { throw '[DM-CONFIG-MERGE-UNSAFE] Duplicate existing schema entries are preserved for manual resolution.' }
    $explicit = @($structures | Where-Object Key -eq 'schema_list')
    if ($explicit.Count -eq 0) {
        $baseMatches = [regex]::Matches($BaseContent, '(?m)^\s*-\s*(?:\{\s*)?schema:\s*([a-zA-Z0-9_]+)')
        $known += @($baseMatches | ForEach-Object { $_.Groups[1].Value })
    }
    $missing = @('damao_wubi','luna_quanpin' | Where-Object { $known -cnotcontains $_ })
    if ($missing.Count -eq 0) { return $Content }
    $target = @($structures | Where-Object { $_.Key -eq 'schema_list' -or $_.Key -eq 'schema_list/+' } | Select-Object -First 1)
    if ($target.Count -eq 0) {
        $addition = @('  "schema_list/+":') + @($missing | ForEach-Object { '    - schema: ' + $_ })
        for ($i=0; $i -lt $addition.Count; $i++) { $lines.Insert($end+$i,$addition[$i]) }
    } else {
        $t=$target[0]
        if ($t.IsInlineValue) {
            $render = @(((' ' * $t.KeyIndent) + '"' + $t.Key + '":' + $t.KeyComment))
            $render += @($t.Entries | ForEach-Object { (' ' * ($t.KeyIndent+2)) + '- schema: ' + $_.SchemaId + $_.Comment })
            $render += @($missing | ForEach-Object { (' ' * ($t.KeyIndent+2)) + '- schema: ' + $_ })
            $lines.RemoveRange($t.KeyIndex,$t.EndIndex-$t.KeyIndex)
            for($i=0;$i -lt $render.Count;$i++){ $lines.Insert($t.KeyIndex+$i,$render[$i]) }
        } else {
            $indent=if($null -ne $t.SequenceIndent){$t.SequenceIndent}else{$t.KeyIndent+2}
            for($i=0;$i -lt $missing.Count;$i++){ $lines.Insert($t.EndIndex+$i,((' ' * $indent)+'- schema: '+$missing[$i])) }
        }
    }
    return (($lines -join "`n") + "`n")
}

function Assert-DaMaoQuanpinDeployment {
    param([string]$RimeUserDir)
    $path=Join-Path $RimeUserDir 'build\luna_quanpin.schema.yaml'
    if (-not (Test-Path -LiteralPath $path)) { throw '[DM-PINYIN-DEPLOY] Full-pinyin schema was not compiled.' }
    $text=[IO.File]::ReadAllText($path)
    if ($text -notmatch '(?m)^\s*schema_id:\s*luna_quanpin\s*$' -or $text -notmatch 'script_translator' -or
        $text -notmatch '(?m)^\s*dictionary:\s*luna_pinyin\s*$' -or $text -match '(?m)^\s*max_code_length:\s*4\s*$') {
        throw '[DM-PINYIN-DEPLOY] Effective full-pinyin engine or dictionary is incompatible.'
    }
    foreach($key in @('icon','ascii_icon')){
        if($text -notmatch ('(?m)^\s*'+$key+':\s*["'']?luna_quanpin/branding/bigcat-ime\.ico["'']?\s*$')){throw '[DM-PINYIN-ICON] Compiled schema is missing its cat icon.'}
    }
    if(-not(Test-Path -LiteralPath (Join-Path $RimeUserDir 'luna_quanpin\branding\bigcat-ime.ico') -PathType Leaf)){throw '[DM-PINYIN-ICON] Deployed icon resource missing.'}
    foreach($f in @('luna_quanpin.prism.bin','luna_pinyin.table.bin','stroke.table.bin')) {
        if(-not(Test-Path -LiteralPath (Join-Path $RimeUserDir ('build\'+$f)))) { throw "[DM-PINYIN-DEPLOY] Missing compiled resource: $f" }
    }
    $default=[IO.File]::ReadAllText((Join-Path $RimeUserDir 'build\default.yaml'))
    foreach($id in @('damao_wubi','luna_quanpin')) {
        if ([regex]::Matches($default,'(?m)^\s*-\s*schema:\s*["'']?'+$id+'["'']?\s*$').Count -ne 1) { throw '[DM-PINYIN-DEPLOY] Both entries must be registered exactly once.' }
    }
}