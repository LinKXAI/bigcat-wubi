[CmdletBinding()]
param(
    [string]$RimeUserDir,
    [string]$WeaselRoot,
    [switch]$RequireUserDictionary
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'DaMao.Common.ps1')

$checks = [System.Collections.Generic.List[object]]::new()
function Add-Check {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Passed,
        [Parameter(Mandatory = $true)][string]$Detail,
        [bool]$Required = $true
    )

    $checks.Add([PSCustomObject]@{
        Check = $Name
        Passed = $Passed
        Required = $Required
        Detail = $Detail
    })
}

$damaoDisplayName = -join @([char]0x5927, [char]0x732b, [char]0x8f93, [char]0x5165, [char]0x6cd5)
$legacyProjectSchemaId = 'modern' + '_' + 'wubi'
$repoRoot = Split-Path $PSScriptRoot -Parent
$formalSchemaSource = Join-Path $repoRoot 'schemas\damao_wubi.schema.yaml'

$isWindows11 = [Environment]::OSVersion.Version.Build -ge 22000
Add-Check -Name 'Windows 11' -Passed $isWindows11 -Detail ([Environment]::OSVersion.VersionString)

$resolvedWeaselRoot = $null
try {
    $resolvedWeaselRoot = Get-DaMaoWeaselRoot -Override $WeaselRoot
    Add-Check -Name 'Weasel installation' -Passed $true -Detail $resolvedWeaselRoot
}
catch {
    Add-Check -Name 'Weasel installation' -Passed $false -Detail $_.Exception.Message
}

$resolvedUserDir = Get-DaMaoRimeUserDir -Override $RimeUserDir
$userDirExists = Test-Path -LiteralPath $resolvedUserDir -PathType Container
Add-Check -Name 'Rime user directory' -Passed $userDirExists -Detail $resolvedUserDir

$directoriesSeparated = $false
$separationDetail = "Program directory unavailable | User: $resolvedUserDir"
if ($null -ne $resolvedWeaselRoot) {
    $directoriesSeparated = -not (Test-DaMaoPathWithin -Path $resolvedUserDir -Parent $resolvedWeaselRoot)
    $separationDetail = "Program: $resolvedWeaselRoot | User: $resolvedUserDir"
}
Add-Check -Name 'Program/user directory separation' -Passed $directoriesSeparated -Detail $separationDetail

$dependency = $null
if ($null -ne $resolvedWeaselRoot) {
    $dependency = Get-DaMaoDependencyFile -RimeUserDir $resolvedUserDir -WeaselRoot $resolvedWeaselRoot
}
else {
    $userDictionaryDependency = Join-Path $resolvedUserDir 'wubi86.dict.yaml'
    if (Test-DaMaoDictionaryFile -Path $userDictionaryDependency) {
        $dependency = $userDictionaryDependency
    }
}
Add-Check -Name 'wubi86.dict.yaml' -Passed ($null -ne $dependency) -Detail $(if ($null -ne $dependency) { $dependency } else { 'Not found' })

$formalSourceExists = Test-Path -LiteralPath $formalSchemaSource -PathType Leaf
Add-Check -Name 'Formal schema source' -Passed $formalSourceExists -Detail $formalSchemaSource

$schemaPath = Join-Path $resolvedUserDir 'damao_wubi.schema.yaml'
$schemaExists = Test-Path -LiteralPath $schemaPath -PathType Leaf
Add-Check -Name 'Installed damao_wubi.schema.yaml' -Passed $schemaExists -Detail $schemaPath

$installedMatchesFormal = $false
if ($formalSourceExists -and $schemaExists) {
    $formalHash = (Get-FileHash -LiteralPath $formalSchemaSource -Algorithm SHA256).Hash
    $installedHash = (Get-FileHash -LiteralPath $schemaPath -Algorithm SHA256).Hash
    $installedMatchesFormal = [string]::Equals($formalHash, $installedHash, [System.StringComparison]::Ordinal)
}
Add-Check -Name 'Installed schema matches formal source' -Passed $installedMatchesFormal -Detail 'Repository formal schema and Rime user schema SHA-256 must match'

$defaultCustomPath = Join-Path $resolvedUserDir 'default.custom.yaml'
$damaoRegistered = Test-DaMaoSchemaRegistered -DefaultCustomPath $defaultCustomPath -SchemaId 'damao_wubi'
$legacyRegistered = Test-DaMaoSchemaRegistered -DefaultCustomPath $defaultCustomPath -SchemaId $legacyProjectSchemaId
Add-Check -Name 'default.custom.yaml registers damao_wubi' -Passed $damaoRegistered -Detail $defaultCustomPath
Add-Check -Name 'Old development schema is not registered' -Passed (-not $legacyRegistered) -Detail $defaultCustomPath

$builtDefaultPath = Join-Path $resolvedUserDir 'build\default.yaml'
$builtDefaultExists = Test-Path -LiteralPath $builtDefaultPath -PathType Leaf
$builtDefaultRegistersDamao = $false
if ($builtDefaultExists) {
    $builtDefaultContent = [System.IO.File]::ReadAllText($builtDefaultPath)
    $builtDefaultRegistersDamao = $builtDefaultContent -match '(?m)^\s*-\s*schema:\s*["'']?damao_wubi["'']?\s*(?:#.*)?$'
}
Add-Check -Name 'build\default.yaml registers damao_wubi' -Passed $builtDefaultRegistersDamao -Detail $builtDefaultPath

$builtSchemaPath = Join-Path $resolvedUserDir 'build\damao_wubi.schema.yaml'
$builtSchemaExists = Test-Path -LiteralPath $builtSchemaPath -PathType Leaf
Add-Check -Name 'Compiled damao_wubi.schema.yaml' -Passed $builtSchemaExists -Detail $builtSchemaPath

$builtSchemaContent = if ($builtSchemaExists) { [System.IO.File]::ReadAllText($builtSchemaPath) } else { '' }
$displayNamePattern = '(?m)^\s*name:\s*["'']?{0}["'']?\s*$' -f [regex]::Escape($damaoDisplayName)
Add-Check -Name 'Compiled schema_id is damao_wubi' -Passed ($builtSchemaExists -and $builtSchemaContent -match '(?m)^\s*schema_id:\s*["'']?damao_wubi["'']?\s*$') -Detail $builtSchemaPath
Add-Check -Name 'Compiled schema name is formal' -Passed ($builtSchemaExists -and $builtSchemaContent -match $displayNamePattern) -Detail $damaoDisplayName
Add-Check -Name 'Compiled schema name is not diagnostic' -Passed ($builtSchemaExists -and $builtSchemaContent -notmatch '(?im)^\s*name\s*:.*Diagnostic') -Detail 'Formal schema name must not contain Diagnostic'
Add-Check -Name 'Compiled dictionary is wubi86' -Passed ($builtSchemaExists -and $builtSchemaContent -match '(?m)^\s*dictionary:\s*["'']?wubi86["'']?\s*$') -Detail $builtSchemaPath
Add-Check -Name 'Compiled max_code_length is 4' -Passed ($builtSchemaExists -and $builtSchemaContent -match '(?m)^\s*max_code_length:\s*4\s*$') -Detail $builtSchemaPath
Add-Check -Name 'Compiled auto_select is true' -Passed ($builtSchemaExists -and $builtSchemaContent -match '(?m)^\s*auto_select:\s*true\s*$') -Detail $builtSchemaPath
Add-Check -Name 'auto_select_unique_candidate is absent' -Passed ($builtSchemaExists -and $builtSchemaContent -notmatch '(?m)^\s*auto_select_unique_candidate\s*:') -Detail $builtSchemaPath

$userDbPresent = (Test-Path -LiteralPath (Join-Path $resolvedUserDir 'damao_wubi.userdb') -PathType Container) -or
    (Test-Path -LiteralPath (Join-Path $resolvedUserDir 'damao_wubi.userdb.kct') -PathType Leaf) -or
    ($null -ne (Get-ChildItem -LiteralPath (Join-Path $resolvedUserDir 'sync') -Recurse -File -Filter 'damao_wubi.userdb.txt' -ErrorAction SilentlyContinue | Select-Object -First 1))
Add-Check -Name 'DaMao user dictionary' -Passed $userDbPresent -Detail $(if ($userDbPresent) { 'Local database or sync snapshot found' } else { 'Use the schema and select a candidate first' }) -Required ([bool]$RequireUserDictionary)

foreach ($check in $checks) {
    $status = if ($check.Passed) { 'PASS' } else { 'FAIL' }
    $requirement = if ($check.Required) { '' } else { ' (optional)' }
    Write-Host ("{0} {1}{2} - {3}" -f $status, $check.Check, $requirement, $check.Detail)
}

$failedRequired = @($checks | Where-Object { $_.Required -and -not $_.Passed })
if ($failedRequired.Count -gt 0) {
    $failedNames = ($failedRequired | ForEach-Object { $_.Check }) -join ', '
    Write-Host 'Result: failure'
    Write-Error "[DM-SMOKE-FAILED] $($failedRequired.Count) required environment check(s) failed: $failedNames" -ErrorAction Continue
    exit 1
}

Write-Host 'Result: success'
