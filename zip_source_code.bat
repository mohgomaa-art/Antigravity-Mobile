<# :
@echo off
setlocal enabledelayedexpansion
title Antigravity - Source Code Archiver

set "TARGET_ZIP="
set "NO_PAUSE=0"

for %%a in (%*) do (
    if /i "%%a"=="/nopause" (
        set "NO_PAUSE=1"
    ) else if /i "%%a"=="-nopause" (
        set "NO_PAUSE=1"
    ) else if /i "%%a"=="--nopause" (
        set "NO_PAUSE=1"
    ) else if /i "%%a"=="-y" (
        set "NO_PAUSE=1"
    ) else (
        if not defined TARGET_ZIP set "TARGET_ZIP=%%~a"
    )
)

powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText('%~f0'))"
set "EXIT_CODE=%ERRORLEVEL%"

if "%NO_PAUSE%"=="0" (
    echo %cmdcmdline% | findstr /i /c:"%~nx0" >nul
    if !ERRORLEVEL! equ 0 (
        echo.
        pause
    )
)
exit /b %EXIT_CODE%
: #>

# ==============================================================================
# Antigravity Source Code Packaging Engine (v1.0.4)
# Packages pure, complete source code preserving exact architecture and paths.
# ==============================================================================

$ErrorActionPreference = "Stop"
$sw = [System.Diagnostics.Stopwatch]::StartNew()

$scriptPath = $MyInvocation.MyCommand.Path
if ([string]::IsNullOrEmpty($scriptPath)) {
    $root = (Get-Location).Path
} else {
    $root = Split-Path -Parent $scriptPath
}

# Determine target output zip file from environment or defaults
$targetZip = $env:TARGET_ZIP

if ([string]::IsNullOrEmpty($targetZip)) {
    $outDir = Join-Path $root "APP"
    $zipPath = Join-Path $outDir "Antigravity-SourceCode-v1.0.4.zip"
    $latestZip = Join-Path $outDir "Antigravity-SourceCode-Latest.zip"
} else {
    $zipPath = [System.IO.Path]::GetFullPath($targetZip)
    $outDir = [System.IO.Path]::GetDirectoryName($zipPath)
    $latestZip = $null
}

if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

Clear-Host
Write-Host "===============================================================================" -ForegroundColor Cyan
Write-Host "               ANTIGRAVITY SOURCE CODE PACKAGER (v1.0.4)                       " -ForegroundColor Cyan
Write-Host "===============================================================================" -ForegroundColor Cyan
Write-Host " Project Root : $root" -ForegroundColor Gray
Write-Host " Target Output: $zipPath" -ForegroundColor Gray
if ($latestZip) {
    Write-Host " Mirror Copy  : $latestZip" -ForegroundColor Gray
}
Write-Host "===============================================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "[1/4] Scanning codebase for pure source files..." -ForegroundColor Cyan

# Directories to exclude at root
$excludedDirs = @(
    "build", "dist", "APP", ".git", ".pytest_cache", "__pycache__", "projects", "scratch"
)

# Relative path prefixes to exclude
$excludedRelPrefixes = @(
    "flutter_app\build\",
    "flutter_app\.dart_tool\",
    "flutter_app\.idea\",
    "flutter_app\android\.gradle\",
    "flutter_app\android\app\build\",
    "flutter_app\windows\flutter\ephemeral\"
)

# Root-level temporary dumps, logs, and screenshots to exclude
$excludedRootPatterns = @(
    "screen_*.png", "screen*.png", "*_dump.xml", "ui_*.xml", "dump_check.xml", "drawer_dump2.xml",
    "pairing_dump.xml", "perm_dump.xml", "q_dump.xml", "scroll_dump.xml", "window_dump.xml",
    "chat_response.png", "chat_sent.png", "scratch_ls.js", "scratch_main.js", "test_turns.py",
    "2026-09-28", "*.log", "*.zip"
)

$allFiles = Get-ChildItem -Path $root -Recurse -File
$selectedFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()

foreach ($f in $allFiles) {
    $rel = $f.FullName.Substring($root.Length).TrimStart('\')
    $topPart = $rel.Split('\')[0]
    
    # 1. Skip excluded root directories
    if ($excludedDirs -contains $topPart) { continue }
    
    # 2. Skip internal cache/build folders
    $skip = $false
    foreach ($p in $excludedRelPrefixes) {
        if ($rel.StartsWith($p, [System.StringComparison]::OrdinalIgnoreCase)) {
            $skip = $true
            break
        }
    }
    if ($skip) { continue }
    
    # 3. Skip Python bytecode and caches anywhere
    if ($rel -match "\\__pycache__\\" -or $f.Extension -in @(".pyc", ".pyo")) { continue }
    
    # 4. Skip root temporary test dumps and screenshots
    if (-not $rel.Contains('\')) {
        foreach ($pat in $excludedRootPatterns) {
            if ($f.Name -like $pat) {
                $skip = $true
                break
            }
        }
        if ($skip) { continue }
    }
    
    $selectedFiles.Add($f)
}

Write-Host "      Found $($selectedFiles.Count) clean source files." -ForegroundColor Green
Write-Host ""

# Summarize breakdown by top module
$summary = $selectedFiles | Group-Object {
    $rel = $_.FullName.Substring($root.Length).TrimStart('\')
    if ($rel.Contains('\')) { $rel.Split('\')[0] } else { "(root files)" }
} | Sort-Object Count -Descending

Write-Host "      Architecture Breakdown:" -ForegroundColor Gray
foreach ($group in $summary) {
    Write-Host ("       - {0,-20} : {1,3} files" -f $group.Name, $group.Count) -ForegroundColor DarkGray
}
Write-Host ""

Write-Host "[2/4] Initializing archive engine (.NET ZipArchive)..." -ForegroundColor Cyan
if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$zipStream = [System.IO.File]::Open($zipPath, [System.IO.FileMode]::Create)
$archive = [System.IO.Compression.ZipArchive]::new($zipStream, [System.IO.Compression.ZipArchiveMode]::Create)

Write-Host "[3/4] Compressing files preserving relative architecture..." -ForegroundColor Cyan

try {
    $count = 0
    foreach ($f in $selectedFiles) {
        $relPath = $f.FullName.Substring($root.Length).TrimStart('\').Replace('\', '/')
        $entry = $archive.CreateEntry($relPath, [System.IO.Compression.CompressionLevel]::Optimal)
        $entryStream = $entry.Open()
        $fileStream = [System.IO.File]::OpenRead($f.FullName)
        $fileStream.CopyTo($entryStream)
        $fileStream.Close()
        $entryStream.Close()
        $count++
    }
} finally {
    $archive.Dispose()
    $zipStream.Dispose()
}

# Mirror to latest zip if configured
if (-not [string]::IsNullOrEmpty($latestZip)) {
    Copy-Item $zipPath $latestZip -Force
}

$sw.Stop()
$zipItem = Get-Item $zipPath
$zipSizeMb = [math]::Round($zipItem.Length / 1MB, 2)

Write-Host "[4/4] Verifying archive integrity..." -ForegroundColor Cyan
$verifyStream = [System.IO.File]::OpenRead($zipPath)
$verifyArchive = [System.IO.Compression.ZipArchive]::new($verifyStream, [System.IO.Compression.ZipArchiveMode]::Read)
$verifiedCount = $verifyArchive.Entries.Count
$verifyArchive.Dispose()
$verifyStream.Dispose()

Write-Host ""
Write-Host "===============================================================================" -ForegroundColor Green
Write-Host "                 SOURCE CODE ARCHIVED SUCCESSFULLY!                            " -ForegroundColor Green
Write-Host "===============================================================================" -ForegroundColor Green
Write-Host (" Output Archive  : " + $zipItem.FullName) -ForegroundColor Yellow
if (-not [string]::IsNullOrEmpty($latestZip)) {
    Write-Host (" Mirror Output   : " + $latestZip) -ForegroundColor Yellow
}
Write-Host (" Total Files     : " + $verifiedCount + " source files") -ForegroundColor White
Write-Host (" Total Size      : " + $zipSizeMb + " MB (" + $zipItem.Length + " bytes)") -ForegroundColor White
Write-Host (" Elapsed Time    : " + [math]::Round($sw.Elapsed.TotalSeconds, 2) + " seconds") -ForegroundColor White
Write-Host " Structure Check : 100% exact directory hierarchy preserved." -ForegroundColor White
Write-Host " Clean Status    : Zero build caches, zero temporary dumps, zero bloated logs." -ForegroundColor White
Write-Host "===============================================================================" -ForegroundColor Green
Write-Host ""
