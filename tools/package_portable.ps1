$ErrorActionPreference = "Stop"
$root = "D:\Antigravity"
$portableStaging = Join-Path $root "dist\portable_staging"
$outDir = Join-Path $root "APP"

Write-Host "Creating portable distribution staging at: $portableStaging" -ForegroundColor Cyan

if (Test-Path $portableStaging) {
    Remove-Item $portableStaging -Recurse -Force
}
New-Item -ItemType Directory -Path $portableStaging -Force | Out-Null

# 1. Copy Flutter runner Release directory contents to staging root
$flutterRelease = Join-Path $root "flutter_app\build\windows\x64\runner\Release"
Write-Host "Copying Flutter Windows release binaries..." -ForegroundColor Gray
Copy-Item -Path "$flutterRelease\*" -Destination $portableStaging -Recurse -Force

# 2. Copy compiled Python bridge to staging/bridge
$bridgeDest = Join-Path $portableStaging "bridge"
Write-Host "Copying compiled Python bridge..." -ForegroundColor Gray
Copy-Item -Path "$root\dist\antigravity_bridge" -Destination $bridgeDest -Recurse -Force

# 3. Copy tools to staging/tools
$toolsDest = Join-Path $portableStaging "tools"
New-Item -ItemType Directory -Path $toolsDest -Force | Out-Null
Copy-Item -Path "$root\tools\cloudflared.exe" -Destination $toolsDest -Force
Copy-Item -Path "$root\tools\silent_firewall_setup.ps1" -Destination $toolsDest -Force

# Also place cloudflared.exe in bridge for direct lookup
Copy-Item -Path "$root\tools\cloudflared.exe" -Destination $bridgeDest -Force

# 4. Copy docs and license
Copy-Item -Path "$root\README.md" -Destination $portableStaging -Force
Copy-Item -Path "$root\LICENSE" -Destination $portableStaging -Force
Copy-Item -Path "$root\DISCLAIMER.md" -Destination $portableStaging -Force
Copy-Item -Path "$root\GUIDE.md" -Destination $portableStaging -Force

# 5. Create launcher batch script
$launcherContent = @"
@echo off
setlocal
cd /d "%~dp0"
echo Starting Antigravity Fleet Station (Portable)...
start "" "antigravity_mobile.exe"
exit /b 0
"@
Set-Content -Path (Join-Path $portableStaging "Run-FleetStation.bat") -Value $launcherContent -Encoding ASCII

# 6. Compress staging into portable zip files in APP
$zipVersioned = Join-Path $outDir "Antigravity-FleetStation-Portable-v1.0.4.zip"
$zipLatest = Join-Path $outDir "Antigravity-FleetStation-Portable.zip"
$zipPortable = Join-Path $outDir "portable.zip"

Write-Host "Compressing portable distribution..." -ForegroundColor Cyan
if (Test-Path $zipVersioned) { Remove-Item $zipVersioned -Force }
Compress-Archive -Path "$portableStaging\*" -DestinationPath $zipVersioned -CompressionLevel Optimal

Write-Host "Copying aliases..." -ForegroundColor Gray
Copy-Item $zipVersioned $zipLatest -Force
Copy-Item $zipVersioned $zipPortable -Force

$zipItem = Get-Item $zipVersioned
Write-Host "Portable package created: $($zipItem.FullName) ($([math]::Round($zipItem.Length/1MB, 2)) MB)" -ForegroundColor Green
