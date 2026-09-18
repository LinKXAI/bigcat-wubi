[CmdletBinding()]
param(
    [AllowNull()][string]$RimeDll,
    [switch]$HermeticOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot 'scripts\DaMao.UserDbPortabilityP2.ps1')
. (Join-Path $PSScriptRoot 'DaMao.PortabilityBaseline.ps1')

$script:assertionCount = 0
$script:nativeCaseCount = 0
$script:packageCaseCount = 0
$script:failureCaseCount = 0
$script:privacyCaseCount = 0
$script:matrix = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::Ordinal
)

function Assert-P2 {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Message
    )
    $script:assertionCount++
    if (-not $Condition) { throw "[$Code] $Message" }
}

function Add-MatrixCase {
    param([Parameter(Mandatory = $true)][string]$Name)
    [void]$script:matrix.Add($Name)
}

function Assert-ThrowsP2 {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [Parameter(Mandatory = $true)][string]$ExpectedCode,
        [Parameter(Mandatory = $true)][string]$CaseName,
        [string[]]$ForbiddenText = @()
    )
    $caught = $null
    try { & $Action }
    catch { $caught = $_.Exception.Message }
    $script:failureCaseCount++
    Assert-P2 ($null -ne $caught -and $caught -match ('^\[' + [regex]::Escape($ExpectedCode) + '\]')) `
        ('DM-P2-FAIL-' + $CaseName) "Expected $ExpectedCode."
    foreach ($text in $ForbiddenText) {
        Assert-P2 ($caught -notmatch [regex]::Escape($text)) `
            ('DM-P2-PRIVACY-' + $CaseName) 'A failure message leaked dictionary content.'
        $script:privacyCaseCount++
    }
}

function Write-Utf8P2 {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text
    )
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force)
    [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false))
}

function Write-InstallationP2 {
    param(
        [Parameter(Mandatory = $true)][string]$UserDir,
        [Parameter(Mandatory = $true)][string]$InstallationId,
        [Parameter(Mandatory = $true)][string]$SyncDir
    )
    $portableSync = [System.IO.Path]::GetFullPath($SyncDir).Replace('\', '/')
    Write-Utf8P2 -Path (Join-Path $UserDir 'installation.yaml') -Text (
        "installation_id: '$InstallationId'`n" +
        "sync_dir: '$portableSync'`n" +
        "distribution_code_name: 'Weasel'`n" +
        "distribution_version: '0.17.4'`n" +
        "rime_version: '1.13.1'`n"
    )
}

function Write-SchemaP2 {
    param(
        [Parameter(Mandatory = $true)][string]$UserDir,
        [Parameter(Mandatory = $true)][string]$DbName,
        [Parameter(Mandatory = $true)][string]$NormalPhrase,
        [Parameter(Mandatory = $true)][string]$DeletedPhrase
    )
    Write-Utf8P2 -Path (Join-Path $UserDir ($DbName + '.schema.yaml')) -Text (
        "schema:`n" +
        "  schema_id: $DbName`n" +
        "  name: P2 Synthetic Fixture`n" +
        "  version: '1'`n" +
        "engine:`n" +
        "  processors: [speller, selector, navigator, express_editor]`n" +
        "  segmentors: [abc_segmentor]`n" +
        "  translators: [table_translator]`n" +
        "speller:`n" +
        "  alphabet: abcdefghijklmnopqrstuvwxyz`n" +
        "translator:`n" +
        "  dictionary: $DbName`n" +
        "  enable_user_dict: true`n" +
        "  enable_sentence: false`n"
    )
    Write-Utf8P2 -Path (Join-Path $UserDir ($DbName + '.dict.yaml')) -Text (
        "---`nname: $DbName`nversion: '1'`nsort: original`n...`n" +
        "$NormalPhrase`tabcd`t100`n$DeletedPhrase`tefgh`t90`n"
    )
}

function Write-SnapshotP2 {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$DbName,
        [Parameter(Mandatory = $true)][string]$UserId,
        [Parameter(Mandatory = $true)][string]$Phrase
    )
    Write-Utf8P2 -Path $Path -Text (
        "# Rime user dictionary`n" +
        "#@/db_name`t$DbName`n" +
        "#@/db_type`tuserdb`n" +
        "#@/rime_version`t1.13.1`n" +
        "#@/tick`t20`n" +
        "#@/user_id`t$UserId`n" +
        "zzzz `t$Phrase`tc=1 d=2.5 t=20`n"
    )
}

function Assert-PublicBaselineP2 {
    $contract = Get-DaMaoPublicBaseline -RepositoryRoot $repoRoot
    $files = @($contract.current_file_integrity.files)
    $failures = @(Test-DaMaoPublicBaselineManifest -RepositoryRoot $repoRoot -Files $files)
    Assert-P2 ($files.Count -eq 17 -and $failures.Count -eq 0) `
        'DM-P2-FREEZE' `
        "Public Baseline V1 failed: $($failures -join '; ')"
    return 17
}

function Assert-PublicCiP2 {
    $workflow = [System.IO.File]::ReadAllText((Join-Path $repoRoot `
        '.github\workflows\validate.yml'))
    Assert-P2 (-not $workflow.Contains('fetch-depth: 0')) 'DM-P2-CI-HISTORY' `
        'Public CI must not require private repository history.'
    foreach ($requiredStep in @(
            'Verify configuration and repository hygiene',
            'Test comprehensive harness',
            'Test Public Baseline V1 with Windows PowerShell 5.1',
            'Test Public Baseline V1 with PowerShell 7',
            'Test P1 portability contract with Windows PowerShell 5.1',
            'Test P1 portability contract with PowerShell 7',
            'Test P2 hermetic contract with Windows PowerShell 5.1',
            'Test P2 hermetic contract with PowerShell 7'
        )) {
        Assert-P2 ($workflow.Contains($requiredStep)) 'DM-P2-CI-SEMANTICS' `
            'A required existing or P2 hermetic CI step is absent.'
    }
}

function Assert-NoPackageArtifactsP2 {
    param([Parameter(Mandatory = $true)][string]$OutputDirectory)
    if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) { return }
    $artifacts = @(Get-ChildItem -LiteralPath $OutputDirectory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like '*.zip' -or $_.Name -like '.damao-p2-*' })
    Assert-P2 ($artifacts.Count -eq 0) 'DM-P2-ATOMIC-NO-ARTIFACT' `
        'A failed operation left a final or temporary package artifact.'
}

function Get-ZipEntryNamesP2 {
    param([Parameter(Mandatory = $true)][string]$Path)
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try { return @($zip.Entries | ForEach-Object { $_.FullName }) }
    finally { $zip.Dispose() }
}

function Get-ZipManifestP2 {
    param([Parameter(Mandatory = $true)][string]$Path)
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $entry = @($zip.Entries | Where-Object { $_.FullName -ceq 'manifest.json' })[0]
        $reader = New-Object System.IO.StreamReader(
            $entry.Open(), [System.Text.UTF8Encoding]::new($false, $true)
        )
        try { return ($reader.ReadToEnd() | ConvertFrom-Json) }
        finally { $reader.Dispose() }
    }
    finally { $zip.Dispose() }
}

if ($HermeticOnly) {
    $hermeticRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
        ('damao-userdb-p2-hermetic-' + [guid]::NewGuid().ToString('N'))
    try {
        $freeze = Assert-PublicBaselineP2
        Assert-PublicCiP2
        Import-DaMaoRimeLeversAdapter
        Assert-P2 ([DaMaoRimeLeversAdapter]::SupportedArchitecture -ceq 'x64' -and
            [IntPtr]::Size -eq 8) 'DM-P2-HERMETIC-ARCH' `
            'The hermetic runner is not exercising the validated x64 adapter build.'
        foreach ($source in @(
                'scripts\DaMao.UserDbPortabilityP2.ps1',
                'scripts\Backup-DaMaoUserDbPackageV2.ps1',
                'scripts\DaMao.RimeLeversAdapter.cs',
                'tests\DaMaoRimeP2FixtureNative.cs',
                'tests\Test-DaMaoUserDbPortabilityP2.ps1'
            )) {
            [byte[]]$sourceBytes = [System.IO.File]::ReadAllBytes((Join-Path $repoRoot $source))
            $nonAscii = @($sourceBytes | Where-Object { $_ -gt 0x7f })
            Assert-P2 ($nonAscii.Count -eq 0) 'DM-P2-HERMETIC-SOURCE' `
                'P2 PowerShell/C# source must remain ASCII-safe for PS5.1.'
        }

        [void](New-Item -ItemType Directory -Path $hermeticRoot)
        $snapshot = Join-Path $hermeticRoot 'damao_wubi.userdb.txt'
        Write-SnapshotP2 $snapshot 'damao_wubi' 'hermetic-id' 'HERMETIC_PRIVATE_SENTINEL'
        $output = Join-Path $hermeticRoot 'out'
        $created = [datetime]'2026-09-14T01:02:03Z'
        $package = New-DaMaoUserDbPackageV2FromSnapshot $snapshot 'damao_wubi' `
            $output '1.13.1' '0.17.4' $created
        $manifest = Get-ZipManifestP2 $package.PackagePath
        Assert-P2 ($package.Status -ceq 'Success' -and
            $package.PackageSha256 -ceq (Get-FileHash $package.PackagePath -Algorithm SHA256).Hash -and
            $package.PackageByteLength -eq (Get-Item $package.PackagePath).Length -and
            $manifest.SourceArchitecture -ceq 'x64' -and
            $manifest.ContainsUserDictionaryData -and $manifest.Sensitive -and
            @(Get-ZipEntryNamesP2 $package.PackagePath).Count -eq 2) `
            'DM-P2-HERMETIC-PACKAGE' 'Hermetic Package V2 validation failed.'
        $manifestJson = $manifest | ConvertTo-Json -Depth 8 -Compress
        Assert-P2 ($manifestJson -notmatch 'HERMETIC_PRIVATE_SENTINEL' -and
            $manifestJson -notmatch [regex]::Escape($hermeticRoot)) `
            'DM-P2-HERMETIC-PRIVACY' 'Hermetic manifest leaked content or an absolute path.'

        [byte[]]$oldPackageBytes = [System.IO.File]::ReadAllBytes($package.PackagePath)
        Assert-ThrowsP2 -ExpectedCode 'P2_PACKAGE_DESTINATION_EXISTS' `
            -CaseName 'HERMETIC-DESTINATION' -Action {
                New-DaMaoUserDbPackageV2FromSnapshot $snapshot 'damao_wubi' `
                    $output '1.13.1' '0.17.4' $created
            }
        [byte[]]$afterCollisionBytes = [System.IO.File]::ReadAllBytes($package.PackagePath)
        Assert-P2 ((Get-DaMaoP2BytesSha256 $oldPackageBytes) -ceq
            (Get-DaMaoP2BytesSha256 $afterCollisionBytes)) `
            'DM-P2-HERMETIC-DESTINATION-PRESERVE' `
            'An existing package changed during collision refusal.'

        foreach ($case in @(
                [pscustomobject]@{ Name = 'UNSTABLE'; Code = 'P2_CANONICAL_SNAPSHOT_CHANGED_DURING_READ'; Fault = @{ UnstableRead = $true } },
                [pscustomobject]@{ Name = 'MANIFEST'; Code = 'P2_MANIFEST_SERIALIZATION_FAILED'; Fault = @{ ManifestSerialization = $true } },
                [pscustomobject]@{ Name = 'ZIP'; Code = 'P2_ZIP_READBACK_FAILED'; Fault = @{ ZipReadback = $true } },
                [pscustomobject]@{ Name = 'PUBLISH'; Code = 'P2_FINAL_PUBLISH_FAILED'; Fault = @{ FinalPublish = $true } }
            )) {
            $caseOutput = Join-Path $hermeticRoot $case.Name
            Assert-ThrowsP2 -ExpectedCode $case.Code -CaseName ('HERMETIC-' + $case.Name) `
                -ForbiddenText @('HERMETIC_PRIVATE_SENTINEL') -Action {
                    New-DaMaoUserDbPackageV2FromSnapshot $snapshot 'damao_wubi' `
                        $caseOutput '1.13.1' '0.17.4' $null $case.Fault
                }
            Assert-NoPackageArtifactsP2 $caseOutput
        }
        Assert-ThrowsP2 -ExpectedCode 'P2_TARGET_EXCLUDED' -CaseName 'HERMETIC-PINYIN' `
            -Action { Get-DaMaoP2AuthorizedIdentity 'damao_wubi_pinyin' }
        Assert-ThrowsP2 -ExpectedCode 'P2_TARGET_UNCLASSIFIED' -CaseName 'HERMETIC-UNKNOWN' `
            -Action { Get-DaMaoP2AuthorizedIdentity 'unclassified_db' }
        Write-Host ('DaMao UserDB Portability P2 hermetic tests passed. ' +
            "Assertions=$script:assertionCount FailureCases=$script:failureCaseCount " +
            "Freeze=$freeze/17 NativeSkipped=1 " +
            "Reason=RealLibrimeRequiresControlledLocalWeasel PowerShell=$($PSVersionTable.PSVersion)")
    }
    finally {
        if (Test-Path -LiteralPath $hermeticRoot) {
            Remove-Item -LiteralPath $hermeticRoot -Recurse -Force
        }
    }
    return
}

$RimeDll = Resolve-DaMaoP2RimeDll -Path $RimeDll
if (-not (Test-Path -LiteralPath $RimeDll -PathType Leaf)) {
    throw '[DM-P2-NATIVE-REQUIRED] The pinned real librime 1.13.1 rime.dll is required.'
}

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
    ('damao-userdb-p2-' + [guid]::NewGuid().ToString('N'))
$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
)
$testRoot = [System.IO.Path]::GetFullPath($testRoot)
Assert-P2 ($testRoot.StartsWith($tempRoot + [System.IO.Path]::DirectorySeparatorChar,
        [System.StringComparison]::OrdinalIgnoreCase)) 'DM-P2-TEMP' `
    'The P2 test root is outside the system temporary directory.'

$normalLegacy = 'P2_PRIVATE_NORMAL_LEGACY'
$deletedLegacy = 'P2_PRIVATE_DELETED_LEGACY'
$normalAlpha = 'P2_PRIVATE_NORMAL_ALPHA'
$deletedAlpha = 'P2_PRIVATE_DELETED_ALPHA'
$oldMachinePhrase = 'P2_PRIVATE_OLD_MACHINE'
$privacySentinels = @($normalLegacy, $deletedLegacy, $normalAlpha, $deletedAlpha, $oldMachinePhrase)

    $freezeStart = Assert-PublicBaselineP2
    Assert-PublicCiP2

try {
    [void](New-Item -ItemType Directory -Path $testRoot)
    $fixtureRoot = Join-Path $testRoot 'real-librime-fixture'
    $userDir = Join-Path $fixtureRoot 'user'
    $sharedDir = Join-Path $fixtureRoot 'shared'
    $stagingDir = Join-Path $userDir 'build'
    $syncDir = Join-Path $fixtureRoot 'sync'
    $outputDir = Join-Path $fixtureRoot 'packages'
    [void](New-Item -ItemType Directory -Path $userDir,$sharedDir,$stagingDir,$syncDir,$outputDir)

    Write-Utf8P2 -Path (Join-Path $sharedDir 'default.yaml') -Text (
        "config_version: '1'`nschema_list:`n" +
        "  - schema: damao_wubi_alpha03`n  - schema: damao_wubi`nmenu:`n  page_size: 5`n"
    )
    Write-InstallationP2 -UserDir $userDir -InstallationId 'machine-a-id' -SyncDir $syncDir
    Write-SchemaP2 -UserDir $userDir -DbName 'damao_wubi_alpha03' `
        -NormalPhrase $normalAlpha -DeletedPhrase $deletedAlpha
    Write-SchemaP2 -UserDir $userDir -DbName 'damao_wubi' `
        -NormalPhrase $normalLegacy -DeletedPhrase $deletedLegacy

    Add-Type -TypeDefinition ([System.IO.File]::ReadAllText(
            (Join-Path $PSScriptRoot 'DaMaoRimeP2FixtureNative.cs'))) -Language CSharp
    [DaMaoRimeP2FixtureNative]::Load($RimeDll, $sharedDir, $userDir, $stagingDir)
    try {
        Assert-P2 ([DaMaoRimeP2FixtureNative]::Deploy()) 'DM-P2-FIXTURE-DEPLOY' `
            'The real-librime synthetic fixture did not deploy.'
        [DaMaoRimeP2FixtureNative]::Start()
        foreach ($fixture in @(
                [pscustomobject]@{ Db = 'damao_wubi_alpha03'; Normal = $normalAlpha },
                [pscustomobject]@{ Db = 'damao_wubi'; Normal = $normalLegacy }
            )) {
            $session = [DaMaoRimeP2FixtureNative]::OpenSession($fixture.Db)
            try {
                $committed = [DaMaoRimeP2FixtureNative]::CommitFirst($session, 'abcd')
                [void][DaMaoRimeP2FixtureNative]::CommitFirst($session, 'efgh')
                $deleted = [DaMaoRimeP2FixtureNative]::DeleteFirst($session, 'efgh')
                Assert-P2 ($committed -ceq $fixture.Normal -and $deleted) `
                    'DM-P2-FIXTURE-LEARNING' 'The fixture did not create learning/tombstone state.'
            }
            finally { [DaMaoRimeP2FixtureNative]::CloseSession($session) }
        }
    }
    finally { [DaMaoRimeP2FixtureNative]::Shutdown() }
    $script:nativeCaseCount += 2

    Assert-P2 ((Test-Path -LiteralPath (Join-Path $userDir 'damao_wubi_alpha03.userdb') -PathType Container) -and
        (Test-Path -LiteralPath (Join-Path $userDir 'damao_wubi.userdb') -PathType Container)) `
        'DM-P2-BOTH-LIVE' 'The two synthetic PureWubi databases do not coexist.'
    Add-MatrixCase 'J'

    Import-DaMaoRimeLeversAdapter
    Assert-P2 ([DaMaoRimeLeversAdapter]::SupportedArchitecture -ceq 'x64' -and
        [IntPtr]::Size -eq 8) 'DM-P2-NATIVE-ARCH' `
        'The native integration runner is not using the validated x64 adapter ABI.'
    [DaMaoRimeLeversAdapter]::Initialize($RimeDll, $sharedDir, $userDir, $stagingDir)
    try {
        $missingBackup = [DaMaoRimeLeversAdapter]::BackupUserDictionary('missing_synthetic_db')
    }
    finally { [DaMaoRimeLeversAdapter]::Shutdown() }
    Assert-P2 (-not $missingBackup) 'DM-P2-MISSING-DB' `
        'Real librime did not return false for a missing synthetic DB.'
    $script:nativeCaseCount++
    Add-MatrixCase 'C'

    $oldDirectory = Join-Path $syncDir 'old-machine-id'
    Write-SnapshotP2 -Path (Join-Path $oldDirectory 'damao_wubi.userdb.txt') `
        -DbName 'damao_wubi' -UserId 'old-machine-id' -Phrase $oldMachinePhrase
    Write-SnapshotP2 -Path (Join-Path $oldDirectory 'damao_wubi_alpha03.userdb.txt') `
        -DbName 'damao_wubi_alpha03' -UserId 'old-machine-id' -Phrase $oldMachinePhrase
    Write-Utf8P2 -Path (Join-Path $syncDir `
            'malformed-old-machine\damao_wubi.userdb.txt') -Text '# old malformed history'

    $alphaPackage = Backup-DaMaoUserDbPackageV2 -DbName 'damao_wubi_alpha03' `
        -OutputDirectory $outputDir -RimeUserDir $userDir -RimeDll $RimeDll `
        -RimeSharedDataDir $sharedDir -Synthetic
    $legacyPackage = Backup-DaMaoUserDbPackageV2 -DbName 'damao_wubi' `
        -OutputDirectory $outputDir -RimeUserDir $userDir -RimeDll $RimeDll `
        -RimeSharedDataDir $sharedDir -Synthetic
    $script:nativeCaseCount += 2
    $script:packageCaseCount += 2
    foreach ($package in @($alphaPackage, $legacyPackage)) {
        $packageFile = Get-Item -LiteralPath $package.PackagePath
        $packageManifest = Get-ZipManifestP2 -Path $package.PackagePath
        Assert-P2 ($package.Status -ceq 'Success' -and $package.LibrimeVersion -ceq '1.13.1' -and
            $package.BackupApi -ceq 'librime.levers.backup_user_dict' -and
            $package.BackupMutationCapability -ceq 'PotentialMetadataMutation' -and
            $package.SupportedArchitecture -ceq 'x64' -and
            $package.PackageSha256 -ceq (Get-FileHash -LiteralPath $packageFile.FullName `
                -Algorithm SHA256).Hash -and
            $package.PackageByteLength -eq $packageFile.Length -and
            $package.Maintenance.Status -ceq 'NotRequiredSynthetic') `
            'DM-P2-REAL-BACKUP' 'A real-librime synthetic backup receipt is incomplete.'
        $names = @(Get-ZipEntryNamesP2 -Path $package.PackagePath)
        Assert-P2 ($names.Count -eq 2 -and $names -ccontains 'manifest.json' -and
            $names -ccontains ('snapshots/' + $package.DbName + '.userdb.txt')) `
            'DM-P2-ONE-DB' 'A package did not contain exactly one physical DB snapshot.'
        Assert-P2 ($packageManifest.LogicalRole -ceq 'PureWubi' -and
            @($packageManifest.SchemaIdentities).Count -eq 1 -and
            @($packageManifest.SchemaIdentities)[0] -ceq $package.DbName -and
            $packageManifest.DbName -ceq $package.DbName -and
            $packageManifest.SnapshotDbName -ceq $package.DbName -and
            $packageManifest.SourceArchitecture -ceq 'x64' -and
            $packageManifest.ContainsUserDictionaryData -and $packageManifest.Sensitive) `
            'DM-P2-MANIFEST-IDENTITY' 'Package manifest identity or sensitivity facts are incomplete.'
        $serializedManifest = $packageManifest | ConvertTo-Json -Depth 8 -Compress
        Assert-P2 ($serializedManifest -notmatch [regex]::Escape($testRoot) -and
            $serializedManifest -notmatch 'machine-a-id|old-machine-id|abcd|efgh') `
            'DM-P2-PRIVACY-MANIFEST-METADATA' `
            'A manifest leaked a local path, installation identity, phrase, or code.'
        $script:privacyCaseCount++
        $serializedReceipt = $package | ConvertTo-Json -Depth 8 -Compress
        foreach ($sentinel in $privacySentinels) {
            Assert-P2 ($serializedReceipt -notmatch [regex]::Escape($sentinel)) `
                'DM-P2-PRIVACY-RECEIPT' 'A success receipt leaked dictionary content.'
            $script:privacyCaseCount++
        }
    }
    Add-MatrixCase 'A'; Add-MatrixCase 'H'; Add-MatrixCase 'I'
    Add-MatrixCase 'K'; Add-MatrixCase 'N'

    $alphaSnapshotPath = Join-Path $syncDir 'machine-a-id\damao_wubi_alpha03.userdb.txt'
    $legacySnapshotPath = Join-Path $syncDir 'machine-a-id\damao_wubi.userdb.txt'
    $alphaSnapshot = Read-DaMaoUserDbSnapshot $alphaSnapshotPath
    $legacySnapshot = Read-DaMaoUserDbSnapshot $legacySnapshotPath
    foreach ($snapshot in @($alphaSnapshot, $legacySnapshot)) {
        Assert-P2 ($snapshot.StructuralHealth -ceq 'Healthy' -and $snapshot.EntryCount -eq 2 -and
            $snapshot.TombstoneCount -eq 1 -and $null -ne $snapshot.MinTick -and
            $null -ne $snapshot.MaxTick -and $snapshot.DuplicateKeyCount -eq 0) `
            'DM-P2-SNAPSHOT-SEMANTICS' 'Canonical snapshot validation lost learning/tombstone state.'
    }

    $auditDir = Join-Path $fixtureRoot 'audit'
    [void](New-Item -ItemType Directory -Path $auditDir)
    $exportPath = Join-Path $auditDir 'export.txt'
    [DaMaoRimeLeversAdapter]::Initialize($RimeDll, $sharedDir, $userDir, $stagingDir)
    try { $exportCount = [DaMaoRimeLeversAdapter]::ExportUserDictionaryForAudit('damao_wubi', $exportPath) }
    finally { [DaMaoRimeLeversAdapter]::Shutdown() }
    $script:nativeCaseCount++
    $exportHeader = [System.IO.File]::ReadAllLines($exportPath)[0]
    $exportAsSnapshot = Join-Path $auditDir 'damao_wubi.userdb.txt'
    [System.IO.File]::Copy($exportPath, $exportAsSnapshot)
    $exportParse = Read-DaMaoUserDbSnapshot $exportAsSnapshot
    Assert-P2 ($exportCount -lt $legacySnapshot.EntryCount -and
        $exportHeader -ceq '# Rime user dictionary export' -and
        $exportParse.StructuralHealth -cne 'Healthy' -and
        (Get-FileHash $exportPath -Algorithm SHA256).Hash -cne $legacySnapshot.Sha256) `
        'DM-P2-EXPORT-AUDIT' 'Export and backup snapshot semantics were not distinguished.'

    $repeatPackage = Backup-DaMaoUserDbPackageV2 -DbName 'damao_wubi' `
        -OutputDirectory $outputDir -RimeUserDir $userDir -RimeDll $RimeDll `
        -RimeSharedDataDir $sharedDir -Synthetic
    $script:nativeCaseCount++
    $script:packageCaseCount++
    Assert-P2 ($repeatPackage.SnapshotSha256 -ceq $legacyPackage.SnapshotSha256 -and
        $repeatPackage.DbName -ceq $legacyPackage.DbName -and
        @(Get-ZipEntryNamesP2 $repeatPackage.PackagePath).Count -eq 2) `
        'DM-P2-REPEAT' 'Repeated unchanged backup did not accept the same snapshot hash.'
    Add-MatrixCase 'L'; Add-MatrixCase 'M'

    Write-InstallationP2 -UserDir $userDir -InstallationId 'machine-b-id' -SyncDir $syncDir
    $machineBPackage = Backup-DaMaoUserDbPackageV2 -DbName 'damao_wubi' `
        -OutputDirectory $outputDir -RimeUserDir $userDir -RimeDll $RimeDll `
        -RimeSharedDataDir $sharedDir -Synthetic
    $machineBSnapshot = Read-DaMaoUserDbSnapshot `
        (Join-Path $syncDir 'machine-b-id\damao_wubi.userdb.txt')
    Assert-P2 ($machineBSnapshot.StructuralHealth -ceq 'Healthy' -and
        $machineBSnapshot.UserId -ceq 'machine-b-id' -and
        $machineBPackage.DbName -ceq 'damao_wubi' -and
        (Test-Path -LiteralPath $legacySnapshotPath -PathType Leaf)) `
        'DM-P2-MACHINE-AB' 'Machine-A/B metadata behavior was not observed in isolation.'
    $script:nativeCaseCount++
    $script:packageCaseCount++
    Add-MatrixCase 'B'

    $maintenanceOutput = Join-Path $fixtureRoot 'maintenance-warning-package'
    $maintenancePackage = Backup-DaMaoUserDbPackageV2 -DbName 'damao_wubi' `
        -OutputDirectory $maintenanceOutput -RimeUserDir $userDir -RimeDll $RimeDll `
        -RimeSharedDataDir $sharedDir -Synthetic -Faults @{ MaintenanceRestore = $true }
    Assert-P2 ($maintenancePackage.Status -ceq 'CompletedWithMaintenanceWarning' -and
        $maintenancePackage.Maintenance.Status -ceq 'ExitRestartFailed' -and
        $maintenancePackage.Maintenance.ErrorCode -ceq 'P2_MAINTENANCE_FAILED' -and
        -not $maintenancePackage.Maintenance.Restored -and
        (Test-Path -LiteralPath $maintenancePackage.PackagePath -PathType Leaf) -and
        $maintenancePackage.PackageSha256 -ceq (Get-FileHash `
            -LiteralPath $maintenancePackage.PackagePath -Algorithm SHA256).Hash) `
        'DM-P2-MAINTENANCE-WARNING' `
        'A restoration failure was hidden as success or discarded a valid package.'
    $script:nativeCaseCount++
    $script:packageCaseCount++
    $script:failureCaseCount++

    $cliOutput = (& (Join-Path $repoRoot 'scripts\Backup-DaMaoUserDbPackageV2.ps1') `
        -DbName 'damao_wubi' -OutputDirectory (Join-Path $fixtureRoot 'cli-package') `
        -RimeUserDir $userDir -RimeDll $RimeDll -RimeSharedDataDir $sharedDir `
        -Synthetic -AsJson *>&1 | Out-String)
    Assert-P2 ($cliOutput -match 'sensitive' -and $cliOutput -match '"Status"\s*:\s*"Success"') `
        'DM-P2-CLI-WARNING' 'The CLI did not warn about sensitive data or return success JSON.'
    foreach ($sentinel in $privacySentinels) {
        Assert-P2 ($cliOutput -notmatch [regex]::Escape($sentinel)) `
            'DM-P2-PRIVACY-CLI' 'CLI stdout/stderr leaked dictionary content.'
        $script:privacyCaseCount++
    }
    $script:nativeCaseCount++
    $script:packageCaseCount++

    $snapshotOnlyRoot = Join-Path $testRoot 'snapshot-only'
    $snapshotOnlyUser = Join-Path $snapshotOnlyRoot 'user'
    $snapshotOnlySync = Join-Path $snapshotOnlyRoot 'sync'
    [void](New-Item -ItemType Directory -Path $snapshotOnlyUser,$snapshotOnlySync)
    Write-InstallationP2 $snapshotOnlyUser 'snapshot-only-id' $snapshotOnlySync
    Write-SnapshotP2 -Path (Join-Path $snapshotOnlySync `
            'snapshot-only-id\damao_wubi.userdb.txt') -DbName 'damao_wubi' `
        -UserId 'snapshot-only-id' -Phrase $oldMachinePhrase
    Assert-ThrowsP2 -ExpectedCode 'P2_TARGET_STATE_REJECTED' -CaseName 'SNAPSHOT-ONLY' `
        -Action { Backup-DaMaoUserDbPackageV2 -DbName 'damao_wubi' `
                -OutputDirectory (Join-Path $snapshotOnlyRoot 'out') `
                -RimeUserDir $snapshotOnlyUser -RimeDll $RimeDll `
                -RimeSharedDataDir $sharedDir -Synthetic }
    Add-MatrixCase 'D'

    $ambiguousRoot = Join-Path $testRoot 'ambiguous'
    $ambiguousUser = Join-Path $ambiguousRoot 'user'
    $ambiguousSync = Join-Path $ambiguousRoot 'sync'
    [void](New-Item -ItemType Directory -Path $ambiguousUser,$ambiguousSync,(
            Join-Path $ambiguousUser 'damao_wubi.userdb'))
    Write-Utf8P2 -Path (Join-Path $ambiguousUser 'damao_wubi.userdb.kct') -Text 'fixture'
    Write-InstallationP2 $ambiguousUser 'ambiguous-id' $ambiguousSync
    Assert-ThrowsP2 -ExpectedCode 'P2_TARGET_STATE_REJECTED' -CaseName 'AMBIGUOUS' `
        -Action { Backup-DaMaoUserDbPackageV2 -DbName 'damao_wubi' `
                -OutputDirectory (Join-Path $ambiguousRoot 'out') `
                -RimeUserDir $ambiguousUser -RimeDll $RimeDll `
                -RimeSharedDataDir $sharedDir -Synthetic }
    Add-MatrixCase 'E'

    Assert-ThrowsP2 -ExpectedCode 'P2_TARGET_EXCLUDED' -CaseName 'PINYIN' `
        -Action { Get-DaMaoP2AuthorizedIdentity 'damao_wubi_pinyin' }
    Assert-ThrowsP2 -ExpectedCode 'P2_TARGET_UNCLASSIFIED' -CaseName 'UNKNOWN' `
        -Action { Get-DaMaoP2AuthorizedIdentity 'unknown_user_dictionary' }
    Add-MatrixCase 'F'; Add-MatrixCase 'G'

    $failureRoot = Join-Path $testRoot 'failures'
    [void](New-Item -ItemType Directory -Path $failureRoot)
    $validFailureSnapshot = Join-Path $failureRoot 'damao_wubi.userdb.txt'
    Write-SnapshotP2 -Path $validFailureSnapshot -DbName 'damao_wubi' `
        -UserId 'failure-id' -Phrase $normalLegacy
    $packageFailures = @(
        [pscustomobject]@{ Name = 'SNAPSHOT-MISSING'; Code = 'P2_CANONICAL_SNAPSHOT_NOT_FOUND'; Fault = @{ SnapshotMissing = $true }; Path = $validFailureSnapshot },
        [pscustomobject]@{ Name = 'UNSTABLE'; Code = 'P2_CANONICAL_SNAPSHOT_CHANGED_DURING_READ'; Fault = @{ UnstableRead = $true }; Path = $validFailureSnapshot },
        [pscustomobject]@{ Name = 'MANIFEST'; Code = 'P2_MANIFEST_SERIALIZATION_FAILED'; Fault = @{ ManifestSerialization = $true }; Path = $validFailureSnapshot },
        [pscustomobject]@{ Name = 'TEMP-ZIP'; Code = 'P2_TEMP_ZIP_FAILED'; Fault = @{ TempZip = $true }; Path = $validFailureSnapshot },
        [pscustomobject]@{ Name = 'ZIP-READBACK'; Code = 'P2_ZIP_READBACK_FAILED'; Fault = @{ ZipReadback = $true }; Path = $validFailureSnapshot },
        [pscustomobject]@{ Name = 'FINAL-PUBLISH'; Code = 'P2_FINAL_PUBLISH_FAILED'; Fault = @{ FinalPublish = $true }; Path = $validFailureSnapshot }
    )
    foreach ($case in $packageFailures) {
        $caseOutput = Join-Path $failureRoot $case.Name
        Assert-ThrowsP2 -ExpectedCode $case.Code -CaseName $case.Name `
            -ForbiddenText $privacySentinels -Action {
                New-DaMaoUserDbPackageV2FromSnapshot -SnapshotPath $case.Path `
                    -DbName 'damao_wubi' -OutputDirectory $caseOutput `
                    -SourceLibrimeVersion '1.13.1' -SourceWeaselVersion '0.17.4' `
                    -Faults $case.Fault
            }
        Assert-NoPackageArtifactsP2 $caseOutput
    }

    $malformedPath = Join-Path $failureRoot 'malformed\damao_wubi.userdb.txt'
    Write-Utf8P2 -Path $malformedPath -Text "# not a snapshot`n$normalLegacy"
    $malformedOutput = Join-Path $failureRoot 'malformed-out'
    Assert-ThrowsP2 -ExpectedCode 'P2_CANONICAL_SNAPSHOT_INVALID' -CaseName 'MALFORMED' `
        -ForbiddenText $privacySentinels -Action {
            New-DaMaoUserDbPackageV2FromSnapshot $malformedPath 'damao_wubi' `
                $malformedOutput '1.13.1' '0.17.4'
        }
    Assert-NoPackageArtifactsP2 $malformedOutput

    $mismatchPath = Join-Path $failureRoot 'mismatch\damao_wubi.userdb.txt'
    Write-SnapshotP2 -Path $mismatchPath -DbName 'damao_wubi_alpha03' `
        -UserId 'failure-id' -Phrase $normalAlpha
    $mismatchOutput = Join-Path $failureRoot 'mismatch-out'
    Assert-ThrowsP2 -ExpectedCode 'P2_CANONICAL_DB_IDENTITY_MISMATCH' -CaseName 'DB-MISMATCH' `
        -ForbiddenText $privacySentinels -Action {
            New-DaMaoUserDbPackageV2FromSnapshot $mismatchPath 'damao_wubi' `
                $mismatchOutput '1.13.1' '0.17.4'
        }
    Assert-NoPackageArtifactsP2 $mismatchOutput

    $preExistingSnapshotPath = Join-Path $syncDir 'machine-b-id\damao_wubi.userdb.txt'
    [byte[]]$preExistingSnapshotBytes = [System.IO.File]::ReadAllBytes($preExistingSnapshotPath)
    $preExistingSnapshotSha256 = Get-DaMaoP2BytesSha256 $preExistingSnapshotBytes
    foreach ($nativeFailure in @(
            [pscustomobject]@{ Name = 'NATIVE-API'; Code = 'P2_RIME_API_UNAVAILABLE'; Fault = @{ NativeApiUnavailable = $true } },
            [pscustomobject]@{ Name = 'LEVERS'; Code = 'P2_LEVERS_MODULE_UNAVAILABLE'; Fault = @{ LeversUnavailable = $true } },
            [pscustomobject]@{ Name = 'BACKUP-API'; Code = 'P2_BACKUP_API_UNAVAILABLE'; Fault = @{ BackupApiUnavailable = $true } },
            [pscustomobject]@{ Name = 'BACKUP-FALSE'; Code = 'P2_NATIVE_BACKUP_FAILED'; Fault = @{ BackupFalse = $true } },
            [pscustomobject]@{ Name = 'BACKUP-EXCEPTION'; Code = 'P2_NATIVE_BACKUP_FAILED'; Fault = @{ BackupException = $true } }
        )) {
        $nativeOutput = Join-Path $failureRoot $nativeFailure.Name
        Assert-ThrowsP2 -ExpectedCode $nativeFailure.Code -CaseName $nativeFailure.Name `
            -ForbiddenText $privacySentinels -Action {
                Backup-DaMaoUserDbPackageV2 -DbName 'damao_wubi' `
                    -OutputDirectory $nativeOutput -RimeUserDir $userDir `
                    -RimeDll $RimeDll -RimeSharedDataDir $sharedDir -Synthetic `
                    -Faults $nativeFailure.Fault
        }
        Assert-NoPackageArtifactsP2 $nativeOutput
        Assert-P2 (-not [DaMaoRimeLeversAdapter]::IsInitialized) `
            ('DM-P2-FINALIZE-' + $nativeFailure.Name) `
            'The native runtime remained initialized after a native failure.'
    }
    $postFailureSnapshotSha256 = (Get-FileHash -LiteralPath $preExistingSnapshotPath `
        -Algorithm SHA256).Hash
    Assert-P2 ($postFailureSnapshotSha256 -ceq $preExistingSnapshotSha256) `
        'DM-P2-OLD-SNAPSHOT-PRESERVED' `
        'Backup failure changed the pre-existing valid snapshot.'

    $badZip = Join-Path $failureRoot 'malicious.zip'
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    $badArchive = [System.IO.Compression.ZipFile]::Open($badZip,
        [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        [void]$badArchive.CreateEntry('manifest.json')
        [void]$badArchive.CreateEntry('../damao_wubi.userdb.txt')
    }
    finally { $badArchive.Dispose() }
    Assert-ThrowsP2 -ExpectedCode 'P2_ZIP_READBACK_FAILED' -CaseName 'ZIP-PATH' `
        -Action { Test-DaMaoP2ZipReadback $badZip 'damao_wubi' ('0' * 64) 0 $null }

    $unicodeLeaf = 'nonascii-' + [char]0x8DEF + [char]0x5F84 + '-' + ('longsegment-' * 8)
    $unicodeRoot = Join-Path $testRoot $unicodeLeaf
    $unicodeUser = Join-Path $unicodeRoot 'user'
    $unicodeShared = Join-Path $unicodeRoot 'shared'
    $unicodeSync = Join-Path $unicodeRoot 'sync'
    [void](New-Item -ItemType Directory -Path $unicodeRoot,$unicodeSync)
    Copy-Item -LiteralPath $userDir -Destination $unicodeUser -Recurse
    Copy-Item -LiteralPath $sharedDir -Destination $unicodeShared -Recurse
    Write-InstallationP2 -UserDir $unicodeUser -InstallationId `
        (([string][char]0x673A) + ([string][char]0x5668) + '-id') -SyncDir $unicodeSync
    [DaMaoRimeLeversAdapter]::Initialize($RimeDll, $unicodeShared, $unicodeUser,
        (Join-Path $unicodeUser 'build'))
    try { $unicodeBackup = [DaMaoRimeLeversAdapter]::BackupUserDictionary('damao_wubi_alpha03') }
    finally { [DaMaoRimeLeversAdapter]::Shutdown() }
    $unicodeSnapshot = Read-DaMaoUserDbSnapshot (Join-Path $unicodeSync (
            ([string][char]0x673A) + ([string][char]0x5668) + '-id\damao_wubi_alpha03.userdb.txt'))
    Assert-P2 ($unicodeBackup -and $unicodeSnapshot.StructuralHealth -ceq 'Healthy' -and
        $unicodeSnapshot.UserId -ceq (([string][char]0x673A) + ([string][char]0x5668) + '-id')) `
        'DM-P2-UTF8-LONG' 'UTF-8/non-ASCII long-path native marshaling failed.'
    $script:nativeCaseCount++

    Assert-P2 (@($script:matrix).Count -eq 14) 'DM-P2-MATRIX' `
        'The synthetic A-N integration matrix is incomplete.'
    $freezeEnd = Assert-PublicBaselineP2
    Assert-PublicCiP2
    Assert-P2 ($freezeStart -eq 17 -and $freezeEnd -eq 17) 'DM-P2-FREEZE-END' `
        'Public Baseline V1 changed during P2 tests.'

    Write-Host ('DaMao UserDB Portability P2 tests passed. ' +
        "Assertions=$script:assertionCount NativeCases=$script:nativeCaseCount " +
        "PackageCases=$script:packageCaseCount FailureCases=$script:failureCaseCount " +
        "PrivacyCases=$script:privacyCaseCount Matrix=A-N Freeze=17/17 " +
        "PowerShell=$($PSVersionTable.PSVersion)")
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        $verified = [System.IO.Path]::GetFullPath($testRoot)
        if (-not $verified.StartsWith($tempRoot + [System.IO.Path]::DirectorySeparatorChar,
                [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'Refusing to remove a P2 test directory outside the system temporary directory.'
        }
        Remove-Item -LiteralPath $verified -Recurse -Force
    }
}
