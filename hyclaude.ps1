#!/usr/bin/env pwsh
# hyclaude.ps1 — launch Claude Code on Tencent TokenHub's Anthropic-compatible API (Windows port).
#
# Tencent TokenHub aggregates Hunyuan, DeepSeek, GLM, Kimi, MiniMax, Qwen.
# One subscription, one endpoint, many models.
#
# Endpoint: https://api.lkeap.cloud.tencent.com/plan/anthropic
# Reads HY_API_KEY from process env first, then User/Machine env vars.
#
# Use:
#   pwsh -File ./hyclaude.ps1                  # hy3-preview (Tencent default)
#   pwsh -File ./hyclaude.ps1 fast             # hy-mt2-lite
#   pwsh -File ./hyclaude.ps1 kimi             # kimi-k2.7-code
#   pwsh -File ./hyclaude.ps1 deepseek         # deepseek-v4-pro
#   pwsh -File ./hyclaude.ps1 glm              # glm-5.2
#   pwsh -File ./hyclaude.ps1 minimax          # minimax-m3
#   pwsh -File ./hyclaude.ps1 qwen             # qwen3.5-plus
#   pwsh -File ./hyclaude.ps1 long             # max context window
#   pwsh -File ./hyclaude.ps1 effort max       # set effort (low|medium|high|xhigh|max)
#   pwsh -File ./hyclaude.ps1 update           # git pull
#
# Optional env overrides:
#   $env:HY_MODEL       = 'hy3-preview'          # main model
#   $env:HY_FLASH_MODEL = 'hy-mt2-lite'          # flash tier
#   $env:HY_BASE_URL    = 'https://.../anthropic' # custom base URL
#   $env:HY_CTX         = '1048576'              # max context tokens
#   $env:HY_OUTPUT      = '8000'                 # cap output tokens
#   $env:HY_EFFORT      = 'max'                  # CLAUDE_CODE_EFFORT_LEVEL

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Error @"
hyclaude.ps1: PowerShell 7+ required (you're on $($PSVersionTable.PSVersion)).
Install once:  winget install Microsoft.PowerShell
Then:  pwsh -File .\hyclaude.ps1
"@
    exit 1
}

function Invoke-HyclaudeUpdate {
    $repo = $null; $selfDir = Split-Path -Parent $PSCommandPath
    if (Test-Path (Join-Path $selfDir '.git')) { $repo = $selfDir }
    if (-not $repo -and $env:HYCLAUDE_HOME) { $repo = $env:HYCLAUDE_HOME }
    if (-not $repo) { $c = Join-Path $env:USERPROFILE 'github\xxclaude'; if (Test-Path (Join-Path $c '.git')) { $repo = $c } }
    if (-not $repo) { Write-Error "hyclaude: cannot find xxclaude repo."; exit 1 }
    Write-Host "hyclaude: pulling latest from $repo ..."
    git -C $repo pull; if ($LASTEXITCODE -ne 0) { Write-Error 'hyclaude: git pull failed.'; exit 1 }
    Write-Host 'hyclaude: updated.'; exit 0
}

function Resolve-ApiKey {
    if ($env:HY_API_KEY) { return $env:HY_API_KEY }
    foreach ($scope in 'User','Machine') { $v=[Environment]::GetEnvironmentVariable('HY_API_KEY',$scope); if($v){return $v} }
    Write-Error "HY_API_KEY not found.`n  setx HY_API_KEY `"your_api_key`"`n  Get your key: https://cloud.tencent.com/product/lkeap"; exit 1
}

$mainModel = $null; $LongCtx = $false; $Effort = if($env:HY_EFFORT){$env:HY_EFFORT}else{''}
$remaining = @(); $rest = @($Rest); $i = 0
:argloop while ($i -lt $rest.Count) {
    $a = $rest[$i]
    switch -CaseSensitive ($a) {
        'update'        { Invoke-HyclaudeUpdate }
        'max'           { $i++; break }; 'pro' { $i++; break }; 'code' { $i++; break }
        'fast'          { $mainModel = 'hy-mt2-lite'; $i++; break }
        'flash'         { $mainModel = 'hy-mt2-lite'; $i++; break }
        'lite'          { $mainModel = 'hy-mt2-lite'; $i++; break }
        'kimi'          { $mainModel = 'kimi-k2.7-code'; $i++; break }
        'kimi-pro'      { $mainModel = 'kimi-k2.6'; $i++; break }
        'kimi-k2'       { $mainModel = 'kimi-k2.6'; $i++; break }
        'deepseek'      { $mainModel = 'deepseek-v4-pro'; $i++; break }
        'deepseek-flash'{ $mainModel = 'deepseek-v4-flash'; $i++; break }
        'glm'           { $mainModel = 'glm-5.2'; $i++; break }
        'minimax'       { $mainModel = 'minimax-m3'; $i++; break }
        'qwen'          { $mainModel = 'qwen3.5-plus'; $i++; break }
        'long'          { $LongCtx=$true; $i++; break }
        'effort'        { $i++; if($i -lt $rest.Count){$l=$rest[$i];if($l -in 'low','medium','high','xhigh','max'){$Effort=$l;$i++;break}else{Write-Error "hyclaude: invalid effort level '$l'. Use: low medium high xhigh max";exit 1}}else{Write-Error "hyclaude: 'effort' requires a level";exit 1} }
        '--'            { $i++; if($i -lt $rest.Count){$remaining+=$rest[$i..($rest.Count-1)]}; break argloop }
        default         { $remaining+=$rest[$i..($rest.Count-1)]; break argloop }
    }
}

$apiKey = Resolve-ApiKey
$baseUrl    = if($env:HY_BASE_URL)   {$env:HY_BASE_URL}    else{'https://api.lkeap.cloud.tencent.com/plan/anthropic'}
$proModel   = if($env:HY_MODEL)      {$env:HY_MODEL}       else{'hy3-preview'}
$flashModel = if($env:HY_FLASH_MODEL){$env:HY_FLASH_MODEL} else{'hy-mt2-lite'}
if(-not $mainModel){$mainModel=$proModel}

switch -Wildcard ($mainModel) {
    $proModel         { $otherModel=$flashModel; $otherDesc='HY MT2 Lite — fast / cheap tier' }
    $flashModel       { $otherModel=$proModel;   $otherDesc='HY3 Preview — Tencent flagship' }
    'kimi-k2.7-code'  { $otherModel='kimi-k2.6'; $otherDesc='Kimi K2.6' }
    'kimi-k2.6'       { $otherModel='kimi-k2.7-code'; $otherDesc='Kimi K2.7 Code' }
    'deepseek-v4-pro' { $otherModel='deepseek-v4-flash'; $otherDesc='DeepSeek V4 Flash' }
    'deepseek-v4-flash'{ $otherModel='deepseek-v4-pro'; $otherDesc='DeepSeek V4 Pro' }
    default           { $otherModel=$proModel;   $otherDesc='HY3 Preview' }
}

$env:ANTHROPIC_API_KEY=$null
$env:ANTHROPIC_BASE_URL=$baseUrl; $env:ANTHROPIC_AUTH_TOKEN=$apiKey
$env:ANTHROPIC_MODEL=$mainModel; $env:ANTHROPIC_DEFAULT_OPUS_MODEL=$mainModel; $env:ANTHROPIC_DEFAULT_SONNET_MODEL=$mainModel
$env:ANTHROPIC_DEFAULT_HAIKU_MODEL=$flashModel; $env:CLAUDE_CODE_SUBAGENT_MODEL=$flashModel
$env:CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC='1'
if($otherModel -ne $mainModel){
    $env:ANTHROPIC_CUSTOM_MODEL_OPTION=$otherModel; $env:ANTHROPIC_CUSTOM_MODEL_OPTION_NAME=$otherModel
    $env:ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION=$otherDesc
}
if($Effort){$env:CLAUDE_CODE_EFFORT_LEVEL=$Effort}
$ctx=if($env:HY_CTX){$env:HY_CTX}elseif($LongCtx){'1048576'}else{''}
if($ctx){$env:CLAUDE_CODE_MAX_CONTEXT_TOKENS=$ctx;$env:DISABLE_COMPACT='1'}
if($env:HY_OUTPUT){$env:CLAUDE_CODE_MAX_OUTPUT_TOKENS=$env:HY_OUTPUT}

if(-not(Get-Command claude -ErrorAction SilentlyContinue)){Write-Error "hyclaude: `claude` CLI not found.`n  Install: npm install -g @anthropic-ai/claude-code";exit 1}

$banner="🚀 Claude Code on TokenHub  →  $mainModel  ($baseUrl)"
if($ctx){$banner+="  |  ctx=$ctx"}; if($Effort){$banner+="  |  effort=$Effort"}
if($otherModel -ne $mainModel){$banner+='  (switch mid-session via /model)'}
Write-Host $banner; & claude @remaining; exit $LASTEXITCODE
