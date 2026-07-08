#!/usr/bin/env pwsh
# mxclaude-desktop.ps1 — configure Claude Desktop to use MiniMax (Windows port).
#
# Usage:
#   pwsh ./mxclaude-desktop.ps1                    # auto-detect and configure
#   pwsh ./mxclaude-desktop.ps1 -ClaudeExePath <p> # custom Claude.exe
#   pwsh ./mxclaude-desktop.ps1 -Update            # git pull
#   pwsh ./mxclaude-desktop.ps1 -h                 # help
#
# Reads MINIMAX_API_KEY from env (else prompts). Base URL defaults to
# https://api.minimaxi.com/anthropic; override with $env:MINIMAX_BASE_URL.

[CmdletBinding()]
param([Alias('h')][switch]$Help, [switch]$Update, [string]$ClaudeExePath)

$ErrorActionPreference = 'Stop'

$ConfigDir  = Join-Path $env:LOCALAPPDATA 'Claude-3p\configLibrary'
$StoreDir   = if (Get-ChildItem "$env:LOCALAPPDATA\Packages\Claude_*" -ErrorAction SilentlyContinue) {
    Join-Path (Resolve-Path "$env:LOCALAPPDATA\Packages\Claude_*") 'LocalCache\Roaming\Claude-3p\configLibrary'
} else { $null }
$EntryName  = 'mxclaude-desktop'
$AuthScheme = 'bearer'
$MainModel  = 'MiniMax-M3'
$FastModel  = 'MiniMax-M2.5'
$BaseUrl    = if ($env:MINIMAX_BASE_URL) { $env:MINIMAX_BASE_URL } else { 'https://api.minimaxi.com/anthropic' }
$ClaudeExe = $null

if ($Help) { Get-Content $PSCommandPath | Select-Object -Skip 1 -First 14 | ForEach-Object { $_ -replace '^# ?', '' }; exit 0 }
if ($Update) {
    $repo = Split-Path -Parent $PSCommandPath
    Write-Host "mxclaude-desktop: pulling latest from $repo ..."
    git -C $repo pull
    if ($LASTEXITCODE -eq 0) { Write-Host 'mxclaude-desktop: updated.' } else { Write-Error 'mxclaude-desktop: git pull failed.'; exit 1 }
    exit 0
}

function Test-Preflight {
    $isWin = if ($null -ne $IsWindows) { $IsWindows } else { $true }
    if (-not $isWin) { Write-Error 'mxclaude-desktop.ps1: Windows only.'; exit 1 }
    if ($script:ClaudeExePath) {
        if (-not (Test-Path $script:ClaudeExePath)) { Write-Error "mxclaude-desktop.ps1: Claude.exe not found at '$script:ClaudeExePath'"; exit 1 }
        $script:ClaudeExe = $script:ClaudeExePath
    } else {
        $candidates = @()
        $pkg = Get-AppxPackage -Name 'Claude*' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($pkg) { $candidates += Join-Path $pkg.InstallLocation 'app\claude.exe' }
        $packagesBase = Join-Path $env:LOCALAPPDATA 'Packages'
        if (Test-Path $packagesBase) {
            $candidates += Get-ChildItem -Path $packagesBase -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue |
                ForEach-Object { Join-Path $_.FullName 'LocalCache\Local\Claude-3p\claude-code\*\claude.exe' } |
                ForEach-Object { Get-ChildItem -Path $_ -ErrorAction SilentlyContinue } | Select-Object -ExpandProperty FullName
        }
        $candidates += @((Join-Path $env:LOCALAPPDATA 'AnthropicClaude\Claude.exe'),(Join-Path $env:LOCALAPPDATA 'Programs\AnthropicClaude\Claude.exe'),(Join-Path ${env:ProgramFiles} 'AnthropicClaude\Claude.exe'),(Join-Path ${env:ProgramFiles(x86)} 'AnthropicClaude\Claude.exe'))
        $found = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $found) { Write-Error "mxclaude-desktop.ps1: Claude Desktop not found."; exit 1 }
        $script:ClaudeExe = $found
    }
    $devSettings = Join-Path $env:APPDATA 'Claude\developer_settings.json'; $devDir = Split-Path $devSettings -Parent; $needsEnable = $false
    if (Test-Path $devSettings) { $dev = Get-Content $devSettings -Raw | ConvertFrom-Json; if (-not $dev.allowDevTools) { $needsEnable = $true } } else { $needsEnable = $true }
    if ($needsEnable) {
        Write-Host 'mxclaude-desktop.ps1: Enabling Developer Mode...'
        if (-not (Test-Path $devDir)) { New-Item -ItemType Directory -Path $devDir -Force | Out-Null }
        [System.IO.File]::WriteAllText($devSettings, '{ "allowDevTools": true }', [System.Text.UTF8Encoding]::new($false))
    }
}

function Resolve-ApiKey {
    if ($env:MINIMAX_API_KEY) { return $env:MINIMAX_API_KEY }
    foreach ($scope in 'User','Machine') { $v = [Environment]::GetEnvironmentVariable('MINIMAX_API_KEY',$scope); if ($v) { return $v } }
    $secure = Read-Host 'MINIMAX_API_KEY not set. Paste your MiniMax API Key' -AsSecureString
    if (-not $secure -or $secure.Length -eq 0) { Write-Error 'mxclaude-desktop.ps1: no API Key provided.'; exit 1 }
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr) }
    finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function Confirm-OrAbort { param([string]$Action); Write-Host ''; Write-Host "About to: $Action"; [void](Read-Host 'Press Enter to continue, Ctrl-C to abort') }
function Write-JsonAtomic { param([string]$Path,$Object); $json = ($Object|ConvertTo-Json -Depth 6).TrimEnd("`r","`n"); $tmp="$Path.tmp"; [System.IO.File]::WriteAllText($tmp,$json,[System.Text.UTF8Encoding]::new($false)); Move-Item $tmp $Path -Force }

function Update-MetaEntry {
    $dirs = @($script:ConfigDir) + @(if ($script:StoreDir) { $script:StoreDir } else { @() })
    foreach ($d in $dirs) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null } }
    $existingUuid=$null; $metaPath=Join-Path $dirs[0] '_meta.json'
    if (Test-Path $metaPath) { $e=Get-Content $metaPath -Raw|ConvertFrom-Json; $existingUuid=($e.entries|?{$_.name -eq $script:EntryName}|Select-Object -First 1).id }
    $uuid=if($existingUuid){$existingUuid}else{[guid]::NewGuid().ToString().ToLower()}
    $entries=@(); if(Test-Path $metaPath){$e=Get-Content $metaPath -Raw|ConvertFrom-Json; $entries=@($e.entries|?{$_.name -ne $script:EntryName})}
    $entries+=[pscustomobject]@{id=$uuid;name=$script:EntryName}
    $m=[ordered]@{appliedId=$uuid;entries=@($entries)}
    foreach($d in $dirs){Write-JsonAtomic -Path (Join-Path $d '_meta.json') -Object $m}
    return $uuid
}

function Write-Entry { param([string]$Uuid,[string]$ApiKey)
    $e=[ordered]@{inferenceProvider='gateway';inferenceGatewayBaseUrl=$script:BaseUrl;inferenceGatewayApiKey=$ApiKey;inferenceGatewayAuthScheme=$AuthScheme;unstableDisableModelVerification=$true;inferenceModels=@([ordered]@{name=$MainModel;supports1m=$false},[ordered]@{name=$FastModel;supports1m=$false})}
    $dirs=@($script:ConfigDir)+@(if($script:StoreDir){$script:StoreDir}else{@()})
    foreach($d in $dirs){Write-JsonAtomic -Path (Join-Path $d "$Uuid.json") -Object $e}
}

function Restart-Claude { Get-CimInstance Win32_Process -Filter "Name='claude.exe'" -ErrorAction SilentlyContinue|?{$_.CommandLine -like "*$($script:ClaudeExe)*"}|%{Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue}; Start-Sleep 1; Start-Process $script:ClaudeExe }

Test-Preflight; $apiKey=Resolve-ApiKey; Confirm-OrAbort "configure Claude Desktop to use MiniMax ($script:BaseUrl) and restart it."
$uuid=Update-MetaEntry; Write-Entry -Uuid $uuid -ApiKey $apiKey; Restart-Claude

@"

Done. Claude Desktop is restarting with MiniMax as the inference backend.
Re-run mxclaude-desktop.ps1 any time to refresh the gateway config.
"@ | Write-Host
