[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory = $true)][string]$Archive,
    [string]$RimeUserDir,
    [string]$WeaselRoot
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'DaMao.Common.ps1')

$resolvedArchive = ConvertTo-DaMaoFullPath $Archive
if (-not (Test-Path -LiteralPath $resolvedArchive -PathType Leaf)) {
    throw "Backup archive does not exist: $resolvedArchive"
}

$resolvedUserDir = Get-DaMaoRimeUserDir -Override $RimeUserDir
$resolvedWeaselRoot = Get-DaMaoWeaselRoot -Override $WeaselRoot
if (-not (Test-Path -LiteralPath $resolvedUserDir -PathType Container)) {
    throw "Rime user directory does not exist: $resolvedUserDir"
}

$stagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) "damao-ime-restore-$([Guid]::NewGuid().ToString('N'))"
try {
    New-Item -ItemType Directory -Path $stagingRoot -Force -WhatIf:$false | Out-Null
    Expand-Archive -LiteralPath $resolvedArchive -DestinationPath $stagingRoot -WhatIf:$false

    $manifestPath = Join-Path $stagingRoot 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw 'Invalid backup: manifest.json is missing.'
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($manifest.format_version -ne 1 -or $manifest.schema_id -ne 'damao_wubi') {
        throw 'Invalid or unsupported DaMao Input Method backup format.'
    }

    $snapshots = @(Get-ChildItem -LiteralPath (Join-Path $stagingRoot 'snapshots') -Recurse -File -Filter 'damao_wubi.userdb.txt' -ErrorAction SilentlyContinue)
    if ($snapshots.Count -eq 0 -or $snapshots.Count -ne $manifest.snapshot_count) {
        throw 'Invalid backup: snapshot count does not match the manifest.'
    }

    $restoreId = Get-Date -Format 'yyyyMMdd-HHmmss'
    $syncDirectory = Join-Path $resolvedUserDir 'sync'
    if ($PSCmdlet.ShouldProcess($resolvedUserDir, "Merge $($snapshots.Count) DaMao Input Method user dictionary snapshot(s)")) {
        New-Item -ItemType Directory -Path $syncDirectory -Force | Out-Null
        for ($index = 0; $index -lt $snapshots.Count; $index++) {
            $restoreDirectory = Join-Path $syncDirectory ('damao-ime-restore-{0}-{1:D2}' -f $restoreId, ($index + 1))
            New-Item -ItemType Directory -Path $restoreDirectory -Force | Out-Null
            Copy-Item -LiteralPath $snapshots[$index].FullName -Destination (Join-Path $restoreDirectory 'damao_wubi.userdb.txt') -Force
        }
        Invoke-DaMaoDeployer -WeaselRoot $resolvedWeaselRoot -Command '/sync'
    }
}
finally {
    $safeTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    $resolvedStagingRoot = [System.IO.Path]::GetFullPath($stagingRoot)
    if ($resolvedStagingRoot.StartsWith($safeTempRoot, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $resolvedStagingRoot)) {
        Remove-Item -LiteralPath $resolvedStagingRoot -Recurse -Force -WhatIf:$false
    }
}

[PSCustomObject]@{
    SchemaId = 'damao_wubi'
    RestoredSnapshots = $snapshots.Count
    RimeUserDir = $resolvedUserDir
}
