[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-PunctuationRegression {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw "[$Code] $Message"
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$schemaPaths = @(
    (Join-Path $repoRoot 'schemas\damao_wubi.schema.yaml'),
    (Join-Path $repoRoot 'schemas\damao_wubi_pinyin.schema.yaml'),
    (Join-Path $repoRoot 'schemas\damao_wubi_alpha03.schema.yaml')
)

foreach ($schemaPath in $schemaPaths) {
    $schema = [System.IO.File]::ReadAllText($schemaPath)
    $schemaName = Split-Path -Leaf $schemaPath
    $processorMatch = [regex]::Match($schema, '(?ms)^  processors:\r?\n(?<items>(?:    - [^\r\n]+\r?\n)+)')
    $processors = if ($processorMatch.Success) {
        @([regex]::Matches($processorMatch.Groups['items'].Value, '(?m)^\s*-\s*(?<name>\S+)\s*$') | ForEach-Object { $_.Groups['name'].Value })
    }
    else { @() }
    $keyBinderMatch = [regex]::Match($schema, '(?ms)^key_binder:\r?\n(?<body>.*?)(?=^[A-Za-z_][A-Za-z0-9_]*:\s*$|\z)')
    $keyBinder = if ($keyBinderMatch.Success) { $keyBinderMatch.Groups['body'].Value } else { '' }

    Assert-PunctuationRegression (
        $processors -contains 'punctuator' -and
        $schema -match '(?ms)^punctuator:\s*\r?\n\s+import_preset:\s*default\s*$' -and
        $schema -match '(?m)^\s*digit_separators:\s*"\."\s*$' -and
        $schema -notmatch '(?m)^\s*digit_separator_action\s*:' -and
        $keyBinder -notmatch '(?m)accept:\s*comma\b'
    ) 'DM-R-PUNCT-01' "$schemaName must leave comma to the default punctuator so a candidate commits before the Chinese comma."

    $periodBindings = @([regex]::Matches($keyBinder, '(?m)^\s*-\s*\{[^\r\n]*when:\s*has_menu[^\r\n]*accept:\s*period[^\r\n]*\}\s*$'))
    Assert-PunctuationRegression (
        $periodBindings.Count -eq 1 -and
        $periodBindings[0].Value -match 'send:\s*period\b' -and
        $keyBinder -notmatch '(?m)accept:\s*period[^\r\n]*send:\s*Page_Down\b'
    ) 'DM-R-PUNCT-02' "$schemaName must override inherited period paging with has_menu period -> period."

    foreach ($code in [char[]]'abcdefghijklmnopqrstuvwxyz') {
        Assert-PunctuationRegression (
            $periodBindings.Count -eq 1 -and
            $periodBindings[0].Value -match 'when:\s*has_menu\b' -and
            $periodBindings[0].Value -match 'send:\s*period\b'
        ) 'DM-R-PUNCT-03' "$schemaName leaves period paging active for the single-letter candidate code '$code'."
    }

    Assert-PunctuationRegression (
        $schema -match '(?m)^\s*max_code_length:\s*4\s*$' -and
        $schema -match '(?m)^\s*auto_select:\s*true\s*$' -and
        $schema -notmatch '(?m)^\s*auto_select_unique_candidate\s*:' -and
        $keyBinder -match '(?m)accept:\s*Return,\s*send:\s*Escape\b' -and
        $keyBinder -match '(?m)accept:\s*semicolon,\s*send:\s*2\b' -and
        $keyBinder -match '(?m)accept:\s*apostrophe,\s*send:\s*3\b'
    ) 'DM-R-PUNCT-03' "$schemaName changed a protected input behavior while fixing period paging."
}

Write-Host 'DaMao punctuation regression tests passed (DM-R-PUNCT-01/02/03).'
