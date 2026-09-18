[CmdletBinding()]
param(
    [string]$RimeDll = 'C:\Program Files\Rime\weasel-0.17.4\rime.dll',
    [string]$RimeSharedDataDir,
    [string]$WubiDictionary = (Join-Path $env:APPDATA 'Rime\wubi86.dict.yaml'),
    [ValidateRange(40, 200)][int]$CandidateLimit = 100,
    [ValidateRange(1, 50)][int]$TrainingRounds = 20,
    [ValidateRange(1, 30)][int]$NewPhraseRounds = 8,
    [switch]$KeepTestData
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($RimeSharedDataDir)) {
    $RimeSharedDataDir = Join-Path (Split-Path -Parent $RimeDll) 'data'
}

function Assert-Runtime {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) { throw "[$Code] $Message" }
}

function Get-CharacterCount {
    param([Parameter(Mandatory = $true)][string]$Text)
    return [System.Globalization.StringInfo]::ParseCombiningCharacters($Text).Count
}

function New-UnicodeText {
    param([Parameter(Mandatory = $true)][int[]]$CodePoints)
    return -join @($CodePoints | ForEach-Object { [char]$_ })
}

function Test-HanCharacter {
    param([Parameter(Mandatory = $true)][string]$Text)
    if ((Get-CharacterCount -Text $Text) -ne 1 -or $Text.Length -ne 1) { return $false }
    $value = [int][char]$Text[0]
    return $value -ge 0x3400 -and $value -le 0x9fff
}

function Test-ObviousRepeatedPhrase {
    param([Parameter(Mandatory = $true)][string]$Text)
    $length = Get-CharacterCount -Text $Text
    if ($length -lt 2 -or $Text.Length -ne $length) { return $false }
    if (@($Text.ToCharArray() | Select-Object -Unique).Count -eq 1) { return $true }
    if ($length % 2 -eq 0) {
        $half = [int]($length / 2)
        return $Text.Substring(0, $half) -ceq $Text.Substring($half)
    }
    return $false
}

function Get-DictionaryCorpus {
    param([Parameter(Mandatory = $true)][string]$DictionaryPath)

    $singleCounts = @{}
    $phraseCounts = @{}
    $words = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($line in [System.IO.File]::ReadLines($DictionaryPath, [System.Text.Encoding]::UTF8)) {
        $fields = $line.Split([char]9)
        if ($fields.Count -lt 2 -or $fields[0].StartsWith('#')) { continue }
        $text = $fields[0]
        $code = $fields[1].Trim()
        if ($code -notmatch '^[a-z]{1,4}$') { continue }
        $words.Add($text) | Out-Null
        if (Test-HanCharacter -Text $text) {
            $target = $singleCounts
        }
        elseif ((Get-CharacterCount -Text $text) -ge 2) {
            $target = $phraseCounts
        }
        else {
            continue
        }
        for ($prefixLength = 1; $prefixLength -le $code.Length; $prefixLength++) {
            $prefix = $code.Substring(0, $prefixLength)
            if (-not $target.ContainsKey($prefix)) { $target[$prefix] = 0 }
            $target[$prefix]++
        }
    }
    return [pscustomobject]@{
        SingleCounts = $singleCounts
        PhraseCounts = $phraseCounts
        Words = $words
    }
}

function Get-UserDbSnapshot {
    param([Parameter(Mandatory = $true)][string]$UserDataDir)

    $path = Get-ChildItem -LiteralPath (Join-Path $UserDataDir 'sync') `
        -Filter 'damao_wubi_alpha03.userdb.txt' -File -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $path) {
        return [pscustomobject]@{ Path = $null; Records = @(); Provisional = @() }
    }
    $records = @(
        Get-Content -LiteralPath $path -Encoding UTF8 |
            Where-Object { $_ -and -not $_.StartsWith('#') } |
            ForEach-Object {
                $fields = $_.Split([char]9)
                if ($fields.Count -ge 2) {
                    $value = if ($fields.Count -ge 3) { $fields[2] } else { '' }
                    $commits = if ($value -match '(?:^|\s)c=(-?\d+)(?:\s|$)') { [int]$Matches[1] } else { $null }
                    [pscustomobject]@{
                        Code = $fields[0]
                        Text = $fields[1]
                        Value = $value
                        Commits = $commits
                    }
                }
            }
    )
    return [pscustomobject]@{
        Path = $path
        Records = $records
        Provisional = @($records | Where-Object { $_.Commits -eq 0 })
    }
}

function Sync-Snapshot {
    param([Parameter(Mandatory = $true)][string]$UserDataDir)
    Assert-Runtime ([DaMaoRimeAlpha03Native]::SyncUserData()) 'DM-A03-LR-SYNC' `
        'librime failed to export the isolated Alpha 0.3 userdb.'
    return Get-UserDbSnapshot -UserDataDir $UserDataDir
}

function Get-ProvisionalVisibility {
    param(
        [Parameter(Mandatory = $true)][UInt64]$Session,
        [Parameter(Mandatory = $true)][object[]]$Records
    )

    $prefix = ([string][char]0x7f) + 'enc' + ([string][char]0x1f)
    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($record in $Records) {
        if (-not $record.Code.StartsWith($prefix, [StringComparison]::Ordinal)) { continue }
        $code = $record.Code.Substring($prefix.Length).Trim()
        if ($code -notmatch '^[a-z]{1,4}$') { continue }
        $menu = @([DaMaoRimeAlpha03Native]::Candidates($Session, $code, $CandidateLimit))
        $rank = [Array]::IndexOf($menu, $record.Text)
        $result.Add([pscustomobject]@{ Code = $code; Text = $record.Text; Rank = $rank })
    }
    return $result.ToArray()
}

function Find-SingleLearningCase {
    param(
        [Parameter(Mandatory = $true)][UInt64]$Session,
        [Parameter(Mandatory = $true)][hashtable]$SingleCounts,
        [Parameter(Mandatory = $true)][ValidateRange(1, 4)][int]$CodeLength
    )

    $codes = @($SingleCounts.GetEnumerator() |
        Where-Object { $_.Key.Length -eq $CodeLength -and $_.Value -ge 2 -and $_.Key -notmatch '^z' } |
        Sort-Object @{ Expression = 'Value'; Descending = $true }, @{ Expression = 'Key'; Descending = $false } |
        ForEach-Object Key)
    foreach ($code in $codes) {
        $menu = @([DaMaoRimeAlpha03Native]::Candidates($Session, $code, $CandidateLimit))
        $singles = @($menu | Where-Object { Test-HanCharacter -Text $_ })
        if ($singles.Count -lt 2) { continue }
        # A one-key completion cannot displace the exact one-key candidate, so
        # choose a later collision and verify that learning raises it within
        # the completion tier. Exact two/four-code collisions may reach rank 0.
        $targetOrdinal = if ($singles.Count -ge 3) { 2 } else { 1 }
        $target = $singles[$targetOrdinal]
        $rank = [Array]::IndexOf($menu, $target)
        if ($rank -gt 0) {
            return [pscustomobject]@{ Category = "$CodeLength-code"; Code = $code; Target = $target; BeforeRank = $rank }
        }
    }
    throw "[DM-A03-LR-SINGLE] No non-first single candidate found for code length $CodeLength."
}

function Find-PhraseLearningCases {
    param(
        [Parameter(Mandatory = $true)][UInt64]$Session,
        [Parameter(Mandatory = $true)][hashtable]$PhraseCounts,
        [ValidateRange(1, 8)][int]$Count = 3
    )

    $result = [System.Collections.Generic.List[object]]::new()
    $codes = @($PhraseCounts.GetEnumerator() |
        Where-Object { $_.Value -ge 3 } |
        Sort-Object @{ Expression = 'Value'; Descending = $true }, @{ Expression = 'Key'; Descending = $false } |
        ForEach-Object Key)
    foreach ($code in $codes) {
        $menu = @([DaMaoRimeAlpha03Native]::Candidates($Session, $code, $CandidateLimit))
        $phrases = @($menu | Where-Object { (Get-CharacterCount -Text $_) -ge 2 })
        if ($phrases.Count -lt 2) { continue }
        $target = $phrases[1]
        $rank = [Array]::IndexOf($menu, $target)
        if ($rank -gt 0) {
            $result.Add([pscustomobject]@{ Code = $code; Target = $target; BeforeRank = $rank })
            if ($result.Count -ge $Count) { break }
        }
    }
    if ($result.Count -lt $Count) {
        throw "[DM-A03-LR-PHRASE] Only $($result.Count) existing phrase cases were found; expected $Count."
    }
    return $result.ToArray()
}

function Train-Case {
    param(
        [Parameter(Mandatory = $true)][object]$Case,
        [Parameter(Mandatory = $true)][int]$Rounds
    )

    $session = [DaMaoRimeAlpha03Native]::CreateSession('damao_wubi_alpha03')
    try {
        for ($round = 0; $round -lt $Rounds; $round++) {
            $committed = [DaMaoRimeAlpha03Native]::CommitCandidate(
                $session, $Case.Code, $Case.Target, $CandidateLimit)
            Assert-Runtime ($committed -ceq $Case.Target) 'DM-A03-LR-TRAIN' `
                "Commit mismatch for $($Case.Code)/$($Case.Target): $committed"
        }
        $menu = @([DaMaoRimeAlpha03Native]::Candidates($session, $Case.Code, $CandidateLimit))
        $Case | Add-Member -NotePropertyName TrainedRank -NotePropertyValue ([Array]::IndexOf($menu, $Case.Target)) -Force
        Assert-Runtime ($Case.TrainedRank -ge 0 -and $Case.TrainedRank -lt $Case.BeforeRank) 'DM-A03-LR-TRAIN' `
            "Learning did not raise $($Case.Target) for $($Case.Code): $($Case.BeforeRank) -> $($Case.TrainedRank)."
    }
    finally {
        [DaMaoRimeAlpha03Native]::DestroySession($session)
    }
}

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw '[DM-A03-LR-00] The Alpha 0.3 learning runtime requires Windows.'
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$schemaSource = Join-Path $repoRoot 'schemas\damao_wubi_alpha03.schema.yaml'
$nativeSource = Join-Path $PSScriptRoot 'DaMaoRimeAlpha03Native.cs'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "damao-alpha03-learning-$([Guid]::NewGuid().ToString('N'))"
$userDir = Join-Path $testRoot 'Rime'
$buildDir = Join-Path $userDir 'build'

foreach ($requiredPath in @($RimeDll, $WubiDictionary, $schemaSource, $nativeSource)) {
    Assert-Runtime (Test-Path -LiteralPath $requiredPath -PathType Leaf) 'DM-A03-LR-00' `
        "Required runtime input is missing: $requiredPath"
}
Assert-Runtime (Test-Path -LiteralPath $RimeSharedDataDir -PathType Container) 'DM-A03-LR-00' `
    "Rime shared data directory is missing: $RimeSharedDataDir"

try {
    New-Item -ItemType Directory -Path $userDir, $buildDir -Force | Out-Null
    Copy-Item -LiteralPath $schemaSource -Destination (Join-Path $userDir 'damao_wubi_alpha03.schema.yaml')
    Copy-Item -LiteralPath $WubiDictionary -Destination (Join-Path $userDir 'wubi86.dict.yaml')
    [System.IO.File]::WriteAllText(
        (Join-Path $userDir 'default.custom.yaml'),
        "patch:`n  schema_list:`n    - schema: damao_wubi_alpha03`n",
        [System.Text.UTF8Encoding]::new($false)
    )

    Add-Type -Path $nativeSource
    [DaMaoRimeAlpha03Native]::Load($RimeDll, $RimeSharedDataDir, $userDir, $buildDir)
    Assert-Runtime ([DaMaoRimeAlpha03Native]::DeployWorkspace()) 'DM-A03-LR-01' `
        'librime failed to build the isolated Alpha 0.3 workspace.'
    foreach ($artifact in @('damao_wubi_alpha03.schema.yaml', 'wubi86.table.bin')) {
        Assert-Runtime (Test-Path -LiteralPath (Join-Path $buildDir $artifact) -PathType Leaf) `
            'DM-A03-LR-01' "Missing isolated build artifact: $artifact"
    }
    [DaMaoRimeAlpha03Native]::StartService()

    $corpus = Get-DictionaryCorpus -DictionaryPath $WubiDictionary
    $discoverySession = [DaMaoRimeAlpha03Native]::CreateSession('damao_wubi_alpha03')
    try {
        $singleCases = @(1..4 | ForEach-Object {
            Find-SingleLearningCase -Session $discoverySession -SingleCounts $corpus.SingleCounts -CodeLength $_
        })
        $phraseCases = @(Find-PhraseLearningCases -Session $discoverySession -PhraseCounts $corpus.PhraseCounts -Count 3)
    }
    finally {
        [DaMaoRimeAlpha03Native]::DestroySession($discoverySession)
    }

    foreach ($case in $singleCases) { Train-Case -Case $case -Rounds $TrainingRounds }
    $afterSingles = Sync-Snapshot -UserDataDir $userDir
    foreach ($case in $singleCases) {
        $record = @($afterSingles.Records | Where-Object { $_.Text -ceq $case.Target -and $_.Commits -gt 0 })
        Assert-Runtime ($record.Count -gt 0) 'DM-A03-LR-02' `
            "Learned single is absent from userdb: $($case.Target)"
    }

    [DaMaoRimeAlpha03Native]::Restart()
    $singlePersistenceSession = [DaMaoRimeAlpha03Native]::CreateSession('damao_wubi_alpha03')
    try {
        foreach ($case in $singleCases) {
            $menu = @([DaMaoRimeAlpha03Native]::Candidates($singlePersistenceSession, $case.Code, $CandidateLimit))
            $rank = [Array]::IndexOf($menu, $case.Target)
            $case | Add-Member -NotePropertyName PhasePersistentRank -NotePropertyValue $rank -Force
            Assert-Runtime ($rank -ge 0 -and $rank -lt $case.BeforeRank) 'DM-A03-LR-02' `
                "Single learning did not persist for $($case.Code)/$($case.Target): rank=$rank."
        }
    }
    finally {
        [DaMaoRimeAlpha03Native]::DestroySession($singlePersistenceSession)
    }

    foreach ($case in $phraseCases) { Train-Case -Case $case -Rounds $TrainingRounds }
    $afterPhrases = Sync-Snapshot -UserDataDir $userDir
    foreach ($case in $phraseCases) {
        $record = @($afterPhrases.Records | Where-Object { $_.Text -ceq $case.Target -and $_.Commits -gt 0 })
        Assert-Runtime ($record.Count -gt 0) 'DM-A03-LR-03' `
            "Learned existing phrase is absent from userdb: $($case.Target)"
    }

    [DaMaoRimeAlpha03Native]::Restart()
    $phrasePersistenceSession = [DaMaoRimeAlpha03Native]::CreateSession('damao_wubi_alpha03')
    try {
        foreach ($case in $phraseCases) {
            $menu = @([DaMaoRimeAlpha03Native]::Candidates($phrasePersistenceSession, $case.Code, $CandidateLimit))
            $rank = [Array]::IndexOf($menu, $case.Target)
            $case | Add-Member -NotePropertyName PhasePersistentRank -NotePropertyValue $rank -Force
            Assert-Runtime ($rank -ge 0 -and $rank -lt $case.BeforeRank) 'DM-A03-LR-03' `
                "Existing phrase learning did not persist for $($case.Code)/$($case.Target): rank=$rank."
        }
    }
    finally {
        [DaMaoRimeAlpha03Native]::DestroySession($phrasePersistenceSession)
    }

    $u = @{
        Whale = New-UnicodeText @(0x9CB8)
        Boat = New-UnicodeText @(0x821F)
        Egret = New-UnicodeText @(0x9E6D)
        Cloud = New-UnicodeText @(0x4E91)
        Bay = New-UnicodeText @(0x6E7E)
        ClearSky = New-UnicodeText @(0x9701)
        Star = New-UnicodeText @(0x661F)
        Port = New-UnicodeText @(0x6E2F)
    }
    $newPhraseCases = @(
        [pscustomobject]@{ Target = $u.Whale + $u.Boat; Code = 'qgte'; Chars = @(@($u.Whale, 'qgy'), @($u.Boat, 'tei')); Length = 2 },
        [pscustomobject]@{ Target = $u.Egret + $u.Cloud + $u.Bay; Code = 'kfiy'; Chars = @(@($u.Egret, 'khtg'), @($u.Cloud, 'fcu'), @($u.Bay, 'iyo')); Length = 3 },
        [pscustomobject]@{ Target = $u.ClearSky + $u.Cloud + $u.Star + $u.Port; Code = 'ffji'; Chars = @(@($u.ClearSky, 'fyj'), @($u.Cloud, 'fcu'), @($u.Star, 'jtg'), @($u.Port, 'iawn')); Length = 4 }
    )

    foreach ($case in $newPhraseCases) {
        Assert-Runtime (-not $corpus.Words.Contains($case.Target)) 'DM-A03-LR-04' `
            "Synthetic phrase already exists in wubi86: $($case.Target)"
        $session = [DaMaoRimeAlpha03Native]::CreateSession('damao_wubi_alpha03')
        try {
            $cold = @([DaMaoRimeAlpha03Native]::Candidates($session, $case.Code, $CandidateLimit))
            Assert-Runtime ([Array]::IndexOf($cold, $case.Target) -lt 0) 'DM-A03-LR-04' `
                "Synthetic phrase was not cold: $($case.Target)/$($case.Code)"
            foreach ($character in $case.Chars) {
                $committed = [DaMaoRimeAlpha03Native]::CommitCandidate(
                    $session, [string]$character[1], [string]$character[0], $CandidateLimit)
                Assert-Runtime ($committed -ceq [string]$character[0]) 'DM-A03-LR-05' `
                    "Character commit mismatch while constructing $($case.Target)."
            }
            $menu = @([DaMaoRimeAlpha03Native]::Candidates($session, $case.Code, $CandidateLimit))
            $case | Add-Member -NotePropertyName BeforeRank -NotePropertyValue ([Array]::IndexOf($menu, $case.Target)) -Force
            Assert-Runtime ($case.BeforeRank -ge 0) 'DM-A03-LR-05' `
                "UnityTableEncoder did not create $($case.Target)/$($case.Code)."
        }
        finally {
            [DaMaoRimeAlpha03Native]::DestroySession($session)
        }
    }

    $afterConstruction = Sync-Snapshot -UserDataDir $userDir
    foreach ($case in $newPhraseCases) {
        $record = @($afterConstruction.Provisional | Where-Object { $_.Text -ceq $case.Target })
        Assert-Runtime ($record.Count -gt 0) 'DM-A03-LR-06' `
            "Constructed phrase has no c=0 provisional entry: $($case.Target)"
    }

    $visibilitySession = [DaMaoRimeAlpha03Native]::CreateSession('damao_wubi_alpha03')
    try {
        $provisionalVisibility = @(Get-ProvisionalVisibility -Session $visibilitySession -Records $afterConstruction.Provisional)
    }
    finally {
        [DaMaoRimeAlpha03Native]::DestroySession($visibilitySession)
    }

    foreach ($case in $newPhraseCases) { Train-Case -Case $case -Rounds $NewPhraseRounds }
    $finalSnapshot = Sync-Snapshot -UserDataDir $userDir
    foreach ($case in $newPhraseCases) {
        $record = @($finalSnapshot.Records | Where-Object { $_.Text -ceq $case.Target -and $_.Commits -ge $NewPhraseRounds })
        Assert-Runtime ($record.Count -gt 0) 'DM-A03-LR-07' `
            "Constructed phrase commits did not grow as expected: $($case.Target)"
    }

    [DaMaoRimeAlpha03Native]::Restart()
    $persistenceSession = [DaMaoRimeAlpha03Native]::CreateSession('damao_wubi_alpha03')
    try {
        foreach ($case in @($singleCases) + @($phraseCases) + @($newPhraseCases)) {
            $menu = @([DaMaoRimeAlpha03Native]::Candidates($persistenceSession, $case.Code, $CandidateLimit))
            $rank = [Array]::IndexOf($menu, $case.Target)
            $case | Add-Member -NotePropertyName FinalRank -NotePropertyValue $rank -Force
            Assert-Runtime ($rank -ge 0) 'DM-A03-LR-08' `
                "Learned entry disappeared after final restart: $($case.Code)/$($case.Target)."
        }
        foreach ($case in $newPhraseCases) {
            Assert-Runtime ($case.FinalRank -le $case.BeforeRank) 'DM-A03-LR-08' `
                "New phrase learning did not persist for $($case.Code)/$($case.Target): rank=$($case.FinalRank)."
        }
        $finalProvisionalVisibility = @(Get-ProvisionalVisibility -Session $persistenceSession -Records $finalSnapshot.Provisional)
    }
    finally {
        [DaMaoRimeAlpha03Native]::DestroySession($persistenceSession)
    }

    $singleProvisional = $afterSingles.Provisional.Count
    $phraseProvisionalDelta = $afterPhrases.Provisional.Count - $afterSingles.Provisional.Count
    $constructionProvisionalDelta = $afterConstruction.Provisional.Count - $afterPhrases.Provisional.Count
    $trainingProvisionalDelta = $finalSnapshot.Provisional.Count - $afterConstruction.Provisional.Count
    $visibleProvisional = @($provisionalVisibility | Where-Object { $_.Rank -ge 0 })
    $topTenProvisional = @($provisionalVisibility | Where-Object { $_.Rank -ge 0 -and $_.Rank -lt 10 })
    $obviousRepeatedEntries = @($finalSnapshot.Provisional | Where-Object {
        Test-ObviousRepeatedPhrase -Text $_.Text
    } | ForEach-Object Text | Sort-Object -Unique)
    $visibleObviousRepeated = @($finalProvisionalVisibility | Where-Object {
        $_.Rank -ge 0 -and $_.Text -in $obviousRepeatedEntries
    })

    Write-Host 'Alpha 0.3 native learning runtime passed.'
    Write-Host "Single learning ($TrainingRounds selections each):"
    foreach ($case in $singleCases) {
        Write-Host "  $($case.Category) $($case.Code)/$($case.Target): $($case.BeforeRank) -> $($case.TrainedRank), phase-restart=$($case.PhasePersistentRank), final=$($case.FinalRank)"
    }
    Write-Host "Existing phrase learning ($TrainingRounds selections each):"
    foreach ($case in $phraseCases) {
        Write-Host "  $($case.Code)/$($case.Target): $($case.BeforeRank) -> $($case.TrainedRank), phase-restart=$($case.PhasePersistentRank), final=$($case.FinalRank)"
    }
    Write-Host "Automatic phrase construction ($NewPhraseRounds whole-phrase selections):"
    foreach ($case in $newPhraseCases) {
        Write-Host "  $($case.Length)-char $($case.Target)/$($case.Code): constructed=$($case.BeforeRank), trained=$($case.TrainedRank), restart=$($case.FinalRank)"
    }
    Write-Host "Provisional c=0 counts: singles=$singleProvisional; existing-phrase delta=$phraseProvisionalDelta; construction delta=$constructionProvisionalDelta; new-phrase-training delta=$trainingProvisionalDelta; final=$($finalSnapshot.Provisional.Count)"
    Write-Host "Provisional visibility before whole-phrase training: visible=$($visibleProvisional.Count)/$($provisionalVisibility.Count); Top-10=$($topTenProvisional.Count)"
    Write-Host "Obvious repeated provisional entries: $($obviousRepeatedEntries.Count); visible after restart=$($visibleObviousRepeated.Count); text=$($obviousRepeatedEntries -join ',')"
    Write-Host "Isolated userdb export: $($finalSnapshot.Path)"
    Write-Host "Isolated runtime root: $testRoot"
}
finally {
    try { [DaMaoRimeAlpha03Native]::Shutdown() } catch {}
    if (-not $KeepTestData -and (Test-Path -LiteralPath $testRoot)) {
        $resolvedRoot = [System.IO.Path]::GetFullPath($testRoot)
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        if ($resolvedRoot.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase)) {
            try { Remove-Item -LiteralPath $resolvedRoot -Recurse -Force }
            catch { Write-Warning "Temporary Alpha 0.3 runtime data could not be removed: $resolvedRoot" }
        }
    }
}
