#!/usr/bin/env pwsh
# xclaude.ps1 — auto-detect API key and launch the right backend (Windows port).
#
# Checks env vars and user/machine environment variables for a known API key,
# then delegates to the matching launcher script. No need to remember which
# script name maps to which provider.
#
# Supported keys → launchers, checked in order:
#   DEEPSEEK_API_KEY     → dsclaude     (DeepSeek)
#   MIMO_API_KEY         → mmclaude     (Xiaomi MiMo)
#   DASHSCOPE_API_KEY    → qwclaude     (Bailian Qwen)
#   DASHSCOPE_CP_API_KEY → qwclaude     (Bailian Qwen, Coding Plan)
#   DASHSCOPE_TP_API_KEY → qwclaude     (Bailian Qwen, Token Plan)
#   GLM_API_KEY          → glmclaude    (ZhipuAI GLM)
#   KIMI_API_KEY         → kmclaude    (Moonshot Kimi)
#   ARK_API_KEY          → arkclaude    (Volcengine Ark)
#   LONGCAT_API_KEY      → lcclaude    (Meituan LongCat)
#   MINIMAX_API_KEY      → mxclaude    (MiniMax)
#   HY_API_KEY           → hyclaude    (Tencent TokenHub)
#   SF_API_KEY           → sfclaude    (SiliconFlow)
#
# Use:
#   pwsh -File ./xclaude.ps1                  # auto-detect and launch
#   pwsh -File ./xclaude.ps1 fast             # forwarded: fast tier
#   pwsh -File ./xclaude.ps1 long effort max  # forwarded: 1M + max effort
#   pwsh -File ./xclaude.ps1 kimi             # forwarded: model alias
#
# If multiple keys are set, the first found wins.
# Set $env:XCLAUDE_PREFER = 'dsclaude' to force a specific provider.

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)

$ErrorActionPreference = 'Stop'

# ---- Find the repo directory -----------------------------------------------
function Find-Repo {
    $selfDir = Split-Path -Parent $PSCommandPath
    if (Test-Path (Join-Path $selfDir '.git')) { return $selfDir }
    if ($env:XCLAUDE_HOME) {
        $candidate = $env:XCLAUDE_HOME
        if (Test-Path (Join-Path $candidate '.git')) { return $candidate }
    }
    $candidate = Join-Path $env:USERPROFILE 'github\xxclaude'
    if (Test-Path (Join-Path $candidate '.git')) { return $candidate }
    return $null
}

$Repo = Find-Repo
if (-not $Repo) {
    Write-Error @'
xclaude: cannot find the xxclaude repo.
  Set $env:XCLAUDE_HOME = 'C:\path\to\xxclaude'  or  cd into the repo and run  pwsh -File ./xclaude.ps1
'@
    exit 1
}

# ---- API key resolution ----------------------------------------------------
function Get-ApiKey {
    param([string]$Name)
    if ($env:$Name) { return $env:$Name }
    foreach ($scope in 'User', 'Machine') {
        $v = [Environment]::GetEnvironmentVariable($Name, $scope)
        if ($v) { return $v }
    }
    return $null
}

# ---- Provider registry -----------------------------------------------------
$providers = @(
    @{ Key = 'DEEPSEEK_API_KEY';     Launcher = 'dsclaude.ps1';  Label = 'DeepSeek' },
    @{ Key = 'MIMO_API_KEY';         Launcher = 'mmclaude.ps1';  Label = 'Xiaomi MiMo' },
    @{ Key = 'DASHSCOPE_API_KEY';    Launcher = 'qwclaude.ps1';  Label = 'Bailian Qwen payg' },
    @{ Key = 'DASHSCOPE_CP_API_KEY'; Launcher = 'qwclaude.ps1';  Label = 'Bailian Qwen CodingPlan' },
    @{ Key = 'DASHSCOPE_TP_API_KEY'; Launcher = 'qwclaude.ps1';  Label = 'Bailian Qwen TokenPlan' },
    @{ Key = 'GLM_API_KEY';          Launcher = 'glmclaude.ps1'; Label = 'ZhipuAI GLM' },
    @{ Key = 'KIMI_API_KEY';         Launcher = 'kmclaude.ps1';  Label = 'Moonshot Kimi' },
    @{ Key = 'ARK_API_KEY';          Launcher = 'arkclaude.ps1'; Label = 'Volcengine Ark' },
    @{ Key = 'LONGCAT_API_KEY';      Launcher = 'lcclaude.ps1';  Label = 'Meituan LongCat' },
    @{ Key = 'MINIMAX_API_KEY';      Launcher = 'mxclaude.ps1';  Label = 'MiniMax' },
    @{ Key = 'HY_API_KEY';           Launcher = 'hyclaude.ps1';  Label = 'Tencent TokenHub' },
    @{ Key = 'SF_API_KEY';           Launcher = 'sfclaude.ps1';  Label = 'SiliconFlow' }
)

# ---- Selection logic -------------------------------------------------------
$foundLauncher = $null
$foundLabel = $null

# XCLAUDE_PREFER override.
if ($env:XCLAUDE_PREFER) {
    foreach ($p in $providers) {
        if ($p.Launcher -eq "$($env:XCLAUDE_PREFER).ps1" -or $p.Launcher -eq $env:XCLAUDE_PREFER) {
            $key = Get-ApiKey $p.Key
            if ($key) { $foundLauncher = $p.Launcher; $foundLabel = $p.Label; break }
        }
    }
    if (-not $foundLauncher) {
        Write-Host "xclaude: XCLAUDE_PREFER=$env:XCLAUDE_PREFER but that key is not set. Auto-detecting..."
    }
}

# Auto-detect — first key set wins.
if (-not $foundLauncher) {
    $found = @()
    foreach ($p in $providers) {
        $key = Get-ApiKey $p.Key
        if ($key) { $found += $p }
    }
    if ($found.Count -eq 0) {
        Write-Error @'
xclaude: no known API key found.
  Set one via setx (persistent, new shells) or $env: (current shell):
    setx DEEPSEEK_API_KEY "sk-..."       # DeepSeek
    setx GLM_API_KEY "..."               # ZhipuAI GLM
    setx KIMI_API_KEY "sk-..."           # Moonshot Kimi
    setx DASHSCOPE_API_KEY "sk-..."      # Bailian Qwen
    setx ARK_API_KEY "..."               # Volcengine Ark
    setx LONGCAT_API_KEY "lc-..."        # Meituan LongCat
    setx MINIMAX_API_KEY "..."           # MiniMax
    setx HY_API_KEY "..."                # Tencent TokenHub
    setx SF_API_KEY "sk-..."             # SiliconFlow
    setx MIMO_API_KEY "sk-..."           # Xiaomi MiMo
  Or use a specific launcher: dsclaude.ps1, mmclaude.ps1, qwclaude.ps1, ...
'@
        exit 1
    }
    $foundLauncher = $found[0].Launcher
    $foundLabel = $found[0].Label
    if ($found.Count -gt 1) {
        Write-Host "xclaude: multiple API keys detected ($($found.Count)). Using first found ($foundLabel)."
        Write-Host "  Set `$env:XCLAUDE_PREFER to choose a specific provider."
    }
}

# ---- Delegate --------------------------------------------------------------
$launcherPath = Join-Path $Repo $foundLauncher
if (-not (Test-Path $launcherPath)) {
    Write-Error "xclaude: launcher not found at $launcherPath"
    exit 1
}

Write-Host "xclaude: detected $foundLabel  →  delegating to $foundLauncher"
& pwsh -File $launcherPath @Rest
exit $LASTEXITCODE
