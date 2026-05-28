#!/usr/bin/env pwsh
# qwclaude.ps1 — launch Claude Code on Alibaba Cloud Bailian's Qwen models (Windows port).
#
# Windows companion to the macOS/Linux bash script `qwclaude`. Same env vars,
# same plan/model selection, same model picker — different shell.
#
# Follows the official Bailian "Claude Code 配置" guide. Three billing plans,
# each with its own base URL and model lineup:
#   - Pay-as-you-go : https://dashscope.aliyuncs.com/apps/anthropic        (Beijing)
#                     https://dashscope-intl.aliyuncs.com/apps/anthropic   (Singapore)
#   - Coding Plan   : https://coding.dashscope.aliyuncs.com/apps/anthropic
#   - Token Plan    : https://token-plan.cn-beijing.maas.aliyuncs.com/apps/anthropic
#
# Reads the plan-specific Bailian API key from the process env first, then
# User/Machine env vars:
#   - Pay-as-you-go : DASHSCOPE_API_KEY
#   - Coding Plan   : DASHSCOPE_CP_API_KEY
#   - Token Plan    : DASHSCOPE_TP_API_KEY
#
# Quick start (from the qwclaude directory):
#   pwsh -File .\qwclaude.ps1
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
#     'C:\Users\<you>\Desktop\qwclaude\qwclaude.ps1'
# (`-NoExit` keeps the window open if the launching context doesn't have one.)
#
# Optional — make it globally available (one-time, from this dir):
#   $bin = "$env:USERPROFILE\bin"; New-Item -ItemType Directory -Force $bin | Out-Null
#   Copy-Item .\qwclaude.ps1 $bin\qwclaude.ps1
#   # then add $bin to PATH and run:  pwsh -File qwclaude.ps1
#
# Use:
#   pwsh -File ./qwclaude.ps1                  # pay-as-you-go, qwen3.7-max (Beijing)
#   pwsh -File ./qwclaude.ps1 fast             # run the flash tier (qwen3.6-flash) as main
#   pwsh -File ./qwclaude.ps1 intl             # pay-as-you-go on the Singapore endpoint
#   pwsh -File ./qwclaude.ps1 coding           # Coding Plan (qwen3.6-plus)
#   pwsh -File ./qwclaude.ps1 token            # Token Plan team edition (qwen3.7-max)
#   pwsh -File ./qwclaude.ps1 coding fast      # combine plan + flash
#   pwsh -File ./qwclaude.ps1 update           # git pull latest from this repo
#   pwsh -File ./qwclaude.ps1 --help           # any remaining flag is forwarded to claude
#
# Optional env overrides (take precedence over positional aliases):
#   $env:QWEN_PLAN       = 'coding'            # payg | coding | token-plan
#   $env:QWEN_REGION     = 'intl'              # cn (Beijing) | intl (Singapore), payg only
#   $env:QWEN_MODEL      = 'qwen3.7-max'       # main model
#   $env:QWEN_FLASH_MODEL= 'qwen3.6-flash'     # flash / haiku / subagent tier
#   $env:QWEN_BASE_URL   = 'https://.../apps/anthropic'  # custom base URL
#
# In-session switch:
#   /model qwen3.6-flash                       # switch to the flash tier
#   /model qwen3.7-max                         # switch back to the main model
#
# Requires: PowerShell 7+ (`winget install Microsoft.PowerShell`), Claude Code
# CLI on PATH (`npm i -g @anthropic-ai/claude-code`), Bailian API key.

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
qwclaude.ps1: PowerShell 7+ required (you're on $($PSVersionTable.PSVersion)).

Windows PowerShell 5.1 cannot host claude's interactive UI — the first
keystroke causes claude to exit. Install PowerShell 7 once:

  winget install Microsoft.PowerShell

Then re-run with:

  pwsh -File .\qwclaude.ps1
"@
    exit 1
}

# ---- Self-update -----------------------------------------------------------

function Invoke-QwclaudeUpdate {
    $repo = $null
    $selfDir = Split-Path -Parent $PSCommandPath
    if (Test-Path (Join-Path $selfDir '.git')) {
        $repo = $selfDir
    }
    if (-not $repo -and $env:QWCLAUDE_HOME) {
        $repo = $env:QWCLAUDE_HOME
    }
    if (-not $repo) {
        $candidate = Join-Path $env:USERPROFILE 'github\xxclaude'
        if (Test-Path (Join-Path $candidate '.git')) { $repo = $candidate }
    }
    if (-not $repo) {
        Write-Error @'
qwclaude: cannot find the xxclaude repo for self-update.
  Set $env:QWCLAUDE_HOME = 'C:\path\to\xxclaude'  or  cd into the repo and run  pwsh -File ./qwclaude.ps1 update
'@
        exit 1
    }
    Write-Host "qwclaude: pulling latest from $repo ..."
    git -C $repo pull
    if ($LASTEXITCODE -ne 0) {
        Write-Error 'qwclaude: git pull failed. Check network or resolve conflicts manually.'
        exit 1
    }
    Write-Host 'qwclaude: updated.'
    exit 0
}

# ---- API key resolution ----------------------------------------------------

function Resolve-ApiKey {
    param([string]$Name, [string]$PlanLabel)
    $v = [Environment]::GetEnvironmentVariable($Name, 'Process')
    if ($v) { return $v }
    foreach ($scope in 'User', 'Machine') {
        $v = [Environment]::GetEnvironmentVariable($Name, $scope)
        if ($v) { return $v }
    }
    Write-Error @"
$Name not found (needed for Bailian $PlanLabel).
  Set it persistently (User scope, takes effect in new shells):
    setx $Name "sk-xxxxxxxxxxxxxxxxxx"
  Or for the current shell only:
    `$env:$Name = 'sk-xxxxxxxxxxxxxxxxxx'
"@
    exit 1
}

# ---- Arg parsing -----------------------------------------------------------

$Plan      = if ($env:QWEN_PLAN)   { $env:QWEN_PLAN }   else { 'payg' }
$Region    = if ($env:QWEN_REGION) { $env:QWEN_REGION } else { 'cn' }
$WantFlash = $false

$remaining = @()
$rest = @($Rest)
$i = 0
:argloop while ($i -lt $rest.Count) {
    $a = $rest[$i]
    switch -CaseSensitive ($a) {
        'update'     { Invoke-QwclaudeUpdate }
        'coding'     { $Plan = 'coding';     $i++; break }
        'token-plan' { $Plan = 'token-plan'; $i++; break }
        'token'      { $Plan = 'token-plan'; $i++; break }
        'tp'         { $Plan = 'token-plan'; $i++; break }
        'payg'       { $Plan = 'payg';       $i++; break }
        'intl'       { $Region = 'intl';     $i++; break }
        'singapore'  { $Region = 'intl';     $i++; break }
        'sg'         { $Region = 'intl';     $i++; break }
        'cn'         { $Region = 'cn';       $i++; break }
        'beijing'    { $Region = 'cn';       $i++; break }
        'fast'       { $WantFlash = $true;   $i++; break }
        'flash'      { $WantFlash = $true;   $i++; break }
        '--'         {
            $i++
            if ($i -lt $rest.Count) { $remaining += $rest[$i..($rest.Count - 1)] }
            break argloop
        }
        default      {
            $remaining += $rest[$i..($rest.Count - 1)]
            break argloop
        }
    }
}

# ---- Resolve base URL, model lineup, and key variable from the chosen plan -

switch ($Plan) {
    'token-plan' {
        $baseUrlDefault   = 'https://token-plan.cn-beijing.maas.aliyuncs.com/apps/anthropic'
        $proModelDefault  = 'qwen3.7-max'
        $flashModelDefault= 'qwen3.6-flash'
        $planLabel        = 'Token Plan'
        $keyVar           = 'DASHSCOPE_TP_API_KEY'
    }
    'coding' {
        # Coding Plan only serves qwen3.6-plus — no separate flash tier.
        $baseUrlDefault   = 'https://coding.dashscope.aliyuncs.com/apps/anthropic'
        $proModelDefault  = 'qwen3.6-plus'
        $flashModelDefault= 'qwen3.6-plus'
        $planLabel        = 'Coding Plan'
        $keyVar           = 'DASHSCOPE_CP_API_KEY'
    }
    default {
        $Plan = 'payg'
        if ($Region -eq 'intl') {
            $baseUrlDefault = 'https://dashscope-intl.aliyuncs.com/apps/anthropic'
        } else {
            $baseUrlDefault = 'https://dashscope.aliyuncs.com/apps/anthropic'
        }
        $proModelDefault  = 'qwen3.7-max'
        $flashModelDefault= 'qwen3.6-flash'
        $planLabel        = 'pay-as-you-go'
        $keyVar           = 'DASHSCOPE_API_KEY'
    }
}

$apiKey = Resolve-ApiKey $keyVar $planLabel

$baseUrl    = if ($env:QWEN_BASE_URL)    { $env:QWEN_BASE_URL }    else { $baseUrlDefault }
$proModel   = if ($env:QWEN_MODEL)       { $env:QWEN_MODEL }       else { $proModelDefault }
$flashModel = if ($env:QWEN_FLASH_MODEL) { $env:QWEN_FLASH_MODEL } else { $flashModelDefault }

$mainModel = if ($WantFlash) { $flashModel } else { $proModel }

# Pick the "other" model to surface in Claude Code's /model picker.
if ($mainModel -eq $proModel) {
    $otherModel = $flashModel
    $otherDesc  = 'Qwen flash — fast / cheap haiku tier'
} else {
    $otherModel = $proModel
    $otherDesc  = 'Qwen — full reasoning'
}

# ---- Export env for claude -------------------------------------------------

# Bailian docs warn that lingering official Anthropic credentials shadow
# ANTHROPIC_AUTH_TOKEN and make Claude Code hit api.anthropic.com instead.
$env:ANTHROPIC_API_KEY = $null

$env:ANTHROPIC_BASE_URL             = $baseUrl
$env:ANTHROPIC_AUTH_TOKEN           = $apiKey
$env:API_TIMEOUT_MS                 = '600000'
$env:ANTHROPIC_MODEL                = $mainModel
$env:ANTHROPIC_DEFAULT_OPUS_MODEL   = $mainModel
$env:ANTHROPIC_DEFAULT_SONNET_MODEL = $mainModel
$env:ANTHROPIC_DEFAULT_HAIKU_MODEL  = $flashModel
# Subagents run on the cheaper flash tier.
$env:CLAUDE_CODE_SUBAGENT_MODEL     = $flashModel
# Keep all traffic on Bailian; avoids the api.anthropic.com connection error.
$env:CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = '1'

# Expose the other Qwen model inside the /model picker (skip when identical).
if ($otherModel -ne $mainModel) {
    $env:ANTHROPIC_CUSTOM_MODEL_OPTION             = $otherModel
    $env:ANTHROPIC_CUSTOM_MODEL_OPTION_NAME        = $otherModel
    $env:ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION = $otherDesc
}

# ---- Launch ----------------------------------------------------------------

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Error @'
qwclaude: `claude` CLI not found on PATH.
  Install Claude Code:  npm install -g @anthropic-ai/claude-code
  Then re-run this script.
'@
    exit 1
}

$banner = "🚀 Claude Code on Qwen (Bailian $planLabel)  →  $mainModel  ($baseUrl)"
if ($otherModel -ne $mainModel) { $banner += '  (switch mid-session via /model)' }
Write-Host $banner

& claude @remaining
exit $LASTEXITCODE
