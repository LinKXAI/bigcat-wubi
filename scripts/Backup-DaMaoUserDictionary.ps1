[CmdletBinding()]
param(
    [string]$RimeUserDir,
    [string]$WeaselRoot,
    [string]$BackupDirectory
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'DaMao.Common.ps1')

$resolvedUserDir = Get-DaMaoRimeUserDir -Override $RimeUserDir
$resolvedWeaselRoot = Get-DaMaoWeaselRoot -Override $WeaselRoot
if (-not (Test-Path -LiteralPath $resolvedUserDir -PathType Container)) {
    throw "Rime user directory does not exist: $resolvedUserDir"
}

Invoke-DaMaoDeployer -WeaselRoot $resolvedWeaselRoot -Command '/sync'

$syncDirectory = Join-Path $resolvedUserDir 'sync'
$snapshots = @(Get-ChildItem -LiteralPath $syncDirectory -Recurse -File -Filter 'damao_wubi.userdb.txt' -ErrorAction SilentlyContinue)
if ($snapshots.Count -eq 0) {
    throw 'No DaMao Input Method user dictionary snapshot exists. Select at least one candidate with DaMao Input Method, then run the backup again.'
}

if ([string]::IsNullOrWhiteSpace($BackupDirectory)) {
    $BackupDirectory = Join-Path $env:USERPROFILE 'DaMaoBackups'
}
$resolvedBackupDirectory = ConvertTo-DaMaoFullPath $BackupDirectory
New-Item -ItemType Directory -Path $resolvedBackupDirectory -Force | Out-Null

$backupId = Get-Date -Format 'yyyyMMdd-HHmmss'
$archivePath = Join-Path $resolvedBackupDirectory "damao-ime-userdict-$backupId.zip"
if (Test-Path -LiteralPath $archivePath) {
    $archivePath = Join-Path $resolvedBackupDirectory "damao-ime-userdict-$backupId-$([Guid]::NewGuid().ToString('N').Substring(0, 8)).zip"
}

$stagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) "damao-ime-backup-$([Guid]::NewGuid().ToString('N'))"
try {
    $snapshotRoot = Join-Path $stagingRoot 'snapshots'
    New-Item -ItemType Directory -Path $snapshotRoot -Force | Out-Null
    for ($index = 0; $index -lt $snapshots.Count; $index++) {
        $destination = Join-Path $snapshotRoot ('source-{0:D2}' -f ($index + 1))
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        Copy-Item -LiteralPath $snapshots[$index].FullName -Destination (Join-Path $destination 'damao_wubi.userdb.txt') -Force
    }

    $manifest = [ordered]@{
        format_version = 1
        schema_id = 'damao_wubi'
        created_utc = [DateTime]::UtcNow.ToString('o')
        snapshot_count = $snapshots.Count
    }
    Write-DaMaoUtf8File -Path (Join-Path $stagingRoot 'manifest.json') -Content (($manifest | ConvertTo-Json) + "`n")
    Compress-Archive -Path (Join-Path $stagingRoot '*') -DestinationPath $archivePath -CompressionLevel Optimal
}
finally {
    $safeTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    $resolvedStagingRoot = [System.IO.Path]::GetFullPath($stagingRoot)
    if ($resolvedStagingRoot.StartsWith($safeTempRoot, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $resolvedStagingRoot)) {
        Remove-Item -LiteralPath $resolvedStagingRoot -Recurse -Force
    }
}

[PSCustomObject]@{
    SchemaId = 'damao_wubi'
    SnapshotCount = $snapshots.Count
    Archive = $archivePath
}
