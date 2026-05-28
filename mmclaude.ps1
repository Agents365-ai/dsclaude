#!/usr/bin/env pwsh
# mmclaude.ps1 — launch Claude Code on Xiaomi MiMo's Anthropic-compatible API (Windows port).
#
# Windows companion to the macOS/Linux bash script `mmclaude`. Same env vars,
# same model picker — different shell.
#
# Follows the official MiMo "Claude Code 配置" guide:
#   - Pay-as-you-go : https://api.xiaomimimo.com/anthropic            (sk-... keys)
#   - Token Plan    : https://token-plan-cn.xiaomimimo.com/anthropic  (tp-... keys)
#
# Reads MIMO_API_KEY from the process env first, then User/Machine env vars.
# The base URL is auto-detected from the key prefix (tp-* → Token Plan, else
# pay-as-you-go); override with $env:MIMO_BASE_URL.
#
# Quick start (from the mmclaude directory):
#   pwsh -File .\mmclaude.ps1
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
#     'C:\Users\<you>\Desktop\mmclaude\mmclaude.ps1'
# (`-NoExit` keeps the window open if the launching context doesn't have one.)
#
# Optional — make it globally available (one-time, from this dir):
#   $bin = "$env:USERPROFILE\bin"; New-Item -ItemType Directory -Force $bin | Out-Null
#   Copy-Item .\mmclaude.ps1 $bin\mmclaude.ps1
#   # then add $bin to PATH and run:  pwsh -File mmclaude.ps1
#
# Use:
#   pwsh -File ./mmclaude.ps1                  # mimo-v2.5-pro (MiMo default)
#   pwsh -File ./mmclaude.ps1 fast             # run the flash tier (mimo-v2.5) as main
#   pwsh -File ./mmclaude.ps1 update           # git pull latest from this repo
#   pwsh -File ./mmclaude.ps1 --help           # any remaining flag is forwarded to claude
#
# Optional env overrides (take precedence over positional aliases):
#   $env:MIMO_MODEL       = 'mimo-v2.5-pro'    # main model
#   $env:MIMO_FLASH_MODEL = 'mimo-v2.5'        # flash / haiku / subagent tier
#   $env:MIMO_BASE_URL    = 'https://.../anthropic'  # custom base URL
#
# In-session switch:
#   /model mimo-v2.5        # switch to the flash tier
#   /model mimo-v2.5-pro    # switch back to the main model
#
# Requires: PowerShell 7+ (`winget install Microsoft.PowerShell`), Claude Code
# CLI on PATH (`npm i -g @anthropic-ai/claude-code`), MiMo API key.

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
mmclaude.ps1: PowerShell 7+ required (you're on $($PSVersionTable.PSVersion)).

Windows PowerShell 5.1 cannot host claude's interactive UI — the first
keystroke causes claude to exit. Install PowerShell 7 once:

  winget install Microsoft.PowerShell

Then re-run with:

  pwsh -File .\mmclaude.ps1
"@
    exit 1
}

# ---- Self-update -----------------------------------------------------------

function Invoke-MmclaudeUpdate {
    $repo = $null
    $selfDir = Split-Path -Parent $PSCommandPath
    if (Test-Path (Join-Path $selfDir '.git')) {
        $repo = $selfDir
    }
    if (-not $repo -and $env:MMCLAUDE_HOME) {
        $repo = $env:MMCLAUDE_HOME
    }
    if (-not $repo) {
        $candidate = Join-Path $env:USERPROFILE 'github\xxclaude'
        if (Test-Path (Join-Path $candidate '.git')) { $repo = $candidate }
    }
    if (-not $repo) {
        Write-Error @'
mmclaude: cannot find the xxclaude repo for self-update.
  Set $env:MMCLAUDE_HOME = 'C:\path\to\xxclaude'  or  cd into the repo and run  pwsh -File ./mmclaude.ps1 update
'@
        exit 1
    }
    Write-Host "mmclaude: pulling latest from $repo ..."
    git -C $repo pull
    if ($LASTEXITCODE -ne 0) {
        Write-Error 'mmclaude: git pull failed. Check network or resolve conflicts manually.'
        exit 1
    }
    Write-Host 'mmclaude: updated.'
    exit 0
}

# ---- API key resolution ----------------------------------------------------

function Resolve-ApiKey {
    if ($env:MIMO_API_KEY) { return $env:MIMO_API_KEY }
    foreach ($scope in 'User', 'Machine') {
        $v = [Environment]::GetEnvironmentVariable('MIMO_API_KEY', $scope)
        if ($v) { return $v }
    }
    Write-Error @'
MIMO_API_KEY not found.
  Set it persistently (User scope, takes effect in new shells):
    setx MIMO_API_KEY "sk-xxxxxxxxxxxxxxxxxx"   # or tp-... for Token Plan
  Or for the current shell only:
    $env:MIMO_API_KEY = 'sk-xxxxxxxxxxxxxxxxxx'
'@
    exit 1
}

# ---- Arg parsing -----------------------------------------------------------

$WantFlash = $false

$remaining = @()
$rest = @($Rest)
$i = 0
:argloop while ($i -lt $rest.Count) {
    $a = $rest[$i]
    switch -CaseSensitive ($a) {
        'update' { Invoke-MmclaudeUpdate }
        'fast'   { $WantFlash = $true; $i++; break }
        'flash'  { $WantFlash = $true; $i++; break }
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

# Auto-detect the base URL from the key prefix; MIMO_BASE_URL always wins.
$baseUrl = if ($env:MIMO_BASE_URL) {
    $env:MIMO_BASE_URL
} elseif ($apiKey -like 'tp-*') {
    'https://token-plan-cn.xiaomimimo.com/anthropic'
} else {
    'https://api.xiaomimimo.com/anthropic'
}

$proModel   = if ($env:MIMO_MODEL)       { $env:MIMO_MODEL }       else { 'mimo-v2.5-pro' }
$flashModel = if ($env:MIMO_FLASH_MODEL) { $env:MIMO_FLASH_MODEL } else { 'mimo-v2.5' }

$mainModel = if ($WantFlash) { $flashModel } else { $proModel }

# Pick the "other" model to surface in Claude Code's /model picker.
if ($mainModel -eq $proModel) {
    $otherModel = $flashModel
    $otherDesc  = 'MiMo v2.5 — fast / cheap haiku tier'
} else {
    $otherModel = $proModel
    $otherDesc  = 'MiMo v2.5 Pro — full reasoning'
}

# ---- Export env for claude -------------------------------------------------

# MiMo docs warn that lingering official Anthropic credentials shadow
# ANTHROPIC_AUTH_TOKEN and make Claude Code hit api.anthropic.com instead.
$env:ANTHROPIC_API_KEY = $null

$env:ANTHROPIC_BASE_URL             = $baseUrl
$env:ANTHROPIC_AUTH_TOKEN           = $apiKey
$env:ANTHROPIC_MODEL                = $mainModel
$env:ANTHROPIC_DEFAULT_OPUS_MODEL   = $mainModel
$env:ANTHROPIC_DEFAULT_SONNET_MODEL = $mainModel
$env:ANTHROPIC_DEFAULT_HAIKU_MODEL  = $flashModel
# Subagents run on the cheaper flash tier.
$env:CLAUDE_CODE_SUBAGENT_MODEL     = $flashModel

# Expose the other MiMo model inside the /model picker (skip when identical).
if ($otherModel -ne $mainModel) {
    $env:ANTHROPIC_CUSTOM_MODEL_OPTION             = $otherModel
    $env:ANTHROPIC_CUSTOM_MODEL_OPTION_NAME        = $otherModel
    $env:ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION = $otherDesc
}

# ---- Launch ----------------------------------------------------------------

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Error @'
mmclaude: `claude` CLI not found on PATH.
  Install Claude Code:  npm install -g @anthropic-ai/claude-code
  Then re-run this script.
'@
    exit 1
}

$banner = "🚀 Claude Code on MiMo  →  $mainModel  ($baseUrl)"
if ($otherModel -ne $mainModel) { $banner += '  (switch mid-session via /model)' }
Write-Host $banner

& claude @remaining
exit $LASTEXITCODE
