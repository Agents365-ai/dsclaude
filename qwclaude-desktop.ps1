#!/usr/bin/env pwsh
# qwclaude-desktop.ps1 — configure Claude Desktop to use Alibaba Cloud Bailian (Qwen) (Windows port).
#
# Edits %APPDATA%\Claude-3p\configLibrary\{_meta,<uuid>}.json and restarts Claude Desktop.
# This is the Windows companion to the macOS bash version `qwclaude-desktop` —
# same JSON schema, same flow, different shell.
#
# Note: This port has NOT been smoke-tested on Windows by the maintainer.
# Schema and gotchas (trailing-newline-rejection, lowercase UUIDs, allowDevTools
# gating, single-element-array JSON) were discovered on macOS; Anthropic ships
# the same Electron app on Windows so they should hold, but please open an issue
# if anything misbehaves: https://github.com/Agents365-ai/dsclaude/issues
#
# Usage:
#   pwsh ./qwclaude-desktop.ps1                          # pay-as-you-go (Beijing)
#   pwsh ./qwclaude-desktop.ps1 -Plan coding             # Coding Plan
#   pwsh ./qwclaude-desktop.ps1 -Plan token              # Token Plan team edition
#   pwsh ./qwclaude-desktop.ps1 -Region intl             # pay-as-you-go, Singapore
#   pwsh ./qwclaude-desktop.ps1 -ClaudeExePath <path>    # specify custom Claude.exe
#   pwsh ./qwclaude-desktop.ps1 -Update                  # git pull latest from the repo
#   pwsh ./qwclaude-desktop.ps1 -h                       # help
#
# Reads the plan-specific Bailian API key from env (else prompts): pay-as-you-go
# → DASHSCOPE_API_KEY, Coding Plan → DASHSCOPE_CP_API_KEY, Token Plan → DASHSCOPE_TP_API_KEY.
#
# Requires: PowerShell 5.1+ (Windows 10+ ships this), Claude Desktop installed,
# Developer Mode enabled in Claude Desktop, Bailian API key.

[CmdletBinding()]
param(
    [Alias('h')][switch]$Help,
    [switch]$Update,
    [string]$ClaudeExePath,
    [Parameter(Position = 0)]
    [ValidateSet('payg', 'pay-as-you-go', 'coding', 'token-plan', 'token', 'tp')]
    [string]$Plan = 'payg',
    [ValidateSet('cn', 'beijing', 'intl', 'singapore', 'sg')]
    [string]$Region = 'cn'
)

$ErrorActionPreference = 'Stop'

# ---- Help ------------------------------------------------------------------

if ($Help) {
    Get-Content $PSCommandPath | Select-Object -Skip 1 -First 26 |
        ForEach-Object { $_ -replace '^# ?', '' }
    exit 0
}

if ($Update) {
    $repo = Split-Path -Parent $PSCommandPath
    Write-Host "qwclaude-desktop: pulling latest from $repo ..."
    git -C $repo pull
    if ($LASTEXITCODE -eq 0) {
        Write-Host 'qwclaude-desktop: updated.'
    } else {
        Write-Error 'qwclaude-desktop: git pull failed. Check network or resolve conflicts manually.'
        exit 1
    }
    exit 0
}

# ---- Constants -------------------------------------------------------------

$ConfigDir  = Join-Path $env:LOCALAPPDATA 'Claude-3p\configLibrary'
$StoreDir   = if (Get-ChildItem "$env:LOCALAPPDATA\Packages\Claude_*" -ErrorAction SilentlyContinue) {
                  Join-Path (Resolve-Path "$env:LOCALAPPDATA\Packages\Claude_*") 'LocalCache\Roaming\Claude-3p\configLibrary'
              } else { $null }
$EntryName  = 'qwclaude-desktop'
$AuthScheme = 'bearer'

$ClaudeExe = $null  # populated by Test-Preflight

# ---- Resolve base URL, models, key variable, and label from the plan -------

# Normalize plan/region aliases.
switch ($Plan) {
    { $_ -in 'token-plan', 'token', 'tp' } { $Plan = 'token-plan' }
    'pay-as-you-go'                        { $Plan = 'payg' }
}
switch ($Region) {
    { $_ -in 'intl', 'singapore', 'sg' } { $Region = 'intl' }
    'beijing'                            { $Region = 'cn' }
}

switch ($Plan) {
    'token-plan' {
        $BaseUrl    = 'https://token-plan.cn-beijing.maas.aliyuncs.com/apps/anthropic'
        $MainModel  = 'qwen3.7-max'
        $FastModel  = 'qwen3.6-flash'
        $KeyVar     = 'DASHSCOPE_TP_API_KEY'
        $PlanLabel  = 'Token Plan'
    }
    'coding' {
        # Coding Plan only serves qwen3.6-plus — no separate flash tier.
        $BaseUrl    = 'https://coding.dashscope.aliyuncs.com/apps/anthropic'
        $MainModel  = 'qwen3.6-plus'
        $FastModel  = 'qwen3.6-plus'
        $KeyVar     = 'DASHSCOPE_CP_API_KEY'
        $PlanLabel  = 'Coding Plan'
    }
    default {
        $Plan = 'payg'
        $BaseUrl = if ($Region -eq 'intl') {
            'https://dashscope-intl.aliyuncs.com/apps/anthropic'
        } else {
            'https://dashscope.aliyuncs.com/apps/anthropic'
        }
        $MainModel  = 'qwen3.7-max'
        $FastModel  = 'qwen3.6-flash'
        $KeyVar     = 'DASHSCOPE_API_KEY'
        $PlanLabel  = 'pay-as-you-go'
    }
}

# ---- JSON helpers ----------------------------------------------------------
# ConvertTo-Json unwraps single-element arrays into a bare value (e.g. Coding
# Plan's one model, or a fresh _meta with one entry). Build arrays explicitly so
# they always serialize as JSON arrays.

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

# Claude Desktop's parser rejects entries with a trailing newline ("unknown
# config id"), so we TrimEnd before writing. Writes via .NET to control the
# encoding (UTF-8 no-BOM).
function Write-TextAtomic {
    param([string]$Path, [string]$Text)
    $Text = $Text.TrimEnd("`r", "`n")
    $tmp = "$Path.tmp"
    [System.IO.File]::WriteAllText($tmp, $Text, [System.Text.UTF8Encoding]::new($false))
    Move-Item -Path $tmp -Destination $Path -Force
}

# ---- Pre-flight ------------------------------------------------------------

function Test-Preflight {
    # PS 5.1 has no $IsWindows; assume yes if absent (PS 5.1 is Windows-only).
    $isWin = if ($null -ne $IsWindows) { $IsWindows } else { $true }
    if (-not $isWin) {
        Write-Error 'qwclaude-desktop.ps1: Windows only. Use ./qwclaude-desktop on macOS.'
        exit 1
    }

    if ($script:ClaudeExePath) {
        if (-not (Test-Path $script:ClaudeExePath)) {
            Write-Error "qwclaude-desktop.ps1: Claude.exe not found at '$script:ClaudeExePath'"
            exit 1
        }
        $script:ClaudeExe = $script:ClaudeExePath
    } else {
        # Auto-detect: Windows Store package first (Get-AppxPackage is the
        # reliable way to find Store-installed apps without touching the
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
qwclaude-desktop.ps1: Claude Desktop not found.
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
        Write-Host 'qwclaude-desktop.ps1: Enabling Developer Mode for Claude Desktop...'
        if (-not (Test-Path $devDir)) { New-Item -ItemType Directory -Path $devDir -Force | Out-Null }
        $devContent = '{ "allowDevTools": true }'
        [System.IO.File]::WriteAllText($devSettings, $devContent, [System.Text.UTF8Encoding]::new($false))
        Write-Host 'qwclaude-desktop.ps1: Developer Mode enabled.'
    }
}

# ---- API key resolution ----------------------------------------------------

function Resolve-ApiKey {
    param([string]$Name, [string]$Label)
    $v = [Environment]::GetEnvironmentVariable($Name, 'Process')
    if ($v) { return $v }
    foreach ($scope in 'User', 'Machine') {
        $v = [Environment]::GetEnvironmentVariable($Name, $scope)
        if ($v) { return $v }
    }

    # Windows has no shell-rc tradition; jump straight to interactive prompt.
    $secure = Read-Host "$Name (Bailian $Label) not set. Paste your key" -AsSecureString
    if (-not $secure -or $secure.Length -eq 0) {
        Write-Error "qwclaude-desktop.ps1: no $Name provided. Aborting."
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

# Ensure _meta.json has an entry named $EntryName (creating or reusing its
# uuid) and set appliedId to that uuid. Returns the uuid.
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

    # unstableDisableModelVerification skips Claude Desktop 1.7xxx's local
    # model-name validator, which otherwise rejects non-Anthropic names
    # (deepseek/qwen/gemini/...) before any request leaves the app.
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
$apiKey = Resolve-ApiKey $KeyVar $PlanLabel
Confirm-OrAbort -Action "configure Claude Desktop to use Bailian $PlanLabel ($BaseUrl) and restart it."
$uuid = Update-MetaEntry
Write-Entry -Uuid $uuid -ApiKey $apiKey
Restart-Claude

@"

Done. Claude Desktop is restarting with Bailian $PlanLabel as the inference backend.

Heads up: Chat mode is unavailable while a third-party gateway is active.
You'll see Cowork (3P) and Code modes only. To use Chat:

  - At launch chooser, pick "Continue with Anthropic", OR
  - In Developer -> Configure Third-Party Inference, toggle off "Skip
    login-mode chooser" (default is off, so the chooser should appear)

Re-run qwclaude-desktop.ps1 any time to refresh the gateway config.
"@ | Write-Host
