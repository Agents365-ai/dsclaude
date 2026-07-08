#!/usr/bin/env pwsh
# arkclaude.ps1 — launch Claude Code on Volcengine Ark's Coding Plan (Windows port).
#
# Windows companion to the macOS/Linux bash script `arkclaude`. Same env vars,
# same model aliases — different shell.
#
# Volcengine Ark is a multi-model aggregator — one Coding Plan subscription
# gives access to doubao, Kimi, DeepSeek, GLM, MiniMax, and more.
#
# Endpoint: https://ark.cn-beijing.volces.com/api/coding
#
# Reads ARK_API_KEY from the process env first, then User/Machine env vars.
#
# Quick start (from the arkclaude directory):
#   pwsh -File .\arkclaude.ps1
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
#     'C:\Users\<you>\Desktop\arkclaude\arkclaude.ps1'
# (`-NoExit` keeps the window open if the launching context doesn't have one.)
#
# Optional — make it globally available (one-time, from this dir):
#   $bin = "$env:USERPROFILE\bin"; New-Item -ItemType Directory -Force $bin | Out-Null
#   Copy-Item .\arkclaude.ps1 $bin\arkclaude.ps1
#   # then add $bin to PATH and run:  pwsh -File arkclaude.ps1
#
# Use:
#   pwsh -File ./arkclaude.ps1                  # doubao-seed-2.0-code (default)
#   pwsh -File ./arkclaude.ps1 plus             # doubao-seed-2.0-pro
#   pwsh -File ./arkclaude.ps1 fast             # doubao-seed-2.0-lite
#   pwsh -File ./arkclaude.ps1 kimi             # kimi-k2.7-code
#   pwsh -File ./arkclaude.ps1 deepseek         # deepseek-v4-pro
#   pwsh -File ./arkclaude.ps1 glm              # glm-5.2
#   pwsh -File ./arkclaude.ps1 minimax          # minimax-m2.7
#   pwsh -File ./arkclaude.ps1 long             # request max context window
#   pwsh -File ./arkclaude.ps1 effort max       # set effort (low|medium|high|xhigh|max)
#   pwsh -File ./arkclaude.ps1 update           # git pull latest from this repo
#   pwsh -File ./arkclaude.ps1 --help           # any remaining flag is forwarded to claude
#
# Optional env overrides (take precedence over positional aliases):
#   $env:ARK_MODEL      = 'doubao-seed-2.0-code'   # main model
#   $env:ARK_PLUS_MODEL = 'doubao-seed-2.0-pro'    # plus tier
#   $env:ARK_FLASH_MODEL= 'doubao-seed-2.0-lite'   # flash / haiku / subagent tier
#   $env:ARK_BASE_URL   = 'https://.../api/coding' # custom base URL
#   $env:ARK_CTX        = '1048576'                # max context tokens
#   $env:ARK_OUTPUT     = '8000'                   # cap output tokens
#   $env:ARK_EFFORT     = 'max'                    # CLAUDE_CODE_EFFORT_LEVEL
#
# In-session switch:
#   /model doubao-seed-2.0-lite  # switch to the lite tier
#   /model kimi-k2.7-code        # switch to Kimi
#   /model doubao-seed-2.0-code  # switch back
#
# Requires: PowerShell 7+ (`winget install Microsoft.PowerShell`), Claude Code
# CLI on PATH (`npm i -g @anthropic-ai/claude-code`), Volcengine ARK API key.

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)

$ErrorActionPreference = 'Stop'

# ---- PowerShell version guard ----------------------------------------------
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Error @"
arkclaude.ps1: PowerShell 7+ required (you're on $($PSVersionTable.PSVersion)).

Windows PowerShell 5.1 cannot host claude's interactive UI — the first
keystroke causes claude to exit. Install PowerShell 7 once:

  winget install Microsoft.PowerShell

Then re-run with:

  pwsh -File .\arkclaude.ps1
"@
    exit 1
}

# ---- Self-update -----------------------------------------------------------

function Invoke-ArkclaudeUpdate {
    $repo = $null
    $selfDir = Split-Path -Parent $PSCommandPath
    if (Test-Path (Join-Path $selfDir '.git')) {
        $repo = $selfDir
    }
    if (-not $repo -and $env:ARKCLAUDE_HOME) {
        $repo = $env:ARKCLAUDE_HOME
    }
    if (-not $repo) {
        $candidate = Join-Path $env:USERPROFILE 'github\xxclaude'
        if (Test-Path (Join-Path $candidate '.git')) { $repo = $candidate }
    }
    if (-not $repo) {
        Write-Error @'
arkclaude: cannot find the xxclaude repo for self-update.
  Set $env:ARKCLAUDE_HOME = 'C:\path\to\xxclaude'  or  cd into the repo and run  pwsh -File ./arkclaude.ps1 update
'@
        exit 1
    }
    Write-Host "arkclaude: pulling latest from $repo ..."
    git -C $repo pull
    if ($LASTEXITCODE -ne 0) {
        Write-Error 'arkclaude: git pull failed. Check network or resolve conflicts manually.'
        exit 1
    }
    Write-Host 'arkclaude: updated.'
    exit 0
}

# ---- API key resolution ----------------------------------------------------

function Resolve-ApiKey {
    if ($env:ARK_API_KEY) { return $env:ARK_API_KEY }
    foreach ($scope in 'User', 'Machine') {
        $v = [Environment]::GetEnvironmentVariable('ARK_API_KEY', $scope)
        if ($v) { return $v }
    }
    Write-Error @'
ARK_API_KEY not found.
  Set it persistently (User scope, takes effect in new shells):
    setx ARK_API_KEY "your_ark_api_key"
  Or for the current shell only:
    $env:ARK_API_KEY = 'your_ark_api_key'
  Get your key at: https://console.volcengine.com/ark
'@
    exit 1
}

# ---- Arg parsing -----------------------------------------------------------

$mainModel = $null
$LongCtx   = $false
$Effort    = if ($env:ARK_EFFORT) { $env:ARK_EFFORT } else { '' }

$remaining = @()
$rest = @($Rest)
$i = 0
:argloop while ($i -lt $rest.Count) {
    $a = $rest[$i]
    switch -CaseSensitive ($a) {
        'update'        { Invoke-ArkclaudeUpdate }
        # Tier aliases
        'max'           { $mainModel = $null; $i++; break }  # null → resolved below to default
        'pro'           { $mainModel = $null; $i++; break }
        'code'          { $mainModel = $null; $i++; break }
        'plus'          { $mainModel = 'doubao-seed-2.0-pro'; $i++; break }
        'fast'          { $mainModel = 'doubao-seed-2.0-lite'; $i++; break }
        'flash'         { $mainModel = 'doubao-seed-2.0-lite'; $i++; break }
        'lite'          { $mainModel = 'doubao-seed-2.0-lite'; $i++; break }
        # Provider aliases
        'kimi'          { $mainModel = 'kimi-k2.7-code'; $i++; break }
        'kimi-pro'      { $mainModel = 'kimi-k2.6'; $i++; break }
        'kimi-k2'       { $mainModel = 'kimi-k2.6'; $i++; break }
        'deepseek'      { $mainModel = 'deepseek-v4-pro'; $i++; break }
        'deepseek-flash'{ $mainModel = 'deepseek-v4-flash'; $i++; break }
        'glm'           { $mainModel = 'glm-5.2'; $i++; break }
        'minimax'       { $mainModel = 'minimax-m2.7'; $i++; break }
        'long'          { $LongCtx = $true; $i++; break }
        'effort'        {
            $i++
            if ($i -lt $rest.Count) {
                $level = $rest[$i]
                if ($level -in 'low','medium','high','xhigh','max') { $Effort = $level; $i++; break }
                else { Write-Error "arkclaude: invalid effort level '$level'. Use: low medium high xhigh max"; exit 1 }
            } else { Write-Error "arkclaude: 'effort' requires a level: low medium high xhigh max"; exit 1 }
        }
        '--'            {
            $i++
            if ($i -lt $rest.Count) { $remaining += $rest[$i..($rest.Count - 1)] }
            break argloop
        }
        default         {
            $remaining += $rest[$i..($rest.Count - 1)]
            break argloop
        }
    }
}

$apiKey = Resolve-ApiKey

$baseUrl    = if ($env:ARK_BASE_URL)    { $env:ARK_BASE_URL }    else { 'https://ark.cn-beijing.volces.com/api/coding' }
$proModel   = if ($env:ARK_MODEL)       { $env:ARK_MODEL }       else { 'doubao-seed-2.0-code' }
$plusModel  = if ($env:ARK_PLUS_MODEL)  { $env:ARK_PLUS_MODEL }  else { 'doubao-seed-2.0-pro' }
$flashModel = if ($env:ARK_FLASH_MODEL) { $env:ARK_FLASH_MODEL } else { 'doubao-seed-2.0-lite' }

# Default to pro model if no alias matched.
if (-not $mainModel) { $mainModel = $proModel }

# ---- Pick the "other" model for /model picker ------------------------------

switch -Wildcard ($mainModel) {
    $proModel {
        $otherModel = $plusModel
        $otherDesc  = 'Doubao Seed 2.0 Pro — balanced flagship'
    }
    $plusModel {
        $otherModel = $proModel
        $otherDesc  = 'Doubao Seed 2.0 Code — code specialist'
    }
    $flashModel {
        $otherModel = $proModel
        $otherDesc  = 'Doubao Seed 2.0 Code — code specialist'
    }
    'kimi-k2.7-code' {
        $otherModel = 'kimi-k2.6'
        $otherDesc  = 'Kimi K2.6 — full reasoning'
    }
    'kimi-k2.6' {
        $otherModel = 'kimi-k2.7-code'
        $otherDesc  = 'Kimi K2.7 Code — code specialist'
    }
    'deepseek-v4-pro' {
        $otherModel = 'deepseek-v4-flash'
        $otherDesc  = 'DeepSeek V4 Flash — fast tier'
    }
    'deepseek-v4-flash' {
        $otherModel = 'deepseek-v4-pro'
        $otherDesc  = 'DeepSeek V4 Pro — full reasoning'
    }
    default {
        $otherModel = $proModel
        $otherDesc  = 'Doubao Seed 2.0 Code — code specialist'
    }
}

# ---- Export env for claude -------------------------------------------------

$env:ANTHROPIC_API_KEY = $null

$env:ANTHROPIC_BASE_URL             = $baseUrl
$env:ANTHROPIC_AUTH_TOKEN           = $apiKey
$env:ANTHROPIC_MODEL                = $mainModel
$env:ANTHROPIC_DEFAULT_OPUS_MODEL   = $mainModel
$env:ANTHROPIC_DEFAULT_SONNET_MODEL = $mainModel
$env:ANTHROPIC_DEFAULT_HAIKU_MODEL  = $flashModel
# Subagents run on the cheapest tier.
$env:CLAUDE_CODE_SUBAGENT_MODEL     = $flashModel
# Keep all traffic on Ark; avoids the api.anthropic.com connection error.
$env:CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = '1'

# Expose the alternate model in the /model picker (skip when identical).
if ($otherModel -ne $mainModel) {
    $env:ANTHROPIC_CUSTOM_MODEL_OPTION             = $otherModel
    $env:ANTHROPIC_CUSTOM_MODEL_OPTION_NAME        = $otherModel
    $env:ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION = $otherDesc
}

# ---- Effort level ----------------------------------------------------------
if ($Effort) { $env:CLAUDE_CODE_EFFORT_LEVEL = $Effort }

# ---- Context window --------------------------------------------------------
$ctx = if ($env:ARK_CTX) { $env:ARK_CTX } elseif ($LongCtx) { '1048576' } else { '' }
if ($ctx) { $env:CLAUDE_CODE_MAX_CONTEXT_TOKENS = $ctx; $env:DISABLE_COMPACT = '1' }

# ---- Output cap ------------------------------------------------------------
if ($env:ARK_OUTPUT) { $env:CLAUDE_CODE_MAX_OUTPUT_TOKENS = $env:ARK_OUTPUT }

# ---- Launch ----------------------------------------------------------------

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Error @'
arkclaude: `claude` CLI not found on PATH.
  Install Claude Code:  npm install -g @anthropic-ai/claude-code
  Then re-run this script.
'@
    exit 1
}

$banner = "🚀 Claude Code on Ark  →  $mainModel  ($baseUrl)"
if ($ctx)    { $banner += "  |  ctx=$ctx" }
if ($Effort) { $banner += "  |  effort=$Effort" }
if ($otherModel -ne $mainModel) { $banner += '  (switch mid-session via /model)' }
Write-Host $banner

& claude @remaining
exit $LASTEXITCODE
