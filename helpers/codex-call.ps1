# codex-call.ps1 — wrapper for Codex CLI invocation per the cross-ai-review cycle.
# Cross-platform note: this is the PowerShell version; the bash equivalent
# (codex-call.sh) implements the same interface for Unix-like shells.
#
# Interface (same as .sh):
#   -Layer <int>            Layer index. Recorded in per-call .md header.
#   -Primitive <string>     Primitive code: P1 / P2 / P3 / P4 / P5 / P6.
#   -Phase <string>         One of: semantic-iterate | semantic-cross-check | semantic-verify
#   -Outer <int>            Outer cycle index (1, 2, 3).
#   -Iter <int>             Inner iteration index. Required for -Role iterating.
#   -Role <iterating|cross-check|verify>
#   -Model <slug>           Requested model slug.
#   -ThinkingLevel <fast|standard|deep>
#                           Abstract thinking level. Helper translates to model_reasoning_effort.
#   -PromptFile <path>      Path to file containing the reviewer prompt.
#   -Schema <path>          Path to JSON schema (default: ~/.claude/cross-ai-review-schema.json).
#   -RunDir <path>          Run directory.
#   -CallStarted <ts>       Timestamp prefix for output filenames.
#
# No override flag exists for actual-model extraction failure — the cycle halts as
# Class E unconditionally per methodology § Actual-model extraction failure.
#
# Output: JSON status object on stdout. Same exit codes (0=ok, 1-7=halt classes A-G, 8=invalid args).

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][int]$Layer,
    [Parameter(Mandatory=$true)][ValidateSet("P1","P2","P3","P4","P5","P6")][string]$Primitive,
    [Parameter(Mandatory=$true)][ValidateSet("semantic-iterate","semantic-cross-check","semantic-verify")][string]$Phase,
    [Parameter(Mandatory=$true)][int]$Outer,
    [int]$Iter,
    [Parameter(Mandatory=$true)][ValidateSet("iterating","cross-check","verify")][string]$Role,
    [Parameter(Mandatory=$true)][string]$Model,
    [Parameter(Mandatory=$true)][ValidateSet("fast","standard","deep")][string]$ThinkingLevel,
    [Parameter(Mandatory=$true)][string]$PromptFile,
    [string]$Schema = "$HOME\.claude\cross-ai-review-schema.json",
    [Parameter(Mandatory=$true)][string]$RunDir,
    [Parameter(Mandatory=$true)][string]$CallStarted
)

# Validate iterating requires --iter
if ($Role -eq "iterating" -and -not $PSBoundParameters.ContainsKey('Iter')) {
    Write-Output '{"error": "-Iter required for -Role iterating"}'
    exit 8
}

if (-not (Test-Path $PromptFile)) {
    Write-Output "{`"error`": `"prompt file not found: $PromptFile`"}"
    exit 8
}

# Translate thinking level → Codex native model_reasoning_effort
$NativeReasoning = switch ($ThinkingLevel) {
    "fast"     { "low" }
    "standard" { "medium" }
    "deep"     { "high" }
}

$TmpOut = Join-Path $RunDir ".tmp-$CallStarted-out.json"
$TmpErr = Join-Path $RunDir ".tmp-$CallStarted-err"
$Prompt = Get-Content $PromptFile -Raw

# Invoke Codex with non-negotiable flags.
$ArgList = @(
    "exec", "-s", "read-only", "--skip-git-repo-check",
    "-m", $Model, "-c", "model_reasoning_effort=$NativeReasoning",
    "--output-schema", $Schema,
    "-o", $TmpOut,
    $Prompt
)

$ProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
$ProcessInfo.FileName = "codex"
$ProcessInfo.RedirectStandardInput = $true
$ProcessInfo.RedirectStandardError = $true
$ProcessInfo.UseShellExecute = $false
foreach ($arg in $ArgList) { $ProcessInfo.ArgumentList.Add($arg) }

$Proc = New-Object System.Diagnostics.Process
$Proc.StartInfo = $ProcessInfo
$Proc.Start() | Out-Null
$Proc.StandardInput.Close()  # Equivalent to < /dev/null
$StderrCapture = $Proc.StandardError.ReadToEnd()
$Proc.WaitForExit()
$CodexExit = $Proc.ExitCode
$StderrCapture | Out-File -FilePath $TmpErr -Encoding UTF8 -NoNewline

# Halt-signal classification
$HaltClass = ""
$OutSize = if (Test-Path $TmpOut) { (Get-Item $TmpOut).Length } else { 0 }
if ($CodexExit -ne 0 -or $OutSize -eq 0) {
    if ($StderrCapture -match "(?i)payment required|usage limit|monthly quota|daily quota") { $HaltClass = "B" }
    elseif ($StderrCapture -match "(?i)service overloaded|try again later" -or $StderrCapture -match "503|529") { $HaltClass = "C" }
    elseif ($StderrCapture -match "(?i)Requested entity was not found|ModelNotFoundError|404") { $HaltClass = "D" }
    elseif ($StderrCapture -match "(?i)401|403|authentication|permission denied") { $HaltClass = "A" }
    elseif ($StderrCapture -match "invalid_json_schema|invalid_request_error|""status""\s*:\s*400") { $HaltClass = "A" }
    else { $HaltClass = "G" }
}

# Actual-model extraction (Class E check)
$ModelActual = ""
if ($StderrCapture) {
    $match = [regex]::Match($StderrCapture, 'model[ =:"]*([a-z0-9.-]+)')
    if ($match.Success) { $ModelActual = $match.Groups[1].Value }
}

# Class E — extraction failure halts unconditionally (no override in v1)
if (-not $ModelActual -and -not $HaltClass) {
    $HaltClass = "E"
    $ModelActual = "extraction-failed"
}
elseif ($ModelActual -and $ModelActual -ne $Model) {
    $HaltClass = "E"  # silent fallback detected
}

# Map halt class to exit code
$ExitCode = switch ($HaltClass) {
    "A" { 1 } "B" { 2 } "C" { 3 } "D" { 4 }
    "E" { 5 } "F" { 6 } "G" { 7 }
    default { 0 }
}

$NativeThinking = "codex model_reasoning_effort=$NativeReasoning"
$HaltJson = if ($HaltClass) { "`"$HaltClass`"" } else { "null" }
Write-Output "{`"exit_code`": $ExitCode, `"output_file`": `"$($TmpOut -replace '\\','/')`", `"stderr_file`": `"$($TmpErr -replace '\\','/')`", `"model_actual`": `"$ModelActual`", `"native_thinking`": `"$NativeThinking`", `"halt_class`": $HaltJson}"
exit $ExitCode
