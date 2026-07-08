#!/usr/bin/env pwsh
# install.ps1 — one-command installer for xxclaude launchers (Windows).
#
# Usage:
#   irm https://raw.githubusercontent.com/Agents365-ai/dsclaude/main/install.ps1 | iex
#
#   # Or, if you already have the repo:
#   pwsh -File ./install.ps1
#
#   # Custom install directory:
#   pwsh -File ./install.ps1 -Prefix "C:\tools\bin"
#
# Requires PowerShell 5.1+ (ships with Windows 10+).

[CmdletBinding()]
param(
    [string]$Prefix = "",
    [switch]$AddToPath
)

$ErrorActionPreference = 'Stop'

# ---- Resolve install directory ---------------------------------------------
if (-not $Prefix) {
    $Prefix = Join-Path $env:USERPROFILE 'bin'
}

if (-not (Test-Path $Prefix)) {
    New-Item -ItemType Directory -Path $Prefix -Force | Out-Null
}

Write-Host "install.ps1: installing to $Prefix"

# ---- Get the scripts -------------------------------------------------------
$repoDir = $null
$selfDir = if ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { $null }
if ($selfDir -and (Test-Path (Join-Path $selfDir 'dsclaude.ps1')) -and (Test-Path (Join-Path $selfDir '.git'))) {
    $repoDir = $selfDir
    Write-Host "install.ps1: using local repo at $repoDir"
} else {
    $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "dsclaude-install-$(Get-Random)"
    Write-Host "install.ps1: downloading from GitHub..."
    try {
        git clone --depth 1 'https://github.com/Agents365-ai/dsclaude.git' $tmpDir *>$null
        if ($LASTEXITCODE -ne 0) { throw "git clone failed" }
        $repoDir = $tmpDir
    } catch {
        Write-Warning "git clone failed. Trying zip download..."
        $zipUrl = 'https://github.com/Agents365-ai/dsclaude/archive/refs/heads/main.zip'
        $zipPath = Join-Path $env:TEMP 'dsclaude-main.zip'
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath
        Expand-Archive -Path $zipPath -DestinationPath $env:TEMP -Force
        $repoDir = Join-Path $env:TEMP 'dsclaude-main'
        Remove-Item $zipPath -Force
    }
}

# ---- Install PS1 CLI launchers ---------------------------------------------
$count = 0
Write-Host "install.ps1: installing CLI launchers..."
Get-ChildItem -Path $repoDir -Filter '*.ps1' | ForEach-Object {
    $name = $_.Name
    # Skip desktop configurators and the installer itself.
    if ($name -match '-desktop') { return }
    if ($name -eq 'install.ps1') { return }
    Copy-Item $_.FullName (Join-Path $Prefix $name) -Force
    Write-Host "  $name"
    $count++
}

# ---- Install desktop PS1 configurators -------------------------------------
Write-Host "install.ps1: installing desktop configurators..."
Get-ChildItem -Path $repoDir -Filter '*-desktop.ps1' | ForEach-Object {
    $name = $_.Name
    Copy-Item $_.FullName (Join-Path $Prefix $name) -Force
    Write-Host "  $name"
    $count++
}

Write-Host ""
Write-Host "✓ Installed $count scripts to $Prefix"

# ---- PATH check ------------------------------------------------------------
$userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
$machinePath = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
$inPath = ($userPath -like "*$Prefix*") -or ($machinePath -like "*$Prefix*")

if (-not $inPath) {
    if ($AddToPath) {
        Write-Host "install.ps1: adding $Prefix to User PATH..."
        [Environment]::SetEnvironmentVariable('PATH', "$userPath;$Prefix", 'User')
        Write-Host "install.ps1: PATH updated. Restart your terminal for changes to take effect."
    } else {
        Write-Host ""
        Write-Host "⚠️  $Prefix is not in your PATH. Add it manually or re-run with -AddToPath:"
        Write-Host "     irm .../install.ps1 | iex  →  change to:  irm .../install.ps1 | iex -AddToPath"
        Write-Host "   Or add it from System Settings → Environment Variables."
    }
}

Write-Host ""
Write-Host "Now set an API key and launch:"
Write-Host "  setx DEEPSEEK_API_KEY `"sk-...`""
Write-Host "  # then in a new terminal:"
Write-Host "  pwsh -File xclaude.ps1"
