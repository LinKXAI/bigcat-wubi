[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\DaMao.UserDbSnapshot.ps1')
. (Join-Path $PSScriptRoot 'DaMao.PortabilityBaseline.ps1')

$script:assertionCount = 0
$script:parserCaseCount = 0
$script:detectorCaseCount = 0
$script:privacyCaseCount = 0

function Assert-P1 {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $script:assertionCount++
    if (-not $Condition) {
        throw "[$Code] $Message"
    }
}

function Assert-PublicBaselineP1 {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $contract = Get-DaMaoPublicBaseline -RepositoryRoot $repoRoot
    $files = @($contract.current_file_integrity.files)
    $failures = @(Test-DaMaoPublicBaselineManifest -RepositoryRoot $repoRoot -Files $files)
    if ($failures.Count -gt 0) {
        throw "[P1_BLOCKED_INPUT_CORE_DRIFT] Public baseline mismatch count: $($failures.Count)"
    }
    Assert-P1 ($files.Count -eq 17) 'DM-P1-FREEZE-01' `
        'Public Baseline V1 must contain 17 pinned files.'
    return 17
}

function Write-Utf8Text {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [switch]$Bom
    )

    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force)
    $encoding = [System.Text.UTF8Encoding]::new([bool]$Bom)
    [System.IO.File]::WriteAllText($Path, $Text, $encoding)
}

function New-SnapshotHeader {
    param(
        [string]$DbName = 'damao_wubi',
        [string]$DbType = 'userdb',
        [string]$UserId = 'test-machine',
        [string]$NewLine = "`n",
        [string[]]$ExtraHeaders = @(),
        [switch]$OmitDbName,
        [switch]$OmitDbType
    )

    $lines = New-Object 'System.Collections.Generic.List[string]'
    $lines.Add('# Rime user dictionary')
    if (-not $OmitDbName) { $lines.Add("#@/db_name`t$DbName") }
    if (-not $OmitDbType) { $lines.Add("#@/db_type`t$DbType") }
    $lines.Add('#@/rime_version' + "`t" + '1.13.1')
    $lines.Add('#@/tick' + "`t" + '100')
    $lines.Add("#@/user_id`t$UserId")
    foreach ($header in $ExtraHeaders) { $lines.Add($header) }
    return (@($lines) -join $NewLine) + $NewLine
}

function New-SnapshotFixture {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$CaseName,
        [Parameter(Mandatory = $true)][string]$Text,
        [string]$FileDbName = 'damao_wubi',
        [switch]$Bom
    )

    $path = Join-Path (Join-Path $Root $CaseName) ($FileDbName + '.userdb.txt')
    Write-Utf8Text -Path $path -Text $Text -Bom:$Bom
    return $path
}

function Assert-SnapshotError {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedCode,
        [Parameter(Mandatory = $true)][string]$CaseName
    )

    $script:parserCaseCount++
    $result = Read-DaMaoUserDbSnapshot -Path $Path
    Assert-P1 ($result.ErrorCode -ceq $ExpectedCode) "DM-P1-PARSER-$CaseName" `
        "Expected $ExpectedCode, received $($result.ErrorCode)."
    Assert-P1 ($result.StructuralHealth -ceq 'Invalid') "DM-P1-PARSER-$CaseName-HEALTH" `
        'A corrupt snapshot was not marked invalid.'
    return $result
}

function New-TestEnvironment {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$InstallationId = ($Name.ToLowerInvariant() + '-id'),
        [ValidateSet('Default', 'Explicit', 'Missing', 'MissingId', 'InvalidSync')]
        [string]$InstallationMode = 'Explicit',
        [string]$RimeVersion = '1.13.1'
    )

    $machineRoot = Join-Path $Root $Name
    $userDir = Join-Path $machineRoot 'user'
    $siblingSync = Join-Path $machineRoot 'sync'
    [void](New-Item -ItemType Directory -Path $userDir -Force)
    if ($InstallationMode -eq 'Default') {
        $syncDir = Join-Path $userDir 'sync'
    }
    else {
        $syncDir = $siblingSync
    }
    if ($InstallationMode -notin @('Missing', 'InvalidSync')) {
        [void](New-Item -ItemType Directory -Path $syncDir -Force)
    }

    if ($InstallationMode -ne 'Missing') {
        $lines = New-Object 'System.Collections.Generic.List[string]'
        if ($InstallationMode -ne 'MissingId') {
            $lines.Add("installation_id: '$InstallationId'")
        }
        if ($InstallationMode -eq 'Explicit') {
            $lines.Add("sync_dir: '$syncDir'")
        }
        elseif ($InstallationMode -eq 'InvalidSync') {
            $lines.Add("sync_dir: 'relative-sync'")
        }
        $lines.Add("distribution_code_name: 'Weasel'")
        $lines.Add("distribution_version: '0.17.4'")
        $lines.Add("rime_version: '$RimeVersion'")
        Write-Utf8Text -Path (Join-Path $userDir 'installation.yaml') `
            -Text ((@($lines) -join "`n") + "`n")
    }

    return [pscustomobject]@{
        Root = $machineRoot
        User = $userDir
        Sync = $syncDir
        InstallationId = $InstallationId
    }
}

function Add-TestSnapshot {
    param(
        [Parameter(Mandatory = $true)]$Environment,
        [Parameter(Mandatory = $true)][string]$DbName,
        [string]$SourceInstallationId = $Environment.InstallationId,
        [string]$Phrase = 'test-phrase',
        [string]$Code = 'abcd '
    )

    $directory = Join-Path $Environment.Sync $SourceInstallationId
    $path = Join-Path $directory ($DbName + '.userdb.txt')
    $text = (New-SnapshotHeader -DbName $DbName -UserId $SourceInstallationId) +
        "$Code`t$Phrase`tc=1 d=1.5 t=90`n"
    Write-Utf8Text -Path $path -Text $text
    return $path
}

function Get-DatabaseStatus {
    param(
        [Parameter(Mandatory = $true)]$Status,
        [Parameter(Mandatory = $true)][string]$DbName
    )

    return @($Status.Databases | Where-Object { $_.DbName -ceq $DbName })[0]
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
    ('damao-userdb-p1-' + [guid]::NewGuid().ToString('N'))
$tempRootFull = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
)
$testRootFull = [System.IO.Path]::GetFullPath($testRoot)
Assert-P1 ($testRootFull.StartsWith(
        $tempRootFull + [System.IO.Path]::DirectorySeparatorChar,
        [System.StringComparison]::OrdinalIgnoreCase
    )) 'DM-P1-TEMP-01' 'The isolated test root is outside the system temporary directory.'

    $freezeStart = Assert-PublicBaselineP1
$stateFingerprintParts = New-Object 'System.Collections.Generic.List[string]'
$privacySentinel = 'PRIVACY_SENTINEL_DO_NOT_PRINT'
$unicodePhrase = -join @(
    [char]0x5927,
    [char]0x732B,
    [char]0x4E94,
    [char]0x7B14,
    [char]0xD83D,
    [char]0xDE00
)

try {
    [void](New-Item -ItemType Directory -Path $testRootFull)
    $parserRoot = Join-Path $testRootFull 'parser'

    $minimalText = (New-SnapshotHeader) + "abcd `t$unicodePhrase`tc=1 d=1.5 t=90`n"
    $minimalPath = New-SnapshotFixture -Root $parserRoot -CaseName 'valid-minimal' `
        -Text $minimalText
    $script:parserCaseCount++
    $minimal = Read-DaMaoUserDbSnapshot -Path $minimalPath
    Assert-P1 ($minimal.StructuralHealth -ceq 'Healthy' -and $minimal.EntryCount -eq 1) `
        'DM-P1-PARSER-VALID-MINIMAL' 'The minimal native snapshot was not accepted.'
    Assert-P1 ($minimal.DbName -ceq 'damao_wubi' -and $minimal.DbType -ceq 'userdb') `
        'DM-P1-PARSER-HEADER-AUTHORITY' 'Header identity was not parsed.'
    Assert-P1 ($minimal.PSObject.Properties.Name -cnotcontains 'Entries') `
        'DM-P1-PRIVACY-DEFAULT-ENTRIES' 'Default parser result exposed entries.'

    $multiText = (New-SnapshotHeader) +
        "abcd `talpha`tc=2 d=2 t=80`n" +
        "efgh `tbeta`tc=3 d=3e-2 t=99`n"
    $multiPath = New-SnapshotFixture -Root $parserRoot -CaseName 'valid-multiple' `
        -Text $multiText
    $script:parserCaseCount++
    $multi = Read-DaMaoUserDbSnapshot -Path $multiPath -IncludeEntries
    Assert-P1 ($multi.EntryCount -eq 2 -and $multi.MinTick -eq 80 -and
        $multi.MaxTick -eq 99) 'DM-P1-PARSER-MULTIPLE' 'Multiple entries or tick range failed.'

    $tombstonePath = New-SnapshotFixture -Root $parserRoot -CaseName 'valid-tombstone' `
        -Text ((New-SnapshotHeader) + "abcd `ttombstone`tc=-2 d=0 t=91`n")
    $script:parserCaseCount++
    $tombstone = Read-DaMaoUserDbSnapshot -Path $tombstonePath -IncludeEntries
    Assert-P1 ($tombstone.TombstoneCount -eq 1 -and $tombstone.Entries[0].IsTombstone) `
        'DM-P1-PARSER-TOMBSTONE' 'Negative c was not preserved as a tombstone.'

    $unicodePath = New-SnapshotFixture -Root $parserRoot -CaseName 'valid-unicode' `
        -Text ((New-SnapshotHeader) + "abcd `t$unicodePhrase`tc=1 d=1 t=92`n")
    $script:parserCaseCount++
    $unicode = Read-DaMaoUserDbSnapshot -Path $unicodePath -IncludeEntries
    Assert-P1 ($unicode.Entries[0].Phrase -ceq $unicodePhrase) 'DM-P1-PARSER-UNICODE' `
        'Valid Unicode phrase content changed.'

    $bomPath = New-SnapshotFixture -Root $parserRoot -CaseName 'valid-bom' `
        -Text $minimalText -Bom
    $script:parserCaseCount++
    $bom = Read-DaMaoUserDbSnapshot -Path $bomPath
    Assert-P1 ($bom.StructuralHealth -ceq 'Healthy' -and $bom.Encoding -ceq 'UTF-8-BOM') `
        'DM-P1-PARSER-BOM' 'UTF-8 BOM compatibility failed.'
    Assert-P1 ($bom.DbName -ceq $minimal.DbName -and $bom.EntryCount -eq $minimal.EntryCount) `
        'DM-P1-PARSER-BOM-SEMANTICS' 'BOM changed parser semantics.'

    $crlfText = ((New-SnapshotHeader -NewLine "`r`n") +
        "abcd `tcrlf`tc=1 d=1 t=90`r`n")
    $crlfPath = New-SnapshotFixture -Root $parserRoot -CaseName 'valid-crlf' -Text $crlfText
    $script:parserCaseCount++
    Assert-P1 ((Read-DaMaoUserDbSnapshot -Path $crlfPath).StructuralHealth -ceq 'Healthy') `
        'DM-P1-PARSER-CRLF' 'CRLF snapshot was rejected.'

    $unknownHeaderText = (New-SnapshotHeader -ExtraHeaders @('#@/future_field' + "`t" + 'future')) +
        "abcd `tunknown-header`tc=1 d=1 t=90"
    $unknownHeaderPath = New-SnapshotFixture -Root $parserRoot `
        -CaseName 'valid-unknown-header-no-final-newline' -Text $unknownHeaderText
    $script:parserCaseCount++
    $unknownHeader = Read-DaMaoUserDbSnapshot -Path $unknownHeaderPath
    Assert-P1 ($unknownHeader.StructuralHealth -ceq 'Healthy' -and
        $unknownHeader.UnknownHeaderFields -ccontains '/future_field') `
        'DM-P1-PARSER-UNKNOWN-HEADER' 'Unknown metadata was not tolerated safely.'

    $optionalHeaderText = "# Rime user dictionary`n" +
        "#@/db_name`tdamao_wubi`n#@/db_type`tuserdb`n" +
        "abcd `toptional`tc=1 d=1 t=9`n"
    $optionalHeaderPath = New-SnapshotFixture -Root $parserRoot `
        -CaseName 'valid-optional-header-fields' -Text $optionalHeaderText
    $script:parserCaseCount++
    $optionalHeader = Read-DaMaoUserDbSnapshot -Path $optionalHeaderPath
    Assert-P1 ($optionalHeader.StructuralHealth -ceq 'Healthy' -and
        $null -eq $optionalHeader.RimeVersion -and $null -eq $optionalHeader.Tick -and
        $null -eq $optionalHeader.UserId) 'DM-P1-PARSER-OPTIONAL-HEADER' `
        'Optional librime metadata was incorrectly required.'

    $nonEmptyCodePath = New-SnapshotFixture -Root $parserRoot `
        -CaseName 'valid-nonempty-code-with-leading-space' `
        -Text ((New-SnapshotHeader) + " abcd`tcode-compat`tc=1 d=1 t=9`n")
    $script:parserCaseCount++
    $nonEmptyCode = Read-DaMaoUserDbSnapshot -Path $nonEmptyCodePath -IncludeEntries
    Assert-P1 ($nonEmptyCode.StructuralHealth -ceq 'Healthy' -and
        $nonEmptyCode.Entries[0].Code -ceq ' abcd ') `
        'DM-P1-PARSER-CODE-COMPAT' 'A nonempty librime code was restricted by invented grammar.'

    $clampPath = New-SnapshotFixture -Root $parserRoot -CaseName 'valid-dee-clamp' `
        -Text ((New-SnapshotHeader) + "abcd `tclamp`tc=1 d=20000 t=90`n")
    $script:parserCaseCount++
    $clamped = Read-DaMaoUserDbSnapshot -Path $clampPath -IncludeEntries
    Assert-P1 ($clamped.Entries[0].D -eq 10000.0) 'DM-P1-PARSER-DEE-CLAMP' `
        'The librime 1.13.1 dee upper clamp was not reproduced.'

    $invalidUtf8Path = Join-Path (Join-Path $parserRoot 'invalid-utf8') `
        'damao_wubi.userdb.txt'
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $invalidUtf8Path) -Force)
    $validPrefix = ([System.Text.UTF8Encoding]::new($false)).GetBytes(
        (New-SnapshotHeader)
    )
    [byte[]]$invalidBytes = @($validPrefix + [byte[]]@(0xC3, 0x28))
    [System.IO.File]::WriteAllBytes($invalidUtf8Path, $invalidBytes)
    [void](Assert-SnapshotError -Path $invalidUtf8Path -ExpectedCode 'SNAPSHOT_INVALID_UTF8' `
        -CaseName 'INVALID-UTF8')

    $truncatedUtf8Path = Join-Path (Join-Path $parserRoot 'truncated-utf8') `
        'damao_wubi.userdb.txt'
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $truncatedUtf8Path) -Force)
    [byte[]]$truncatedBytes = @($validPrefix + [byte[]]@(0xE4, 0xB8))
    [System.IO.File]::WriteAllBytes($truncatedUtf8Path, $truncatedBytes)
    [void](Assert-SnapshotError -Path $truncatedUtf8Path -ExpectedCode 'SNAPSHOT_INVALID_UTF8' `
        -CaseName 'TRUNCATED-UTF8')

    $badHeaderPath = New-SnapshotFixture -Root $parserRoot -CaseName 'bad-header' `
        -Text "# not a native snapshot`n"
    [void](Assert-SnapshotError -Path $badHeaderPath -ExpectedCode 'SNAPSHOT_HEADER_INVALID' `
        -CaseName 'BAD-HEADER')

    $missingNamePath = New-SnapshotFixture -Root $parserRoot -CaseName 'missing-db-name' `
        -Text ((New-SnapshotHeader -OmitDbName) + "abcd `tword`tc=1 d=1 t=1`n")
    [void](Assert-SnapshotError -Path $missingNamePath -ExpectedCode 'SNAPSHOT_DB_NAME_INVALID' `
        -CaseName 'MISSING-DB-NAME')

    $wrongTypePath = New-SnapshotFixture -Root $parserRoot -CaseName 'wrong-db-type' `
        -Text ((New-SnapshotHeader -DbType 'tabledb') + "abcd `tword`tc=1 d=1 t=1`n")
    [void](Assert-SnapshotError -Path $wrongTypePath -ExpectedCode 'SNAPSHOT_DB_TYPE_INVALID' `
        -CaseName 'WRONG-DB-TYPE')

    $missingTypePath = New-SnapshotFixture -Root $parserRoot -CaseName 'missing-db-type' `
        -Text ((New-SnapshotHeader -OmitDbType) + "abcd `tword`tc=1 d=1 t=1`n")
    [void](Assert-SnapshotError -Path $missingTypePath -ExpectedCode 'SNAPSHOT_HEADER_INVALID' `
        -CaseName 'MISSING-DB-TYPE')

    $mismatchPath = New-SnapshotFixture -Root $parserRoot -CaseName 'filename-mismatch' `
        -FileDbName 'different' -Text ((New-SnapshotHeader) + "abcd `tword`tc=1 d=1 t=1`n")
    [void](Assert-SnapshotError -Path $mismatchPath `
        -ExpectedCode 'SNAPSHOT_FILENAME_DB_NAME_MISMATCH' -CaseName 'FILENAME-MISMATCH')

    $malformedKeyPath = New-SnapshotFixture -Root $parserRoot -CaseName 'malformed-key' `
        -Text ((New-SnapshotHeader) + "ab$([char]1)cd`tword`tc=1 d=1 t=1`n")
    [void](Assert-SnapshotError -Path $malformedKeyPath -ExpectedCode 'SNAPSHOT_ENTRY_INVALID' `
        -CaseName 'MALFORMED-KEY')

    $emptyCodePath = New-SnapshotFixture -Root $parserRoot -CaseName 'empty-code' `
        -Text ((New-SnapshotHeader) + "`tword`tc=1 d=1 t=1`n")
    [void](Assert-SnapshotError -Path $emptyCodePath -ExpectedCode 'SNAPSHOT_ENTRY_INVALID' `
        -CaseName 'EMPTY-CODE')

    $emptyPhrasePath = New-SnapshotFixture -Root $parserRoot -CaseName 'empty-phrase' `
        -Text ((New-SnapshotHeader) + "abcd `t`tc=1 d=1 t=1`n")
    [void](Assert-SnapshotError -Path $emptyPhrasePath -ExpectedCode 'SNAPSHOT_ENTRY_INVALID' `
        -CaseName 'EMPTY-PHRASE')

    foreach ($numericCase in @(
            @{ Name = 'BAD-C'; Value = 'c=no d=1 t=1' },
            @{ Name = 'BAD-D'; Value = 'c=1 d=no t=1' },
            @{ Name = 'BAD-T'; Value = 'c=1 d=1 t=no' },
            @{ Name = 'C-OVERFLOW'; Value = 'c=2147483648 d=1 t=1' },
            @{ Name = 'T-OVERFLOW'; Value = 'c=1 d=1 t=18446744073709551616' },
            @{ Name = 'D-OVERFLOW'; Value = 'c=1 d=1e9999 t=1' },
            @{ Name = 'D-NAN'; Value = 'c=1 d=NaN t=1' },
            @{ Name = 'D-INFINITY'; Value = 'c=1 d=Infinity t=1' },
            @{ Name = 'D-NEGATIVE'; Value = 'c=1 d=-1 t=1' },
            @{ Name = 'T-NEGATIVE'; Value = 'c=1 d=1 t=-1' }
        )) {
        $path = New-SnapshotFixture -Root $parserRoot `
            -CaseName ('numeric-' + $numericCase.Name.ToLowerInvariant()) `
            -Text ((New-SnapshotHeader) + "abcd `tnumeric`t$($numericCase.Value)`n")
        [void](Assert-SnapshotError -Path $path -ExpectedCode 'SNAPSHOT_NUMERIC_FIELD_INVALID' `
            -CaseName $numericCase.Name)
    }

    $duplicatePath = New-SnapshotFixture -Root $parserRoot -CaseName 'duplicate-key' `
        -Text ((New-SnapshotHeader) +
            "abcd`t$privacySentinel`tc=1 d=1 t=1`n" +
            "abcd `t$privacySentinel`tc=2 d=2 t=2`n")
    $duplicate = Assert-SnapshotError -Path $duplicatePath `
        -ExpectedCode 'SNAPSHOT_DUPLICATE_KEY' -CaseName 'DUPLICATE-KEY'
    Assert-P1 ($duplicate.DuplicateKeyCount -eq 1 -and $duplicate.ErrorLine -eq 8) `
        'DM-P1-PARSER-DUPLICATE-DIAGNOSTIC' 'Duplicate count or first conflict line is wrong.'
    $duplicateJson = $duplicate | ConvertTo-Json -Depth 8 -Compress
    $script:privacyCaseCount++
    Assert-P1 ($duplicateJson -notmatch [regex]::Escape($privacySentinel)) `
        'DM-P1-PRIVACY-DUPLICATE' 'Duplicate-key failure leaked phrase text.'

    $truncatedRecordPath = New-SnapshotFixture -Root $parserRoot `
        -CaseName 'truncated-last-record' `
        -Text ((New-SnapshotHeader) + "abcd `ttruncated")
    [void](Assert-SnapshotError -Path $truncatedRecordPath `
        -ExpectedCode 'SNAPSHOT_TRUNCATED' -CaseName 'TRUNCATED-RECORD')

    $nulPath = New-SnapshotFixture -Root $parserRoot -CaseName 'embedded-nul' `
        -Text ((New-SnapshotHeader) + "abcd `tbefore$([char]0)after`tc=1 d=1 t=1`n")
    [void](Assert-SnapshotError -Path $nulPath -ExpectedCode 'SNAPSHOT_ENTRY_INVALID' `
        -CaseName 'EMBEDDED-NUL')

    $replacementPath = New-SnapshotFixture -Root $parserRoot -CaseName 'replacement-char' `
        -Text ((New-SnapshotHeader) + "abcd `tbefore$([char]0xFFFD)after`tc=1 d=1 t=1`n")
    $script:parserCaseCount++
    $literalReplacement = Read-DaMaoUserDbSnapshot -Path $replacementPath -IncludeEntries
    Assert-P1 ($literalReplacement.StructuralHealth -ceq 'Healthy' -and
        $literalReplacement.Entries[0].Phrase.IndexOf([char]0xFFFD) -ge 0) `
        'DM-P1-PARSER-LITERAL-UFFFD' 'Literal valid UTF-8 U+FFFD was rejected.'
    $literalReplacementDefault = Read-DaMaoUserDbSnapshot -Path $replacementPath
    $literalReplacementJson = $literalReplacementDefault | ConvertTo-Json -Depth 8 -Compress
    Assert-P1 ($literalReplacementJson.IndexOf([char]0xFFFD) -lt 0) `
        'DM-P1-PRIVACY-LITERAL-UFFFD' 'Default metadata leaked the literal U+FFFD phrase.'

    $bareCrPath = New-SnapshotFixture -Root $parserRoot -CaseName 'bare-cr' `
        -Text ((New-SnapshotHeader) + "abcd `tword`tc=1 d=1 t=1`rnext")
    [void](Assert-SnapshotError -Path $bareCrPath -ExpectedCode 'SNAPSHOT_ENTRY_INVALID' `
        -CaseName 'BARE-CR')

    $extraFieldPath = New-SnapshotFixture -Root $parserRoot -CaseName 'extra-field' `
        -Text ((New-SnapshotHeader) + "abcd `tword`tc=1 d=1 t=1`textra`n")
    [void](Assert-SnapshotError -Path $extraFieldPath -ExpectedCode 'SNAPSHOT_ENTRY_INVALID' `
        -CaseName 'EXTRA-FIELD')

    $duplicateHeaderText = "# Rime user dictionary`n#@/db_name`tdamao_wubi`n" +
        "#@/db_name`tdamao_wubi_alpha03`n#@/db_type`tuserdb`n"
    $duplicateHeaderPath = New-SnapshotFixture -Root $parserRoot `
        -CaseName 'duplicate-header' -Text $duplicateHeaderText
    [void](Assert-SnapshotError -Path $duplicateHeaderPath -ExpectedCode 'SNAPSHOT_HEADER_INVALID' `
        -CaseName 'DUPLICATE-HEADER')

    $missingPath = Join-Path $parserRoot 'missing\damao_wubi.userdb.txt'
    [void](Assert-SnapshotError -Path $missingPath -ExpectedCode 'SNAPSHOT_NOT_FOUND' `
        -CaseName 'NOT-FOUND')

    $privacyPath = New-SnapshotFixture -Root $parserRoot -CaseName 'privacy' `
        -Text ((New-SnapshotHeader) + "abcd `t$privacySentinel`tc=1 d=1 t=1`n")
    $privacyDefault = Read-DaMaoUserDbSnapshot -Path $privacyPath
    $privacyDefaultJson = $privacyDefault | ConvertTo-Json -Depth 8 -Compress
    $script:privacyCaseCount++
    Assert-P1 ($privacyDefaultJson -notmatch [regex]::Escape($privacySentinel)) `
        'DM-P1-PRIVACY-PARSER-DEFAULT' 'Default parser serialization leaked phrase text.'
    $privacyInternal = Read-DaMaoUserDbSnapshot -Path $privacyPath -IncludeEntries
    Assert-P1 ($privacyInternal.Entries[0].Phrase -ceq $privacySentinel) `
        'DM-P1-PRIVACY-INTERNAL' 'Explicit internal entry access did not work.'

    $detectorRoot = Join-Path $testRootFull 'detector'

    $absentEnv = New-TestEnvironment -Root $detectorRoot -Name 'Absent'
    $absentStatus = Get-DaMaoUserDbEnvironmentStatus -RimeUserDir $absentEnv.User
    $script:detectorCaseCount++
    Assert-P1 ((Get-DatabaseStatus $absentStatus 'damao_wubi').State -ceq 'Absent') `
        'DM-P1-DETECT-ABSENT' 'Absent state was not detected.'
    Assert-P1 ($absentStatus.WeaselVersionStatus -ceq 'Supported' -and
        $absentStatus.LibrimeVersionStatus -ceq 'Supported' -and
        $absentStatus.SnapshotFormatVerified) 'DM-P1-DETECT-SUPPORTED-VERSIONS' `
        'The verified Weasel/librime reference versions were not recognized.'
    $stateFingerprintParts.Add('Absent')

    $liveEnv = New-TestEnvironment -Root $detectorRoot -Name 'Live'
    [void](New-Item -ItemType Directory -Path (Join-Path $liveEnv.User 'damao_wubi_alpha03.userdb'))
    $liveStatus = Get-DaMaoUserDbEnvironmentStatus -RimeUserDir $liveEnv.User
    $script:detectorCaseCount++
    $liveDb = Get-DatabaseStatus $liveStatus 'damao_wubi_alpha03'
    Assert-P1 ($liveDb.State -ceq 'LiveDb' -and
        $liveDb.LiveDbBasicStructure -ceq 'DirectoryPresent_NotOpened') `
        'DM-P1-DETECT-LIVE' 'Live DB existence-only state failed.'
    $stateFingerprintParts.Add('LiveDb')

    $legacyEnv = New-TestEnvironment -Root $detectorRoot -Name 'Legacy'
    Write-Utf8Text -Path (Join-Path $legacyEnv.User 'damao_wubi.userdb.kct') -Text 'fixture'
    $legacyStatus = Get-DaMaoUserDbEnvironmentStatus -RimeUserDir $legacyEnv.User
    $script:detectorCaseCount++
    Assert-P1 ((Get-DatabaseStatus $legacyStatus 'damao_wubi').State -ceq 'LegacyDb') `
        'DM-P1-DETECT-LEGACY' 'Legacy DB state failed.'
    $stateFingerprintParts.Add('LegacyDb')

    $snapshotEnv = New-TestEnvironment -Root $detectorRoot -Name 'SnapshotOnly'
    [void](Add-TestSnapshot -Environment $snapshotEnv -DbName 'damao_wubi')
    $snapshotStatus = Get-DaMaoUserDbEnvironmentStatus -RimeUserDir $snapshotEnv.User
    $script:detectorCaseCount++
    Assert-P1 ((Get-DatabaseStatus $snapshotStatus 'damao_wubi').State -ceq 'SnapshotOnly') `
        'DM-P1-DETECT-SNAPSHOT-ONLY' 'SnapshotOnly state failed.'
    $stateFingerprintParts.Add('SnapshotOnly')

    $normalEnv = New-TestEnvironment -Root $detectorRoot -Name 'LiveAndSnapshot'
    [void](New-Item -ItemType Directory -Path (Join-Path $normalEnv.User 'damao_wubi.userdb'))
    [void](Add-TestSnapshot -Environment $normalEnv -DbName 'damao_wubi')
    $normalStatus = Get-DaMaoUserDbEnvironmentStatus -RimeUserDir $normalEnv.User
    $script:detectorCaseCount++
    Assert-P1 ((Get-DatabaseStatus $normalStatus 'damao_wubi').State -ceq 'LiveDb') `
        'DM-P1-DETECT-LIVE-SNAPSHOT' 'Normal LiveDb plus sync snapshot became ambiguous.'

    $ambiguousEnv = New-TestEnvironment -Root $detectorRoot -Name 'Ambiguous'
    [void](New-Item -ItemType Directory -Path (Join-Path $ambiguousEnv.User 'damao_wubi.userdb'))
    Write-Utf8Text -Path (Join-Path $ambiguousEnv.User 'damao_wubi.userdb.kct') -Text 'fixture'
    $ambiguousStatus = Get-DaMaoUserDbEnvironmentStatus -RimeUserDir $ambiguousEnv.User
    $script:detectorCaseCount++
    $ambiguousDb = Get-DatabaseStatus $ambiguousStatus 'damao_wubi'
    Assert-P1 ($ambiguousDb.State -ceq 'Ambiguous' -and
        $ambiguousDb.ErrorCodes -ccontains 'USERDB_ARTIFACT_AMBIGUOUS') `
        'DM-P1-DETECT-AMBIGUOUS' 'Conflicting live and legacy DB was not ambiguous.'
    $stateFingerprintParts.Add('Ambiguous')

    $multiSnapshotEnv = New-TestEnvironment -Root $detectorRoot -Name 'MultiSnapshot'
    [void](Add-TestSnapshot -Environment $multiSnapshotEnv -DbName 'damao_wubi' `
        -SourceInstallationId 'source-one' -Phrase 'alpha')
    [void](Add-TestSnapshot -Environment $multiSnapshotEnv -DbName 'damao_wubi' `
        -SourceInstallationId 'source-two' -Phrase 'beta')
    $multiSnapshotStatus = Get-DaMaoUserDbEnvironmentStatus `
        -RimeUserDir $multiSnapshotEnv.User
    $script:detectorCaseCount++
    Assert-P1 ((Get-DatabaseStatus $multiSnapshotStatus 'damao_wubi').State -ceq 'Ambiguous') `
        'DM-P1-DETECT-MULTI-SNAPSHOT' 'Conflicting SnapshotOnly sources were not ambiguous.'

    $bothEnv = New-TestEnvironment -Root $detectorRoot -Name 'BothPureWubi'
    [void](New-Item -ItemType Directory -Path (Join-Path $bothEnv.User 'damao_wubi.userdb'))
    [void](New-Item -ItemType Directory -Path (Join-Path $bothEnv.User 'damao_wubi_alpha03.userdb'))
    Write-Utf8Text -Path (Join-Path $bothEnv.User 'damao_wubi_alpha03.schema.yaml') `
        -Text "schema:`n  schema_id: damao_wubi_alpha03`n"
    $bothStatus = Get-DaMaoUserDbEnvironmentStatus -RimeUserDir $bothEnv.User
    $script:detectorCaseCount++
    $bothLegacy = Get-DatabaseStatus $bothStatus 'damao_wubi'
    $bothAlpha03 = Get-DatabaseStatus $bothStatus 'damao_wubi_alpha03'
    Assert-P1 ($bothLegacy.State -ceq 'LiveDb' -and $bothAlpha03.State -ceq 'LiveDb' -and
        $bothLegacy.DbName -cne $bothAlpha03.DbName -and
        -not $bothLegacy.AutomaticMerge -and -not $bothAlpha03.AutomaticMerge -and
        -not $bothLegacy.AutomaticRename -and -not $bothAlpha03.AutomaticRename) `
        'DM-P1-DETECT-COEXISTENCE' 'PureWubi identities did not remain separate.'
    Assert-P1 ($bothStatus.InstalledSchemaIdentities -ccontains 'damao_wubi_alpha03') `
        'DM-P1-DETECT-SCHEMA-IDENTITY' 'Installed schema identity was not detected.'

    $excludedEnv = New-TestEnvironment -Root $detectorRoot -Name 'PinyinExcluded'
    [void](New-Item -ItemType Directory -Path (Join-Path $excludedEnv.User 'damao_wubi_pinyin.userdb'))
    $excludedStatus = Get-DaMaoUserDbEnvironmentStatus -RimeUserDir $excludedEnv.User
    $script:detectorCaseCount++
    Assert-P1 ($excludedStatus.ExcludedArtifacts.Count -eq 1 -and
        $excludedStatus.ExcludedArtifacts[0].Disposition -ceq 'excluded_by_default') `
        'DM-P1-DETECT-PINYIN' 'Pinyin was not excluded by default.'

    $unknownEnv = New-TestEnvironment -Root $detectorRoot -Name 'Unknown'
    [void](New-Item -ItemType Directory -Path (Join-Path $unknownEnv.User 'mystery.userdb'))
    $unknownStatus = Get-DaMaoUserDbEnvironmentStatus -RimeUserDir $unknownEnv.User
    $script:detectorCaseCount++
    Assert-P1 ($unknownStatus.UnknownArtifacts.Count -eq 1 -and
        $unknownStatus.ErrorCodes -ccontains 'USERDB_IDENTITY_UNCLASSIFIED') `
        'DM-P1-DETECT-UNKNOWN' 'Unknown DB did not fail closed.'

    $defaultEnv = New-TestEnvironment -Root $detectorRoot -Name 'DefaultSync' `
        -InstallationMode Default
    $defaultStatus = Get-DaMaoUserDbEnvironmentStatus -RimeUserDir $defaultEnv.User
    $script:detectorCaseCount++
    Assert-P1 ($defaultStatus.SyncDirSource -ceq 'Default' -and
        $defaultStatus.SyncDir -ceq (Join-Path $defaultEnv.User 'sync')) `
        'DM-P1-DETECT-DEFAULT-SYNC' 'Default sync_dir resolution failed.'

    $explicitEnv = New-TestEnvironment -Root $detectorRoot -Name 'ExplicitSync'
    $explicitStatus = Get-DaMaoUserDbEnvironmentStatus -RimeUserDir $explicitEnv.User
    $script:detectorCaseCount++
    Assert-P1 ($explicitStatus.SyncDirSource -ceq 'Explicit' -and
        $explicitStatus.SyncDir -ceq $explicitEnv.Sync) `
        'DM-P1-DETECT-EXPLICIT-SYNC' 'Explicit sync_dir resolution failed.'

    $missingInstallEnv = New-TestEnvironment -Root $detectorRoot -Name 'MissingInstall' `
        -InstallationMode Missing
    $missingInstallStatus = Get-DaMaoUserDbEnvironmentStatus `
        -RimeUserDir $missingInstallEnv.User
    $script:detectorCaseCount++
    Assert-P1 ($missingInstallStatus.ErrorCodes -ccontains 'INSTALLATION_YAML_NOT_FOUND') `
        'DM-P1-DETECT-MISSING-INSTALL' 'Missing installation.yaml was not reported.'

    $missingIdEnv = New-TestEnvironment -Root $detectorRoot -Name 'MissingId' `
        -InstallationMode MissingId
    $missingIdStatus = Get-DaMaoUserDbEnvironmentStatus -RimeUserDir $missingIdEnv.User
    $script:detectorCaseCount++
    Assert-P1 ($missingIdStatus.ErrorCodes -ccontains 'INSTALLATION_ID_MISSING') `
        'DM-P1-DETECT-MISSING-ID' 'Missing installation_id was not reported.'

    $invalidSyncEnv = New-TestEnvironment -Root $detectorRoot -Name 'InvalidSync' `
        -InstallationMode InvalidSync
    $invalidSyncStatus = Get-DaMaoUserDbEnvironmentStatus -RimeUserDir $invalidSyncEnv.User
    $script:detectorCaseCount++
    Assert-P1 ($invalidSyncStatus.ErrorCodes -ccontains 'SYNC_DIR_INVALID' -and
        $null -eq $invalidSyncStatus.SyncDir) `
        'DM-P1-DETECT-INVALID-SYNC' 'Invalid custom sync_dir was not rejected.'

    $missingSyncEnv = New-TestEnvironment -Root $detectorRoot -Name 'MissingSync'
    Remove-Item -LiteralPath $missingSyncEnv.Sync
    $missingSyncStatus = Get-DaMaoUserDbEnvironmentStatus -RimeUserDir $missingSyncEnv.User
    $script:detectorCaseCount++
    Assert-P1 ($missingSyncStatus.ErrorCodes -ccontains 'SYNC_DIR_NOT_FOUND') `
        'DM-P1-DETECT-MISSING-SYNC' 'A configured missing sync_dir was not reported.'

    $duplicateIdEnv = New-TestEnvironment -Root $detectorRoot -Name 'DuplicateId'
    Write-Utf8Text -Path (Join-Path $duplicateIdEnv.User 'installation.yaml') -Text (
        "installation_id: 'first-id'`n" +
        "installation_id: 'second-id'`n" +
        "sync_dir: '$($duplicateIdEnv.Sync)'`n" +
        "distribution_version: '0.17.4'`n" +
        "rime_version: '1.13.1'`n"
    )
    $duplicateIdStatus = Get-DaMaoUserDbEnvironmentStatus -RimeUserDir $duplicateIdEnv.User
    $script:detectorCaseCount++
    Assert-P1 ($duplicateIdStatus.ErrorCodes -ccontains 'INSTALLATION_ID_INVALID') `
        'DM-P1-DETECT-DUPLICATE-ID' 'Duplicate installation_id was not rejected.'

    $invalidIdEnv = New-TestEnvironment -Root $detectorRoot -Name 'InvalidId' `
        -InstallationId 'invalid/id'
    $invalidIdStatus = Get-DaMaoUserDbEnvironmentStatus -RimeUserDir $invalidIdEnv.User
    $script:detectorCaseCount++
    Assert-P1 ($invalidIdStatus.ErrorCodes -ccontains 'INSTALLATION_ID_INVALID') `
        'DM-P1-DETECT-INVALID-ID' 'Invalid installation_id was not rejected.'

    $mismatchEnv = New-TestEnvironment -Root $detectorRoot -Name 'HeaderMismatch'
    $mismatchDir = Join-Path $mismatchEnv.Sync 'foreign-machine'
    $mismatchSnapshot = Join-Path $mismatchDir 'damao_wubi.userdb.txt'
    Write-Utf8Text -Path $mismatchSnapshot -Text (
        (New-SnapshotHeader -DbName 'damao_wubi_alpha03' -UserId 'foreign-machine') +
        "abcd `tword`tc=1 d=1 t=1`n"
    )
    $mismatchStatus = Get-DaMaoUserDbEnvironmentStatus -RimeUserDir $mismatchEnv.User
    $script:detectorCaseCount++
    $mismatchDb = Get-DatabaseStatus $mismatchStatus 'damao_wubi'
    Assert-P1 ($mismatchDb.State -ceq 'Ambiguous' -and
        $mismatchDb.ErrorCodes -ccontains 'SNAPSHOT_FILENAME_DB_NAME_MISMATCH') `
        'DM-P1-DETECT-HEADER-MISMATCH' 'Snapshot filename/header conflict was not fail closed.'

    $unknownVersionEnv = New-TestEnvironment -Root $detectorRoot -Name 'UnknownVersion' `
        -RimeVersion '1.14.0'
    $unknownVersionStatus = Get-DaMaoUserDbEnvironmentStatus `
        -RimeUserDir $unknownVersionEnv.User
    $script:detectorCaseCount++
    Assert-P1 ($unknownVersionStatus.LibrimeVersionStatus -ceq 'UnknownVersion' -and
        -not $unknownVersionStatus.SnapshotFormatVerified -and
        $unknownVersionStatus.ErrorCodes -ccontains 'LIBRIME_VERSION_UNVERIFIED') `
        'DM-P1-DETECT-UNKNOWN-VERSION' 'Unknown librime version did not disable format capability.'
    $unsupportedVersion = Get-DaMaoVersionAssessment -Version '1.12.0' -Product librime
    $notDetectedVersion = Get-DaMaoVersionAssessment -Version $null -Product librime
    Assert-P1 ($unsupportedVersion.Status -ceq 'Unsupported' -and
        $notDetectedVersion.Status -ceq 'NotDetected') 'DM-P1-DETECT-VERSION-STATES' `
        'Unsupported and NotDetected version states are not distinct.'

    $missingUserPath = Join-Path $detectorRoot 'NoSuchMachine\user'
    $missingUserStatus = Get-DaMaoUserDbEnvironmentStatus -RimeUserDir $missingUserPath
    $script:detectorCaseCount++
    Assert-P1 ($missingUserStatus.ErrorCodes -ccontains 'RIME_USER_DIR_NOT_FOUND') `
        'DM-P1-DETECT-MISSING-USER-DIR' 'Missing Rime user directory was not reported.'

    $machineA = New-TestEnvironment -Root $detectorRoot -Name 'Machine-A' `
        -InstallationId 'machine-a-id'
    $machineB = New-TestEnvironment -Root $detectorRoot -Name 'Machine-B' `
        -InstallationId 'machine-b-id'
    [void](New-Item -ItemType Directory -Path (Join-Path $machineB.User 'damao_wubi.userdb'))
    $machineASnapshot = Add-TestSnapshot -Environment $machineB -DbName 'damao_wubi' `
        -SourceInstallationId $machineA.InstallationId -Phrase $privacySentinel
    $machineBStatus = Get-DaMaoUserDbEnvironmentStatus -RimeUserDir $machineB.User
    $script:detectorCaseCount++
    $machineBDb = Get-DatabaseStatus $machineBStatus 'damao_wubi'
    Assert-P1 ($machineBStatus.InstallationId -ceq 'machine-b-id' -and
        $machineBDb.State -ceq 'LiveDb' -and
        $machineBDb.Snapshots[0].UserId -ceq 'machine-a-id' -and
        $machineBDb.Snapshots[0].Path -ceq $machineASnapshot) `
        'DM-P1-DETECT-MACHINE-ISOLATION' `
        'Machine-A snapshot identity was conflated with Machine-B installation/live identity.'

    $statusScript = Join-Path $repoRoot 'scripts\Get-DaMaoUserDbStatus.ps1'
    $capturedStatus = (& $statusScript -RimeUserDir $machineB.User -AsJson 2>&1 | Out-String)
    $script:privacyCaseCount++
    Assert-P1 ($capturedStatus -notmatch [regex]::Escape($privacySentinel)) `
        'DM-P1-PRIVACY-STATUS' 'Default status stdout/stderr leaked phrase text.'

    $badPrivacyPath = New-SnapshotFixture -Root $parserRoot -CaseName 'privacy-error' `
        -Text ((New-SnapshotHeader) + "abcd `t$privacySentinel`tc=bad d=1 t=1`n")
    $badPrivacy = Read-DaMaoUserDbSnapshot -Path $badPrivacyPath
    $badPrivacySerialized = $badPrivacy | ConvertTo-Json -Depth 8 -Compress
    $script:privacyCaseCount++
    Assert-P1 ($badPrivacySerialized -notmatch [regex]::Escape($privacySentinel)) `
        'DM-P1-PRIVACY-ERROR' 'Parser error serialization leaked the bad line.'

    $freezeEnd = Assert-PublicBaselineP1
    Assert-P1 ($freezeStart -eq 17 -and $freezeEnd -eq 17) 'DM-P1-FREEZE-02' `
        'Public Baseline V1 did not remain 17/17 through P1 tests.'

    $fingerprintSource = 'parser=' + $script:parserCaseCount +
        ';detector=' + $script:detectorCaseCount +
        ';privacy=' + $script:privacyCaseCount +
        ';states=' + (@($stateFingerprintParts) -join ',')
    $fingerprintBytes = ([System.Text.UTF8Encoding]::new($false)).GetBytes($fingerprintSource)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $fingerprint = ([System.BitConverter]::ToString(
                $sha.ComputeHash($fingerprintBytes)
            )).Replace('-', '')
    }
    finally {
        $sha.Dispose()
    }

    Write-Host ('DaMao UserDB Portability P1 tests passed. ' +
        "Assertions=$script:assertionCount ParserCases=$script:parserCaseCount " +
        "DetectorCases=$script:detectorCaseCount PrivacyCases=$script:privacyCaseCount " +
        "Freeze=17/17 Fingerprint=$fingerprint PowerShell=$($PSVersionTable.PSVersion)")
}
finally {
    if (Test-Path -LiteralPath $testRootFull) {
        $verifiedTestRoot = [System.IO.Path]::GetFullPath($testRootFull)
        if (-not $verifiedTestRoot.StartsWith(
                $tempRootFull + [System.IO.Path]::DirectorySeparatorChar,
                [System.StringComparison]::OrdinalIgnoreCase
            )) {
            throw 'Refusing to remove a test directory outside the system temporary directory.'
        }
        Remove-Item -LiteralPath $verifiedTestRoot -Recurse -Force
    }
}
