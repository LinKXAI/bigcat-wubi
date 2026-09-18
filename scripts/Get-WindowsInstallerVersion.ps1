[CmdletBinding()]
param(
    [string]$VersionPath
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($VersionPath)) {
    $VersionPath = Join-Path $PSScriptRoot '..\installer\windows\VERSION'
}
$definitions = @{}
foreach ($line in ([System.IO.File]::ReadAllText($VersionPath) -split '\r?\n')) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    if ($line -cnotmatch '^#define (MyAppReleaseTag|MyAppVersion|MyAppNumericVersion) "([^"\r\n]+)"$') {
        throw '[DM-INNO-VERSION-INVALID] VERSION must contain only the three literal public version definitions.'
    }
    $name = $Matches[1]
    $value = $Matches[2]
    if ($definitions.ContainsKey($name)) {
        throw "[DM-INNO-VERSION-INVALID] Duplicate definition: $name"
    }
    $definitions[$name] = $value
}
if ($definitions.Count -ne 3) {
    throw '[DM-INNO-VERSION-INVALID] VERSION must define the release tag, display version, and numeric version.'
}

$tag = [regex]::Match($definitions.MyAppReleaseTag,
    '^v(?<base>(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*))(?:-rc(?<rc>[1-9][0-9]*))?$')
if (-not $tag.Success) {
    throw '[DM-INNO-VERSION-INVALID] Release tag must be vMAJOR.MINOR.PATCH or vMAJOR.MINOR.PATCH-rcN.'
}
$baseVersion = $tag.Groups['base'].Value
$expectedDisplayVersion = $baseVersion
if ($tag.Groups['rc'].Success) {
    $expectedDisplayVersion += ' RC' + $tag.Groups['rc'].Value
}
if ($definitions.MyAppVersion -cne $expectedDisplayVersion -or
    $definitions.MyAppNumericVersion -cne ($baseVersion + '.0')) {
    throw '[DM-INNO-VERSION-INVALID] Release tag, display version, and numeric Windows version must agree.'
}
foreach ($component in ($definitions.MyAppNumericVersion -split '\.')) {
    $numericComponent = [uint16]0
    if (-not [uint16]::TryParse($component, [ref]$numericComponent)) {
        throw '[DM-INNO-VERSION-INVALID] Windows version components must be in the range 0..65535.'
    }
}

[pscustomobject][ordered]@{
    ReleaseTag = $definitions.MyAppReleaseTag
    DisplayVersion = $definitions.MyAppVersion
    NumericVersion = $definitions.MyAppNumericVersion
}
