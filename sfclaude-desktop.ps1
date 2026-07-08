#!/usr/bin/env pwsh
# sfclaude-desktop.ps1 — configure Claude Desktop to use SiliconFlow (Windows port).
#
# Usage:
#   pwsh ./sfclaude-desktop.ps1                         # deepseek-ai/DeepSeek-V4-PRO
#   pwsh ./sfclaude-desktop.ps1 -ModelTier kimi         # moonshotai/Kimi-K2-Instruct-0905
#   pwsh ./sfclaude-desktop.ps1 -ModelTier glm          # Pro/zai-org/GLM-5
#   pwsh ./sfclaude-desktop.ps1 -ModelTier minimax      # Pro/MiniMaxAI/MiniMax-M2.5
#   pwsh ./sfclaude-desktop.ps1 -ModelTier qwen         # Qwen/Qwen2.5-Coder
#   pwsh ./sfclaude-desktop.ps1 -ModelTier yi           # 01-ai/Yi-1.5
#   pwsh ./sfclaude-desktop.ps1 -ModelTier r1           # deepseek-ai/DeepSeek-R1
#   pwsh ./sfclaude-desktop.ps1 -ClaudeExePath <path>   # custom Claude.exe
#   pwsh ./sfclaude-desktop.ps1 -Update                 # git pull
#   pwsh ./sfclaude-desktop.ps1 -h                      # help

[CmdletBinding()]
param([Alias('h')][switch]$Help,[switch]$Update,[string]$ClaudeExePath,
    [ValidateSet('code','max','pro','fast','flash','lite','kimi','glm','minimax','qwen','yi','r1')]
    [string]$ModelTier='code')
$ErrorActionPreference='Stop'

$ConfigDir=Join-Path $env:LOCALAPPDATA 'Claude-3p\configLibrary'
$StoreDir=if(Get-ChildItem "$env:LOCALAPPDATA\Packages\Claude_*" -ErrorAction SilentlyContinue){Join-Path(Resolve-Path "$env:LOCALAPPDATA\Packages\Claude_*")'LocalCache\Roaming\Claude-3p\configLibrary'}else{$null}
$EntryName='sfclaude-desktop';$AuthScheme='bearer';$ClaudeExe=$null

if($Help){Get-Content $PSCommandPath|Select-Object -Skip 1 -First 16|%{$_ -replace '^# ?',''};exit 0}
if($Update){$r=Split-Path -Parent $PSCommandPath;Write-Host "sfclaude-desktop: pulling latest from $r ...";git -C $r pull;if($LASTEXITCODE-eq0){Write-Host 'updated.'}else{Write-Error 'git pull failed.';exit 1};exit 0}

switch($ModelTier){
    {$_ -in 'code','max','pro'}{$m='deepseek-ai/DeepSeek-V4-PRO';$f='deepseek-ai/DeepSeek-V3';$l='DeepSeek V4 PRO'}
    {$_ -in 'fast','flash','lite'}{$m='deepseek-ai/DeepSeek-V3';$f='deepseek-ai/DeepSeek-V3';$l='DeepSeek V3'}
    'kimi'{$m='moonshotai/Kimi-K2-Instruct-0905';$f='deepseek-ai/DeepSeek-V3';$l='Kimi K2 Instruct'}
    'glm'{$m='Pro/zai-org/GLM-5';$f='Pro/zai-org/GLM-5';$l='GLM 5'}
    'minimax'{$m='Pro/MiniMaxAI/MiniMax-M2.5';$f='Pro/MiniMaxAI/MiniMax-M2.5';$l='MiniMax M2.5'}
    'qwen'{$m='Qwen/Qwen2.5-Coder';$f='Qwen/Qwen2.5-Coder';$l='Qwen 2.5 Coder'}
    'yi'{$m='01-ai/Yi-1.5';$f='01-ai/Yi-1.5';$l='Yi 1.5'}
    'r1'{$m='deepseek-ai/DeepSeek-R1';$f='deepseek-ai/DeepSeek-R1';$l='DeepSeek R1'}
}
$BaseUrl=if($env:SF_BASE_URL){$env:SF_BASE_URL}else{'https://api.siliconflow.cn/'}

function CJ{param($V)$V|ConvertTo-Json -Depth 1 -Compress}
function CJA{param([object[]]$I,[int]$D=4)$a=@($I);if($a.Count-eq0){'[]'}else{'['+(($a|%{$_|ConvertTo-Json -Depth $D -Compress})-join',')+']'}}
function WTA{param([string]$P,[string]$T)$T=$T.TrimEnd("`r","`n");$t="$P.tmp";[System.IO.File]::WriteAllText($t,$T,[System.Text.UTF8Encoding]::new($false));Move-Item $t $P -Force}

function Test-Preflight{
    $w=if($null-ne$IsWindows){$IsWindows}else{$true};if(-not$w){Write-Error 'Windows only.';exit 1}
    if($script:ClaudeExePath){if(-not(Test-Path $script:ClaudeExePath)){Write-Error "Claude.exe not found.";exit 1};$script:ClaudeExe=$script:ClaudeExePath}else{
        $c=@();$p=Get-AppxPackage -Name 'Claude*' -ErrorAction SilentlyContinue|Select-Object -First 1;if($p){$c+=Join-Path $p.InstallLocation 'app\claude.exe'}
        $pb=Join-Path $env:LOCALAPPDATA 'Packages';if(Test-Path $pb){$c+=Get-ChildItem $pb -Dir -Filter 'Claude_*' -ErrorAction SilentlyContinue|%{Join-Path $_.FullName 'LocalCache\Local\Claude-3p\claude-code\*\claude.exe'}|%{Get-ChildItem $_ -ErrorAction SilentlyContinue}|Select-Object -ExpandProperty FullName}
        $c+=@((Join-Path $env:LOCALAPPDATA 'AnthropicClaude\Claude.exe'),(Join-Path $env:LOCALAPPDATA 'Programs\AnthropicClaude\Claude.exe'),(Join-Path ${env:ProgramFiles} 'AnthropicClaude\Claude.exe'),(Join-Path ${env:ProgramFiles(x86)} 'AnthropicClaude\Claude.exe'))
        $f=$c|?{Test-Path $_}|Select-Object -First 1;if(-not$f){Write-Error "Claude Desktop not found.";exit 1};$script:ClaudeExe=$f
    }
    $ds=Join-Path $env:APPDATA 'Claude\developer_settings.json';$dd=Split-Path $ds -Parent;$ne=$false
    if(Test-Path $ds){$d=Get-Content $ds -Raw|ConvertFrom-Json;if(-not$d.allowDevTools){$ne=$true}}else{$ne=$true}
    if($ne){Write-Host 'Enabling Developer Mode...';if(-not(Test-Path $dd)){New-Item -ItemType Dir -Path $dd -Force|Out-Null};[System.IO.File]::WriteAllText($ds,'{ "allowDevTools": true }',[System.Text.UTF8Encoding]::new($false))}
}
function Resolve-ApiKey{if($env:SF_API_KEY){return$env:SF_API_KEY};foreach($s in 'User','Machine'){$v=[Environment]::GetEnvironmentVariable('SF_API_KEY',$s);if($v){return$v}};$sec=Read-Host 'SF_API_KEY not set. Paste your SiliconFlow API Key' -AsSecureString;if(-not$sec -or$sec.Length-eq0){Write-Error 'No API Key provided.';exit 1};$b=[System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec);try{return[System.Runtime.InteropServices.Marshal]::PtrToStringAuto($b)}finally{[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b)}}
function Confirm-OrAbort{param([string]$A);Write-Host '';Write-Host "About to: $A";[void](Read-Host 'Press Enter to continue, Ctrl-C to abort')}
function Update-MetaEntry{
    $dd=@($script:ConfigDir)+@(if($script:StoreDir){$script:StoreDir}else{@()});foreach($d in $dd){if(-not(Test-Path $d)){New-Item -ItemType Dir -Path $d -Force|Out-Null}}
    $eu=$null;$mp=Join-Path $dd[0] '_meta.json';$k=@()
    if(Test-Path $mp){$e=Get-Content $mp -Raw|ConvertFrom-Json;$m=$e.entries|?{$_.name -eq $script:EntryName}|Select-Object -First 1;if($m){$eu=$m.id};$k=@($e.entries|?{$_.name -ne $script:EntryName}|%{[ordered]@{id=$_.id;name=$_.name}})}
    $u=if($eu){$eu}else{[guid]::NewGuid().ToString().ToLower()}
    $entries=@($k)+@([ordered]@{id=$u;name=$script:EntryName})
    $mj="{`n  ""appliedId"": $(CJ $u),`n  ""entries"": $(CJA $entries)`n}"
    foreach($d in $dd){WTA -Path(Join-Path $d '_meta.json') -Text $mj}
    return $u
}
function Write-Entry{param([string]$U,[string]$ApiKey)
    $mo=@([ordered]@{name=$m;supports1m=$false});if($f -ne $m){$mo+=[ordered]@{name=$f;supports1m=$false}}
    $mj=CJA $mo
    $json="{`n  ""inferenceProvider"": ""gateway"",`n  ""inferenceGatewayBaseUrl"": $(CJ $BaseUrl),`n  ""inferenceGatewayApiKey"": $(CJ $ApiKey),`n  ""inferenceGatewayAuthScheme"": $(CJ $AuthScheme),`n  ""unstableDisableModelVerification"": true,`n  ""inferenceModels"": $mj`n}"
    $dd=@($script:ConfigDir)+@(if($script:StoreDir){$script:StoreDir}else{@()})
    foreach($d in $dd){WTA -Path(Join-Path $d "$U.json") -Text $json}
}
function Restart-Claude{Get-CimInstance Win32_Process -Filter "Name='claude.exe'" -ErrorAction SilentlyContinue|?{$_.CommandLine -like "*$($script:ClaudeExe)*"}|%{Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue};Start-Sleep 1;Start-Process $script:ClaudeExe}

Test-Preflight;$ak=Resolve-ApiKey
Confirm-OrAbort "configure Claude Desktop to use SiliconFlow ($BaseUrl, $l) and restart."
$uuid=Update-MetaEntry;Write-Entry -Uuid $uuid -ApiKey $ak;Restart-Claude
@"

Done. Claude Desktop is restarting with SiliconFlow ($l) as the inference backend.
Re-run sfclaude-desktop.ps1 any time to refresh the gateway config.
"@ | Write-Host
