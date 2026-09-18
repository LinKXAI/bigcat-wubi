[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RimeUserDir,
    [string]$WeaselRoot,
    [string]$WubiSourcePath,
    [switch]$InstallWubiDependency,
    [switch]$SkipDeploy,
    [switch]$UserFacingRedeploy,
    [switch]$InitializeFreshRimeState,
    [string]$InstallerStatePath
)

$ErrorActionPreference = 'Stop'

if ($UserFacingRedeploy) {
    # Windows PowerShell 5.1 otherwise uses the machine OEM code page for redirected host output.
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

    function Write-DaMaoRedeployMessage {
        param(
            [AllowEmptyString()][string]$Message = '',
            [System.ConsoleColor]$ForegroundColor
        )

        if ([Console]::IsOutputRedirected) {
            [Console]::Out.WriteLine($Message)
        }
        elseif ($PSBoundParameters.ContainsKey('ForegroundColor')) {
            Write-Host $Message -ForegroundColor $ForegroundColor
        }
        else {
            Write-Host $Message
        }
    }

    $forwardedParameters = @{}
    foreach ($parameterName in @('RimeUserDir', 'WeaselRoot', 'WubiSourcePath', 'InstallWubiDependency', 'SkipDeploy')) {
        if ($PSBoundParameters.ContainsKey($parameterName)) {
            $forwardedParameters[$parameterName] = $PSBoundParameters[$parameterName]
        }
    }

    try {
        & $PSCommandPath @forwardedParameters
    }
    catch {
        $errorRecord = $_
        $errorCodeMatch = [regex]::Match($errorRecord.Exception.Message, '\[(?<code>DM-[A-Z0-9-]+)\]')
        $errorCode = if ($errorCodeMatch.Success) { $errorCodeMatch.Groups['code'].Value } else { 'DM-REDEPLOY-FAILED' }
        $redeployLog = Join-Path ([System.IO.Path]::GetTempPath()) 'BigCatWubi-redeploy.log'

        try {
            $logEntry = @(
                "[$(Get-Date -Format o)] $errorCode"
                ($errorRecord | Out-String).TrimEnd()
                ''
            ) -join [Environment]::NewLine
            Add-Content -LiteralPath $redeployLog -Value $logEntry -Encoding UTF8
        }
        catch {
            # Logging must not replace or expose the original deployment failure.
        }

        Write-DaMaoRedeployMessage
        Write-DaMaoRedeployMessage `
            -Message ([regex]::Unescape('\u5927\u732b\u4e94\u7b14\u91cd\u65b0\u90e8\u7f72\u672a\u5b8c\u6210\u3002')) `
            -ForegroundColor Red
        Write-DaMaoRedeployMessage
        if ($errorCode -eq 'DM-WEASEL-NOT-FOUND') {
            Write-DaMaoRedeployMessage ([regex]::Unescape('\u672a\u68c0\u6d4b\u5230\u5c0f\u72fc\u6beb\uff08Weasel\uff09\u3002'))
            Write-DaMaoRedeployMessage ([regex]::Unescape('\u8bf7\u5148\u5b89\u88c5\u5c0f\u72fc\u6beb\uff0c\u7136\u540e\u91cd\u65b0\u8fd0\u884c\u201c\u5927\u732b\u4e94\u7b14 - \u91cd\u65b0\u90e8\u7f72\u201d\u3002'))
        }
        else {
            Write-DaMaoRedeployMessage ([regex]::Unescape('\u90e8\u7f72\u8fc7\u7a0b\u4e2d\u53d1\u751f\u9519\u8bef\u3002\u8bf7\u68c0\u67e5\u76f8\u5173\u4f9d\u8d56\u540e\u91cd\u8bd5\u3002'))
        }
        Write-DaMaoRedeployMessage
        Write-DaMaoRedeployMessage (([regex]::Unescape('\u9519\u8bef\u4ee3\u7801\uff1a')) + $errorCode)
        Write-DaMaoRedeployMessage
        $closePrompt = [regex]::Unescape('\u6309 Enter \u952e\u5173\u95ed\u6b64\u7a97\u53e3')
        if ([Console]::IsOutputRedirected) {
            [Console]::Out.Write($closePrompt)
            [void][Console]::In.ReadLine()
        }
        else {
            [void](Read-Host $closePrompt)
        }
        $Host.SetShouldExit(1)
        return
    }
    return
}

. (Join-Path $PSScriptRoot 'DaMao.Common.ps1')
if (-not [string]::IsNullOrWhiteSpace($InstallerStatePath)) {
    . (Join-Path $PSScriptRoot 'DaMao.InstallerState.ps1')
}

$resolvedUserDir = Get-DaMaoRimeUserDir -Override $RimeUserDir
$resolvedWeaselRoot = Get-DaMaoWeaselRoot -Override $WeaselRoot
$rimeOwnershipBefore = if (-not [string]::IsNullOrWhiteSpace($InstallerStatePath)) {
    Get-DaMaoRimeOwnershipSnapshot -RimeUserDir $resolvedUserDir
}
else {
    @{}
}

if (Test-DaMaoPathWithin -Path $resolvedUserDir -Parent $resolvedWeaselRoot) {
    throw 'The Rime user directory must not be inside the Weasel program directory.'
}

if (-not (Test-Path -LiteralPath $resolvedUserDir -PathType Container)) {
    if ($PSCmdlet.ShouldProcess($resolvedUserDir, 'Create Rime user directory')) {
        New-Item -ItemType Directory -Path $resolvedUserDir -Force | Out-Null
    }
}

$dependency = $null
if (-not [string]::IsNullOrWhiteSpace($WubiSourcePath)) {
    if ($PSCmdlet.ShouldProcess($WubiSourcePath, 'Install wubi86 dictionary from local official rime-wubi source')) {
        $dependency = Install-DaMaoWubiFromSource -SourcePath $WubiSourcePath -RimeUserDir $resolvedUserDir -Method local
    }
}
else {
    $dependency = Get-DaMaoDependencyFile -RimeUserDir $resolvedUserDir -WeaselRoot $resolvedWeaselRoot
}

if ($null -eq $dependency -and $InstallWubiDependency) {
    $installer = Join-Path $resolvedWeaselRoot 'rime-install.bat'
    $plumFailure = $null
    if (Test-Path -LiteralPath $installer -PathType Leaf) {
        if ($PSCmdlet.ShouldProcess('official Plum recipe: wubi', 'Install the official rime-wubi package')) {
            try {
                $plumOutput = (& $installer wubi 2>&1 | Out-String)
                $plumExitCode = $LASTEXITCODE
                $dependency = Get-DaMaoDependencyFile -RimeUserDir $resolvedUserDir -WeaselRoot $resolvedWeaselRoot
                if ($plumExitCode -ne 0 -or $null -eq $dependency) {
                    $plumFailure = "Plum exit code: $plumExitCode. $($plumOutput.Trim())"
                }
            }
            catch {
                $plumFailure = $_.Exception.Message
            }
        }
    }
    else {
        $plumFailure = "Weasel package installer was not found: $installer"
    }

    if ($null -eq $dependency -and $PSCmdlet.ShouldProcess('https://github.com/rime/rime-wubi.git', 'Clone the official repository as a Plum fallback')) {
        if (-not [string]::IsNullOrWhiteSpace($plumFailure)) {
            $plumSummary = $plumFailure.Trim()
            if ($plumSummary.Length -gt 1200) {
                $plumSummary = $plumSummary.Substring(0, 1200) + '...'
            }
            Write-Warning "[DM-PLUM-FAILED] Plum did not install wubi; trying the official GitHub repository. $plumSummary"
        }
        try {
            $dependency = Install-DaMaoWubiFromGitHub -RimeUserDir $resolvedUserDir
        }
        catch {
            $fallbackError = $_.Exception.Message
            if (-not [string]::IsNullOrWhiteSpace($plumFailure)) {
                throw "$fallbackError`n[DM-PLUM-FAILED] Plum could not install wubi. $plumFailure`nUse -WubiSourcePath <path> for a completely offline installation."
            }
            throw
        }
    }
}

if ($null -eq $dependency) {
    throw '[DM-WUBI-MISSING] The upstream wubi86 dictionary is missing. Use -InstallWubiDependency for Plum/GitHub installation, or -WubiSourcePath <path> for offline installation.'
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDirectory = Join-Path $resolvedUserDir "backup\damao-ime-config-$timestamp"
$repoRoot = Split-Path $PSScriptRoot -Parent
$formalSchemaDirectory = Join-Path $repoRoot 'schemas'
$sourceSchema = ConvertTo-DaMaoFullPath (Join-Path $repoRoot 'schemas\damao_wubi.schema.yaml')
$sourceSchemaIcon = ConvertTo-DaMaoFullPath (Join-Path $repoRoot 'assets\branding\windows\bigcat-ime.ico')
$diagnosticSchemaDirectory = Join-Path $formalSchemaDirectory 'diagnostics'
$targetSchema = Join-Path $resolvedUserDir 'damao_wubi.schema.yaml'
$targetSchemaIcon = Join-Path $resolvedUserDir 'damao_wubi\branding\bigcat-ime.ico'
$defaultCustom = Join-Path $resolvedUserDir 'default.custom.yaml'

if (-not (Test-Path -LiteralPath $sourceSchema -PathType Leaf)) {
    throw "[DM-INSTALL-SCHEMA-INVALID] Formal DaMao schema was not found: $sourceSchema"
}
if (Test-DaMaoPathWithin -Path $sourceSchema -Parent $diagnosticSchemaDirectory) {
    throw "[DM-INSTALL-SCHEMA-INVALID] The normal installer cannot use a diagnostic schema source: $sourceSchema"
}
Assert-DaMaoFormalSchemaFile -Path $sourceSchema -Context 'Formal schema source'
if (-not (Test-Path -LiteralPath $sourceSchemaIcon -PathType Leaf)) {
    throw "[DM-INSTALL-BRANDING-INVALID] Authoritative BigCat schema icon was not found: $sourceSchemaIcon"
}

$iconNeedsCopy = -not (Test-Path -LiteralPath $targetSchemaIcon -PathType Leaf)
if (-not $iconNeedsCopy) {
    $sourceIconHash = (Get-FileHash -LiteralPath $sourceSchemaIcon -Algorithm SHA256).Hash
    $targetIconHash = (Get-FileHash -LiteralPath $targetSchemaIcon -Algorithm SHA256).Hash
    $iconNeedsCopy = $sourceIconHash -ne $targetIconHash
}
if ($iconNeedsCopy -and $PSCmdlet.ShouldProcess($targetSchemaIcon, 'Install BigCat schema icon')) {
    $targetSchemaIconDirectory = Split-Path -Parent $targetSchemaIcon
    New-Item -ItemType Directory -Path $targetSchemaIconDirectory -Force | Out-Null
    Copy-Item -LiteralPath $sourceSchemaIcon -Destination $targetSchemaIcon -Force
}

$schemaNeedsCopy = $true
if (Test-Path -LiteralPath $targetSchema -PathType Leaf) {
    $sourceHash = (Get-FileHash -LiteralPath $sourceSchema -Algorithm SHA256).Hash
    $targetHash = (Get-FileHash -LiteralPath $targetSchema -Algorithm SHA256).Hash
    $schemaNeedsCopy = $sourceHash -ne $targetHash
}

$schemaWasCopied = $false
if ($schemaNeedsCopy -and $PSCmdlet.ShouldProcess($targetSchema, 'Install DaMao Input Method schema')) {
    if (Test-Path -LiteralPath $targetSchema -PathType Leaf) {
        New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
        Copy-Item -LiteralPath $targetSchema -Destination (Join-Path $backupDirectory 'damao_wubi.schema.yaml') -Force
    }
    Copy-Item -LiteralPath $sourceSchema -Destination $targetSchema -Force
    [System.IO.File]::SetLastWriteTimeUtc($targetSchema, [DateTime]::UtcNow)
    $schemaWasCopied = $true
}

$builtSchema = Join-Path $resolvedUserDir 'build\damao_wubi.schema.yaml'
$compiledSchemaNeedsRefresh = $schemaWasCopied
if (Test-Path -LiteralPath $builtSchema -PathType Leaf) {
    $builtSchemaContent = [System.IO.File]::ReadAllText($builtSchema)
    if (@(Get-DaMaoFormalSchemaContentFailures -Content $builtSchemaContent).Count -gt 0) {
        $compiledSchemaNeedsRefresh = $true
    }
}
if ($compiledSchemaNeedsRefresh -and
    (Test-Path -LiteralPath $builtSchema -PathType Leaf) -and
    $PSCmdlet.ShouldProcess($builtSchema, 'Invalidate stale compiled DaMao schema')) {
    Remove-Item -LiteralPath $builtSchema -Force
}

if ($PSCmdlet.ShouldProcess($defaultCustom, 'Add DaMao Input Method to the Rime schema list')) {
    [void](Add-DaMaoSchemaSelection -DefaultCustomPath $defaultCustom -BackupDirectory $backupDirectory `
        -PreferAsFirstSchema:$InitializeFreshRimeState)
}

if (-not [string]::IsNullOrWhiteSpace($InstallerStatePath)) {
    Update-DaMaoInstallerRimeOwnership -StatePath $InstallerStatePath `
        -RimeUserDir $resolvedUserDir -ExistedBefore $rimeOwnershipBefore
}

if (-not $SkipDeploy -and $PSCmdlet.ShouldProcess($resolvedWeaselRoot, 'Deploy Rime configuration')) {
    try {
        Invoke-DaMaoDeployer -WeaselRoot $resolvedWeaselRoot -Command '/deploy' -TimeoutSeconds 120
        Assert-DaMaoFormalDeployment -RimeUserDir $resolvedUserDir
    }
    catch {
        if ($_.Exception.Message -match '^\[DM-DEPLOY-(?:FAILED|TIMEOUT|BUSY)\]') {
            throw
        }
        throw "[DM-DEPLOY-FAILED] Rime deployment failed. $($_.Exception.Message)"
    }
}

[PSCustomObject]@{
    SchemaId = 'damao_wubi'
    RimeUserDir = $resolvedUserDir
    WeaselRoot = $resolvedWeaselRoot
    DictionaryDependency = $dependency
    SchemaSource = $sourceSchema
    SchemaIcon = $targetSchemaIcon
    FreshStateInitialized = [bool]$InitializeFreshRimeState
    InstallerStatePath = $InstallerStatePath
    Deployed = -not $SkipDeploy
}
