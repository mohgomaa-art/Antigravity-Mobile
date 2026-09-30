$rootDir = Split-Path -Parent $PSScriptRoot
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
if (-not (Test-Path $adb)) {
    $adb = "$rootDir\tools\adb\adb.exe"
}
if (-not (Test-Path $adb)) {
    $adb = "adb.exe"
}
$apkItem = Get-ChildItem "$rootDir\APP\*.apk" -ErrorAction SilentlyContinue | Select-Object -First 1
$apk = if ($apkItem) { $apkItem.FullName } else { "$rootDir\APP\Antigravity-Mobile-v1.0.0.apk" }

Write-Host "=========================================="
Write-Host "Antigravity Mobile ADB Auto-Installer"
Write-Host "Target APK: $apk"
Write-Host "Monitoring ADB devices..."
Write-Host "=========================================="

$maxAttempts = 120
for ($i = 1; $i -le $maxAttempts; $i++) {
    $devicesOutput = & $adb devices -l
    
    # Check for unauthorized device
    if ($devicesOutput -match "unauthorized") {
        Write-Host "[$i/$maxAttempts] Device found but UNAUTHORIZED! Please check your phone screen and tap 'Allow USB Debugging'." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
        continue
    }
    
    # Check for authorized device
    if ($devicesOutput -match "device\s+product:") {
        Write-Host "[$i/$maxAttempts] Device connected and authorized!" -ForegroundColor Green
        Write-Host "Installing APK: $apk..."
        
        $installResult = & $adb install -r -d "$apk" 2>&1
        Write-Host $installResult
        
        if ($installResult -match "Success") {
            Write-Host "SUCCESS! App installed successfully on mobile device." -ForegroundColor Green
            # Launch the app
            Write-Host "Launching Antigravity Mobile..."
            & $adb shell am start -n com.antigravity.antigravity_mobile/.MainActivity
            exit 0
        } else {
            Write-Host "Install attempt finished with: $installResult" -ForegroundColor Yellow
            # If prompt required permission, give user 3 seconds to tap allow and retry
            Start-Sleep -Seconds 3
        }
    } else {
        if ($i % 5 -eq 0) {
            Write-Host "[$i/$maxAttempts] Waiting for phone to be connected via USB with USB Debugging enabled..."
        }
    }
    Start-Sleep -Seconds 1
}

Write-Host "Timeout: No authorized ADB device connected within $maxAttempts seconds." -ForegroundColor Red
exit 1
