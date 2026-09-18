[CmdletBinding()]
param(
    [string]$ISCCPath
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
Write-Host "Building BigCat Wubi $($packageVersion.DisplayVersion) ($($packageVersion.ReleaseTag); Windows $($packageVersion.NumericVersion))"
& $resolvedISCC $installerSource
if ($LASTEXITCODE -ne 0) {
    throw "[DM-INNO-BUILD-FAILED] ISCC.exe exited with code $LASTEXITCODE."
}
if (-not (Test-Path -LiteralPath $outputInstaller -PathType Leaf)) {
    throw "[DM-INNO-OUTPUT-MISSING] ISCC.exe reported success but the expected installer was not found: $outputInstaller"
}

Write-Host "Windows installer created: $outputInstaller"
Get-Item -LiteralPath $outputInstaller
