$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'DaMao.UserDbSnapshot.ps1')

$script:DaMaoP2PackageFormat = 'DaMao.UserDbPortabilityPackage'
$script:DaMaoP2PackageVersion = 2
$script:DaMaoP2SupportedLibrimeVersion = '1.13.1'
$script:DaMaoP2MaximumSnapshotBytes = 268435456L
$script:DaMaoP2ErrorCodes = @(
    'P2_RIME_API_UNAVAILABLE',
    'P2_LEVERS_MODULE_UNAVAILABLE',
    'P2_LEVERS_API_INCOMPATIBLE',
    'P2_BACKUP_API_UNAVAILABLE',
    'P2_NATIVE_INITIALIZATION_FAILED',
    'P2_NATIVE_BACKUP_FAILED',
    'P2_NATIVE_ARCHITECTURE_UNSUPPORTED',
    'P2_LIBRIME_MUTATION_UNVERIFIED',
    'P2_TARGET_EXCLUDED',
    'P2_TARGET_UNCLASSIFIED',
    'P2_TARGET_STATE_REJECTED',
    'P2_MAINTENANCE_FAILED',
    'P2_CANONICAL_SNAPSHOT_NOT_FOUND',
    'P2_CANONICAL_SNAPSHOT_INVALID',
    'P2_CANONICAL_DB_IDENTITY_MISMATCH',
    'P2_CANONICAL_SNAPSHOT_CHANGED_DURING_READ',
    'P2_MANIFEST_SERIALIZATION_FAILED',
    'P2_TEMP_ZIP_FAILED',
    'P2_ZIP_READBACK_FAILED',
    'P2_FINAL_PUBLISH_FAILED'
    'P2_PACKAGE_DESTINATION_EXISTS'
)

function Get-DaMaoUserDbP2ErrorCodes {
    return @($script:DaMaoP2ErrorCodes)
}

function Throw-DaMaoP2Error {
    param(
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Message
    )
    throw "[$Code] $Message"
}

function Test-DaMaoP2Fault {
    param(
        [AllowNull()][hashtable]$Faults,
        [Parameter(Mandatory = $true)][string]$Name
    )
    return $null -ne $Faults -and $Faults.ContainsKey($Name) -and [bool]$Faults[$Name]
}

function Import-DaMaoRimeLeversAdapter {
    if ('DaMaoRimeLeversAdapter' -as [type]) {
        return
    }
    $sourcePath = Join-Path $PSScriptRoot 'DaMao.RimeLeversAdapter.cs'
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        Throw-DaMaoP2Error 'P2_RIME_API_UNAVAILABLE' 'The native adapter source is unavailable.'
    }
    try {
        Add-Type -TypeDefinition ([System.IO.File]::ReadAllText($sourcePath)) `
            -Language CSharp -ErrorAction Stop
    }
    catch {
        Throw-DaMaoP2Error 'P2_NATIVE_INITIALIZATION_FAILED' `
            'The native adapter could not be compiled for this PowerShell host.'
    }
}

function Resolve-DaMaoP2RimeDll {
    param([AllowNull()][string]$Path)

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    if ([string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        Throw-DaMaoP2Error 'P2_RIME_API_UNAVAILABLE' `
            'The standard Program Files location is unavailable; specify RimeDll explicitly.'
    }
    $candidate = Join-Path (Join-Path $env:ProgramFiles 'Rime') `
        'weasel-0.17.4\rime.dll'
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        Throw-DaMaoP2Error 'P2_RIME_API_UNAVAILABLE' `
            'The pinned Weasel rime.dll was not detected; specify RimeDll explicitly.'
    }
    return [System.IO.Path]::GetFullPath($candidate)
}

function Get-DaMaoP2AuthorizedIdentity {
    param([Parameter(Mandatory = $true)][string]$DbName)

    $contractPath = Join-Path (Split-Path -Parent $PSScriptRoot) `
        'contracts\public-baseline-v1.json'
    $contract = Get-Content -LiteralPath $contractPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($exclusion in @($contract.identity_contract.default_exclusions)) {
        if ([string]$exclusion.db_name -ceq $DbName) {
            Throw-DaMaoP2Error 'P2_TARGET_EXCLUDED' `
                'The requested physical database is excluded by default.'
        }
    }
    foreach ($role in @($contract.identity_contract.logical_roles)) {
        foreach ($identity in @($role.physical_identities)) {
            if ([string]$identity.db_name -ceq $DbName) {
                return [pscustomobject][ordered]@{
                    LogicalRole = [string]$role.logical_role
                    SchemaId = [string]$identity.schema_id
                    DbName = [string]$identity.db_name
                    IdentityId = [string]$identity.identity_id
                    AutomaticMerge = [bool]$role.automatic_merge
                    AutomaticRename = [bool]$role.automatic_rename
                    CoexistencePolicy = [string]$role.coexistence_policy
                }
            }
        }
    }
    Throw-DaMaoP2Error 'P2_TARGET_UNCLASSIFIED' `
        'The requested physical database is not authorized by Public Baseline V1.'
}

function Get-DaMaoP2CanonicalSnapshotPath {
    param(
        [Parameter(Mandatory = $true)]$EnvironmentStatus,
        [Parameter(Mandatory = $true)][string]$DbName
    )

    if ([string]::IsNullOrWhiteSpace([string]$EnvironmentStatus.SyncDir) -or
        [string]::IsNullOrWhiteSpace([string]$EnvironmentStatus.InstallationId)) {
        Throw-DaMaoP2Error 'P2_CANONICAL_SNAPSHOT_NOT_FOUND' `
            'The current installation sync identity is unavailable.'
    }
    $syncRoot = [System.IO.Path]::GetFullPath([string]$EnvironmentStatus.SyncDir).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $currentDirectory = [System.IO.Path]::GetFullPath(
        (Join-Path $syncRoot ([string]$EnvironmentStatus.InstallationId))
    )
    if (-not $currentDirectory.StartsWith(
            $syncRoot + [System.IO.Path]::DirectorySeparatorChar,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        Throw-DaMaoP2Error 'P2_CANONICAL_SNAPSHOT_NOT_FOUND' `
            'The current installation sync directory escaped the configured sync root.'
    }
    return Join-Path $currentDirectory ($DbName + '.userdb.txt')
}

function Get-DaMaoP2StableSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$RequestedDbName,
        [AllowNull()][hashtable]$Faults
    )

    if (Test-DaMaoP2Fault $Faults 'SnapshotMissing') {
        Throw-DaMaoP2Error 'P2_CANONICAL_SNAPSHOT_NOT_FOUND' `
            'The canonical snapshot was not found after native backup.'
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Throw-DaMaoP2Error 'P2_CANONICAL_SNAPSHOT_NOT_FOUND' `
            'The canonical snapshot was not found after native backup.'
    }

    $file = Get-Item -LiteralPath $Path -Force
    if (($file.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        Throw-DaMaoP2Error 'P2_CANONICAL_SNAPSHOT_INVALID' `
            'A reparse-point snapshot payload is forbidden.'
    }
    $beforeLength = [long]$file.Length
    $beforeWrite = $file.LastWriteTimeUtc.Ticks
    if ($beforeLength -le 0 -or $beforeLength -gt $script:DaMaoP2MaximumSnapshotBytes) {
        Throw-DaMaoP2Error 'P2_CANONICAL_SNAPSHOT_INVALID' `
            'The canonical snapshot size is outside the accepted bound.'
    }

    [byte[]]$firstBytes = [System.IO.File]::ReadAllBytes($Path)
    if (Test-DaMaoP2Fault $Faults 'UnstableRead') {
        $beforeLength++
    }
    $middle = Get-Item -LiteralPath $Path -Force
    [byte[]]$secondBytes = [System.IO.File]::ReadAllBytes($Path)
    $after = Get-Item -LiteralPath $Path -Force
    if ($beforeLength -ne [long]$middle.Length -or
        $beforeLength -ne [long]$after.Length -or
        $beforeWrite -ne $middle.LastWriteTimeUtc.Ticks -or
        $beforeWrite -ne $after.LastWriteTimeUtc.Ticks -or
        $firstBytes.Length -ne $secondBytes.Length) {
        Throw-DaMaoP2Error 'P2_CANONICAL_SNAPSHOT_CHANGED_DURING_READ' `
            'The canonical snapshot changed during stable read validation.'
    }

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $firstHash = ([System.BitConverter]::ToString($sha.ComputeHash($firstBytes))).Replace('-', '')
        $secondHash = ([System.BitConverter]::ToString($sha.ComputeHash($secondBytes))).Replace('-', '')
    }
    finally {
        $sha.Dispose()
    }
    if ($firstHash -cne $secondHash) {
        Throw-DaMaoP2Error 'P2_CANONICAL_SNAPSHOT_CHANGED_DURING_READ' `
            'The canonical snapshot content changed during stable read validation.'
    }

    $parsed = Read-DaMaoUserDbSnapshot -Path $Path
    if (($null -ne $parsed.DbName -and $parsed.DbName -cne $RequestedDbName) -or
        ($null -ne $parsed.DbType -and $parsed.DbType -cne 'userdb')) {
        Throw-DaMaoP2Error 'P2_CANONICAL_DB_IDENTITY_MISMATCH' `
            'The canonical snapshot identity does not match the authorized request.'
    }
    if ($parsed.StructuralHealth -cne 'Healthy' -or
        $parsed.DuplicateKeyCount -ne 0 -or
        $parsed.ByteLength -le 0 -or
        [string]::IsNullOrWhiteSpace([string]$parsed.Sha256) -or
        $null -eq $parsed.EntryCount) {
        Throw-DaMaoP2Error 'P2_CANONICAL_SNAPSHOT_INVALID' `
            'The canonical snapshot failed strict P1 structural validation.'
    }
    if ($parsed.DbName -cne $RequestedDbName -or $parsed.DbType -cne 'userdb') {
        Throw-DaMaoP2Error 'P2_CANONICAL_DB_IDENTITY_MISMATCH' `
            'The canonical snapshot identity does not match the authorized request.'
    }
    if ($parsed.Sha256 -cne $firstHash -or $parsed.ByteLength -ne $firstBytes.Length) {
        Throw-DaMaoP2Error 'P2_CANONICAL_SNAPSHOT_CHANGED_DURING_READ' `
            'The strict parser did not observe the stable snapshot bytes.'
    }

    return [pscustomobject][ordered]@{
        Path = [System.IO.Path]::GetFullPath($Path)
        Bytes = $firstBytes
        Parsed = $parsed
        Sha256 = $firstHash
        ByteLength = [long]$firstBytes.Length
    }
}

function ConvertTo-DaMaoP2JsonBytes {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [AllowNull()][hashtable]$Faults
    )
    if (Test-DaMaoP2Fault $Faults 'ManifestSerialization') {
        Throw-DaMaoP2Error 'P2_MANIFEST_SERIALIZATION_FAILED' `
            'Manifest serialization failed.'
    }
    try {
        $json = $Value | ConvertTo-Json -Depth 10
        return ([System.Text.UTF8Encoding]::new($false)).GetBytes($json + "`n")
    }
    catch {
        Throw-DaMaoP2Error 'P2_MANIFEST_SERIALIZATION_FAILED' `
            'Manifest serialization failed.'
    }
}

function Get-DaMaoP2BytesSha256 {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '')
    }
    finally {
        $sha.Dispose()
    }
}

function Assert-DaMaoP2ZipEntryName {
    param([Parameter(Mandatory = $true)][string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name) -or
        [System.IO.Path]::IsPathRooted($Name) -or
        $Name.Contains('\') -or $Name.Contains(':') -or
        $Name.StartsWith('/', [System.StringComparison]::Ordinal) -or
        @($Name.Split('/') | Where-Object { $_ -eq '..' -or $_ -eq '.' -or $_ -eq '' }).Count -gt 0) {
        Throw-DaMaoP2Error 'P2_ZIP_READBACK_FAILED' `
            'The package contains a non-canonical entry path.'
    }
}

function Test-DaMaoP2ZipReadback {
    param(
        [Parameter(Mandatory = $true)][string]$ZipPath,
        [Parameter(Mandatory = $true)][string]$DbName,
        [Parameter(Mandatory = $true)][string]$SnapshotSha256,
        [Parameter(Mandatory = $true)][long]$SnapshotByteLength,
        [AllowNull()][hashtable]$Faults
    )

    if (Test-DaMaoP2Fault $Faults 'ZipReadback') {
        Throw-DaMaoP2Error 'P2_ZIP_READBACK_FAILED' 'ZIP readback validation failed.'
    }
    Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
    $archive = $null
    try {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
        $entries = @($archive.Entries)
        if ($entries.Count -ne 2) {
            Throw-DaMaoP2Error 'P2_ZIP_READBACK_FAILED' `
                'A single-database package must contain exactly two entries.'
        }
        $expectedSnapshot = 'snapshots/' + $DbName + '.userdb.txt'
        $allowed = @('manifest.json', $expectedSnapshot)
        $seen = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )
        foreach ($entry in $entries) {
            Assert-DaMaoP2ZipEntryName -Name $entry.FullName
            if (-not $seen.Add($entry.FullName) -or $allowed -cnotcontains $entry.FullName) {
                Throw-DaMaoP2Error 'P2_ZIP_READBACK_FAILED' `
                    'The package contains duplicate, colliding, or non-whitelisted entries.'
            }
        }
        if ($seen.Count -ne 2) {
            Throw-DaMaoP2Error 'P2_ZIP_READBACK_FAILED' `
                'The package whitelist is incomplete.'
        }

        $snapshotEntry = @($entries | Where-Object { $_.FullName -ceq $expectedSnapshot })[0]
        if ($snapshotEntry.Length -ne $SnapshotByteLength -or
            $snapshotEntry.Length -gt $script:DaMaoP2MaximumSnapshotBytes) {
            Throw-DaMaoP2Error 'P2_ZIP_READBACK_FAILED' `
                'The packaged snapshot length does not match the staged snapshot.'
        }
        $snapshotStream = $snapshotEntry.Open()
        $memory = New-Object System.IO.MemoryStream
        try {
            $snapshotStream.CopyTo($memory)
            [byte[]]$readbackBytes = $memory.ToArray()
        }
        finally {
            $memory.Dispose()
            $snapshotStream.Dispose()
        }
        if ((Get-DaMaoP2BytesSha256 $readbackBytes) -cne $SnapshotSha256) {
            Throw-DaMaoP2Error 'P2_ZIP_READBACK_FAILED' `
                'The packaged snapshot hash does not match the staged snapshot.'
        }

        $manifestEntry = @($entries | Where-Object { $_.FullName -ceq 'manifest.json' })[0]
        if ($manifestEntry.Length -le 0 -or $manifestEntry.Length -gt 1048576) {
            Throw-DaMaoP2Error 'P2_ZIP_READBACK_FAILED' 'The manifest size is invalid.'
        }
        $reader = New-Object System.IO.StreamReader(
            $manifestEntry.Open(), [System.Text.UTF8Encoding]::new($false, $true)
        )
        try {
            $manifest = $reader.ReadToEnd() | ConvertFrom-Json
        }
        finally {
            $reader.Dispose()
        }
        if ($manifest.PackageFormat -cne $script:DaMaoP2PackageFormat -or
            $manifest.PackageFormatVersion -ne $script:DaMaoP2PackageVersion -or
            $manifest.DbName -cne $DbName -or
            $manifest.SnapshotFile -cne $expectedSnapshot -or
            $manifest.SnapshotSha256 -cne $SnapshotSha256 -or
            $manifest.SnapshotByteLength -ne $SnapshotByteLength -or
            -not [bool]$manifest.ContainsUserDictionaryData -or
            [bool]$manifest.AutomaticMerge -or [bool]$manifest.AutomaticRename) {
            Throw-DaMaoP2Error 'P2_ZIP_READBACK_FAILED' `
                'The manifest failed semantic readback validation.'
        }
    }
    catch {
        if ($_.Exception.Message -match '^\[P2_ZIP_READBACK_FAILED\]') { throw }
        Throw-DaMaoP2Error 'P2_ZIP_READBACK_FAILED' 'ZIP readback validation failed.'
    }
    finally {
        if ($null -ne $archive) { $archive.Dispose() }
    }
}

function New-DaMaoUserDbPackageV2FromSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SnapshotPath,
        [Parameter(Mandatory = $true)][string]$DbName,
        [Parameter(Mandatory = $true)][string]$OutputDirectory,
        [Parameter(Mandatory = $true)][string]$SourceLibrimeVersion,
        [AllowNull()][string]$SourceWeaselVersion,
        [AllowNull()][Nullable[datetime]]$CreatedUtc,
        [AllowNull()][hashtable]$Faults
    )

    $identity = Get-DaMaoP2AuthorizedIdentity -DbName $DbName
    if ($identity.AutomaticMerge -or $identity.AutomaticRename -or
        $identity.CoexistencePolicy -cne 'preserve_separate') {
        Throw-DaMaoP2Error 'P2_CANONICAL_DB_IDENTITY_MISMATCH' `
            'The authorized identity is incompatible with preserve_separate packaging.'
    }
    if ($SourceLibrimeVersion -cne $script:DaMaoP2SupportedLibrimeVersion) {
        Throw-DaMaoP2Error 'P2_LIBRIME_MUTATION_UNVERIFIED' `
            'Package V2 accepts only snapshots acquired with verified librime 1.13.1.'
    }
    $stable = Get-DaMaoP2StableSnapshot -Path $SnapshotPath `
        -RequestedDbName $DbName -Faults $Faults
    $parsed = $stable.Parsed
    if ($parsed.DbName -cne $identity.DbName) {
        Throw-DaMaoP2Error 'P2_CANONICAL_DB_IDENTITY_MISMATCH' `
            'Caller, contract, and snapshot database identities disagree.'
    }

    $outputRoot = [System.IO.Path]::GetFullPath($OutputDirectory)
    [void](New-Item -ItemType Directory -Path $outputRoot -Force)
    $outputItem = Get-Item -LiteralPath $outputRoot -Force
    if (($outputItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        Throw-DaMaoP2Error 'P2_FINAL_PUBLISH_FAILED' `
            'A reparse-point output directory is forbidden.'
    }
    $created = if ($null -eq $CreatedUtc) { [datetime]::UtcNow }
        else { ([datetime]$CreatedUtc).ToUniversalTime() }
    $stamp = $created.ToString('yyyyMMddTHHmmssfffffffZ',
        [System.Globalization.CultureInfo]::InvariantCulture)
    $finalPath = Join-Path $outputRoot ($DbName + '-userdb-portability-v2-' + $stamp + '.zip')
    if (Test-Path -LiteralPath $finalPath) {
        Throw-DaMaoP2Error 'P2_PACKAGE_DESTINATION_EXISTS' `
            'The final package path already exists and will not be replaced.'
    }

    $temporaryRoot = Join-Path $outputRoot ('.damao-p2-' + [guid]::NewGuid().ToString('N'))
    $temporaryZip = Join-Path $outputRoot ('.damao-p2-' + [guid]::NewGuid().ToString('N') + '.zip.tmp')
    $published = $false
    try {
        [void](New-Item -ItemType Directory -Path $temporaryRoot)
        $stagedDirectory = Join-Path $temporaryRoot 'snapshots'
        [void](New-Item -ItemType Directory -Path $stagedDirectory)
        $stagedPath = Join-Path $stagedDirectory ($DbName + '.userdb.txt')
        [System.IO.File]::WriteAllBytes($stagedPath, [byte[]]$stable.Bytes)
        $staged = Get-DaMaoP2StableSnapshot -Path $stagedPath `
            -RequestedDbName $DbName -Faults $null
        if ($staged.Sha256 -cne $stable.Sha256 -or
            $staged.ByteLength -ne $stable.ByteLength) {
            Throw-DaMaoP2Error 'P2_CANONICAL_SNAPSHOT_INVALID' `
                'The staged byte copy differs from the canonical snapshot.'
        }
        # All manifest facts and ZIP payload bytes below come from this one
        # stable, strictly parsed staged copy.
        $stable = $staged
        $parsed = $staged.Parsed

        $manifest = [ordered]@{
            PackageFormat = $script:DaMaoP2PackageFormat
            PackageFormatVersion = $script:DaMaoP2PackageVersion
            CreatedUtc = $created.ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
            LogicalRole = $identity.LogicalRole
            SchemaIdentities = @($identity.SchemaId)
            DbName = $identity.DbName
            SnapshotFile = 'snapshots/' + $DbName + '.userdb.txt'
            SnapshotSha256 = $stable.Sha256
            SnapshotByteLength = $stable.ByteLength
            SnapshotEntryCount = [int]$parsed.EntryCount
            SnapshotTombstoneCount = [int]$parsed.TombstoneCount
            SnapshotMinTick = $parsed.MinTick
            SnapshotMaxTick = $parsed.MaxTick
            SnapshotDbName = $parsed.DbName
            SnapshotDbType = $parsed.DbType
            SnapshotRimeVersion = $parsed.RimeVersion
            SourceLibrimeVersion = $SourceLibrimeVersion
            SourceWeaselVersion = $SourceWeaselVersion
            SourceArchitecture = 'x64'
            BackupApi = 'librime.levers.backup_user_dict'
            BackupMutationCapability = 'PotentialMetadataMutation'
            AutomaticMerge = $false
            AutomaticRename = $false
            ContainsUserDictionaryData = $true
            Sensitive = $true
            SensitiveDataWarning = 'This package contains complete user dictionary data. Handle it as sensitive data.'
        }
        [byte[]]$manifestBytes = ConvertTo-DaMaoP2JsonBytes -Value $manifest -Faults $Faults
        [System.IO.File]::WriteAllBytes((Join-Path $temporaryRoot 'manifest.json'), $manifestBytes)

        if (Test-DaMaoP2Fault $Faults 'TempZip') {
            Throw-DaMaoP2Error 'P2_TEMP_ZIP_FAILED' 'Temporary ZIP creation failed.'
        }
        try {
            Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
            Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
            $zipFileStream = [System.IO.File]::Open(
                $temporaryZip, [System.IO.FileMode]::CreateNew,
                [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None
            )
            try {
                $zipArchive = New-Object System.IO.Compression.ZipArchive(
                    $zipFileStream, [System.IO.Compression.ZipArchiveMode]::Create, $true
                )
                try {
                    foreach ($zipSource in @(
                            [pscustomobject]@{ Name = 'manifest.json'; Bytes = $manifestBytes },
                            [pscustomobject]@{ Name = ('snapshots/' + $DbName + '.userdb.txt'); Bytes = [byte[]]$stable.Bytes }
                        )) {
                        Assert-DaMaoP2ZipEntryName -Name $zipSource.Name
                        $zipEntry = $zipArchive.CreateEntry(
                            $zipSource.Name, [System.IO.Compression.CompressionLevel]::Optimal
                        )
                        $zipStream = $zipEntry.Open()
                        try {
                            [byte[]]$zipBytes = $zipSource.Bytes
                            $zipStream.Write($zipBytes, 0, $zipBytes.Length)
                        }
                        finally { $zipStream.Dispose() }
                    }
                }
                finally { $zipArchive.Dispose() }
            }
            finally { $zipFileStream.Dispose() }
        }
        catch {
            Throw-DaMaoP2Error 'P2_TEMP_ZIP_FAILED' 'Temporary ZIP creation failed.'
        }
        Test-DaMaoP2ZipReadback -ZipPath $temporaryZip -DbName $DbName `
            -SnapshotSha256 $stable.Sha256 -SnapshotByteLength $stable.ByteLength `
            -Faults $Faults
        $temporaryZipFile = Get-Item -LiteralPath $temporaryZip
        $expectedPackageByteLength = [long]$temporaryZipFile.Length
        $expectedPackageSha256 = (Get-FileHash -LiteralPath $temporaryZip `
            -Algorithm SHA256).Hash

        if (Test-DaMaoP2Fault $Faults 'FinalPublish') {
            Throw-DaMaoP2Error 'P2_FINAL_PUBLISH_FAILED' 'Final atomic publication failed.'
        }
        try {
            [System.IO.File]::Move($temporaryZip, $finalPath)
        }
        catch {
            Throw-DaMaoP2Error 'P2_FINAL_PUBLISH_FAILED' 'Final atomic publication failed.'
        }
        $packageFile = Get-Item -LiteralPath $finalPath
        $finalPackageSha256 = (Get-FileHash -LiteralPath $packageFile.FullName `
            -Algorithm SHA256).Hash
        if ([long]$packageFile.Length -ne $expectedPackageByteLength -or
            $finalPackageSha256 -cne $expectedPackageSha256) {
            Throw-DaMaoP2Error 'P2_FINAL_PUBLISH_FAILED' `
                'The final package differs from the validated temporary ZIP.'
        }
        Test-DaMaoP2ZipReadback -ZipPath $packageFile.FullName -DbName $DbName `
            -SnapshotSha256 $stable.Sha256 -SnapshotByteLength $stable.ByteLength `
            -Faults $null
        $published = $true
        return [pscustomobject][ordered]@{
            Status = 'Success'
            PackagePath = $packageFile.FullName
            PackageSha256 = $finalPackageSha256
            PackageByteLength = $expectedPackageByteLength
            LogicalRole = $identity.LogicalRole
            DbName = $identity.DbName
            SnapshotSha256 = $stable.Sha256
            SnapshotByteLength = $stable.ByteLength
            EntryCount = [int]$parsed.EntryCount
            TombstoneCount = [int]$parsed.TombstoneCount
            LibrimeVersion = $SourceLibrimeVersion
            WeaselVersion = $SourceWeaselVersion
            SupportedArchitecture = 'x64'
            BackupApi = 'librime.levers.backup_user_dict'
            BackupMutationCapability = 'PotentialMetadataMutation'
            CreatedUtc = $created.ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
            ContainsUserDictionaryData = $true
            Sensitive = $true
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryRoot) {
            Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $temporaryZip) {
            Remove-Item -LiteralPath $temporaryZip -Force -ErrorAction SilentlyContinue
        }
        if (-not $published -and (Test-Path -LiteralPath $finalPath)) {
            Remove-Item -LiteralPath $finalPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Enter-DaMaoP2MaintenanceWindow {
    param(
        [Parameter(Mandatory = $true)][string]$WeaselRoot,
        [ValidateRange(1, 120)][int]$TimeoutSeconds = 15,
        [switch]$Synthetic
    )

    if ($Synthetic) {
        return [pscustomobject][ordered]@{
            Status = 'NotRequiredSynthetic'
            WasRunning = $false
            Restored = $false
            ErrorCode = $null
            ServerPath = $null
        }
    }
    $serverPath = [System.IO.Path]::GetFullPath((Join-Path $WeaselRoot 'WeaselServer.exe'))
    if (-not (Test-Path -LiteralPath $serverPath -PathType Leaf)) {
        Throw-DaMaoP2Error 'P2_MAINTENANCE_FAILED' `
            'The verified WeaselServer executable was not found.'
    }
    $matching = New-Object 'System.Collections.Generic.List[object]'
    foreach ($process in @(Get-Process -Name 'WeaselServer' -ErrorAction SilentlyContinue)) {
        try {
            if ([string]::Equals([System.IO.Path]::GetFullPath($process.Path), $serverPath,
                    [System.StringComparison]::OrdinalIgnoreCase)) {
                $matching.Add($process)
            }
        }
        catch {
            Throw-DaMaoP2Error 'P2_MAINTENANCE_FAILED' `
                'A WeaselServer process could not be safely classified.'
        }
    }
    if ($matching.Count -eq 0) {
        return [pscustomobject][ordered]@{
            Status = 'EnteredAlreadyStopped'
            WasRunning = $false
            Restored = $false
            ErrorCode = $null
            ServerPath = $serverPath
        }
    }

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $serverPath
    $startInfo.Arguments = '/quit'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    try {
        $request = [System.Diagnostics.Process]::Start($startInfo)
        if ($null -ne $request) { $request.Dispose() }
    }
    catch {
        Throw-DaMaoP2Error 'P2_MAINTENANCE_FAILED' `
            'The WeaselServer shutdown request failed.'
    }
    $deadline = [datetime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $remaining = @($matching | Where-Object { -not $_.HasExited })
        if ($remaining.Count -eq 0) { break }
        Start-Sleep -Milliseconds 100
    } while ([datetime]::UtcNow -lt $deadline)
    if (@($matching | Where-Object { -not $_.HasExited }).Count -gt 0) {
        Throw-DaMaoP2Error 'P2_MAINTENANCE_FAILED' `
            'The verified WeaselServer did not stop within the maintenance timeout.'
    }
    return [pscustomobject][ordered]@{
        Status = 'EnteredStoppedVerifiedServer'
        WasRunning = $true
        Restored = $false
        ErrorCode = $null
        ServerPath = $serverPath
    }
}

function Exit-DaMaoP2MaintenanceWindow {
    param(
        [Parameter(Mandatory = $true)]$Maintenance,
        [AllowNull()][hashtable]$Faults
    )

    if (Test-DaMaoP2Fault $Faults 'MaintenanceRestore') {
        $Maintenance.WasRunning = $true
        $Maintenance.Restored = $false
        $Maintenance.ErrorCode = 'P2_MAINTENANCE_FAILED'
        $Maintenance.Status = 'ExitRestartFailed'
        return $Maintenance
    }

    if (-not [bool]$Maintenance.WasRunning) {
        return $Maintenance
    }
    try {
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = [string]$Maintenance.ServerPath
        $startInfo.UseShellExecute = $false
        $restoredProcess = [System.Diagnostics.Process]::Start($startInfo)
        if ($null -eq $restoredProcess) {
            throw 'The verified WeaselServer restart request returned no process.'
        }
        $restoredProcess.Dispose()
        $Maintenance.Restored = $true
        $Maintenance.Status = 'ExitedServerRestartRequested'
    }
    catch {
        $Maintenance.ErrorCode = 'P2_MAINTENANCE_FAILED'
        $Maintenance.Status = 'ExitRestartFailed'
    }
    return $Maintenance
}

function Backup-DaMaoUserDbPackageV2 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DbName,
        [Parameter(Mandatory = $true)][string]$OutputDirectory,
        [string]$RimeUserDir = (Join-Path $env:APPDATA 'Rime'),
        [AllowNull()][string]$RimeDll,
        [string]$RimeSharedDataDir,
        [string]$WeaselRoot,
        [ValidateRange(1, 120)][int]$MaintenanceTimeoutSeconds = 15,
        [switch]$Synthetic,
        [AllowNull()][hashtable]$Faults
    )

    $identity = Get-DaMaoP2AuthorizedIdentity -DbName $DbName
    $RimeDll = Resolve-DaMaoP2RimeDll -Path $RimeDll
    if ([string]::IsNullOrWhiteSpace($RimeSharedDataDir)) {
        $RimeSharedDataDir = Join-Path (Split-Path -Parent $RimeDll) 'data'
    }
    if ([string]::IsNullOrWhiteSpace($WeaselRoot)) {
        $WeaselRoot = Split-Path -Parent $RimeDll
    }
    $environment = Get-DaMaoUserDbEnvironmentStatus -RimeUserDir $RimeUserDir `
        -LogicalRole $identity.LogicalRole -WeaselRoot $WeaselRoot
    $database = @($environment.Databases | Where-Object { $_.DbName -ceq $DbName })
    if ($database.Count -ne 1) {
        Throw-DaMaoP2Error 'P2_TARGET_STATE_REJECTED' `
            'Only one authorized LiveDb may enter native backup.'
    }
    $canonicalPath = Get-DaMaoP2CanonicalSnapshotPath `
        -EnvironmentStatus $environment -DbName $DbName
    # P2 is targeted: other-machine sync history is never part of target-state
    # authorization or snapshot selection. Ambiguity is physical live+legacy
    # coexistence for this DB; the exact current-installation snapshot is the
    # only snapshot considered for Absent versus SnapshotOnly.
    $targetState = if ($database[0].LiveDbPresent -and $database[0].LegacyDbPresent) {
        'Ambiguous'
    }
    elseif ($database[0].LiveDbPresent) { 'LiveDb' }
    elseif ($database[0].LegacyDbPresent) { 'LegacyDb' }
    elseif (Test-Path -LiteralPath $canonicalPath -PathType Leaf) { 'SnapshotOnly' }
    else { 'Absent' }
    if ($targetState -cne 'LiveDb') {
        Throw-DaMaoP2Error 'P2_TARGET_STATE_REJECTED' `
            'Only one authorized LiveDb may enter native backup.'
    }
    if ($environment.LibrimeVersionStatus -cne 'Supported') {
        Throw-DaMaoP2Error 'P2_LIBRIME_MUTATION_UNVERIFIED' `
            'The detector did not verify librime 1.13.1.'
    }
    $maintenance = $null
    $nativeInitialized = $false
    $librimeVersion = $null
    $result = $null
    try {
        $maintenance = Enter-DaMaoP2MaintenanceWindow -WeaselRoot $WeaselRoot `
            -TimeoutSeconds $MaintenanceTimeoutSeconds -Synthetic:$Synthetic
        Import-DaMaoRimeLeversAdapter
        if (Test-DaMaoP2Fault $Faults 'NativeApiUnavailable') {
            Throw-DaMaoP2Error 'P2_RIME_API_UNAVAILABLE' 'The native API is unavailable.'
        }
        if (Test-DaMaoP2Fault $Faults 'LeversUnavailable') {
            Throw-DaMaoP2Error 'P2_LEVERS_MODULE_UNAVAILABLE' 'The levers module is unavailable.'
        }
        if (Test-DaMaoP2Fault $Faults 'BackupApiUnavailable') {
            Throw-DaMaoP2Error 'P2_BACKUP_API_UNAVAILABLE' 'backup_user_dict is unavailable.'
        }
        $stagingDir = Join-Path ([System.IO.Path]::GetFullPath($RimeUserDir)) 'build'
        try {
            [DaMaoRimeLeversAdapter]::Initialize(
                [System.IO.Path]::GetFullPath($RimeDll),
                [System.IO.Path]::GetFullPath($RimeSharedDataDir),
                [System.IO.Path]::GetFullPath($RimeUserDir),
                $stagingDir
            )
            $nativeInitialized = $true
            $librimeVersion = [DaMaoRimeLeversAdapter]::LibrimeVersion
            if (Test-DaMaoP2Fault $Faults 'BackupException') {
                Throw-DaMaoP2Error 'P2_NATIVE_BACKUP_FAILED' `
                    'The injected native backup call failed.'
            }
            if (Test-DaMaoP2Fault $Faults 'BackupFalse') { $backedUp = $false }
            else { $backedUp = [DaMaoRimeLeversAdapter]::BackupUserDictionary($DbName) }
            if (-not $backedUp) {
                Throw-DaMaoP2Error 'P2_NATIVE_BACKUP_FAILED' `
                    'librime backup_user_dict returned false.'
            }
        }
        catch {
            if ($_.Exception.InnerException -is [DaMaoRimeP2Exception]) {
                $nativeError = $_.Exception.InnerException
                Throw-DaMaoP2Error $nativeError.ErrorCode $nativeError.Message
            }
            if ($_.Exception -is [DaMaoRimeP2Exception]) {
                Throw-DaMaoP2Error $_.Exception.ErrorCode $_.Exception.Message
            }
            throw
        }
        finally {
            if ($nativeInitialized -or [DaMaoRimeLeversAdapter]::IsInitialized) {
                [DaMaoRimeLeversAdapter]::Shutdown()
                $nativeInitialized = $false
            }
        }

        $result = New-DaMaoUserDbPackageV2FromSnapshot `
            -SnapshotPath $canonicalPath -DbName $DbName `
            -OutputDirectory $OutputDirectory `
            -SourceLibrimeVersion $librimeVersion `
            -SourceWeaselVersion $environment.WeaselVersion -Faults $Faults
    }
    finally {
        if ($nativeInitialized -and ('DaMaoRimeLeversAdapter' -as [type])) {
            [DaMaoRimeLeversAdapter]::Shutdown()
        }
        if ($null -ne $maintenance) {
            $maintenance = Exit-DaMaoP2MaintenanceWindow -Maintenance $maintenance `
                -Faults $Faults
            if ($null -ne $result) {
                $result | Add-Member -NotePropertyName Maintenance `
                    -NotePropertyValue $maintenance
                if ($maintenance.ErrorCode) {
                    $result.Status = 'CompletedWithMaintenanceWarning'
                }
            }
        }
    }
    return $result
}
