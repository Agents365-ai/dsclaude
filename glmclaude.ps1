#!/usr/bin/env pwsh
# glmclaude.ps1 — launch Claude Code on ZhipuAI GLM's Anthropic-compatible API (Windows port).
#
# Windows companion to the macOS/Linux bash script `glmclaude`. Same env vars,
# same model picker — different shell.
#
# Uses the official ZhipuAI Anthropic-compatible endpoint:
#   - China (default): https://open.bigmodel.cn/api/anthropic
#   - International:   https://api.z.ai/api/anthropic          (set $env:GLM_BASE_URL)
#
# Reads GLM_API_KEY from the process env first, then User/Machine env vars.
#
# Quick start (from the glmclaude directory):
#   pwsh -File .\glmclaude.ps1
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
#     'C:\Users\<you>\Desktop\glmclaude\glmclaude.ps1'
# (`-NoExit` keeps the window open if the launching context doesn't have one.)
#
# Optional — make it globally available (one-time, from this dir):
#   $bin = "$env:USERPROFILE\bin"; New-Item -ItemType Directory -Force $bin | Out-Null
#   Copy-Item .\glmclaude.ps1 $bin\glmclaude.ps1
#   # then add $bin to PATH and run:  pwsh -File glmclaude.ps1
#
# Use:
#   pwsh -File ./glmclaude.ps1                  # glm-5.2 (ZhipuAI default)
#   pwsh -File ./glmclaude.ps1 fast             # run the flash tier (glm-4.7) as main
#   pwsh -File ./glmclaude.ps1 long             # request max context window
#   pwsh -File ./glmclaude.ps1 effort max       # set effort (low|medium|high|xhigh|max)
#   pwsh -File ./glmclaude.ps1 update           # git pull latest from this repo
#   pwsh -File ./glmclaude.ps1 --help           # any remaining flag is forwarded to claude
#
# Optional env overrides (take precedence over positional aliases):
#   $env:GLM_MODEL       = 'glm-5.2'            # main model
#   $env:GLM_FLASH_MODEL = 'glm-4.7'            # flash / haiku / subagent tier
#   $env:GLM_BASE_URL    = 'https://api.z.ai/api/anthropic'  # custom base URL
#   $env:GLM_CTX         = '1048576'            # max context tokens
#   $env:GLM_OUTPUT      = '8000'               # cap output tokens
#   $env:GLM_EFFORT      = 'max'                # CLAUDE_CODE_EFFORT_LEVEL
#
# In-session switch:
#   /model glm-4.7        # switch to the flash tier
#   /model glm-5.2        # switch back to the main model
#
# Requires: PowerShell 7+ (`winget install Microsoft.PowerShell`), Claude Code
# CLI on PATH (`npm i -g @anthropic-ai/claude-code`), ZhipuAI GLM API key.

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
glmclaude.ps1: PowerShell 7+ required (you're on $($PSVersionTable.PSVersion)).

Windows PowerShell 5.1 cannot host claude's interactive UI — the first
keystroke causes claude to exit. Install PowerShell 7 once:

  winget install Microsoft.PowerShell

Then re-run with:

  pwsh -File .\glmclaude.ps1
"@
    exit 1
}

# ---- Self-update -----------------------------------------------------------

function Invoke-GlmclaudeUpdate {
    $repo = $null
    $selfDir = Split-Path -Parent $PSCommandPath
    if (Test-Path (Join-Path $selfDir '.git')) {
        $repo = $selfDir
    }
    if (-not $repo -and $env:GLMCLAUDE_HOME) {
        $repo = $env:GLMCLAUDE_HOME
    }
    if (-not $repo) {
        $candidate = Join-Path $env:USERPROFILE 'github\xxclaude'
        if (Test-Path (Join-Path $candidate '.git')) { $repo = $candidate }
    }
    if (-not $repo) {
        Write-Error @'
glmclaude: cannot find the xxclaude repo for self-update.
  Set $env:GLMCLAUDE_HOME = 'C:\path\to\xxclaude'  or  cd into the repo and run  pwsh -File ./glmclaude.ps1 update
'@
        exit 1
    }
    Write-Host "glmclaude: pulling latest from $repo ..."
    git -C $repo pull
    if ($LASTEXITCODE -ne 0) {
        Write-Error 'glmclaude: git pull failed. Check network or resolve conflicts manually.'
        exit 1
    }
    Write-Host 'glmclaude: updated.'
    exit 0
}

# ---- API key resolution ----------------------------------------------------

function Resolve-ApiKey {
    if ($env:GLM_API_KEY) { return $env:GLM_API_KEY }
    foreach ($scope in 'User', 'Machine') {
        $v = [Environment]::GetEnvironmentVariable('GLM_API_KEY', $scope)
        if ($v) { return $v }
    }
    Write-Error @'
GLM_API_KEY not found.
  Set it persistently (User scope, takes effect in new shells):
    setx GLM_API_KEY "your_zhipu_api_key"
  Or for the current shell only:
    $env:GLM_API_KEY = 'your_zhipu_api_key'
  Get your key at: https://open.bigmodel.cn/usercenter/apikeys
'@
    exit 1
}

# ---- Arg parsing -----------------------------------------------------------

$WantFlash = $false
$LongCtx   = $false
$Effort    = if ($env:GLM_EFFORT) { $env:GLM_EFFORT } else { '' }

$remaining = @()
$rest = @($Rest)
$i = 0
:argloop while ($i -lt $rest.Count) {
    $a = $rest[$i]
    switch -CaseSensitive ($a) {
        'update' { Invoke-GlmclaudeUpdate }
        'fast'   { $WantFlash = $true; $i++; break }
        'flash'  { $WantFlash = $true; $i++; break }
        'long'   { $LongCtx = $true; $i++; break }
        'effort' {
            $i++; if ($i -lt $rest.Count) { $l=$rest[$i]; if ($l -in 'low','medium','high','xhigh','max'){$Effort=$l;$i++;break}else{Write-Error "glmclaude: invalid effort level '$l'. Use: low medium high xhigh max";exit 1}}else{Write-Error "glmclaude: 'effort' requires a level: low medium high xhigh max";exit 1}
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

$baseUrl    = if ($env:GLM_BASE_URL)    { $env:GLM_BASE_URL }    else { 'https://open.bigmodel.cn/api/anthropic' }
$proModel   = if ($env:GLM_MODEL)       { $env:GLM_MODEL }       else { 'glm-5.2' }
$flashModel = if ($env:GLM_FLASH_MODEL) { $env:GLM_FLASH_MODEL } else { 'glm-4.7' }

$mainModel = if ($WantFlash) { $flashModel } else { $proModel }

# Pick the "other" model to surface in Claude Code's /model picker.
if ($mainModel -eq $proModel) {
    $otherModel = $flashModel
    $otherDesc  = 'GLM 4.7 — fast / cheap tier'
} else {
    $otherModel = $proModel
    $otherDesc  = 'GLM 5.2 — full reasoning'
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

# Expose the other GLM model inside the /model picker (skip when identical).
if ($otherModel -ne $mainModel) {
    $env:ANTHROPIC_CUSTOM_MODEL_OPTION             = $otherModel
    $env:ANTHROPIC_CUSTOM_MODEL_OPTION_NAME        = $otherModel
    $env:ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION = $otherDesc
}

# ---- Effort level ----------------------------------------------------------
if ($Effort) { $env:CLAUDE_CODE_EFFORT_LEVEL = $Effort }

# ---- Context window --------------------------------------------------------
$ctx = if ($env:GLM_CTX) { $env:GLM_CTX } elseif ($LongCtx) { '1048576' } else { '' }
if ($ctx) { $env:CLAUDE_CODE_MAX_CONTEXT_TOKENS = $ctx; $env:DISABLE_COMPACT = '1' }

# ---- Output cap ------------------------------------------------------------
if ($env:GLM_OUTPUT) { $env:CLAUDE_CODE_MAX_OUTPUT_TOKENS = $env:GLM_OUTPUT }

# ---- Launch ----------------------------------------------------------------

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Error @'
glmclaude: `claude` CLI not found on PATH.
  Install Claude Code:  npm install -g @anthropic-ai/claude-code
  Then re-run this script.
'@
    exit 1
}

$banner = "🚀 Claude Code on GLM  →  $mainModel  ($baseUrl)"
if ($ctx)    { $banner += "  |  ctx=$ctx" }
if ($Effort) { $banner += "  |  effort=$Effort" }
if ($otherModel -ne $mainModel) { $banner += '  (switch mid-session via /model)' }
Write-Host $banner

& claude @remaining
exit $LASTEXITCODE
