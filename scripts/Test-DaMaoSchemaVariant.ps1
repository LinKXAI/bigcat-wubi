[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet(
        '00-minimal',
        '01-speller',
        '01a-code-length',
        '01b-delimiter-length',
        '01c-four-code-pattern',
        '02-group2-all',
        '02a-recognizer',
        '02b-switches',
        '02c-uniquifier',
        '03-group3-all',
        '03a-user-dictionary',
        '03b-translator-options',
        '04-full-alpha'
    )]
    [string]$Variant,
    [string]$RimeUserDir,
    [string]$WeaselRoot
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'DaMao.Common.ps1')

$resolvedUserDir = Get-DaMaoRimeUserDir -Override $RimeUserDir
$resolvedWeaselRoot = Get-DaMaoWeaselRoot -Override $WeaselRoot

if (Test-DaMaoPathWithin -Path $resolvedUserDir -Parent $resolvedWeaselRoot) {
    throw '[DM-DIAG-INVALID-ENVIRONMENT] The Rime user directory must not be inside the Weasel program directory.'
}

$dependency = Get-DaMaoDependencyFile -RimeUserDir $resolvedUserDir -WeaselRoot $resolvedWeaselRoot
if ($null -eq $dependency) {
    throw '[DM-DIAG-WUBI-MISSING] The existing wubi86.dict.yaml dependency was not found. Run the normal installer first.'
}

$defaultCustom = Join-Path $resolvedUserDir 'default.custom.yaml'
$schemaRegistered = Test-DaMaoSchemaRegistered -DefaultCustomPath $defaultCustom -SchemaId 'damao_wubi'
Write-Host "Diagnostic script: $PSCommandPath"
Write-Host "Schema registration check: Path=$defaultCustom Schema=damao_wubi Registered=$schemaRegistered"
if (-not $schemaRegistered) {
    throw "[DM-DIAG-SCHEMA-NOT-REGISTERED] default.custom.yaml does not register damao_wubi: $defaultCustom. Run the normal installer first; this diagnostic does not modify schema_list."
}

Assert-DaMaoDeployerAvailable

$repoRoot = Split-Path $PSScriptRoot -Parent
$isFullAlpha = $Variant -eq '04-full-alpha'
$sourceSchema = if ($isFullAlpha) {
    Join-Path $repoRoot 'schemas\damao_wubi.schema.yaml'
}
else {
    Join-Path $repoRoot "schemas\diagnostics\damao_wubi.$Variant.schema.yaml"
}
if (-not (Test-Path -LiteralPath $sourceSchema -PathType Leaf)) {
    throw "[DM-DIAG-VARIANT-NOT-FOUND] Diagnostic schema was not found: $sourceSchema"
}

$sourceContent = [System.IO.File]::ReadAllText($sourceSchema)
$installContent = if ($isFullAlpha) {
    ConvertTo-DaMaoFullAlphaDiagnosticSchema -SchemaContent $sourceContent
}
else {
    $sourceContent
}
if ($installContent -notmatch '(?m)^\s*schema_id:\s*damao_wubi\s*$' -or
    $installContent -notmatch '(?m)^\s*dictionary:\s*wubi86\s*$') {
    throw "[DM-DIAG-VARIANT-INVALID] Variant '$Variant' must use schema_id damao_wubi and dictionary wubi86."
}
$expectedVersionPattern = if ($Variant -eq '00-minimal') {
    '0\.1'
}
elseif ($isFullAlpha) {
    '0\.1-diag-04'
}
else {
    '0\.1-diag-[a-z0-9-]+'
}
$versionPattern = '(?m)^\s*version:\s*["'']?(?<version>{0})["'']?\s*$' -f $expectedVersionPattern
$versionMatch = [regex]::Match($installContent, $versionPattern)
if (-not $versionMatch.Success) {
    throw "[DM-DIAG-VARIANT-INVALID] Variant '$Variant' does not have a diagnostic version marker."
}
$nameMatch = [regex]::Match($installContent, '(?m)^\s*name:\s*"(?<name>[^"]+)"\s*$')
if (-not $nameMatch.Success) {
    throw "[DM-DIAG-VARIANT-INVALID] Variant '$Variant' does not have a recognizable schema name."
}

$targetSchema = Join-Path $resolvedUserDir 'damao_wubi.schema.yaml'
$builtSchema = Join-Path $resolvedUserDir 'build\damao_wubi.schema.yaml'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmssfff'
$backupDirectory = Join-Path $resolvedUserDir "backup\damao-ime-diagnostics-$timestamp-$Variant"
New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
$hadOriginalSchema = Test-Path -LiteralPath $targetSchema -PathType Leaf
if ($hadOriginalSchema) {
    Copy-Item -LiteralPath $targetSchema -Destination (Join-Path $backupDirectory 'damao_wubi.schema.yaml') -Force
}

try {
    if ($isFullAlpha) {
        Write-DaMaoUtf8File -Path $targetSchema -Content $installContent
    }
    else {
        Copy-Item -LiteralPath $sourceSchema -Destination $targetSchema -Force
    }
    [System.IO.File]::SetLastWriteTimeUtc($targetSchema, [DateTime]::UtcNow)
    if (Test-Path -LiteralPath $builtSchema -PathType Leaf) {
        Remove-Item -LiteralPath $builtSchema -Force
    }

    Write-Host "Installed diagnostic variant '$Variant'."
    Write-Host "Schema backup: $backupDirectory"
    Write-Host 'Invalidated build\damao_wubi.schema.yaml to force a fresh diagnostic build.'
    Write-Host 'Deploying with the existing wubi86 dictionary; timeout is 120 seconds...'

    $rimeLogSnapshot = Get-DaMaoRimeLogSnapshot
    Invoke-DaMaoDeployer -WeaselRoot $resolvedWeaselRoot -Command '/deploy' -TimeoutSeconds 120
    $deploymentLog = Assert-DaMaoWorkspaceDeploymentLog -BeforeSnapshot $rimeLogSnapshot -SchemaId 'damao_wubi'
    Assert-DaMaoDeployment -RimeUserDir $resolvedUserDir

    $builtContent = [System.IO.File]::ReadAllText($builtSchema)
    $expectedName = $nameMatch.Groups['name'].Value
    if (-not $builtContent.Contains($expectedName)) {
        $latestLog = Get-DaMaoLatestRimeLogPath
        throw "[DM-DEPLOY-FAILED] Deployment completed, but the built schema does not contain diagnostic name '$expectedName'. The build may be stale: $builtSchema. Latest Rime log location: $latestLog"
    }
    Write-Host "Verified workspace/schema deployment log: $deploymentLog"
}
catch {
    $deploymentFailure = $_
    try {
        if ($hadOriginalSchema) {
            Copy-Item -LiteralPath (Join-Path $backupDirectory 'damao_wubi.schema.yaml') -Destination $targetSchema -Force
            [System.IO.File]::SetLastWriteTimeUtc($targetSchema, [DateTime]::UtcNow)
        }
        elseif (Test-Path -LiteralPath $targetSchema -PathType Leaf) {
            Remove-Item -LiteralPath $targetSchema -Force
        }
        if (Test-Path -LiteralPath $builtSchema -PathType Leaf) {
            Remove-Item -LiteralPath $builtSchema -Force
        }
    }
    catch {
        throw "[DM-DIAG-RESTORE-FAILED] Diagnostic deployment failed and the original schema could not be restored. Backup: $backupDirectory. Deployment error: $($deploymentFailure.Exception.Message). Restore error: $($_.Exception.Message)"
    }
    Write-Warning "Diagnostic variant '$Variant' failed; restored the schema that was present before this test and invalidated its compiled schema."
    throw $deploymentFailure
}

[PSCustomObject]@{
    Variant = $Variant
    Result = 'success'
    Dictionary = $dependency
    InstalledSchema = $targetSchema
    BuiltSchema = $builtSchema
    DeploymentLog = $deploymentLog
    BackupDirectory = $backupDirectory
}
