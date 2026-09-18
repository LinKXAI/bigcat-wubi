[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$failures = [System.Collections.Generic.List[string]]::new()
$damaoDisplayName = -join @([char]0x5927, [char]0x732b, [char]0x8f93, [char]0x5165, [char]0x6cd5)
$legacyProjectSchemaId = 'modern' + '_' + 'wubi'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        $failures.Add($Message)
    }
}

$powershellFiles = @(
    Get-ChildItem -LiteralPath (Join-Path $repoRoot 'scripts') -File -Filter '*.ps1'
    Get-ChildItem -LiteralPath (Join-Path $repoRoot 'tests') -File -Filter '*.ps1'
)
$powershellFiles | ForEach-Object {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors)
    foreach ($parseError in $errors) {
        $failures.Add("PowerShell parse error in $($_.Name): $($parseError.Message)")
    }
}

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "damao-ime-tests-$([Guid]::NewGuid().ToString('N'))"
try {
    . (Join-Path $repoRoot 'scripts\DaMao.Common.ps1')
    $defaultUserDir = Get-DaMaoRimeUserDir
    Assert-True -Condition (-not [string]::IsNullOrWhiteSpace($defaultUserDir)) -Message 'Default Rime user directory resolution failed.'

    $fakeWeaselRoot = Join-Path $testRoot 'program\weasel-0.0.0'
    $fakeUserDir = Join-Path $testRoot 'user\Rime'
    $fakeWubiSource = Join-Path $testRoot 'source\rime-wubi'
    New-Item -ItemType Directory -Path $fakeWeaselRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $fakeUserDir -Force | Out-Null
    New-Item -ItemType Directory -Path $fakeWubiSource -Force | Out-Null
    $wubiDictionaryContent = "# Rime dictionary: wubi86`n---`nname: wubi86`ncolumns:`n  - text`n  - code`n...`n" + [char]0x5DE5 + "`ta`n"
    $wubiReadmeContent = '# ' + (-join @([char]0x4E94, [char]0x7B14, [char]0x5B57, [char]0x578B)) + [char]0x000A
    $wubiDictionarySuffixCodePoints = @($wubiDictionaryContent.Substring($wubiDictionaryContent.Length - 4).ToCharArray() | ForEach-Object { [int]$_ })
    $wubiReadmeCodePoints = @($wubiReadmeContent.ToCharArray() | ForEach-Object { [int]$_ })
    Assert-True -Condition (($wubiDictionarySuffixCodePoints -join ',') -eq ((0x5DE5, 0x0009, 0x0061, 0x000A) -join ',')) -Message 'The ASCII-safe dictionary fixture did not preserve its intended Unicode, tab, and newline code points.'
    Assert-True -Condition (($wubiReadmeCodePoints -join ',') -eq ((0x0023, 0x0020, 0x4E94, 0x7B14, 0x5B57, 0x578B, 0x000A) -join ',')) -Message 'The ASCII-safe README fixture did not preserve its intended Unicode and newline code points.'
    [System.IO.File]::WriteAllText((Join-Path $fakeWeaselRoot 'WeaselDeployer.exe'), '')
    $wubiDictionaryPath = Join-Path $fakeWubiSource 'wubi86.dict.yaml'
    [System.IO.File]::WriteAllText($wubiDictionaryPath, $wubiDictionaryContent)
    [System.IO.File]::WriteAllText((Join-Path $fakeWubiSource 'wubi86.schema.yaml'), "schema:`n  schema_id: wubi86`ntranslator:`n  dictionary: wubi86`n")
    $wubiReadmePath = Join-Path $fakeWubiSource 'README.md'
    [System.IO.File]::WriteAllText($wubiReadmePath, $wubiReadmeContent)
    [System.IO.File]::WriteAllText((Join-Path $fakeWubiSource 'LICENSE'), "GNU LESSER GENERAL PUBLIC LICENSE`nVersion 3`n")
    Assert-True -Condition ([System.IO.File]::ReadAllText($wubiDictionaryPath) -ceq $wubiDictionaryContent) -Message 'The generated dictionary fixture text changed after ASCII-safe source construction.'
    Assert-True -Condition ([System.IO.File]::ReadAllText($wubiReadmePath) -ceq $wubiReadmeContent) -Message 'The generated README fixture text changed after ASCII-safe source construction.'
    Assert-True -Condition ([System.BitConverter]::ToString([System.IO.File]::ReadAllBytes($wubiDictionaryPath)) -ceq [System.BitConverter]::ToString([System.Text.Encoding]::UTF8.GetBytes($wubiDictionaryContent))) -Message 'The generated dictionary fixture UTF-8 bytes changed after ASCII-safe source construction.'
    Assert-True -Condition ([System.BitConverter]::ToString([System.IO.File]::ReadAllBytes($wubiReadmePath)) -ceq [System.BitConverter]::ToString([System.Text.Encoding]::UTF8.GetBytes($wubiReadmeContent))) -Message 'The generated README fixture UTF-8 bytes changed after ASCII-safe source construction.'

    $registrationCases = @(
        [PSCustomObject]@{
            Name = 'current-after-old-id-and-blank-line'
            Content = "patch:`n  `"schema_list/+`":`n    - schema: $legacyProjectSchemaId`n`n    - schema: damao_wubi`n"
            Expected = $true
        },
        [PSCustomObject]@{
            Name = 'current-before-other-schema'
            Content = "patch:`n  `"schema_list/+`":`n    - schema: damao_wubi`n    - schema: other_schema`n"
            Expected = $true
        },
        [PSCustomObject]@{
            Name = 'current-between-other-schemas'
            Content = "patch:`n  `"schema_list/+`":`n    - schema: first_schema`n    - schema: damao_wubi`n    - schema: last_schema`n"
            Expected = $true
        },
        [PSCustomObject]@{
            Name = 'current-absent'
            Content = "patch:`n  `"schema_list/+`":`n    - schema: old_schema`n    - schema: other_schema`n"
            Expected = $false
        },
        [PSCustomObject]@{
            Name = 'current-in-explicit-list'
            Content = "patch:`n  schema_list:`n    - schema: luna_pinyin`n    - schema: damao_wubi`n"
            Expected = $true
        },
        [PSCustomObject]@{
            Name = 'current-in-switcher-and-append-flow-lists'
            Content = "patch:`n  schema_list:`n    - {schema: luna_pinyin}`n  `"schema_list/+`":`n    - {schema: damao_wubi}`n"
            Expected = $true
        },
        [PSCustomObject]@{
            Name = 'current-in-next-operation'
            Content = "patch:`n  `"schema_list/@next`": { schema: damao_wubi }`n"
            Expected = $true
        },
        [PSCustomObject]@{
            Name = 'current-in-fresh-prepend-operation'
            Content = "patch:`n  `"schema_list/@before 0`": { schema: damao_wubi }`n"
            Expected = $true
        }
    )
    foreach ($registrationCase in $registrationCases) {
        $registrationPath = Join-Path $testRoot "registration\$($registrationCase.Name)\default.custom.yaml"
        New-Item -ItemType Directory -Path (Split-Path -Parent $registrationPath) -Force | Out-Null
        [System.IO.File]::WriteAllText($registrationPath, $registrationCase.Content)
        $registered = Test-DaMaoSchemaRegistered -DefaultCustomPath $registrationPath -SchemaId 'damao_wubi'
        Assert-True -Condition ($registered -eq $registrationCase.Expected) -Message "Registration case '$($registrationCase.Name)' returned $registered instead of $($registrationCase.Expected)."
    }

    # Exercise the complete diagnostic script with the real two-entry shape,
    # not only the Common helper. It must pass registration and fail later at
    # the intentionally invalid fake deployer without changing schema_list.
    $diagnosticRegistrationUserDir = Join-Path $testRoot 'diagnostic-registration\Rime'
    New-Item -ItemType Directory -Path $diagnosticRegistrationUserDir -Force | Out-Null
    $diagnosticRegistrationConfig = Join-Path $diagnosticRegistrationUserDir 'default.custom.yaml'
    $diagnosticRegistrationContent = $registrationCases[0].Content
    [System.IO.File]::WriteAllText($diagnosticRegistrationConfig, $diagnosticRegistrationContent)
    Copy-Item -LiteralPath (Join-Path $fakeWubiSource 'wubi86.dict.yaml') -Destination $diagnosticRegistrationUserDir -Force
    $diagnosticRegistrationError = $null
    try {
        & (Join-Path $repoRoot 'scripts\Test-DaMaoSchemaVariant.ps1') -Variant '00-minimal' -RimeUserDir $diagnosticRegistrationUserDir -WeaselRoot $fakeWeaselRoot | Out-Null
    }
    catch {
        $diagnosticRegistrationError = $_.Exception.Message
    }
    Assert-True -Condition ($diagnosticRegistrationError -notmatch '^\[DM-DIAG-SCHEMA-NOT-REGISTERED\]') -Message 'The complete diagnostic script rejected damao_wubi when it followed another schema_list/+ entry.'
    Assert-True -Condition ($diagnosticRegistrationError -match '^\[DM-DEPLOY-FAILED\]') -Message 'The complete diagnostic registration regression did not continue through the registration guard to the expected fake deployment failure.'
    Assert-True -Condition ([System.IO.File]::ReadAllText($diagnosticRegistrationConfig) -ceq $diagnosticRegistrationContent) -Message 'The diagnostic script modified schema_list while checking registration.'

    $installScript = Join-Path $repoRoot 'scripts\Install-DaMao.ps1'
    $switcherCustomization = @'
customization:
  distribution_code_name: Weasel
  distribution_version: 0.17.4
  generator: "Rime::SwitcherSettings"
  modified_time: "Sat Aug  8 01:21:34 2026"
  rime_version: 1.13.1
'@
    $mergeCases = @(
        [PSCustomObject]@{
            Name = 'missing'
            CreateFile = $false
            InitialContent = $null
            ExpectedFragments = @('patch:', 'schema_list/+', 'schema: damao_wubi')
            ExpectedListKind = 'plus'
            Modified = $true
        },
        [PSCustomObject]@{
            Name = 'empty'
            CreateFile = $true
            InitialContent = ''
            ExpectedFragments = @('patch:', 'schema_list/+', 'schema: damao_wubi')
            ExpectedListKind = 'plus'
            Modified = $true
        },
        [PSCustomObject]@{
            Name = 'customization-only'
            CreateFile = $true
            InitialContent = "customization:`n  distribution_code_name: Weasel`n  distribution_version: 0.17.4`n"
            ExpectedFragments = @('customization:', 'distribution_version: 0.17.4', 'patch:', 'schema_list/+', 'schema: damao_wubi')
            ExpectedListKind = 'plus'
            Modified = $true
        },
        [PSCustomObject]@{
            Name = 'patch-without-schema-list'
            CreateFile = $true
            InitialContent = "patch:`n  `"menu/page_size`": 9`n"
            ExpectedFragments = @('menu/page_size', 'schema_list/+', 'schema: damao_wubi')
            ExpectedListKind = 'plus'
            Modified = $true
        },
        [PSCustomObject]@{
            Name = 'existing-schema-list'
            CreateFile = $true
            InitialContent = "patch:`n  schema_list:`n    - schema: luna_pinyin`n    - schema: double_pinyin`n  `"menu/page_size`": 9`n"
            ExpectedFragments = @('schema: luna_pinyin', 'schema: double_pinyin', 'schema: damao_wubi', 'menu/page_size')
            ExpectedListKind = 'explicit'
            Modified = $true
        },
        [PSCustomObject]@{
            Name = 'damao-ime-already-present'
            CreateFile = $true
            InitialContent = "patch:`n  schema_list:`n    - schema: luna_pinyin`n    - schema: damao_wubi`n"
            ExpectedFragments = @('schema: luna_pinyin', 'schema: damao_wubi')
            ExpectedListKind = 'explicit'
            Modified = $false
        },
        [PSCustomObject]@{
            Name = 'existing-plus-list'
            CreateFile = $true
            InitialContent = @'
patch:
  "schema_list/+":
    - schema: terra_pinyin
'@
            ExpectedFragments = @('schema_list/+', 'schema: terra_pinyin', 'schema: damao_wubi')
            ExpectedListKind = 'plus'
            Modified = $true
        },
        [PSCustomObject]@{
            Name = 'damao-ime-plus-already-present'
            CreateFile = $true
            InitialContent = @'
patch:
  "schema_list/+":
    - schema: luna_pinyin
    - schema: damao_wubi
'@
            ExpectedFragments = @('schema_list/+', 'schema: luna_pinyin', 'schema: damao_wubi')
            ExpectedListKind = 'plus'
            Modified = $false
        },
        [PSCustomObject]@{
            Name = 'legacy-project-id-cleanup'
            CreateFile = $true
            InitialContent = "patch:`n  `"schema_list/+`":`n    - schema: luna_pinyin`n    - schema: terra_pinyin`n    - schema: abc_custom`n    - schema: $legacyProjectSchemaId`n`n    - schema: damao_wubi`n"
            ExpectedFragments = @('schema: luna_pinyin', 'schema: terra_pinyin', 'schema: abc_custom', 'schema: damao_wubi')
            ExpectedListKind = 'plus'
            ExpectedSchemaOrder = @('luna_pinyin', 'terra_pinyin', 'abc_custom', 'damao_wubi')
            Modified = $true
        },
        [PSCustomObject]@{
            Name = 'duplicate-current-selection-cleanup'
            CreateFile = $true
            InitialContent = "patch:`n  `"schema_list/+`":`n    - schema: damao_wubi`n    - schema: other_schema`n    - schema: damao_wubi`n"
            ExpectedFragments = @('schema: damao_wubi', 'schema: other_schema')
            ExpectedListKind = 'plus'
            Modified = $true
        },
        [PSCustomObject]@{
            Name = 'switcher-settings-dual-lists'
            CreateFile = $true
            InitialContent = $switcherCustomization + "`npatch:`n  schema_list:`n    - {schema: damao_wubi}`n  `"schema_list/+`":`n    - {schema: damao_wubi}`n"
            ExpectedFragments = @('generator: "Rime::SwitcherSettings"', 'schema_list:', '{schema: damao_wubi}')
            ForbiddenFragments = @('schema_list/+', 'schema_list/@next')
            PreservedText = $switcherCustomization
            ExpectedListKind = 'explicit'
            Modified = $true
        },
        [PSCustomObject]@{
            Name = 'explicit-plus-semantic-merge'
            CreateFile = $true
            InitialContent = "patch:`n  schema_list:`n    - {schema: luna_pinyin}`n    - {schema: $legacyProjectSchemaId}`n  `"schema_list/+`":`n    - {schema: terra_pinyin}`n    - {schema: damao_wubi}`n"
            ExpectedFragments = @('{schema: luna_pinyin}', '{schema: terra_pinyin}', '{schema: damao_wubi}')
            ForbiddenFragments = @('schema_list/+', 'schema_list/@next')
            ExpectedSchemaOrder = @('luna_pinyin', 'terra_pinyin', 'damao_wubi')
            ExpectedListKind = 'explicit'
            Modified = $true
        },
        [PSCustomObject]@{
            Name = 'explicit-and-next-merge'
            CreateFile = $true
            InitialContent = "patch:`n  schema_list:`n    - schema: luna_pinyin`n  `"schema_list/@next`": { schema: terra_pinyin }`n"
            ExpectedFragments = @('schema: luna_pinyin', 'schema: terra_pinyin', 'schema: damao_wubi')
            ForbiddenFragments = @('schema_list/+', 'schema_list/@next')
            ExpectedSchemaOrder = @('luna_pinyin', 'terra_pinyin', 'damao_wubi')
            ExpectedListKind = 'explicit'
            Modified = $true
        },
        [PSCustomObject]@{
            Name = 'all-three-schema-list-forms'
            CreateFile = $true
            InitialContent = "patch:`n  schema_list:`n    - {schema: luna_pinyin}`n  `"schema_list/+`":`n    - {schema: terra_pinyin}`n    - {schema: damao_wubi}`n  `"schema_list/@next`": { schema: damao_wubi }`n"
            ExpectedFragments = @('{schema: luna_pinyin}', '{schema: terra_pinyin}', '{schema: damao_wubi}')
            ForbiddenFragments = @('schema_list/+', 'schema_list/@next')
            ExpectedSchemaOrder = @('luna_pinyin', 'terra_pinyin', 'damao_wubi')
            ExpectedListKind = 'explicit'
            Modified = $true
        },
        [PSCustomObject]@{
            Name = 'legacy-next-migration'
            CreateFile = $true
            InitialContent = @'
patch:
  "schema_list/@next": { schema: damao_wubi }
'@
            ExpectedFragments = @('schema_list/+', 'schema: damao_wubi')
            ExpectedListKind = 'plus'
            Modified = $true
        }
    )

    foreach ($mergeCase in $mergeCases) {
        $caseUserDir = Join-Path $testRoot "merge\$($mergeCase.Name)\Rime"
        New-Item -ItemType Directory -Path $caseUserDir -Force | Out-Null
        $caseDefaultCustom = Join-Path $caseUserDir 'default.custom.yaml'
        if ($mergeCase.CreateFile) {
            [System.IO.File]::WriteAllText($caseDefaultCustom, $mergeCase.InitialContent)
        }

        & $installScript -RimeUserDir $caseUserDir -WeaselRoot $fakeWeaselRoot -WubiSourcePath $fakeWubiSource -SkipDeploy | Out-Null
        $firstInstallContent = [System.IO.File]::ReadAllText($caseDefaultCustom)
        Assert-True -Condition ([regex]::Matches($firstInstallContent, '(?m)^patch:\s*$').Count -eq 1) -Message "Case '$($mergeCase.Name)' did not produce exactly one top-level patch block."
        Assert-True -Condition ([regex]::Matches($firstInstallContent, 'schema:\s*damao_wubi\b').Count -eq 1) -Message "Case '$($mergeCase.Name)' did not contain exactly one DaMao Input Method schema selection."
        $legacySelectionPattern = '(?m)^\s*-\s*schema:\s*["'']?' + [regex]::Escape($legacyProjectSchemaId) + '["'']?\s*(?:#.*)?$'
        Assert-True -Condition ([regex]::Matches($firstInstallContent, $legacySelectionPattern).Count -eq 0) -Message "Case '$($mergeCase.Name)' retained the old development schema selection."
        foreach ($fragment in $mergeCase.ExpectedFragments) {
            Assert-True -Condition ($firstInstallContent.Contains($fragment)) -Message "Case '$($mergeCase.Name)' did not preserve or add '$fragment'."
        }
        $forbiddenFragmentsProperty = $mergeCase.PSObject.Properties['ForbiddenFragments']
        if ($null -ne $forbiddenFragmentsProperty) {
            foreach ($fragment in $forbiddenFragmentsProperty.Value) {
                Assert-True -Condition (-not $firstInstallContent.Contains($fragment)) -Message "Case '$($mergeCase.Name)' retained redundant '$fragment'."
            }
        }
        $preservedTextProperty = $mergeCase.PSObject.Properties['PreservedText']
        if ($null -ne $preservedTextProperty) {
            Assert-True -Condition ($firstInstallContent.StartsWith($preservedTextProperty.Value, [System.StringComparison]::Ordinal)) -Message "Case '$($mergeCase.Name)' changed the customization block."
        }
        $expectedSchemaOrderProperty = $mergeCase.PSObject.Properties['ExpectedSchemaOrder']
        if ($null -ne $expectedSchemaOrderProperty) {
            $previousPosition = -1
            foreach ($schemaId in $expectedSchemaOrderProperty.Value) {
                $position = $firstInstallContent.IndexOf("schema: $schemaId", [System.StringComparison]::Ordinal)
                Assert-True -Condition ($position -gt $previousPosition) -Message "Case '$($mergeCase.Name)' did not preserve schema order at '$schemaId'."
                $previousPosition = $position
            }
        }
        Assert-True -Condition ($firstInstallContent -notmatch 'schema_list/@next') -Message "Case '$($mergeCase.Name)' retained the incompatible schema_list/@next operation."
        Assert-True -Condition ($firstInstallContent -notmatch '(?m)^\s*["'']?schema_list/\+["'']?\s*:\s*\{') -Message "Case '$($mergeCase.Name)' generated schema_list/+ as an inline object instead of a list."
        if ($mergeCase.ExpectedListKind -eq 'plus') {
            $validPlusList = $firstInstallContent -match '(?m)^\s{2}["'']?schema_list/\+["'']?\s*:\s*$' -and
                $firstInstallContent -match '(?m)^\s{4}-\s*(?:schema:\s*damao_wubi|\{\s*schema:\s*damao_wubi\s*\})\s*$'
            Assert-True -Condition $validPlusList -Message "Case '$($mergeCase.Name)' did not generate a valid schema_list/+ list structure."
        }

        if ($mergeCase.CreateFile -and $mergeCase.Modified) {
            $defaultBackups = @(Get-ChildItem -LiteralPath (Join-Path $caseUserDir 'backup') -File -Filter 'default.custom.yaml' -Recurse -ErrorAction SilentlyContinue)
            Assert-True -Condition ($defaultBackups.Count -ge 1) -Message "Case '$($mergeCase.Name)' was modified without a default.custom.yaml backup."
        }
        if (-not $mergeCase.Modified) {
            Assert-True -Condition ($firstInstallContent -eq $mergeCase.InitialContent) -Message "Case '$($mergeCase.Name)' changed an already-correct configuration."
        }

        & $installScript -RimeUserDir $caseUserDir -WeaselRoot $fakeWeaselRoot -SkipDeploy | Out-Null
        $secondInstallContent = [System.IO.File]::ReadAllText($caseDefaultCustom)
        Assert-True -Condition ($secondInstallContent -eq $firstInstallContent) -Message "Case '$($mergeCase.Name)' was not idempotent on repeated installation."
    }

    # The normal silent Weasel install creates an empty default.custom.yaml.
    # Prepending through Rime's list patch preserves every shared default schema.
    $freshEmptyUserDir = Join-Path $testRoot 'fresh-empty\Rime'
    New-Item -ItemType Directory -Path $freshEmptyUserDir -Force | Out-Null
    $freshEmptyDefaultPath = Join-Path $freshEmptyUserDir 'default.custom.yaml'
    [System.IO.File]::WriteAllText($freshEmptyDefaultPath, '')
    & $installScript -RimeUserDir $freshEmptyUserDir -WeaselRoot $fakeWeaselRoot `
        -WubiSourcePath $fakeWubiSource -SkipDeploy -InitializeFreshRimeState | Out-Null
    $freshEmptyAfter = [System.IO.File]::ReadAllText($freshEmptyDefaultPath)
    Assert-True -Condition ($freshEmptyAfter -match '(?m)^\s*"schema_list/@before 0":\s*\{\s*schema:\s*damao_wubi\s*\}\s*$') -Message 'Fresh empty configuration did not prepend BigCat through the supported Rime list operation.'
    Assert-True -Condition ([regex]::Matches($freshEmptyAfter, 'schema:\s*damao_wubi\b').Count -eq 1) -Message 'Fresh empty configuration did not contain BigCat exactly once.'
    Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path $freshEmptyUserDir 'user.yaml'))) -Message 'Fresh initialization created user.yaml to force BigCat active.'
    & $installScript -RimeUserDir $freshEmptyUserDir -WeaselRoot $fakeWeaselRoot `
        -WubiSourcePath $fakeWubiSource -SkipDeploy | Out-Null
    Assert-True -Condition ([System.IO.File]::ReadAllText($freshEmptyDefaultPath) -ceq $freshEmptyAfter) -Message 'Reinstall rewrote the one-shot fresh schema preference.'

    # A freshness decision captured before Weasel ran may arrive after Weasel has
    # created its ordinary initial files. Only that explicit one-shot signal may
    # place BigCat first; all generated schemas and unrelated settings survive.
    $freshInitializeUserDir = Join-Path $testRoot 'fresh-initialize\Rime'
    New-Item -ItemType Directory -Path $freshInitializeUserDir -Force | Out-Null
    $freshDefaultCustomPath = Join-Path $freshInitializeUserDir 'default.custom.yaml'
    $freshUserYamlPath = Join-Path $freshInitializeUserDir 'user.yaml'
    $freshInstallationYamlPath = Join-Path $freshInitializeUserDir 'installation.yaml'
    $freshWeaselCustomPath = Join-Path $freshInitializeUserDir 'weasel.custom.yaml'
    $freshUserYaml = "var:`n  previously_selected_schema: luna_pinyin`n"
    $freshInstallationYaml = "installation_id: fresh-weasel-fixture`n"
    $freshWeaselCustom = "patch:`n  `"style/color_scheme`": user_owned_theme`n"
    [System.IO.File]::WriteAllText($freshDefaultCustomPath, @'
customization:
  distribution_code_name: Weasel
  distribution_version: 0.17.4
patch:
  schema_list:
    - schema: luna_pinyin
    - schema: terra_pinyin
  "menu/page_size": 9
'@)
    [System.IO.File]::WriteAllText($freshUserYamlPath, $freshUserYaml)
    [System.IO.File]::WriteAllText($freshInstallationYamlPath, $freshInstallationYaml)
    [System.IO.File]::WriteAllText($freshWeaselCustomPath, $freshWeaselCustom)

    $freshResult = & $installScript -RimeUserDir $freshInitializeUserDir -WeaselRoot $fakeWeaselRoot `
        -WubiSourcePath $fakeWubiSource -SkipDeploy -InitializeFreshRimeState
    $freshDefaultAfter = [System.IO.File]::ReadAllText($freshDefaultCustomPath)
    $freshSchemaMatches = [regex]::Matches($freshDefaultAfter, '(?m)^\s*-\s*(?:\{\s*)?schema:\s*(?<schema>[A-Za-z0-9_.+-]+)')
    $freshSchemaOrder = @($freshSchemaMatches | ForEach-Object { $_.Groups['schema'].Value })
    Assert-True -Condition ($freshResult.FreshStateInitialized) -Message 'Fresh initialization result did not record the one-shot preference.'
    Assert-True -Condition (($freshSchemaOrder -join ',') -ceq 'damao_wubi,luna_pinyin,terra_pinyin') -Message 'Fresh initialization did not place BigCat first while preserving generated schema order.'
    Assert-True -Condition ([regex]::Matches($freshDefaultAfter, 'schema:\s*damao_wubi\b').Count -eq 1) -Message 'Fresh initialization did not contain BigCat exactly once.'
    Assert-True -Condition ($freshDefaultAfter -match 'distribution_code_name:\s*Weasel' -and $freshDefaultAfter -match 'menu/page_size.*9') -Message 'Fresh initialization removed unrelated default.custom.yaml settings.'
    Assert-True -Condition ([System.IO.File]::ReadAllText($freshUserYamlPath) -ceq $freshUserYaml) -Message 'Fresh initialization overwrote user.yaml to force the active schema.'
    Assert-True -Condition ([System.IO.File]::ReadAllText($freshInstallationYamlPath) -ceq $freshInstallationYaml) -Message 'Fresh initialization changed installation.yaml.'
    Assert-True -Condition ([System.IO.File]::ReadAllText($freshWeaselCustomPath) -ceq $freshWeaselCustom) -Message 'Fresh initialization changed unrelated Weasel appearance state.'

    # Simulate the user choosing another schema. Reinstall and user-facing
    # redeploy must not apply the fresh preference again.
    $switchedDefault = "patch:`n  schema_list:`n    - schema: terra_pinyin`n    - schema: damao_wubi`n    - schema: luna_pinyin`n  `"menu/page_size`": 8`n"
    $switchedUser = "var:`n  previously_selected_schema: terra_pinyin`n"
    [System.IO.File]::WriteAllText($freshDefaultCustomPath, $switchedDefault)
    [System.IO.File]::WriteAllText($freshUserYamlPath, $switchedUser)
    & $installScript -RimeUserDir $freshInitializeUserDir -WeaselRoot $fakeWeaselRoot `
        -WubiSourcePath $fakeWubiSource -SkipDeploy | Out-Null
    Assert-True -Condition ([System.IO.File]::ReadAllText($freshDefaultCustomPath) -ceq $switchedDefault) -Message 'Reinstall reapplied the fresh BigCat-first preference after the user switched schemas.'
    Assert-True -Condition ([System.IO.File]::ReadAllText($freshUserYamlPath) -ceq $switchedUser) -Message 'Reinstall changed the user-selected active schema state.'
    & $installScript -RimeUserDir $freshInitializeUserDir -WeaselRoot $fakeWeaselRoot `
        -WubiSourcePath $fakeWubiSource -SkipDeploy -UserFacingRedeploy | Out-Null
    Assert-True -Condition ([System.IO.File]::ReadAllText($freshDefaultCustomPath) -ceq $switchedDefault) -Message 'Redeploy reapplied the fresh BigCat-first preference after the user switched schemas.'
    Assert-True -Condition ([System.IO.File]::ReadAllText($freshUserYamlPath) -ceq $switchedUser) -Message 'Redeploy changed the user-selected active schema state.'

    # A pre-existing entry makes this an existing-user path: append BigCat once
    # without reordering the user's list or touching active/runtime state.
    $existingStateUserDir = Join-Path $testRoot 'existing-state\Rime'
    New-Item -ItemType Directory -Path $existingStateUserDir -Force | Out-Null
    $existingDefaultPath = Join-Path $existingStateUserDir 'default.custom.yaml'
    $existingUserPath = Join-Path $existingStateUserDir 'user.yaml'
    $existingDefault = "patch:`n  schema_list:`n    - schema: luna_pinyin`n    - schema: terra_pinyin`n  `"menu/page_size`": 7`n"
    $existingUser = "var:`n  previously_selected_schema: terra_pinyin`n"
    [System.IO.File]::WriteAllText($existingDefaultPath, $existingDefault)
    [System.IO.File]::WriteAllText($existingUserPath, $existingUser)
    & $installScript -RimeUserDir $existingStateUserDir -WeaselRoot $fakeWeaselRoot `
        -WubiSourcePath $fakeWubiSource -SkipDeploy | Out-Null
    $existingDefaultAfter = [System.IO.File]::ReadAllText($existingDefaultPath)
    $existingLunaIndex = $existingDefaultAfter.IndexOf('schema: luna_pinyin', [System.StringComparison]::Ordinal)
    $existingTerraIndex = $existingDefaultAfter.IndexOf('schema: terra_pinyin', [System.StringComparison]::Ordinal)
    $existingDamaoIndex = $existingDefaultAfter.IndexOf('schema: damao_wubi', [System.StringComparison]::Ordinal)
    Assert-True -Condition ($existingLunaIndex -ge 0 -and $existingLunaIndex -lt $existingTerraIndex -and $existingTerraIndex -lt $existingDamaoIndex) -Message 'Existing-user installation reordered the schema list instead of appending BigCat.'
    Assert-True -Condition ([regex]::Matches($existingDefaultAfter, 'schema:\s*damao_wubi\b').Count -eq 1) -Message 'Existing-user installation did not add BigCat exactly once.'
    Assert-True -Condition ($existingDefaultAfter -match 'menu/page_size.*7') -Message 'Existing-user installation removed an unrelated default.custom.yaml key.'
    Assert-True -Condition ([System.IO.File]::ReadAllText($existingUserPath) -ceq $existingUser) -Message 'Existing-user installation changed the active schema stored in user.yaml.'

    $unsafeMergeCases = @(
        [PSCustomObject]@{
            Name = 'schema-list-object-not-list'
            Content = "patch:`n  schema_list: { schema: damao_wubi }`n"
        },
        [PSCustomObject]@{
            Name = 'abnormal-schema-entry'
            Content = "patch:`n  schema_list:`n    - name: damao_wubi`n"
        },
        [PSCustomObject]@{
            Name = 'nested-schema-entry'
            Content = "patch:`n  schema_list:`n    - schema: damao_wubi`n      unexpected: value`n"
        },
        [PSCustomObject]@{
            Name = 'duplicate-schema-list-key'
            Content = "patch:`n  schema_list:`n    - schema: luna_pinyin`n  schema_list:`n    - schema: damao_wubi`n"
        },
        [PSCustomObject]@{
            Name = 'unsupported-schema-list-operation'
            Content = "patch:`n  `"schema_list/@0`": { schema: damao_wubi }`n"
        }
    )
    foreach ($unsafeCase in $unsafeMergeCases) {
        $unsafeDirectory = Join-Path $testRoot "unsafe-merge\$($unsafeCase.Name)"
        $unsafeConfig = Join-Path $unsafeDirectory 'default.custom.yaml'
        New-Item -ItemType Directory -Path $unsafeDirectory -Force | Out-Null
        [System.IO.File]::WriteAllText($unsafeConfig, $unsafeCase.Content)
        $unsafeError = $null
        try {
            [void](Add-DaMaoSchemaSelection -DefaultCustomPath $unsafeConfig -BackupDirectory (Join-Path $unsafeDirectory 'backup'))
        }
        catch {
            $unsafeError = $_.Exception.Message
        }
        Assert-True -Condition ($unsafeError -match '^\[DM-CONFIG-MERGE-UNSAFE\]') -Message "Unsafe merge case '$($unsafeCase.Name)' was not rejected with DM-CONFIG-MERGE-UNSAFE."
        Assert-True -Condition ([System.IO.File]::ReadAllText($unsafeConfig) -ceq $unsafeCase.Content) -Message "Unsafe merge case '$($unsafeCase.Name)' modified the configuration before rejection."
    }

    [System.IO.File]::WriteAllText(
        (Join-Path $fakeUserDir 'default.custom.yaml'),
        "patch:`n  schema_list:`n    - schema: luna_pinyin`n  `"menu/page_size`": 9`n"
    )

    $invalidInstalledDictionary = Join-Path $fakeUserDir 'wubi86.dict.yaml'
    [System.IO.File]::WriteAllText($invalidInstalledDictionary, "name: not_wubi86`n")
    $invalidDependency = Get-DaMaoDependencyFile -RimeUserDir $fakeUserDir -WeaselRoot $fakeWeaselRoot
    Assert-True -Condition ($null -eq $invalidDependency) -Message 'Malformed installed dictionary was accepted as the wubi86 dependency.'

    & $installScript -RimeUserDir $fakeUserDir -WeaselRoot $fakeWeaselRoot -WubiSourcePath $fakeWubiSource -SkipDeploy | Out-Null
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $fakeUserDir 'damao_wubi.schema.yaml')) -Message 'Installer did not copy damao_wubi.schema.yaml.'
    $installedSchemaIcon = Join-Path $fakeUserDir 'damao_wubi\branding\bigcat-ime.ico'
    Assert-True -Condition (Test-Path -LiteralPath $installedSchemaIcon -PathType Leaf) -Message 'Installer did not deploy the schema-scoped BigCat icon.'
    Assert-True -Condition ((Get-FileHash -LiteralPath $installedSchemaIcon -Algorithm SHA256).Hash -eq
        (Get-FileHash -LiteralPath (Join-Path $repoRoot 'assets\branding\windows\bigcat-ime.ico') -Algorithm SHA256).Hash) -Message 'Deployed schema icon differs from the IME-specific BigCat icon.'
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $fakeUserDir 'wubi86.dict.yaml')) -Message 'Offline installer did not copy wubi86.dict.yaml.'
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $fakeUserDir 'LICENSE.rime-wubi.txt')) -Message 'Offline installer did not preserve the rime-wubi license.'
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $fakeUserDir 'rime-wubi.source.json')) -Message 'Offline installer did not record rime-wubi provenance.'
    Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path $fakeUserDir 'wubi86.schema.yaml'))) -Message 'Installer copied an unnecessary upstream schema.'

    Assert-True -Condition (Test-DaMaoOfficialRepositoryUrl 'https://github.com/rime/rime-wubi.git') -Message 'Official HTTPS repository URL was rejected.'
    Assert-True -Condition (-not (Test-DaMaoOfficialRepositoryUrl 'https://github.com/example/rime-wubi.git')) -Message 'Non-official repository URL was accepted.'

    $invalidSource = Join-Path $testRoot 'source\invalid'
    New-Item -ItemType Directory -Path $invalidSource -Force | Out-Null
    $invalidSourceRejected = $false
    try {
        [void](Get-DaMaoWubiSourceInfo -SourcePath $invalidSource)
    }
    catch {
        $invalidSourceRejected = $_.Exception.Message -match '^\[DM-WUBI-SOURCE-INVALID\]'
    }
    Assert-True -Condition $invalidSourceRejected -Message 'Incomplete offline source did not produce DM-WUBI-SOURCE-INVALID.'

    $defaultCustomPath = Join-Path $fakeUserDir 'default.custom.yaml'
    $defaultCustom = [System.IO.File]::ReadAllText($defaultCustomPath)
    Assert-True -Condition ($defaultCustom -match 'schema:\s*damao_wubi') -Message 'Installer did not enable the DaMao Input Method schema.'
    Assert-True -Condition ($defaultCustom -match 'schema:\s*luna_pinyin') -Message 'Installer removed an existing schema selection.'
    Assert-True -Condition ($defaultCustom -match 'menu/page_size') -Message 'Installer removed an existing user setting.'

    & $installScript -RimeUserDir $fakeUserDir -WeaselRoot $fakeWeaselRoot -SkipDeploy | Out-Null
    $defaultCustom = [System.IO.File]::ReadAllText($defaultCustomPath)
    $selectionCount = [regex]::Matches($defaultCustom, 'schema:\s*damao_wubi').Count
    Assert-True -Condition ($selectionCount -eq 1) -Message 'Installer is not idempotent; schema selection was duplicated.'
    Assert-True -Condition ((Get-FileHash -LiteralPath $installedSchemaIcon -Algorithm SHA256).Hash -eq
        (Get-FileHash -LiteralPath (Join-Path $repoRoot 'assets\branding\windows\bigcat-ime.ico') -Algorithm SHA256).Hash) -Message 'Repeated installation did not preserve the IME-specific schema icon.'

    $deployFailureReported = $false
    try {
        & $installScript -RimeUserDir $fakeUserDir -WeaselRoot $fakeWeaselRoot | Out-Null
    }
    catch {
        $deployFailureReported = $_.Exception.Message -match '^\[DM-DEPLOY-FAILED\]'
    }
    Assert-True -Condition $deployFailureReported -Message 'Deployment failure did not produce DM-DEPLOY-FAILED.'

    $installedSchemaPath = Join-Path $fakeUserDir 'damao_wubi.schema.yaml'
    $schemaBeforeFailedDiagnostic = [System.IO.File]::ReadAllText($installedSchemaPath)
    $failedDiagnosticBuildDirectory = Join-Path $fakeUserDir 'build'
    $failedDiagnosticBuiltSchema = Join-Path $failedDiagnosticBuildDirectory 'damao_wubi.schema.yaml'
    New-Item -ItemType Directory -Path $failedDiagnosticBuildDirectory -Force | Out-Null
    [System.IO.File]::WriteAllText($failedDiagnosticBuiltSchema, 'name: stale diagnostic build')
    $diagnosticFailureReported = $false
    try {
        & (Join-Path $repoRoot 'scripts\Test-DaMaoSchemaVariant.ps1') -Variant '00-minimal' -RimeUserDir $fakeUserDir -WeaselRoot $fakeWeaselRoot | Out-Null
    }
    catch {
        $diagnosticFailureReported = $_.Exception.Message -match '^\[DM-DEPLOY-FAILED\]'
    }
    Assert-True -Condition $diagnosticFailureReported -Message 'A failed diagnostic deployment did not preserve DM-DEPLOY-FAILED.'
    $schemaAfterFailedDiagnostic = [System.IO.File]::ReadAllText($installedSchemaPath)
    Assert-True -Condition ($schemaAfterFailedDiagnostic -ceq $schemaBeforeFailedDiagnostic) -Message 'A failed diagnostic deployment did not restore the original user schema.'
    Assert-True -Condition (-not (Test-Path -LiteralPath $failedDiagnosticBuiltSchema -PathType Leaf)) -Message 'A failed diagnostic deployment left a diagnostic compiled schema after restoring the original source schema.'

    # Two sources with the same timestamp must still produce two distinct fresh builds.
    $cacheTestRepo = Join-Path $testRoot 'diagnostic-cache-repo'
    $cacheTestScripts = Join-Path $cacheTestRepo 'scripts'
    $cacheTestDiagnostics = Join-Path $cacheTestRepo 'schemas\diagnostics'
    $cacheTestWeaselRoot = Join-Path $testRoot 'diagnostic-cache-weasel'
    $cacheTestUserDir = Join-Path $testRoot 'diagnostic-cache-user\Rime'
    New-Item -ItemType Directory -Path $cacheTestScripts -Force | Out-Null
    New-Item -ItemType Directory -Path $cacheTestDiagnostics -Force | Out-Null
    New-Item -ItemType Directory -Path $cacheTestWeaselRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $cacheTestUserDir -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts\DaMao.Common.ps1') -Destination $cacheTestScripts -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts\Test-DaMaoSchemaVariant.ps1') -Destination $cacheTestScripts -Force
    $cacheMinimalSource = Join-Path $cacheTestDiagnostics 'damao_wubi.00-minimal.schema.yaml'
    $cacheSpellerSource = Join-Path $cacheTestDiagnostics 'damao_wubi.01-speller.schema.yaml'
    Copy-Item -LiteralPath (Join-Path $repoRoot 'schemas\diagnostics\damao_wubi.00-minimal.schema.yaml') -Destination $cacheMinimalSource -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot 'schemas\diagnostics\damao_wubi.01-speller.schema.yaml') -Destination $cacheSpellerSource -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot 'schemas\damao_wubi.schema.yaml') -Destination (Join-Path $cacheTestRepo 'schemas\damao_wubi.schema.yaml') -Force
    $identicalSourceTime = [DateTime]::SpecifyKind([DateTime]'2020-01-02T03:04:05', [DateTimeKind]::Utc)
    [System.IO.File]::SetLastWriteTimeUtc($cacheMinimalSource, $identicalSourceTime)
    [System.IO.File]::SetLastWriteTimeUtc($cacheSpellerSource, $identicalSourceTime)
    Assert-True -Condition ((Get-Item -LiteralPath $cacheMinimalSource).LastWriteTimeUtc.ToFileTimeUtc() -eq (Get-Item -LiteralPath $cacheSpellerSource).LastWriteTimeUtc.ToFileTimeUtc()) -Message 'The diagnostic cache regression sources do not have identical timestamps.'

    [System.IO.File]::WriteAllText((Join-Path $cacheTestUserDir 'wubi86.dict.yaml'), "# Rime dictionary: wubi86`n---`nname: wubi86`ncolumns:`n  - text`n  - code`n...`n")
    [System.IO.File]::WriteAllText((Join-Path $cacheTestUserDir 'default.custom.yaml'), "patch:`n  schema_list:`n    - schema: damao_wubi`n")
    [System.IO.File]::WriteAllText((Join-Path $cacheTestUserDir 'damao_wubi.schema.yaml'), 'name: original schema')
    $cacheBuildDirectory = Join-Path $cacheTestUserDir 'build'
    $cacheBuiltSchema = Join-Path $cacheBuildDirectory 'damao_wubi.schema.yaml'
    $preservedDictionaryBuild = Join-Path $cacheBuildDirectory 'wubi86.table.bin'
    New-Item -ItemType Directory -Path $cacheBuildDirectory -Force | Out-Null
    [System.IO.File]::WriteAllText($cacheBuiltSchema, 'name: stale compiled schema')
    [System.IO.File]::WriteAllText($preservedDictionaryBuild, 'preserve this dictionary artifact')

    $fakeDeployerSource = @'
using System;
using System.IO;

public static class DaMaoFakeDeployer
{
    public static int Main(string[] args)
    {
        try
        {
            string userDir = Environment.GetEnvironmentVariable("DAMAO_WUBI_TEST_RIME_USER_DIR");
            if (String.IsNullOrWhiteSpace(userDir)) return 2;
            string source = Path.Combine(userDir, "damao_wubi.schema.yaml");
            string buildDir = Path.Combine(userDir, "build");
            string compiled = Path.Combine(buildDir, "damao_wubi.schema.yaml");
            Directory.CreateDirectory(buildDir);
            File.WriteAllText(Path.Combine(buildDir, "default.yaml"), "schema_list:\r\n  - schema: damao_wubi\r\n");

            // Simulate a stale Rime cache: an existing compiled schema is reused.
            if (!File.Exists(compiled))
            {
                File.Copy(source, compiled, true);
            }
            string logPrefix = Environment.GetEnvironmentVariable("DAMAO_WUBI_TEST_RIME_LOG_PREFIX");
            if (!String.IsNullOrWhiteSpace(logPrefix))
            {
                File.WriteAllText(logPrefix + System.Diagnostics.Process.GetCurrentProcess().Id + ".log",
                    "updating workspace.\r\nupdating schemas.\r\nschema: damao_wubi\r\nfinished updating schemas: 1 success, 0 failure.\r\n");
            }
            return 0;
        }
        catch
        {
            return 3;
        }
    }
}
'@
    $fakeDeployerPath = Join-Path $cacheTestWeaselRoot 'WeaselDeployer.exe'
    Add-Type -TypeDefinition $fakeDeployerSource -Language CSharp -OutputAssembly $fakeDeployerPath -OutputType ConsoleApplication
    $cacheDiagnosticScript = Join-Path $cacheTestScripts 'Test-DaMaoSchemaVariant.ps1'
    $previousCacheTestUserDir = $env:DAMAO_WUBI_TEST_RIME_USER_DIR
    $previousCacheTestLogPrefix = $env:DAMAO_WUBI_TEST_RIME_LOG_PREFIX
    $rimeLogRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'rime.weasel'
    New-Item -ItemType Directory -Path $rimeLogRoot -Force | Out-Null
    $cacheTestLogPrefix = Join-Path $rimeLogRoot "damao-ime-fake-deploy-$([Guid]::NewGuid().ToString('N'))-"
    try {
        $env:DAMAO_WUBI_TEST_RIME_USER_DIR = $cacheTestUserDir
        $env:DAMAO_WUBI_TEST_RIME_LOG_PREFIX = $cacheTestLogPrefix
        & $cacheDiagnosticScript -Variant '00-minimal' -RimeUserDir $cacheTestUserDir -WeaselRoot $cacheTestWeaselRoot | Out-Null
        $firstCacheBuild = [System.IO.File]::ReadAllText($cacheBuiltSchema)
        Assert-True -Condition $firstCacheBuild.Contains("$damaoDisplayName Diagnostic 00 - Minimal") -Message 'The first same-timestamp diagnostic variant did not receive a fresh build.'
        Assert-True -Condition ((Get-Item -LiteralPath (Join-Path $cacheTestUserDir 'damao_wubi.schema.yaml')).LastWriteTimeUtc -gt $identicalSourceTime) -Message 'The installed diagnostic schema LastWriteTime was not explicitly refreshed.'

        & $cacheDiagnosticScript -Variant '01-speller' -RimeUserDir $cacheTestUserDir -WeaselRoot $cacheTestWeaselRoot | Out-Null
        $secondCacheBuild = [System.IO.File]::ReadAllText($cacheBuiltSchema)
        Assert-True -Condition $secondCacheBuild.Contains("$damaoDisplayName Diagnostic 01 - Speller") -Message 'The second same-timestamp diagnostic variant reused the first variant stale build.'
        Assert-True -Condition (Test-Path -LiteralPath $preservedDictionaryBuild -PathType Leaf) -Message 'Diagnostic cache invalidation removed a dictionary build artifact.'

        & $cacheDiagnosticScript -Variant '04-full-alpha' -RimeUserDir $cacheTestUserDir -WeaselRoot $cacheTestWeaselRoot | Out-Null
        $fullAlphaCacheBuild = [System.IO.File]::ReadAllText($cacheBuiltSchema)
        Assert-True -Condition $fullAlphaCacheBuild.Contains("$damaoDisplayName Diagnostic 04 - Full Alpha") -Message 'The runtime-generated full Alpha diagnostic did not deploy with its diagnostic name.'
        Assert-True -Condition ($fullAlphaCacheBuild -match '(?m)^\s*version:\s*"0\.1-diag-04"\s*$') -Message 'The runtime-generated full Alpha diagnostic did not deploy with version 0.1-diag-04.'

        # A normal install must replace both a diagnostic source and its stale
        # compiled schema with the repository's formal Alpha schema.
        $formalInstallUserDir = Join-Path $testRoot 'formal-install-user\Rime'
        $formalInstallBuildDir = Join-Path $formalInstallUserDir 'build'
        New-Item -ItemType Directory -Path $formalInstallBuildDir -Force | Out-Null
        $formalInstallDictionary = Join-Path $formalInstallUserDir 'wubi86.dict.yaml'
        Copy-Item -LiteralPath (Join-Path $fakeWubiSource 'wubi86.dict.yaml') -Destination $formalInstallDictionary -Force
        $formalInstallDefault = Join-Path $formalInstallUserDir 'default.custom.yaml'
        [System.IO.File]::WriteAllText(
            $formalInstallDefault,
            "patch:`n  `"schema_list/+`":`n    - schema: luna_pinyin`n    - schema: terra_pinyin`n    - schema: $legacyProjectSchemaId`n    - schema: damao_wubi`n"
        )
        $formalInstallSchema = Join-Path $formalInstallUserDir 'damao_wubi.schema.yaml'
        Copy-Item -LiteralPath $cacheSpellerSource -Destination $formalInstallSchema -Force
        $formalInstallBuiltSchema = Join-Path $formalInstallBuildDir 'damao_wubi.schema.yaml'
        Copy-Item -LiteralPath $cacheSpellerSource -Destination $formalInstallBuiltSchema -Force
        [System.IO.File]::WriteAllText((Join-Path $formalInstallBuildDir 'default.yaml'), "schema_list:`n  - schema: damao_wubi`n")

        $formalSourcePath = Join-Path $repoRoot 'schemas\damao_wubi.schema.yaml'
        $formalSourceContent = [System.IO.File]::ReadAllText($formalSourcePath)
        $dictionaryHashBeforeInstall = (Get-FileHash -LiteralPath $formalInstallDictionary -Algorithm SHA256).Hash
        $env:DAMAO_WUBI_TEST_RIME_USER_DIR = $formalInstallUserDir

        & $installScript -RimeUserDir $formalInstallUserDir -WeaselRoot $cacheTestWeaselRoot | Out-Null
        $firstFormalSchema = [System.IO.File]::ReadAllText($formalInstallSchema)
        $firstFormalBuild = [System.IO.File]::ReadAllText($formalInstallBuiltSchema)
        $firstFormalDefault = [System.IO.File]::ReadAllText($formalInstallDefault)
        Assert-True -Condition ($firstFormalSchema -ceq $formalSourceContent) -Message 'Normal installation did not restore the repository formal schema after a diagnostic variant.'
        Assert-True -Condition ($firstFormalBuild -ceq $formalSourceContent) -Message 'Normal installation left a stale Diagnostic compiled schema.'
        Assert-True -Condition ($firstFormalBuild -notmatch '(?im)^\s*name\s*:.*Diagnostic') -Message 'Normal installation produced a compiled schema with a Diagnostic name.'
        Assert-True -Condition ([regex]::Matches($firstFormalDefault, 'schema:\s*damao_wubi\b').Count -eq 1) -Message 'Normal installation did not leave exactly one damao_wubi registration.'
        $formalLegacyPattern = 'schema:\s*' + [regex]::Escape($legacyProjectSchemaId) + '\b'
        Assert-True -Condition ($firstFormalDefault -notmatch $formalLegacyPattern) -Message 'Normal installation retained the old development schema registration.'
        Assert-True -Condition ($firstFormalDefault -match 'schema:\s*luna_pinyin\b' -and $firstFormalDefault -match 'schema:\s*terra_pinyin\b') -Message 'Normal installation removed an unrelated user schema.'
        Assert-True -Condition ((Get-FileHash -LiteralPath $formalInstallDictionary -Algorithm SHA256).Hash -eq $dictionaryHashBeforeInstall) -Message 'Normal installation destructively reinstalled an existing valid wubi86 dictionary.'
        Assert-True -Condition (Test-Path -LiteralPath (Join-Path $formalInstallBuildDir 'default.yaml') -PathType Leaf) -Message 'Normal installation did not preserve a valid build/default.yaml.'

        & $installScript -RimeUserDir $formalInstallUserDir -WeaselRoot $cacheTestWeaselRoot | Out-Null
        $secondFormalSchema = [System.IO.File]::ReadAllText($formalInstallSchema)
        $secondFormalBuild = [System.IO.File]::ReadAllText($formalInstallBuiltSchema)
        $secondFormalDefault = [System.IO.File]::ReadAllText($formalInstallDefault)
        Assert-True -Condition ($secondFormalSchema -ceq $firstFormalSchema) -Message 'A repeated normal installation changed formal schema content.'
        Assert-True -Condition ($secondFormalBuild -ceq $firstFormalBuild) -Message 'A repeated normal installation invalidated a valid formal build result.'
        Assert-True -Condition ($secondFormalDefault -ceq $firstFormalDefault) -Message 'A repeated normal installation changed schema registration content.'
        Assert-True -Condition ([regex]::Matches($secondFormalDefault, 'schema:\s*damao_wubi\b').Count -eq 1) -Message 'A repeated normal installation duplicated damao_wubi.'
        Assert-True -Condition ($secondFormalDefault -notmatch $formalLegacyPattern) -Message 'A repeated normal installation recreated the old development schema registration.'
        Assert-True -Condition ((Get-FileHash -LiteralPath $formalInstallDictionary -Algorithm SHA256).Hash -eq $dictionaryHashBeforeInstall) -Message 'A repeated normal installation changed the existing wubi86 dictionary.'

        $smokeOutput = (& (Join-Path $repoRoot 'scripts\Test-DaMaoEnvironment.ps1') -RimeUserDir $formalInstallUserDir -WeaselRoot $cacheTestWeaselRoot 6>&1 | Out-String)
        Assert-True -Condition ($smokeOutput -match '(?m)^PASS Weasel installation') -Message 'The Alpha smoke test did not report PASS for the fake Weasel installation.'
        Assert-True -Condition ($smokeOutput -match '(?m)^PASS Compiled schema name is formal') -Message 'The Alpha smoke test did not validate the formal compiled schema name.'
        Assert-True -Condition ($smokeOutput -match '(?m)^PASS auto_select_unique_candidate is absent') -Message 'The Alpha smoke test did not validate the forbidden speller option absence.'
        Assert-True -Condition ($smokeOutput -match '(?m)^Result: success\s*$') -Message 'The Alpha smoke test did not finish with Result: success.'
    }
    finally {
        $env:DAMAO_WUBI_TEST_RIME_USER_DIR = $previousCacheTestUserDir
        $env:DAMAO_WUBI_TEST_RIME_LOG_PREFIX = $previousCacheTestLogPrefix
        Get-ChildItem -LiteralPath $rimeLogRoot -File -Filter "$([System.IO.Path]::GetFileName($cacheTestLogPrefix))*" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    }

    $buildDirectory = Join-Path $fakeUserDir 'build'
    New-Item -ItemType Directory -Path $buildDirectory -Force | Out-Null
    $builtDefaultPath = Join-Path $buildDirectory 'default.yaml'
    $builtSchemaPath = Join-Path $buildDirectory 'damao_wubi.schema.yaml'
    [System.IO.File]::WriteAllLines($builtDefaultPath, @('schema_list:', '  - schema: luna_pinyin'))
    [System.IO.File]::WriteAllText($builtSchemaPath, 'schema:')
    $missingRegistrationReported = $false
    try {
        Assert-DaMaoDeployment -RimeUserDir $fakeUserDir
    }
    catch {
        $missingRegistrationReported = $_.Exception.Message -match '^\[DM-DEPLOY-FAILED\].*does not register damao_wubi'
    }
    Assert-True -Condition $missingRegistrationReported -Message 'Post-deployment verification accepted a build/default.yaml without damao_wubi.'

    [System.IO.File]::WriteAllLines($builtDefaultPath, @('schema_list:', '  - schema: luna_pinyin', '  - schema: damao_wubi'))
    Assert-DaMaoDeployment -RimeUserDir $fakeUserDir

    $powershellExecutable = (Get-Command powershell -ErrorAction Stop).Source

    $deployStartInfo = New-DaMaoDeployerStartInfo -DeployerPath (Join-Path $fakeWeaselRoot 'WeaselDeployer.exe') -Command '/deploy'
    Assert-True -Condition ([string]::Equals($deployStartInfo.Arguments, '/deploy', [System.StringComparison]::Ordinal)) -Message 'ProcessStartInfo.Arguments is not exactly /deploy.'
    Assert-True -Condition ($deployStartInfo.Arguments.Length -eq 7) -Message 'ProcessStartInfo.Arguments for /deploy is not exactly seven characters.'
    Assert-True -Condition ([string]::Equals($deployStartInfo.WorkingDirectory, $fakeWeaselRoot, [System.StringComparison]::OrdinalIgnoreCase)) -Message 'ProcessStartInfo.WorkingDirectory is not the deployer executable directory.'
    Assert-True -Condition (-not $deployStartInfo.UseShellExecute) -Message 'WeaselDeployer must be launched directly without shell argument rewriting.'
    Assert-True -Condition (-not $deployStartInfo.CreateNoWindow) -Message 'WeaselDeployer must not suppress its interactive window.'
    $deployDescription = Get-DaMaoDeployerCommandDescription -Command $deployStartInfo.Arguments
    Assert-True -Condition ($deployDescription -eq 'Command=[/deploy] Length=7 CodePoints=[U+002F U+0064 U+0065 U+0070 U+006C U+006F U+0079]') -Message 'The /deploy command diagnostic does not expose its exact length and Unicode code points.'
    $syncStartInfo = New-DaMaoDeployerStartInfo -DeployerPath (Join-Path $fakeWeaselRoot 'WeaselDeployer.exe') -Command '/sync'
    Assert-True -Condition ([string]::Equals($syncStartInfo.Arguments, '/sync', [System.StringComparison]::Ordinal) -and $syncStartInfo.Arguments.Length -eq 5) -Message 'ProcessStartInfo.Arguments is not exactly /sync.'

    $invalidDeployerCommands = @(
        '',
        $null,
        ' /deploy',
        '/deploy ',
        '"/deploy"',
        "'/deploy'",
        "/deploy`t",
        "/deploy`r",
        "/deploy`n",
        '/DEPLOY'
    )
    foreach ($invalidCommand in $invalidDeployerCommands) {
        $invalidCommandMessage = $null
        try {
            [void](New-DaMaoDeployerStartInfo -DeployerPath (Join-Path $fakeWeaselRoot 'WeaselDeployer.exe') -Command $invalidCommand)
        }
        catch {
            $invalidCommandMessage = $_.Exception.Message
        }
        Assert-True -Condition ($invalidCommandMessage -match '^\[DM-DEPLOY-COMMAND-INVALID\]') -Message "An inexact WeaselDeployer command was accepted: $(Get-DaMaoDeployerCommandDescription -Command $invalidCommand)"
    }

    $guiOnlyLog = Join-Path $rimeLogRoot "damao-ime-gui-only-$([Guid]::NewGuid().ToString('N')).log"
    $guiOnlySnapshot = Get-DaMaoRimeLogSnapshot
    [System.IO.File]::WriteAllText($guiOnlyLog, "loading damao_wubi.schema.yaml`nloading build/weasel.yaml`n")
    $guiOnlyFailure = $null
    try {
        [void](Assert-DaMaoWorkspaceDeploymentLog -BeforeSnapshot $guiOnlySnapshot -SchemaId 'damao_wubi')
    }
    catch {
        $guiOnlyFailure = $_.Exception.Message
    }
    finally {
        Remove-Item -LiteralPath $guiOnlyLog -Force -ErrorAction SilentlyContinue
    }
    Assert-True -Condition ($guiOnlyFailure -match '^\[DM-DEPLOY-FAILED\].*does not confirm') -Message 'GUI-only Rime log output was accepted as a real workspace/schema deployment.'

    # A: A successful deployer main process is sufficient for success and returns promptly.
    $successfulProcess = Start-Process -FilePath $powershellExecutable -ArgumentList @('-NoProfile', '-Command', 'exit 0') -WindowStyle Hidden -PassThru
    $successfulStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $successfulMessage = $null
    try {
        Wait-DaMaoDeployerProcess -Process $successfulProcess -Command '/deploy' -TimeoutSeconds 10
    }
    catch {
        $successfulMessage = $_.Exception.Message
    }
    finally {
        $successfulStopwatch.Stop()
    }
    Assert-True -Condition ($null -eq $successfulMessage) -Message "A deployer main process that exited 0 was not accepted. Actual: $successfulMessage"
    Assert-True -Condition $successfulProcess.HasExited -Message 'The successful deployer main process was not observed as exited.'
    Assert-True -Condition ($successfulProcess.ExitCode -eq 0) -Message 'The successful deployer main process exit code was not preserved.'
    Assert-True -Condition ($successfulStopwatch.Elapsed.TotalSeconds -lt 5) -Message 'The wrapper kept waiting after the successful deployer main process exited.'

    # B: A resident process started by the deployer must not participate in normal success.
    $residentHelper = Join-Path $testRoot 'success-with-resident.ps1'
    $residentChildPidFile = Join-Path $testRoot 'success-resident-child.pid'
    [System.IO.File]::WriteAllLines($residentHelper, @(
        'param([string]$ChildPidPath)',
        '$child = Start-Process powershell -ArgumentList @(''-NoProfile'', ''-Command'', ''Start-Sleep -Seconds 20'') -WindowStyle Hidden -PassThru',
        '[System.IO.File]::WriteAllText($ChildPidPath, [string]$child.Id)',
        'exit 0'
    ))
    $residentProcess = Start-Process -FilePath $powershellExecutable -ArgumentList @('-NoProfile', '-File', $residentHelper, '-ChildPidPath', $residentChildPidFile) -WindowStyle Hidden -PassThru
    $residentPidDeadline = [DateTime]::UtcNow.AddSeconds(5)
    while (-not (Test-Path -LiteralPath $residentChildPidFile -PathType Leaf) -and [DateTime]::UtcNow -lt $residentPidDeadline) {
        Start-Sleep -Milliseconds 50
    }
    $residentPidRecorded = Test-Path -LiteralPath $residentChildPidFile -PathType Leaf
    Assert-True -Condition $residentPidRecorded -Message 'Successful deployer test did not create its resident process.'
    $residentChildPid = if ($residentPidRecorded) { [int][System.IO.File]::ReadAllText($residentChildPidFile) } else { -1 }
    $residentStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $residentMessage = $null
    try {
        Wait-DaMaoDeployerProcess -Process $residentProcess -Command '/deploy' -TimeoutSeconds 10
    }
    catch {
        $residentMessage = $_.Exception.Message
    }
    finally {
        $residentStopwatch.Stop()
    }
    Assert-True -Condition ($null -eq $residentMessage) -Message "A successful deployer with a resident process was not accepted. Actual: $residentMessage"
    Assert-True -Condition $residentProcess.HasExited -Message 'The successful deployer main process with a resident process was not observed as exited.'
    Assert-True -Condition ($residentStopwatch.Elapsed.TotalSeconds -lt 5) -Message 'The wrapper waited for a resident process after the deployer main process exited.'
    if ($residentChildPid -gt 0) {
        $residentChild = Get-Process -Id $residentChildPid -ErrorAction SilentlyContinue
        Assert-True -Condition ($null -ne $residentChild) -Message 'Normal success incorrectly terminated or waited for the resident process.'
        if ($null -ne $residentChild) {
            $residentChild.Kill()
            $residentChild.WaitForExit(5000) | Out-Null
        }
    }

    # C: Only a main-process timeout triggers complete process-tree cleanup.
    $timeoutHelper = Join-Path $testRoot 'timeout-parent.ps1'
    $timeoutChildPidFile = Join-Path $testRoot 'timeout-child.pid'
    [System.IO.File]::WriteAllLines($timeoutHelper, @(
        'param([string]$ChildPidPath)',
        '$child = Start-Process powershell -ArgumentList @(''-NoProfile'', ''-Command'', ''Start-Sleep -Seconds 20'') -WindowStyle Hidden -PassThru',
        '[System.IO.File]::WriteAllText($ChildPidPath, [string]$child.Id)',
        'Start-Sleep -Seconds 20'
    ))
    $timeoutProcess = Start-Process -FilePath $powershellExecutable -ArgumentList @('-NoProfile', '-File', $timeoutHelper, '-ChildPidPath', $timeoutChildPidFile) -WindowStyle Hidden -PassThru
    $childPidDeadline = [DateTime]::UtcNow.AddSeconds(5)
    while (-not (Test-Path -LiteralPath $timeoutChildPidFile -PathType Leaf) -and [DateTime]::UtcNow -lt $childPidDeadline) {
        Start-Sleep -Milliseconds 50
    }
    $childPidRecorded = Test-Path -LiteralPath $timeoutChildPidFile -PathType Leaf
    Assert-True -Condition $childPidRecorded -Message 'Timeout process did not create its child process.'
    $timeoutChildPid = if ($childPidRecorded) { [int][System.IO.File]::ReadAllText($timeoutChildPidFile) } else { -1 }

    $busyMessage = $null
    try {
        Assert-DaMaoDeployerAvailable -ProcessName 'powershell'
    }
    catch {
        $busyMessage = $_.Exception.Message
    }
    Assert-True -Condition ($busyMessage -match '^\[DM-DEPLOY-BUSY\]') -Message 'An existing deployer process did not produce DM-DEPLOY-BUSY.'

    $timeoutMessage = $null
    try {
        Wait-DaMaoDeployerProcess -Process $timeoutProcess -Command '/deploy' -TimeoutSeconds 1
    }
    catch {
        $timeoutMessage = $_.Exception.Message
    }
    finally {
        if (-not $timeoutProcess.HasExited) {
            $timeoutProcess.Kill()
        }
    }
    Assert-True -Condition ($timeoutMessage -match '^\[DM-DEPLOY-TIMEOUT\]') -Message "Deployment timeout did not produce DM-DEPLOY-TIMEOUT. Actual: $timeoutMessage"
    Assert-True -Condition ($timeoutMessage -match 'Latest Rime log location:') -Message 'Deployment timeout did not report the latest Rime log location.'
    Assert-True -Condition $timeoutProcess.HasExited -Message 'Timed-out deployer parent process was left running.'
    if ($timeoutChildPid -gt 0) {
        $childExitDeadline = [DateTime]::UtcNow.AddSeconds(5)
        while ($null -ne (Get-Process -Id $timeoutChildPid -ErrorAction SilentlyContinue) -and [DateTime]::UtcNow -lt $childExitDeadline) {
            Start-Sleep -Milliseconds 50
        }
        Assert-True -Condition ($null -eq (Get-Process -Id $timeoutChildPid -ErrorAction SilentlyContinue)) -Message 'Timed-out deployer child process was left running.'
    }

    $failedProcess = Start-Process -FilePath $powershellExecutable -ArgumentList @('-NoProfile', '-Command', 'exit 7') -WindowStyle Hidden -PassThru
    $nonzeroMessage = $null
    try {
        Wait-DaMaoDeployerProcess -Process $failedProcess -Command '/deploy' -TimeoutSeconds 10
    }
    catch {
        $nonzeroMessage = $_.Exception.Message
    }
    Assert-True -Condition ($nonzeroMessage -match '^\[DM-DEPLOY-FAILED\].*exit code 7') -Message 'Nonzero deployer exit did not remain classified as DM-DEPLOY-FAILED.'

    $schema = [System.IO.File]::ReadAllText((Join-Path $repoRoot 'schemas\damao_wubi.schema.yaml'))
    Assert-True -Condition ($schema -match '(?m)^\s*icon:\s*damao_wubi/branding/bigcat-ime\.ico\s*$') -Message 'Schema does not reference the IME-specific BigCat cat-head icon.'
    Assert-True -Condition ($schema -match '(?m)^\s*ascii_icon:\s*damao_wubi/branding/bigcat-ime\.ico\s*$') -Message 'Schema does not reuse the IME-specific BigCat cat-head icon in ASCII mode.'
    Assert-True -Condition ($schema -match '(?m)^\s*user_dict:\s*damao_wubi\s*$') -Message 'Schema does not isolate the DaMao Input Method user dictionary.'
    Assert-True -Condition ($schema -match '(?m)^\s*max_code_length:\s*4\s*$') -Message 'Schema does not keep the Wubi maximum code length at four.'
    Assert-True -Condition ($schema -match '(?m)^\s*auto_select:\s*true\s*$') -Message 'Schema does not auto-select candidates at the maximum code length.'
    Assert-True -Condition ($schema -notmatch '(?m)^\s*auto_select_unique_candidate:\s*true\s*$') -Message 'The installed schema must not auto-select unique candidates before reaching four codes.'
    Assert-True -Condition ($schema -match '(?m)^\s*enable_encoder:\s*false\s*$') -Message 'Automatic phrase encoding must remain disabled in the installed schema.'
    Assert-True -Condition ($schema -match '(?m)^\s*enable_sentence:\s*false\s*$') -Message 'Sentence generation must remain disabled in the installed schema.'
    Assert-True -Condition ($schema -match '(?m)^\s*-\s*\{\s*when:\s*composing,\s*accept:\s*Return,\s*send:\s*Escape\s*\}\s*$') -Message 'Composing Return must cancel the current code instead of committing raw input.'
    Assert-True -Condition ($schema -match '(?m)^\s*-\s*\{\s*when:\s*has_menu,\s*accept:\s*semicolon,\s*send:\s*2\s*\}\s*$') -Message 'Semicolon must select the second candidate when a menu exists.'
    Assert-True -Condition ($schema -match '(?m)^\s*-\s*\{\s*when:\s*has_menu,\s*accept:\s*apostrophe,\s*send:\s*3\s*\}\s*$') -Message 'Apostrophe must select the third candidate when a menu exists.'
    Assert-True -Condition ($schema -match '(?m)^\s*delimiter:\s*" ;''"\s*$') -Message 'Semicolon/apostrophe candidate shortcuts must not change the existing speller delimiter.'
    Assert-True -Condition ($schema -match '(?m)^\s*import_preset:\s*default\s*$') -Message 'The formal schema must retain the default key binder and punctuation presets.'
    Assert-True -Condition ($schema -notmatch 'key_bindings:/paging_with_comma_period') -Message 'Comma/period paging bindings must not bypass native punctuation commit behavior.'
    foreach ($preservedKeyBindingPreset in @('emacs_editing', 'move_by_word_with_tab', 'paging_with_minus_equal', 'numbered_mode_switch')) {
        Assert-True -Condition ($schema -match ('key_bindings:/' + [regex]::Escape($preservedKeyBindingPreset))) -Message "The formal schema no longer preserves the '$preservedKeyBindingPreset' default key bindings."
    }

    $processorMatch = [regex]::Match($schema, '(?ms)^  processors:\r?\n(?<items>(?:    - [^\r\n]+\r?\n)+)')
    $processors = if ($processorMatch.Success) { @([regex]::Matches($processorMatch.Groups['items'].Value, '(?m)^\s*-\s*(?<name>\S+)\s*$') | ForEach-Object { $_.Groups['name'].Value }) } else { @() }
    $expectedProcessors = @('ascii_composer', 'recognizer', 'key_binder', 'speller', 'punctuator', 'selector', 'navigator', 'express_editor')
    Assert-True -Condition (($processors -join ',') -ceq ($expectedProcessors -join ',')) -Message 'The processor order no longer lets key_binder guard Return and punctuator handle punctuation natively.'

    $segmentorMatch = [regex]::Match($schema, '(?ms)^  segmentors:\r?\n(?<items>(?:    - [^\r\n]+\r?\n)+)')
    $segmentors = if ($segmentorMatch.Success) { @([regex]::Matches($segmentorMatch.Groups['items'].Value, '(?m)^\s*-\s*(?<name>\S+)\s*$') | ForEach-Object { $_.Groups['name'].Value }) } else { @() }
    Assert-True -Condition ($segmentors -contains 'punct_segmentor') -Message 'The formal schema must retain punct_segmentor.'

    $translatorMatch = [regex]::Match($schema, '(?ms)^  translators:\r?\n(?<items>(?:    - [^\r\n]+\r?\n)+)')
    $translators = if ($translatorMatch.Success) { @([regex]::Matches($translatorMatch.Groups['items'].Value, '(?m)^\s*-\s*(?<name>\S+)\s*$') | ForEach-Object { $_.Groups['name'].Value }) } else { @() }
    Assert-True -Condition ($translators -contains 'punct_translator') -Message 'The formal schema must retain punct_translator.'
    Assert-True -Condition ($schema -notmatch '(?m)^\s*-\s*lua_processor(?:@\S+)?\s*$') -Message 'The two native input behavior fixes must not introduce a Lua processor.'

    $fullAlphaDiagnostic = ConvertTo-DaMaoFullAlphaDiagnosticSchema -SchemaContent $schema
    $fullAlphaNamePattern = '(?m)^  name:\s*"{0}"\s*$' -f [regex]::Escape("$damaoDisplayName Diagnostic 04 - Full Alpha")
    Assert-True -Condition ($fullAlphaDiagnostic -match $fullAlphaNamePattern) -Message '04-full-alpha does not have the required diagnostic name.'
    Assert-True -Condition ($fullAlphaDiagnostic -match '(?m)^  version:\s*"0\.1-diag-04"\s*$') -Message '04-full-alpha does not have the required diagnostic version.'
    $formalAlphaComparable = $schema -replace '(?m)^  name:[^\r\n]*$', '  name: <schema-identity>' -replace '(?m)^  version:[^\r\n]*$', '  version: <schema-identity>'
    $fullAlphaComparable = $fullAlphaDiagnostic -replace '(?m)^  name:[^\r\n]*$', '  name: <schema-identity>' -replace '(?m)^  version:[^\r\n]*$', '  version: <schema-identity>'
    Assert-True -Condition ($fullAlphaComparable -ceq $formalAlphaComparable) -Message '04-full-alpha differs from the formal Alpha schema outside schema/name and schema/version.'

    $diagnosticDirectory = Join-Path $repoRoot 'schemas\diagnostics'
    $diagnosticSchemas = @(Get-ChildItem -LiteralPath $diagnosticDirectory -File -Filter '*.schema.yaml')
    Assert-True -Condition ($diagnosticSchemas.Count -eq 12) -Message 'The expected twelve file-backed diagnostic schema variants were not found.'
    $diagnosticVersions = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($diagnosticSchema in $diagnosticSchemas) {
        $diagnosticContent = [System.IO.File]::ReadAllText($diagnosticSchema.FullName)
        Assert-True -Condition ([regex]::Matches($diagnosticContent, '(?m)^\s*schema_id:\s*damao_wubi\s*$').Count -eq 1) -Message "$($diagnosticSchema.Name) must keep schema_id damao_wubi."
        Assert-True -Condition ([regex]::Matches($diagnosticContent, '(?m)^\s*dictionary:\s*wubi86\s*$').Count -eq 1) -Message "$($diagnosticSchema.Name) must use exactly one wubi86 dictionary declaration."
        Assert-True -Condition ($diagnosticContent -notmatch '(?m)^\s*import_tables\s*:') -Message "$($diagnosticSchema.Name) must not introduce another dictionary table."
        $expectedDiagnosticVersion = if ($diagnosticSchema.Name -eq 'damao_wubi.00-minimal.schema.yaml') { '0\.1' } else { '0\.1-diag-[a-z0-9-]+' }
        $diagnosticVersionPattern = '(?m)^\s*version:\s*["'']?(?<version>{0})["'']?\s*$' -f $expectedDiagnosticVersion
        $diagnosticVersion = [regex]::Match($diagnosticContent, $diagnosticVersionPattern)
        Assert-True -Condition $diagnosticVersion.Success -Message "$($diagnosticSchema.Name) has no diagnostic version marker."
        if ($diagnosticVersion.Success) {
            Assert-True -Condition ($diagnosticVersions.Add($diagnosticVersion.Groups['version'].Value)) -Message "$($diagnosticSchema.Name) reuses a diagnostic version marker."
        }
    }

    $minimalControl = [System.IO.File]::ReadAllText((Join-Path $diagnosticDirectory 'damao_wubi.00-minimal.schema.yaml')) -replace "`r`n", "`n"
    $expectedMinimalControl = [string]::Join([char]10, @(
        'schema:',
        '  schema_id: damao_wubi',
        "  name: `"$damaoDisplayName Diagnostic 00 - Minimal`"",
        '  version: "0.1"',
        '',
        'engine:',
        '  processors:',
        '    - ascii_composer',
        '    - key_binder',
        '    - speller',
        '    - punctuator',
        '    - selector',
        '    - navigator',
        '    - express_editor',
        '  segmentors:',
        '    - ascii_segmentor',
        '    - abc_segmentor',
        '    - punct_segmentor',
        '    - fallback_segmentor',
        '  translators:',
        '    - punct_translator',
        '    - table_translator',
        '',
        'speller:',
        '  alphabet: zyxwvutsrqponmlkjihgfedcba',
        '',
        'translator:',
        '  dictionary: wubi86',
        '  enable_user_dict: false',
        '  enable_sentence: false',
        '',
        'punctuator:',
        '  import_preset: default',
        '',
        'key_binder:',
        '  import_preset: default'
    )) + [char]10
    Assert-True -Condition ($minimalControl -ceq $expectedMinimalControl) -Message 'The 00-minimal control is not content-identical to the known-good Minimal schema.'

    $spellerDiagnostic = [System.IO.File]::ReadAllText((Join-Path $diagnosticDirectory 'damao_wubi.01-speller.schema.yaml'))
    Assert-True -Condition ($spellerDiagnostic -match '(?m)^\s*delimiter:\s*" ;''"\s*$') -Message 'The first diagnostic variant does not restore the Alpha delimiter.'
    Assert-True -Condition ($spellerDiagnostic -match '(?m)^\s*max_code_length:\s*4\s*$') -Message 'The first diagnostic variant does not restore max_code_length.'
    Assert-True -Condition ($spellerDiagnostic -match '(?m)^\s*auto_select:\s*true\s*$') -Message 'The first diagnostic variant does not restore auto_select.'
    Assert-True -Condition ($spellerDiagnostic -notmatch '(?m)^switches:\s*$|^\s*-\s*recognizer\s*$|^\s*user_dict\s*:') -Message 'The first diagnostic variant contains settings outside the speller group.'

    $fourCodePatternDiagnostic = [System.IO.File]::ReadAllText((Join-Path $diagnosticDirectory 'damao_wubi.01c-four-code-pattern.schema.yaml'))
    Assert-True -Condition ($fourCodePatternDiagnostic -notmatch '(?m)^\s*max_code_length\s*:') -Message 'The four-code pattern diagnostic must not use max_code_length.'
    Assert-True -Condition ($fourCodePatternDiagnostic -match '(?m)^\s*auto_select:\s*true\s*$') -Message 'The four-code pattern diagnostic does not enable auto_select.'
    Assert-True -Condition ($fourCodePatternDiagnostic -match '(?m)^\s*auto_select_pattern:\s*"\^\[a-z\]\{4\}\$"\s*$') -Message 'The four-code pattern diagnostic does not use the exact four-letter match.'
    Assert-True -Condition ($fourCodePatternDiagnostic -notmatch '(?m)^\s*auto_select_unique_candidate\s*:') -Message 'The four-code pattern diagnostic must not set auto_select_unique_candidate.'

    $diagnosticScript = [System.IO.File]::ReadAllText((Join-Path $repoRoot 'scripts\Test-DaMaoSchemaVariant.ps1'))
    $normalInstallerScript = [System.IO.File]::ReadAllText((Join-Path $repoRoot 'scripts\Install-DaMao.ps1'))
    $environmentTestScript = [System.IO.File]::ReadAllText((Join-Path $repoRoot 'scripts\Test-DaMaoEnvironment.ps1'))
    Assert-True -Condition ($normalInstallerScript -match 'schemas\\damao_wubi\.schema\.yaml') -Message 'The normal installer does not use the formal schema source.'
    Assert-True -Condition ($normalInstallerScript -notmatch 'schemas\\diagnostics|schemas/diagnostics') -Message 'The normal installer references a development-only diagnostic schema path.'
    Assert-True -Condition ($normalInstallerScript -match 'Assert-DaMaoFormalDeployment') -Message 'The normal installer does not verify the formal compiled schema after deployment.'
    Assert-True -Condition ($environmentTestScript -match 'Result: success' -and $environmentTestScript -match 'DM-SMOKE-FAILED') -Message 'The Alpha environment smoke test does not expose clear overall success/failure output.'
    Assert-True -Condition ($diagnosticScript -notmatch 'Add-DaMaoSchemaSelection') -Message 'The schema diagnostic script must not modify schema_list.'
    Assert-True -Condition ($diagnosticScript -match 'Test-DaMaoSchemaRegistered\s+-DefaultCustomPath\s+\$defaultCustom') -Message 'The schema diagnostic script does not use structured schema registration detection.'
    Assert-True -Condition ($diagnosticScript -match 'TimeoutSeconds 120') -Message 'The schema diagnostic script does not retain the finite deployment timeout.'
    Assert-True -Condition ($diagnosticScript -match '''04-full-alpha''') -Message 'The schema diagnostic script does not accept 04-full-alpha.'
    Assert-True -Condition ($diagnosticScript -match 'Join-Path\s+\$repoRoot\s+''schemas\\damao_wubi\.schema\.yaml''') -Message '04-full-alpha does not use the formal Alpha schema as its source.'

    $commonScriptSource = [System.IO.File]::ReadAllText((Join-Path $repoRoot 'scripts\DaMao.Common.ps1'))
    Assert-True -Condition ($commonScriptSource -match '\$startInfo\.WorkingDirectory\s*=\s*Split-Path\s+-Parent\s+\$DeployerPath') -Message 'The deployer working directory is not derived from the executable path.'
    Assert-True -Condition ($commonScriptSource -match '\$startInfo\.Arguments\s*=\s*\$Command') -Message 'ProcessStartInfo.Arguments is not assigned the strictly validated command.'
    Assert-True -Condition ($commonScriptSource -match '\[System\.Diagnostics\.Process\]::Start\(\$startInfo\)') -Message 'WeaselDeployer is not launched directly from the validated ProcessStartInfo.'
    Assert-True -Condition ($commonScriptSource -notmatch '\$startInfo\.WindowStyle\s*=.*Hidden|\$startInfo\.CreateNoWindow\s*=\s*\$true') -Message 'WeaselDeployer must remain visible so interactive deployment UI cannot be suppressed.'
    Assert-True -Condition ($commonScriptSource -match '\$mainProcessExited\s*=\s*\$Process\.WaitForExit\(\$TimeoutSeconds\s*\*\s*1000\)') -Message 'The wrapper does not wait directly for the exact deployer main process.'

    $archiveSource = Join-Path $testRoot 'archive-source'
    $archiveSnapshots = Join-Path $archiveSource 'snapshots\source-01'
    New-Item -ItemType Directory -Path $archiveSnapshots -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $archiveSource 'manifest.json'), '{"format_version":1,"schema_id":"damao_wubi","snapshot_count":1}')
    [System.IO.File]::WriteAllText((Join-Path $archiveSnapshots 'damao_wubi.userdb.txt'), "# Rime user dictionary export`n")
    $testArchive = Join-Path $testRoot 'test-backup.zip'
    Compress-Archive -Path (Join-Path $archiveSource '*') -DestinationPath $testArchive
    & (Join-Path $repoRoot 'scripts\Restore-DaMaoUserDictionary.ps1') -Archive $testArchive -RimeUserDir $fakeUserDir -WeaselRoot $fakeWeaselRoot -WhatIf | Out-Null
}
finally {
    $safeTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
    if ($resolvedTestRoot.StartsWith($safeTempRoot, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $resolvedTestRoot)) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host 'DaMao tests passed.'
