Set-StrictMode -Version 2.0

function Test-DaMaoWindowsInstallerDependencyLock {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [string]$LockPath = (Join-Path $RepoRoot 'dependencies\windows-installer-v2.lock.json')
    )

    if (-not (Test-Path -LiteralPath $LockPath -PathType Leaf)) {
        throw "[DM-INSTALLER-DEPENDENCY-LOCK-MISSING] Dependency lock was not found: $LockPath"
    }

    try {
        $lock = [System.IO.File]::ReadAllText($LockPath) | ConvertFrom-Json
    }
    catch {
        throw "[DM-INSTALLER-DEPENDENCY-LOCK-INVALID] Dependency lock is not valid JSON: $LockPath"
    }

    if ($lock.schemaVersion -ne 1 -or @($lock.components).Count -ne 2) {
        throw '[DM-INSTALLER-DEPENDENCY-LOCK-INVALID] Expected schema version 1 with exactly two components.'
    }

    $resolvedRepoRoot = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd('\') + '\'
    $verified = [System.Collections.Generic.List[object]]::new()
    foreach ($component in @($lock.components)) {
        if ([string]::IsNullOrWhiteSpace([string]$component.name) -or
            [string]::IsNullOrWhiteSpace([string]$component.repository) -or
            [string]::IsNullOrWhiteSpace([string]$component.license)) {
            throw '[DM-INSTALLER-DEPENDENCY-LOCK-INVALID] Each component requires name, repository, and license metadata.'
        }
        foreach ($file in @($component.files)) {
            $relativePath = [string]$file.path
            if ([string]::IsNullOrWhiteSpace($relativePath) -or [System.IO.Path]::IsPathRooted($relativePath)) {
                throw "[DM-INSTALLER-DEPENDENCY-LOCK-INVALID] Invalid locked path: $relativePath"
            }
            $fullPath = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $relativePath))
            if (-not $fullPath.StartsWith($resolvedRepoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "[DM-INSTALLER-DEPENDENCY-LOCK-INVALID] Locked path escapes the repository: $relativePath"
            }
            if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
                throw "[DM-INSTALLER-DEPENDENCY-MISSING] Locked dependency file was not found: $relativePath"
            }
            $item = Get-Item -LiteralPath $fullPath -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "[DM-INSTALLER-DEPENDENCY-INVALID] Locked dependency cannot be a reparse point: $relativePath"
            }
            if ([int64]$item.Length -ne [int64]$file.size) {
                throw "[DM-INSTALLER-DEPENDENCY-SIZE-MISMATCH] Size mismatch for $relativePath"
            }
            $actualHash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash
            if (-not [string]::Equals($actualHash, [string]$file.sha256,
                [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "[DM-INSTALLER-DEPENDENCY-HASH-MISMATCH] SHA-256 mismatch for $relativePath"
            }
            $verified.Add([PSCustomObject]@{
                Component = [string]$component.name
                Path = $relativePath
                Size = [int64]$item.Length
                SHA256 = $actualHash
            })
        }
    }

    return @($verified)
}
