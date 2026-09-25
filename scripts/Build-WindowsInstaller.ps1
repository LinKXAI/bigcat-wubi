[CmdletBinding()]
param(
    [string]$ISCCPath,
    [switch]$QuanpinCandidate
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
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
    $candidateName = 'BigCatWubi-Quanpin-0.9.1-dev.3-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
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
if ($QuanpinCandidate) { Write-Host 'Building BigCat Quanpin candidate 0.9.1-dev.3 (Windows 0.9.1.3; working-tree source)' } else { Write-Host "Building BigCat Wubi $($packageVersion.DisplayVersion) ($($packageVersion.ReleaseTag); Windows $($packageVersion.NumericVersion))" }
$manifestPaths = @($requiredSources) + @(
    [regex]::Matches([IO.File]::ReadAllText($installerSource),'(?m)^Source: "([^\r\n"]+)";') | ForEach-Object {
        [IO.Path]::GetFullPath((Join-Path (Split-Path $installerSource -Parent) $_.Groups[1].Value))
    }
) + @($PSCommandPath, (Join-Path $PSScriptRoot 'DaMao.Quanpin.ps1'))
$sourceFiles = @($manifestPaths | Sort-Object -Unique | ForEach-Object {
    [ordered]@{path=$_.Substring($repoRoot.Length+1).Replace('\','/');size=(Get-Item -LiteralPath $_).Length;sha256=(Get-FileHash -LiteralPath $_).Hash}
})
if ($QuanpinCandidate) {
    $gitTrust = 'safe.directory=' + $repoRoot.Replace('\','/')
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
    $receipt = [ordered]@{
        format_version=1; candidate_version='0.9.1-dev.3'; base_commit=$baseCommit;
        source_kind='uncommitted working tree (not the base commit alone)'; worktree_status=$worktreeStatus;
        compiler=$compilerVersion.VersionText; compiler_sha256=(Get-FileHash -LiteralPath $resolvedISCC).Hash;
        compiler_defines=@('QuanpinCandidate=1'); source_files=$sourceFiles;
        installer=[ordered]@{file=[IO.Path]::GetFileName($outputInstaller);size=(Get-Item -LiteralPath $outputInstaller).Length;sha256=(Get-FileHash -LiteralPath $outputInstaller).Hash}
    }
    $receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath ($outputInstaller+'.sources.json') -Encoding UTF8
}
Write-Host "Windows installer created: $outputInstaller"
Get-Item -LiteralPath $outputInstaller
