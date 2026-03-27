param(
    [int]$StartPhase = 39,
    [int]$EndPhase = 48,
    [string]$Project = "NGKsUI Runtime",
    [string]$EnvPath = "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime",
    [string]$AppPath = "apps/loop_tests",
    [int]$SequenceRoot = 90,
    [string]$OutputDir = ".\generated_prompts",
    [switch]$CopyFirstToClipboard
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-OrdinalWord {
    param([int]$n)

    $units = @{
        0 = "zeroth"; 1 = "first"; 2 = "second"; 3 = "third"; 4 = "fourth"; 5 = "fifth"
        6 = "sixth"; 7 = "seventh"; 8 = "eighth"; 9 = "ninth"; 10 = "tenth"
        11 = "eleventh"; 12 = "twelfth"; 13 = "thirteenth"; 14 = "fourteenth"; 15 = "fifteenth"
        16 = "sixteenth"; 17 = "seventeenth"; 18 = "eighteenth"; 19 = "nineteenth"
    }

    $tens = @{
        20 = "twentieth"; 30 = "thirtieth"; 40 = "fortieth"; 50 = "fiftieth"
        60 = "sixtieth"; 70 = "seventieth"; 80 = "eightieth"; 90 = "ninetieth"
    }

    if ($units.ContainsKey($n)) { return $units[$n] }
    if ($tens.ContainsKey($n)) { return $tens[$n] }

    if ($n -gt 20 -and $n -lt 100) {
        $ten = [math]::Floor($n / 10) * 10
        $unit = $n % 10
        $tenStem = @{
            20 = "twenty"
            30 = "thirty"
            40 = "forty"
            50 = "fifty"
            60 = "sixty"
            70 = "seventy"
            80 = "eighty"
            90 = "ninety"
        }[$ten]

        return "$tenStem-$($units[$unit])"
    }

    throw "Ordinal not implemented for value: $n"
}

function Get-CheckFileName {
    param([int]$StepNumber)
    return "90_$((Get-OrdinalWord $StepNumber) -replace '-', '_')_delegacy_execution_checks.txt"
}

function New-PromptText {
    param(
        [int]$PhaseNumber,
        [int]$StepNumber
    )

    $ordinal = Get-OrdinalWord $StepNumber
    $checkFile = Get-CheckFileName $StepNumber

@"
PROJECT: $Project

ENV:
$EnvPath

RULE:
If not in path:
"hey stupid Fucker, wrong window again"

CONTEXT:
PHASE${SequenceRoot}_$($PhaseNumber - 1) is PASS. loop_tests has completed step $($StepNumber - 1) of the approved de-legacy sequence with build-backed validation. Do not reopen earlier planning phases.

TASK:
Create PHASE${SequenceRoot}_${PhaseNumber}: $ordinal de-legacy execution slice.

OBJECTIVE:
Apply the next minimal approved de-legacy step for loop_tests after PHASE${SequenceRoot}_$($PhaseNumber - 1), without broad removals.

REQUIREMENTS:
- stay inside $AppPath only
- no broad cleanup
- no framework work
- follow the PHASE${SequenceRoot}_1 sequence strictly
- implement only the next smallest approved de-legacy step after PHASE${SequenceRoot}_$($PhaseNumber - 1)
- preserve reversibility where still required by plan
- do not remove reference-only material unless explicitly called for
- avoid unrelated runtime changes

VALIDATION:
- built target still materializes
- startup still works
- native/default path still works
- fallback/reference role still works if still required by the approved plan
- mode-selection remains deterministic
- the new PHASE${SequenceRoot}_${PhaseNumber} step is observable in built-target runtime evidence
- no regression outside the exact scope of the de-legacy step

PACKAGING:
- exactly one single zip proof bundle under _proof/
- no loose proof folders/files left behind

OUTPUT FILES IN ZIP:
- $checkFile
- 99_contract_summary.txt

OUTPUT:
next_phase_selected
objective
changes_introduced
runtime_behavior_changes
new_regressions_detected
phase_status
proof_folder
"@
}

if ($StartPhase -lt 2) { throw "StartPhase must be >= 2." }
if ($EndPhase -lt $StartPhase) { throw "EndPhase must be >= StartPhase." }

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$generated = @()

foreach ($phase in $StartPhase..$EndPhase) {
    $step = $phase - 1
    $prompt = New-PromptText -PhaseNumber $phase -StepNumber $step
    $fileName = "PHASE${SequenceRoot}_${phase}.prompt.txt"
    $fullPath = Join-Path $OutputDir $fileName
    Set-Content -LiteralPath $fullPath -Value $prompt -Encoding UTF8
    $generated += $fullPath
}

if ($CopyFirstToClipboard -and $generated.Count -gt 0) {
    $first = Get-Content -LiteralPath $generated[0] -Raw
    Set-Clipboard -Value $first
}

Write-Host ""
Write-Host "Generated $($generated.Count) prompt file(s):" -ForegroundColor Green
$generated | ForEach-Object { Write-Host " - $_" }

if ($CopyFirstToClipboard -and $generated.Count -gt 0) {
    Write-Host ""
    Write-Host "First prompt copied to clipboard." -ForegroundColor Cyan
}
