#!/usr/bin/env pwsh
# dsclaude.ps1 — launch Claude Code on DeepSeek's Anthropic-compatible API (Windows port).
#
# Windows companion to the macOS/Linux bash script `dsclaude`. Same env vars,
# same model picker, same positional flags — different shell.
#
# Follows the official guide:
#   https://api-docs.deepseek.com/guides/anthropic_api
#   https://api-docs.deepseek.com/guides/coding_agents
#   https://api-docs.deepseek.com/quick_start/agent_integrations/claude_code
#
# Reads DEEPSEEK_API_KEY from the process env first, then User/Machine env vars.
#
# Quick start (from the dsclaude directory):
#   pwsh -File .\dsclaude.ps1
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
#     'C:\Users\<you>\Desktop\dsclaude\dsclaude.ps1'
# (`-NoExit` keeps the window open if the launching context doesn't have one.)
#
# Optional — make it globally available (one-time, from this dir):
#   $bin = "$env:USERPROFILE\bin"; New-Item -ItemType Directory -Force $bin | Out-Null
#   Copy-Item .\dsclaude.ps1 $bin\dsclaude.ps1
#   # then add $bin to PATH and run:  pwsh -File dsclaude.ps1
#
# Use:
#   pwsh -File ./dsclaude.ps1                  # deepseek-v4-pro  (default, full reasoning)
#   pwsh -File ./dsclaude.ps1 fast             # deepseek-v4-flash[1m] (cheaper / faster)
#   pwsh -File ./dsclaude.ps1 long             # request a 1M context window
#   pwsh -File ./dsclaude.ps1 long fast        # 1M + flash
#   pwsh -File ./dsclaude.ps1 update           # git pull latest from the dsclaude repo
#   pwsh -File ./dsclaude.ps1 --help           # any remaining flag is forwarded to claude
#
# Backward-compat aliases (v4-pro is unified thinking/non-thinking, so these all
# resolve to deepseek-v4-pro today):
#   think | reasoner | -r     # same as default
#
# Optional env overrides (take precedence over positional aliases):
#   $env:DSCLAUDE_CTX    = '1048576'     # CLAUDE_CODE_MAX_CONTEXT_TOKENS + DISABLE_COMPACT=1
#   $env:DSCLAUDE_OUTPUT = '8000'        # CLAUDE_CODE_MAX_OUTPUT_TOKENS
#   $env:DSCLAUDE_EFFORT = 'max'         # CLAUDE_CODE_EFFORT_LEVEL (default: max)
#
# In-session switch:
#   /model deepseek-v4-flash[1m]         # switch to the fast/haiku tier
#   /model deepseek-v4-pro[1m]           # switch back to pro
#
# Requires: PowerShell 7+ (`winget install Microsoft.PowerShell`), Claude Code
# CLI on PATH (`npm i -g @anthropic-ai/claude-code`), DeepSeek API key.

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
dsclaude.ps1: PowerShell 7+ required (you're on $($PSVersionTable.PSVersion)).

Windows PowerShell 5.1 cannot host claude's interactive UI — the first
keystroke causes claude to exit. Install PowerShell 7 once:

  winget install Microsoft.PowerShell

Then re-run with:

  pwsh -File .\dsclaude.ps1
"@
    exit 1
}

# ---- Self-update -----------------------------------------------------------

function Invoke-DsclaudeUpdate {
    $repo = $null
    $selfDir = Split-Path -Parent $PSCommandPath
    if (Test-Path (Join-Path $selfDir '.git')) {
        $repo = $selfDir
    }
    if (-not $repo -and $env:DSCLAUDE_HOME) {
        $repo = $env:DSCLAUDE_HOME
    }
    if (-not $repo) {
        $candidate = Join-Path $env:USERPROFILE 'github\dsclaude'
        if (Test-Path (Join-Path $candidate '.git')) { $repo = $candidate }
    }
    if (-not $repo) {
        Write-Error @'
dsclaude: cannot find the dsclaude repo for self-update.
  Set $env:DSCLAUDE_HOME = 'C:\path\to\dsclaude'  or  cd into the repo and run  pwsh -File ./dsclaude.ps1 update
'@
        exit 1
    }
    Write-Host "dsclaude: pulling latest from $repo ..."
    git -C $repo pull
    if ($LASTEXITCODE -ne 0) {
        Write-Error 'dsclaude: git pull failed. Check network or resolve conflicts manually.'
        exit 1
    }
    Write-Host 'dsclaude: updated.'
    exit 0
}

# ---- API key resolution ----------------------------------------------------

function Resolve-ApiKey {
    if ($env:DEEPSEEK_API_KEY) { return $env:DEEPSEEK_API_KEY }
    foreach ($scope in 'User', 'Machine') {
        $v = [Environment]::GetEnvironmentVariable('DEEPSEEK_API_KEY', $scope)
        if ($v) { return $v }
    }
    Write-Error @'
DEEPSEEK_API_KEY not found.
  Set it persistently (User scope, takes effect in new shells):
    setx DEEPSEEK_API_KEY "sk-xxxxxxxxxxxxxxxxxx"
  Or for the current shell only:
    $env:DEEPSEEK_API_KEY = 'sk-xxxxxxxxxxxxxxxxxx'
'@
    exit 1
}

# ---- Arg parsing -----------------------------------------------------------

$ProModel   = 'deepseek-v4-pro[1m]'
$FlashModel = 'deepseek-v4-flash[1m]'

$LongCtx    = $false
$MainModel  = $ProModel
$HaikuModel = $FlashModel

$remaining = @()
$rest = @($Rest)
$i = 0
:argloop while ($i -lt $rest.Count) {
    $a = $rest[$i]
    switch -CaseSensitive ($a) {
        'update'   { Invoke-DsclaudeUpdate }
        'long'     { $LongCtx = $true;            $i++; break }
        'fast'     { $MainModel = $FlashModel;    $i++; break }
        'flash'    { $MainModel = $FlashModel;    $i++; break }
        'think'    { $MainModel = $ProModel;      $i++; break }
        'reasoner' { $MainModel = $ProModel;      $i++; break }
        '-r'       { $MainModel = $ProModel;      $i++; break }
        '--'       {
            $i++
            if ($i -lt $rest.Count) { $remaining += $rest[$i..($rest.Count - 1)] }
            break argloop
        }
        default    {
            $remaining += $rest[$i..($rest.Count - 1)]
            break argloop
        }
    }
}

$apiKey = Resolve-ApiKey

# Pick the "other" model to surface in Claude Code's /model picker.
if ($MainModel -eq $ProModel) {
    $otherModel = $FlashModel
    $otherDesc  = 'DeepSeek V4 Flash — fast / cheap haiku tier'
} else {
    $otherModel = $ProModel
    $otherDesc  = 'DeepSeek V4 Pro — full reasoning'
}

# ---- Export env for claude -------------------------------------------------

$env:ANTHROPIC_BASE_URL                = 'https://api.deepseek.com/anthropic'
$env:ANTHROPIC_AUTH_TOKEN              = $apiKey
$env:API_TIMEOUT_MS                    = '600000'
$env:ANTHROPIC_MODEL                   = $MainModel
$env:ANTHROPIC_DEFAULT_OPUS_MODEL      = $MainModel
$env:ANTHROPIC_DEFAULT_SONNET_MODEL    = $MainModel
$env:ANTHROPIC_DEFAULT_HAIKU_MODEL     = $HaikuModel
# Subagents: strip the [1m] long-context tag — short subagent calls don't need 1M.
$env:CLAUDE_CODE_SUBAGENT_MODEL        = $FlashModel -replace '\[1m\]$', ''
$env:CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC    = '1'
$env:CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK   = '1'
$env:CLAUDE_CODE_EFFORT_LEVEL          = if ($env:DSCLAUDE_EFFORT) { $env:DSCLAUDE_EFFORT } else { 'max' }

$env:ANTHROPIC_CUSTOM_MODEL_OPTION             = $otherModel
$env:ANTHROPIC_CUSTOM_MODEL_OPTION_NAME        = $otherModel
$env:ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION = $otherDesc

# Optional context-window override. Env > positional > unset (Claude Code default).
$ctx = $env:DSCLAUDE_CTX
if (-not $ctx -and $LongCtx) { $ctx = '1048576' }
if ($ctx) {
    $env:CLAUDE_CODE_MAX_CONTEXT_TOKENS = $ctx
    $env:DISABLE_COMPACT                = '1'
}

if ($env:DSCLAUDE_OUTPUT) {
    $env:CLAUDE_CODE_MAX_OUTPUT_TOKENS = $env:DSCLAUDE_OUTPUT
}

# ---- Launch ----------------------------------------------------------------

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Error @'
dsclaude: `claude` CLI not found on PATH.
  Install Claude Code:  npm install -g @anthropic-ai/claude-code
  Then re-run this script.
'@
    exit 1
}

$banner = "🚀 Claude Code on DeepSeek  →  $MainModel"
if ($ctx) { $banner += "  |  ctx=$ctx" }
Write-Host "$banner  (switch mid-session via /model)"

& claude @remaining
exit $LASTEXITCODE
