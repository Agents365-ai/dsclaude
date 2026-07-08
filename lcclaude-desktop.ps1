#!/usr/bin/env pwsh
# lcclaude-desktop.ps1 — configure Claude Desktop to use Meituan LongCat (Windows port).
#
# Usage:
#   pwsh ./lcclaude-desktop.ps1                          # auto-detect and configure
#   pwsh ./lcclaude-desktop.ps1 -ClaudeExePath <path>    # specify custom Claude.exe
#   pwsh ./lcclaude-desktop.ps1 -Update                  # git pull
#   pwsh ./lcclaude-desktop.ps1 -h                       # help
#
# Reads LONGCAT_API_KEY from env (else prompts). Base URL defaults to
# https://api.longcat.chat/anthropic; override with $env:LONGCAT_BASE_URL.
#
# Get your free API key: https://longcat.chat/platform

[CmdletBinding()]
param(
    [Alias('h')][switch]$Help,
    [switch]$Update,
    [string]$ClaudeExePath
)

$ErrorActionPreference = 'Stop'

$ConfigDir  = Join-Path $env:LOCALAPPDATA 'Claude-3p\configLibrary'
$Meta       = Join-Path $ConfigDir '_meta.json'
$StoreDir   = if (Get-ChildItem "$env:LOCALAPPDATA\Packages\Claude_*" -ErrorAction SilentlyContinue) {
                  Join-Path (Resolve-Path "$env:LOCALAPPDATA\Packages\Claude_*") 'LocalCache\Roaming\Claude-3p\configLibrary'
              } else { $null }
$EntryName  = 'lcclaude-desktop'
$AuthScheme = 'bearer'
$MainModel  = 'LongCat-2.0'
$FastModel  = 'LongCat-Flash-Chat'
$BaseUrl    = if ($env:LONGCAT_BASE_URL) { $env:LONGCAT_BASE_URL } else { 'https://api.longcat.chat/anthropic' }

$ClaudeExe = $null

if ($Help) {
    Get-Content $PSCommandPath | Select-Object -Skip 1 -First 15 |
        ForEach-Object { $_ -replace '^# ?', '' }
    exit 0
}

if ($Update) {
    $repo = Split-Path -Parent $PSCommandPath
    Write-Host "lcclaude-desktop: pulling latest from $repo ..."
    git -C $repo pull
    if ($LASTEXITCODE -eq 0) { Write-Host 'lcclaude-desktop: updated.' }
    else { Write-Error 'lcclaude-desktop: git pull failed.'; exit 1 }
    exit 0
}

# ---- Pre-flight ------------------------------------------------------------

function Test-Preflight {
    $isWin = if ($null -ne $IsWindows) { $IsWindows } else { $true }
    if (-not $isWin) {
        Write-Error 'lcclaude-desktop.ps1: Windows only. Use ./lcclaude-desktop on macOS.'
        exit 1
    }

    if ($script:ClaudeExePath) {
        if (-not (Test-Path $script:ClaudeExePath)) {
            Write-Error "lcclaude-desktop.ps1: Claude.exe not found at '$script:ClaudeExePath'"
            exit 1
        }
        $script:ClaudeExe = $script:ClaudeExePath
    } else {
        $candidates = @()
        $pkg = Get-AppxPackage -Name 'Claude*' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($pkg) { $candidates += Join-Path $pkg.InstallLocation 'app\claude.exe' }

        $packagesBase = Join-Path $env:LOCALAPPDATA 'Packages'
        if (Test-Path $packagesBase) {
            $candidates += Get-ChildItem -Path $packagesBase -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue |
                ForEach-Object { Join-Path $_.FullName 'LocalCache\Local\Claude-3p\claude-code\*\claude.exe' } |
                ForEach-Object { Get-ChildItem -Path $_ -ErrorAction SilentlyContinue } |
                Select-Object -ExpandProperty FullName
        }
        $candidates += @(
            (Join-Path $env:LOCALAPPDATA 'AnthropicClaude\Claude.exe'),
            (Join-Path $env:LOCALAPPDATA 'Programs\AnthropicClaude\Claude.exe'),
            (Join-Path ${env:ProgramFiles}        'AnthropicClaude\Claude.exe'),
            (Join-Path ${env:ProgramFiles(x86)}   'AnthropicClaude\Claude.exe')
        )
        $found = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $found) {
            Write-Error "lcclaude-desktop.ps1: Claude Desktop not found. Install from https://claude.ai/download"
            exit 1
        }
        $script:ClaudeExe = $found
    }

    $devSettings = Join-Path $env:APPDATA 'Claude\developer_settings.json'
    $devDir = Split-Path $devSettings -Parent
    $needsEnable = $false
    if (Test-Path $devSettings) {
        $dev = Get-Content $devSettings -Raw | ConvertFrom-Json
        if (-not $dev.allowDevTools) { $needsEnable = $true }
    } else { $needsEnable = $true }
    if ($needsEnable) {
        Write-Host 'lcclaude-desktop.ps1: Enabling Developer Mode for Claude Desktop...'
        if (-not (Test-Path $devDir)) { New-Item -ItemType Directory -Path $devDir -Force | Out-Null }
        $devContent = '{ "allowDevTools": true }'
        [System.IO.File]::WriteAllText($devSettings, $devContent, [System.Text.UTF8Encoding]::new($false))
        Write-Host 'lcclaude-desktop.ps1: Developer Mode enabled.'
    }
}

# ---- API key resolution ----------------------------------------------------

function Resolve-ApiKey {
    if ($env:LONGCAT_API_KEY) { return $env:LONGCAT_API_KEY }
    foreach ($scope in 'User', 'Machine') {
        $v = [Environment]::GetEnvironmentVariable('LONGCAT_API_KEY', $scope)
        if ($v) { return $v }
    }
    $secure = Read-Host 'LONGCAT_API_KEY not set. Paste your LongCat API Key' -AsSecureString
    if (-not $secure -or $secure.Length -eq 0) {
        Write-Error 'lcclaude-desktop.ps1: no LongCat API Key provided. Aborting.'
        exit 1
    }
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr) }
    finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function Confirm-OrAbort { param([string]$Action); Write-Host ''; Write-Host "About to: $Action"; [void](Read-Host 'Press Enter to continue, Ctrl-C to abort') }

function Write-JsonAtomic {
    param([string]$Path, $Object)
    $json = $Object | ConvertTo-Json -Depth 6
    $json = $json.TrimEnd("`r", "`n")
    $tmp = "$Path.tmp"
    [System.IO.File]::WriteAllText($tmp, $json, [System.Text.UTF8Encoding]::new($false))
    Move-Item -Path $tmp -Destination $Path -Force
}

function Update-MetaEntry {
    $dirs = @($script:ConfigDir) + @(if ($script:StoreDir) { $script:StoreDir } else { @() })
    foreach ($d in $dirs) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null } }
    $existingUuid = $null
    $metaPath = Join-Path $dirs[0] '_meta.json'
    if (Test-Path $metaPath) {
        $existing = Get-Content $metaPath -Raw | ConvertFrom-Json
        $existingUuid = ($existing.entries | Where-Object { $_.name -eq $script:EntryName } | Select-Object -First 1).id
    }
    $uuid = if ($existingUuid) { $existingUuid } else { [guid]::NewGuid().ToString().ToLower() }
    $entries = @()
    if (Test-Path $metaPath) {
        $existing = Get-Content $metaPath -Raw | ConvertFrom-Json
        $entries = @($existing.entries | Where-Object { $_.name -ne $script:EntryName })
    }
    $entries += [pscustomobject]@{ id = $uuid; name = $script:EntryName }
    $newMeta = [ordered]@{ appliedId = $uuid; entries = @($entries) }
    foreach ($d in $dirs) { Write-JsonAtomic -Path (Join-Path $d '_meta.json') -Object $newMeta }
    return $uuid
}

function Write-Entry {
    param([string]$Uuid, [string]$ApiKey)
    $entry = [ordered]@{
        inferenceProvider                 = 'gateway'
        inferenceGatewayBaseUrl           = $script:BaseUrl
        inferenceGatewayApiKey            = $ApiKey
        inferenceGatewayAuthScheme        = $AuthScheme
        unstableDisableModelVerification  = $true
        inferenceModels                   = @(
            [ordered]@{ name = $MainModel; supports1m = $false },
            [ordered]@{ name = $FastModel; supports1m = $false }
        )
    }
    $dirs = @($script:ConfigDir) + @(if ($script:StoreDir) { $script:StoreDir } else { @() })
    foreach ($d in $dirs) { Write-JsonAtomic -Path (Join-Path $d "$Uuid.json") -Object $entry }
}

function Restart-Claude {
    Get-CimInstance Win32_Process -Filter "Name='claude.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "*$($script:ClaudeExe)*" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 1
    Start-Process -FilePath $script:ClaudeExe
}

# ---- Main ------------------------------------------------------------------

Test-Preflight
$apiKey = Resolve-ApiKey
Confirm-OrAbort -Action "configure Claude Desktop to use Meituan LongCat ($script:BaseUrl) and restart it."
$uuid = Update-MetaEntry
Write-Entry -Uuid $uuid -ApiKey $apiKey
Restart-Claude

@"

Done. Claude Desktop is restarting with Meituan LongCat as the inference backend.

Heads up: Chat mode is unavailable while a third-party gateway is active.
Re-run lcclaude-desktop.ps1 any time to refresh the gateway config.
"@ | Write-Host
