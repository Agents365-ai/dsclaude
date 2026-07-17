#!/usr/bin/env pwsh
# kmclaude.ps1 — launch Claude Code on Moonshot AI Kimi's Anthropic-compatible API (Windows port).
#
# Windows companion to the macOS/Linux bash script `kmclaude`. Same env vars,
# same model picker — different shell.
#
# Uses the official Kimi Anthropic-compatible endpoint:
#   https://api.moonshot.cn/anthropic
#
# Reads KIMI_API_KEY from the process env first, then User/Machine env vars.
#
# Quick start (from the kmclaude directory):
#   pwsh -File .\kmclaude.ps1
#
# Three invocation rules that matter on Windows:
#   1. Use `pwsh`, not `powershell`. PowerShell 5.1 ships with Windows but its
#      legacy console host breaks Ink-based CLIs (claude exits silently after
#      the first keystroke). This script refuses to run on PS < 7.
#      Install once:  winget install Microsoft.PowerShell
#   2. Use `-File`, not `-Command` / `&`. `-File` runs the script in a clean
#      arg-parsing mode; `-Command` re-tokenizes the line and mangles paths.
#   3. Allow local scripts to run (one-time, current user only):
#        Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
#
# Launching from a shortcut, Run dialog, or another shell:
#   Start-Process pwsh -ArgumentList '-NoExit', '-File',
#     'C:\Users\<you>\Desktop\kmclaude\kmclaude.ps1'
# (`-NoExit` keeps the window open if the launching context doesn't have one.)
#
# Optional — make it globally available (one-time, from this dir):
#   $bin = "$env:USERPROFILE\bin"; New-Item -ItemType Directory -Force $bin | Out-Null
#   Copy-Item .\kmclaude.ps1 $bin\kmclaude.ps1
#   # then add $bin to PATH and run:  pwsh -File kmclaude.ps1
#
# Use:
#   pwsh -File ./kmclaude.ps1                  # kimi-k3 (Kimi flagship)
#   pwsh -File ./kmclaude.ps1 fast             # run the flash tier (kimi-k2.5) as main
#   pwsh -File ./kmclaude.ps1 long             # (no-op; 1M context is the default)
#   pwsh -File ./kmclaude.ps1 effort max       # set effort (low|medium|high|xhigh|max)
#   pwsh -File ./kmclaude.ps1 update           # git pull latest from this repo
#   pwsh -File ./kmclaude.ps1 --help           # any remaining flag is forwarded to claude
#
# Optional env overrides (take precedence over positional aliases):
#   $env:KIMI_MODEL       = 'kimi-k3'          # main model
#   $env:KIMI_FLASH_MODEL = 'kimi-k2.5'        # flash / haiku / subagent tier
#   $env:KIMI_BASE_URL    = 'https://.../anthropic'  # custom base URL
#   $env:KIMI_CTX         = '1048576'          # max context tokens (default: 1M)
#   $env:KIMI_OUTPUT      = '8000'             # cap output tokens
#   $env:KIMI_EFFORT      = 'max'              # CLAUDE_CODE_EFFORT_LEVEL
#
# In-session switch:
#   /model kimi-k2.5        # switch to the flash tier
#   /model kimi-k3          # switch back to the main model
#
# Requires: PowerShell 7+ (`winget install Microsoft.PowerShell`), Claude Code
# CLI on PATH (`npm i -g @anthropic-ai/claude-code`), Moonshot Kimi API key.

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)

$ErrorActionPreference = 'Stop'

# ---- PowerShell version guard ----------------------------------------------
# Windows PowerShell 5.1 ships with a legacy console host whose raw-mode TTY
# breaks Ink (the React-for-CLI framework Claude Code uses): the welcome
# screen renders, then the first keystroke causes claude to exit silently.
# PowerShell 7+ uses ConPTY and works correctly. Refuse early with a clear
# message rather than letting the user debug the silent-exit symptom.
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Error @"
kmclaude.ps1: PowerShell 7+ required (you're on $($PSVersionTable.PSVersion)).

Windows PowerShell 5.1 cannot host claude's interactive UI — the first
keystroke causes claude to exit. Install PowerShell 7 once:

  winget install Microsoft.PowerShell

Then re-run with:

  pwsh -File .\kmclaude.ps1
"@
    exit 1
}

# ---- Self-update -----------------------------------------------------------

function Invoke-KmclaudeUpdate {
    $repo = $null
    $selfDir = Split-Path -Parent $PSCommandPath
    if (Test-Path (Join-Path $selfDir '.git')) {
        $repo = $selfDir
    }
    if (-not $repo -and $env:KMCLAUDE_HOME) {
        $repo = $env:KMCLAUDE_HOME
    }
    if (-not $repo) {
        $candidate = Join-Path $env:USERPROFILE 'github\xxclaude'
        if (Test-Path (Join-Path $candidate '.git')) { $repo = $candidate }
    }
    if (-not $repo) {
        Write-Error @'
kmclaude: cannot find the xxclaude repo for self-update.
  Set $env:KMCLAUDE_HOME = 'C:\path\to\xxclaude'  or  cd into the repo and run  pwsh -File ./kmclaude.ps1 update
'@
        exit 1
    }
    Write-Host "kmclaude: pulling latest from $repo ..."
    git -C $repo pull
    if ($LASTEXITCODE -ne 0) {
        Write-Error 'kmclaude: git pull failed. Check network or resolve conflicts manually.'
        exit 1
    }
    Write-Host 'kmclaude: updated.'
    exit 0
}

# ---- API key resolution ----------------------------------------------------

function Resolve-ApiKey {
    if ($env:KIMI_API_KEY) { return $env:KIMI_API_KEY }
    foreach ($scope in 'User', 'Machine') {
        $v = [Environment]::GetEnvironmentVariable('KIMI_API_KEY', $scope)
        if ($v) { return $v }
    }
    Write-Error @'
KIMI_API_KEY not found.
  Set it persistently (User scope, takes effect in new shells):
    setx KIMI_API_KEY "sk-xxxxxxxxxxxxxxxxxx"
  Or for the current shell only:
    $env:KIMI_API_KEY = 'sk-xxxxxxxxxxxxxxxxxx'
  Get your key at: https://platform.moonshot.cn/console/api-keys
'@
    exit 1
}

# ---- Arg parsing -----------------------------------------------------------

$WantFlash = $false
$LongCtx   = $false
$Effort    = if ($env:KIMI_EFFORT) { $env:KIMI_EFFORT } else { '' }

$remaining = @()
$rest = @($Rest)
$i = 0
:argloop while ($i -lt $rest.Count) {
    $a = $rest[$i]
    switch -CaseSensitive ($a) {
        'update' { Invoke-KmclaudeUpdate }
        'fast'   { $WantFlash = $true; $i++; break }
        'flash'  { $WantFlash = $true; $i++; break }
        'long'   { $LongCtx = $true; $i++; break }
        'effort' {
            $i++
            if ($i -lt $rest.Count) {
                $level = $rest[$i]
                if ($level -in 'low','medium','high','xhigh','max') { $Effort = $level; $i++; break }
                else { Write-Error "kmclaude: invalid effort level '$level'. Use: low medium high xhigh max"; exit 1 }
            } else { Write-Error "kmclaude: 'effort' requires a level: low medium high xhigh max"; exit 1 }
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

$baseUrl    = if ($env:KIMI_BASE_URL)    { $env:KIMI_BASE_URL }    else { 'https://api.moonshot.cn/anthropic' }
$proModel   = if ($env:KIMI_MODEL)       { $env:KIMI_MODEL }       else { 'kimi-k3' }
$flashModel = if ($env:KIMI_FLASH_MODEL) { $env:KIMI_FLASH_MODEL } else { 'kimi-k2.5' }

$mainModel = if ($WantFlash) { $flashModel } else { $proModel }

# Pick the "other" model to surface in Claude Code's /model picker.
if ($mainModel -eq $proModel) {
    $otherModel = $flashModel
    $otherDesc  = 'Kimi K2.5 — fast / cheap tier'
} else {
    $otherModel = $proModel
    $otherDesc  = 'Kimi K3 — full reasoning'
}

# ---- Export env for claude -------------------------------------------------

$env:ANTHROPIC_API_KEY = $null

$env:ANTHROPIC_BASE_URL             = $baseUrl
$env:ANTHROPIC_AUTH_TOKEN           = $apiKey
$env:ANTHROPIC_MODEL                = $mainModel
$env:ANTHROPIC_DEFAULT_OPUS_MODEL   = $mainModel
$env:ANTHROPIC_DEFAULT_SONNET_MODEL = $mainModel
$env:ANTHROPIC_DEFAULT_HAIKU_MODEL  = $flashModel
# Subagents run on the cheaper flash tier.
$env:CLAUDE_CODE_SUBAGENT_MODEL     = $flashModel

# Expose the other Kimi model inside the /model picker (skip when identical).
if ($otherModel -ne $mainModel) {
    $env:ANTHROPIC_CUSTOM_MODEL_OPTION             = $otherModel
    $env:ANTHROPIC_CUSTOM_MODEL_OPTION_NAME        = $otherModel
    $env:ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION = $otherDesc
}

# ---- Effort level ----------------------------------------------------------
if ($Effort) { $env:CLAUDE_CODE_EFFORT_LEVEL = $Effort }

# ---- Context window --------------------------------------------------------
$ctx = if ($env:KIMI_CTX) { $env:KIMI_CTX } else { '1048576' }
if ($ctx) { $env:CLAUDE_CODE_MAX_CONTEXT_TOKENS = $ctx; $env:DISABLE_COMPACT = '1' }

# ---- Output cap ------------------------------------------------------------
if ($env:KIMI_OUTPUT) { $env:CLAUDE_CODE_MAX_OUTPUT_TOKENS = $env:KIMI_OUTPUT }

# ---- Launch ----------------------------------------------------------------

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Error @'
kmclaude: `claude` CLI not found on PATH.
  Install Claude Code:  npm install -g @anthropic-ai/claude-code
  Then re-run this script.
'@
    exit 1
}

$banner = "🚀 Claude Code on Kimi  →  $mainModel  ($baseUrl)"
if ($ctx)    { $banner += "  |  ctx=$ctx" }
if ($Effort) { $banner += "  |  effort=$Effort" }
if ($otherModel -ne $mainModel) { $banner += '  (switch mid-session via /model)' }
Write-Host $banner

& claude @remaining
exit $LASTEXITCODE
