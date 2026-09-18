Set-StrictMode -Version Latest

function Get-DaMaoPublicBaseline {
    param([Parameter(Mandatory = $true)][string]$RepositoryRoot)

    $baselinePath = Join-Path $RepositoryRoot 'contracts\public-baseline-v1.json'
    if (-not (Test-Path -LiteralPath $baselinePath -PathType Leaf)) {
        throw '[DAMAO-PUBLIC-BASELINE-INVALID] Public Baseline V1 manifest is missing.'
    }

    $baseline = Get-Content -LiteralPath $baselinePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $failures = New-Object 'System.Collections.Generic.List[string]'
    if ($baseline.format_version -ne 1 -or $baseline.contract_version -ne 1 -or
        [string]$baseline.contract_id -cne 'bigcat-wubi-public-baseline-v1' -or
        [string]$baseline.status -cne 'Public Baseline V1') {
        $failures.Add('unexpected public baseline identity, version, or status')
    }
    if ([string]$baseline.revision_policy -cne
        'Any change to a pinned file requires an explicit reviewed update to this manifest and the public baseline tests.') {
        $failures.Add('public baseline revision policy changed')
    }

    $dimensionNames = @($baseline.identity_dimensions | ForEach-Object { [string]$_.field })
    if ($dimensionNames.Count -ne 3 -or
        @($dimensionNames | Select-Object -Unique).Count -ne 3 -or
        $dimensionNames -cnotcontains 'logical_role' -or
        $dimensionNames -cnotcontains 'schema_id' -or
        $dimensionNames -cnotcontains 'db_name') {
        $failures.Add('identity dimensions changed')
    }

    $pureWubiRoles = @($baseline.identity_contract.logical_roles | Where-Object {
            [string]$_.logical_role -ceq 'PureWubi'
        })
    if ($pureWubiRoles.Count -ne 1) {
        $failures.Add('PureWubi role is missing or duplicated')
    }
    else {
        $role = $pureWubiRoles[0]
        $identities = @($role.physical_identities)
        $current = @($identities | Where-Object {
                [string]$_.identity_id -ceq 'purewubi.alpha03' -and
                [string]$_.schema_id -ceq 'damao_wubi_alpha03' -and
                [string]$_.db_name -ceq 'damao_wubi_alpha03' -and
                [string]$_.lifecycle -ceq 'current'
            })
        $legacy = @($identities | Where-Object {
                [string]$_.identity_id -ceq 'purewubi.legacy' -and
                [string]$_.schema_id -ceq 'damao_wubi' -and
                [string]$_.db_name -ceq 'damao_wubi' -and
                [string]$_.lifecycle -ceq 'legacy'
            })
        if ($identities.Count -ne 2 -or $current.Count -ne 1 -or $legacy.Count -ne 1 -or
            [string]$role.coexistence_policy -cne 'preserve_separate' -or
            [bool]$role.automatic_merge -or [bool]$role.automatic_rename) {
            $failures.Add('PureWubi physical identity separation changed')
        }
    }

    $pinyinExclusions = @($baseline.identity_contract.default_exclusions | Where-Object {
            [string]$_.schema_id -ceq 'damao_wubi_pinyin' -and
            [string]$_.db_name -ceq 'damao_wubi_pinyin' -and
            [bool]$_.future_explicit_logical_role_required
        })
    if ($pinyinExclusions.Count -ne 1 -or
        [string]$baseline.identity_contract.unknown_db_policy -cne 'reject_unclassified' -or
        @($baseline.identity_contract.migration_rules).Count -ne 0) {
        $failures.Add('exclusion, unknown database, or migration policy changed')
    }

    $requiredInvariants = @(
        'PureWubi physical identities remain separate',
        'No automatic merge or rename',
        'Pinyin remains excluded unless explicitly classified',
        'No automatic migration',
        'Strict snapshot parsing',
        'Package V2 backup semantics',
        'Restore authorization and preflight before mutation',
        'Safety backup before destructive restore',
        'Native ABI and version validation',
        'Privacy-preserving output and failure handling',
        'Malformed or ambiguous UserDB input is rejected'
    )
    $actualInvariants = @($baseline.semantic_invariants | ForEach-Object { [string]$_ })
    if ($actualInvariants.Count -ne $requiredInvariants.Count -or
        ($actualInvariants -join "`n") -cne ($requiredInvariants -join "`n")) {
        $failures.Add('public portability invariant set changed')
    }

    $files = @($baseline.current_file_integrity.files)
    $paths = @($files | ForEach-Object { [string]$_.path })
    if ([string]$baseline.current_file_integrity.hash_algorithm -cne 'SHA-256' -or
        [string]$baseline.current_file_integrity.path_basis -cne 'repository-relative' -or
        $files.Count -ne 17 -or @($paths | Select-Object -Unique).Count -ne 17) {
        $failures.Add('public baseline file manifest shape changed')
    }
    foreach ($entry in $files) {
        $path = [string]$entry.path
        if ([System.IO.Path]::IsPathRooted($path) -or
            $path -match '(^|[\/])\.\.([\/]|$)') {
            $failures.Add("unsafe public baseline path: $path")
        }
        if ([string]$entry.sha256 -cnotmatch '^[0-9A-F]{64}$') {
            $failures.Add("invalid SHA-256 pin: $path")
        }
    }

    if ($failures.Count -gt 0) {
        throw "[DAMAO-PUBLIC-BASELINE-INVALID] $($failures -join '; ')"
    }
    return $baseline
}

function Test-DaMaoPublicBaselineManifest {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][object[]]$Files
    )

    $failures = New-Object 'System.Collections.Generic.List[string]'
    foreach ($entry in $Files) {
        $relativePath = [string]$entry.path
        $fullPath = Join-Path $RepositoryRoot $relativePath.Replace(
            '/', [System.IO.Path]::DirectorySeparatorChar
        )
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            $failures.Add("missing: $relativePath")
        }
        elseif ((Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash -cne
            [string]$entry.sha256) {
            $failures.Add("hash mismatch: $relativePath")
        }
    }
    return @($failures)
}
