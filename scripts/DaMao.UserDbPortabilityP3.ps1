$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'DaMao.UserDbPortabilityP2.ps1')

$script:DaMaoP3MaximumManifestBytes = 1048576L
$script:DaMaoP3MaximumSnapshotBytes = 268435456L
$script:DaMaoP3MaximumPackageBytes = 300000000L
$script:DaMaoP3MaintenanceEntryCount = 0
$script:DaMaoP3BackupCallCount = 0
$script:DaMaoP3NativeMutationSessionCount = 0
$script:DaMaoP3ErrorCodes = @(
    'P3_PACKAGE_NOT_FOUND',
    'P3_PACKAGE_INVALID',
    'P3_PACKAGE_CONTENT_MISMATCH',
    'P3_TARGET_EXCLUDED',
    'P3_TARGET_UNCLASSIFIED',
    'P3_TARGET_STATE_REJECTED',
    'P3_TARGET_STATE_CHANGED',
    'P3_RESTORE_SOURCE_CHANGED',
    'P3_RIME_API_UNAVAILABLE',
    'P3_LEVERS_MODULE_UNAVAILABLE',
    'P3_LEVERS_API_INCOMPATIBLE',
    'P3_RESTORE_API_UNAVAILABLE',
    'P3_NATIVE_ARCHITECTURE_UNSUPPORTED',
    'P3_NATIVE_INITIALIZATION_FAILED',
    'P3_NATIVE_RESTORE_FAILED',
    'P3_NATIVE_FINALIZE_FAILED',
    'P3_LIBRIME_MUTATION_UNVERIFIED',
    'P3_MAINTENANCE_FAILED',
    'P3_SAFETY_BACKUP_FAILED',
    'P3_POST_RESTORE_BACKUP_FAILED',
    'P3_POST_RESTORE_PARSE_FAILED',
    'P3_POST_RESTORE_VERIFICATION_FAILED',
    'P3_RECEIPT_SERIALIZATION_FAILED',
    'P3_TEMP_CLEANUP_FAILED'
)

function Get-DaMaoUserDbP3ErrorCodes {
    return @($script:DaMaoP3ErrorCodes)
}

function Get-DaMaoP3OperationCounters {
    $restoreCalls = if ('DaMaoRimeRestoreAdapter' -as [type]) {
        [DaMaoRimeRestoreAdapter]::RestoreCallCount
    } else { 0 }
    return [pscustomobject][ordered]@{
        MaintenanceEntryCount = [int]$script:DaMaoP3MaintenanceEntryCount
        BackupCallCount = [int]$script:DaMaoP3BackupCallCount
        NativeMutationSessionCount = [int]$script:DaMaoP3NativeMutationSessionCount
        RestoreCallCount = [int]$restoreCalls
        MutationCapableApiCount = [int]$script:DaMaoP3BackupCallCount +
            [int]$script:DaMaoP3NativeMutationSessionCount + [int]$restoreCalls
    }
}

function Throw-DaMaoP3Error {
    param(
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Message
    )
    throw "[$Code] $Message"
}

function Test-DaMaoP3Fault {
    param(
        [AllowNull()][hashtable]$Faults,
        [Parameter(Mandatory = $true)][string]$Name
    )
    return $null -ne $Faults -and $Faults.ContainsKey($Name) -and [bool]$Faults[$Name]
}

function Import-DaMaoRimeRestoreAdapter {
    if ('DaMaoRimeRestoreAdapter' -as [type]) { return }
    $sourcePath = Join-Path $PSScriptRoot 'DaMao.RimeRestoreAdapter.cs'
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        Throw-DaMaoP3Error 'P3_RIME_API_UNAVAILABLE' `
            'The native restore adapter source is unavailable.'
    }
    try {
        Add-Type -TypeDefinition ([System.IO.File]::ReadAllText($sourcePath)) `
            -Language CSharp -ErrorAction Stop
    }
    catch {
        Throw-DaMaoP3Error 'P3_NATIVE_INITIALIZATION_FAILED' `
            'The native restore adapter could not be compiled for this host.'
    }
}

function Get-DaMaoP3BytesSha256 {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '')
    }
    finally { $sha.Dispose() }
}

function Assert-DaMaoP3ZipEntryName {
    param([Parameter(Mandatory = $true)][string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name) -or
        [System.IO.Path]::IsPathRooted($Name) -or
        $Name.Contains('\') -or $Name.Contains(':') -or
        $Name.StartsWith('/', [System.StringComparison]::Ordinal) -or
        @($Name.Split('/') | Where-Object {
                $_ -eq '..' -or $_ -eq '.' -or $_ -eq ''
            }).Count -gt 0) {
        Throw-DaMaoP3Error 'P3_PACKAGE_INVALID' `
            'The package contains a non-canonical entry path.'
    }
}

function Assert-DaMaoP3ZipEntryType {
    param([Parameter(Mandatory = $true)]$Entry)
    [long]$external = [int64]$Entry.ExternalAttributes
    if ($external -lt 0) { $external += 4294967296L }
    $unixType = ($external -shr 16) -band 0xF000
    $dosAttributes = $external -band 0xFFFF
    if ($unixType -eq 0xA000 -or
        ($dosAttributes -band [int][System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        Throw-DaMaoP3Error 'P3_PACKAGE_INVALID' `
            'Symbolic-link and reparse-point ZIP entries are forbidden.'
    }
}

function Read-DaMaoP3ZipEntryBytes {
    param(
        [Parameter(Mandatory = $true)]$Entry,
        [Parameter(Mandatory = $true)][long]$MaximumBytes
    )
    if ([long]$Entry.Length -lt 0 -or [long]$Entry.Length -gt $MaximumBytes) {
        Throw-DaMaoP3Error 'P3_PACKAGE_INVALID' `
            'A package entry exceeds its accepted size bound.'
    }
    $stream = $Entry.Open()
    $memory = New-Object System.IO.MemoryStream
    try {
        $buffer = New-Object byte[] 65536
        [long]$total = 0
        while (($count = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $total += $count
            if ($total -gt $MaximumBytes) {
                Throw-DaMaoP3Error 'P3_PACKAGE_INVALID' `
                    'A package entry expanded beyond its accepted size bound.'
            }
            $memory.Write($buffer, 0, $count)
        }
        [byte[]]$bytes = $memory.ToArray()
        if ($bytes.Length -ne [long]$Entry.Length) {
            Throw-DaMaoP3Error 'P3_PACKAGE_INVALID' `
                'A package entry was truncated during CRC-checked readback.'
        }
        return $bytes
    }
    finally {
        $memory.Dispose()
        $stream.Dispose()
    }
}

function Test-DaMaoP3ManifestShape {
    param([Parameter(Mandatory = $true)]$Manifest)
    $required = @(
        'PackageFormat', 'PackageFormatVersion', 'LogicalRole', 'SchemaIdentities',
        'DbName', 'SnapshotFile', 'SnapshotSha256', 'SnapshotByteLength',
        'SnapshotEntryCount', 'SnapshotTombstoneCount', 'SnapshotMinTick',
        'SnapshotMaxTick', 'SnapshotDbName', 'SnapshotDbType',
        'SourceLibrimeVersion', 'BackupApi', 'BackupMutationCapability',
        'AutomaticMerge', 'AutomaticRename', 'ContainsUserDictionaryData',
        'Sensitive', 'SourceArchitecture'
    )
    $names = @($Manifest.PSObject.Properties.Name)
    foreach ($field in $required) {
        if ($names -cnotcontains $field) {
            Throw-DaMaoP3Error 'P3_PACKAGE_INVALID' `
                'The Package V2 manifest is missing a required field.'
        }
    }
    foreach ($field in @(
            'PackageFormat', 'LogicalRole', 'DbName', 'SnapshotFile',
            'SnapshotSha256', 'SnapshotDbName', 'SnapshotDbType',
            'SourceLibrimeVersion', 'BackupApi', 'BackupMutationCapability',
            'SourceArchitecture'
        )) {
        if ($Manifest.$field -isnot [string]) {
            Throw-DaMaoP3Error 'P3_PACKAGE_INVALID' `
                'The Package V2 manifest contains an invalid field type.'
        }
    }
    foreach ($field in @(
            'AutomaticMerge', 'AutomaticRename', 'ContainsUserDictionaryData', 'Sensitive'
        )) {
        if ($Manifest.$field -isnot [bool]) {
            Throw-DaMaoP3Error 'P3_PACKAGE_INVALID' `
                'The Package V2 manifest contains an invalid policy field type.'
        }
    }
}

function Get-DaMaoP3AuthorizedIdentity {
    param([Parameter(Mandatory = $true)][string]$DbName)
    try {
        return Get-DaMaoP2AuthorizedIdentity -DbName $DbName
    }
    catch {
        if ($_.Exception.Message -match '^\[P2_TARGET_EXCLUDED\]') {
            Throw-DaMaoP3Error 'P3_TARGET_EXCLUDED' `
                'The package physical database is excluded by default.'
        }
        Throw-DaMaoP3Error 'P3_TARGET_UNCLASSIFIED' `
            'The package physical database is not authorized by Public Baseline V1.'
    }
}

function Read-DaMaoUserDbPackageV2ForRestore {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$PackagePath)

    $resolved = [System.IO.Path]::GetFullPath($PackagePath)
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        Throw-DaMaoP3Error 'P3_PACKAGE_NOT_FOUND' 'The restore package was not found.'
    }
    $packageFile = Get-Item -LiteralPath $resolved -Force
    if (($packageFile.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or
        $packageFile.Length -le 0 -or
        $packageFile.Length -gt $script:DaMaoP3MaximumPackageBytes) {
        Throw-DaMaoP3Error 'P3_PACKAGE_INVALID' `
            'The restore package file is unsafe or outside the accepted size bound.'
    }

    Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    $archive = $null
    $tempRoot = $null
    try {
        try { $archive = [System.IO.Compression.ZipFile]::OpenRead($resolved) }
        catch {
            Throw-DaMaoP3Error 'P3_PACKAGE_INVALID' `
                'The restore package is not a complete readable ZIP archive.'
        }
        $entries = @($archive.Entries)
        if ($entries.Count -ne 2) {
            Throw-DaMaoP3Error 'P3_PACKAGE_INVALID' `
                'Package V2 must contain exactly two entries.'
        }
        $seen = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )
        foreach ($entry in $entries) {
            Assert-DaMaoP3ZipEntryName -Name $entry.FullName
            Assert-DaMaoP3ZipEntryType -Entry $entry
            if (-not $seen.Add($entry.FullName)) {
                Throw-DaMaoP3Error 'P3_PACKAGE_INVALID' `
                    'The package contains duplicate or colliding entry paths.'
            }
        }
        $manifestEntries = @($entries | Where-Object { $_.FullName -ceq 'manifest.json' })
        $snapshotEntries = @($entries | Where-Object {
                $_.FullName -cmatch '^snapshots/[^/]+\.userdb\.txt$'
            })
        if ($manifestEntries.Count -ne 1 -or $snapshotEntries.Count -ne 1) {
            Throw-DaMaoP3Error 'P3_PACKAGE_INVALID' `
                'Package V2 requires one manifest and one canonical snapshot entry.'
        }

        [byte[]]$manifestBytes = Read-DaMaoP3ZipEntryBytes `
            -Entry $manifestEntries[0] -MaximumBytes $script:DaMaoP3MaximumManifestBytes
        try {
            $strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
            $manifestText = $strictUtf8.GetString($manifestBytes)
            $manifest = $manifestText | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            Throw-DaMaoP3Error 'P3_PACKAGE_INVALID' `
                'The Package V2 manifest is not strict UTF-8 JSON.'
        }
        Test-DaMaoP3ManifestShape -Manifest $manifest

        if ($manifest.PackageFormat -cne 'DaMao.UserDbPortabilityPackage' -or
            [int64]$manifest.PackageFormatVersion -ne 2 -or
            $manifest.LogicalRole -cne 'PureWubi' -or
            $manifest.SourceLibrimeVersion -cne '1.13.1' -or
            $manifest.BackupApi -cne 'librime.levers.backup_user_dict' -or
            $manifest.BackupMutationCapability -cne 'PotentialMetadataMutation' -or
            $manifest.AutomaticMerge -or $manifest.AutomaticRename -or
            -not $manifest.ContainsUserDictionaryData -or -not $manifest.Sensitive -or
            $manifest.SourceArchitecture -cne 'x64') {
            Throw-DaMaoP3Error 'P3_PACKAGE_INVALID' `
                'The manifest is not an authorized Package V2 contract.'
        }
        if (-not (Test-DaMaoDbName -DbName $manifest.DbName)) {
            Throw-DaMaoP3Error 'P3_PACKAGE_INVALID' `
                'The manifest physical database name is unsafe.'
        }
        $expectedSnapshotName = 'snapshots/' + $manifest.DbName + '.userdb.txt'
        if ($manifest.SnapshotFile -cne $expectedSnapshotName -or
            $snapshotEntries[0].FullName -cne $expectedSnapshotName) {
            Throw-DaMaoP3Error 'P3_PACKAGE_CONTENT_MISMATCH' `
                'Manifest, archive path, and authorized physical database disagree.'
        }

        [byte[]]$snapshotBytes = Read-DaMaoP3ZipEntryBytes `
            -Entry $snapshotEntries[0] -MaximumBytes $script:DaMaoP3MaximumSnapshotBytes
        $snapshotSha = Get-DaMaoP3BytesSha256 -Bytes $snapshotBytes
        if ($manifest.SnapshotSha256 -cnotmatch '^[A-F0-9]{64}$' -or
            $manifest.SnapshotSha256 -cne $snapshotSha -or
            [int64]$manifest.SnapshotByteLength -ne $snapshotBytes.Length) {
            Throw-DaMaoP3Error 'P3_PACKAGE_CONTENT_MISMATCH' `
                'The snapshot bytes disagree with the manifest hash or size.'
        }

        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
            ('damao-userdb-p3-' + [guid]::NewGuid().ToString('N'))
        $snapshotDirectory = Join-Path $tempRoot 'snapshots'
        [void](New-Item -ItemType Directory -Path $snapshotDirectory)
        $extractedPath = Join-Path $snapshotDirectory ($manifest.DbName + '.userdb.txt')
        [System.IO.File]::WriteAllBytes($extractedPath, $snapshotBytes)
        $extractedFile = Get-Item -LiteralPath $extractedPath -Force
        $extractedFile.IsReadOnly = $true
        $parsed = Read-DaMaoUserDbSnapshot -Path $extractedPath -IncludeEntries
        if ($parsed.StructuralHealth -cne 'Healthy' -or
            $parsed.DuplicateKeyCount -ne 0) {
            Throw-DaMaoP3Error 'P3_PACKAGE_CONTENT_MISMATCH' `
                'The extracted snapshot failed strict structural validation.'
        }
        if ($parsed.DbName -cne $manifest.DbName -or
            $parsed.DbType -cne 'userdb' -or
            $parsed.Sha256 -cne $snapshotSha -or
            $parsed.ByteLength -ne $snapshotBytes.Length -or
            [int64]$manifest.SnapshotEntryCount -ne $parsed.EntryCount -or
            [int64]$manifest.SnapshotTombstoneCount -ne $parsed.TombstoneCount -or
            [string]$manifest.SnapshotDbName -cne $parsed.DbName -or
            [string]$manifest.SnapshotDbType -cne $parsed.DbType -or
            [string]$manifest.SnapshotMinTick -cne [string]$parsed.MinTick -or
            [string]$manifest.SnapshotMaxTick -cne [string]$parsed.MaxTick) {
            Throw-DaMaoP3Error 'P3_PACKAGE_CONTENT_MISMATCH' `
                'Manifest facts disagree with the strict snapshot parse.'
        }

        # Authorization deliberately follows byte validation and the strict
        # parse, so no manifest assertion can bypass snapshot structural truth.
        $identity = Get-DaMaoP3AuthorizedIdentity -DbName $parsed.DbName
        if ($identity.LogicalRole -cne $manifest.LogicalRole -or
            $identity.DbName -cne $manifest.DbName -or
            $identity.AutomaticMerge -or $identity.AutomaticRename -or
            $identity.CoexistencePolicy -cne 'preserve_separate' -or
            @($manifest.SchemaIdentities).Count -ne 1 -or
            [string]@($manifest.SchemaIdentities)[0] -cne $identity.SchemaId) {
            Throw-DaMaoP3Error 'P3_PACKAGE_CONTENT_MISMATCH' `
                'Manifest identity fields disagree with Public Baseline V1 authorization.'
        }

        $archive.Dispose()
        $archive = $null
        return [pscustomobject][ordered]@{
            Status = 'Verified'
            PackagePath = $resolved
            PackageSha256 = (Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash
            PackageByteLength = [long]$packageFile.Length
            Manifest = $manifest
            Identity = $identity
            SnapshotPath = $extractedPath
            SnapshotBytes = $snapshotBytes
            SnapshotSha256 = $snapshotSha
            SnapshotByteLength = [long]$snapshotBytes.Length
            Parsed = $parsed
            TempRoot = $tempRoot
            SourceUserIdentityPresent = -not [string]::IsNullOrWhiteSpace([string]$parsed.UserId)
        }
    }
    catch {
        if ($null -ne $tempRoot -and (Test-Path -LiteralPath $tempRoot)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        if ($_.Exception.Message -match '^\[P3_') { throw }
        Throw-DaMaoP3Error 'P3_PACKAGE_INVALID' `
            'The restore package failed closed during ZIP or content validation.'
    }
    finally {
        if ($null -ne $archive) { $archive.Dispose() }
    }
}

function Remove-DaMaoP3Preflight {
    param([AllowNull()]$Preflight)
    if ($null -eq $Preflight -or
        [string]::IsNullOrWhiteSpace([string]$Preflight.TempRoot) -or
        -not (Test-Path -LiteralPath $Preflight.TempRoot)) { return }
    $resolved = [System.IO.Path]::GetFullPath([string]$Preflight.TempRoot)
    $temp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    if (-not $resolved.StartsWith($temp + [System.IO.Path]::DirectorySeparatorChar,
            [System.StringComparison]::OrdinalIgnoreCase) -or
        [System.IO.Path]::GetFileName($resolved) -notlike 'damao-userdb-p3-*') {
        Throw-DaMaoP3Error 'P3_TEMP_CLEANUP_FAILED' `
            'Refusing to clean a restore preflight directory outside the controlled temp root.'
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}

function Get-DaMaoP3TargetContext {
    param(
        [Parameter(Mandatory = $true)][string]$RimeUserDir,
        [Parameter(Mandatory = $true)][string]$DbName,
        [Parameter(Mandatory = $true)][string]$WeaselRoot
    )
    $identity = Get-DaMaoP3AuthorizedIdentity -DbName $DbName
    $environment = Get-DaMaoUserDbEnvironmentStatus -RimeUserDir $RimeUserDir `
        -LogicalRole $identity.LogicalRole -WeaselRoot $WeaselRoot
    if ($environment.LibrimeVersionStatus -cne 'Supported') {
        Throw-DaMaoP3Error 'P3_LIBRIME_MUTATION_UNVERIFIED' `
            'The target detector did not verify librime 1.13.1.'
    }
    $database = @($environment.Databases | Where-Object { $_.DbName -ceq $DbName })
    if ($database.Count -ne 1) {
        Throw-DaMaoP3Error 'P3_TARGET_STATE_REJECTED' `
            'The target database could not be classified exactly once.'
    }
    $state = if ($database[0].LiveDbPresent -and $database[0].LegacyDbPresent) {
        'Ambiguous'
    }
    elseif ($database[0].LiveDbPresent) { 'LiveDb' }
    elseif ($database[0].LegacyDbPresent) { 'LegacyDb' }
    else { 'CleanTarget' }
    if ($state -cne 'LiveDb' -and $state -cne 'CleanTarget') {
        Throw-DaMaoP3Error 'P3_TARGET_STATE_REJECTED' `
            'P3 restore accepts only a clean target or one authorized LiveDb.'
    }
    return [pscustomobject][ordered]@{
        Identity = $identity
        Environment = $environment
        Database = $database[0]
        TargetState = $state
        InstallationId = [string]$environment.InstallationId
        SyncDir = [string]$environment.SyncDir
        WeaselVersion = [string]$environment.WeaselVersion
    }
}

function Confirm-DaMaoP3TargetContextUnchanged {
    param(
        [Parameter(Mandatory = $true)]$Planned,
        [Parameter(Mandatory = $true)][string]$RimeUserDir,
        [Parameter(Mandatory = $true)][string]$DbName,
        [Parameter(Mandatory = $true)][string]$WeaselRoot
    )
    try {
        $current = Get-DaMaoP3TargetContext -RimeUserDir $RimeUserDir `
            -DbName $DbName -WeaselRoot $WeaselRoot
    }
    catch {
        Throw-DaMaoP3Error 'P3_TARGET_STATE_CHANGED' `
            'The target binding changed after restore planning.'
    }
    $same = $current.TargetState -ceq $Planned.TargetState -and
        $current.InstallationId -ceq $Planned.InstallationId -and
        $current.SyncDir -ceq $Planned.SyncDir -and
        $current.Database.DbName -ceq $Planned.Database.DbName -and
        [bool]$current.Database.LiveDbPresent -eq [bool]$Planned.Database.LiveDbPresent -and
        [bool]$current.Database.LegacyDbPresent -eq [bool]$Planned.Database.LegacyDbPresent -and
        [string]::Equals([string]$current.Database.LiveDbPath,
            [string]$Planned.Database.LiveDbPath,
            [System.StringComparison]::OrdinalIgnoreCase) -and
        [string]::Equals([string]$current.Database.LegacyDbPath,
            [string]$Planned.Database.LegacyDbPath,
            [System.StringComparison]::OrdinalIgnoreCase)
    if (-not $same) {
        Throw-DaMaoP3Error 'P3_TARGET_STATE_CHANGED' `
            'The target binding changed after restore planning.'
    }
    return $current
}

function Get-DaMaoP3TargetStateAfterFailure {
    param(
        [Parameter(Mandatory = $true)][string]$RimeUserDir,
        [Parameter(Mandatory = $true)][string]$DbName
    )
    try {
        $root = [System.IO.Path]::GetFullPath($RimeUserDir)
        $live = Test-Path -LiteralPath (Join-Path $root ($DbName + '.userdb')) `
            -PathType Container
        $legacy = Test-Path -LiteralPath (Join-Path $root ($DbName + '.userdb.kct')) `
            -PathType Leaf
        if ($live -and $legacy) { return 'Ambiguous' }
        if ($live) { return 'LiveDb' }
        if ($legacy) { return 'LegacyDb' }
        return 'CleanTarget'
    }
    catch { return 'Unknown' }
}

function Confirm-DaMaoP3RestoreSourceBinding {
    param([Parameter(Mandatory = $true)]$Preflight)
    try {
        $root = [System.IO.Path]::GetFullPath([string]$Preflight.TempRoot).TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        )
        $path = [System.IO.Path]::GetFullPath([string]$Preflight.SnapshotPath)
        $expected = [System.IO.Path]::GetFullPath((Join-Path $root `
            ('snapshots\' + $Preflight.Identity.DbName + '.userdb.txt')))
        if (-not $path.StartsWith($root + [System.IO.Path]::DirectorySeparatorChar,
                [System.StringComparison]::OrdinalIgnoreCase) -or
            -not [string]::Equals($path, $expected,
                [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'binding'
        }
        foreach ($itemPath in @($root, (Split-Path -Parent $path), $path)) {
            $item = Get-Item -LiteralPath $itemPath -Force -ErrorAction Stop
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'reparse'
            }
        }
        [byte[]]$bytes = [System.IO.File]::ReadAllBytes($path)
        if ($bytes.Length -ne [long]$Preflight.SnapshotByteLength -or
            (Get-DaMaoP3BytesSha256 -Bytes $bytes) -cne $Preflight.SnapshotSha256) {
            throw 'bytes'
        }
        $parsed = Read-DaMaoUserDbSnapshot -Path $path -IncludeEntries
        if ($parsed.StructuralHealth -cne 'Healthy' -or
            $parsed.DuplicateKeyCount -ne 0 -or
            $parsed.DbName -cne $Preflight.Parsed.DbName -or
            $parsed.DbType -cne $Preflight.Parsed.DbType -or
            $parsed.Sha256 -cne $Preflight.SnapshotSha256 -or
            $parsed.ByteLength -ne $Preflight.SnapshotByteLength -or
            $parsed.EntryCount -ne $Preflight.Parsed.EntryCount -or
            $parsed.TombstoneCount -ne $Preflight.Parsed.TombstoneCount -or
            [string]$parsed.MinTick -cne [string]$Preflight.Parsed.MinTick -or
            [string]$parsed.MaxTick -cne [string]$Preflight.Parsed.MaxTick) {
            throw 'identity'
        }
    }
    catch {
        Throw-DaMaoP3Error 'P3_RESTORE_SOURCE_CHANGED' `
            'The validated restore source changed before native restore.'
    }
}

function Get-DaMaoP3NormalizedDee {
    param(
        [Parameter(Mandatory = $true)][double]$Dee,
        [Parameter(Mandatory = $true)][uint64]$EntryTick,
        [Parameter(Mandatory = $true)][uint64]$DatabaseTick
    )
    if ($EntryTick -lt $DatabaseTick) {
        return $Dee * [math]::Exp((([double]$EntryTick) - [double]$DatabaseTick) / 200.0)
    }
    return $Dee
}

function Test-DaMaoP3DeeEqual {
    param(
        [Parameter(Mandatory = $true)][double]$Actual,
        [Parameter(Mandatory = $true)][double]$Expected
    )
    $scale = [math]::Max(1.0, [math]::Abs($Expected))
    return [math]::Abs($Actual - $Expected) -le (0.000001 * $scale)
}

function Test-DaMaoP3MergeSemantics {
    param(
        [Parameter(Mandatory = $true)]$SourceParsed,
        [AllowNull()]$PreTargetParsed,
        [Parameter(Mandatory = $true)]$PostParsed,
        [AllowNull()][hashtable]$Faults
    )
    $source = [System.Collections.Generic.Dictionary[string, object]]::new(
        [System.StringComparer]::Ordinal
    )
    $before = [System.Collections.Generic.Dictionary[string, object]]::new(
        [System.StringComparer]::Ordinal
    )
    $after = [System.Collections.Generic.Dictionary[string, object]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($entry in @($SourceParsed.Entries)) { $source.Add([string]$entry.Key, $entry) }
    if ($null -ne $PreTargetParsed) {
        foreach ($entry in @($PreTargetParsed.Entries)) { $before.Add([string]$entry.Key, $entry) }
    }
    foreach ($entry in @($PostParsed.Entries)) { $after.Add([string]$entry.Key, $entry) }

    [uint64]$sourceTick = if ($null -eq $SourceParsed.Tick) { 1 } else { $SourceParsed.Tick }
    [uint64]$targetTick = if ($null -eq $PreTargetParsed -or
        $null -eq $PreTargetParsed.Tick) { 1 } else { $PreTargetParsed.Tick }
    [uint64]$mergedTick = [math]::Max([double]$sourceTick, [double]$targetTick)
    $present = 0
    $tombstones = 0
    $conflicts = 0
    $missing = 0
    $valueMismatches = 0

    foreach ($pair in $source.GetEnumerator()) {
        $key = $pair.Key
        $incoming = $pair.Value
        if (-not $after.ContainsKey($key)) {
            $missing++
            continue
        }
        $present++
        $actual = $after[$key]
        if ($actual.IsTombstone) { $tombstones++ }
        $incomingDee = Get-DaMaoP3NormalizedDee -Dee $incoming.D `
            -EntryTick $incoming.T -DatabaseTick $sourceTick
        $expectedC = [int]$incoming.C
        $expectedDee = [double]$incomingDee
        if ($before.ContainsKey($key)) {
            $ours = $before[$key]
            $ourDee = Get-DaMaoP3NormalizedDee -Dee $ours.D `
                -EntryTick $ours.T -DatabaseTick $targetTick
            $expectedC = [int]$ours.C
            if ([math]::Abs([int]$ours.C) -lt [math]::Abs([int]$incoming.C)) {
                $expectedC = [int]$incoming.C
            }
            $expectedDee = [math]::Max([double]$ourDee, [double]$incomingDee)
        }
        $valueMatches = [int]$actual.C -eq $expectedC -and
            [uint64]$actual.T -eq $mergedTick -and
            (Test-DaMaoP3DeeEqual -Actual $actual.D -Expected $expectedDee)
        if (-not $valueMatches) { $valueMismatches++ }
        elseif ($before.ContainsKey($key)) { $conflicts++ }
    }

    $targetOnlyExpected = 0
    $targetOnlyPreserved = 0
    foreach ($pair in $before.GetEnumerator()) {
        if ($source.ContainsKey($pair.Key)) { continue }
        $targetOnlyExpected++
        if (-not $after.ContainsKey($pair.Key)) { continue }
        $old = $pair.Value
        $actual = $after[$pair.Key]
        if ([int]$actual.C -eq [int]$old.C -and
            [uint64]$actual.T -eq [uint64]$old.T -and
            (Test-DaMaoP3DeeEqual -Actual $actual.D -Expected $old.D)) {
            $targetOnlyPreserved++
        }
    }
    if (Test-DaMaoP3Fault $Faults 'SemanticMissing') { $missing++ }
    $verified = $missing -eq 0 -and $valueMismatches -eq 0 -and
        $targetOnlyPreserved -eq $targetOnlyExpected
    return [pscustomobject][ordered]@{
        Status = if ($verified) { 'Verified' } else { 'Failed' }
        SourceEntryCount = $source.Count
        VerifiedPresentCount = $present
        VerifiedTombstoneCount = $tombstones
        ConflictResolvedCount = $conflicts
        TargetOnlyExpectedCount = $targetOnlyExpected
        TargetOnlyPreservedCount = $targetOnlyPreserved
        MissingCount = $missing
        ValueMismatchCount = $valueMismatches
    }
}

function New-DaMaoP3RestoreReceipt {
    param(
        [Parameter(Mandatory = $true)]$Preflight,
        [Parameter(Mandatory = $true)]$Target
    )
    return [pscustomobject][ordered]@{
        Status = 'Planned'
        FailureCode = $null
        LogicalRole = [string]$Preflight.Identity.LogicalRole
        DbName = [string]$Preflight.Identity.DbName
        PackageSha256 = [string]$Preflight.PackageSha256
        SnapshotSha256 = [string]$Preflight.SnapshotSha256
        TargetStateBefore = [string]$Target.TargetState
        PreRestoreSafetyBackupStatus = if ($Target.TargetState -ceq 'LiveDb') {
            'Pending'
        } else { 'NotApplicable_CleanTarget' }
        PreRestoreSafetyBackupPath = $null
        PreRestoreSafetyBackupSha256 = $null
        PreRestoreBackupSemantics = 'SafetyArtifactNotRollbackPoint'
        PreRestoreVerificationBaseline = if ($Target.TargetState -ceq 'LiveDb') {
            'CanonicalStateAfterSafetyBackup'
        } else { 'NoPreExistingTarget' }
        SafetyBackupMutationCapability = if ($Target.TargetState -ceq 'LiveDb') {
            'PotentialMetadataMutation'
        } else { 'NotApplicable_CleanTarget' }
        NativeRestoreStatus = 'NotStarted'
        NativeMutationSessionStarted = $false
        NativeRestoreAttempted = $false
        TargetMayHaveBeenModified = $false
        TargetStateAfterFailure = $null
        PostRestoreVerificationStatus = 'NotStarted'
        PostRestoreDiagnosticBackupPath = $null
        PostRestoreDiagnosticBackupSha256 = $null
        SourceEntryCount = [int]$Preflight.Parsed.EntryCount
        VerifiedPresentCount = 0
        VerifiedTombstoneCount = 0
        ConflictResolvedCount = 0
        TargetOnlyPreservedCount = 0
        MissingCount = [int]$Preflight.Parsed.EntryCount
        SourceUserIdentityPresent = [bool]$Preflight.SourceUserIdentityPresent
        TargetUserIdentityBoundToCurrentMachine = $false
        RepeatedRestoreSemantics = 'ReentrantUnderVerifiedSemantics'
        LibrimeVersion = $null
        WeaselVersion = [string]$Target.WeaselVersion
        SupportedArchitecture = 'x64'
        ObservedRimeApiDataSize = 0
        ObservedRimeLeversApiDataSize = 0
        MaintenanceStatus = 'NotEntered'
        CleanupStatus = 'Pending'
        MaintenanceContinuity = 'SingleOuterWindow'
        ManualReviewRequired = $false
        TransactionalRestore = $false
        RollbackAvailable = $false
        CreatedUtc = [datetime]::UtcNow.ToString('o',
            [System.Globalization.CultureInfo]::InvariantCulture)
        Sensitive = $true
    }
}

function ConvertTo-DaMaoP3ReceiptJson {
    param(
        [Parameter(Mandatory = $true)]$Receipt,
        [AllowNull()][hashtable]$Faults
    )
    if (Test-DaMaoP3Fault $Faults 'ReceiptSerialization') {
        Throw-DaMaoP3Error 'P3_RECEIPT_SERIALIZATION_FAILED' `
            'Restore receipt serialization failed.'
    }
    try { return $Receipt | ConvertTo-Json -Depth 8 }
    catch {
        Throw-DaMaoP3Error 'P3_RECEIPT_SERIALIZATION_FAILED' `
            'Restore receipt serialization failed.'
    }
}

function Restore-DaMaoUserDbPackageV2 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$PackagePath,
        [string]$RimeUserDir = (Join-Path $env:APPDATA 'Rime'),
        [AllowNull()][string]$RimeDll,
        [AllowNull()][string]$RimeSharedDataDir,
        [AllowNull()][string]$WeaselRoot,
        [AllowNull()][string]$SafetyBackupDirectory,
        [AllowNull()][string]$DiagnosticBackupDirectory,
        [ValidateRange(1, 120)][int]$MaintenanceTimeoutSeconds = 15,
        [switch]$Synthetic,
        [AllowNull()][hashtable]$Faults
    )

    # Package verification and extraction intentionally precede target detection,
    # maintenance entry, safety backup, and every native mutation.
    $preflight = Read-DaMaoUserDbPackageV2ForRestore -PackagePath $PackagePath
    $safetyPreflight = $null
    $diagnosticPreflight = $null
    $maintenance = $null
    $receipt = $null
    $cleanupWarning = $false
    try {
        $RimeDll = Resolve-DaMaoP2RimeDll -Path $RimeDll
        if ([string]::IsNullOrWhiteSpace($RimeSharedDataDir)) {
            $RimeSharedDataDir = Join-Path (Split-Path -Parent $RimeDll) 'data'
        }
        if ([string]::IsNullOrWhiteSpace($WeaselRoot)) {
            $WeaselRoot = Split-Path -Parent $RimeDll
        }
        $target = Get-DaMaoP3TargetContext -RimeUserDir $RimeUserDir `
            -DbName $preflight.Identity.DbName -WeaselRoot $WeaselRoot
        $receipt = New-DaMaoP3RestoreReceipt -Preflight $preflight -Target $target
        $packageDirectory = Split-Path -Parent $preflight.PackagePath
        if ([string]::IsNullOrWhiteSpace($SafetyBackupDirectory)) {
            $SafetyBackupDirectory = Join-Path $packageDirectory 'pre-restore-safety-backups'
        }
        if ([string]::IsNullOrWhiteSpace($DiagnosticBackupDirectory)) {
            $DiagnosticBackupDirectory = Join-Path $packageDirectory 'post-restore-diagnostics'
        }

        if (Test-DaMaoP3Fault $Faults 'MaintenanceEntry') {
            Throw-DaMaoP3Error 'P3_MAINTENANCE_FAILED' `
                'The restore maintenance window could not be entered.'
        }
        try {
            $script:DaMaoP3MaintenanceEntryCount++
            $maintenance = Enter-DaMaoP2MaintenanceWindow -WeaselRoot $WeaselRoot `
                -TimeoutSeconds $MaintenanceTimeoutSeconds -Synthetic:$Synthetic
            $receipt.MaintenanceStatus = [string]$maintenance.Status
        }
        catch {
            Throw-DaMaoP3Error 'P3_MAINTENANCE_FAILED' `
                'The restore maintenance window could not be entered.'
        }

        if ($null -ne $Faults -and $Faults.ContainsKey('AfterMaintenanceEntered') -and
            $Faults.AfterMaintenanceEntered -is [scriptblock]) {
            & $Faults.AfterMaintenanceEntered
        }
        $target = Confirm-DaMaoP3TargetContextUnchanged -Planned $target `
            -RimeUserDir $RimeUserDir -DbName $preflight.Identity.DbName `
            -WeaselRoot $WeaselRoot

        if ($target.TargetState -ceq 'LiveDb') {
            if (Test-DaMaoP3Fault $Faults 'SafetyBackup') {
                Throw-DaMaoP3Error 'P3_SAFETY_BACKUP_FAILED' `
                    'The pre-restore safety backup failed; restore was not started.'
            }
            try {
                $script:DaMaoP3BackupCallCount++
                $safety = Backup-DaMaoUserDbPackageV2 `
                    -DbName $preflight.Identity.DbName `
                    -OutputDirectory $SafetyBackupDirectory `
                    -RimeUserDir $RimeUserDir -RimeDll $RimeDll `
                    -RimeSharedDataDir $RimeSharedDataDir -WeaselRoot $WeaselRoot `
                    -Synthetic
                $safetyPreflight = Read-DaMaoUserDbPackageV2ForRestore `
                    -PackagePath $safety.PackagePath
                $receipt.PreRestoreSafetyBackupStatus = 'Completed'
                $receipt.PreRestoreSafetyBackupPath = [string]$safety.PackagePath
                $receipt.PreRestoreSafetyBackupSha256 = [string]$safety.PackageSha256
            }
            catch {
                if ($_.Exception.Message -match '^\[P3_') { throw }
                Throw-DaMaoP3Error 'P3_SAFETY_BACKUP_FAILED' `
                    'The pre-restore safety backup failed; restore was not started.'
            }
        }

        if ($null -ne $Faults -and $Faults.ContainsKey('AfterSafetyBackup') -and
            $Faults.AfterSafetyBackup -is [scriptblock]) {
            & $Faults.AfterSafetyBackup
        }

        $target = Confirm-DaMaoP3TargetContextUnchanged -Planned $target `
            -RimeUserDir $RimeUserDir -DbName $preflight.Identity.DbName `
            -WeaselRoot $WeaselRoot

        Import-DaMaoRimeRestoreAdapter
        $nativeFailure = $null
        $nativeInitialized = $false
        $sourceLock = $null
        try {
            if (Test-DaMaoP3Fault $Faults 'RestoreApiUnavailable') {
                Throw-DaMaoP3Error 'P3_RESTORE_API_UNAVAILABLE' `
                    'restore_user_dict is unavailable.'
            }
            if (Test-DaMaoP3Fault $Faults 'RestoreSourceChanged') {
                (Get-Item -LiteralPath $preflight.SnapshotPath -Force).IsReadOnly = $false
                [System.IO.File]::AppendAllText($preflight.SnapshotPath, "# changed`n",
                    [System.Text.UTF8Encoding]::new($false))
            }
            $sourceLock = [System.IO.File]::Open(
                $preflight.SnapshotPath, [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read
            )
            Confirm-DaMaoP3RestoreSourceBinding -Preflight $preflight
            $script:DaMaoP3NativeMutationSessionCount++
            $receipt.NativeMutationSessionStarted = $true
            [DaMaoRimeRestoreAdapter]::Initialize(
                [System.IO.Path]::GetFullPath($RimeDll),
                [System.IO.Path]::GetFullPath($RimeSharedDataDir),
                [System.IO.Path]::GetFullPath($RimeUserDir),
                (Join-Path ([System.IO.Path]::GetFullPath($RimeUserDir)) 'build')
            )
            $nativeInitialized = $true
            $receipt.LibrimeVersion = [DaMaoRimeRestoreAdapter]::LibrimeVersion
            $receipt.ObservedRimeApiDataSize = [DaMaoRimeRestoreAdapter]::MainApiDataSize
            $receipt.ObservedRimeLeversApiDataSize = [DaMaoRimeRestoreAdapter]::LeversApiDataSize
            Confirm-DaMaoP3RestoreSourceBinding -Preflight $preflight
            $receipt.NativeRestoreAttempted = $true
            if (Test-DaMaoP3Fault $Faults 'RestoreException') {
                Throw-DaMaoP3Error 'P3_NATIVE_RESTORE_FAILED' `
                    'The injected native restore call failed.'
            }
            if ((Test-DaMaoP3Fault $Faults 'RestoreFalse') -or
                (Test-DaMaoP3Fault $Faults 'TargetReopenFailure')) {
                $restored = $false
            }
            else {
                $restored = [DaMaoRimeRestoreAdapter]::RestoreUserDictionary(
                    $preflight.SnapshotPath
                )
                if (Test-DaMaoP3Fault $Faults 'RestoreFalseAfterCall') {
                    $restored = $false
                }
            }
            if (-not $restored) {
                Throw-DaMaoP3Error 'P3_NATIVE_RESTORE_FAILED' `
                    'librime restore_user_dict returned false.'
            }
            $receipt.NativeRestoreStatus = 'Completed'
        }
        catch {
            $nativeFailure = 'P3_NATIVE_RESTORE_FAILED'
            if ($_.Exception.Message -match '^\[(P3_[A-Z0-9_]+)\]') {
                $nativeFailure = $matches[1]
            }
            elseif ($_.Exception.InnerException -is [DaMaoRimeP3Exception]) {
                $nativeFailure = $_.Exception.InnerException.ErrorCode
            }
            elseif ($_.Exception -is [DaMaoRimeP3Exception]) {
                $nativeFailure = $_.Exception.ErrorCode
            }
        }
        finally {
            if ($null -ne $sourceLock) { $sourceLock.Dispose() }
            try {
                if ($nativeInitialized -or [DaMaoRimeRestoreAdapter]::IsInitialized) {
                    [DaMaoRimeRestoreAdapter]::Shutdown()
                }
                if (Test-DaMaoP3Fault $Faults 'FinalizeFailure') {
                    Throw-DaMaoP3Error 'P3_NATIVE_FINALIZE_FAILED' `
                        'The injected native finalize path failed.'
                }
            }
            catch {
                $nativeFailure = 'P3_NATIVE_FINALIZE_FAILED'
            }
        }

        if ($null -ne $nativeFailure) {
            $receipt.TargetMayHaveBeenModified = [bool]$receipt.NativeMutationSessionStarted
            $receipt.TargetStateAfterFailure = Get-DaMaoP3TargetStateAfterFailure `
                -RimeUserDir $RimeUserDir -DbName $preflight.Identity.DbName
            $receipt.Status = if ($receipt.TargetMayHaveBeenModified) {
                'RestoreFailedTargetMayBeModified'
            } else { 'RestoreFailed' }
            $receipt.FailureCode = $nativeFailure
            $receipt.NativeRestoreStatus = 'Failed'
            $receipt.ManualReviewRequired = $true
        }
        else {
            [byte[]]$sourceAfter = [System.IO.File]::ReadAllBytes($preflight.SnapshotPath)
            if ((Get-DaMaoP3BytesSha256 $sourceAfter) -cne $preflight.SnapshotSha256 -or
                $sourceAfter.Length -ne $preflight.SnapshotByteLength) {
                $receipt.Status = 'RestoreCompletedVerificationFailed'
                $receipt.FailureCode = 'P3_POST_RESTORE_VERIFICATION_FAILED'
                $receipt.NativeRestoreStatus = 'Completed'
                $receipt.PostRestoreVerificationStatus = 'Failed'
                $receipt.ManualReviewRequired = $true
            }
            elseif (Test-DaMaoP3Fault $Faults 'PostRestoreBackup') {
                $receipt.Status = 'RestoreCompletedVerificationFailed'
                $receipt.FailureCode = 'P3_POST_RESTORE_BACKUP_FAILED'
                $receipt.PostRestoreVerificationStatus = 'BackupFailed'
                $receipt.ManualReviewRequired = $true
            }
            else {
                try {
                    $diagnostic = Backup-DaMaoUserDbPackageV2 `
                        -DbName $preflight.Identity.DbName `
                        -OutputDirectory $DiagnosticBackupDirectory `
                        -RimeUserDir $RimeUserDir -RimeDll $RimeDll `
                        -RimeSharedDataDir $RimeSharedDataDir -WeaselRoot $WeaselRoot `
                        -Synthetic
                    $receipt.PostRestoreDiagnosticBackupPath = [string]$diagnostic.PackagePath
                    $receipt.PostRestoreDiagnosticBackupSha256 = [string]$diagnostic.PackageSha256
                    if (Test-DaMaoP3Fault $Faults 'PostRestoreParse') {
                        Throw-DaMaoP3Error 'P3_POST_RESTORE_PARSE_FAILED' `
                            'The post-restore canonical snapshot failed parsing.'
                    }
                    $diagnosticPreflight = Read-DaMaoUserDbPackageV2ForRestore `
                        -PackagePath $diagnostic.PackagePath
                    $semantic = Test-DaMaoP3MergeSemantics `
                        -SourceParsed $preflight.Parsed `
                        -PreTargetParsed $(if ($null -ne $safetyPreflight) {
                                $safetyPreflight.Parsed
                            } else { $null }) `
                        -PostParsed $diagnosticPreflight.Parsed -Faults $Faults
                    $receipt.SourceEntryCount = [int]$semantic.SourceEntryCount
                    $receipt.VerifiedPresentCount = [int]$semantic.VerifiedPresentCount
                    $receipt.VerifiedTombstoneCount = [int]$semantic.VerifiedTombstoneCount
                    $receipt.ConflictResolvedCount = [int]$semantic.ConflictResolvedCount
                    $receipt.TargetOnlyPreservedCount = [int]$semantic.TargetOnlyPreservedCount
                    $receipt.MissingCount = [int]$semantic.MissingCount
                    $receipt.TargetUserIdentityBoundToCurrentMachine = (
                        $diagnosticPreflight.Parsed.UserId -ceq $target.InstallationId
                    )
                    if ($semantic.Status -cne 'Verified' -or
                        -not $receipt.TargetUserIdentityBoundToCurrentMachine) {
                        Throw-DaMaoP3Error 'P3_POST_RESTORE_VERIFICATION_FAILED' `
                            'Post-restore semantic verification requires manual review.'
                    }
                    $receipt.PostRestoreVerificationStatus = 'Verified'
                    $receipt.Status = 'Success'
                }
                catch {
                    $receipt.Status = 'RestoreCompletedVerificationFailed'
                    $receipt.FailureCode = if ($_.Exception.Message -match
                        '^\[(P3_[A-Z0-9_]+)\]') { $matches[1] }
                        else { 'P3_POST_RESTORE_VERIFICATION_FAILED' }
                    $receipt.PostRestoreVerificationStatus = 'Failed'
                    $receipt.ManualReviewRequired = $true
                }
            }
        }
    }
    finally {
        if ($null -ne $maintenance) {
            $maintenance = Exit-DaMaoP2MaintenanceWindow -Maintenance $maintenance `
                -Faults $Faults
            if ($null -ne $receipt) {
                $receipt.MaintenanceStatus = [string]$maintenance.Status
                if ($maintenance.ErrorCode -and $receipt.Status -ceq 'Success') {
                    $receipt.Status = 'CompletedWithMaintenanceWarning'
                    $receipt.FailureCode = 'P3_MAINTENANCE_FAILED'
                }
            }
        }
        foreach ($item in @($diagnosticPreflight, $safetyPreflight, $preflight)) {
            if ($null -ne $item) {
                try { Remove-DaMaoP3Preflight -Preflight $item }
                catch { $cleanupWarning = $true }
            }
        }
        if (Test-DaMaoP3Fault $Faults 'TempCleanup') { $cleanupWarning = $true }
        if ($null -ne $receipt) {
            $receipt.CleanupStatus = if ($cleanupWarning) {
                'SensitiveTemporaryArtifactCleanupFailed'
            } else { 'Completed' }
            if ($cleanupWarning -and $receipt.Status -ceq 'Success') {
                $receipt.Status = 'CompletedWithCleanupWarning'
                $receipt.FailureCode = 'P3_TEMP_CLEANUP_FAILED'
            }
        }
    }
    if (Test-DaMaoP3Fault $Faults 'ReceiptSerialization') {
        if ($receipt.PostRestoreVerificationStatus -ceq 'Verified') {
            Throw-DaMaoP3Error 'P3_RECEIPT_SERIALIZATION_FAILED' `
                'Restore was verified, but receipt serialization failed; no restore was retried or reversed.'
        }
        [void](ConvertTo-DaMaoP3ReceiptJson -Receipt $receipt -Faults $Faults)
    }
    return $receipt
}
