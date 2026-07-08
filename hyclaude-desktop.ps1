#!/usr/bin/env pwsh
# hyclaude-desktop.ps1 — configure Claude Desktop to use Tencent TokenHub (Windows port).
#
# Usage:
#   pwsh ./hyclaude-desktop.ps1                         # hy3-preview
#   pwsh ./hyclaude-desktop.ps1 -ModelTier kimi         # kimi-k2.7-code
#   pwsh ./hyclaude-desktop.ps1 -ModelTier deepseek     # deepseek-v4-pro
#   pwsh ./hyclaude-desktop.ps1 -ModelTier glm          # glm-5.2
#   pwsh ./hyclaude-desktop.ps1 -ClaudeExePath <path>   # custom Claude.exe
#   pwsh ./hyclaude-desktop.ps1 -Update                 # git pull
#   pwsh ./hyclaude-desktop.ps1 -h                      # help

[CmdletBinding()]
param([Alias('h')][switch]$Help,[switch]$Update,[string]$ClaudeExePath,
    [ValidateSet('code','max','pro','fast','flash','lite','kimi','kimi-pro','kimi-k2','deepseek','deepseek-flash','glm','minimax','qwen')]
    [string]$ModelTier='code')

$ErrorActionPreference='Stop'
$ConfigDir=Join-Path $env:LOCALAPPDATA 'Claude-3p\configLibrary'
$StoreDir=if(Get-ChildItem "$env:LOCALAPPDATA\Packages\Claude_*" -ErrorAction SilentlyContinue){Join-Path(Resolve-Path "$env:LOCALAPPDATA\Packages\Claude_*")'LocalCache\Roaming\Claude-3p\configLibrary'}else{$null}
$EntryName='hyclaude-desktop'; $AuthScheme='bearer'; $ClaudeExe=$null

if($Help){Get-Content $PSCommandPath|Select-Object -Skip 1 -First 14|%{$_ -replace '^# ?',''};exit 0}
if($Update){$r=Split-Path -Parent $PSCommandPath;Write-Host "hyclaude-desktop: pulling latest from $r ...";git -C $r pull;if($LASTEXITCODE -eq 0){Write-Host 'updated.'}else{Write-Error 'git pull failed.';exit 1};exit 0}

switch($ModelTier){
    {$_ -in 'code','max','pro'}{$m='hy3-preview';$f='hy-mt2-lite';$l='HY3 Preview'}
    {$_ -in 'fast','flash','lite'}{$m='hy-mt2-lite';$f='hy-mt2-lite';$l='HY MT2 Lite'}
    'kimi'{$m='kimi-k2.7-code';$f='hy-mt2-lite';$l='Kimi K2.7 Code'}
    {$_ -in 'kimi-pro','kimi-k2'}{$m='kimi-k2.6';$f='kimi-k2.6';$l='Kimi K2.6'}
    'deepseek'{$m='deepseek-v4-pro';$f='deepseek-v4-flash';$l='DeepSeek V4 Pro'}
    'deepseek-flash'{$m='deepseek-v4-flash';$f='deepseek-v4-flash';$l='DeepSeek V4 Flash'}
    'glm'{$m='glm-5.2';$f='glm-5.2';$l='GLM 5.2'}
    'minimax'{$m='minimax-m3';$f='minimax-m3';$l='MiniMax M3'}
    'qwen'{$m='qwen3.5-plus';$f='qwen3.5-plus';$l='Qwen 3.5 Plus'}
}
$BaseUrl=if($env:HY_BASE_URL){$env:HY_BASE_URL}else{'https://api.lkeap.cloud.tencent.com/plan/anthropic'}

function ConvertTo-JsonScalar{param($V)$V|ConvertTo-Json -Depth 1 -Compress}
function ConvertTo-JsonArrayString{param([object[]]$I,[int]$D=4)$a=@($I);if($a.Count -eq 0){'[]'}else{'['+(($a|%{$_|ConvertTo-Json -Depth $D -Compress})-join',')+']'}}
function Write-TextAtomic{param([string]$P,[string]$T)$T=$T.TrimEnd("`r","`n");$t="$P.tmp";[System.IO.File]::WriteAllText($t,$T,[System.Text.UTF8Encoding]::new($false));Move-Item $t $P -Force}

function Test-Preflight{
    $w=if($null -ne $IsWindows){$IsWindows}else{$true};if(-not $w){Write-Error 'Windows only.';exit 1}
    if($script:ClaudeExePath){
        if(-not(Test-Path $script:ClaudeExePath)){Write-Error "Claude.exe not found at '$script:ClaudeExePath'";exit 1}
        $script:ClaudeExe=$script:ClaudeExePath
    }else{
        $c=@();$p=Get-AppxPackage -Name 'Claude*' -ErrorAction SilentlyContinue|Select-Object -First 1
        if($p){$c+=Join-Path $p.InstallLocation 'app\claude.exe'}
        $pb=Join-Path $env:LOCALAPPDATA 'Packages'
        if(Test-Path $pb){$c+=Get-ChildItem $pb -Dir -Filter 'Claude_*' -ErrorAction SilentlyContinue|%{Join-Path $_.FullName 'LocalCache\Local\Claude-3p\claude-code\*\claude.exe'}|%{Get-ChildItem $_ -ErrorAction SilentlyContinue}|Select-Object -ExpandProperty FullName}
        $c+=@((Join-Path $env:LOCALAPPDATA 'AnthropicClaude\Claude.exe'),(Join-Path $env:LOCALAPPDATA 'Programs\AnthropicClaude\Claude.exe'),(Join-Path ${env:ProgramFiles} 'AnthropicClaude\Claude.exe'),(Join-Path ${env:ProgramFiles(x86)} 'AnthropicClaude\Claude.exe'))
        $f=$c|?{Test-Path $_}|Select-Object -First 1;if(-not $f){Write-Error "Claude Desktop not found.";exit 1}
        $script:ClaudeExe=$f
    }
    $ds=Join-Path $env:APPDATA 'Claude\developer_settings.json';$dd=Split-Path $ds -Parent;$ne=$false
    if(Test-Path $ds){$d=Get-Content $ds -Raw|ConvertFrom-Json;if(-not $d.allowDevTools){$ne=$true}}else{$ne=$true}
    if($ne){Write-Host 'Enabling Developer Mode...';if(-not(Test-Path $dd)){New-Item -ItemType Dir -Path $dd -Force|Out-Null};[System.IO.File]::WriteAllText($ds,'{ "allowDevTools": true }',[System.Text.UTF8Encoding]::new($false))}
}
function Resolve-ApiKey{
    if($env:HY_API_KEY){return $env:HY_API_KEY}
    foreach($s in 'User','Machine'){$v=[Environment]::GetEnvironmentVariable('HY_API_KEY',$s);if($v){return $v}}
    $sec=Read-Host 'HY_API_KEY not set. Paste your Tencent TokenHub API Key' -AsSecureString
    if(-not $sec -or $sec.Length -eq 0){Write-Error 'No API Key provided.';exit 1}
    $b=[System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec);try{return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($b)}finally{[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b)}
}
function Confirm-OrAbort{param([string]$A);Write-Host '';Write-Host "About to: $A";[void](Read-Host 'Press Enter to continue, Ctrl-C to abort')}
function Update-MetaEntry{
    $d=@($script:ConfigDir)+@(if($script:StoreDir){$script:StoreDir}else{@()});foreach($dd in $d){if(-not(Test-Path $dd)){New-Item -ItemType Dir -Path $dd -Force|Out-Null}}
    $eu=$null;$mp=Join-Path $d[0] '_meta.json';$k=@()
    if(Test-Path $mp){$e=Get-Content $mp -Raw|ConvertFrom-Json;$m=$e.entries|?{$_.name -eq $script:EntryName}|Select-Object -First 1;if($m){$eu=$m.id};$k=@($e.entries|?{$_.name -ne $script:EntryName}|%{[ordered]@{id=$_.id;name=$_.name}})}
    $u=if($eu){$eu}else{[guid]::NewGuid().ToString().ToLower()}
    $entries=@($k)+@([ordered]@{id=$u;name=$script:EntryName})
    $mj="{`n  ""appliedId"": $(ConvertTo-JsonScalar $u),`n  ""entries"": $(ConvertTo-JsonArrayString $entries)`n}"
    foreach($dd in $d){Write-TextAtomic -Path(Join-Path $dd '_meta.json') -Text $mj}
    return $u
}
function Write-Entry{param([string]$U,[string]$ApiKey)
    $mo=@([ordered]@{name=$m;supports1m=$false});if($f -ne $m){$mo+=[ordered]@{name=$f;supports1m=$false}}
    $mj=ConvertTo-JsonArrayString $mo
    $json=@"
{
  "inferenceProvider": "gateway",
  "inferenceGatewayBaseUrl": $(ConvertTo-JsonScalar $BaseUrl),
  "inferenceGatewayApiKey": $(ConvertTo-JsonScalar $ApiKey),
  "inferenceGatewayAuthScheme": $(ConvertTo-JsonScalar $AuthScheme),
  "unstableDisableModelVerification": true,
  "inferenceModels": $mj
}
"@
    $dd=@($script:ConfigDir)+@(if($script:StoreDir){$script:StoreDir}else{@()})
    foreach($d in $dd){Write-TextAtomic -Path(Join-Path $d "$U.json") -Text $json}
}
function Restart-Claude{Get-CimInstance Win32_Process -Filter "Name='claude.exe'" -ErrorAction SilentlyContinue|?{$_.CommandLine -like "*$($script:ClaudeExe)*"}|%{Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue};Start-Sleep 1;Start-Process $script:ClaudeExe}

Test-Preflight;$ak=Resolve-ApiKey
Confirm-OrAbort "configure Claude Desktop to use Tencent TokenHub ($BaseUrl, $l) and restart."
$uuid=Update-MetaEntry;Write-Entry -Uuid $uuid -ApiKey $ak;Restart-Claude
@"

Done. Claude Desktop is restarting with Tencent TokenHub ($l) as the inference backend.
Re-run hyclaude-desktop.ps1 any time to refresh the gateway config.
"@ | Write-Host
