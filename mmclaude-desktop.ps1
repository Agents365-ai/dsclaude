#!/usr/bin/env pwsh
# mmclaude-desktop.ps1 — configure Claude Desktop to use Xiaomi MiMo as inference backend (Windows port).
#
# Edits %APPDATA%\Claude-3p\configLibrary\{_meta,<uuid>}.json and restarts Claude Desktop.
# This is the Windows companion to the macOS bash version `mmclaude-desktop` —
# same JSON schema, same flow, different shell.
#
# Note: This port has NOT been smoke-tested on Windows by the maintainer.
# Schema and gotchas (trailing-newline-rejection, lowercase UUIDs, allowDevTools
# gating) were discovered on macOS; Anthropic ships the same Electron app on
# Windows so they should hold, but please open an issue if anything misbehaves:
#   https://github.com/Agents365-ai/dsclaude/issues
#
# Usage:
#   pwsh ./mmclaude-desktop.ps1                          # auto-detect and configure
#   pwsh ./mmclaude-desktop.ps1 -ClaudeExePath <path>    # specify custom Claude.exe
#   pwsh ./mmclaude-desktop.ps1 -Update                  # git pull latest from the repo
#   pwsh ./mmclaude-desktop.ps1 -h                       # help
#
# Reads MIMO_API_KEY from env (else prompts). The base URL is auto-detected from
# the key prefix (tp-* → Token Plan, else pay-as-you-go); override with MIMO_BASE_URL.
#
# Requires: PowerShell 5.1+ (Windows 10+ ships this), Claude Desktop installed,
# Developer Mode enabled in Claude Desktop, MiMo API key.

[CmdletBinding()]
param(
    [Alias('h')][switch]$Help,
    [switch]$Update,
    [string]$ClaudeExePath
)

$ErrorActionPreference = 'Stop'

# ---- Constants -------------------------------------------------------------

$ConfigDir  = Join-Path $env:LOCALAPPDATA 'Claude-3p\configLibrary'
$Meta       = Join-Path $ConfigDir '_meta.json'
$StoreDir   = if (Get-ChildItem "$env:LOCALAPPDATA\Packages\Claude_*" -ErrorAction SilentlyContinue) {
                  Join-Path (Resolve-Path "$env:LOCALAPPDATA\Packages\Claude_*") 'LocalCache\Roaming\Claude-3p\configLibrary'
              } else { $null }
$EntryName  = 'mmclaude-desktop'
$AuthScheme = 'bearer'
$MainModel  = 'mimo-v2.5-pro'
$FastModel  = 'mimo-v2.5'
$BaseUrl    = $null  # resolved from the key prefix (or MIMO_BASE_URL) after the key is read

$ClaudeExe = $null  # populated by Test-Preflight

# ---- Help ------------------------------------------------------------------

if ($Help) {
    Get-Content $PSCommandPath | Select-Object -Skip 1 -First 23 |
        ForEach-Object { $_ -replace '^# ?', '' }
    exit 0
}

if ($Update) {
    $repo = Split-Path -Parent $PSCommandPath
    Write-Host "mmclaude-desktop: pulling latest from $repo ..."
    git -C $repo pull
    if ($LASTEXITCODE -eq 0) {
        Write-Host 'mmclaude-desktop: updated.'
    } else {
        Write-Error 'mmclaude-desktop: git pull failed. Check network or resolve conflicts manually.'
        exit 1
    }
    exit 0
}

# ---- Pre-flight ------------------------------------------------------------

function Test-Preflight {
    # PS 5.1 has no $IsWindows; assume yes if absent (PS 5.1 is Windows-only).
    $isWin = if ($null -ne $IsWindows) { $IsWindows } else { $true }
    if (-not $isWin) {
        Write-Error 'mmclaude-desktop.ps1: Windows only. Use ./mmclaude-desktop on macOS.'
        exit 1
    }

    # If user provided a custom path, verify it and use it.
    if ($script:ClaudeExePath) {
        if (-not (Test-Path $script:ClaudeExePath)) {
            Write-Error "mmclaude-desktop.ps1: Claude.exe not found at '$script:ClaudeExePath'"
            exit 1
        }
        $script:ClaudeExe = $script:ClaudeExePath
    } else {
        # Auto-detect: check Windows Store package first (Get-AppxPackage is
        # the reliable way to find Store-installed apps without touching the
        # restricted WindowsApps directory), then standard installs, then the
        # user-local Packages folder as a fallback.
        $candidates = @()

        $pkg = Get-AppxPackage -Name 'Claude*' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($pkg) {
            $candidates += Join-Path $pkg.InstallLocation 'app\claude.exe'
        }

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
            Write-Error @"
mmclaude-desktop.ps1: Claude Desktop not found.
Install from https://claude.ai/download, or pass -ClaudeExePath to specify
your custom install location. Looked in:
  $($candidates -join "`n  ")
"@
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
    } else {
        $needsEnable = $true
    }
    if ($needsEnable) {
        Write-Host 'mmclaude-desktop.ps1: Enabling Developer Mode for Claude Desktop...'
        if (-not (Test-Path $devDir)) { New-Item -ItemType Directory -Path $devDir -Force | Out-Null }
        $devContent = '{ "allowDevTools": true }'
        [System.IO.File]::WriteAllText($devSettings, $devContent, [System.Text.UTF8Encoding]::new($false))
        Write-Host 'mmclaude-desktop.ps1: Developer Mode enabled.'
    }
}

# ---- API key resolution ----------------------------------------------------

function Resolve-ApiKey {
    if ($env:MIMO_API_KEY) { return $env:MIMO_API_KEY }
    foreach ($scope in 'User', 'Machine') {
        $v = [Environment]::GetEnvironmentVariable('MIMO_API_KEY', $scope)
        if ($v) { return $v }
    }

    # Windows has no shell-rc tradition; jump straight to interactive prompt.
    $secure = Read-Host 'MIMO_API_KEY not set. Paste your MiMo API Key' -AsSecureString
    if (-not $secure -or $secure.Length -eq 0) {
        Write-Error 'mmclaude-desktop.ps1: no MiMo API Key provided. Aborting.'
        exit 1
    }
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

# ---- Confirmation gate -----------------------------------------------------

function Confirm-OrAbort {
    param([string]$Action)
    Write-Host ''
    Write-Host "About to: $Action"
    [void](Read-Host 'Press Enter to continue, Ctrl-C to abort')
}

# ---- File writes (atomic, no trailing newline) -----------------------------

# Claude Desktop's parser rejects entries with a trailing newline ("unknown
# config id"), so we TrimEnd before writing. Writes via .NET to control the
# encoding (UTF-8 no-BOM) and avoid any ambient newline addition.
function Write-JsonAtomic {
    param([string]$Path, $Object)
    $json = $Object | ConvertTo-Json -Depth 6
    $json = $json.TrimEnd("`r", "`n")
    $tmp = "$Path.tmp"
    [System.IO.File]::WriteAllText($tmp, $json, [System.Text.UTF8Encoding]::new($false))
    Move-Item -Path $tmp -Destination $Path -Force
}

# Ensure _meta.json has an entry named $EntryName (creating or reusing its
# uuid) and set appliedId to that uuid. Returns the uuid.
function Update-MetaEntry {
    $dirs = @($script:ConfigDir) + @(if ($script:StoreDir) { $script:StoreDir } else { @() })
    foreach ($d in $dirs) {
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }

    $existingUuid = $null
    $metaPath = Join-Path $dirs[0] '_meta.json'
    if (Test-Path $metaPath) {
        $existing = Get-Content $metaPath -Raw | ConvertFrom-Json
        $existingUuid = (
            $existing.entries | Where-Object { $_.name -eq $script:EntryName } |
            Select-Object -First 1
        ).id
    }

    $uuid = if ($existingUuid) { $existingUuid }
            else { [guid]::NewGuid().ToString().ToLower() }

    $entries = @()
    if (Test-Path $metaPath) {
        $existing = Get-Content $metaPath -Raw | ConvertFrom-Json
        $entries = @($existing.entries | Where-Object { $_.name -ne $script:EntryName })
    }
    $entries += [pscustomobject]@{ id = $uuid; name = $script:EntryName }

    $newMeta = [ordered]@{
        appliedId = $uuid
        entries   = @($entries)
    }
    foreach ($d in $dirs) {
        Write-JsonAtomic -Path (Join-Path $d '_meta.json') -Object $newMeta
    }
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
    foreach ($d in $dirs) {
        Write-JsonAtomic -Path (Join-Path $d "$Uuid.json") -Object $entry
    }
}

# ---- Restart ---------------------------------------------------------------

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
# Auto-detect the base URL from the key prefix; MIMO_BASE_URL always wins.
$script:BaseUrl = if ($env:MIMO_BASE_URL) {
    $env:MIMO_BASE_URL
} elseif ($apiKey -like 'tp-*') {
    'https://token-plan-cn.xiaomimimo.com/anthropic'
} else {
    'https://api.xiaomimimo.com/anthropic'
}
Confirm-OrAbort -Action "configure Claude Desktop to use Xiaomi MiMo ($script:BaseUrl) and restart it."
$uuid = Update-MetaEntry
Write-Entry -Uuid $uuid -ApiKey $apiKey
Restart-Claude

@"

Done. Claude Desktop is restarting with Xiaomi MiMo as the inference backend.

Heads up: Chat mode is unavailable while a third-party gateway is active.
You'll see Cowork (3P) and Code modes only. To use Chat:

  - At launch chooser, pick "Continue with Anthropic", OR
  - In Developer -> Configure Third-Party Inference, toggle off "Skip
    login-mode chooser" (default is off, so the chooser should appear)

Re-run mmclaude-desktop.ps1 any time to refresh the gateway config.
"@ | Write-Host
