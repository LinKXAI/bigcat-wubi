[CmdletBinding()]
param(
    [string]$WubiDictionary = (Join-Path $env:APPDATA 'Rime\wubi86.dict.yaml')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-Alpha03 {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) { throw "[$Code] $Message" }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$stableSchemaPath = Join-Path $repoRoot 'schemas\damao_wubi.schema.yaml'
$pinyinSchemaPath = Join-Path $repoRoot 'schemas\damao_wubi_pinyin.schema.yaml'
$alpha03SchemaPath = Join-Path $repoRoot 'schemas\damao_wubi_alpha03.schema.yaml'
$installerPath = Join-Path $repoRoot 'scripts\Install-DaMao.ps1'
$runtimePath = Join-Path $PSScriptRoot 'Invoke-DaMaoAlpha03LearningRuntime.ps1'
$nativePath = Join-Path $PSScriptRoot 'DaMaoRimeAlpha03Native.cs'
$legacyFormalFilterPath = Join-Path $repoRoot 'lua\damao_adaptive_phrase_filter.lua'

foreach ($requiredPath in @($stableSchemaPath, $pinyinSchemaPath, $alpha03SchemaPath,
        $installerPath, $runtimePath, $nativePath)) {
    Assert-Alpha03 (Test-Path -LiteralPath $requiredPath -PathType Leaf) 'DM-A03-01' `
        "Required native-learning compatibility file is missing: $requiredPath"
}

$stableSchema = Get-Content -LiteralPath $stableSchemaPath -Raw -Encoding UTF8
$pinyinSchema = Get-Content -LiteralPath $pinyinSchemaPath -Raw -Encoding UTF8
Assert-Alpha03 ($stableSchema -match '(?m)^  schema_id: damao_wubi$') `
    'DM-A03-02' 'The installed schema identity changed.'
Assert-Alpha03 ($pinyinSchema -match '(?m)^  schema_id: damao_wubi_pinyin$') `
    'DM-A03-03' 'The excluded Pinyin schema identity changed.'

$schema = Get-Content -LiteralPath $alpha03SchemaPath -Raw -Encoding UTF8
$installer = Get-Content -LiteralPath $installerPath -Raw -Encoding UTF8

Assert-Alpha03 ($schema -match '(?m)^  schema_id: damao_wubi_alpha03$') 'DM-A03-04' `
    'The native-learning compatibility schema id changed.'
Assert-Alpha03 ($schema -match '(?ms)^translator:\r?\n(?:  .+\r?\n)*?  dictionary: wubi86\r?\n  user_dict: damao_wubi_alpha03\r?\n  enable_user_dict: true$') `
    'DM-A03-05' 'The compatibility schema must use wubi86 and its isolated user dictionary.'
Assert-Alpha03 ([regex]::Matches($schema, '(?m)^    - table_translator\s*$').Count -eq 1) `
    'DM-A03-06' 'The compatibility schema must contain exactly one native table translator.'
Assert-Alpha03 ($schema -notmatch 'table_translator@fixed|lua_filter@|damao_adaptive_phrase_filter|(?m)^fixed:') `
    'DM-A03-07' 'A retired fixed translator or Lua filter remains in Formal.'
Assert-Alpha03 ($schema -notmatch '(?m)^filters:\s*$') 'DM-A03-08' `
    'The single-translator Formal schema should not retain an unnecessary filter chain.'
Assert-Alpha03 ($schema -match '(?m)^  enable_sentence: false$' -and
    $schema -match '(?m)^  enable_encoder: true$' -and
    $schema -match '(?m)^  encode_commit_history: true$' -and
    $schema -match '(?m)^  max_phrase_length: 4$') 'DM-A03-09' `
    'The native-learning compatibility options are incomplete or unexpected.'
Assert-Alpha03 (-not (Test-Path -LiteralPath $legacyFormalFilterPath)) 'DM-A03-10' `
    'The retired Lua filter remains at its former Formal runtime path.'
Assert-Alpha03 ($installer -notmatch 'damao_wubi_alpha03|alpha-0\.3') 'DM-A03-11' `
    'The normal installer must not register the compatibility schema.'

$requiredInputPatterns = @(
    '(?m)^  max_code_length: 4$',
    '(?m)^  auto_select: true$',
    '(?m)^  delimiter: " ;''"$',
    '(?ms)^punctuator:\r?\n  import_preset: default\r?\n  digit_separators: "\."$',
    '(?m)^\s*- \{ when: composing, accept: Return, send: Escape \}$',
    '(?m)^\s*- \{ when: has_menu, accept: semicolon, send: 2 \}$',
    '(?m)^\s*- \{ when: has_menu, accept: apostrophe, send: 3 \}$',
    '(?m)^\s*- \{ when: has_menu, accept: period, send: period \}$'
)
foreach ($pattern in $requiredInputPatterns) {
    Assert-Alpha03 ($schema -match $pattern) 'DM-A03-12' `
        "The compatibility schema is missing a required input behavior: $pattern"
}

if (Test-Path -LiteralPath $WubiDictionary -PathType Leaf) {
    $dictionary = Get-Content -LiteralPath $WubiDictionary -Raw -Encoding UTF8
    foreach ($expectedRule in @(
            'length_equal:\s*2\s*\r?\n\s*formula:\s*"AaAbBaBb"',
            'length_equal:\s*3\s*\r?\n\s*formula:\s*"AaBaCaCb"',
            'length_in_range:\s*\[4,\s*10\]\s*\r?\n\s*formula:\s*"AaBaCaZa"')) {
        Assert-Alpha03 ($dictionary -match $expectedRule) 'DM-A03-13' `
            "wubi86 is missing an encoder rule: $expectedRule"
    }
}
else {
    Write-Warning "wubi86 encoder rules were not checked because the external dictionary is absent: $WubiDictionary"
}

Write-Host 'DaMao native-learning compatibility static tests passed.'
