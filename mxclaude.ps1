#!/usr/bin/env pwsh
# mxclaude.ps1 — launch Claude Code on MiniMax's Anthropic-compatible API (Windows port).
#
# Windows companion to the macOS/Linux bash script `mxclaude`. Same env vars,
# same model picker — different shell.
#
# Uses the official MiniMax Anthropic-compatible endpoint:
#   - China (default): https://api.minimaxi.com/anthropic
#   - International:   https://api.minimax.io/anthropic      (set $env:MINIMAX_BASE_URL)
#
# Reads MINIMAX_API_KEY from the process env first, then User/Machine env vars.
#
# Quick start (from the mxclaude directory):
#   pwsh -File .\mxclaude.ps1
#
# Use:
#   pwsh -File ./mxclaude.ps1                  # MiniMax-M3 (flagship)
#   pwsh -File ./mxclaude.ps1 fast             # MiniMax-M2.5 (cheaper)
#   pwsh -File ./mxclaude.ps1 long             # 1M context window
#   pwsh -File ./mxclaude.ps1 effort max       # set effort (low|medium|high|xhigh|max)
#   pwsh -File ./mxclaude.ps1 update           # git pull
#   pwsh -File ./mxclaude.ps1 --help           # forwarded to claude
#
# Optional env overrides:
#   $env:MINIMAX_MODEL       = 'MiniMax-M3'       # main model
#   $env:MINIMAX_FLASH_MODEL = 'MiniMax-M2.5'     # flash tier
#   $env:MINIMAX_BASE_URL    = 'https://.../anthropic'
#   $env:MINIMAX_CTX         = '1048576'          # max context tokens
#   $env:MINIMAX_OUTPUT      = '8000'             # cap output tokens
#   $env:MINIMAX_EFFORT      = 'max'              # CLAUDE_CODE_EFFORT_LEVEL
#
# Requires: PowerShell 7+, Claude Code CLI, MiniMax API key.

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Error @"
mxclaude.ps1: PowerShell 7+ required (you're on $($PSVersionTable.PSVersion)).
Install once:  winget install Microsoft.PowerShell
Then re-run with:  pwsh -File .\mxclaude.ps1
"@
    exit 1
}

# ---- Self-update -----------------------------------------------------------

function Invoke-MxclaudeUpdate {
    $repo = $null
    $selfDir = Split-Path -Parent $PSCommandPath
    if (Test-Path (Join-Path $selfDir '.git')) { $repo = $selfDir }
    if (-not $repo -and $env:MXCLAUDE_HOME) { $repo = $env:MXCLAUDE_HOME }
    if (-not $repo) {
        $candidate = Join-Path $env:USERPROFILE 'github\xxclaude'
        if (Test-Path (Join-Path $candidate '.git')) { $repo = $candidate }
    }
    if (-not $repo) {
        Write-Error @'
mxclaude: cannot find the xxclaude repo for self-update.
  Set $env:MXCLAUDE_HOME = 'C:\path\to\xxclaude'  or  cd into the repo and run  pwsh -File ./mxclaude.ps1 update
'@
        exit 1
    }
    Write-Host "mxclaude: pulling latest from $repo ..."
    git -C $repo pull
    if ($LASTEXITCODE -ne 0) { Write-Error 'mxclaude: git pull failed.'; exit 1 }
    Write-Host 'mxclaude: updated.'
    exit 0
}

# ---- API key resolution ----------------------------------------------------

function Resolve-ApiKey {
    if ($env:MINIMAX_API_KEY) { return $env:MINIMAX_API_KEY }
    foreach ($scope in 'User', 'Machine') {
        $v = [Environment]::GetEnvironmentVariable('MINIMAX_API_KEY', $scope)
        if ($v) { return $v }
    }
    Write-Error @'
MINIMAX_API_KEY not found.
  setx MINIMAX_API_KEY "your_api_key"
  Get your key at: https://platform.minimaxi.com
'@
    exit 1
}

# ---- Arg parsing -----------------------------------------------------------

$WantFlash = $false
$LongCtx   = $false
$Effort    = if ($env:MINIMAX_EFFORT) { $env:MINIMAX_EFFORT } else { '' }

$remaining = @()
$rest = @($Rest)
$i = 0
:argloop while ($i -lt $rest.Count) {
    $a = $rest[$i]
    switch -CaseSensitive ($a) {
        'update' { Invoke-MxclaudeUpdate }
        'fast'   { $WantFlash = $true; $i++; break }
        'flash'  { $WantFlash = $true; $i++; break }
        'long'   { $LongCtx = $true; $i++; break }
        'effort' {
            $i++; if ($i -lt $rest.Count) { $l=$rest[$i]; if ($l -in 'low','medium','high','xhigh','max'){$Effort=$l;$i++;break}else{Write-Error "mxclaude: invalid effort level '$l'. Use: low medium high xhigh max";exit 1}}else{Write-Error "mxclaude: 'effort' requires a level: low medium high xhigh max";exit 1}
        }
        '--'     { $i++; if ($i -lt $rest.Count) { $remaining += $rest[$i..($rest.Count - 1)] }; break argloop }
        default  { $remaining += $rest[$i..($rest.Count - 1)]; break argloop }
    }
}

$apiKey = Resolve-ApiKey

$baseUrl    = if ($env:MINIMAX_BASE_URL)    { $env:MINIMAX_BASE_URL }    else { 'https://api.minimaxi.com/anthropic' }
$proModel   = if ($env:MINIMAX_MODEL)       { $env:MINIMAX_MODEL }       else { 'MiniMax-M3' }
$flashModel = if ($env:MINIMAX_FLASH_MODEL) { $env:MINIMAX_FLASH_MODEL } else { 'MiniMax-M2.5' }

$mainModel = if ($WantFlash) { $flashModel } else { $proModel }

if ($mainModel -eq $proModel) {
    $otherModel = $flashModel; $otherDesc = 'MiniMax M2.5 — fast / cheap tier'
} else {
    $otherModel = $proModel; $otherDesc = 'MiniMax M3 — full reasoning'
}

# ---- Export env for claude -------------------------------------------------

$env:ANTHROPIC_API_KEY = $null
$env:ANTHROPIC_BASE_URL             = $baseUrl
$env:ANTHROPIC_AUTH_TOKEN           = $apiKey
$env:ANTHROPIC_MODEL                = $mainModel
$env:ANTHROPIC_DEFAULT_OPUS_MODEL   = $mainModel
$env:ANTHROPIC_DEFAULT_SONNET_MODEL = $mainModel
$env:ANTHROPIC_DEFAULT_HAIKU_MODEL  = $flashModel
$env:CLAUDE_CODE_SUBAGENT_MODEL     = $flashModel

if ($otherModel -ne $mainModel) {
    $env:ANTHROPIC_CUSTOM_MODEL_OPTION             = $otherModel
    $env:ANTHROPIC_CUSTOM_MODEL_OPTION_NAME        = $otherModel
    $env:ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION = $otherDesc
}

# ---- Effort / context / output ---------------------------------------------
if ($Effort) { $env:CLAUDE_CODE_EFFORT_LEVEL = $Effort }
$ctx = if ($env:MINIMAX_CTX) { $env:MINIMAX_CTX } elseif ($LongCtx) { '1048576' } else { '' }
if ($ctx) { $env:CLAUDE_CODE_MAX_CONTEXT_TOKENS = $ctx; $env:DISABLE_COMPACT = '1' }
if ($env:MINIMAX_OUTPUT) { $env:CLAUDE_CODE_MAX_OUTPUT_TOKENS = $env:MINIMAX_OUTPUT }

# ---- Launch ----------------------------------------------------------------

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Error @'
mxclaude: `claude` CLI not found on PATH.
  Install: npm install -g @anthropic-ai/claude-code
'@
    exit 1
}

$banner = "🚀 Claude Code on MiniMax  →  $mainModel  ($baseUrl)"
if ($ctx)    { $banner += "  |  ctx=$ctx" }
if ($Effort) { $banner += "  |  effort=$Effort" }
if ($otherModel -ne $mainModel) { $banner += '  (switch mid-session via /model)' }
Write-Host $banner

& claude @remaining
exit $LASTEXITCODE
