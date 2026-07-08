#!/usr/bin/env pwsh
# lcclaude.ps1 — launch Claude Code on Meituan LongCat's Anthropic-compatible API (Windows port).
#
# Windows companion to the macOS/Linux bash script `lcclaude`. Same env vars,
# same model picker — different shell.
#
# Uses the official LongCat Anthropic-compatible endpoint:
#   https://api.longcat.chat/anthropic
#
# Reads LONGCAT_API_KEY from the process env first, then User/Machine env vars.
#
# Quick start (from the lcclaude directory):
#   pwsh -File .\lcclaude.ps1
#
# Three invocation rules that matter on Windows:
#   1. Use `pwsh`, not `powershell`.
#   2. Use `-File`, not `-Command` / `&`.
#   3. Allow local scripts to run (one-time):
#        Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
#
# Use:
#   pwsh -File ./lcclaude.ps1                  # LongCat-2.0 (flagship)
#   pwsh -File ./lcclaude.ps1 fast             # LongCat-Flash-Chat
#   pwsh -File ./lcclaude.ps1 think            # LongCat-Flash-Thinking
#   pwsh -File ./lcclaude.ps1 long             # request 1M context window
#   pwsh -File ./lcclaude.ps1 effort max       # set effort (low|medium|high|xhigh|max)
#   pwsh -File ./lcclaude.ps1 update           # git pull
#   pwsh -File ./lcclaude.ps1 --help           # forwarded to claude
#
# Optional env overrides:
#   $env:LONGCAT_MODEL       = 'LongCat-2.0'   # main model
#   $env:LONGCAT_FLASH_MODEL = 'LongCat-Flash-Chat'  # flash tier
#   $env:LONGCAT_BASE_URL    = 'https://.../anthropic'
#   $env:LONGCAT_CTX         = '1048576'       # max context tokens
#   $env:LONGCAT_OUTPUT      = '8000'          # cap output tokens
#   $env:LONGCAT_EFFORT      = 'max'           # CLAUDE_CODE_EFFORT_LEVEL
#
# In-session switch:
#   /model LongCat-Flash-Chat      # fast tier
#   /model LongCat-Flash-Thinking  # thinking tier
#   /model LongCat-2.0             # flagship
#
# Get your free API key: https://longcat.chat/platform

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Error @"
lcclaude.ps1: PowerShell 7+ required (you're on $($PSVersionTable.PSVersion)).

Windows PowerShell 5.1 cannot host claude's interactive UI.
Install PowerShell 7 once:

  winget install Microsoft.PowerShell

Then re-run with:

  pwsh -File .\lcclaude.ps1
"@
    exit 1
}

# ---- Self-update -----------------------------------------------------------

function Invoke-LcclaudeUpdate {
    $repo = $null
    $selfDir = Split-Path -Parent $PSCommandPath
    if (Test-Path (Join-Path $selfDir '.git')) { $repo = $selfDir }
    if (-not $repo -and $env:LCCLAUDE_HOME) { $repo = $env:LCCLAUDE_HOME }
    if (-not $repo) {
        $candidate = Join-Path $env:USERPROFILE 'github\xxclaude'
        if (Test-Path (Join-Path $candidate '.git')) { $repo = $candidate }
    }
    if (-not $repo) {
        Write-Error @'
lcclaude: cannot find the xxclaude repo for self-update.
  Set $env:LCCLAUDE_HOME = 'C:\path\to\xxclaude'  or  cd into the repo and run  pwsh -File ./lcclaude.ps1 update
'@
        exit 1
    }
    Write-Host "lcclaude: pulling latest from $repo ..."
    git -C $repo pull
    if ($LASTEXITCODE -ne 0) {
        Write-Error 'lcclaude: git pull failed. Check network or resolve conflicts manually.'
        exit 1
    }
    Write-Host 'lcclaude: updated.'
    exit 0
}

# ---- API key resolution ----------------------------------------------------

function Resolve-ApiKey {
    if ($env:LONGCAT_API_KEY) { return $env:LONGCAT_API_KEY }
    foreach ($scope in 'User', 'Machine') {
        $v = [Environment]::GetEnvironmentVariable('LONGCAT_API_KEY', $scope)
        if ($v) { return $v }
    }
    Write-Error @'
LONGCAT_API_KEY not found.
  Set it persistently (User scope, takes effect in new shells):
    setx LONGCAT_API_KEY "lc-xxxxxxxxxxxxxxxxxx"
  Or for the current shell only:
    $env:LONGCAT_API_KEY = 'lc-xxxxxxxxxxxxxxxxxx'
  Get your free key at: https://longcat.chat/platform
'@
    exit 1
}

# ---- Arg parsing -----------------------------------------------------------

$mainModel = $null
$LongCtx   = $false
$Effort    = if ($env:LONGCAT_EFFORT) { $env:LONGCAT_EFFORT } else { '' }

$remaining = @()
$rest = @($Rest)
$i = 0
:argloop while ($i -lt $rest.Count) {
    $a = $rest[$i]
    switch -CaseSensitive ($a) {
        'update' { Invoke-LcclaudeUpdate }
        'fast'   { $mainModel = 'LongCat-Flash-Chat'; $i++; break }
        'flash'  { $mainModel = 'LongCat-Flash-Chat'; $i++; break }
        'think'  { $mainModel = 'LongCat-Flash-Thinking'; $i++; break }
        'long'   { $LongCtx = $true; $i++; break }
        'effort' {
            $i++; if ($i -lt $rest.Count) { $l=$rest[$i]; if ($l -in 'low','medium','high','xhigh','max'){$Effort=$l;$i++;break}else{Write-Error "lcclaude: invalid effort level '$l'. Use: low medium high xhigh max";exit 1}}else{Write-Error "lcclaude: 'effort' requires a level: low medium high xhigh max";exit 1}
        }
        '--'     {
            $i++
            if ($i -lt $rest.Count) { $remaining += $rest[$i..($rest.Count - 1)] }
            break argloop
        }
        default  {
            $remaining += $rest[$i..($rest.Count - 1)]
            break argloop
        }
    }
}

$apiKey = Resolve-ApiKey

$baseUrl    = if ($env:LONGCAT_BASE_URL)    { $env:LONGCAT_BASE_URL }    else { 'https://api.longcat.chat/anthropic' }
$proModel   = if ($env:LONGCAT_MODEL)       { $env:LONGCAT_MODEL }       else { 'LongCat-2.0' }
$flashModel = if ($env:LONGCAT_FLASH_MODEL) { $env:LONGCAT_FLASH_MODEL } else { 'LongCat-Flash-Chat' }
$thinkModel = if ($env:LONGCAT_THINK_MODEL) { $env:LONGCAT_THINK_MODEL } else { 'LongCat-Flash-Thinking' }

if (-not $mainModel) { $mainModel = $proModel }

if ($mainModel -eq $proModel) {
    $otherModel = $flashModel
    $otherDesc  = 'LongCat Flash Chat — fast / cheap tier'
} elseif ($mainModel -eq $flashModel) {
    $otherModel = $proModel
    $otherDesc  = 'LongCat 2.0 — flagship reasoning'
} else {
    $otherModel = $proModel
    $otherDesc  = 'LongCat 2.0 — flagship reasoning'
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

# ---- Effort level ----------------------------------------------------------
if ($Effort) { $env:CLAUDE_CODE_EFFORT_LEVEL = $Effort }
# ---- Context window --------------------------------------------------------
$ctx = if ($env:LONGCAT_CTX) { $env:LONGCAT_CTX } elseif ($LongCtx) { '1048576' } else { '' }
if ($ctx) { $env:CLAUDE_CODE_MAX_CONTEXT_TOKENS = $ctx; $env:DISABLE_COMPACT = '1' }
# ---- Output cap ------------------------------------------------------------
if ($env:LONGCAT_OUTPUT) { $env:CLAUDE_CODE_MAX_OUTPUT_TOKENS = $env:LONGCAT_OUTPUT }

# ---- Launch ----------------------------------------------------------------

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Error @'
lcclaude: `claude` CLI not found on PATH.
  Install Claude Code:  npm install -g @anthropic-ai/claude-code
  Then re-run this script.
'@
    exit 1
}

$banner = "🚀 Claude Code on LongCat  →  $mainModel  ($baseUrl)"
if ($ctx)    { $banner += "  |  ctx=$ctx" }
if ($Effort) { $banner += "  |  effort=$Effort" }
if ($otherModel -ne $mainModel) { $banner += '  (switch mid-session via /model)' }
Write-Host $banner

& claude @remaining
exit $LASTEXITCODE
