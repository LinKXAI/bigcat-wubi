$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:DaMaoP1KnownErrorCodes = @(
    'P1_BLOCKED_INPUT_CORE_DRIFT',
    'RIME_USER_DIR_NOT_FOUND',
    'INSTALLATION_YAML_NOT_FOUND',
    'INSTALLATION_YAML_INVALID',
    'INSTALLATION_ID_MISSING',
    'INSTALLATION_ID_INVALID',
    'SYNC_DIR_INVALID',
    'SYNC_DIR_NOT_FOUND',
    'SYNC_DIR_NOT_READABLE',
    'LIBRIME_NOT_DETECTED',
    'LIBRIME_VERSION_UNVERIFIED',
    'WEASEL_NOT_DETECTED',
    'SNAPSHOT_NOT_FOUND',
    'SNAPSHOT_INVALID_UTF8',
    'SNAPSHOT_HEADER_INVALID',
    'SNAPSHOT_DB_TYPE_INVALID',
    'SNAPSHOT_DB_NAME_INVALID',
    'SNAPSHOT_FILENAME_DB_NAME_MISMATCH',
    'SNAPSHOT_ENTRY_INVALID',
    'SNAPSHOT_NUMERIC_FIELD_INVALID',
    'SNAPSHOT_DUPLICATE_KEY',
    'SNAPSHOT_TRUNCATED',
    'USERDB_ARTIFACT_AMBIGUOUS',
    'USERDB_IDENTITY_UNCLASSIFIED'
)

function Get-DaMaoUserDbP1ErrorCodes {
    return @($script:DaMaoP1KnownErrorCodes)
}

function Get-DaMaoUtf8Validation {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    $index = 0
    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and
        $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) {
        $index = 3
    }

    while ($index -lt $Bytes.Length) {
        $first = [int]$Bytes[$index]
        if ($first -le 0x7F) {
            $index++
            continue
        }

        if ($first -ge 0xC2 -and $first -le 0xDF) {
            $continuations = 1
        }
        elseif ($first -ge 0xE0 -and $first -le 0xEF) {
            $continuations = 2
        }
        elseif ($first -ge 0xF0 -and $first -le 0xF4) {
            $continuations = 3
        }
        else {
            return 'Invalid'
        }

        if ($index + $continuations -ge $Bytes.Length) {
            return 'Truncated'
        }

        for ($offset = 1; $offset -le $continuations; $offset++) {
            $next = [int]$Bytes[$index + $offset]
            if ($next -lt 0x80 -or $next -gt 0xBF) {
                return 'Invalid'
            }
        }

        if ($continuations -eq 2) {
            $second = [int]$Bytes[$index + 1]
            if (($first -eq 0xE0 -and $second -lt 0xA0) -or
                ($first -eq 0xED -and $second -gt 0x9F)) {
                return 'Invalid'
            }
        }
        elseif ($continuations -eq 3) {
            $second = [int]$Bytes[$index + 1]
            if (($first -eq 0xF0 -and $second -lt 0x90) -or
                ($first -eq 0xF4 -and $second -gt 0x8F)) {
                return 'Invalid'
            }
        }

        $index += $continuations + 1
    }

    return 'Valid'
}

function New-DaMaoSnapshotResult {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [pscustomobject][ordered]@{
        Path = $Path
        ByteLength = [long]0
        Sha256 = $null
        Encoding = $null
        DbName = $null
        DbType = $null
        RimeVersion = $null
        Tick = $null
        UserId = $null
        UnknownHeaderFields = @()
        EntryCount = 0
        TombstoneCount = 0
        DuplicateKeyCount = 0
        MinTick = $null
        MaxTick = $null
        StructuralHealth = 'Invalid'
        ErrorCode = $null
        ErrorLine = $null
    }
}

function Set-DaMaoSnapshotError {
    param(
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)][string]$ErrorCode,
        [AllowNull()][Nullable[int]]$ErrorLine
    )

    $Result.StructuralHealth = 'Invalid'
    $Result.ErrorCode = $ErrorCode
    $Result.ErrorLine = $ErrorLine
    return $Result
}

function Test-DaMaoDbName {
    param([AllowNull()][string]$DbName)

    if ([string]::IsNullOrWhiteSpace($DbName) -or $DbName -eq '.' -or $DbName -eq '..') {
        return $false
    }
    if ($DbName.IndexOfAny(@([char]'/', [char]'\', [char]0)) -ge 0) {
        return $false
    }
    foreach ($character in $DbName.ToCharArray()) {
        if ([char]::IsControl($character)) {
            return $false
        }
    }
    return $true
}

function Test-DaMaoEntryField {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value
    )

    if ($Value.Length -eq 0) {
        return $false
    }
    foreach ($character in $Value.ToCharArray()) {
        if ([char]::IsControl($character)) {
            return $false
        }
    }
    return $true
}

function Read-DaMaoUserDbSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$IncludeEntries
    )

    try {
        $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    }
    catch {
        $resolvedPath = $Path
    }
    $result = New-DaMaoSnapshotResult -Path $resolvedPath

    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
        return Set-DaMaoSnapshotError -Result $result -ErrorCode 'SNAPSHOT_NOT_FOUND'
    }

    try {
        [byte[]]$bytes = [System.IO.File]::ReadAllBytes($resolvedPath)
        $result.ByteLength = [long]$bytes.Length
        $result.Sha256 = (Get-FileHash -LiteralPath $resolvedPath -Algorithm SHA256).Hash
    }
    catch {
        return Set-DaMaoSnapshotError -Result $result -ErrorCode 'SNAPSHOT_NOT_FOUND'
    }

    $utf8Health = Get-DaMaoUtf8Validation -Bytes $bytes
    if ($utf8Health -ne 'Valid') {
        return Set-DaMaoSnapshotError -Result $result -ErrorCode 'SNAPSHOT_INVALID_UTF8'
    }

    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and
        $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $result.Encoding = if ($hasBom) { 'UTF-8-BOM' } else { 'UTF-8' }
    $offset = if ($hasBom) { 3 } else { 0 }
    try {
        $strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
        $text = $strictUtf8.GetString($bytes, $offset, $bytes.Length - $offset)
    }
    catch {
        return Set-DaMaoSnapshotError -Result $result -ErrorCode 'SNAPSHOT_INVALID_UTF8'
    }

    $nulIndex = $text.IndexOf([char]0)
    if ($nulIndex -ge 0) {
        $nulLine = 1 + ([regex]::Matches($text.Substring(0, $nulIndex), "`n")).Count
        return Set-DaMaoSnapshotError -Result $result -ErrorCode 'SNAPSHOT_ENTRY_INVALID' `
            -ErrorLine $nulLine
    }
    $bareCr = [regex]::Match($text, "`r(?!`n)")
    if ($bareCr.Success) {
        $bareCrLine = 1 + ([regex]::Matches($text.Substring(0, $bareCr.Index), "`n")).Count
        return Set-DaMaoSnapshotError -Result $result -ErrorCode 'SNAPSHOT_ENTRY_INVALID' `
            -ErrorLine $bareCrLine
    }

    $lines = [regex]::Split($text, "`r?`n")
    if ($lines.Count -eq 0 -or $lines[0] -cne '# Rime user dictionary') {
        return Set-DaMaoSnapshotError -Result $result -ErrorCode 'SNAPSHOT_HEADER_INVALID' `
            -ErrorLine 1
    }

    $metadata = @{}
    $knownMetadata = @('/db_name', '/db_type', '/rime_version', '/tick', '/user_id')
    $unknownMetadata = New-Object 'System.Collections.Generic.List[string]'
    $rawEntries = New-Object 'System.Collections.Generic.List[object]'
    $commentsEnabled = $true

    for ($index = 1; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        $lineNumber = $index + 1
        if ($line.Length -eq 0) {
            continue
        }
        if ($commentsEnabled -and $line[0] -eq '#') {
            if ($line.StartsWith('#@', [System.StringComparison]::Ordinal)) {
                $parts = [regex]::Split($line.Substring(2), "`t")
                if ($parts.Count -ne 2 -or [string]::IsNullOrEmpty($parts[0])) {
                    return Set-DaMaoSnapshotError -Result $result `
                        -ErrorCode 'SNAPSHOT_HEADER_INVALID' -ErrorLine $lineNumber
                }
                $metadataKey = [string]$parts[0]
                if ($metadata.ContainsKey($metadataKey) -and $knownMetadata -ccontains $metadataKey) {
                    return Set-DaMaoSnapshotError -Result $result `
                        -ErrorCode 'SNAPSHOT_HEADER_INVALID' -ErrorLine $lineNumber
                }
                $metadata[$metadataKey] = [string]$parts[1]
                if ($knownMetadata -cnotcontains $metadataKey -and
                    $unknownMetadata -cnotcontains $metadataKey) {
                    $unknownMetadata.Add($metadataKey)
                }
            }
            elseif ($line -ceq '# no comment') {
                $commentsEnabled = $false
            }
            continue
        }

        $columns = [regex]::Split($line, "`t")
        $rawEntries.Add([pscustomobject]@{
                Line = $lineNumber
                Columns = @($columns)
                IsTerminalUnterminated = (
                    $index -eq $lines.Count - 1 -and -not $text.EndsWith("`n")
                )
            })
    }

    $result.UnknownHeaderFields = $unknownMetadata.ToArray()
    if (-not $metadata.ContainsKey('/db_name')) {
        return Set-DaMaoSnapshotError -Result $result -ErrorCode 'SNAPSHOT_DB_NAME_INVALID'
    }
    $result.DbName = [string]$metadata['/db_name']
    if (-not (Test-DaMaoDbName -DbName $result.DbName)) {
        return Set-DaMaoSnapshotError -Result $result -ErrorCode 'SNAPSHOT_DB_NAME_INVALID'
    }
    if (-not $metadata.ContainsKey('/db_type')) {
        return Set-DaMaoSnapshotError -Result $result -ErrorCode 'SNAPSHOT_HEADER_INVALID'
    }
    $result.DbType = [string]$metadata['/db_type']
    if ($result.DbType -cne 'userdb') {
        return Set-DaMaoSnapshotError -Result $result -ErrorCode 'SNAPSHOT_DB_TYPE_INVALID'
    }

    if ($metadata.ContainsKey('/rime_version')) {
        $result.RimeVersion = [string]$metadata['/rime_version']
    }
    if ($metadata.ContainsKey('/user_id')) {
        $result.UserId = [string]$metadata['/user_id']
    }
    if ($metadata.ContainsKey('/tick')) {
        $headerTickText = [string]$metadata['/tick']
        [uint64]$headerTick = 0
        if ($headerTickText -notmatch '^[0-9]+$' -or
            -not [uint64]::TryParse($headerTickText,
                [System.Globalization.NumberStyles]::None,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [ref]$headerTick)) {
            return Set-DaMaoSnapshotError -Result $result `
                -ErrorCode 'SNAPSHOT_NUMERIC_FIELD_INVALID'
        }
        $result.Tick = $headerTick
    }

    $expectedFileName = $result.DbName + '.userdb.txt'
    $actualFileName = [System.IO.Path]::GetFileName($resolvedPath)
    if (-not [string]::Equals($actualFileName, $expectedFileName,
            [System.StringComparison]::Ordinal)) {
        return Set-DaMaoSnapshotError -Result $result `
            -ErrorCode 'SNAPSHOT_FILENAME_DB_NAME_MISMATCH'
    }

    $entries = New-Object 'System.Collections.Generic.List[object]'
    $logicalKeys = [System.Collections.Generic.Dictionary[string, int]]::new(
        [System.StringComparer]::Ordinal
    )
    $duplicateCount = 0
    $firstDuplicateLine = $null
    $tombstoneCount = 0
    $minTick = $null
    $maxTick = $null
    $valuePattern = '^c=([+-]?[0-9]+) d=([+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?) t=([0-9]+)$'

    foreach ($rawEntry in $rawEntries) {
        $columns = @($rawEntry.Columns)
        $lineNumber = [int]$rawEntry.Line
        if ($columns.Count -ne 3) {
            $entryErrorCode = if ($rawEntry.IsTerminalUnterminated) {
                'SNAPSHOT_TRUNCATED'
            }
            else {
                'SNAPSHOT_ENTRY_INVALID'
            }
            return Set-DaMaoSnapshotError -Result $result `
                -ErrorCode $entryErrorCode -ErrorLine $lineNumber
        }
        $code = [string]$columns[0]
        $phrase = [string]$columns[1]
        if (-not (Test-DaMaoEntryField -Value $code) -or
            -not (Test-DaMaoEntryField -Value $phrase)) {
            return Set-DaMaoSnapshotError -Result $result `
                -ErrorCode 'SNAPSHOT_ENTRY_INVALID' -ErrorLine $lineNumber
        }

        $valueMatch = [regex]::Match([string]$columns[2], $valuePattern,
            [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
        if (-not $valueMatch.Success) {
            return Set-DaMaoSnapshotError -Result $result `
                -ErrorCode 'SNAPSHOT_NUMERIC_FIELD_INVALID' -ErrorLine $lineNumber
        }

        [int]$commits = 0
        if (-not [int]::TryParse($valueMatch.Groups[1].Value,
                [System.Globalization.NumberStyles]::AllowLeadingSign,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [ref]$commits)) {
            return Set-DaMaoSnapshotError -Result $result `
                -ErrorCode 'SNAPSHOT_NUMERIC_FIELD_INVALID' -ErrorLine $lineNumber
        }
        [double]$dee = 0.0
        if (-not [double]::TryParse($valueMatch.Groups[2].Value,
                [System.Globalization.NumberStyles]::Float,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [ref]$dee) -or [double]::IsNaN($dee) -or
            [double]::IsInfinity($dee) -or $dee -lt 0.0) {
            return Set-DaMaoSnapshotError -Result $result `
                -ErrorCode 'SNAPSHOT_NUMERIC_FIELD_INVALID' -ErrorLine $lineNumber
        }
        $dee = [math]::Min(10000.0, $dee)

        [uint64]$entryTick = 0
        if (-not [uint64]::TryParse($valueMatch.Groups[3].Value,
                [System.Globalization.NumberStyles]::None,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [ref]$entryTick)) {
            return Set-DaMaoSnapshotError -Result $result `
                -ErrorCode 'SNAPSHOT_NUMERIC_FIELD_INVALID' -ErrorLine $lineNumber
        }

        $canonicalCode = if ($code.EndsWith(' ', [System.StringComparison]::Ordinal)) {
            $code
        }
        else {
            $code + ' '
        }
        $logicalKey = $canonicalCode + "`t" + $phrase
        if ($logicalKeys.ContainsKey($logicalKey)) {
            $duplicateCount++
            if ($null -eq $firstDuplicateLine) {
                $firstDuplicateLine = $lineNumber
            }
        }
        else {
            $logicalKeys.Add($logicalKey, $lineNumber)
        }

        if ($commits -lt 0) {
            $tombstoneCount++
        }
        if ($null -eq $minTick -or $entryTick -lt $minTick) {
            $minTick = $entryTick
        }
        if ($null -eq $maxTick -or $entryTick -gt $maxTick) {
            $maxTick = $entryTick
        }
        $entries.Add([pscustomobject][ordered]@{
                Key = $logicalKey
                Code = $canonicalCode
                Phrase = $phrase
                C = $commits
                D = $dee
                T = $entryTick
                IsTombstone = ($commits -lt 0)
                Line = $lineNumber
            })
    }

    $result.EntryCount = $entries.Count
    $result.TombstoneCount = $tombstoneCount
    $result.DuplicateKeyCount = $duplicateCount
    $result.MinTick = $minTick
    $result.MaxTick = $maxTick
    if ($duplicateCount -gt 0) {
        return Set-DaMaoSnapshotError -Result $result `
            -ErrorCode 'SNAPSHOT_DUPLICATE_KEY' -ErrorLine $firstDuplicateLine
    }

    $result.StructuralHealth = 'Healthy'
    if ($IncludeEntries) {
        $result | Add-Member -MemberType NoteProperty -Name Entries `
            -Value $entries.ToArray()
    }
    return $result
}

function Remove-DaMaoYamlComment {
    param([Parameter(Mandatory = $true)][string]$Value)

    $singleQuoted = $false
    $doubleQuoted = $false
    for ($index = 0; $index -lt $Value.Length; $index++) {
        $character = $Value[$index]
        if ($character -eq "'" -and -not $doubleQuoted) {
            if ($singleQuoted -and $index + 1 -lt $Value.Length -and
                $Value[$index + 1] -eq "'") {
                $index++
                continue
            }
            $singleQuoted = -not $singleQuoted
        }
        elseif ($character -eq '"' -and -not $singleQuoted) {
            $escaped = $index -gt 0 -and $Value[$index - 1] -eq '\'
            if (-not $escaped) {
                $doubleQuoted = -not $doubleQuoted
            }
        }
        elseif ($character -eq '#' -and -not $singleQuoted -and -not $doubleQuoted -and
            ($index -eq 0 -or [char]::IsWhiteSpace($Value[$index - 1]))) {
            return $Value.Substring(0, $index).TrimEnd()
        }
    }
    return $Value.TrimEnd()
}

function ConvertFrom-DaMaoYamlScalar {
    param([Parameter(Mandatory = $true)][string]$Text)

    $value = (Remove-DaMaoYamlComment -Value $Text).Trim()
    if ($value.Length -ge 2 -and $value[0] -eq "'" -and
        $value[$value.Length - 1] -eq "'") {
        return [pscustomobject]@{
            Success = $true
            Value = $value.Substring(1, $value.Length - 2).Replace("''", "'")
        }
    }
    if ($value.Length -ge 2 -and $value[0] -eq '"' -and
        $value[$value.Length - 1] -eq '"') {
        $body = $value.Substring(1, $value.Length - 2)
        $builder = New-Object System.Text.StringBuilder
        for ($index = 0; $index -lt $body.Length; $index++) {
            $character = $body[$index]
            if ($character -ne '\') {
                [void]$builder.Append($character)
                continue
            }
            if ($index + 1 -ge $body.Length) {
                return [pscustomobject]@{ Success = $false; Value = $null }
            }
            $index++
            $escaped = $body[$index]
            switch ($escaped) {
                '\' { [void]$builder.Append('\') }
                '"' { [void]$builder.Append('"') }
                'n' { [void]$builder.Append("`n") }
                'r' { [void]$builder.Append("`r") }
                't' { [void]$builder.Append("`t") }
                default { return [pscustomobject]@{ Success = $false; Value = $null } }
            }
        }
        return [pscustomobject]@{ Success = $true; Value = $builder.ToString() }
    }
    if ($value.StartsWith("'", [System.StringComparison]::Ordinal) -or
        $value.StartsWith('"', [System.StringComparison]::Ordinal)) {
        return [pscustomobject]@{ Success = $false; Value = $null }
    }
    return [pscustomobject]@{ Success = $true; Value = $value }
}

function Read-DaMaoInstallationMetadata {
    param([Parameter(Mandatory = $true)][string]$Path)

    $response = [pscustomobject][ordered]@{
        Path = $Path
        Found = $false
        Valid = $false
        Values = @{}
        DuplicateKeys = @()
        ErrorCode = $null
        ErrorLine = $null
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        $response.ErrorCode = 'INSTALLATION_YAML_NOT_FOUND'
        return $response
    }

    [byte[]]$bytes = [System.IO.File]::ReadAllBytes($Path)
    if ((Get-DaMaoUtf8Validation -Bytes $bytes) -ne 'Valid') {
        $response.Found = $true
        $response.ErrorCode = 'INSTALLATION_YAML_INVALID'
        return $response
    }
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and
        $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $offset = if ($hasBom) { 3 } else { 0 }
    $text = ([System.Text.UTF8Encoding]::new($false, $true)).GetString(
        $bytes, $offset, $bytes.Length - $offset
    )
    if ($text.IndexOf([char]0) -ge 0) {
        $response.Found = $true
        $response.ErrorCode = 'INSTALLATION_YAML_INVALID'
        return $response
    }

    $values = @{}
    $duplicates = New-Object 'System.Collections.Generic.List[string]'
    $lines = [regex]::Split($text, "`r?`n")
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) {
            continue
        }
        $match = [regex]::Match($line, '^([A-Za-z0-9_]+)\s*:\s*(.*)$')
        if (-not $match.Success) {
            continue
        }
        $key = $match.Groups[1].Value
        $scalar = ConvertFrom-DaMaoYamlScalar -Text $match.Groups[2].Value
        if (-not $scalar.Success) {
            $response.Found = $true
            $response.ErrorCode = 'INSTALLATION_YAML_INVALID'
            $response.ErrorLine = $index + 1
            return $response
        }
        if ($values.ContainsKey($key)) {
            $duplicates.Add($key)
        }
        $values[$key] = [string]$scalar.Value
    }
    $response.Found = $true
    $response.Valid = $true
    $response.Values = $values
    $response.DuplicateKeys = $duplicates.ToArray()
    return $response
}

function Get-DaMaoVersionAssessment {
    param(
        [AllowNull()][string]$Version,
        [Parameter(Mandatory = $true)][ValidateSet('Weasel', 'librime')][string]$Product
    )

    if ([string]::IsNullOrWhiteSpace($Version)) {
        return [pscustomobject]@{
            Version = $null
            Status = 'NotDetected'
            FormatVerified = $false
            ErrorCode = if ($Product -eq 'librime') { 'LIBRIME_NOT_DETECTED' } else { 'WEASEL_NOT_DETECTED' }
        }
    }
    $referenceText = if ($Product -eq 'librime') { '1.13.1' } else { '0.17.4' }
    [version]$parsed = New-Object version
    [version]$reference = [version]$referenceText
    if (-not [version]::TryParse($Version, [ref]$parsed)) {
        return [pscustomobject]@{
            Version = $Version
            Status = 'UnknownVersion'
            FormatVerified = $false
            ErrorCode = if ($Product -eq 'librime') { 'LIBRIME_VERSION_UNVERIFIED' } else { $null }
        }
    }
    if ($parsed -eq $reference) {
        return [pscustomobject]@{
            Version = $Version
            Status = 'Supported'
            FormatVerified = ($Product -eq 'librime')
            ErrorCode = $null
        }
    }
    return [pscustomobject]@{
        Version = $Version
        Status = if ($parsed -lt $reference) { 'Unsupported' } else { 'UnknownVersion' }
        FormatVerified = $false
        ErrorCode = if ($Product -eq 'librime') { 'LIBRIME_VERSION_UNVERIFIED' } else { $null }
    }
}

function Test-DaMaoInstallationId {
    param([AllowNull()][string]$InstallationId)

    return -not [string]::IsNullOrWhiteSpace($InstallationId) -and
        $InstallationId -ne '.' -and $InstallationId -ne '..' -and
        $InstallationId -match '^[\p{L}\p{N}._-]+$'
}

function Get-DaMaoSnapshotCandidatePaths {
    param(
        [Parameter(Mandatory = $true)][string]$RimeUserDir,
        [AllowNull()][string]$SyncDir
    )

    $paths = [System.Collections.Generic.Dictionary[string, string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    try {
        foreach ($file in @(Get-ChildItem -LiteralPath $RimeUserDir -File `
                -Filter '*.userdb.txt' -ErrorAction Stop)) {
            $paths[$file.FullName] = $file.FullName
        }
    }
    catch {
    }
    if (-not [string]::IsNullOrWhiteSpace($SyncDir) -and
        (Test-Path -LiteralPath $SyncDir -PathType Container)) {
        try {
            foreach ($file in @(Get-ChildItem -LiteralPath $SyncDir -File -Recurse `
                    -Filter '*.userdb.txt' -ErrorAction Stop)) {
                $paths[$file.FullName] = $file.FullName
            }
        }
        catch {
        }
    }
    return @($paths.Values | Sort-Object)
}

function Get-DaMaoInstalledSchemaIdentities {
    param([Parameter(Mandatory = $true)][string]$RimeUserDir)

    $identities = New-Object 'System.Collections.Generic.List[string]'
    foreach ($file in @(Get-ChildItem -LiteralPath $RimeUserDir -File `
            -Filter '*.schema.yaml' -ErrorAction SilentlyContinue)) {
        try {
            [byte[]]$bytes = [System.IO.File]::ReadAllBytes($file.FullName)
            if ((Get-DaMaoUtf8Validation -Bytes $bytes) -ne 'Valid') {
                continue
            }
            $offset = if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and
                $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { 3 } else { 0 }
            $text = ([System.Text.UTF8Encoding]::new($false, $true)).GetString(
                $bytes, $offset, $bytes.Length - $offset
            )
            $match = [regex]::Match($text, '(?m)^\s*schema_id:\s*["'']?([^\s"'']+)["'']?\s*$')
            if ($match.Success -and $identities -cnotcontains $match.Groups[1].Value) {
                $identities.Add($match.Groups[1].Value)
            }
        }
        catch {
        }
    }
    return @($identities | Sort-Object)
}

function Get-DaMaoUserDbEnvironmentStatus {
    [CmdletBinding()]
    param(
        [string]$RimeUserDir = (Join-Path $env:APPDATA 'Rime'),
        [ValidateSet('PureWubi')][string]$LogicalRole = 'PureWubi',
        [string]$WeaselRoot
    )

    $errorCodes = New-Object 'System.Collections.Generic.List[string]'
    try {
        $resolvedUserDir = [System.IO.Path]::GetFullPath($RimeUserDir)
    }
    catch {
        $resolvedUserDir = $RimeUserDir
        $errorCodes.Add('RIME_USER_DIR_NOT_FOUND')
    }

    $contractPath = Join-Path (Split-Path -Parent $PSScriptRoot) `
        'contracts\public-baseline-v1.json'
    $contract = Get-Content -LiteralPath $contractPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $role = @($contract.identity_contract.logical_roles | Where-Object {
            [string]$_.logical_role -ceq $LogicalRole
        }) | Select-Object -First 1
    $knownIdentities = @($role.physical_identities)

    $userDirPresent = Test-Path -LiteralPath $resolvedUserDir -PathType Container
    if (-not $userDirPresent -and $errorCodes -cnotcontains 'RIME_USER_DIR_NOT_FOUND') {
        $errorCodes.Add('RIME_USER_DIR_NOT_FOUND')
    }
    $installationPath = Join-Path $resolvedUserDir 'installation.yaml'
    $installation = Read-DaMaoInstallationMetadata -Path $installationPath
    if ($installation.ErrorCode -and $errorCodes -cnotcontains $installation.ErrorCode) {
        $errorCodes.Add($installation.ErrorCode)
    }

    $installationId = $null
    $syncDir = Join-Path $resolvedUserDir 'sync'
    $syncDirSource = 'Default'
    $weaselVersion = $null
    $librimeVersion = $null
    if ($installation.Valid) {
        if ($installation.Values.ContainsKey('installation_id')) {
            $installationId = [string]$installation.Values['installation_id']
            if ($installation.DuplicateKeys -ccontains 'installation_id' -or
                -not (Test-DaMaoInstallationId -InstallationId $installationId)) {
                $errorCodes.Add('INSTALLATION_ID_INVALID')
            }
        }
        else {
            $errorCodes.Add('INSTALLATION_ID_MISSING')
        }

        if ($installation.Values.ContainsKey('sync_dir')) {
            $syncDirSource = 'Explicit'
            $explicitSyncDir = [string]$installation.Values['sync_dir']
            if ($installation.DuplicateKeys -ccontains 'sync_dir' -or
                [string]::IsNullOrWhiteSpace($explicitSyncDir) -or
                -not [System.IO.Path]::IsPathRooted($explicitSyncDir)) {
                $errorCodes.Add('SYNC_DIR_INVALID')
                $syncDir = $null
            }
            else {
                try {
                    $syncDir = [System.IO.Path]::GetFullPath($explicitSyncDir)
                }
                catch {
                    $errorCodes.Add('SYNC_DIR_INVALID')
                    $syncDir = $null
                }
            }
        }
        if ($installation.Values.ContainsKey('distribution_version')) {
            $weaselVersion = [string]$installation.Values['distribution_version']
        }
        if ($installation.Values.ContainsKey('rime_version')) {
            $librimeVersion = [string]$installation.Values['rime_version']
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($WeaselRoot)) {
        foreach ($binaryName in @('WeaselServer.exe', 'WeaselDeployer.exe')) {
            $binaryPath = Join-Path $WeaselRoot $binaryName
            if (Test-Path -LiteralPath $binaryPath -PathType Leaf) {
                try {
                    $binaryVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo(
                        $binaryPath
                    ).FileVersion
                    if (-not [string]::IsNullOrWhiteSpace($binaryVersion)) {
                        $weaselVersion = $binaryVersion
                        break
                    }
                }
                catch {
                }
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($syncDir)) {
        if (-not (Test-Path -LiteralPath $syncDir -PathType Container)) {
            $errorCodes.Add('SYNC_DIR_NOT_FOUND')
        }
        else {
            try {
                [void](Get-ChildItem -LiteralPath $syncDir -Force -ErrorAction Stop |
                    Select-Object -First 1)
            }
            catch {
                $errorCodes.Add('SYNC_DIR_NOT_READABLE')
            }
        }
    }

    $weaselAssessment = Get-DaMaoVersionAssessment -Version $weaselVersion -Product Weasel
    $librimeAssessment = Get-DaMaoVersionAssessment -Version $librimeVersion -Product librime
    foreach ($versionError in @($weaselAssessment.ErrorCode, $librimeAssessment.ErrorCode)) {
        if ($versionError -and $errorCodes -cnotcontains $versionError) {
            $errorCodes.Add($versionError)
        }
    }

    $allSnapshotPaths = if ($userDirPresent) {
        @(Get-DaMaoSnapshotCandidatePaths -RimeUserDir $resolvedUserDir -SyncDir $syncDir)
    }
    else {
        @()
    }
    $snapshotResults = New-Object 'System.Collections.Generic.List[object]'
    foreach ($snapshotPath in $allSnapshotPaths) {
        $snapshotResults.Add((Read-DaMaoUserDbSnapshot -Path $snapshotPath))
    }

    $databaseStatuses = New-Object 'System.Collections.Generic.List[object]'
    foreach ($identity in $knownIdentities) {
        $dbName = [string]$identity.db_name
        $schemaId = [string]$identity.schema_id
        $livePath = Join-Path $resolvedUserDir ($dbName + '.userdb')
        $legacyPath = Join-Path $resolvedUserDir ($dbName + '.userdb.kct')
        $livePresent = Test-Path -LiteralPath $livePath -PathType Container
        $legacyPresent = Test-Path -LiteralPath $legacyPath -PathType Leaf
        $candidateSnapshots = @($snapshotResults | Where-Object {
                [string]::Equals([System.IO.Path]::GetFileName([string]$_.Path),
                    $dbName + '.userdb.txt', [System.StringComparison]::Ordinal)
            })
        $validSnapshots = @($candidateSnapshots | Where-Object {
                $_.StructuralHealth -ceq 'Healthy' -and $_.DbName -ceq $dbName
            })
        $invalidSnapshots = @($candidateSnapshots | Where-Object {
                $_.StructuralHealth -cne 'Healthy' -or $_.DbName -cne $dbName
            })
        $distinctSnapshotHashes = @($validSnapshots | Select-Object -ExpandProperty Sha256 -Unique)
        $state = 'Absent'
        $dbErrors = New-Object 'System.Collections.Generic.List[string]'
        if ($livePresent -and $legacyPresent) {
            $state = 'Ambiguous'
            $dbErrors.Add('USERDB_ARTIFACT_AMBIGUOUS')
        }
        elseif ($invalidSnapshots.Count -gt 0) {
            $state = 'Ambiguous'
            $dbErrors.Add('USERDB_ARTIFACT_AMBIGUOUS')
            foreach ($snapshot in $invalidSnapshots) {
                if ($snapshot.ErrorCode -and $dbErrors -cnotcontains $snapshot.ErrorCode) {
                    $dbErrors.Add([string]$snapshot.ErrorCode)
                }
            }
        }
        elseif ($livePresent) {
            $state = 'LiveDb'
        }
        elseif ($legacyPresent) {
            $state = 'LegacyDb'
        }
        elseif ($validSnapshots.Count -gt 0 -and $distinctSnapshotHashes.Count -eq 1) {
            $state = 'SnapshotOnly'
        }
        elseif ($validSnapshots.Count -gt 1 -and $distinctSnapshotHashes.Count -gt 1) {
            $state = 'Ambiguous'
            $dbErrors.Add('USERDB_ARTIFACT_AMBIGUOUS')
        }

        $databaseStatuses.Add([pscustomobject][ordered]@{
                LogicalRole = $LogicalRole
                SchemaId = $schemaId
                DbName = $dbName
                IdentityId = [string]$identity.identity_id
                State = $state
                LiveDbPath = $livePath
                LiveDbPresent = $livePresent
                LiveDbBasicStructure = if ($livePresent) { 'DirectoryPresent_NotOpened' } else { 'Absent' }
                LegacyDbPath = $legacyPath
                LegacyDbPresent = $legacyPresent
                SnapshotCount = $candidateSnapshots.Count
                ValidSnapshotCount = $validSnapshots.Count
                Snapshots = @($candidateSnapshots)
                StructuralHealth = if ($state -eq 'Ambiguous') { 'Conflict' } elseif ($livePresent) { 'ExistenceOnly_NotValidated' } else { 'Reported' }
                ErrorCodes = $dbErrors.ToArray()
                AutomaticMerge = $false
                AutomaticRename = $false
            })
    }

    $knownDbNames = @($knownIdentities | ForEach-Object { [string]$_.db_name })
    $excludedDbNames = @($contract.identity_contract.default_exclusions |
        ForEach-Object { [string]$_.db_name })
    $excludedArtifacts = New-Object 'System.Collections.Generic.List[object]'
    $unknownArtifacts = New-Object 'System.Collections.Generic.List[object]'

    if ($userDirPresent) {
        $topArtifacts = @(Get-ChildItem -LiteralPath $resolvedUserDir -Force `
            -ErrorAction SilentlyContinue | Where-Object {
                ($_.PSIsContainer -and $_.Name -like '*.userdb') -or
                (-not $_.PSIsContainer -and $_.Name -like '*.userdb.kct')
            })
        foreach ($artifact in $topArtifacts) {
            $dbName = if ($artifact.Name.EndsWith('.userdb.kct')) {
                $artifact.Name.Substring(0, $artifact.Name.Length - '.userdb.kct'.Length)
            }
            else {
                $artifact.Name.Substring(0, $artifact.Name.Length - '.userdb'.Length)
            }
            $kind = if ($artifact.PSIsContainer) { 'LiveDb' } else { 'LegacyDb' }
            if ($excludedDbNames -ccontains $dbName) {
                $excludedArtifacts.Add([pscustomobject]@{
                        Path = $artifact.FullName
                        FileName = $artifact.Name
                        DbName = $dbName
                        ArtifactKind = $kind
                        Disposition = 'excluded_by_default'
                    })
            }
            elseif ($knownDbNames -cnotcontains $dbName) {
                $unknownArtifacts.Add([pscustomobject]@{
                        Path = $artifact.FullName
                        FileName = $artifact.Name
                        DbName = $dbName
                        ArtifactKind = $kind
                        ErrorCode = 'USERDB_IDENTITY_UNCLASSIFIED'
                    })
            }
        }
    }
    foreach ($snapshot in $snapshotResults) {
        $snapshotDbName = [string]$snapshot.DbName
        if ($excludedDbNames -ccontains $snapshotDbName) {
            $excludedArtifacts.Add([pscustomobject]@{
                    Path = $snapshot.Path
                    FileName = [System.IO.Path]::GetFileName([string]$snapshot.Path)
                    DbName = $snapshotDbName
                    ArtifactKind = 'Snapshot'
                    Disposition = 'excluded_by_default'
                })
        }
        elseif ($snapshotDbName -and $knownDbNames -cnotcontains $snapshotDbName) {
            $unknownArtifacts.Add([pscustomobject]@{
                    Path = $snapshot.Path
                    FileName = [System.IO.Path]::GetFileName([string]$snapshot.Path)
                    DbName = $snapshotDbName
                    ArtifactKind = 'Snapshot'
                    ErrorCode = 'USERDB_IDENTITY_UNCLASSIFIED'
                })
        }
    }
    if ($unknownArtifacts.Count -gt 0 -and
        $errorCodes -cnotcontains 'USERDB_IDENTITY_UNCLASSIFIED') {
        $errorCodes.Add('USERDB_IDENTITY_UNCLASSIFIED')
    }

    return [pscustomobject][ordered]@{
        ContractVersion = 1
        ReadOnly = $true
        LogicalRole = $LogicalRole
        RimeUserDir = $resolvedUserDir
        RimeUserDirStatus = if ($userDirPresent) { 'Present' } else { 'NotFound' }
        InstallationPath = $installationPath
        InstallationId = $installationId
        SyncDir = $syncDir
        SyncDirSource = $syncDirSource
        SyncDirStatus = if (-not $syncDir) { 'Invalid' } elseif (Test-Path -LiteralPath $syncDir -PathType Container) { 'Present' } else { 'NotFound' }
        WeaselVersion = $weaselAssessment.Version
        WeaselVersionStatus = $weaselAssessment.Status
        LibrimeVersion = $librimeAssessment.Version
        LibrimeVersionStatus = $librimeAssessment.Status
        SnapshotFormatVerified = $librimeAssessment.FormatVerified
        FutureMutationCapability = 'DisabledP1ReadOnly'
        InstalledSchemaIdentities = if ($userDirPresent) { @(Get-DaMaoInstalledSchemaIdentities -RimeUserDir $resolvedUserDir) } else { @() }
        Databases = $databaseStatuses.ToArray()
        ExcludedArtifacts = $excludedArtifacts.ToArray()
        UnknownArtifacts = $unknownArtifacts.ToArray()
        ErrorCodes = @($errorCodes | Select-Object -Unique)
    }
}
