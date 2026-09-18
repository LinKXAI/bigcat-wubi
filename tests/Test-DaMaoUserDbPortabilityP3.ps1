[CmdletBinding()]
param(
    [AllowNull()][string]$RimeDll,
    [switch]$HermeticOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot 'scripts\DaMao.UserDbPortabilityP3.ps1')
. (Join-Path $PSScriptRoot 'DaMao.PortabilityBaseline.ps1')

$script:assertionCount = 0
$script:preflightCaseCount = 0
$script:nativeCaseCount = 0
$script:failureCaseCount = 0
$script:privacyCaseCount = 0
$script:preflightZeroMutationCases = 0
$script:matrix = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::Ordinal
)

function Assert-P3 {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Message
    )
    $script:assertionCount++
    if (-not $Condition) { throw "[$Code] $Message" }
}

function Add-MatrixP3 {
    param([Parameter(Mandatory = $true)][string]$Name)
    [void]$script:matrix.Add($Name)
}

function Write-Utf8P3 {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text
    )
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force)
    [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false))
}

function Write-InstallationP3 {
    param(
        [Parameter(Mandatory = $true)][string]$UserDir,
        [Parameter(Mandatory = $true)][string]$InstallationId,
        [Parameter(Mandatory = $true)][string]$SyncDir
    )
    $portableSync = [System.IO.Path]::GetFullPath($SyncDir).Replace('\', '/')
    Write-Utf8P3 -Path (Join-Path $UserDir 'installation.yaml') -Text (
        "installation_id: '$InstallationId'`n" +
        "sync_dir: '$portableSync'`n" +
        "distribution_code_name: 'Weasel'`n" +
        "distribution_version: '0.17.4'`n" +
        "rime_version: '1.13.1'`n"
    )
}

function Write-DefaultP3 {
    param([Parameter(Mandatory = $true)][string]$SharedDir)
    Write-Utf8P3 -Path (Join-Path $SharedDir 'default.yaml') -Text (
        "config_version: '1'`nschema_list:`n" +
        "  - schema: damao_wubi_alpha03`n" +
        "  - schema: damao_wubi`nmenu:`n  page_size: 9`n"
    )
}

function Write-SchemaP3 {
    param(
        [Parameter(Mandatory = $true)][string]$UserDir,
        [Parameter(Mandatory = $true)][string]$DbName,
        [Parameter(Mandatory = $true)][object[]]$DictionaryEntries
    )
    Write-Utf8P3 -Path (Join-Path $UserDir ($DbName + '.schema.yaml')) -Text (
        "schema:`n  schema_id: $DbName`n  name: P3 Synthetic Fixture`n  version: '1'`n" +
        "engine:`n  processors: [speller, selector, navigator, express_editor]`n" +
        "  segmentors: [abc_segmentor]`n  translators: [table_translator]`n" +
        "speller:`n  alphabet: abcdefghijklmnopqrstuvwxyz`n" +
        "translator:`n  dictionary: $DbName`n  enable_user_dict: true`n" +
        "  enable_sentence: false`n"
    )
    $rows = New-Object System.Text.StringBuilder
    [void]$rows.Append("---`nname: $DbName`nversion: '1'`nsort: original`n...`n")
    foreach ($entry in $DictionaryEntries) {
        [void]$rows.Append(([string]$entry.Phrase + "`t" + [string]$entry.Code + "`t" +
                [string]$entry.Weight + "`n"))
    }
    Write-Utf8P3 -Path (Join-Path $UserDir ($DbName + '.dict.yaml')) -Text $rows.ToString()
}

function Write-SnapshotP3 {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$DbName,
        [Parameter(Mandatory = $true)][string]$UserId,
        [Parameter(Mandatory = $true)][uint64]$Tick,
        [Parameter(Mandatory = $true)][object[]]$Entries
    )
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append("# Rime user dictionary`n")
    [void]$builder.Append("#@/db_name`t$DbName`n")
    [void]$builder.Append("#@/db_type`tuserdb`n")
    [void]$builder.Append("#@/rime_version`t1.13.1`n")
    [void]$builder.Append("#@/tick`t$Tick`n")
    [void]$builder.Append("#@/user_id`t$UserId`n")
    foreach ($entry in $Entries) {
        [void]$builder.Append(([string]$entry.Code + "`t" + [string]$entry.Phrase +
                "`tc=" + [string]$entry.C + " d=" + [string]$entry.D +
                " t=" + [string]$entry.T + "`n"))
    }
    Write-Utf8P3 -Path $Path -Text $builder.ToString()
}

function Assert-PublicBaselineP3 {
    $contract = Get-DaMaoPublicBaseline -RepositoryRoot $repoRoot
    $files = @($contract.current_file_integrity.files)
    $failures = @(Test-DaMaoPublicBaselineManifest -RepositoryRoot $repoRoot -Files $files)
    Assert-P3 ($files.Count -eq 17 -and $failures.Count -eq 0) `
        'DM-P3-CURRENT-BASELINE' `
        "Public Baseline V1 failed: $($failures -join '; ')"
    return 17
}

function Get-PackagePartsP3 {
    param([Parameter(Mandatory = $true)][string]$Path)
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $result = @{}
        foreach ($entry in $zip.Entries) {
            $stream = $entry.Open()
            $memory = New-Object System.IO.MemoryStream
            try { $stream.CopyTo($memory); $result[$entry.FullName] = $memory.ToArray() }
            finally { $memory.Dispose(); $stream.Dispose() }
        }
        return $result
    }
    finally { $zip.Dispose() }
}

function New-ZipP3 {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object[]]$Entries
    )
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force)
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::CreateNew)
    try {
        $zip = New-Object System.IO.Compression.ZipArchive(
            $stream, [System.IO.Compression.ZipArchiveMode]::Create, $true
        )
        try {
            foreach ($item in $Entries) {
                $entry = $zip.CreateEntry([string]$item.Name)
                if ($item.PSObject.Properties.Name -contains 'ExternalAttributes') {
                    $entry.ExternalAttributes = [int]$item.ExternalAttributes
                }
                $entryStream = $entry.Open()
                try {
                    [byte[]]$bytes = $item.Bytes
                    $entryStream.Write($bytes, 0, $bytes.Length)
                }
                finally { $entryStream.Dispose() }
            }
        }
        finally { $zip.Dispose() }
    }
    finally { $stream.Dispose() }
}

function ConvertTo-ManifestBytesP3 {
    param([Parameter(Mandatory = $true)]$Manifest)
    $json = $Manifest | ConvertTo-Json -Depth 10
    return [System.Text.UTF8Encoding]::new($false).GetBytes($json)
}

function Copy-ManifestP3 {
    param([Parameter(Mandatory = $true)]$Manifest)
    return (($Manifest | ConvertTo-Json -Depth 10) | ConvertFrom-Json)
}

function Assert-PreflightRejectedP3 {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedCode,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][int]$RestoreCallsBefore,
        [Parameter(Mandatory = $true)][string[]]$Sentinels
    )
    $message = $null
    $errorRecordText = $null
    $before = Get-DaMaoP3OperationCounters
    $probeRoot = Join-Path (Split-Path -Parent $Path) 'must-not-be-used'
    try {
        [void](Restore-DaMaoUserDbPackageV2 -PackagePath $Path `
            -RimeUserDir (Join-Path $probeRoot 'user') `
            -RimeDll (Join-Path $probeRoot 'rime.dll') `
            -RimeSharedDataDir (Join-Path $probeRoot 'shared') `
            -WeaselRoot $probeRoot -Synthetic)
    }
    catch {
        $message = $_.Exception.Message
        $errorRecordText = ($_ | Out-String)
    }
    $after = Get-DaMaoP3OperationCounters
    $script:preflightCaseCount++
    $script:failureCaseCount++
    Assert-P3 ($null -ne $message -and $message -match
        ('^\[' + [regex]::Escape($ExpectedCode) + '\]')) `
        ('DM-P3-PREFLIGHT-' + $Name) 'A corrupt package did not fail with the expected code.'
    Assert-P3 ($after.RestoreCallCount -eq $RestoreCallsBefore -and
        $after.RestoreCallCount -eq $before.RestoreCallCount -and
        $after.BackupCallCount -eq $before.BackupCallCount -and
        $after.MaintenanceEntryCount -eq $before.MaintenanceEntryCount -and
        $after.NativeMutationSessionCount -eq $before.NativeMutationSessionCount -and
        $after.MutationCapableApiCount -eq $before.MutationCapableApiCount) `
        ('DM-P3-PREMUTATION-' + $Name) `
        'A corrupt package reached maintenance, backup, or restore.'
    $script:preflightZeroMutationCases++
    foreach ($sentinel in $Sentinels) {
        Assert-P3 ($message -notmatch [regex]::Escape($sentinel) -and
            $errorRecordText -notmatch [regex]::Escape($sentinel)) `
            ('DM-P3-PRIVACY-' + $Name) 'A preflight error leaked dictionary content.'
        $script:privacyCaseCount++
    }
}

function Invoke-HermeticP3 {
    param([Parameter(Mandatory = $true)][string]$Root)
    $freeze = Assert-PublicBaselineP3
    Import-DaMaoRimeRestoreAdapter
    Assert-P3 ([DaMaoRimeRestoreAdapter]::SupportedArchitecture -ceq 'x64' -and
        [IntPtr]::Size -eq 8) 'DM-P3-HERMETIC-ARCH' `
        'P3 is not running under the validated x64 architecture contract.'
    foreach ($source in @(
            'scripts\DaMao.UserDbPortabilityP3.ps1',
            'scripts\DaMao.RimeRestoreAdapter.cs',
            'scripts\Restore-DaMaoUserDbPackageV2.ps1',
            'tests\DaMaoRimeP3FixtureNative.cs',
            'tests\Test-DaMaoUserDbPortabilityP3.ps1'
        )) {
        [byte[]]$bytes = [System.IO.File]::ReadAllBytes((Join-Path $repoRoot $source))
        Assert-P3 (@($bytes | Where-Object { $_ -gt 0x7f }).Count -eq 0) `
            'DM-P3-SOURCE-ENCODING' 'P3 PowerShell/C# sources are not ASCII-safe.'
    }

    [void](New-Item -ItemType Directory -Path $Root)
    $sentinel = 'P3_HERMETIC_PRIVATE_SENTINEL'
    $preflightSentinels = @($sentinel, 'zzzz', 'source-a')
    $snapshot = Join-Path $Root 'damao_wubi.userdb.txt'
    Write-SnapshotP3 -Path $snapshot -DbName 'damao_wubi' -UserId 'source-a' `
        -Tick 20 -Entries @(
            [pscustomobject]@{ Code = 'zzzz '; Phrase = $sentinel; C = 3; D = '4.5'; T = 18 }
        )
    $validPackage = New-DaMaoUserDbPackageV2FromSnapshot -SnapshotPath $snapshot `
        -DbName 'damao_wubi' -OutputDirectory (Join-Path $Root 'valid') `
        -SourceLibrimeVersion '1.13.1' -SourceWeaselVersion '0.17.4'
    $validPreflight = Read-DaMaoUserDbPackageV2ForRestore $validPackage.PackagePath
    try {
        Assert-P3 ($validPreflight.Status -ceq 'Verified' -and
            $validPreflight.Parsed.StructuralHealth -ceq 'Healthy' -and
            $validPreflight.Parsed.EntryCount -eq 1 -and
            $validPreflight.SnapshotSha256 -ceq $validPackage.SnapshotSha256) `
            'DM-P3-VALID-PREFLIGHT' 'A valid Package V2 did not pass restore preflight.'
        $manifest = $validPreflight.Manifest
    }
    finally { Remove-DaMaoP3Preflight $validPreflight }
    $parts = Get-PackagePartsP3 $validPackage.PackagePath
    [byte[]]$snapshotBytes = $parts['snapshots/damao_wubi.userdb.txt']
    $calls = [DaMaoRimeRestoreAdapter]::RestoreCallCount
    $badRoot = Join-Path $Root 'corrupt'
    [void](New-Item -ItemType Directory -Path $badRoot)

    [byte[]]$validZipBytes = [System.IO.File]::ReadAllBytes($validPackage.PackagePath)
    $truncated = Join-Path $badRoot 'truncated.zip'
    [System.IO.File]::WriteAllBytes($truncated,
        $validZipBytes[0..([math]::Floor($validZipBytes.Length / 2))])
    Assert-PreflightRejectedP3 $truncated 'P3_PACKAGE_INVALID' 'TRUNCATED' `
        $calls $preflightSentinels

    $cases = New-Object 'System.Collections.Generic.List[object]'
    $badHash = Copy-ManifestP3 $manifest; $badHash.SnapshotSha256 = '0' * 64
    $cases.Add([pscustomobject]@{ Name='HASH'; Code='P3_PACKAGE_CONTENT_MISMATCH'; Manifest=$badHash; Snapshot=$snapshotBytes; SnapshotName='snapshots/damao_wubi.userdb.txt'; Extra=$null })
    [byte[]]$changedSnapshot = $snapshotBytes.Clone(); $changedSnapshot[$changedSnapshot.Length - 2] = 0x58
    $cases.Add([pscustomobject]@{ Name='SNAPSHOT-MODIFIED'; Code='P3_PACKAGE_CONTENT_MISMATCH'; Manifest=$manifest; Snapshot=$changedSnapshot; SnapshotName='snapshots/damao_wubi.userdb.txt'; Extra=$null })
    $badDb = Copy-ManifestP3 $manifest; $badDb.DbName = 'damao_wubi_alpha03'
    $cases.Add([pscustomobject]@{ Name='DB-MISMATCH'; Code='P3_PACKAGE_CONTENT_MISMATCH'; Manifest=$badDb; Snapshot=$snapshotBytes; SnapshotName='snapshots/damao_wubi.userdb.txt'; Extra=$null })
    $badVersion = Copy-ManifestP3 $manifest; $badVersion.PackageFormatVersion = 3
    $cases.Add([pscustomobject]@{ Name='VERSION'; Code='P3_PACKAGE_INVALID'; Manifest=$badVersion; Snapshot=$snapshotBytes; SnapshotName='snapshots/damao_wubi.userdb.txt'; Extra=$null })
    $autoMerge = Copy-ManifestP3 $manifest; $autoMerge.AutomaticMerge = $true
    $cases.Add([pscustomobject]@{ Name='AUTO-MERGE'; Code='P3_PACKAGE_INVALID'; Manifest=$autoMerge; Snapshot=$snapshotBytes; SnapshotName='snapshots/damao_wubi.userdb.txt'; Extra=$null })
    $autoRename = Copy-ManifestP3 $manifest; $autoRename.AutomaticRename = $true
    $cases.Add([pscustomobject]@{ Name='AUTO-RENAME'; Code='P3_PACKAGE_INVALID'; Manifest=$autoRename; Snapshot=$snapshotBytes; SnapshotName='snapshots/damao_wubi.userdb.txt'; Extra=$null })
    foreach ($case in $cases) {
        $path = Join-Path $badRoot ($case.Name + '.zip')
        $entries = @(
            [pscustomobject]@{ Name='manifest.json'; Bytes=(ConvertTo-ManifestBytesP3 $case.Manifest) },
            [pscustomobject]@{ Name=$case.SnapshotName; Bytes=$case.Snapshot }
        )
        New-ZipP3 $path $entries
        Assert-PreflightRejectedP3 $path $case.Code $case.Name $calls $preflightSentinels
    }

    $invalidUtf8 = Join-Path $badRoot 'invalid-utf8.zip'
    [byte[]]$invalidBytes = @(0x23,0x20,0x52,0x69,0x6d,0x65,0x20,0xff,0x0a)
    $invalidManifest = Copy-ManifestP3 $manifest
    $invalidManifest.SnapshotSha256 = Get-DaMaoP3BytesSha256 $invalidBytes
    $invalidManifest.SnapshotByteLength = $invalidBytes.Length
    New-ZipP3 $invalidUtf8 @(
        [pscustomobject]@{Name='manifest.json';Bytes=(ConvertTo-ManifestBytesP3 $invalidManifest)},
        [pscustomobject]@{Name='snapshots/damao_wubi.userdb.txt';Bytes=$invalidBytes}
    )
    Assert-PreflightRejectedP3 $invalidUtf8 'P3_PACKAGE_CONTENT_MISMATCH' `
        'INVALID-UTF8' $calls $preflightSentinels

    $parserInvalid = Join-Path $badRoot 'parser-invalid.zip'
    [byte[]]$parserBytes = [System.Text.UTF8Encoding]::new($false).GetBytes(
        "# Rime user dictionary`n#@/db_name`tdamao_wubi`n"
    )
    $parserManifest = Copy-ManifestP3 $manifest
    $parserManifest.SnapshotSha256 = Get-DaMaoP3BytesSha256 $parserBytes
    $parserManifest.SnapshotByteLength = $parserBytes.Length
    New-ZipP3 $parserInvalid @(
        [pscustomobject]@{Name='manifest.json';Bytes=(ConvertTo-ManifestBytesP3 $parserManifest)},
        [pscustomobject]@{Name='snapshots/damao_wubi.userdb.txt';Bytes=$parserBytes}
    )
    Assert-PreflightRejectedP3 $parserInvalid 'P3_PACKAGE_CONTENT_MISMATCH' `
        'P1-INVALID' $calls $preflightSentinels

    foreach ($identityCase in @(
            [pscustomobject]@{Name='UNKNOWN';Db='unknown_db';Code='P3_TARGET_UNCLASSIFIED'},
            [pscustomobject]@{Name='PINYIN';Db='damao_wubi_pinyin';Code='P3_TARGET_EXCLUDED'}
        )) {
        $identityManifest = Copy-ManifestP3 $manifest
        $identityManifest.DbName = $identityCase.Db
        $identityManifest.SnapshotFile = 'snapshots/' + $identityCase.Db + '.userdb.txt'
        $identityManifest.SnapshotDbName = $identityCase.Db
        $identityManifest.SchemaIdentities = @($identityCase.Db)
        $identitySnapshotPath = Join-Path $badRoot ($identityCase.Db + '.userdb.txt')
        Write-SnapshotP3 -Path $identitySnapshotPath -DbName $identityCase.Db `
            -UserId 'source-a' -Tick 20 -Entries @(
                [pscustomobject]@{Code='zzzz ';Phrase=$sentinel;C=3;D='4.5';T=18}
            )
        [byte[]]$identitySnapshotBytes = [System.IO.File]::ReadAllBytes($identitySnapshotPath)
        $identityManifest.SnapshotSha256 = Get-DaMaoP3BytesSha256 $identitySnapshotBytes
        $identityManifest.SnapshotByteLength = $identitySnapshotBytes.Length
        $path = Join-Path $badRoot ($identityCase.Name + '.zip')
        New-ZipP3 $path @(
            [pscustomobject]@{Name='manifest.json';Bytes=(ConvertTo-ManifestBytesP3 $identityManifest)},
            [pscustomobject]@{Name=$identityManifest.SnapshotFile;Bytes=$identitySnapshotBytes}
        )
        Assert-PreflightRejectedP3 $path $identityCase.Code $identityCase.Name `
            $calls $preflightSentinels
    }

    foreach ($layout in @(
            [pscustomobject]@{Name='EXTRA';Entries=@(
                    [pscustomobject]@{Name='manifest.json';Bytes=(ConvertTo-ManifestBytesP3 $manifest)},
                    [pscustomobject]@{Name='snapshots/damao_wubi.userdb.txt';Bytes=$snapshotBytes},
                    [pscustomobject]@{Name='extra.txt';Bytes=[byte[]]@(1)})},
            [pscustomobject]@{Name='DUPLICATE';Entries=@(
                    [pscustomobject]@{Name='manifest.json';Bytes=(ConvertTo-ManifestBytesP3 $manifest)},
                    [pscustomobject]@{Name='manifest.json';Bytes=(ConvertTo-ManifestBytesP3 $manifest)})},
            [pscustomobject]@{Name='TRAVERSAL';Entries=@(
                    [pscustomobject]@{Name='manifest.json';Bytes=(ConvertTo-ManifestBytesP3 $manifest)},
                    [pscustomobject]@{Name='../damao_wubi.userdb.txt';Bytes=$snapshotBytes})},
            [pscustomobject]@{Name='MISSING-MANIFEST';Entries=@(
                    [pscustomobject]@{Name='other.json';Bytes=(ConvertTo-ManifestBytesP3 $manifest)},
                    [pscustomobject]@{Name='snapshots/damao_wubi.userdb.txt';Bytes=$snapshotBytes})}
        )) {
        $path = Join-Path $badRoot ($layout.Name + '.zip')
        New-ZipP3 $path $layout.Entries
        Assert-PreflightRejectedP3 $path 'P3_PACKAGE_INVALID' $layout.Name `
            $calls $preflightSentinels
    }
    $symlink = Join-Path $badRoot 'symlink.zip'
    New-ZipP3 $symlink @(
        [pscustomobject]@{Name='manifest.json';Bytes=(ConvertTo-ManifestBytesP3 $manifest)},
        [pscustomobject]@{Name='snapshots/damao_wubi.userdb.txt';Bytes=$snapshotBytes;ExternalAttributes=-1610612736}
    )
    Assert-PreflightRejectedP3 $symlink 'P3_PACKAGE_INVALID' 'SYMLINK' `
        $calls $preflightSentinels

    Assert-P3 ([DaMaoRimeRestoreAdapter]::RestoreCallCount -eq $calls) `
        'DM-P3-PREFLIGHT-CALLCOUNT' 'Corrupt preflight cases invoked native restore.'
    return $freeze
}

function Invoke-FixtureRuntimeP3 {
    param(
        [Parameter(Mandatory = $true)][string]$RimeDll,
        [Parameter(Mandatory = $true)][string]$SharedDir,
        [Parameter(Mandatory = $true)][string]$UserDir,
        [switch]$Deploy,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )
    [DaMaoRimeP3FixtureNative]::Load($RimeDll, $SharedDir, $UserDir,
        (Join-Path $UserDir 'build'))
    try {
        if ($Deploy) {
            Assert-P3 ([DaMaoRimeP3FixtureNative]::Deploy()) 'DM-P3-FIXTURE-DEPLOY' `
                'A synthetic target schema did not deploy.'
        }
        [DaMaoRimeP3FixtureNative]::Start()
        & $Action
    }
    finally { [DaMaoRimeP3FixtureNative]::Shutdown() }
}

function Initialize-MachineP3 {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$InstallationId,
        [Parameter(Mandatory = $true)][object[]]$DictionaryEntries
    )
    $user = Join-Path $Root 'user'
    $shared = Join-Path $Root 'shared'
    $sync = Join-Path $Root 'sync'
    [void](New-Item -ItemType Directory -Path $user,$shared,$sync,(Join-Path $user 'build'))
    Write-DefaultP3 -SharedDir $shared
    Write-InstallationP3 -UserDir $user -InstallationId $InstallationId -SyncDir $sync
    foreach ($db in @('damao_wubi_alpha03', 'damao_wubi')) {
        Write-SchemaP3 -UserDir $user -DbName $db -DictionaryEntries $DictionaryEntries
    }
    return [pscustomobject]@{ Root=$Root; User=$user; Shared=$shared; Sync=$sync; Id=$InstallationId }
}

function Assert-ReceiptPrivacyP3 {
    param(
        [Parameter(Mandatory = $true)]$Receipt,
        [Parameter(Mandatory = $true)][string[]]$Sentinels,
        [Parameter(Mandatory = $true)][string]$Name
    )
    $json = ConvertTo-DaMaoP3ReceiptJson -Receipt $Receipt -Faults $null
    foreach ($sentinel in $Sentinels) {
        Assert-P3 ($json -notmatch [regex]::Escape($sentinel)) `
            ('DM-P3-RECEIPT-PRIVACY-' + $Name) `
            'A restore receipt leaked phrase, code, or logical-key content.'
        $script:privacyCaseCount++
    }
    Assert-P3 ($json -notmatch 'edc(?: |\\t)') `
        ('DM-P3-RECEIPT-PRIVACY-EXACT-CODE-' + $Name) `
        'A restore receipt leaked an input code or logical-key prefix.'
    $script:privacyCaseCount++
}

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
    ('damao-userdb-p3-tests-' + [guid]::NewGuid().ToString('N'))
$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
)
$testRoot = [System.IO.Path]::GetFullPath($testRoot)
Assert-P3 ($testRoot.StartsWith($tempRoot + [System.IO.Path]::DirectorySeparatorChar,
        [System.StringComparison]::OrdinalIgnoreCase)) 'DM-P3-TEMP-ROOT' `
    'The P3 test root is outside the system temporary directory.'

try {
    $freezeStart = Invoke-HermeticP3 -Root (Join-Path $testRoot 'hermetic')
    if ($HermeticOnly) {
        Write-Host ('DaMao UserDB Portability P3 hermetic tests passed. ' +
            "Assertions=$script:assertionCount PreflightCases=$script:preflightCaseCount " +
            "FailureCases=$script:failureCaseCount PrivacyCases=$script:privacyCaseCount " +
            "PreflightZeroMutation=$script:preflightZeroMutationCases/16 " +
            "Freeze=$freezeStart/17 NativeSkipped=1 " +
            "Reason=RealLibrimeRequiresControlledLocalWeasel " +
            "PowerShell=$($PSVersionTable.PSVersion)")
        return
    }

    $RimeDll = Resolve-DaMaoP2RimeDll -Path $RimeDll
    Add-Type -TypeDefinition ([System.IO.File]::ReadAllText(
            (Join-Path $PSScriptRoot 'DaMaoRimeP3FixtureNative.cs'))) -Language CSharp

    $baseSingle = [string][char]0x7532
    $learnedSingle = [string][char]0x4E59
    $phrase2 = ([string][char]0x4E19) + ([string][char]0x4E01)
    $phrase3 = $phrase2 + ([string][char]0x620A)
    $phrase4 = $phrase3 + ([string][char]0x5DF1)
    $sourceTombstonePhrase = ([string][char]0x5E9A) + ([string][char]0x8F9B)
    $bothTombstonePhrase = ([string][char]0x58EC) + ([string][char]0x7678)
    $targetOnlyPhrase = ([string][char]0x5B50) + ([string][char]0x4E11)
    $existingPhrase = ([string][char]0x5BC5) + ([string][char]0x536F)
    $alphaOnlyPhrase = ([string][char]0x8FB0) + ([string][char]0x5DF3)
    $legacyOnlyPhrase = ([string][char]0x5348) + ([string][char]0x672A)
    $privacySentinels = @(
        $baseSingle, $learnedSingle, $phrase2, $phrase3, $phrase4,
        $sourceTombstonePhrase, $bothTombstonePhrase, $targetOnlyPhrase,
        $existingPhrase, $alphaOnlyPhrase, $legacyOnlyPhrase,
        'qaz', 'wsx', 'rfv', 'tgb', 'yhn', 'ujm', 'ikm', 'olm', 'pko',
        'machine-a-id', 'machine-b-id', 'machine-c-id', 'machine-unicode-id',
        'target-drift-id', 'source-drift-id', 'clean-partial-id', 'old-machine-id'
    )
    $dictionaryEntries = @(
        [pscustomobject]@{Phrase=$baseSingle;Code='qaz';Weight=100},
        [pscustomobject]@{Phrase=$learnedSingle;Code='qaz';Weight=90},
        [pscustomobject]@{Phrase=$phrase2;Code='wsx';Weight=100},
        [pscustomobject]@{Phrase=$phrase3;Code='edc';Weight=100},
        [pscustomobject]@{Phrase=$phrase4;Code='rfv';Weight=100},
        [pscustomobject]@{Phrase=$sourceTombstonePhrase;Code='tgb';Weight=100},
        [pscustomobject]@{Phrase=$bothTombstonePhrase;Code='yhn';Weight=100},
        [pscustomobject]@{Phrase=$targetOnlyPhrase;Code='ujm';Weight=100},
        [pscustomobject]@{Phrase=$existingPhrase;Code='ikm';Weight=100},
        [pscustomobject]@{Phrase=$alphaOnlyPhrase;Code='olm';Weight=100},
        [pscustomobject]@{Phrase=$legacyOnlyPhrase;Code='pko';Weight=100}
    )

    $nativeRoot = Join-Path $testRoot 'native'
    $sourceA = Initialize-MachineP3 -Root (Join-Path $nativeRoot 'machine-a') `
        -InstallationId 'machine-a-id' -DictionaryEntries $dictionaryEntries
    Invoke-FixtureRuntimeP3 -RimeDll $RimeDll -SharedDir $sourceA.Shared `
        -UserDir $sourceA.User -Deploy -Action {
            foreach ($db in @('damao_wubi_alpha03', 'damao_wubi')) {
                $session = [DaMaoRimeP3FixtureNative]::OpenSession($db)
                try {
                    [void][DaMaoRimeP3FixtureNative]::CommitAt($session, 'qaz', 1)
                    [void][DaMaoRimeP3FixtureNative]::CommitAt($session, 'qaz', 0)
                    [void][DaMaoRimeP3FixtureNative]::CommitAt($session, 'qaz', 0)
                    [void][DaMaoRimeP3FixtureNative]::CommitAt($session, 'wsx', 0)
                    [void][DaMaoRimeP3FixtureNative]::CommitAt($session, 'edc', 0)
                    [void][DaMaoRimeP3FixtureNative]::CommitAt($session, 'rfv', 0)
                    [void][DaMaoRimeP3FixtureNative]::CommitAt($session, 'tgb', 0)
                    Assert-P3 ([DaMaoRimeP3FixtureNative]::DeleteAt($session, 'tgb', 0)) `
                        'DM-P3-SOURCE-TOMBSTONE' 'Source tombstone learning failed.'
                    [void][DaMaoRimeP3FixtureNative]::CommitAt($session, 'yhn', 0)
                    Assert-P3 ([DaMaoRimeP3FixtureNative]::DeleteAt($session, 'yhn', 0)) `
                        'DM-P3-BOTH-TOMBSTONE-SOURCE' 'Source shared tombstone learning failed.'
                    if ($db -ceq 'damao_wubi_alpha03') {
                        [void][DaMaoRimeP3FixtureNative]::CommitAt($session, 'olm', 0)
                    }
                    else {
                        [void][DaMaoRimeP3FixtureNative]::CommitAt($session, 'pko', 0)
                    }
                }
                finally { [DaMaoRimeP3FixtureNative]::CloseSession($session) }
            }
        }
    $script:nativeCaseCount += 2

    $sourcePackages = @{}
    foreach ($db in @('damao_wubi_alpha03', 'damao_wubi')) {
        $sourcePackages[$db] = Backup-DaMaoUserDbPackageV2 -DbName $db `
            -OutputDirectory (Join-Path $sourceA.Root 'packages') `
            -RimeUserDir $sourceA.User -RimeDll $RimeDll `
            -RimeSharedDataDir $sourceA.Shared -Synthetic
    }

    $unicodeLeaf = 'unicode-' + [string][char]0x5927 + [string][char]0x732b + '-' +
        (('long-segment-' * 6).TrimEnd('-'))
    $machineUnicode = Initialize-MachineP3 -Root (Join-Path $nativeRoot $unicodeLeaf) `
        -InstallationId 'machine-unicode-id' -DictionaryEntries $dictionaryEntries
    $unicodeReceipt = Restore-DaMaoUserDbPackageV2 `
        -PackagePath $sourcePackages['damao_wubi'].PackagePath `
        -RimeUserDir $machineUnicode.User -RimeDll $RimeDll `
        -RimeSharedDataDir $machineUnicode.Shared -Synthetic
    Assert-P3 ($unicodeReceipt.Status -ceq 'Success' -and
        $unicodeReceipt.TargetStateBefore -ceq 'CleanTarget' -and
        $unicodeReceipt.PostRestoreVerificationStatus -ceq 'Verified' -and
        $unicodeReceipt.TargetUserIdentityBoundToCurrentMachine -and
        (Test-Path (Join-Path $machineUnicode.User 'damao_wubi.userdb') -PathType Container)) `
        'DM-P3-UNICODE-LONG-PATH' `
        'The production restore path did not survive a non-ASCII long target path.'
    Assert-ReceiptPrivacyP3 $unicodeReceipt $privacySentinels 'UNICODE-LONG-PATH'
    $script:nativeCaseCount++

    $driftMachine = Initialize-MachineP3 -Root (Join-Path $nativeRoot 'target-drift') `
        -InstallationId 'target-drift-id' -DictionaryEntries $dictionaryEntries
    $driftMarker = Join-Path $driftMachine.User 'damao_wubi.userdb.kct'
    $driftBefore = Get-DaMaoP3OperationCounters
    $driftError = $null
    try {
        [void](Restore-DaMaoUserDbPackageV2 `
            -PackagePath $sourcePackages['damao_wubi'].PackagePath `
            -RimeUserDir $driftMachine.User -RimeDll $RimeDll `
            -RimeSharedDataDir $driftMachine.Shared -Synthetic `
            -Faults @{AfterMaintenanceEntered={
                    [System.IO.File]::WriteAllBytes($driftMarker, [byte[]]@(1))
                }})
    }
    catch { $driftError = $_.Exception.Message }
    $driftAfter = Get-DaMaoP3OperationCounters
    Assert-P3 ($driftError -match '^\[P3_TARGET_STATE_CHANGED\]' -and
        $driftAfter.MaintenanceEntryCount -eq ($driftBefore.MaintenanceEntryCount + 1) -and
        $driftAfter.BackupCallCount -eq $driftBefore.BackupCallCount -and
        $driftAfter.NativeMutationSessionCount -eq $driftBefore.NativeMutationSessionCount -and
        $driftAfter.RestoreCallCount -eq $driftBefore.RestoreCallCount -and
        $driftAfter.MutationCapableApiCount -eq $driftBefore.MutationCapableApiCount) `
        'DM-P3-TARGET-DRIFT' `
        'Target-state drift did not fail closed before backup and restore.'
    $script:nativeCaseCount++; $script:failureCaseCount++

    $sourceDriftMachine = Initialize-MachineP3 `
        -Root (Join-Path $nativeRoot 'source-drift') `
        -InstallationId 'source-drift-id' -DictionaryEntries $dictionaryEntries
    $sourceDriftBefore = Get-DaMaoP3OperationCounters
    $sourceDriftReceipt = Restore-DaMaoUserDbPackageV2 `
        -PackagePath $sourcePackages['damao_wubi'].PackagePath `
        -RimeUserDir $sourceDriftMachine.User -RimeDll $RimeDll `
        -RimeSharedDataDir $sourceDriftMachine.Shared -Synthetic `
        -Faults @{RestoreSourceChanged=$true}
    $sourceDriftAfter = Get-DaMaoP3OperationCounters
    Assert-P3 ($sourceDriftReceipt.Status -ceq 'RestoreFailed' -and
        $sourceDriftReceipt.FailureCode -ceq 'P3_RESTORE_SOURCE_CHANGED' -and
        -not $sourceDriftReceipt.NativeRestoreAttempted -and
        -not $sourceDriftReceipt.NativeMutationSessionStarted -and
        -not $sourceDriftReceipt.TargetMayHaveBeenModified -and
        $sourceDriftReceipt.TargetStateAfterFailure -ceq 'CleanTarget' -and
        $sourceDriftAfter.RestoreCallCount -eq $sourceDriftBefore.RestoreCallCount -and
        -not (Test-Path (Join-Path $sourceDriftMachine.User 'damao_wubi.userdb'))) `
        'DM-P3-SOURCE-FINAL-BINDING' `
        'A changed extracted snapshot reached native restore or changed the clean target.'
    Assert-ReceiptPrivacyP3 $sourceDriftReceipt $privacySentinels 'SOURCE-FINAL-BINDING'
    $script:nativeCaseCount++; $script:failureCaseCount++

    $partialMachine = Initialize-MachineP3 -Root (Join-Path $nativeRoot 'clean-partial') `
        -InstallationId 'clean-partial-id' -DictionaryEntries $dictionaryEntries
    $cleanPartialReceipt = Restore-DaMaoUserDbPackageV2 `
        -PackagePath $sourcePackages['damao_wubi'].PackagePath `
        -RimeUserDir $partialMachine.User -RimeDll $RimeDll `
        -RimeSharedDataDir $partialMachine.Shared -Synthetic `
        -Faults @{RestoreFalseAfterCall=$true}
    Assert-P3 ($cleanPartialReceipt.Status -ceq 'RestoreFailedTargetMayBeModified' -and
        $cleanPartialReceipt.NativeRestoreAttempted -and
        $cleanPartialReceipt.NativeMutationSessionStarted -and
        $cleanPartialReceipt.TargetMayHaveBeenModified -and
        $cleanPartialReceipt.TargetStateAfterFailure -ceq 'LiveDb' -and
        $cleanPartialReceipt.PreRestoreSafetyBackupStatus -ceq 'NotApplicable_CleanTarget' -and
        $cleanPartialReceipt.ManualReviewRequired -and
        (Test-Path (Join-Path $partialMachine.User 'damao_wubi.userdb') -PathType Container)) `
        'DM-P3-CLEAN-PARTIAL-FAILURE' `
        'A clean-target partial failure was treated as unchanged or automatically deleted.'
    Assert-ReceiptPrivacyP3 $cleanPartialReceipt $privacySentinels 'CLEAN-PARTIAL'
    $script:nativeCaseCount++; $script:failureCaseCount++

    $machineB = Initialize-MachineP3 -Root (Join-Path $nativeRoot 'machine-b') `
        -InstallationId 'machine-b-id' -DictionaryEntries $dictionaryEntries
    Invoke-FixtureRuntimeP3 -RimeDll $RimeDll -SharedDir $machineB.Shared `
        -UserDir $machineB.User -Deploy -Action { }
    $oldSnapshot = Join-Path $machineB.Sync 'old-machine-id\damao_wubi.userdb.txt'
    Write-SnapshotP3 -Path $oldSnapshot -DbName 'damao_wubi' -UserId 'old-machine-id' `
        -Tick 8 -Entries @(
            [pscustomobject]@{Code='aaa ';Phrase='OLD_UNRELATED_PRIVATE';C=9;D='9';T=8}
        )
    $oldSnapshotHash = (Get-FileHash $oldSnapshot -Algorithm SHA256).Hash

    $cleanReceipts = @{}
    foreach ($db in @('damao_wubi', 'damao_wubi_alpha03')) {
        $receipt = Restore-DaMaoUserDbPackageV2 `
            -PackagePath $sourcePackages[$db].PackagePath `
            -RimeUserDir $machineB.User -RimeDll $RimeDll `
            -RimeSharedDataDir $machineB.Shared -Synthetic
        $cleanReceipts[$db] = $receipt
        Assert-P3 ($receipt.Status -ceq 'Success' -and
            $receipt.TargetStateBefore -ceq 'CleanTarget' -and
            $receipt.PreRestoreSafetyBackupStatus -ceq 'NotApplicable_CleanTarget' -and
            $receipt.NativeRestoreStatus -ceq 'Completed' -and
            $receipt.PostRestoreVerificationStatus -ceq 'Verified' -and
            $receipt.MissingCount -eq 0 -and
            $receipt.VerifiedPresentCount -eq $receipt.SourceEntryCount -and
            $receipt.TargetUserIdentityBoundToCurrentMachine -and
            $receipt.ObservedRimeApiDataSize -eq 788 -and
            $receipt.ObservedRimeLeversApiDataSize -eq 260) `
            'DM-P3-CLEAN-RESTORE' 'Clean-machine restore was not fully verified.'
        Assert-ReceiptPrivacyP3 $receipt $privacySentinels ('CLEAN-' + $db)
        $script:nativeCaseCount++
    }
    Assert-P3 ((Test-Path (Join-Path $machineB.User 'damao_wubi.userdb') -PathType Container) -and
        (Test-Path (Join-Path $machineB.User 'damao_wubi_alpha03.userdb') -PathType Container) -and
        (Get-FileHash $oldSnapshot -Algorithm SHA256).Hash -ceq $oldSnapshotHash) `
        'DM-P3-CLEAN-PHYSICAL' 'Separate physical DB creation or old-history isolation failed.'
    Add-MatrixP3 'A'; Add-MatrixP3 'I'; Add-MatrixP3 'J'; Add-MatrixP3 'K'
    Add-MatrixP3 'L'; Add-MatrixP3 'M'

    $separationPackages = @{}
    foreach ($db in @('damao_wubi', 'damao_wubi_alpha03')) {
        $separationPackages[$db] = Backup-DaMaoUserDbPackageV2 -DbName $db `
            -OutputDirectory (Join-Path $machineB.Root 'separation-audit') `
            -RimeUserDir $machineB.User -RimeDll $RimeDll `
            -RimeSharedDataDir $machineB.Shared -Synthetic
    }
    $script:nativeCaseCount += 2
    foreach ($db in @('damao_wubi', 'damao_wubi_alpha03')) {
        $probe = Read-DaMaoUserDbPackageV2ForRestore `
            -PackagePath $separationPackages[$db].PackagePath
        try {
            $keys = @($probe.Parsed.Entries | ForEach-Object { $_.Key })
            $alphaKey = 'olm ' + "`t" + $alphaOnlyPhrase
            $legacyKey = 'pko ' + "`t" + $legacyOnlyPhrase
            if ($db -ceq 'damao_wubi_alpha03') {
                Assert-P3 ($keys -ccontains $alphaKey -and $keys -cnotcontains $legacyKey) `
                    'DM-P3-NO-CROSS-ALPHA' 'The alpha03 restore crossed physical DB boundaries.'
            }
            else {
                Assert-P3 ($keys -ccontains $legacyKey -and $keys -cnotcontains $alphaKey) `
                    'DM-P3-NO-CROSS-LEGACY' 'The legacy restore crossed physical DB boundaries.'
            }
        }
        finally { Remove-DaMaoP3Preflight $probe }
    }

    Invoke-FixtureRuntimeP3 -RimeDll $RimeDll -SharedDir $machineB.Shared `
        -UserDir $machineB.User -Action {
            foreach ($db in @('damao_wubi', 'damao_wubi_alpha03')) {
                $session = [DaMaoRimeP3FixtureNative]::OpenSession($db)
                try {
                    $ranked = @([DaMaoRimeP3FixtureNative]::Candidates($session, 'qaz'))
                    $two = @([DaMaoRimeP3FixtureNative]::Candidates($session, 'wsx'))
                    $three = @([DaMaoRimeP3FixtureNative]::Candidates($session, 'edc'))
                    $four = @([DaMaoRimeP3FixtureNative]::Candidates($session, 'rfv'))
                    $existing = @([DaMaoRimeP3FixtureNative]::Candidates($session, 'ikm'))
                    Assert-P3 ($ranked.Count -ge 2 -and $ranked[0] -ceq $learnedSingle -and
                        $two -ccontains $phrase2 -and $three -ccontains $phrase3 -and
                        $four -ccontains $phrase4 -and $existing -ccontains $existingPhrase) `
                        'DM-P3-CANDIDATE-CLEAN' `
                        'Clean-machine candidate behavior did not preserve learned ordering and phrases.'
                }
                finally { [DaMaoRimeP3FixtureNative]::CloseSession($session) }
            }
        }
    $script:nativeCaseCount += 2

    $machineC = Initialize-MachineP3 -Root (Join-Path $nativeRoot 'machine-c') `
        -InstallationId 'machine-c-id' -DictionaryEntries $dictionaryEntries
    Invoke-FixtureRuntimeP3 -RimeDll $RimeDll -SharedDir $machineC.Shared `
        -UserDir $machineC.User -Deploy -Action {
            $session = [DaMaoRimeP3FixtureNative]::OpenSession('damao_wubi')
            try {
                Assert-P3 ([DaMaoRimeP3FixtureNative]::DeleteAt($session, 'qaz', 1)) `
                    'DM-P3-TARGET-TOMBSTONE' 'Target tombstone learning failed.'
                [void][DaMaoRimeP3FixtureNative]::CommitAt($session, 'tgb', 0)
                [void][DaMaoRimeP3FixtureNative]::CommitAt($session, 'yhn', 0)
                Assert-P3 ([DaMaoRimeP3FixtureNative]::DeleteAt($session, 'yhn', 0)) `
                    'DM-P3-BOTH-TOMBSTONE-TARGET' 'Target shared tombstone learning failed.'
                [void][DaMaoRimeP3FixtureNative]::CommitAt($session, 'ujm', 0)
                [void][DaMaoRimeP3FixtureNative]::CommitAt($session, 'wsx', 0)
            }
            finally { [DaMaoRimeP3FixtureNative]::CloseSession($session) }
        }
    $existingReceipt = Restore-DaMaoUserDbPackageV2 `
        -PackagePath $sourcePackages['damao_wubi'].PackagePath `
        -RimeUserDir $machineC.User -RimeDll $RimeDll `
        -RimeSharedDataDir $machineC.Shared -Synthetic
    Assert-P3 ($existingReceipt.Status -ceq 'Success' -and
        $existingReceipt.TargetStateBefore -ceq 'LiveDb' -and
        $existingReceipt.PreRestoreSafetyBackupStatus -ceq 'Completed' -and
        $existingReceipt.PreRestoreVerificationBaseline -ceq
            'CanonicalStateAfterSafetyBackup' -and
        $existingReceipt.SafetyBackupMutationCapability -ceq
            'PotentialMetadataMutation' -and
        $existingReceipt.MaintenanceContinuity -ceq 'SingleOuterWindow' -and
        (Test-Path $existingReceipt.PreRestoreSafetyBackupPath -PathType Leaf) -and
        $existingReceipt.ConflictResolvedCount -ge 4 -and
        $existingReceipt.TargetOnlyPreservedCount -ge 1 -and
        $existingReceipt.MissingCount -eq 0) `
        'DM-P3-EXISTING-MERGE' 'Existing-target merge or safety backup verification failed.'
    Assert-ReceiptPrivacyP3 $existingReceipt $privacySentinels 'EXISTING'
    $script:nativeCaseCount++
    Add-MatrixP3 'B'; Add-MatrixP3 'D'; Add-MatrixP3 'E'; Add-MatrixP3 'F'
    Add-MatrixP3 'G'; Add-MatrixP3 'H'

    $mergedProbe = Read-DaMaoUserDbPackageV2ForRestore `
        -PackagePath $existingReceipt.PostRestoreDiagnosticBackupPath
    try {
        $map = @{}
        foreach ($entry in @($mergedProbe.Parsed.Entries)) { $map[[string]$entry.Key] = $entry }
        $sourceTombKey = 'tgb ' + "`t" + $sourceTombstonePhrase
        $bothTombKey = 'yhn ' + "`t" + $bothTombstonePhrase
        $sourceLiveKey = 'qaz ' + "`t" + $learnedSingle
        $targetOnlyKey = 'ujm ' + "`t" + $targetOnlyPhrase
        Assert-P3 (-not $map[$sourceTombKey].IsTombstone -and
            $map[$bothTombKey].IsTombstone -and
            -not $map[$sourceLiveKey].IsTombstone -and
            $map.ContainsKey($targetOnlyKey)) `
            'DM-P3-TOMBSTONE-MATRIX' `
            'Observed tombstone/live conflict results disagree with librime 1.13.1.'
    }
    finally { Remove-DaMaoP3Preflight $mergedProbe }

    $continuityMarker = Join-Path $machineC.User 'damao_wubi.userdb.kct'
    $continuityBefore = Get-DaMaoP3OperationCounters
    $continuityError = $null
    try {
        [void](Restore-DaMaoUserDbPackageV2 `
            -PackagePath $sourcePackages['damao_wubi'].PackagePath `
            -RimeUserDir $machineC.User -RimeDll $RimeDll `
            -RimeSharedDataDir $machineC.Shared -Synthetic `
            -Faults @{AfterSafetyBackup={
                    [System.IO.File]::WriteAllBytes($continuityMarker, [byte[]]@(1))
                }})
    }
    catch { $continuityError = $_.Exception.Message }
    finally { Remove-Item -LiteralPath $continuityMarker -Force -ErrorAction SilentlyContinue }
    $continuityAfter = Get-DaMaoP3OperationCounters
    Assert-P3 ($continuityError -match '^\[P3_TARGET_STATE_CHANGED\]' -and
        $continuityAfter.MaintenanceEntryCount -eq
            ($continuityBefore.MaintenanceEntryCount + 1) -and
        $continuityAfter.BackupCallCount -eq ($continuityBefore.BackupCallCount + 1) -and
        $continuityAfter.NativeMutationSessionCount -eq
            $continuityBefore.NativeMutationSessionCount -and
        $continuityAfter.RestoreCallCount -eq $continuityBefore.RestoreCallCount) `
        'DM-P3-SAFETY-RESTORE-CONTINUITY' `
        'Target drift after the safety backup reached native restore.'
    $script:nativeCaseCount++; $script:failureCaseCount++

    $repeatReceipt = Restore-DaMaoUserDbPackageV2 `
        -PackagePath $sourcePackages['damao_wubi'].PackagePath `
        -RimeUserDir $machineC.User -RimeDll $RimeDll `
        -RimeSharedDataDir $machineC.Shared -Synthetic
    $repeatProbe = Read-DaMaoUserDbPackageV2ForRestore `
        -PackagePath $repeatReceipt.PostRestoreDiagnosticBackupPath
    try {
        Assert-P3 ($repeatReceipt.Status -ceq 'Success' -and
            $repeatReceipt.MissingCount -eq 0 -and
            $repeatProbe.Parsed.StructuralHealth -ceq 'Healthy' -and
            $repeatProbe.Parsed.DuplicateKeyCount -eq 0) `
            'DM-P3-REPEATED' 'Repeated restore was not safe under verified semantics.'
    }
    finally { Remove-DaMaoP3Preflight $repeatProbe }
    $script:nativeCaseCount++
    Add-MatrixP3 'C'

    $cliWarnings = @()
    $cliJson = & (Join-Path $repoRoot 'scripts\Restore-DaMaoUserDbPackageV2.ps1') `
        -PackagePath $sourcePackages['damao_wubi'].PackagePath `
        -RimeUserDir $machineC.User -RimeDll $RimeDll `
        -RimeSharedDataDir $machineC.Shared -Synthetic -AsJson `
        -WarningVariable cliWarnings
    $cliReceipt = @($cliJson) -join [Environment]::NewLine | ConvertFrom-Json
    $cliWarningText = @($cliWarnings) -join [Environment]::NewLine
    Assert-P3 ($cliReceipt.Status -ceq 'Success' -and
        $cliReceipt.PostRestoreVerificationStatus -ceq 'Verified' -and
        $cliWarningText -match 'merge-style mutation' -and
        $cliWarningText -match 'not a transactional rollback point') `
        'DM-P3-CLI-CONTRACT' `
        'The CLI did not return a verified receipt with the required merge/safety warning.'
    foreach ($sentinel in $privacySentinels) {
        Assert-P3 ((@($cliJson) -join [Environment]::NewLine) -notmatch
            [regex]::Escape($sentinel)) 'DM-P3-CLI-PRIVACY' `
            'The JSON CLI receipt leaked phrase, code, or logical-key content.'
        $script:privacyCaseCount++
    }
    Assert-P3 ((@($cliJson) -join [Environment]::NewLine) -notmatch
        'edc(?: |\\t)') 'DM-P3-CLI-PRIVACY-EXACT-CODE' `
        'The JSON CLI receipt leaked an input code or logical-key prefix.'
    $script:privacyCaseCount++
    $script:nativeCaseCount++

    Invoke-FixtureRuntimeP3 -RimeDll $RimeDll -SharedDir $machineC.Shared `
        -UserDir $machineC.User -Action {
            $session = [DaMaoRimeP3FixtureNative]::OpenSession('damao_wubi')
            try {
                $ranked = @([DaMaoRimeP3FixtureNative]::Candidates($session, 'qaz'))
                $targetOnly = @([DaMaoRimeP3FixtureNative]::Candidates($session, 'ujm'))
                Assert-P3 ($ranked[0] -ceq $learnedSingle -and
                    $targetOnly -ccontains $targetOnlyPhrase) `
                    'DM-P3-CANDIDATE-EXISTING' `
                    'Existing-target candidates lost learned ranking or target-only behavior.'
            }
            finally { [DaMaoRimeP3FixtureNative]::CloseSession($session) }
        }
    $script:nativeCaseCount++

    $callsBeforeFailure = [DaMaoRimeRestoreAdapter]::RestoreCallCount
    $nativeFailureReceipt = Restore-DaMaoUserDbPackageV2 `
        -PackagePath $sourcePackages['damao_wubi'].PackagePath `
        -RimeUserDir $machineC.User -RimeDll $RimeDll `
        -RimeSharedDataDir $machineC.Shared -Synthetic `
        -Faults @{ RestoreFalseAfterCall = $true }
    Assert-P3 ($nativeFailureReceipt.Status -ceq 'RestoreFailedTargetMayBeModified' -and
        $nativeFailureReceipt.NativeRestoreStatus -ceq 'Failed' -and
        $nativeFailureReceipt.NativeRestoreAttempted -and
        $nativeFailureReceipt.TargetMayHaveBeenModified -and
        $nativeFailureReceipt.TargetStateAfterFailure -ceq 'LiveDb' -and
        $nativeFailureReceipt.PreRestoreSafetyBackupStatus -ceq 'Completed' -and
        (Test-Path $nativeFailureReceipt.PreRestoreSafetyBackupPath -PathType Leaf) -and
        [string]::IsNullOrWhiteSpace($nativeFailureReceipt.PostRestoreDiagnosticBackupPath) -and
        $nativeFailureReceipt.ManualReviewRequired -and
        [DaMaoRimeRestoreAdapter]::RestoreCallCount -eq ($callsBeforeFailure + 1)) `
        'DM-P3-FAIL-AFTER-SAFETY' `
        'Native failure did not preserve safety evidence or attempted automatic rollback.'
    $script:nativeCaseCount++; $script:failureCaseCount++
    Add-MatrixP3 'N'

    $verificationFailure = Restore-DaMaoUserDbPackageV2 `
        -PackagePath $sourcePackages['damao_wubi'].PackagePath `
        -RimeUserDir $machineC.User -RimeDll $RimeDll `
        -RimeSharedDataDir $machineC.Shared -Synthetic `
        -Faults @{ SemanticMissing = $true }
    Assert-P3 ($verificationFailure.Status -ceq 'RestoreCompletedVerificationFailed' -and
        $verificationFailure.NativeRestoreStatus -ceq 'Completed' -and
        $verificationFailure.PostRestoreVerificationStatus -ceq 'Failed' -and
        (Test-Path $verificationFailure.PreRestoreSafetyBackupPath -PathType Leaf) -and
        (Test-Path $verificationFailure.PostRestoreDiagnosticBackupPath -PathType Leaf) -and
        $verificationFailure.ManualReviewRequired) `
        'DM-P3-VERIFY-FAILURE' `
        'Post-restore verification failure did not preserve diagnostic evidence.'
    $script:nativeCaseCount++; $script:failureCaseCount++
    Add-MatrixP3 'O'

    $callCount = [DaMaoRimeRestoreAdapter]::RestoreCallCount
    foreach ($throwingCase in @(
            [pscustomobject]@{Name='MAINTENANCE-ENTRY';Code='P3_MAINTENANCE_FAILED';Fault=@{MaintenanceEntry=$true}},
            [pscustomobject]@{Name='SAFETY-BACKUP';Code='P3_SAFETY_BACKUP_FAILED';Fault=@{SafetyBackup=$true}}
        )) {
        $message = $null
        try {
            [void](Restore-DaMaoUserDbPackageV2 `
                -PackagePath $sourcePackages['damao_wubi'].PackagePath `
                -RimeUserDir $machineC.User -RimeDll $RimeDll `
                -RimeSharedDataDir $machineC.Shared -Synthetic -Faults $throwingCase.Fault)
        }
        catch { $message = $_.Exception.Message }
        Assert-P3 ($message -match ('^\[' + $throwingCase.Code + '\]') -and
            [DaMaoRimeRestoreAdapter]::RestoreCallCount -eq $callCount) `
            ('DM-P3-' + $throwingCase.Name) `
            'A pre-native failure reached restore or returned the wrong failure.'
        $script:failureCaseCount++
    }

    foreach ($failure in @(
            [pscustomobject]@{Name='RESTORE-API';Fault=@{RestoreApiUnavailable=$true};Status='RestoreFailed';Code='P3_RESTORE_API_UNAVAILABLE'},
            [pscustomobject]@{Name='RESTORE-FALSE';Fault=@{RestoreFalse=$true};Status='RestoreFailedTargetMayBeModified';Code='P3_NATIVE_RESTORE_FAILED'},
            [pscustomobject]@{Name='RESTORE-EXCEPTION';Fault=@{RestoreException=$true};Status='RestoreFailedTargetMayBeModified';Code='P3_NATIVE_RESTORE_FAILED'},
            [pscustomobject]@{Name='FINALIZE';Fault=@{FinalizeFailure=$true};Status='RestoreFailedTargetMayBeModified';Code='P3_NATIVE_FINALIZE_FAILED'},
            [pscustomobject]@{Name='TARGET-REOPEN';Fault=@{TargetReopenFailure=$true};Status='RestoreFailedTargetMayBeModified';Code='P3_NATIVE_RESTORE_FAILED'},
            [pscustomobject]@{Name='POST-BACKUP';Fault=@{PostRestoreBackup=$true};Status='RestoreCompletedVerificationFailed';Code='P3_POST_RESTORE_BACKUP_FAILED'},
            [pscustomobject]@{Name='POST-PARSE';Fault=@{PostRestoreParse=$true};Status='RestoreCompletedVerificationFailed';Code='P3_POST_RESTORE_PARSE_FAILED'}
        )) {
        $failed = Restore-DaMaoUserDbPackageV2 `
            -PackagePath $sourcePackages['damao_wubi'].PackagePath `
            -RimeUserDir $machineC.User -RimeDll $RimeDll `
            -RimeSharedDataDir $machineC.Shared -Synthetic -Faults $failure.Fault
        Assert-P3 ($failed.Status -ceq $failure.Status -and
            $failed.FailureCode -ceq $failure.Code -and
            $failed.PreRestoreSafetyBackupStatus -ceq 'Completed' -and
            ($failure.Status -notlike 'RestoreFailed*' -or
                $failure.Name -eq 'RESTORE-API' -or
                ($failed.NativeRestoreAttempted -and $failed.TargetMayHaveBeenModified)) -and
            -not [DaMaoRimeRestoreAdapter]::IsInitialized) `
            ('DM-P3-FAILURE-' + $failure.Name) `
            'A native or post-restore failure was reported as success or leaked runtime state.'
        Assert-ReceiptPrivacyP3 $failed $privacySentinels $failure.Name
        $script:failureCaseCount++
    }

    $maintenanceWarning = Restore-DaMaoUserDbPackageV2 `
        -PackagePath $sourcePackages['damao_wubi'].PackagePath `
        -RimeUserDir $machineC.User -RimeDll $RimeDll `
        -RimeSharedDataDir $machineC.Shared -Synthetic `
        -Faults @{MaintenanceRestore=$true}
    Assert-P3 ($maintenanceWarning.Status -ceq 'CompletedWithMaintenanceWarning' -and
        $maintenanceWarning.MaintenanceStatus -ceq 'ExitRestartFailed' -and
        $maintenanceWarning.FailureCode -ceq 'P3_MAINTENANCE_FAILED') `
        'DM-P3-MAINTENANCE-WARNING' 'Maintenance restoration failure was hidden as success.'
    $script:failureCaseCount++

    $cleanupWarning = Restore-DaMaoUserDbPackageV2 `
        -PackagePath $sourcePackages['damao_wubi'].PackagePath `
        -RimeUserDir $machineC.User -RimeDll $RimeDll `
        -RimeSharedDataDir $machineC.Shared -Synthetic -Faults @{TempCleanup=$true}
    Assert-P3 ($cleanupWarning.Status -ceq 'CompletedWithCleanupWarning' -and
        $cleanupWarning.CleanupStatus -ceq 'SensitiveTemporaryArtifactCleanupFailed' -and
        $cleanupWarning.FailureCode -ceq 'P3_TEMP_CLEANUP_FAILED') `
        'DM-P3-CLEANUP-WARNING' 'Injected cleanup failure was reported as ordinary success.'
    $script:failureCaseCount++

    $receiptError = $null
    try {
        [void](Restore-DaMaoUserDbPackageV2 `
            -PackagePath $sourcePackages['damao_wubi'].PackagePath `
            -RimeUserDir $machineC.User -RimeDll $RimeDll `
            -RimeSharedDataDir $machineC.Shared -Synthetic `
            -Faults @{ReceiptSerialization=$true})
    }
    catch { $receiptError = $_.Exception.Message }
    Assert-P3 ($receiptError -match '^\[P3_RECEIPT_SERIALIZATION_FAILED\]' -and
        $receiptError -match 'Restore was verified' -and
        $receiptError -match 'no restore was retried or reversed' -and
        -not [DaMaoRimeRestoreAdapter]::IsInitialized) `
        'DM-P3-RECEIPT-SERIALIZATION' 'Receipt serialization failure returned success.'
    foreach ($sentinel in $privacySentinels) {
        Assert-P3 ($receiptError -notmatch [regex]::Escape($sentinel)) `
            'DM-P3-RECEIPT-SERIALIZATION-PRIVACY' `
            'Receipt serialization failure leaked private restore content.'
        $script:privacyCaseCount++
    }
    $script:failureCaseCount++

    Assert-P3 (@($script:matrix).Count -eq 15) 'DM-P3-MATRIX' `
        'The real-librime synthetic A-O matrix is incomplete.'
    $freezeEnd = Assert-PublicBaselineP3
    Assert-P3 ($freezeStart -eq 17 -and $freezeEnd -eq 17) 'DM-P3-SEAL-END' `
        'A pinned Public Baseline V1 file changed during P3 acceptance.'
    Write-Host ('DaMao UserDB Portability P3 tests passed. ' +
        "Assertions=$script:assertionCount PreflightCases=$script:preflightCaseCount " +
        "NativeCases=$script:nativeCaseCount FailureCases=$script:failureCaseCount " +
        "PrivacyCases=$script:privacyCaseCount PreflightZeroMutation=" +
        "$script:preflightZeroMutationCases/16 Matrix=A-O Freeze=17/17 " +
        "P1Fingerprint=2B054404BCD625DEDE55653205CC7F71F6FE3ECF1F72F4F25CBFAA2722595B6A " +
        "PowerShell=$($PSVersionTable.PSVersion)")
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        $verified = [System.IO.Path]::GetFullPath($testRoot)
        if (-not $verified.StartsWith($tempRoot + [System.IO.Path]::DirectorySeparatorChar,
                [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'Refusing to remove a P3 test directory outside the system temporary directory.'
        }
        Remove-Item -LiteralPath $verified -Recurse -Force
    }
}
