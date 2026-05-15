#!/usr/bin/env pwsh
# dsclaude-desktop.ps1 — configure Claude Desktop to use DeepSeek as inference backend (Windows port).
#
# Edits %APPDATA%\Claude-3p\configLibrary\{_meta,<uuid>}.json and restarts Claude Desktop.
# This is the Windows companion to the macOS bash version `dsclaude-desktop` —
# same JSON schema, same flow, different shell.
#
# Note: This port has NOT been smoke-tested on Windows by the maintainer.
# Schema and gotchas (trailing-newline-rejection, lowercase UUIDs, allowDevTools
# gating) were discovered on macOS; Anthropic ships the same Electron app on
# Windows so they should hold, but please open an issue if anything misbehaves:
#   https://github.com/Agents365-ai/dsclaude/issues
#
# Usage:
#   pwsh ./dsclaude-desktop.ps1                          # auto-detect and configure
#   pwsh ./dsclaude-desktop.ps1 -ClaudeExePath <path>    # specify custom Claude.exe
#   pwsh ./dsclaude-desktop.ps1 -Update                  # git pull latest from the repo
#   pwsh ./dsclaude-desktop.ps1 -h                       # help
#
# Requires: PowerShell 5.1+ (Windows 10+ ships this), Claude Desktop installed,
# Developer Mode enabled in Claude Desktop, DeepSeek API key.

[CmdletBinding()]
param(
    [Alias('h')][switch]$Help,
    [switch]$Update,
    [string]$ClaudeExePath
)

$ErrorActionPreference = 'Stop'

# ---- Constants -------------------------------------------------------------

$ConfigDir  = Join-Path $env:APPDATA 'Claude-3p\configLibrary'
$Meta       = Join-Path $ConfigDir '_meta.json'
$EntryName  = 'dsclaude-desktop'
$BaseUrl    = 'https://api.deepseek.com/anthropic'
$AuthScheme = 'bearer'
$MainModel  = 'deepseek-v4-pro'
$FastModel  = 'deepseek-v4-flash'

$ClaudeExe = $null  # populated by Test-Preflight

# ---- Help ------------------------------------------------------------------

if ($Help) {
    Get-Content $PSCommandPath | Select-Object -Skip 1 -First 22 |
        ForEach-Object { $_ -replace '^# ?', '' }
    exit 0
}

if ($Update) {
    $repo = Split-Path -Parent $PSCommandPath
    Write-Host "dsclaude-desktop: pulling latest from $repo ..."
    git -C $repo pull
    if ($LASTEXITCODE -eq 0) {
        Write-Host 'dsclaude-desktop: updated.'
    } else {
        Write-Error 'dsclaude-desktop: git pull failed. Check network or resolve conflicts manually.'
        exit 1
    }
    exit 0
}

# ---- Pre-flight ------------------------------------------------------------

function Test-Preflight {
    # PS 5.1 has no $IsWindows; assume yes if absent (PS 5.1 is Windows-only).
    $isWin = if ($null -ne $IsWindows) { $IsWindows } else { $true }
    if (-not $isWin) {
        Write-Error 'dsclaude-desktop.ps1: Windows only. Use ./dsclaude-desktop on macOS.'
        exit 1
    }

    # If user provided a custom path, verify it and use it.
    if ($script:ClaudeExePath) {
        if (-not (Test-Path $script:ClaudeExePath)) {
            Write-Error "dsclaude-desktop.ps1: Claude.exe not found at '$script:ClaudeExePath'"
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
dsclaude-desktop.ps1: Claude Desktop not found.
Install from https://claude.ai/download, or pass -ClaudeExePath to specify
your custom install location. Looked in:
  $($candidates -join "`n  ")
"@
            exit 1
        }
        $script:ClaudeExe = $found
    }

    $devSettings = Join-Path $env:APPDATA 'Claude\developer_settings.json'
    if (-not (Test-Path $devSettings)) {
        Write-Error @'
dsclaude-desktop.ps1: Developer Mode not enabled in Claude Desktop.

Claude Desktop's third-party inference feature is gated behind Developer Mode.
Enable it once in the GUI before running this script:

  1. Open Claude Desktop
  2. Help -> Troubleshooting -> Enable Developer Mode
  3. Re-run this script
'@
        exit 1
    }
    $dev = Get-Content $devSettings -Raw | ConvertFrom-Json
    if (-not $dev.allowDevTools) {
        Write-Error 'dsclaude-desktop.ps1: developer_settings.json has allowDevTools=false. Toggle Developer Mode in Help -> Troubleshooting.'
        exit 1
    }
}

# ---- API key resolution ----------------------------------------------------

function Resolve-ApiKey {
    if ($env:DEEPSEEK_API_KEY) { return $env:DEEPSEEK_API_KEY }

    # Windows has no shell-rc tradition; jump straight to interactive prompt.
    $secure = Read-Host 'DEEPSEEK_API_KEY not set. Paste your DeepSeek API Key' -AsSecureString
    if (-not $secure -or $secure.Length -eq 0) {
        Write-Error 'dsclaude-desktop.ps1: no DeepSeek API Key provided. Aborting.'
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

function Write-Entry {
    param([string]$Uuid, [string]$ApiKey)
    # unstableDisableModelVerification skips Claude Desktop 1.7xxx's local model-name
    # validator (app.asar: koA/FAi/FFA). Without it, names matching its hard-coded
    # block-list (deepseek/qwen/gemini/...) are rejected before any request leaves
    # the app. Defined in Claude's own config schema (scopes:["3p"], title:
    # "Disable model verification"), so it's a sanctioned-but-internal bypass —
    # the `unstable` prefix means Anthropic reserves the right to rename it.
    $entry = [ordered]@{
        inferenceProvider                 = 'gateway'
        inferenceGatewayBaseUrl           = $BaseUrl
        inferenceGatewayApiKey            = $ApiKey
        inferenceGatewayAuthScheme        = $AuthScheme
        unstableDisableModelVerification  = $true
        inferenceModels                   = @(
            [ordered]@{ name = $MainModel; supports1m = $true },
            [ordered]@{ name = $FastModel; supports1m = $true }
        )
    }
    Write-JsonAtomic -Path (Join-Path $script:ConfigDir "$Uuid.json") -Object $entry
}

# Ensure _meta.json has an entry named $EntryName (creating or reusing its
# uuid) and set appliedId to that uuid. Returns the uuid.
function Update-MetaEntry {
    if (-not (Test-Path $script:ConfigDir)) {
        New-Item -ItemType Directory -Path $script:ConfigDir -Force | Out-Null
    }

    $existingUuid = $null
    if (Test-Path $script:Meta) {
        $existing = Get-Content $script:Meta -Raw | ConvertFrom-Json
        $existingUuid = (
            $existing.entries | Where-Object { $_.name -eq $script:EntryName } |
            Select-Object -First 1
        ).id
    }

    # Lowercase to match Claude's GUI-written UUIDs.
    $uuid = if ($existingUuid) { $existingUuid }
            else { [guid]::NewGuid().ToString().ToLower() }

    $entries = @()
    if (Test-Path $script:Meta) {
        $existing = Get-Content $script:Meta -Raw | ConvertFrom-Json
        $entries = @($existing.entries | Where-Object { $_.name -ne $script:EntryName })
    }
    $entries += [pscustomobject]@{ id = $uuid; name = $script:EntryName }

    $newMeta = [ordered]@{
        appliedId = $uuid
        entries   = @($entries)
    }
    Write-JsonAtomic -Path $script:Meta -Object $newMeta
    return $uuid
}

# ---- Restart ---------------------------------------------------------------

function Restart-Claude {
    Get-Process -Name 'Claude' -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    Start-Process -FilePath $script:ClaudeExe
}

# ---- Main ------------------------------------------------------------------

Test-Preflight
$apiKey = Resolve-ApiKey
Confirm-OrAbort -Action "configure Claude Desktop to use DeepSeek ($BaseUrl) and restart it."
$uuid = Update-MetaEntry
Write-Entry -Uuid $uuid -ApiKey $apiKey
Restart-Claude

@"

Done. Claude Desktop is restarting with DeepSeek as the inference backend.

Heads up: Chat mode is unavailable while a third-party gateway is active.
You'll see Cowork (3P) and Code modes only. To use Chat:

  - At launch chooser, pick "Continue with Anthropic", OR
  - In Developer -> Configure Third-Party Inference, toggle off "Skip
    login-mode chooser" (default is off, so the chooser should appear)

Re-run dsclaude-desktop.ps1 any time to refresh the gateway config.
"@ | Write-Host
