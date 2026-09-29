Set-StrictMode -Version Latest

function Resolve-AcceptancePath {
    param([string]$Root, [string]$Relative)
    if ($Relative -cnotmatch '^[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*$' -or
        @($Relative.Split('/') | Where-Object { $_ -in @('.', '..') -or $_.EndsWith('.') }).Count) {
        throw '[DM-ACCEPTANCE-PATH] Non-canonical or escaping path.'
    }
    $full = [IO.Path]::GetFullPath((Join-Path $Root $Relative))
    $item = $full
    while ($item) {
        if (Test-Path -LiteralPath $item) {
            if ((Get-Item -LiteralPath $item -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw '[DM-ACCEPTANCE-PATH] Reparse points are not accepted.'
            }
        }
        $item = Split-Path -Parent $item
    }
    return $full
}

function Get-AcceptanceByteHash {
    param([byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-', '') }
    finally { $sha.Dispose() }
}

function Read-AcceptancePin {
    param([string]$Root, $Pin)
    if ([string]$Pin.sha256 -cnotmatch '^[0-9A-F]{64}$') { throw '[DM-ACCEPTANCE-HASH] Invalid digest.' }
    $path = Resolve-AcceptancePath $Root ([string]$Pin.path)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "[DM-ACCEPTANCE-MISSING] $($Pin.path)" }
    $bytes = [IO.File]::ReadAllBytes($path)
    if ((Get-AcceptanceByteHash $bytes) -cne $Pin.sha256) { throw "[DM-ACCEPTANCE-HASH] $($Pin.path)" }
    return ,$bytes
}

function Assert-AcceptanceUniquePaths {
    param([string]$Root, [object[]]$Entries)
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $Entries) {
        [void](Resolve-AcceptancePath $Root ([string]$entry.path))
        if (-not $seen.Add([string]$entry.path)) { throw '[DM-ACCEPTANCE-DUPLICATE] Duplicate path.' }
    }
}

function Read-AcceptanceSnapshot {
    param([string]$Root, $Pin)
    $bytes = Read-AcceptancePin $Root $Pin
    Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
    $stream = [IO.MemoryStream]::new($bytes, $false)
    $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Read)
    $files = @{}
    try {
        foreach ($entry in $zip.Entries) {
            if ($entry.FullName.EndsWith('/')) { continue }
            [void](Resolve-AcceptancePath $Root $entry.FullName)
            if ($files.ContainsKey($entry.FullName)) { throw '[DM-ACCEPTANCE-DUPLICATE] Duplicate snapshot path.' }
            $inputStream = $entry.Open(); $memory = [IO.MemoryStream]::new()
            try { $inputStream.CopyTo($memory); $files[$entry.FullName] = $memory.ToArray() }
            finally { $inputStream.Dispose(); $memory.Dispose() }
        }
    }
    finally { $zip.Dispose(); $stream.Dispose() }
    return $files
}

function Get-AcceptanceRecipe {
    param([string]$Path)
    if ($Path -ceq 'schemas/damao_wubi.schema.yaml') {
        return @([pscustomobject]@{
            before="  enable_encoder: false`n  encode_commit_history: false`n"
            after="  enable_encoder: true`n  encode_commit_history: true`n  max_phrase_length: 4`n"
        })
    }
    if ($Path -cmatch '^tests/Test-DaMaoUserDbPortabilityP[0-3]\.ps1$') {
        $recipe = @(
            [pscustomobject]@{before='DaMao.PortabilityBaseline.ps1';after='DaMao.SuccessorBaseline.ps1'},
            [pscustomobject]@{before='Get-DaMaoPublicBaseline';after='Get-DaMaoAcceptanceBaseline'}
        )
        if ($Path -ceq 'tests/Test-DaMaoUserDbPortabilityP2.ps1') {
            # Historical CI step assertions are business coverage, not display wiring.
            $recipe += [pscustomobject]@{before='Public Baseline V1 failed:';after='Public Baseline V2 failed:'}
            $recipe += [pscustomobject]@{before='Public Baseline V1 changed during P2 tests.';after='Public Baseline V2 changed during P2 tests.'}
        }
        else { $recipe += [pscustomobject]@{before='Public Baseline V1';after='Public Baseline V2'} }
        return $recipe
    }
    throw '[DM-ACCEPTANCE-TRANSITION] Path is not an authorized DEV4 transition.'
}

function Assert-AcceptanceSchemaStructure {
    param([string]$Text)
    # Parse the bounded scalar mappings in the byte-locked schema. This is not a
    # general YAML evaluator; exact predecessor transformation excludes other YAML.
    $section = ''; $values = @{}
    foreach ($line in ($Text -split "`n")) {
        if ($line -cmatch '^([a-z_]+):\s*$') { $section = $Matches[1] }
        elseif ($line -cmatch '^  ([a-z_]+): (.+)$') {
            $key = $section + '/' + $Matches[1]
            if ($values.ContainsKey($key)) { throw '[DM-ACCEPTANCE-SCHEMA] Duplicate scalar.' }
            $values[$key] = $Matches[2].Trim()
        }
    }
    $expected = @{
        'schema/schema_id'='damao_wubi'; 'translator/user_dict'='damao_wubi'
        'translator/dictionary'='wubi86'; 'translator/enable_user_dict'='true'
        'translator/enable_encoder'='true'; 'translator/encode_commit_history'='true'
        'translator/max_phrase_length'='4'; 'translator/enable_sentence'='false'
    }
    foreach ($key in $expected.Keys) {
        if ($values[$key] -cne $expected[$key]) { throw "[DM-ACCEPTANCE-SCHEMA] $key" }
    }
}

function Assert-DaMaoAcceptance {
    param([Parameter(Mandatory=$true)][string]$RepositoryRoot)
    $lockPath = Resolve-AcceptancePath $RepositoryRoot 'contracts/acceptance.lock.json'
    if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) { throw '[DM-ACCEPTANCE-LOCK] Missing explicit lock; no fallback.' }
    $lock = [IO.File]::ReadAllText($lockPath) | ConvertFrom-Json
    if ($lock.format_version -ne 1 -or $lock.current_baseline -cne 'bigcat-wubi-public-baseline-v2') {
        throw '[DM-ACCEPTANCE-LOCK] Unknown baseline.'
    }
    $locations = @{
        manifest='contracts/public-baseline-v2.json'; transition='contracts/dev4-transition.json'
        predecessor='contracts/public-baseline-v1.json'; evidence='tests/fixtures/public-baseline-v1/source.zip'
        verifier='tests/DaMao.AcceptancePreflight.ps1'; loader='tests/DaMao.SuccessorBaseline.ps1'
    }
    $contents = @{}
    foreach ($name in $locations.Keys) {
        $pin = $lock.$name
        [void](Resolve-AcceptancePath $RepositoryRoot ([string]$pin.path))
        if ($pin.path -cne $locations[$name]) { throw '[DM-ACCEPTANCE-LOCK] Unexpected artifact path.' }
        $contents[$name] = Read-AcceptancePin $RepositoryRoot $pin
    }
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    $v1 = $utf8.GetString($contents.predecessor) | ConvertFrom-Json
    $v2 = $utf8.GetString($contents.manifest) | ConvertFrom-Json
    $transition = $utf8.GetString($contents.transition) | ConvertFrom-Json
    if ($v2.format_version -ne 1 -or $v2.contract_id -cne $lock.current_baseline -or
        $v2.identity_authority -cne 'contracts/public-baseline-v1.json' -or
        $transition.format_version -ne 1 -or $transition.contract_id -cne 'bigcat-wubi-dev4-exact-transition' -or
        $v2.predecessor_sha256 -cne $lock.predecessor.sha256 -or
        $transition.predecessor_sha256 -cne $lock.predecessor.sha256 -or
        $transition.predecessor_commit -cne '97d0d659bbe808d11c0eefa3114ea929e0151e7f') {
        throw '[DM-ACCEPTANCE-TRANSITION] Invalid predecessor chain.'
    }
    $current = @($v2.current_file_integrity.files)
    $support = @($v2.support_file_integrity.files)
    if ($v2.current_file_integrity.hash_algorithm -cne 'SHA-256' -or
        $v2.support_file_integrity.hash_algorithm -cne 'SHA-256' -or
        $v2.current_file_integrity.path_basis -cne 'repository-relative' -or $current.Count -ne 17 -or
        $support.Count -eq 0) { throw '[DM-ACCEPTANCE-MANIFEST] Invalid protected sets.' }
    Assert-AcceptanceUniquePaths $RepositoryRoot ($current + $support)
    foreach ($entry in ($current + $support)) { [void](Read-AcceptancePin $RepositoryRoot $entry) }
    $history = Read-AcceptanceSnapshot $RepositoryRoot $lock.evidence
    $closure = @($v2.historical_closure)
    Assert-AcceptanceUniquePaths $RepositoryRoot $closure
    if ($history.Count -ne $closure.Count) { throw '[DM-ACCEPTANCE-HISTORY] Unexpected snapshot closure.' }
    foreach ($entry in $closure) {
        if (-not $history.ContainsKey($entry.path) -or (Get-AcceptanceByteHash $history[$entry.path]) -cne $entry.sha256) {
            throw '[DM-ACCEPTANCE-HISTORY] Snapshot member digest mismatch.'
        }
    }
    if ((Get-AcceptanceByteHash $history['contracts/public-baseline-v1.json']) -cne $lock.predecessor.sha256) {
        throw '[DM-ACCEPTANCE-HISTORY] Historical V1 manifest changed.'
    }
    $changes = @($transition.changes)
    Assert-AcceptanceUniquePaths $RepositoryRoot $changes
    if ($changes.Count -ne 5) { throw '[DM-ACCEPTANCE-TRANSITION] Exactly five frozen paths may evolve.' }
    $unchanged = 0
    foreach ($old in $v1.current_file_integrity.files) {
        $new = @($current | Where-Object { $_.path -ceq $old.path })
        if ($new.Count -ne 1 -or (Get-AcceptanceByteHash $history[$old.path]) -cne $old.sha256) {
            throw '[DM-ACCEPTANCE-TRANSITION] V1 path set or raw bytes changed.'
        }
        $change = @($changes | Where-Object { $_.path -ceq $old.path })
        if ($change.Count -eq 0) {
            if ($new[0].sha256 -cne $old.sha256) { throw '[DM-ACCEPTANCE-TRANSITION] Unauthorized frozen drift.' }
            $unchanged++; continue
        }
        $change = $change[0]
        if ($change.before_sha256 -cne $old.sha256 -or $change.after_sha256 -cne $new[0].sha256) {
            throw '[DM-ACCEPTANCE-TRANSITION] Before/after pin mismatch.'
        }
        $recipe = @(Get-AcceptanceRecipe $old.path)
        if (($recipe | ConvertTo-Json -Depth 8 -Compress) -cne ($change.replacements | ConvertTo-Json -Depth 8 -Compress)) {
            throw '[DM-ACCEPTANCE-TRANSITION] Patch exceeds fixed DEV4 recipe.'
        }
        $expected = $utf8.GetString($history[$old.path])
        foreach ($operation in $recipe) {
            if (-not $expected.Contains($operation.before)) { throw '[DM-ACCEPTANCE-TRANSITION] Patch context missing.' }
            $expected = $expected.Replace($operation.before, $operation.after)
        }
        if ((Get-AcceptanceByteHash $utf8.GetBytes($expected)) -cne $new[0].sha256) {
            throw '[DM-ACCEPTANCE-TRANSITION] Bytes outside authorized wiring/schema delta changed.'
        }
        if ($old.path -ceq 'schemas/damao_wubi.schema.yaml') { Assert-AcceptanceSchemaStructure $expected }
    }
    if ($unchanged -ne 12) { throw '[DM-ACCEPTANCE-TRANSITION] Twelve frozen inputs must remain identical.' }
    return [pscustomobject]@{Manifest=$v2;Lock=$lock;History=$history;Unchanged=$unchanged;Changed=5;Support=$support.Count}
}
