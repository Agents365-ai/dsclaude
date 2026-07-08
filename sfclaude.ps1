#!/usr/bin/env pwsh
# sfclaude.ps1 — launch Claude Code on SiliconFlow's Anthropic-compatible API (Windows port).
#
# SiliconFlow aggregates DeepSeek, Kimi, GLM, MiniMax, Qwen, Yi and more.
# Endpoint: https://api.siliconflow.cn/
# Model catalog: https://cloud.siliconflow.cn/models
# Reads SF_API_KEY from process env first, then User/Machine env vars.
#
# Use:
#   pwsh -File ./sfclaude.ps1                  # deepseek-ai/DeepSeek-V4-PRO
#   pwsh -File ./sfclaude.ps1 fast             # deepseek-ai/DeepSeek-V3
#   pwsh -File ./sfclaude.ps1 kimi             # moonshotai/Kimi-K2-Instruct-0905
#   pwsh -File ./sfclaude.ps1 glm              # Pro/zai-org/GLM-5
#   pwsh -File ./sfclaude.ps1 minimax          # Pro/MiniMaxAI/MiniMax-M2.5
#   pwsh -File ./sfclaude.ps1 qwen             # Qwen/Qwen2.5-Coder
#   pwsh -File ./sfclaude.ps1 yi               # 01-ai/Yi-1.5
#   pwsh -File ./sfclaude.ps1 r1               # deepseek-ai/DeepSeek-R1
#   pwsh -File ./sfclaude.ps1 long             # max context window
#   pwsh -File ./sfclaude.ps1 effort max       # set effort (low|medium|high|xhigh|max)
#   pwsh -File ./sfclaude.ps1 update           # git pull
#
# Optional env overrides:
#   $env:SF_MODEL       = 'deepseek-ai/DeepSeek-V4-PRO'  # main model
#   $env:SF_FLASH_MODEL = 'deepseek-ai/DeepSeek-V3'      # flash tier
#   $env:SF_BASE_URL    = 'https://api.siliconflow.cn/'  # custom base URL
#   $env:SF_CTX         = '1048576'                       # max context tokens
#   $env:SF_OUTPUT      = '8000'                          # cap output tokens
#   $env:SF_EFFORT      = 'max'                           # CLAUDE_CODE_EFFORT_LEVEL

[CmdletBinding()]
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Rest)
$ErrorActionPreference='Stop'

if($PSVersionTable.PSVersion.Major -lt 7){Write-Error "sfclaude.ps1: PowerShell 7+ required. Install: winget install Microsoft.PowerShell";exit 1}

function Invoke-SfclaudeUpdate{$r=$null;$d=Split-Path -Parent $PSCommandPath;if(Test-Path(Join-Path $d '.git')){$r=$d};if(-not$r -and $env:SFCLAUDE_HOME){$r=$env:SFCLAUDE_HOME};if(-not$r){$c=Join-Path $env:USERPROFILE 'github\xxclaude';if(Test-Path(Join-Path $c '.git')){$r=$c}};if(-not$r){Write-Error 'sfclaude: cannot find xxclaude repo.';exit 1};Write-Host "sfclaude: pulling latest from $r ...";git -C $r pull;if($LASTEXITCODE -ne 0){Write-Error 'sfclaude: git pull failed.';exit 1};Write-Host 'sfclaude: updated.';exit 0}
function Resolve-ApiKey{if($env:SF_API_KEY){return $env:SF_API_KEY};foreach($s in 'User','Machine'){$v=[Environment]::GetEnvironmentVariable('SF_API_KEY',$s);if($v){return $v}};Write-Error "SF_API_KEY not found.`n  setx SF_API_KEY `"sk-xxxxxxxxxxxxxxxxxx`"`n  Get key: https://cloud.siliconflow.cn/account/ak";exit 1}

$mainModel=$null;$LongCtx=$false;$Effort=if($env:SF_EFFORT){$env:SF_EFFORT}else{''}
$remaining=@();$rest=@($Rest);$i=0
:argloop while($i -lt $rest.Count){$a=$rest[$i]
    switch -CaseSensitive ($a){
        'update'    {Invoke-SfclaudeUpdate}
        'max'       {$i++;break};'pro'{$i++;break}
        'fast'      {$mainModel='deepseek-ai/DeepSeek-V3';$i++;break}
        'flash'     {$mainModel='deepseek-ai/DeepSeek-V3';$i++;break}
        'lite'      {$mainModel='deepseek-ai/DeepSeek-V3';$i++;break}
        'kimi'      {$mainModel='moonshotai/Kimi-K2-Instruct-0905';$i++;break}
        'glm'       {$mainModel='Pro/zai-org/GLM-5';$i++;break}
        'minimax'   {$mainModel='Pro/MiniMaxAI/MiniMax-M2.5';$i++;break}
        'qwen'      {$mainModel='Qwen/Qwen2.5-Coder';$i++;break}
        'yi'        {$mainModel='01-ai/Yi-1.5';$i++;break}
        'r1'        {$mainModel='deepseek-ai/DeepSeek-R1';$i++;break}
        'long'      {$LongCtx=$true;$i++;break}
        'effort'    {$i++;if($i -lt $rest.Count){$l=$rest[$i];if($l -in 'low','medium','high','xhigh','max'){$Effort=$l;$i++;break}else{Write-Error "sfclaude: invalid effort level '$l'. Use: low medium high xhigh max";exit 1}}else{Write-Error "sfclaude: 'effort' requires a level";exit 1}}
        '--'        {$i++;if($i -lt $rest.Count){$remaining+=$rest[$i..($rest.Count-1)]};break argloop}
        default     {$remaining+=$rest[$i..($rest.Count-1)];break argloop}
    }
}

$apiKey=Resolve-ApiKey
$baseUrl=if($env:SF_BASE_URL){$env:SF_BASE_URL}else{'https://api.siliconflow.cn/'}
$proModel=if($env:SF_MODEL){$env:SF_MODEL}else{'deepseek-ai/DeepSeek-V4-PRO'}
$flashModel=if($env:SF_FLASH_MODEL){$env:SF_FLASH_MODEL}else{'deepseek-ai/DeepSeek-V3'}
if(-not$mainModel){$mainModel=$proModel}

switch -Wildcard ($mainModel){
    $proModel{$otherModel=$flashModel;$otherDesc='DeepSeek V3 — fast / cheap tier'}
    $flashModel{$otherModel=$proModel;$otherDesc='DeepSeek V4 PRO — full reasoning'}
    'deepseek-ai/DeepSeek-R1'{$otherModel=$proModel;$otherDesc='DeepSeek V4 PRO'}
    default{$otherModel=$proModel;$otherDesc='DeepSeek V4 PRO — full reasoning'}
}

$env:ANTHROPIC_API_KEY=$null
$env:ANTHROPIC_BASE_URL=$baseUrl;$env:ANTHROPIC_AUTH_TOKEN=$apiKey
$env:ANTHROPIC_MODEL=$mainModel;$env:ANTHROPIC_DEFAULT_OPUS_MODEL=$mainModel;$env:ANTHROPIC_DEFAULT_SONNET_MODEL=$mainModel
$env:ANTHROPIC_DEFAULT_HAIKU_MODEL=$flashModel;$env:CLAUDE_CODE_SUBAGENT_MODEL=$flashModel
if($otherModel -ne $mainModel){$env:ANTHROPIC_CUSTOM_MODEL_OPTION=$otherModel;$env:ANTHROPIC_CUSTOM_MODEL_OPTION_NAME=$otherModel;$env:ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION=$otherDesc}
if($Effort){$env:CLAUDE_CODE_EFFORT_LEVEL=$Effort}
$ctx=if($env:SF_CTX){$env:SF_CTX}elseif($LongCtx){'1048576'}else{''}
if($ctx){$env:CLAUDE_CODE_MAX_CONTEXT_TOKENS=$ctx;$env:DISABLE_COMPACT='1'}
if($env:SF_OUTPUT){$env:CLAUDE_CODE_MAX_OUTPUT_TOKENS=$env:SF_OUTPUT}

if(-not(Get-Command claude -ErrorAction SilentlyContinue)){Write-Error "sfclaude: `claude` CLI not found.`n  Install: npm install -g @anthropic-ai/claude-code";exit 1}
$banner="🚀 Claude Code on SiliconFlow  →  $mainModel  ($baseUrl)";if($ctx){$banner+="  |  ctx=$ctx"};if($Effort){$banner+="  |  effort=$Effort"};if($otherModel -ne $mainModel){$banner+='  (switch mid-session via /model)'}
Write-Host $banner;& claude @remaining;exit $LASTEXITCODE
