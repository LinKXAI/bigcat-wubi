function Assert-DaMaoSchemaPlainPath {
    param([string]$Path)
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        if ((Test-Path -LiteralPath $cursor) -and
            ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw '[DM-RESOURCE-CONFLICT] Reparse path rejected before schema installation.'
        }
        $cursor = Split-Path -Parent $cursor
    }
}

function Get-DaMaoSchemaUpgradePlan {
    param([string]$RepositoryRoot, [string]$RimeUserDir)
    $contractPath = Join-Path $RepositoryRoot 'contracts/wubi-schema-upgrade-v1.json'
    $source = Join-Path $RepositoryRoot 'schemas/damao_wubi.schema.yaml'
    $target = Join-Path $RimeUserDir 'damao_wubi.schema.yaml'
    foreach ($path in @($contractPath, $source, $target)) { Assert-DaMaoSchemaPlainPath $path }
    $contract = [IO.File]::ReadAllText($contractPath) | ConvertFrom-Json
    if ($contract.format_version -ne 1 -or $contract.contract_id -cne 'bigcat-wubi-dev3-to-dev4-schema' -or
        $contract.schema_id -cne 'damao_wubi' -or $contract.user_dict -cne 'damao_wubi' -or
        $contract.predecessor_commit -cne '97d0d659bbe808d11c0eefa3114ea929e0151e7f' -or
        $contract.predecessor_sha256 -cne '651A0EA5EE42CABD39F4D38A2C580AA04D7C95604DAC2AE6D67547470536080C' -or
        $contract.successor_sha256 -cne 'A618CEAC52FA428C52172FE8042B3CC61F275C25445C74F32A57B5D054457CFA' -or
        $contract.automatic_userdb_migration -ne $false) {
        throw '[DM-RESOURCE-CONFLICT] Invalid official schema upgrade contract.'
    }
    if (-not (Test-Path -LiteralPath $source -PathType Leaf) -or
        (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -cne $contract.successor_sha256) {
        throw '[DM-RESOURCE-CONFLICT] Source is not the authorized official successor.'
    }
    $before = 'ABSENT'; $action = 'Install'
    if (Test-Path -LiteralPath $target) {
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw '[DM-RESOURCE-CONFLICT] Schema target is not a regular file.' }
        $before = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
        if ($before -ceq $contract.successor_sha256) { $action = 'Reuse' }
        elseif ($before -ceq $contract.predecessor_sha256) { $action = 'UpgradeExactPredecessor' }
        else { throw '[DM-RESOURCE-CONFLICT] Unknown or customized Wubi schema preserved.' }
    }
    $patch = Join-Path $RimeUserDir 'damao_wubi.custom.yaml'
    Assert-DaMaoSchemaPlainPath $patch
    $patchStatus = 'NoUserPatch'
    if (Test-Path -LiteralPath $patch) {
        $patchStatus = 'RequiresEffectiveConfigValidation'
        Write-Warning '[DM-LEARNING-PATCH-REVIEW] Wubi custom patch retained. Source upgrade does not prove effective encoder/history behavior; compiled configuration and native acceptance are required.'
        if ([IO.File]::ReadAllText($patch) -match '(?m)(enable_encoder|encode_commit_history)["'']?\s*:\s*false\b') {
            $patchStatus = 'ConflictingLearningOverride'
            Write-Warning '[DM-LEARNING-PATCH-OVERRIDE] Existing patch disables native phrase learning; retained without modification. Functional acceptance is NOT successful.'
        }
    }
    return [pscustomobject]@{Source=$source;Target=$target;Before=$before;Successor=$contract.successor_sha256;Action=$action;PatchStatus=$patchStatus}
}

function Assert-DaMaoSchemaUpgradeUnchanged {
    param($Plan)
    foreach ($path in @($Plan.Source, $Plan.Target)) { Assert-DaMaoSchemaPlainPath $path }
    if (-not (Test-Path -LiteralPath $Plan.Source -PathType Leaf) -or
        (Get-FileHash -LiteralPath $Plan.Source -Algorithm SHA256).Hash -cne $Plan.Successor) {
        throw '[DM-RESOURCE-CONFLICT] Official schema source changed after preflight.'
    }
    $now = 'ABSENT'
    if (Test-Path -LiteralPath $Plan.Target) {
        if (-not (Test-Path -LiteralPath $Plan.Target -PathType Leaf)) { throw '[DM-RESOURCE-CONFLICT] Target type changed.' }
        $now = (Get-FileHash -LiteralPath $Plan.Target -Algorithm SHA256).Hash
    }
    if ($now -cne $Plan.Before) { throw '[DM-RESOURCE-CONFLICT] Target changed after preflight; no upgrade authorized.' }
}

function Get-DaMaoEffectiveLearningStatus {
    param([Parameter(Mandatory=$true)][string]$RimeUserDir)
    $path = Join-Path $RimeUserDir 'build/damao_wubi.schema.yaml'
    Assert-DaMaoSchemaPlainPath $path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw '[DM-LEARNING-EFFECTIVE-MISSING] Compiled formal schema is absent.' }
    $section = ''; $values = @{}
    foreach ($line in ([IO.File]::ReadAllText($path) -split '\r?\n')) {
        if ($line -cmatch '^([a-z_]+):\s*$') { $section = $Matches[1] }
        elseif ($line -cmatch '^  ([a-z_]+):\s*(.*?)\s*$') {
            $key = $section + '/' + $Matches[1]
            if ($values.ContainsKey($key)) { throw '[DM-LEARNING-EFFECTIVE-INVALID] Ambiguous compiled scalar.' }
            $values[$key] = $Matches[2].Trim('"', "'")
        }
    }
    $identity = $values['schema/schema_id'] -ceq 'damao_wubi' -and
        $values['translator/user_dict'] -ceq 'damao_wubi' -and $values['translator/dictionary'] -ceq 'wubi86'
    $enabled = $identity -and $values['translator/enable_user_dict'] -ceq 'true' -and
        $values['translator/enable_encoder'] -ceq 'true' -and $values['translator/encode_commit_history'] -ceq 'true' -and
        $values['translator/max_phrase_length'] -ceq '4'
    $status = 'EffectiveNativeLearningEnabled'
    if (-not $enabled) {
        $patchPath = Join-Path $RimeUserDir 'damao_wubi.custom.yaml'
        if ($identity -and (Test-Path -LiteralPath $patchPath -PathType Leaf) -and
            ($values['translator/enable_encoder'] -ceq 'false' -or $values['translator/encode_commit_history'] -ceq 'false')) {
            $status = 'InstalledPreservedAutoPhraseDisabledByUserPatch'
            Write-Warning '[DM-LEARNING-DISABLED-BY-USER-PATCH] Installed/preserved, but compiled formal configuration disables auto-phrase. User patch was retained; DEV4 functional acceptance is NOT successful.'
        }
        else { throw '[DM-LEARNING-EFFECTIVE-MISMATCH] Compiled schema does not match the DEV4 learning/identity contract.' }
    }
    [pscustomobject]@{Status=$status;CapabilityEnabled=[bool]$enabled;SchemaId=$values['schema/schema_id'];UserDict=$values['translator/user_dict'];Dictionary=$values['translator/dictionary'];EnableEncoder=$values['translator/enable_encoder'];EncodeCommitHistory=$values['translator/encode_commit_history'];MaxPhraseLength=$values['translator/max_phrase_length'];CompiledPath=$path}
}
