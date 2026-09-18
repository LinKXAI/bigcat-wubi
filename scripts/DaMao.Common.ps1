Set-StrictMode -Version Latest

function ConvertTo-DaMaoFullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    return [System.IO.Path]::GetFullPath($expanded)
}

function Get-DaMaoRimeUserDir {
    param([string]$Override)

    if (-not [string]::IsNullOrWhiteSpace($Override)) {
        return ConvertTo-DaMaoFullPath $Override
    }

    $registryPath = 'HKCU:\Software\Rime\Weasel'
    $settings = Get-ItemProperty -LiteralPath $registryPath -ErrorAction SilentlyContinue
    if ($null -ne $settings) {
        $property = $settings.PSObject.Properties['RimeUserDir']
        if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace($property.Value)) {
            return ConvertTo-DaMaoFullPath $property.Value
        }
    }

    return ConvertTo-DaMaoFullPath (Join-Path $env:APPDATA 'Rime')
}

function Get-DaMaoWeaselRoot {
    param([string]$Override)

    $candidates = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($Override)) {
        $candidates.Add((ConvertTo-DaMaoFullPath $Override))
    }

    $registryPaths = @(
        'HKLM:\SOFTWARE\Rime\Weasel',
        'HKLM:\SOFTWARE\WOW6432Node\Rime\Weasel'
    )
    foreach ($registryPath in $registryPaths) {
        $settings = Get-ItemProperty -LiteralPath $registryPath -ErrorAction SilentlyContinue
        if ($null -eq $settings) {
            continue
        }
        foreach ($propertyName in @('WeaselRoot', 'InstallDir')) {
            $property = $settings.PSObject.Properties[$propertyName]
            if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace($property.Value)) {
                $candidates.Add((ConvertTo-DaMaoFullPath $property.Value))
            }
        }
    }

    foreach ($programFilesPath in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not [string]::IsNullOrWhiteSpace($programFilesPath)) {
            $candidates.Add((Join-Path $programFilesPath 'Rime'))
        }
    }

    foreach ($candidate in $candidates | Select-Object -Unique) {
        if (Test-Path -LiteralPath (Join-Path $candidate 'WeaselDeployer.exe') -PathType Leaf) {
            return $candidate
        }

        if (Test-Path -LiteralPath $candidate -PathType Container) {
            $versionDirectories = Get-ChildItem -LiteralPath $candidate -Directory -Filter 'weasel-*' -ErrorAction SilentlyContinue |
                Sort-Object Name -Descending
            foreach ($versionDirectory in $versionDirectories) {
                if (Test-Path -LiteralPath (Join-Path $versionDirectory.FullName 'WeaselDeployer.exe') -PathType Leaf) {
                    return $versionDirectory.FullName
                }
            }
        }
    }

    throw '[DM-WEASEL-NOT-FOUND] Weasel installation was not found. Install Weasel first or pass -WeaselRoot.'
}

function Test-DaMaoPathWithin {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Parent
    )

    $fullPath = (ConvertTo-DaMaoFullPath $Path).TrimEnd('\') + '\'
    $fullParent = (ConvertTo-DaMaoFullPath $Parent).TrimEnd('\') + '\'
    return $fullPath.StartsWith($fullParent, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-DaMaoDependencyFile {
    param(
        [Parameter(Mandatory = $true)][string]$RimeUserDir,
        [Parameter(Mandatory = $true)][string]$WeaselRoot
    )

    $candidates = @(
        (Join-Path $RimeUserDir 'wubi86.dict.yaml'),
        (Join-Path $WeaselRoot 'data\wubi86.dict.yaml')
    )
    foreach ($candidate in $candidates) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            continue
        }
        if (-not (Test-DaMaoDictionaryFile $candidate)) {
            continue
        }
        return $candidate
    }
    return $null
}

function Test-DaMaoDictionaryFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }
    $reader = New-Object System.IO.StreamReader($Path, [System.Text.Encoding]::UTF8, $true)
    try {
        $headerLines = [System.Collections.Generic.List[string]]::new()
        for ($index = 0; $index -lt 80 -and -not $reader.EndOfStream; $index++) {
            $headerLines.Add($reader.ReadLine())
        }
        $header = $headerLines -join "`n"
        return $header -match '(?m)^# Rime dictionary: wubi86\s*$' -and
            $header -match '(?m)^name:\s*wubi86\s*$' -and
            $header -match '(?m)^columns:\s*$'
    }
    finally {
        $reader.Dispose()
    }
}

function Test-DaMaoOfficialRepositoryUrl {
    param([Parameter(Mandatory = $true)][string]$Url)

    $normalized = $Url.Trim().TrimEnd('/').ToLowerInvariant()
    return $normalized -in @(
        'https://github.com/rime/rime-wubi.git',
        'https://github.com/rime/rime-wubi',
        'git@github.com:rime/rime-wubi.git',
        'ssh://git@github.com/rime/rime-wubi.git'
    )
}

function Get-DaMaoWubiSourceInfo {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [switch]$RequireOfficialGitRemote
    )

    $resolvedSource = ConvertTo-DaMaoFullPath $SourcePath
    if (-not (Test-Path -LiteralPath $resolvedSource -PathType Container)) {
        throw "[DM-WUBI-SOURCE-INVALID] Wubi source directory does not exist: $resolvedSource"
    }

    $requiredFiles = @('wubi86.dict.yaml', 'wubi86.schema.yaml', 'README.md', 'LICENSE')
    foreach ($requiredFile in $requiredFiles) {
        $requiredPath = Join-Path $resolvedSource $requiredFile
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            throw "[DM-WUBI-SOURCE-INVALID] Official rime-wubi file is missing: $requiredFile"
        }
    }

    $dictionaryPath = Join-Path $resolvedSource 'wubi86.dict.yaml'
    if (-not (Test-DaMaoDictionaryFile $dictionaryPath)) {
        throw '[DM-WUBI-SOURCE-INVALID] wubi86.dict.yaml does not have the expected official Rime dictionary header.'
    }

    $licenseText = [System.IO.File]::ReadAllText((Join-Path $resolvedSource 'LICENSE'))
    if ($licenseText -notmatch 'GNU LESSER GENERAL PUBLIC LICENSE') {
        throw '[DM-WUBI-SOURCE-INVALID] rime-wubi LICENSE is not the expected LGPL license.'
    }

    $remote = $null
    $commit = $null
    if (Test-Path -LiteralPath (Join-Path $resolvedSource '.git') -PathType Container) {
        $git = Get-Command git -ErrorAction SilentlyContinue
        if ($null -eq $git) {
            if ($RequireOfficialGitRemote) {
                throw '[DM-WUBI-INSTALL-FAILED] Git is required to verify the cloned rime-wubi repository.'
            }
        }
        else {
            $remote = (& $git.Source -C $resolvedSource remote get-url origin 2>$null | Select-Object -First 1)
            if (-not [string]::IsNullOrWhiteSpace($remote) -and -not (Test-DaMaoOfficialRepositoryUrl $remote)) {
                throw "[DM-WUBI-SOURCE-INVALID] Git origin is not the official rime/rime-wubi repository: $remote"
            }
            $commit = (& $git.Source -C $resolvedSource rev-parse HEAD 2>$null | Select-Object -First 1)
        }
    }
    elseif ($RequireOfficialGitRemote) {
        throw '[DM-WUBI-INSTALL-FAILED] Downloaded source is not a verifiable Git checkout.'
    }

    return [PSCustomObject]@{
        Root = $resolvedSource
        Dictionary = $dictionaryPath
        License = (Join-Path $resolvedSource 'LICENSE')
        Remote = $remote
        Commit = $commit
    }
}

function Install-DaMaoWubiFromSource {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$RimeUserDir,
        [Parameter(Mandatory = $true)][ValidateSet('local', 'github-clone')][string]$Method,
        [switch]$RequireOfficialGitRemote
    )

    $source = Get-DaMaoWubiSourceInfo -SourcePath $SourcePath -RequireOfficialGitRemote:$RequireOfficialGitRemote
    try {
        if (-not (Test-Path -LiteralPath $RimeUserDir -PathType Container)) {
            New-Item -ItemType Directory -Path $RimeUserDir -Force | Out-Null
        }

        Copy-Item -LiteralPath $source.Dictionary -Destination (Join-Path $RimeUserDir 'wubi86.dict.yaml') -Force
        Copy-Item -LiteralPath $source.License -Destination (Join-Path $RimeUserDir 'LICENSE.rime-wubi.txt') -Force

        $metadata = [ordered]@{
            repository = 'https://github.com/rime/rime-wubi.git'
            method = $Method
            commit = $source.Commit
            installed_utc = [DateTime]::UtcNow.ToString('o')
            installed_files = @('wubi86.dict.yaml', 'LICENSE.rime-wubi.txt')
        }
        Write-DaMaoUtf8File -Path (Join-Path $RimeUserDir 'rime-wubi.source.json') -Content (($metadata | ConvertTo-Json) + "`n")
    }
    catch {
        if ($_.Exception.Message -match '^\[DM-WUBI-') {
            throw
        }
        throw "[DM-WUBI-INSTALL-FAILED] Could not install the validated wubi86 dependency into the Rime user directory. $($_.Exception.Message)"
    }
    return (Join-Path $RimeUserDir 'wubi86.dict.yaml')
}

function Install-DaMaoWubiFromGitHub {
    param([Parameter(Mandatory = $true)][string]$RimeUserDir)

    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($null -eq $git) {
        throw '[DM-WUBI-INSTALL-FAILED] Plum failed and Git was not found. Install Git for Windows or use -WubiSourcePath for offline installation.'
    }

    $cloneRoot = Join-Path ([System.IO.Path]::GetTempPath()) "damao-ime-rime-wubi-$([Guid]::NewGuid().ToString('N'))"
    try {
        $cloneOutput = (& $git.Source clone --depth 1 --branch master --single-branch 'https://github.com/rime/rime-wubi.git' $cloneRoot 2>&1 | Out-String)
        $cloneExitCode = $LASTEXITCODE
        if ($cloneExitCode -ne 0) {
            $networkPattern = 'Could not resolve host|Failed to connect|unable to access|Connection timed out|Connection reset|port 443|SSL|schannel|The requested URL returned error: [45]\d\d'
            if ($cloneOutput -match $networkPattern) {
                throw "[DM-NETWORK-UNAVAILABLE] Cannot reach the official GitHub repository. Plum and git clone both failed. Git output: $($cloneOutput.Trim())"
            }
            throw "[DM-WUBI-INSTALL-FAILED] git clone of official rime/rime-wubi failed. Git output: $($cloneOutput.Trim())"
        }

        return Install-DaMaoWubiFromSource -SourcePath $cloneRoot -RimeUserDir $RimeUserDir -Method github-clone -RequireOfficialGitRemote
    }
    finally {
        $safeTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedCloneRoot = [System.IO.Path]::GetFullPath($cloneRoot)
        if ($resolvedCloneRoot.StartsWith($safeTempRoot, [System.StringComparison]::OrdinalIgnoreCase) -and
            (Test-Path -LiteralPath $resolvedCloneRoot)) {
            Remove-Item -LiteralPath $resolvedCloneRoot -Recurse -Force
        }
    }
}

function Assert-DaMaoDeployerAvailable {
    param([string]$ProcessName = 'WeaselDeployer')

    $existingDeployers = @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue)
    if ($existingDeployers.Count -gt 0) {
        $processIds = ($existingDeployers | ForEach-Object { $_.Id }) -join ', '
        throw "[DM-DEPLOY-BUSY] A $ProcessName process is already running (PID: $processIds). Wait for it to exit or end it before starting another deployment."
    }
}

function Get-DaMaoDescendantProcessIds {
    param([Parameter(Mandatory = $true)][int]$ParentProcessId)

    try {
        $processRows = @(Get-CimInstance -ClassName Win32_Process -ErrorAction Stop |
            Select-Object ProcessId, ParentProcessId)
    }
    catch {
        if (-not ('DaMao.NativeProcessTree' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace DaMao {
    public static class NativeProcessTree {
        private const uint TH32CS_SNAPPROCESS = 0x00000002;
        private static readonly IntPtr INVALID_HANDLE_VALUE = new IntPtr(-1);

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct PROCESSENTRY32 {
            public uint dwSize;
            public uint cntUsage;
            public uint th32ProcessID;
            public IntPtr th32DefaultHeapID;
            public uint th32ModuleID;
            public uint cntThreads;
            public uint th32ParentProcessID;
            public int pcPriClassBase;
            public uint dwFlags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
            public string szExeFile;
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr CreateToolhelp32Snapshot(uint flags, uint processId);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool Process32FirstW(IntPtr snapshot, ref PROCESSENTRY32 entry);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool Process32NextW(IntPtr snapshot, ref PROCESSENTRY32 entry);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool CloseHandle(IntPtr handle);

        public static int[] GetDescendants(int parentProcessId) {
            var parentByProcess = new Dictionary<int, int>();
            IntPtr snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
            if (snapshot == INVALID_HANDLE_VALUE)
                return new int[0];
            try {
                var entry = new PROCESSENTRY32();
                entry.dwSize = (uint)Marshal.SizeOf(typeof(PROCESSENTRY32));
                if (Process32FirstW(snapshot, ref entry)) {
                    do {
                        parentByProcess[(int)entry.th32ProcessID] =
                            (int)entry.th32ParentProcessID;
                    } while (Process32NextW(snapshot, ref entry));
                }
            }
            finally {
                CloseHandle(snapshot);
            }

            var descendants = new List<int>();
            var pending = new Queue<int>();
            pending.Enqueue(parentProcessId);
            while (pending.Count > 0) {
                int parent = pending.Dequeue();
                foreach (var item in parentByProcess) {
                    if (item.Value == parent && !descendants.Contains(item.Key)) {
                        descendants.Add(item.Key);
                        pending.Enqueue(item.Key);
                    }
                }
            }
            return descendants.ToArray();
        }
    }
}
'@
        }
        return [DaMao.NativeProcessTree]::GetDescendants($ParentProcessId)
    }

    $descendants = [System.Collections.Generic.List[int]]::new()
    $pendingParents = [System.Collections.Generic.Queue[int]]::new()
    $pendingParents.Enqueue($ParentProcessId)
    while ($pendingParents.Count -gt 0) {
        $currentParent = $pendingParents.Dequeue()
        foreach ($row in ($processRows | Where-Object { [int]$_.ParentProcessId -eq $currentParent })) {
            $childId = [int]$row.ProcessId
            if (-not $descendants.Contains($childId)) {
                $descendants.Add($childId)
                $pendingParents.Enqueue($childId)
            }
        }
    }
    return $descendants.ToArray()
}

function Stop-DaMaoProcessTree {
    param([Parameter(Mandatory = $true)][System.Diagnostics.Process]$Process)

    $Process.Refresh()
    if ($Process.HasExited) {
        return
    }

    $descendantIds = @(Get-DaMaoDescendantProcessIds -ParentProcessId $Process.Id)
    $taskKill = Join-Path $env:SystemRoot 'System32\taskkill.exe'
    $taskKillOutput = ''
    if (Test-Path -LiteralPath $taskKill -PathType Leaf) {
        $previousErrorActionPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $taskKillOutput = (& $taskKill /PID $Process.Id /T /F 2>&1 | Out-String).Trim()
        }
        finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }
    }
    else {
        $taskKillOutput = 'taskkill.exe was not found; used Process.Kill() fallback.'
    }

    $Process.Refresh()
    try {
        if (-not $Process.HasExited) {
            $Process.Kill()
        }
    }
    catch {
        # The process may have exited between Refresh() and Kill().
    }
    foreach ($descendantId in ($descendantIds | Sort-Object -Descending)) {
        $descendant = Get-Process -Id $descendantId -ErrorAction SilentlyContinue
        if ($null -ne $descendant) {
            try {
                $descendant.Kill()
            }
            catch {
                # Verify all recorded descendants below before reporting success.
            }
        }
    }

    $cleanupDeadline = [DateTime]::UtcNow.AddSeconds(15)
    do {
        $Process.Refresh()
        $remainingDescendants = @($descendantIds | Where-Object {
            $null -ne (Get-Process -Id $_ -ErrorAction SilentlyContinue)
        })
        if ($Process.HasExited -and $remainingDescendants.Count -eq 0) {
            return
        }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $cleanupDeadline)

    throw "[DM-DEPLOY-CLEANUP-FAILED] WeaselDeployer process tree did not fully exit. Parent PID: $($Process.Id). Remaining child PIDs: $($remainingDescendants -join ', '). taskkill output: $taskKillOutput"
}

function Wait-DaMaoDeployerProcess {
    param(
        [Parameter(Mandatory = $true)][System.Diagnostics.Process]$Process,
        [Parameter(Mandatory = $true)][ValidateSet('/deploy', '/sync')][string]$Command,
        [ValidateRange(1, 1800)][int]$TimeoutSeconds = 120
    )

    $mainProcessExited = $Process.WaitForExit($TimeoutSeconds * 1000)
    if (-not $mainProcessExited) {
        Stop-DaMaoProcessTree -Process $Process
        $timeoutCode = if ($Command -eq '/deploy') { 'DM-DEPLOY-TIMEOUT' } else { 'DM-SYNC-TIMEOUT' }
        $latestLog = Get-DaMaoLatestRimeLogPath
        throw "[$timeoutCode] WeaselDeployer.exe $Command did not finish within $TimeoutSeconds second(s). Latest Rime log location: $latestLog"
    }
    $Process.Refresh()
    if ($Process.ExitCode -ne 0) {
        $errorCode = if ($Command -eq '/deploy') { 'DM-DEPLOY-FAILED' } else { 'DM-SYNC-FAILED' }
        $latestLog = Get-DaMaoLatestRimeLogPath
        throw "[$errorCode] WeaselDeployer.exe $Command failed with exit code $($Process.ExitCode). Latest Rime log location: $latestLog"
    }
}

function Get-DaMaoDeployerCommandDescription {
    param([AllowNull()][AllowEmptyString()][string]$Command)

    if ($null -eq $Command) {
        return 'Command=[<null>] Length=<null> CodePoints=[]'
    }

    $safeCharacters = foreach ($character in $Command.ToCharArray()) {
        $codePoint = [int][char]$character
        if ($codePoint -ge 0x20 -and $codePoint -le 0x7e) {
            [string]$character
        }
        else {
            '\u{0:X4}' -f $codePoint
        }
    }
    $codePoints = foreach ($character in $Command.ToCharArray()) {
        'U+{0:X4}' -f ([int][char]$character)
    }
    return 'Command=[{0}] Length={1} CodePoints=[{2}]' -f ($safeCharacters -join ''), $Command.Length, ($codePoints -join ' ')
}

function ConvertTo-DaMaoFullAlphaDiagnosticSchema {
    param([Parameter(Mandatory = $true)][string]$SchemaContent)

    $schemaIdMatches = [regex]::Matches($SchemaContent, '(?m)^  schema_id:\s*damao_wubi\s*$')
    $nameRegex = New-Object System.Text.RegularExpressions.Regex('(?m)^  name:[^\r\n]*$')
    $versionRegex = New-Object System.Text.RegularExpressions.Regex('(?m)^  version:[^\r\n]*$')
    if ($schemaIdMatches.Count -ne 1 -or
        $nameRegex.Matches($SchemaContent).Count -ne 1 -or
        $versionRegex.Matches($SchemaContent).Count -ne 1) {
        throw '[DM-DIAG-VARIANT-INVALID] The formal Alpha schema does not have one unambiguous schema_id/name/version identity block.'
    }

    $damaoDisplayName = -join @([char]0x5927, [char]0x732b, [char]0x8f93, [char]0x5165, [char]0x6cd5)
    $diagnosticNameLine = '  name: "' + $damaoDisplayName + ' Diagnostic 04 - Full Alpha"'
    $diagnosticContent = $nameRegex.Replace($SchemaContent, $diagnosticNameLine, 1)
    $diagnosticContent = $versionRegex.Replace($diagnosticContent, '  version: "0.1-diag-04"', 1)
    return $diagnosticContent
}

function New-DaMaoDeployerStartInfo {
    param(
        [Parameter(Mandatory = $true)][string]$DeployerPath,
        [AllowNull()][AllowEmptyString()][string]$Command
    )

    $isDeploy = [string]::Equals($Command, '/deploy', [System.StringComparison]::Ordinal)
    $isSync = [string]::Equals($Command, '/sync', [System.StringComparison]::Ordinal)
    if (-not $isDeploy -and -not $isSync) {
        $description = Get-DaMaoDeployerCommandDescription -Command $Command
        throw "[DM-DEPLOY-COMMAND-INVALID] WeaselDeployer command must be exactly /deploy or /sync. $description"
    }

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $DeployerPath
    $startInfo.WorkingDirectory = Split-Path -Parent $DeployerPath
    $startInfo.Arguments = $Command
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $false
    return $startInfo
}

function Invoke-DaMaoDeployer {
    param(
        [Parameter(Mandatory = $true)][string]$WeaselRoot,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Command,
        [ValidateRange(1, 1800)][int]$TimeoutSeconds = 120
    )

    $deployer = Join-Path $WeaselRoot 'WeaselDeployer.exe'
    if (-not (Test-Path -LiteralPath $deployer -PathType Leaf)) {
        throw "[DM-WEASEL-NOT-FOUND] Weasel deployer was not found: $deployer"
    }
    $startInfo = New-DaMaoDeployerStartInfo -DeployerPath $deployer -Command $Command
    $commandDescription = Get-DaMaoDeployerCommandDescription -Command $startInfo.Arguments
    Write-Host "Starting WeaselDeployer.exe: $commandDescription"

    Assert-DaMaoDeployerAvailable
    try {
        $process = [System.Diagnostics.Process]::Start($startInfo)
        if ($null -eq $process) {
            throw 'System.Diagnostics.Process.Start returned no process object.'
        }
    }
    catch {
        throw "[DM-DEPLOY-FAILED] Could not start WeaselDeployer.exe $Command. $($_.Exception.Message)"
    }
    Wait-DaMaoDeployerProcess -Process $process -Command $startInfo.Arguments -TimeoutSeconds $TimeoutSeconds
}

function Get-DaMaoRimeLogFiles {
    $tempRoot = [System.IO.Path]::GetTempPath()
    $logRoot = Join-Path $tempRoot 'rime.weasel'
    $candidates = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    $seenPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    if (Test-Path -LiteralPath $logRoot -PathType Container) {
        foreach ($file in (Get-ChildItem -LiteralPath $logRoot -File -Recurse -ErrorAction SilentlyContinue)) {
            if ($seenPaths.Add($file.FullName)) {
                $candidates.Add($file)
            }
        }
    }
    foreach ($file in (Get-ChildItem -LiteralPath $tempRoot -File -Filter 'rime.weasel*' -ErrorAction SilentlyContinue)) {
        if ($seenPaths.Add($file.FullName)) {
            $candidates.Add($file)
        }
    }

    return @($candidates | Sort-Object LastWriteTimeUtc -Descending)
}

function Get-DaMaoRimeLogSnapshot {
    $snapshot = @{}
    foreach ($file in (Get-DaMaoRimeLogFiles)) {
        try {
            $snapshot[$file.FullName] = [System.IO.File]::ReadAllText($file.FullName)
        }
        catch {
            # A concurrently rotating log can disappear between enumeration and reading.
        }
    }
    return $snapshot
}

function Assert-DaMaoWorkspaceDeploymentLog {
    param(
        [Parameter(Mandatory = $true)][hashtable]$BeforeSnapshot,
        [string]$SchemaId = 'damao_wubi'
    )

    $escapedSchemaId = [regex]::Escape($SchemaId)
    foreach ($file in (Get-DaMaoRimeLogFiles)) {
        try {
            $currentContent = [System.IO.File]::ReadAllText($file.FullName)
        }
        catch {
            continue
        }

        $newContent = $currentContent
        if ($BeforeSnapshot.ContainsKey($file.FullName)) {
            $previousContent = [string]$BeforeSnapshot[$file.FullName]
            if ($currentContent.StartsWith($previousContent, [System.StringComparison]::Ordinal)) {
                $newContent = $currentContent.Substring($previousContent.Length)
            }
            elseif ([string]::Equals($currentContent, $previousContent, [System.StringComparison]::Ordinal)) {
                $newContent = ''
            }
        }

        if ($newContent -match '(?im)updating schemas\b' -and
            $newContent -match "(?im)schema:\s*$escapedSchemaId\b") {
            return $file.FullName
        }
    }

    $latestLog = Get-DaMaoLatestRimeLogPath
    throw "[DM-DEPLOY-FAILED] WeaselDeployer exited successfully, but new Rime log output does not confirm 'updating schemas' and 'schema: $SchemaId'. The command may not have entered the /deploy workspace update path. Latest Rime log location: $latestLog"
}

function Get-DaMaoLatestRimeLogPath {
    $logRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'rime.weasel'
    $candidates = @(Get-DaMaoRimeLogFiles)

    $latest = $candidates | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if ($null -ne $latest) {
        return $latest.FullName
    }
    return $logRoot
}

function Assert-DaMaoDeployment {
    param([Parameter(Mandatory = $true)][string]$RimeUserDir)

    $builtDefault = Join-Path $RimeUserDir 'build\default.yaml'
    if (-not (Test-Path -LiteralPath $builtDefault -PathType Leaf)) {
        $latestLog = Get-DaMaoLatestRimeLogPath
        throw "[DM-DEPLOY-FAILED] WeaselDeployer exited successfully, but build\default.yaml was not generated: $builtDefault. Latest Rime log location: $latestLog"
    }

    $builtDefaultContent = [System.IO.File]::ReadAllText($builtDefault)
    if ($builtDefaultContent -notmatch '(?m)^\s*-\s*schema:\s*["'']?damao_wubi["'']?\s*(?:#.*)?$') {
        $latestLog = Get-DaMaoLatestRimeLogPath
        throw "[DM-DEPLOY-FAILED] WeaselDeployer exited successfully, but build\default.yaml does not register damao_wubi: $builtDefault. Latest Rime log location: $latestLog"
    }

    $builtSchema = Join-Path $RimeUserDir 'build\damao_wubi.schema.yaml'
    if (-not (Test-Path -LiteralPath $builtSchema -PathType Leaf)) {
        $latestLog = Get-DaMaoLatestRimeLogPath
        throw "[DM-DEPLOY-FAILED] build\default.yaml registers damao_wubi, but the compiled schema was not generated: $builtSchema. Latest Rime log location: $latestLog"
    }
}

function Get-DaMaoFormalSchemaContentFailures {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content)

    $damaoDisplayName = -join @([char]0x5927, [char]0x732b, [char]0x8f93, [char]0x5165, [char]0x6cd5)
    $displayNamePattern = '(?m)^\s*name:\s*["'']?{0}["'']?\s*$' -f [regex]::Escape($damaoDisplayName)
    $failures = [System.Collections.Generic.List[string]]::new()
    if ($Content -notmatch '(?m)^\s*schema_id:\s*["'']?damao_wubi["'']?\s*$') {
        $failures.Add('schema_id is not damao_wubi')
    }
    if ($Content -notmatch $displayNamePattern) {
        $failures.Add('schema name is not the formal DaMao display name')
    }
    if ($Content -match '(?im)^\s*name\s*:.*Diagnostic') {
        $failures.Add('schema name contains Diagnostic')
    }
    if ($Content -notmatch '(?m)^\s*dictionary:\s*["'']?wubi86["'']?\s*$') {
        $failures.Add('dictionary is not wubi86')
    }
    if ($Content -notmatch '(?m)^\s*max_code_length:\s*4\s*$') {
        $failures.Add('max_code_length is not 4')
    }
    if ($Content -notmatch '(?m)^\s*auto_select:\s*true\s*$') {
        $failures.Add('auto_select is not true')
    }
    if ($Content -match '(?m)^\s*auto_select_unique_candidate\s*:') {
        $failures.Add('auto_select_unique_candidate is present')
    }
    return $failures.ToArray()
}

function Assert-DaMaoFormalSchemaFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Context,
        [string]$ErrorCode = 'DM-INSTALL-SCHEMA-INVALID'
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "[$ErrorCode] $Context was not found: $Path"
    }
    $content = [System.IO.File]::ReadAllText($Path)
    $failures = @(Get-DaMaoFormalSchemaContentFailures -Content $content)
    if ($failures.Count -gt 0) {
        throw "[$ErrorCode] $Context is not the formal Alpha schema: $($failures -join '; '). Path: $Path"
    }
}

function Assert-DaMaoFormalDeployment {
    param([Parameter(Mandatory = $true)][string]$RimeUserDir)

    Assert-DaMaoDeployment -RimeUserDir $RimeUserDir
    $builtSchema = Join-Path $RimeUserDir 'build\damao_wubi.schema.yaml'
    try {
        Assert-DaMaoFormalSchemaFile -Path $builtSchema -Context 'Compiled DaMao schema' -ErrorCode 'DM-DEPLOY-FAILED'
    }
    catch {
        $latestLog = Get-DaMaoLatestRimeLogPath
        throw "$($_.Exception.Message) Latest Rime log location: $latestLog"
    }
}

function Write-DaMaoUtf8File {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function ConvertFrom-DaMaoSchemaFlowSequence {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value,
        [Parameter(Mandatory = $true)][int]$KeyIndex,
        [Parameter(Mandatory = $true)][string]$ContextPath
    )

    $trimmed = $Value.Trim()
    if ($trimmed -eq '[]') {
        return @()
    }
    if (-not ($trimmed.StartsWith('[') -and $trimmed.EndsWith(']'))) {
        throw "[DM-CONFIG-MERGE-UNSAFE] Cannot safely update $ContextPath because schema_list is not a YAML list."
    }

    $inner = $trimmed.Substring(1, $trimmed.Length - 2)
    if ([string]::IsNullOrWhiteSpace($inner)) {
        return @()
    }
    $objectPattern = '\{\s*schema\s*:\s*["'']?(?<schema>[A-Za-z0-9_.+-]+)["'']?\s*\}'
    $objectMatches = [regex]::Matches($inner, $objectPattern)
    if ($objectMatches.Count -eq 0) {
        throw "[DM-CONFIG-MERGE-UNSAFE] Cannot safely update $ContextPath because an inline schema_list entry is not a single schema mapping."
    }

    $entries = [System.Collections.Generic.List[object]]::new()
    $position = 0
    for ($matchIndex = 0; $matchIndex -lt $objectMatches.Count; $matchIndex++) {
        $match = $objectMatches[$matchIndex]
        $separator = $inner.Substring($position, $match.Index - $position)
        $validSeparator = if ($matchIndex -eq 0) {
            [string]::IsNullOrWhiteSpace($separator)
        }
        else {
            $separator -match '^\s*,\s*$'
        }
        if (-not $validSeparator) {
            throw "[DM-CONFIG-MERGE-UNSAFE] Cannot safely update $ContextPath because an inline schema_list has ambiguous content."
        }
        $entries.Add([PSCustomObject]@{
            Index = $KeyIndex
            SchemaId = $match.Groups['schema'].Value
            Style = 'flow'
            Comment = ''
        })
        $position = $match.Index + $match.Length
    }
    if (-not [string]::IsNullOrWhiteSpace($inner.Substring($position))) {
        throw "[DM-CONFIG-MERGE-UNSAFE] Cannot safely update $ContextPath because an inline schema_list has trailing ambiguous content."
    }
    return @($entries)
}

function Get-DaMaoPatchSchemaStructures {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][System.Collections.Generic.List[string]]$Lines,
        [Parameter(Mandatory = $true)][int]$PatchIndex,
        [Parameter(Mandatory = $true)][int]$PatchEnd,
        [string]$ContextPath = 'default.custom.yaml'
    )

    $childIndent = $null
    for ($index = $PatchIndex + 1; $index -lt $PatchEnd; $index++) {
        if ($Lines[$index] -match '^\s*(?:#.*)?$') {
            continue
        }
        $indent = $Lines[$index].Length - $Lines[$index].TrimStart().Length
        if ($indent -eq 0) {
            break
        }
        if ($null -eq $childIndent -or $indent -lt $childIndent) {
            $childIndent = $indent
        }
    }
    if ($null -eq $childIndent) {
        return @()
    }

    $structures = [System.Collections.Generic.List[object]]::new()
    $seenKeys = @{}
    $keyPattern = '^(?<space> +)(?<key>schema_list(?:/\+|/@next|/@before 0)?|"schema_list(?:/\+|/@next|/@before 0)?"|''schema_list(?:/\+|/@next|/@before 0)?'')\s*:\s*(?<value>.*)$'
    for ($index = $PatchIndex + 1; $index -lt $PatchEnd; $index++) {
        $line = $Lines[$index]
        $indent = $line.Length - $line.TrimStart().Length
        if ($indent -ne $childIndent) {
            continue
        }
        if ($line -notmatch $keyPattern) {
            if ($line.TrimStart() -match '^["'']?schema_list(?:[/@][^"'':]+)?["'']?\s*:') {
                throw "[DM-CONFIG-MERGE-UNSAFE] Cannot safely update $ContextPath because it contains an unsupported schema_list patch operation."
            }
            continue
        }

        $key = $Matches.key.Trim([char[]]@('"', "'"))
        if ($seenKeys.ContainsKey($key)) {
            throw "[DM-CONFIG-MERGE-UNSAFE] Cannot safely update $ContextPath because it contains a duplicate $key key."
        }
        $seenKeys[$key] = $true
        $value = $Matches.value
        $keyComment = ''
        if ($value -match '^\s*(?<comment>#.*)$') {
            $keyComment = ' ' + $Matches.comment
            $value = ''
        }

        $entries = [System.Collections.Generic.List[object]]::new()
        $endIndex = $index + 1
        $sequenceIndent = $null
        $entryStyle = $null
        $isInlineValue = -not [string]::IsNullOrWhiteSpace($value)
        if (-not $isInlineValue) {
            $lastOwnedIndex = $index
            for ($entryIndex = $index + 1; $entryIndex -lt $PatchEnd; $entryIndex++) {
                $entryLine = $Lines[$entryIndex]
                if ($entryLine -match '^\s*$') {
                    continue
                }
                $entryIndent = $entryLine.Length - $entryLine.TrimStart().Length
                if ($entryIndent -le $childIndent) {
                    break
                }
                $lastOwnedIndex = $entryIndex
                if ($entryLine -match '^\s*#') {
                    throw "[DM-CONFIG-MERGE-UNSAFE] Cannot safely update $ContextPath because a standalone comment inside $key cannot be associated with one schema entry."
                }
                if ($null -eq $sequenceIndent) {
                    $sequenceIndent = $entryIndent
                }
                if ($entryIndent -ne $sequenceIndent) {
                    throw "[DM-CONFIG-MERGE-UNSAFE] Cannot safely update $ContextPath because $key contains a nested or multi-line schema entry."
                }

                $entryMatch = [regex]::Match($entryLine, '^\s*-\s*schema\s*:\s*["'']?(?<schema>[A-Za-z0-9_.+-]+)["'']?\s*(?<comment>#.*)?$')
                $style = 'block'
                if (-not $entryMatch.Success) {
                    $entryMatch = [regex]::Match($entryLine, '^\s*-\s*\{\s*schema\s*:\s*["'']?(?<schema>[A-Za-z0-9_.+-]+)["'']?\s*\}\s*(?<comment>#.*)?$')
                    $style = 'flow'
                }
                if (-not $entryMatch.Success) {
                    throw "[DM-CONFIG-MERGE-UNSAFE] Cannot safely update $ContextPath because line $($entryIndex + 1) is not a single schema list entry."
                }
                if ($null -eq $entryStyle) {
                    $entryStyle = $style
                }
                $comment = if ($entryMatch.Groups['comment'].Success) { ' ' + $entryMatch.Groups['comment'].Value } else { '' }
                $entries.Add([PSCustomObject]@{
                    Index = $entryIndex
                    SchemaId = $entryMatch.Groups['schema'].Value
                    Style = $style
                    Comment = $comment
                })
            }
            $endIndex = $lastOwnedIndex + 1
            if ($entries.Count -eq 0) {
                throw "[DM-CONFIG-MERGE-UNSAFE] Cannot safely update $ContextPath because $key has a null value instead of a YAML list. Use [] for an empty list."
            }
        }
        else {
            $trimmedValue = ($value -replace '\s+#.*$', '').Trim()
            if ($key -in @('schema_list/@next', 'schema_list/@before 0') -and
                $trimmedValue -match '^\{\s*schema\s*:\s*["'']?(?<schema>[A-Za-z0-9_.+-]+)["'']?\s*\}$') {
                $entries.Add([PSCustomObject]@{
                    Index = $index
                    SchemaId = $Matches.schema
                    Style = 'flow'
                    Comment = ''
                })
                $entryStyle = 'flow'
            }
            elseif ($trimmedValue.StartsWith('[')) {
                foreach ($entry in (ConvertFrom-DaMaoSchemaFlowSequence -Value $trimmedValue -KeyIndex $index -ContextPath $ContextPath)) {
                    $entries.Add($entry)
                }
                $entryStyle = 'flow'
            }
            else {
                throw "[DM-CONFIG-MERGE-UNSAFE] Cannot safely update $ContextPath because $key is not a YAML schema list."
            }
        }

        $structures.Add([PSCustomObject]@{
            Key = $key
            KeyIndex = $index
            EndIndex = $endIndex
            KeyIndent = $childIndent
            SequenceIndent = $sequenceIndent
            EntryStyle = $entryStyle
            KeyComment = $keyComment
            IsInlineValue = $isInlineValue
            Entries = @($entries)
        })
    }
    return @($structures)
}

function Get-DaMaoNormalizedSchemaSelectionContent {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][System.Collections.Generic.List[string]]$Lines,
        [Parameter(Mandatory = $true)][int]$PatchEnd,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Structures,
        [switch]$PreferDamaoFirst
    )

    $explicit = @($Structures | Where-Object { $_.Key -eq 'schema_list' } | Select-Object -First 1)
    $append = @($Structures | Where-Object { $_.Key -eq 'schema_list/+' } | Select-Object -First 1)
    $prepend = @($Structures | Where-Object { $_.Key -eq 'schema_list/@before 0' } | Select-Object -First 1)
    $next = @($Structures | Where-Object { $_.Key -eq 'schema_list/@next' } | Select-Object -First 1)
    $target = if ($explicit.Count -gt 0) { $explicit[0] } elseif ($append.Count -gt 0) { $append[0] } elseif ($prepend.Count -gt 0) { $prepend[0] } elseif ($next.Count -gt 0) { $next[0] } else { $null }
    $orderedStructures = @($prepend + $explicit + $append + $next)

    $legacyProjectSchemaId = 'modern' + '_' + 'wubi'
    $seenSchemaIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $normalizedEntries = [System.Collections.Generic.List[object]]::new()
    if ($PreferDamaoFirst) {
        [void]$seenSchemaIds.Add('damao_wubi')
        $normalizedEntries.Add([PSCustomObject]@{
            Index = -1
            SchemaId = 'damao_wubi'
            Style = 'block'
            Comment = ''
        })
    }
    foreach ($structure in $orderedStructures) {
        foreach ($entry in $structure.Entries) {
            if ([string]::Equals($entry.SchemaId, $legacyProjectSchemaId, [System.StringComparison]::Ordinal)) {
                continue
            }
            if ($seenSchemaIds.Add($entry.SchemaId)) {
                $normalizedEntries.Add($entry)
            }
        }
    }

    $targetStyle = if ($null -ne $target -and -not [string]::IsNullOrWhiteSpace($target.EntryStyle)) { $target.EntryStyle } else { 'block' }
    if ($seenSchemaIds.Add('damao_wubi')) {
        $normalizedEntries.Add([PSCustomObject]@{
            Index = -1
            SchemaId = 'damao_wubi'
            Style = $targetStyle
            Comment = ''
        })
    }

    $targetKey = if ($PreferDamaoFirst -or $explicit.Count -gt 0) { 'schema_list' } else { 'schema_list/+' }
    $keyIndent = if ($null -ne $target) { [int]$target.KeyIndent } else { 2 }
    $sequenceIndent = if ($null -ne $target -and $null -ne $target.SequenceIndent) { [int]$target.SequenceIndent } else { $keyIndent + 2 }
    $insertIndex = if ($null -ne $target) { [int]$target.KeyIndex } else { $PatchEnd }
    $keyComment = if ($null -ne $target) { [string]$target.KeyComment } else { '' }
    $keyText = if ($targetKey -eq 'schema_list') { 'schema_list:' } else { '"schema_list/+":' }

    $canonicalLines = [System.Collections.Generic.List[string]]::new()
    $canonicalLines.Add(((' ' * $keyIndent) + $keyText + $keyComment))
    foreach ($entry in $normalizedEntries) {
        $comment = [string]$entry.Comment
        if ($targetStyle -eq 'flow') {
            $canonicalLines.Add(((' ' * $sequenceIndent) + '- {schema: ' + $entry.SchemaId + '}' + $comment))
        }
        else {
            $canonicalLines.Add(((' ' * $sequenceIndent) + '- schema: ' + $entry.SchemaId + $comment))
        }
    }

    $skipIndices = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($structure in $Structures) {
        for ($index = [int]$structure.KeyIndex; $index -lt [int]$structure.EndIndex; $index++) {
            [void]$skipIndices.Add($index)
        }
    }

    $newLines = [System.Collections.Generic.List[string]]::new()
    for ($index = 0; $index -le $Lines.Count; $index++) {
        if ($index -eq $insertIndex) {
            foreach ($canonicalLine in $canonicalLines) {
                $newLines.Add($canonicalLine)
            }
        }
        if ($index -eq $Lines.Count) {
            break
        }
        if (-not $skipIndices.Contains($index)) {
            $newLines.Add($Lines[$index])
        }
    }
    return (($newLines -join "`n").TrimEnd() + "`n")
}

function Get-DaMaoPatchSchemaListEntries {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][System.Collections.Generic.List[string]]$Lines,
        [Parameter(Mandatory = $true)][int]$PatchIndex,
        [Parameter(Mandatory = $true)][int]$PatchEnd,
        [string]$ContextPath = 'default.custom.yaml'
    )

    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($structure in (Get-DaMaoPatchSchemaStructures -Lines $Lines -PatchIndex $PatchIndex -PatchEnd $PatchEnd -ContextPath $ContextPath)) {
        foreach ($entry in $structure.Entries) {
            $entries.Add([PSCustomObject]@{
                Index = $entry.Index
                SchemaId = $entry.SchemaId
                Key = $structure.Key
                Style = $entry.Style
            })
        }
    }
    return @($entries)
}

function Test-DaMaoSchemaRegistered {
    param(
        [Parameter(Mandatory = $true)][string]$DefaultCustomPath,
        [string]$SchemaId = 'damao_wubi'
    )

    if (-not (Test-Path -LiteralPath $DefaultCustomPath -PathType Leaf)) {
        return $false
    }
    $content = [System.IO.File]::ReadAllText($DefaultCustomPath)
    if ($content.Length -gt 0 -and $content[0] -eq [char]0xFEFF) {
        $content = $content.Substring(1)
    }
    if ($content.Contains("`t")) {
        return $false
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in ($content -split "`r?`n")) {
        $lines.Add($line)
    }
    $patchIndices = @()
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match '^patch:\s*(?:#.*)?$') {
            $patchIndices += $index
        }
    }
    if ($patchIndices.Count -ne 1) {
        return $false
    }

    $patchIndex = $patchIndices[0]
    $patchEnd = $lines.Count
    for ($index = $patchIndex + 1; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match '^[^\s#][^:]*:\s*' -or $lines[$index] -match '^(?:---|\.\.\.)\s*$') {
            $patchEnd = $index
            break
        }
    }
    try {
        foreach ($entry in (Get-DaMaoPatchSchemaListEntries -Lines $lines -PatchIndex $patchIndex -PatchEnd $patchEnd -ContextPath $DefaultCustomPath)) {
            if ([string]::Equals($entry.SchemaId, $SchemaId, [System.StringComparison]::Ordinal)) {
                return $true
            }
        }
    }
    catch {
        return $false
    }
    return $false
}

function Add-DaMaoSchemaSelection {
    param(
        [Parameter(Mandatory = $true)][string]$DefaultCustomPath,
        [Parameter(Mandatory = $true)][string]$BackupDirectory,
        [switch]$PreferAsFirstSchema
    )

    $selectionKey = '"schema_list/+":'
    if (-not (Test-Path -LiteralPath $DefaultCustomPath -PathType Leaf)) {
        $newContent = if ($PreferAsFirstSchema) {
            "patch:`n  `"schema_list/@before 0`": { schema: damao_wubi }`n"
        }
        else {
            "patch:`n  $selectionKey`n    - schema: damao_wubi`n"
        }
        Write-DaMaoUtf8File -Path $DefaultCustomPath -Content $newContent
        return $true
    }

    $content = [System.IO.File]::ReadAllText($DefaultCustomPath)
    $parseContent = $content
    if ($parseContent.Length -gt 0 -and $parseContent[0] -eq [char]0xFEFF) {
        $parseContent = $parseContent.Substring(1)
    }
    if ($parseContent.Contains("`t")) {
        throw "[DM-CONFIG-MERGE-UNSAFE] Cannot safely update $DefaultCustomPath because it contains tab indentation."
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in ($parseContent -split "`r?`n")) {
        $lines.Add($line)
    }

    $patchIndices = [System.Collections.Generic.List[int]]::new()
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        if ($line -match '^patch:\s*(?:#.*)?$') {
            $patchIndices.Add($index)
            continue
        }
        if ($line -match '^patch\s*:') {
            throw "[DM-CONFIG-MERGE-UNSAFE] Cannot safely update $DefaultCustomPath because its top-level patch value is not a block."
        }
        if ($line -notmatch '^\s*(?:#.*)?$' -and
            $line -notmatch '^(?:---|\.\.\.)\s*$' -and
            $line -notmatch '^\s' -and
            $line -notmatch '^[^:#][^:]*:\s*.*$') {
            throw "[DM-CONFIG-MERGE-UNSAFE] Cannot safely update $DefaultCustomPath because line $($index + 1) is not a recognizable top-level YAML mapping."
        }
    }

    if ($patchIndices.Count -gt 1) {
        throw "[DM-CONFIG-MERGE-UNSAFE] Cannot safely update $DefaultCustomPath because it contains multiple top-level patch blocks."
    }

    if ($patchIndices.Count -eq 0) {
        if (-not (Test-Path -LiteralPath $BackupDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $BackupDirectory -Force | Out-Null
        }
        Copy-Item -LiteralPath $DefaultCustomPath -Destination (Join-Path $BackupDirectory 'default.custom.yaml') -Force

        $existingContent = $parseContent.TrimEnd([char[]]@("`r", "`n"))
        $separator = if ([string]::IsNullOrWhiteSpace($existingContent)) { '' } else { "`n`n" }
        $newSelection = if ($PreferAsFirstSchema) {
            '  "schema_list/@before 0": { schema: damao_wubi }'
        }
        else {
            "  $selectionKey`n    - schema: damao_wubi"
        }
        Write-DaMaoUtf8File -Path $DefaultCustomPath -Content "$existingContent${separator}patch:`n$newSelection`n"
        return $true
    }

    $patchIndex = $patchIndices[0]
    $patchEnd = $lines.Count
    for ($index = $patchIndex + 1; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match '^[^\s#][^:]*:\s*' -or $lines[$index] -match '^(?:---|\.\.\.)\s*$') {
            $patchEnd = $index
            break
        }
    }

    $schemaStructures = @(Get-DaMaoPatchSchemaStructures -Lines $lines -PatchIndex $patchIndex -PatchEnd $patchEnd -ContextPath $DefaultCustomPath)
    $projectPrepend = @($schemaStructures | Where-Object {
        $_.Key -eq 'schema_list/@before 0' -and $_.Entries.Count -eq 1 -and $_.Entries[0].SchemaId -eq 'damao_wubi'
    })
    if ($schemaStructures.Count -eq 1 -and $projectPrepend.Count -eq 1) {
        return $false
    }
    if ($PreferAsFirstSchema -and $schemaStructures.Count -eq 0) {
        $childIndent = 2
        for ($index = $patchIndex + 1; $index -lt $patchEnd; $index++) {
            if ($lines[$index] -match '^\s*(?:#.*)?$') {
                continue
            }
            $indent = $lines[$index].Length - $lines[$index].TrimStart().Length
            if ($indent -gt 0 -and $indent -lt $childIndent) {
                $childIndent = $indent
            }
        }
        $lines.Insert($patchEnd, ((' ' * $childIndent) + '"schema_list/@before 0": { schema: damao_wubi }'))
        if (-not (Test-Path -LiteralPath $BackupDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $BackupDirectory -Force | Out-Null
        }
        Copy-Item -LiteralPath $DefaultCustomPath -Destination (Join-Path $BackupDirectory 'default.custom.yaml') -Force
        Write-DaMaoUtf8File -Path $DefaultCustomPath -Content (($lines -join "`n").TrimEnd() + "`n")
        return $true
    }
    $requiresFullNormalization = $PreferAsFirstSchema -or $schemaStructures.Count -gt 1 -or
        @($schemaStructures | Where-Object { $_.Key -eq 'schema_list/@next' -or $_.IsInlineValue -or $_.EntryStyle -eq 'flow' }).Count -gt 0
    if ($requiresFullNormalization) {
        $normalizedContent = Get-DaMaoNormalizedSchemaSelectionContent -Lines $lines -PatchEnd $patchEnd `
            -Structures $schemaStructures -PreferDamaoFirst:$PreferAsFirstSchema
        $existingCore = $parseContent.TrimEnd([char[]]@("`r", "`n")) -replace "`r`n", "`n"
        $normalizedCore = $normalizedContent.TrimEnd([char[]]@("`r", "`n"))
        if ($normalizedCore -ceq $existingCore) {
            return $false
        }
        if (-not (Test-Path -LiteralPath $BackupDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $BackupDirectory -Force | Out-Null
        }
        Copy-Item -LiteralPath $DefaultCustomPath -Destination (Join-Path $BackupDirectory 'default.custom.yaml') -Force
        Write-DaMaoUtf8File -Path $DefaultCustomPath -Content $normalizedContent
        return $true
    }

    $patchChildIndent = $null
    for ($index = $patchIndex + 1; $index -lt $patchEnd; $index++) {
        if ($lines[$index] -match '^\s*(?:#.*)?$') {
            continue
        }
        $indent = $lines[$index].Length - $lines[$index].TrimStart().Length
        if ($null -eq $patchChildIndent -or $indent -lt $patchChildIndent) {
            $patchChildIndent = $indent
        }
    }
    # The old schema ID was used only during development. Remove it only from
    # schema selection structures that this merger can identify unambiguously.
    $legacyProjectSchemaId = 'modern' + '_' + 'wubi'
    $selectionCleanupChanged = $false
    $selectionRemovalIndices = [System.Collections.Generic.HashSet[int]]::new()
    $seenSchemaIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($entry in (Get-DaMaoPatchSchemaListEntries -Lines $lines -PatchIndex $patchIndex -PatchEnd $patchEnd -ContextPath $DefaultCustomPath)) {
        if ([string]::Equals($entry.SchemaId, $legacyProjectSchemaId, [System.StringComparison]::Ordinal)) {
            [void]$selectionRemovalIndices.Add($entry.Index)
            continue
        }
        if (-not $seenSchemaIds.Add($entry.SchemaId)) {
            [void]$selectionRemovalIndices.Add($entry.Index)
        }
    }

    $escapedLegacyProjectSchemaId = [regex]::Escape($legacyProjectSchemaId)
    $legacyNextPattern = '^(?<space> +)(?:"schema_list/@next"|''schema_list/@next''|schema_list/@next)\s*:\s*\{\s*schema\s*:\s*["'']?' +
        $escapedLegacyProjectSchemaId + '["'']?\s*\}\s*(?:#.*)?$'
    for ($index = $patchIndex + 1; $index -lt $patchEnd; $index++) {
        if ($lines[$index] -match $legacyNextPattern) {
            [void]$selectionRemovalIndices.Add($index)
        }
    }

    foreach ($removalIndex in @($selectionRemovalIndices | Sort-Object -Descending)) {
        $lines.RemoveAt([int]$removalIndex)
        $patchEnd--
        $selectionCleanupChanged = $true
    }

    $damaoAlreadyPresent = $false
    foreach ($entry in (Get-DaMaoPatchSchemaListEntries -Lines $lines -PatchIndex $patchIndex -PatchEnd $patchEnd -ContextPath $DefaultCustomPath)) {
        if ([string]::Equals($entry.SchemaId, 'damao_wubi', [System.StringComparison]::Ordinal)) {
            $damaoAlreadyPresent = $true
            break
        }
    }

    $nextSelectionIndex = -1
    $nextSelectionIndent = -1
    for ($index = $patchIndex + 1; $index -lt $patchEnd; $index++) {
        if ($lines[$index] -match '^(?<space> +)(?:"schema_list/@next"|''schema_list/@next''|schema_list/@next)\s*:\s*\{\s*schema\s*:\s*["'']?damao_wubi["'']?\s*\}\s*(?:#.*)?$') {
            if ($nextSelectionIndex -ne -1) {
                throw "[DM-CONFIG-MERGE-UNSAFE] Cannot safely migrate multiple legacy schema_list/@next selections in $DefaultCustomPath."
            }
            $nextSelectionIndex = $index
            $nextSelectionIndent = $Matches.space.Length
        }
    }

    if ($nextSelectionIndex -ne -1) {
        if ($damaoAlreadyPresent) {
            $lines.RemoveAt($nextSelectionIndex)
        }
        else {
            $lines[$nextSelectionIndex] = ((' ' * $nextSelectionIndent) + $selectionKey)
            $lines.Insert($nextSelectionIndex + 1, ((' ' * ($nextSelectionIndent + 2)) + '- schema: damao_wubi'))
        }

        if (-not (Test-Path -LiteralPath $BackupDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $BackupDirectory -Force | Out-Null
        }
        Copy-Item -LiteralPath $DefaultCustomPath -Destination (Join-Path $BackupDirectory 'default.custom.yaml') -Force
        Write-DaMaoUtf8File -Path $DefaultCustomPath -Content (($lines -join "`n").TrimEnd() + "`n")
        return $true
    }
    if ($damaoAlreadyPresent) {
        if (-not $selectionCleanupChanged) {
            return $false
        }
        if (-not (Test-Path -LiteralPath $BackupDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $BackupDirectory -Force | Out-Null
        }
        Copy-Item -LiteralPath $DefaultCustomPath -Destination (Join-Path $BackupDirectory 'default.custom.yaml') -Force
        Write-DaMaoUtf8File -Path $DefaultCustomPath -Content (($lines -join "`n").TrimEnd() + "`n")
        return $true
    }

    $childIndent = $null
    for ($index = $patchIndex + 1; $index -lt $patchEnd; $index++) {
        if ($lines[$index] -match '^\s*(?:#.*)?$') {
            continue
        }
        $indent = $lines[$index].Length - $lines[$index].TrimStart().Length
        if ($indent -eq 0) {
            throw "[DM-CONFIG-MERGE-UNSAFE] Cannot safely determine the patch block boundary in $DefaultCustomPath."
        }
        if ($null -eq $childIndent -or $indent -lt $childIndent) {
            $childIndent = $indent
        }
    }
    if ($null -eq $childIndent) {
        $childIndent = 2
    }

    $schemaListIndex = -1
    $schemaListIndent = -1
    $hasOtherSchemaListPatch = $false
    for ($index = $patchIndex + 1; $index -lt $patchEnd; $index++) {
        $line = $lines[$index]
        if ($line -match '^(?<space> +)(?:schema_list|"schema_list"|''schema_list''|schema_list/\+|"schema_list/\+"|''schema_list/\+'')\s*:\s*(?<value>.*)$') {
            $indent = $Matches.space.Length
            if ($indent -eq $childIndent) {
                if (-not [string]::IsNullOrWhiteSpace(($Matches.value -replace '\s+#.*$', ''))) {
                    throw "[DM-CONFIG-MERGE-UNSAFE] Cannot safely append to an inline schema_list in $DefaultCustomPath."
                }
                if ($schemaListIndex -ne -1) {
                    throw "[DM-CONFIG-MERGE-UNSAFE] Cannot safely update $DefaultCustomPath because it contains multiple schema_list keys."
                }
                $schemaListIndex = $index
                $schemaListIndent = $indent
            }
            else {
                $hasOtherSchemaListPatch = $true
            }
        }
        elseif ($line -match 'schema_list(?:/|\b)') {
            $hasOtherSchemaListPatch = $true
        }
    }

    if ($schemaListIndex -ne -1) {
        if ($hasOtherSchemaListPatch) {
            throw "[DM-CONFIG-MERGE-UNSAFE] Cannot safely combine multiple schema_list patch structures in $DefaultCustomPath."
        }
        $schemaListEnd = $patchEnd
        $sequenceIndent = $null
        for ($index = $schemaListIndex + 1; $index -lt $patchEnd; $index++) {
            if ($lines[$index] -match '^\s*(?:#.*)?$') {
                continue
            }
            $indent = $lines[$index].Length - $lines[$index].TrimStart().Length
            if ($indent -le $schemaListIndent) {
                $schemaListEnd = $index
                break
            }
            if ($null -eq $sequenceIndent) {
                if ($lines[$index].TrimStart() -notmatch '^-\s+') {
                    throw "[DM-CONFIG-MERGE-UNSAFE] Cannot safely append to schema_list in $DefaultCustomPath because it is not a YAML sequence."
                }
                $sequenceIndent = $indent
            }
        }
        if ($null -eq $sequenceIndent) {
            $sequenceIndent = $schemaListIndent + 2
        }
        $lines.Insert($schemaListEnd, ((' ' * $sequenceIndent) + '- schema: damao_wubi'))
    }
    else {
        if ($hasOtherSchemaListPatch) {
            throw "[DM-CONFIG-MERGE-UNSAFE] Cannot safely merge DaMao Input Method with the existing schema_list patch structure in $DefaultCustomPath."
        }
        $lines.Insert($patchEnd, ((' ' * $childIndent) + $selectionKey))
        $lines.Insert($patchEnd + 1, ((' ' * ($childIndent + 2)) + '- schema: damao_wubi'))
    }

    if (-not (Test-Path -LiteralPath $BackupDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $BackupDirectory -Force | Out-Null
    }
    Copy-Item -LiteralPath $DefaultCustomPath -Destination (Join-Path $BackupDirectory 'default.custom.yaml') -Force
    Write-DaMaoUtf8File -Path $DefaultCustomPath -Content (($lines -join "`n").TrimEnd() + "`n")
    return $true
}

function Remove-DaMaoSchemaSelection {
    param(
        [Parameter(Mandatory = $true)][string]$DefaultCustomPath,
        [string]$SchemaId = 'damao_wubi'
    )

    if (-not (Test-Path -LiteralPath $DefaultCustomPath -PathType Leaf)) {
        return $false
    }
    $content = [System.IO.File]::ReadAllText($DefaultCustomPath)
    $parseContent = $content
    if ($parseContent.Length -gt 0 -and $parseContent[0] -eq [char]0xFEFF) {
        $parseContent = $parseContent.Substring(1)
    }
    if ($parseContent.Contains("`t")) {
        throw "[DM-CONFIG-MERGE-UNSAFE] Cannot safely update $DefaultCustomPath because it contains tab indentation."
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in ($parseContent -split "`r?`n")) {
        $lines.Add($line)
    }
    $patchIndices = @()
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match '^patch:\s*(?:#.*)?$') {
            $patchIndices += $index
        }
        elseif ($lines[$index] -match '^patch\s*:') {
            throw "[DM-CONFIG-MERGE-UNSAFE] Cannot safely update $DefaultCustomPath because its top-level patch value is not a block."
        }
    }
    if ($patchIndices.Count -eq 0) {
        return $false
    }
    if ($patchIndices.Count -ne 1) {
        throw "[DM-CONFIG-MERGE-UNSAFE] Cannot safely update $DefaultCustomPath because it contains multiple top-level patch blocks."
    }

    $patchIndex = [int]$patchIndices[0]
    $patchEnd = $lines.Count
    for ($index = $patchIndex + 1; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match '^[^\s#][^:]*:\s*' -or $lines[$index] -match '^(?:---|\.\.\.)\s*$') {
            $patchEnd = $index
            break
        }
    }
    $structures = @(Get-DaMaoPatchSchemaStructures -Lines $lines -PatchIndex $patchIndex `
        -PatchEnd $patchEnd -ContextPath $DefaultCustomPath)
    $changed = $false
    foreach ($structure in @($structures | Sort-Object KeyIndex -Descending)) {
        $matching = @($structure.Entries | Where-Object {
            [string]::Equals($_.SchemaId, $SchemaId, [System.StringComparison]::Ordinal)
        })
        if ($matching.Count -eq 0) {
            continue
        }
        $remaining = @($structure.Entries | Where-Object {
            -not [string]::Equals($_.SchemaId, $SchemaId, [System.StringComparison]::Ordinal)
        })
        if (-not $structure.IsInlineValue) {
            if ($remaining.Count -eq 0) {
                for ($removeIndex = [int]$structure.EndIndex - 1; $removeIndex -ge [int]$structure.KeyIndex; $removeIndex--) {
                    $lines.RemoveAt($removeIndex)
                }
            }
            else {
                foreach ($entryIndex in @($matching.Index | Sort-Object -Descending -Unique)) {
                    $lines.RemoveAt([int]$entryIndex)
                }
            }
        }
        elseif ($remaining.Count -eq 0) {
            $lines.RemoveAt([int]$structure.KeyIndex)
        }
        else {
            $keyText = if ($structure.Key -eq 'schema_list') {
                'schema_list:'
            }
            else {
                '"' + $structure.Key + '":'
            }
            $entryText = @($remaining | ForEach-Object { '{ schema: ' + $_.SchemaId + ' }' }) -join ', '
            $lines[[int]$structure.KeyIndex] = ((' ' * [int]$structure.KeyIndent) +
                $keyText + ' [ ' + $entryText + ' ]' + [string]$structure.KeyComment)
        }
        $changed = $true
    }
    if (-not $changed) {
        return $false
    }

    $hasPatchChild = $false
    for ($index = $patchIndex + 1; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match '^[^\s#][^:]*:\s*' -or $lines[$index] -match '^(?:---|\.\.\.)\s*$') {
            break
        }
        if ($lines[$index] -notmatch '^\s*(?:#.*)?$') {
            $hasPatchChild = $true
            break
        }
    }
    if (-not $hasPatchChild) {
        $lines.RemoveAt($patchIndex)
    }

    $remainingContent = (($lines -join "`n").TrimEnd())
    $meaningfulLines = @($remainingContent -split "`n" | Where-Object {
        $_ -notmatch '^\s*(?:#.*)?$'
    })
    if ($meaningfulLines.Count -eq 0) {
        Remove-Item -LiteralPath $DefaultCustomPath -Force
    }
    else {
        Write-DaMaoUtf8File -Path $DefaultCustomPath -Content ($remainingContent + "`n")
    }
    return $true
}
