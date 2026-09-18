function ConvertTo-DaMaoInnoVersion {
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    $match = [regex]::Match($Text, '(?<![\d.])(?<version>\d+\.\d+(?:\.\d+){0,2})(?![\d.])')
    if (-not $match.Success) {
        return $null
    }

    try {
        $components = @($match.Groups['version'].Value.Split('.') | ForEach-Object { [int]$_ })
        while ($components.Count -lt 4) {
            $components += 0
        }
        $version = [version]::new($components[0], $components[1], $components[2], $components[3])
    }
    catch {
        return $null
    }

    [PSCustomObject]@{
        Version = $version
        VersionText = $match.Groups['version'].Value
    }
}

function Resolve-DaMaoISCCVersion {
    param(
        [AllowNull()][string]$CommandVersionOutput,
        [int]$CommandVersionExitCode = -1,
        [AllowNull()][string]$ProductVersion,
        [AllowNull()][string]$FileVersion
    )

    if ($CommandVersionExitCode -eq 0) {
        $commandVersion = ConvertTo-DaMaoInnoVersion -Text $CommandVersionOutput
        if ($null -ne $commandVersion) {
            return [PSCustomObject]@{
                Version = $commandVersion.Version
                VersionText = $commandVersion.VersionText
                DetectionMethod = '--version'
            }
        }
    }

    $zeroVersionCandidate = $null
    foreach ($candidate in @(
        [PSCustomObject]@{ Text = $ProductVersion; Method = 'ProductVersion' },
        [PSCustomObject]@{ Text = $FileVersion; Method = 'FileVersion' }
    )) {
        $peVersion = ConvertTo-DaMaoInnoVersion -Text $candidate.Text
        if ($null -ne $peVersion) {
            $resolvedCandidate = [PSCustomObject]@{
                Version = $peVersion.Version
                VersionText = $peVersion.VersionText
                DetectionMethod = $candidate.Method
            }
            if ($peVersion.Version -ne [version]'0.0.0.0') {
                return $resolvedCandidate
            }
            if ($null -eq $zeroVersionCandidate) {
                $zeroVersionCandidate = $resolvedCandidate
            }
        }
    }

    return $zeroVersionCandidate
}

function Test-DaMaoISCCVersionSupported {
    param([version]$Version)

    if ($null -eq $Version) {
        return $false
    }

    if ($Version.Major -eq 6) {
        return $Version -ge [version]'6.3.0.0'
    }

    return $Version -ge [version]'7.1.0.0'
}

function Get-DaMaoISCCCandidatePaths {
    param(
        [string[]]$ProgramFilesRoots = @(
            $env:ProgramFiles,
            ${env:ProgramFiles(x86)},
            $env:LOCALAPPDATA
        )
    )

    $candidates = [System.Collections.Generic.List[string]]::new()
    foreach ($version in @('7', '6')) {
        foreach ($programFilesRoot in $ProgramFilesRoots) {
            if (-not [string]::IsNullOrWhiteSpace($programFilesRoot)) {
                $candidates.Add((Join-Path $programFilesRoot "Inno Setup $version\ISCC.exe"))
                $candidates.Add((Join-Path $programFilesRoot "Programs\Inno Setup $version\ISCC.exe"))
            }
        }
    }

    @($candidates | Select-Object -Unique)
}

function Find-DaMaoISCC {
    param([string]$ExplicitPath)

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        $resolvedExplicitPath = [System.IO.Path]::GetFullPath(
            [Environment]::ExpandEnvironmentVariables($ExplicitPath))
        if (-not (Test-Path -LiteralPath $resolvedExplicitPath -PathType Leaf)) {
            throw "[DM-INNO-NOT-FOUND] The explicit ISCC path does not exist: $resolvedExplicitPath"
        }
        return $resolvedExplicitPath
    }

    $command = Get-Command 'ISCC.exe' -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    foreach ($candidate in (Get-DaMaoISCCCandidatePaths)) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
    }

    throw '[DM-INNO-NOT-FOUND] ISCC.exe was not found. Install a supported Inno Setup toolchain (6.3+ on the 6.x line or 7.1+), or pass -ISCCPath <path>. This script never downloads tooling automatically.'
}

function Get-DaMaoISCCVersion {
    param([Parameter(Mandatory)][string]$CompilerPath)

    $commandVersionOutput = $null
    $commandVersionExitCode = -1
    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $CompilerPath
        $startInfo.Arguments = '--version'
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $true
        $process = [System.Diagnostics.Process]::Start($startInfo)
        $standardOutput = $process.StandardOutput.ReadToEnd()
        $standardError = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        $commandVersionExitCode = $process.ExitCode
        $commandVersionOutput = @($standardOutput, $standardError) -join "`n"
    }
    catch {
        $commandVersionExitCode = -1
    }

    $versionInfo = (Get-Item -LiteralPath $CompilerPath).VersionInfo
    Resolve-DaMaoISCCVersion `
        -CommandVersionOutput $commandVersionOutput `
        -CommandVersionExitCode $commandVersionExitCode `
        -ProductVersion $versionInfo.ProductVersion `
        -FileVersion $versionInfo.FileVersion
}
