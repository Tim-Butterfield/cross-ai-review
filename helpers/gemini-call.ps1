# gemini-call.ps1 — wrapper for Gemini CLI invocation per the cross-ai-review cycle.
# PowerShell version of gemini-call.sh; same interface and behavior.
#
# Interface (PowerShell parameter casing):
#   -Layer <int>            Layer index.
#   -Primitive <string>     P1 / P2 / P3 / P4 / P5 / P6.
#   -Phase <string>         semantic-iterate | semantic-cross-check | semantic-verify
#   -Outer <int>            Outer cycle index.
#   -Iter <int>             Inner iteration (only for -Role iterating).
#   -Role <iterating|cross-check|verify>
#   -Model <slug>           Requested model.
#   -ThinkingLevel <fast|standard|deep>
#                           Abstract thinking level. Helper translates to Gemini's native
#                           thinking-budget tokens (or records native=unsupported when the
#                           CLI version doesn't expose the flag).
#   -PromptFile <path>      Reviewer prompt file.
#   -StdinFile <path>       Optional: file content to pipe via stdin.
#   -RunDir <path>          Run directory.
#   -CallStarted <ts>       Timestamp prefix.
#
# No override flag exists for actual-model extraction failure — the cycle halts as
# Class E unconditionally per methodology § Actual-model extraction failure.
#
# Output: JSON status object on stdout.
# Exit codes: 0=ok, 1-7=halt classes A-G, 8=invalid args.

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
    [string]$StdinFile,
    # Schema mode (default ""): validate envelope's .response as /cross-ai-review findings JSON.
    # No-schema mode ("none"): treat .response as raw markdown. Used by /clarify with gemini analyst.
    [string]$Schema = "",
    [Parameter(Mandatory=$true)][string]$RunDir,
    [Parameter(Mandatory=$true)][string]$CallStarted
)

if ($Role -eq "iterating" -and -not $PSBoundParameters.ContainsKey('Iter')) {
    Write-Output '{"error": "-Iter required for -Role iterating"}'
    exit 8
}

if (-not (Test-Path $PromptFile)) {
    Write-Output "{`"error`": `"prompt file not found: $PromptFile`"}"
    exit 8
}

# Translate thinking level → Gemini native thinking-budget tokens (default mapping)
$NativeBudget = switch ($ThinkingLevel) {
    "fast"     { 2048 }
    "standard" { 8192 }
    "deep"     { 24576 }
}

$TmpOut = Join-Path $RunDir ".tmp-$CallStarted-out.json"
$TmpReviewer = Join-Path $RunDir ".tmp-$CallStarted-reviewer.json"
$TmpErr = Join-Path $RunDir ".tmp-$CallStarted-err"

$Prompt = Get-Content $PromptFile -Raw

# Invoke Gemini. Required flags: --approval-mode plan, --output-format json.
$ProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
$ProcessInfo.FileName = "gemini"
$ProcessInfo.RedirectStandardInput = $true
$ProcessInfo.RedirectStandardOutput = $true
$ProcessInfo.RedirectStandardError = $true
$ProcessInfo.UseShellExecute = $false
foreach ($arg in @("-p", $Prompt, "-m", $Model, "--approval-mode", "plan", "--output-format", "json")) {
    $ProcessInfo.ArgumentList.Add($arg)
}

$Proc = New-Object System.Diagnostics.Process
$Proc.StartInfo = $ProcessInfo
$Proc.Start() | Out-Null

if ($StdinFile -and (Test-Path $StdinFile)) {
    $StdinContent = Get-Content $StdinFile -Raw
    $Proc.StandardInput.Write($StdinContent)
}
$Proc.StandardInput.Close()

$StdoutCapture = $Proc.StandardOutput.ReadToEnd()
$StderrCapture = $Proc.StandardError.ReadToEnd()
$Proc.WaitForExit()
$GeminiExit = $Proc.ExitCode

$StdoutCapture | Out-File -FilePath $TmpOut -Encoding UTF8 -NoNewline
$StderrCapture | Out-File -FilePath $TmpErr -Encoding UTF8 -NoNewline

# Halt-signal classification
$HaltClass = ""
$OutSize = if (Test-Path $TmpOut) { (Get-Item $TmpOut).Length } else { 0 }
if ($GeminiExit -ne 0 -or $OutSize -eq 0) {
    if ($StderrCapture -match "RetryableQuotaError|exhausted your capacity") { $HaltClass = "C" }
    elseif ($StderrCapture -match "ModelNotFoundError|Requested entity was not found|404") { $HaltClass = "D" }
    elseif ($StderrCapture -match "QUOTA_EXCEEDED") { $HaltClass = "B" }
    elseif ($StderrCapture -match "401|403|authentication|permission denied") { $HaltClass = "A" }
    elseif ($StderrCapture -match "Ripgrep is not available" -and $OutSize -gt 0) { }
    else { $HaltClass = "G" }
}

# Parse envelope and extract reviewer JSON
$ModelActual = ""
$NativeThinking = "gemini thinking_budget_tokens=$NativeBudget"
if (-not $HaltClass -and $OutSize -gt 0) {
    try {
        $Envelope = $StdoutCapture | ConvertFrom-Json -ErrorAction Stop
        if ($Envelope.error) {
            $HaltClass = "G"
        } else {
            $Response = $Envelope.response
            $ResponseClean = $Response -replace '^```(json)?\r?\n', '' -replace '\r?\n```$', ''
            if ($Schema -eq "none") {
                # No-schema mode: write raw markdown response; caller (e.g. /clarify) parses it.
                $ResponseClean | Out-File -FilePath $TmpReviewer -Encoding UTF8 -NoNewline
            } else {
                # Schema mode: validate as /cross-ai-review findings JSON.
                try {
                    $Reviewer = $ResponseClean | ConvertFrom-Json -ErrorAction Stop
                    if ($Reviewer.summary -and $Reviewer.verdict -and $Reviewer.findings) {
                        $ResponseClean | Out-File -FilePath $TmpReviewer -Encoding UTF8 -NoNewline
                    } else {
                        $HaltClass = "G"
                    }
                } catch {
                    $HaltClass = "G"
                }
            }
            if ($Envelope.stats -and $Envelope.stats.models) {
                $ModelActual = ($Envelope.stats.models | Get-Member -MemberType NoteProperty | Select-Object -First 1).Name
            }
            # Detect whether the CLI version honored the thinking-budget flag (best-effort).
            if (-not ($StdoutCapture -match "thinking|reasoning")) {
                $NativeThinking = "unsupported"
            }
        }
    } catch {
        $HaltClass = "G"
    }
}

# Class E — extraction failure halts unconditionally (no override in v1)
if (-not $ModelActual -and -not $HaltClass) {
    $HaltClass = "E"
    $ModelActual = "extraction-failed"
}
elseif ($ModelActual -and $ModelActual -ne $Model) {
    $HaltClass = "E"
}

$ExitCode = switch ($HaltClass) {
    "A" { 1 } "B" { 2 } "C" { 3 } "D" { 4 }
    "E" { 5 } "F" { 6 } "G" { 7 }
    default { 0 }
}

$HaltJson = if ($HaltClass) { "`"$HaltClass`"" } else { "null" }
$TmpOutFwd = $TmpOut -replace '\\','/'
$TmpRevFwd = $TmpReviewer -replace '\\','/'
$TmpErrFwd = $TmpErr -replace '\\','/'
Write-Output "{`"exit_code`": $ExitCode, `"output_file`": `"$TmpOutFwd`", `"reviewer_file`": `"$TmpRevFwd`", `"stderr_file`": `"$TmpErrFwd`", `"model_actual`": `"$ModelActual`", `"native_thinking`": `"$NativeThinking`", `"halt_class`": $HaltJson}"
exit $ExitCode
