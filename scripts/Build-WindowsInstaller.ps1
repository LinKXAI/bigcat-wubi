[CmdletBinding()]
param(
    [string]$ISCCPath,
    [switch]$QuanpinCandidate
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
& (Join-Path $repoRoot 'tests/Invoke-DaMaoAcceptance.ps1')
$installerSource = Join-Path $repoRoot 'installer\windows\BigCatWubi.iss'
$versionSource = Join-Path $repoRoot 'installer\windows\VERSION'
$versionReader = Join-Path $PSScriptRoot 'Get-WindowsInstallerVersion.ps1'
$iconSource = Join-Path $repoRoot 'assets\branding\windows\bigcat.ico'
$imeIconSource = Join-Path $repoRoot 'assets\branding\windows\bigcat-ime.ico'
$compilerSupportScript = Join-Path $repoRoot 'scripts\DaMao.InnoCompiler.ps1'
$dependencySupportScript = Join-Path $repoRoot 'scripts\DaMao.WindowsInstallerDependencies.ps1'
$outputDirectory = Join-Path $repoRoot 'dist\windows'
$outputInstaller = Join-Path $outputDirectory 'BigCatWubi-Setup.exe'

if ($QuanpinCandidate) {
    $candidateName = 'BigCatWubi-Quanpin-0.9.1-dev.4-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
    $outputInstaller = Join-Path $outputDirectory ($candidateName + '.exe')
    if (Test-Path -LiteralPath $outputInstaller) { throw 'Candidate output already exists.' }
}
$requiredSources = @(
    $installerSource,
    $versionSource,
    $versionReader,
    $iconSource,
    $imeIconSource,
    $compilerSupportScript,
    $dependencySupportScript,
    (Join-Path $repoRoot 'dependencies\windows-installer-v2.lock.json'),
    (Join-Path $repoRoot 'scripts\Install-DaMao.ps1'),
    (Join-Path $repoRoot 'scripts\DaMao.Common.ps1'),
    (Join-Path $repoRoot 'scripts\DaMao.SchemaUpgrade.ps1'),
    (Join-Path $repoRoot 'contracts\wubi-schema-upgrade-v1.json'),
    (Join-Path $repoRoot 'scripts\DaMao.InstallerState.ps1'),
    (Join-Path $repoRoot 'scripts\Bootstrap-Weasel.ps1'),
    (Join-Path $repoRoot 'scripts\Uninstall-BigCat.ps1'),
    (Join-Path $repoRoot 'schemas\damao_wubi.schema.yaml'),
    (Join-Path $repoRoot 'third_party\weasel\0.17.4\weasel-0.17.4.0-installer.exe'),
    (Join-Path $repoRoot 'third_party\weasel\0.17.4\LICENSE.txt'),
    (Join-Path $repoRoot 'third_party\weasel\0.17.4\UPSTREAM.md'),
    (Join-Path $repoRoot 'third_party\rime\rime-wubi\LICENSE'),
    (Join-Path $repoRoot 'third_party\rime\rime-wubi\README.md'),
    (Join-Path $repoRoot 'third_party\rime\rime-wubi\wubi86.dict.yaml'),
    (Join-Path $repoRoot 'third_party\rime\rime-wubi\wubi86.schema.yaml'),
    (Join-Path $repoRoot 'third_party\rime\rime-wubi\UPSTREAM.md'),
    (Join-Path $repoRoot 'LICENSE')
)
foreach ($requiredSource in $requiredSources) {
    if (-not (Test-Path -LiteralPath $requiredSource -PathType Leaf)) {
        throw "[DM-INNO-SOURCE-MISSING] Required installer source was not found: $requiredSource"
    }
}

. (Join-Path $PSScriptRoot 'DaMao.Quanpin.ps1')
# Validate every vendored pinyin resource before compilation without installing it.
$absent = Join-Path ([IO.Path]::GetTempPath()) ('BigCatBuildValidate-' + [guid]::NewGuid().ToString('N'))
Get-DaMaoQuanpinPlan -RepoRoot $repoRoot -RimeUserDir (Join-Path $absent 'user') -WeaselRoot (Join-Path $absent 'weasel') | Out-Null
. $dependencySupportScript
$verifiedDependencies = @(Test-DaMaoWindowsInstallerDependencyLock -RepoRoot $repoRoot)
Write-Host "Verified $($verifiedDependencies.Count) pinned third-party installer files."

$packageVersion = & $versionReader -VersionPath $versionSource

. $compilerSupportScript

$resolvedISCC = Find-DaMaoISCC -ExplicitPath $ISCCPath
$compilerVersion = Get-DaMaoISCCVersion -CompilerPath $resolvedISCC
if ($null -eq $compilerVersion) {
    throw '[DM-INNO-VERSION-UNSUPPORTED] Supported Inno Setup toolchains are 6.3+ on the 6.x line or 7.1+. Detected: no semantic version from --version or PE VersionInfo.'
}
if (-not (Test-DaMaoISCCVersionSupported -Version $compilerVersion.Version)) {
    throw "[DM-INNO-VERSION-UNSUPPORTED] Supported Inno Setup toolchains are 6.3+ on the 6.x line or 7.1+. Detected: $($compilerVersion.VersionText) via $($compilerVersion.DetectionMethod)."
}

if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

Write-Host "Detected Inno Setup $($compilerVersion.VersionText) via $($compilerVersion.DetectionMethod): $resolvedISCC"
if ($QuanpinCandidate) { Write-Host 'Building BigCat candidate 0.9.1-dev.4 (Windows 0.9.1.4; working-tree source)' } else { Write-Host "Building BigCat Wubi $($packageVersion.DisplayVersion) ($($packageVersion.ReleaseTag); Windows $($packageVersion.NumericVersion))" }
$manifestPaths = @($requiredSources) + @(
    [regex]::Matches([IO.File]::ReadAllText($installerSource),'(?m)^Source: "([^\r\n"]+)";') | ForEach-Object {
        [IO.Path]::GetFullPath((Join-Path (Split-Path $installerSource -Parent) $_.Groups[1].Value))
    }
) + @($PSCommandPath, (Join-Path $PSScriptRoot 'DaMao.Quanpin.ps1'))
$acceptanceLock = [IO.File]::ReadAllText((Join-Path $repoRoot 'contracts/acceptance.lock.json')) | ConvertFrom-Json
$acceptanceManifest = [IO.File]::ReadAllText((Join-Path $repoRoot $acceptanceLock.manifest.path)) | ConvertFrom-Json
$manifestPaths += @(Join-Path $repoRoot 'contracts/acceptance.lock.json')
foreach ($pin in @($acceptanceLock.manifest,$acceptanceLock.transition,$acceptanceLock.predecessor,$acceptanceLock.evidence,$acceptanceLock.verifier,$acceptanceLock.loader) +
        @($acceptanceManifest.current_file_integrity.files) + @($acceptanceManifest.support_file_integrity.files)) {
    $manifestPaths += Join-Path $repoRoot $pin.path
}
$sourceFiles = @($manifestPaths | Sort-Object -Unique | ForEach-Object {
    [ordered]@{path=$_.Substring($repoRoot.Length+1).Replace('\','/');size=(Get-Item -LiteralPath $_).Length;sha256=(Get-FileHash -LiteralPath $_).Hash}
})
if ($QuanpinCandidate) {
    $gitTrust = 'safe.directory=' + $repoRoot.Replace('\','/')
    # Audit Git's clean-filter bytes without staging or writing Git objects.
    foreach ($file in $sourceFiles) {
        $absolute = Join-Path $repoRoot $file.path
        $rawBlob = & git -c $gitTrust -C $repoRoot hash-object --no-filters -- $absolute
        if ($LASTEXITCODE -ne 0) { throw 'Raw source audit failed.' }
        $filteredBlob = & git -c $gitTrust -C $repoRoot hash-object --path=$($file.path) -- $absolute
        if ($LASTEXITCODE -ne 0 -or $rawBlob -cne $filteredBlob) { throw "Git EOL/filter transformation would change pinned candidate input: $($file.path)" }
    }
    # Conservative inventory: all files of the local compiler distribution,
    # including setup stubs, compression libraries and language resources.
    # It intentionally includes unused toolchain files; nothing is downloaded.
    $compilerRoot = Split-Path $resolvedISCC -Parent
    $compilerFiles = @(Get-ChildItem -LiteralPath $compilerRoot -File -Recurse | Sort-Object FullName | ForEach-Object {
        [ordered]@{path=$_.FullName.Substring($compilerRoot.Length+1).Replace('\','/');size=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}
    })
    $baseCommit = & git -c $gitTrust -C $repoRoot rev-parse HEAD
    if ($LASTEXITCODE -ne 0) { throw 'Cannot record candidate base commit.' }
    $worktreeStatus = @(& git --no-optional-locks -c $gitTrust -C $repoRoot status --short --untracked-files=all)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot record candidate worktree status.' }
    & $resolvedISCC '/DQuanpinCandidate=1' ('/F' + $candidateName) $installerSource
} else {
    & $resolvedISCC $installerSource
}
if ($LASTEXITCODE -ne 0) {
    throw "[DM-INNO-BUILD-FAILED] ISCC.exe exited with code $LASTEXITCODE."
}
if (-not (Test-Path -LiteralPath $outputInstaller -PathType Leaf)) {
    throw "[DM-INNO-OUTPUT-MISSING] ISCC.exe reported success but the expected installer was not found: $outputInstaller"
}

if ($QuanpinCandidate) {
    foreach ($file in $sourceFiles) {
        if ((Get-FileHash -LiteralPath (Join-Path $repoRoot $file.path)).Hash -ne $file.sha256) { throw 'Source changed during candidate build.' }
    }
    foreach ($file in $compilerFiles) {
        if ((Get-FileHash -LiteralPath (Join-Path $compilerRoot $file.path)).Hash -cne $file.sha256) { throw 'Toolchain input changed during candidate build.' }
    }
    $receipt = [ordered]@{
        format_version=2; candidate_version='0.9.1-dev.4'; windows_version='0.9.1.4'; base_commit=$baseCommit;
        source_kind='uncommitted working tree (not the base commit alone)'; worktree_status=$worktreeStatus;
        compiler=$compilerVersion.VersionText; compiler_sha256=(Get-FileHash -LiteralPath $resolvedISCC).Hash;
        compiler_defines=@('QuanpinCandidate=1'); source_files=$sourceFiles;
        compiler_root=$compilerRoot; compiler_files=$compilerFiles;
        compiler_inventory_scope='conservative complete compiler-directory inventory, including unused files';
        git_clean_filter_bytes_unchanged=$true; acceptance_baseline=$acceptanceLock.current_baseline;
        acceptance_lock_sha256=(Get-FileHash -LiteralPath (Join-Path $repoRoot 'contracts/acceptance.lock.json')).Hash;
        installer=[ordered]@{file=[IO.Path]::GetFileName($outputInstaller);size=(Get-Item -LiteralPath $outputInstaller).Length;sha256=(Get-FileHash -LiteralPath $outputInstaller).Hash}
    }
    $receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath ($outputInstaller+'.sources.json') -Encoding UTF8
}
Write-Host "Windows installer created: $outputInstaller"
Get-Item -LiteralPath $outputInstaller
