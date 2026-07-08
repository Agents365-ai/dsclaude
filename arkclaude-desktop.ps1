#!/usr/bin/env pwsh
# arkclaude-desktop.ps1 — configure Claude Desktop to use Volcengine Ark (Windows port).
#
# Edits %APPDATA%\Claude-3p\configLibrary\{_meta,<uuid>}.json and restarts Claude Desktop.
# This is the Windows companion to the macOS bash version `arkclaude-desktop` —
# same JSON schema, same flow, different shell.
#
# Note: This port has NOT been smoke-tested on Windows by the maintainer.
# Schema and gotchas (trailing-newline-rejection, lowercase UUIDs, allowDevTools
# gating) were discovered on macOS; Anthropic ships the same Electron app on
# Windows so they should hold, but please open an issue if anything misbehaves:
#   https://github.com/Agents365-ai/dsclaude/issues
#
# Usage:
#   pwsh ./arkclaude-desktop.ps1                          # doubao-seed-2.0-code
#   pwsh ./arkclaude-desktop.ps1 -ModelTier plus          # doubao-seed-2.0-pro
#   pwsh ./arkclaude-desktop.ps1 -ModelTier kimi          # kimi-k2.7-code
#   pwsh ./arkclaude-desktop.ps1 -ModelTier deepseek      # deepseek-v4-pro
#   pwsh ./arkclaude-desktop.ps1 -ModelTier glm           # glm-5.2
#   pwsh ./arkclaude-desktop.ps1 -ModelTier minimax       # minimax-m2.7
#   pwsh ./arkclaude-desktop.ps1 -ClaudeExePath <path>    # specify custom Claude.exe
#   pwsh ./arkclaude-desktop.ps1 -Update                  # git pull latest from the repo
#   pwsh ./arkclaude-desktop.ps1 -h                       # help
#
# Reads ARK_API_KEY from env (else prompts). The base URL defaults to
# https://ark.cn-beijing.volces.com/api/coding; override with $env:ARK_BASE_URL.
#
# Requires: PowerShell 5.1+ (Windows 10+ ships this), Claude Desktop installed,
# Developer Mode enabled in Claude Desktop, Volcengine ARK API key.

[CmdletBinding()]
param(
    [Alias('h')][switch]$Help,
    [switch]$Update,
    [string]$ClaudeExePath,
    [Parameter(Position = 0)]
    [ValidateSet('code', 'max', 'pro', 'plus', 'fast', 'flash', 'lite',
                 'kimi', 'kimi-pro', 'kimi-k2',
                 'deepseek', 'deepseek-flash',
                 'glm', 'minimax')]
    [string]$ModelTier = 'code'
)

$ErrorActionPreference = 'Stop'

# ---- Help ------------------------------------------------------------------

if ($Help) {
    Get-Content $PSCommandPath | Select-Object -Skip 1 -First 27 |
        ForEach-Object { $_ -replace '^# ?', '' }
    exit 0
}

if ($Update) {
    $repo = Split-Path -Parent $PSCommandPath
    Write-Host "arkclaude-desktop: pulling latest from $repo ..."
    git -C $repo pull
    if ($LASTEXITCODE -eq 0) {
        Write-Host 'arkclaude-desktop: updated.'
    } else {
        Write-Error 'arkclaude-desktop: git pull failed. Check network or resolve conflicts manually.'
        exit 1
    }
    exit 0
}

# ---- Constants -------------------------------------------------------------

$ConfigDir  = Join-Path $env:LOCALAPPDATA 'Claude-3p\configLibrary'
$StoreDir   = if (Get-ChildItem "$env:LOCALAPPDATA\Packages\Claude_*" -ErrorAction SilentlyContinue) {
                  Join-Path (Resolve-Path "$env:LOCALAPPDATA\Packages\Claude_*") 'LocalCache\Roaming\Claude-3p\configLibrary'
              } else { $null }
$EntryName  = 'arkclaude-desktop'
$AuthScheme = 'bearer'

$ClaudeExe = $null  # populated by Test-Preflight

# ---- Resolve model from tier alias -----------------------------------------

switch ($ModelTier) {
    { $_ -in 'code', 'max', 'pro' } {
        $MainModel  = 'doubao-seed-2.0-code'
        $FastModel  = 'doubao-seed-2.0-lite'
        $ModelLabel = 'doubao-seed-2.0-code'
    }
    'plus' {
        $MainModel  = 'doubao-seed-2.0-pro'
        $FastModel  = 'doubao-seed-2.0-lite'
        $ModelLabel = 'doubao-seed-2.0-pro'
    }
    { $_ -in 'fast', 'flash', 'lite' } {
        $MainModel  = 'doubao-seed-2.0-lite'
        $FastModel  = 'doubao-seed-2.0-lite'
        $ModelLabel = 'doubao-seed-2.0-lite'
    }
    'kimi' {
        $MainModel  = 'kimi-k2.7-code'
        $FastModel  = 'doubao-seed-2.0-lite'
        $ModelLabel = 'Kimi K2.7 Code'
    }
    { $_ -in 'kimi-pro', 'kimi-k2' } {
        $MainModel  = 'kimi-k2.6'
        $FastModel  = 'kimi-k2.6'
        $ModelLabel = 'Kimi K2.6'
    }
    'deepseek' {
        $MainModel  = 'deepseek-v4-pro'
        $FastModel  = 'deepseek-v4-flash'
        $ModelLabel = 'DeepSeek V4 Pro'
    }
    'deepseek-flash' {
        $MainModel  = 'deepseek-v4-flash'
        $FastModel  = 'deepseek-v4-flash'
        $ModelLabel = 'DeepSeek V4 Flash'
    }
    'glm' {
        $MainModel  = 'glm-5.2'
        $FastModel  = 'glm-5.2'
        $ModelLabel = 'GLM 5.2'
    }
    'minimax' {
        $MainModel  = 'minimax-m2.7'
        $FastModel  = 'minimax-m2.7'
        $ModelLabel = 'MiniMax M2.7'
    }
}

$BaseUrl = if ($env:ARK_BASE_URL) { $env:ARK_BASE_URL } else { 'https://ark.cn-beijing.volces.com/api/coding' }

# ---- JSON helpers ----------------------------------------------------------

function ConvertTo-JsonScalar {
    param($Value)
    $Value | ConvertTo-Json -Depth 1 -Compress
}

function ConvertTo-JsonArrayString {
    param([object[]]$Items, [int]$Depth = 4)
    $arr = @($Items)
    if ($arr.Count -eq 0) { return '[]' }
    '[' + (($arr | ForEach-Object { $_ | ConvertTo-Json -Depth $Depth -Compress }) -join ',') + ']'
}

function Write-TextAtomic {
    param([string]$Path, [string]$Text)
    $Text = $Text.TrimEnd("`r", "`n")
    $tmp = "$Path.tmp"
    [System.IO.File]::WriteAllText($tmp, $Text, [System.Text.UTF8Encoding]::new($false))
    Move-Item -Path $tmp -Destination $Path -Force
}

# ---- Pre-flight ------------------------------------------------------------

function Test-Preflight {
    $isWin = if ($null -ne $IsWindows) { $IsWindows } else { $true }
    if (-not $isWin) {
        Write-Error 'arkclaude-desktop.ps1: Windows only. Use ./arkclaude-desktop on macOS.'
        exit 1
    }

    if ($script:ClaudeExePath) {
        if (-not (Test-Path $script:ClaudeExePath)) {
            Write-Error "arkclaude-desktop.ps1: Claude.exe not found at '$script:ClaudeExePath'"
            exit 1
        }
        $script:ClaudeExe = $script:ClaudeExePath
    } else {
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
arkclaude-desktop.ps1: Claude Desktop not found.
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
        Write-Host 'arkclaude-desktop.ps1: Enabling Developer Mode for Claude Desktop...'
        if (-not (Test-Path $devDir)) { New-Item -ItemType Directory -Path $devDir -Force | Out-Null }
        $devContent = '{ "allowDevTools": true }'
        [System.IO.File]::WriteAllText($devSettings, $devContent, [System.Text.UTF8Encoding]::new($false))
        Write-Host 'arkclaude-desktop.ps1: Developer Mode enabled.'
    }
}

# ---- API key resolution ----------------------------------------------------

function Resolve-ApiKey {
    if ($env:ARK_API_KEY) { return $env:ARK_API_KEY }
    foreach ($scope in 'User', 'Machine') {
        $v = [Environment]::GetEnvironmentVariable('ARK_API_KEY', $scope)
        if ($v) { return $v }
    }

    $secure = Read-Host 'ARK_API_KEY not set. Paste your Volcengine Ark API Key' -AsSecureString
    if (-not $secure -or $secure.Length -eq 0) {
        Write-Error 'arkclaude-desktop.ps1: no ARK API Key provided. Aborting.'
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

# ---- _meta.json + entry writes ---------------------------------------------

function Update-MetaEntry {
    $dirs = @($script:ConfigDir) + @(if ($script:StoreDir) { $script:StoreDir } else { @() })
    foreach ($d in $dirs) {
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }

    $metaPath = Join-Path $dirs[0] '_meta.json'
    $existingUuid = $null
    $keep = @()
    if (Test-Path $metaPath) {
        $existing = Get-Content $metaPath -Raw | ConvertFrom-Json
        $mine = $existing.entries | Where-Object { $_.name -eq $script:EntryName } | Select-Object -First 1
        if ($mine) { $existingUuid = $mine.id }
        $keep = @($existing.entries | Where-Object { $_.name -ne $script:EntryName } |
            ForEach-Object { [ordered]@{ id = $_.id; name = $_.name } })
    }

    $uuid = if ($existingUuid) { $existingUuid }
            else { [guid]::NewGuid().ToString().ToLower() }

    $entries = @($keep) + @([ordered]@{ id = $uuid; name = $script:EntryName })

    $metaJson = "{`n  ""appliedId"": $(ConvertTo-JsonScalar $uuid),`n  ""entries"": $(ConvertTo-JsonArrayString $entries)`n}"
    foreach ($d in $dirs) {
        Write-TextAtomic -Path (Join-Path $d '_meta.json') -Text $metaJson
    }
    return $uuid
}

function Write-Entry {
    param([string]$Uuid, [string]$ApiKey)

    $modelObjs = @([ordered]@{ name = $script:MainModel; supports1m = $false })
    if ($script:FastModel -ne $script:MainModel) {
        $modelObjs += [ordered]@{ name = $script:FastModel; supports1m = $false }
    }
    $modelsJson = ConvertTo-JsonArrayString $modelObjs

    $json = @"
{
  "inferenceProvider": "gateway",
  "inferenceGatewayBaseUrl": $(ConvertTo-JsonScalar $script:BaseUrl),
  "inferenceGatewayApiKey": $(ConvertTo-JsonScalar $ApiKey),
  "inferenceGatewayAuthScheme": $(ConvertTo-JsonScalar $script:AuthScheme),
  "unstableDisableModelVerification": true,
  "inferenceModels": $modelsJson
}
"@
    $dirs = @($script:ConfigDir) + @(if ($script:StoreDir) { $script:StoreDir } else { @() })
    foreach ($d in $dirs) {
        Write-TextAtomic -Path (Join-Path $d "$Uuid.json") -Text $json
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
Confirm-OrAbort -Action "configure Claude Desktop to use Ark Coding Plan ($BaseUrl, $ModelLabel) and restart it."
$uuid = Update-MetaEntry
Write-Entry -Uuid $uuid -ApiKey $apiKey
Restart-Claude

@"

Done. Claude Desktop is restarting with Ark Coding Plan ($ModelLabel) as the inference backend.

Heads up: Chat mode is unavailable while a third-party gateway is active.
You'll see Cowork (3P) and Code modes only. To use Chat:

  - At launch chooser, pick "Continue with Anthropic", OR
  - In Developer -> Configure Third-Party Inference, toggle off "Skip
    login-mode chooser" (default is off, so the chooser should appear)

Re-run arkclaude-desktop.ps1 any time to refresh the gateway config.
"@ | Write-Host
