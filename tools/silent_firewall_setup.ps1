param(
    [int]$GatewayPort = 8765,
    [string]$InstallDir = "",
    [switch]$Uninstall
)

if ($env:AGY_PORT) {
    try { $GatewayPort = [int]$env:AGY_PORT } catch {}
}

$ErrorActionPreference = "SilentlyContinue"

# --- UNINSTALL MODE ---
if ($Uninstall) {
    Write-Host "Removing all Antigravity Windows Defender Firewall rules..." -ForegroundColor Cyan
    Get-NetFirewallRule | Where-Object { 
        $_.DisplayName -match "Antigravity" -or $_.Name -match "Antigravity"
    } | ForEach-Object {
        Remove-NetFirewallRule -Name $_.Name -ErrorAction SilentlyContinue
    }
    Write-Host "Antigravity firewall rules removed." -ForegroundColor Green
    exit 0
}

# --- INSTALL / CONFIGURE MODE ---
Write-Host "Configuring Windows Defender Firewall rules for Antigravity Fleet Station (Port $GatewayPort)..." -ForegroundColor Cyan

if (-not $InstallDir -or -not (Test-Path $InstallDir)) {
    $InstallDir = Split-Path -Parent $PSScriptRoot
}

$localAppData = $env:LOCALAPPDATA
$userProfile = $env:USERPROFILE
$progFiles = $env:ProgramFiles

$targets = @(
    # Port Gateway TCP/UDP on all network profiles
    @{ Name = "Antigravity Fleet Station Port $GatewayPort"; Type = "Port"; Port = $GatewayPort; Protocol = "TCP" },
    @{ Name = "Antigravity Fleet Station Port $GatewayPort Out"; Type = "Port"; Port = $GatewayPort; Protocol = "TCP"; Dir = "Out" },
    @{ Name = "Antigravity Fleet Station UDP Beacon"; Type = "Port"; Port = $GatewayPort; Protocol = "UDP" },
    @{ Name = "Antigravity Fleet Station UDP Beacon Out"; Type = "Port"; Port = $GatewayPort; Protocol = "UDP"; Dir = "Out" },
    @{ Name = "Antigravity Fleet Station UDP Beacon 8766"; Type = "Port"; Port = 8766; Protocol = "UDP" },
    @{ Name = "Antigravity Fleet Station UDP Beacon 8766 Out"; Type = "Port"; Port = 8766; Protocol = "UDP"; Dir = "Out" },
    # Port 5037 (ADB Daemon)
    @{ Name = "Antigravity Fleet Station ADB Port"; Type = "Port"; Port = 5037; Protocol = "TCP" },
    @{ Name = "Antigravity Fleet Station ADB Port Out"; Type = "Port"; Port = 5037; Protocol = "TCP"; Dir = "Out" },
    # Binaries in target install directory
    @{ Name = "Antigravity Installed - Bridge In"; Program = "$InstallDir\bridge\antigravity_bridge.exe"; Dir = "In" },
    @{ Name = "Antigravity Installed - Bridge Out"; Program = "$InstallDir\bridge\antigravity_bridge.exe"; Dir = "Out" },
    @{ Name = "Antigravity Installed - App In"; Program = "$InstallDir\antigravity_mobile.exe"; Dir = "In" },
    @{ Name = "Antigravity Installed - App Out"; Program = "$InstallDir\antigravity_mobile.exe"; Dir = "Out" },
    @{ Name = "Antigravity Installed - Cloudflared In"; Program = "$InstallDir\tools\cloudflared.exe"; Dir = "In" },
    @{ Name = "Antigravity Installed - Cloudflared Out"; Program = "$InstallDir\tools\cloudflared.exe"; Dir = "Out" },
    @{ Name = "Antigravity Installed - ADB In"; Program = "$InstallDir\bridge\adb.exe"; Dir = "In" },
    @{ Name = "Antigravity Installed - ADB Out"; Program = "$InstallDir\bridge\adb.exe"; Dir = "Out" },
    @{ Name = "Antigravity Installed - ADB Internal In"; Program = "$InstallDir\bridge\_internal\adb.exe"; Dir = "In" },
    @{ Name = "Antigravity Installed - ADB Internal Out"; Program = "$InstallDir\bridge\_internal\adb.exe"; Dir = "Out" },
    # Standard Program Files fallback
    @{ Name = "Antigravity ProgramFiles - Bridge In"; Program = "$progFiles\Antigravity Fleet Station\bridge\antigravity_bridge.exe"; Dir = "In" },
    @{ Name = "Antigravity ProgramFiles - Bridge Out"; Program = "$progFiles\Antigravity Fleet Station\bridge\antigravity_bridge.exe"; Dir = "Out" },
    @{ Name = "Antigravity ProgramFiles - App In"; Program = "$progFiles\Antigravity Fleet Station\antigravity_mobile.exe"; Dir = "In" },
    @{ Name = "Antigravity ProgramFiles - App Out"; Program = "$progFiles\Antigravity Fleet Station\antigravity_mobile.exe"; Dir = "Out" },
    # Development / workspace fallback
    @{ Name = "Antigravity Dev - Bridge In"; Program = "$InstallDir\dist\antigravity_bridge\antigravity_bridge.exe"; Dir = "In" },
    @{ Name = "Antigravity Dev - Bridge Out"; Program = "$InstallDir\dist\antigravity_bridge\antigravity_bridge.exe"; Dir = "Out" },
    @{ Name = "Antigravity Dev - Flutter Runner In"; Program = "$InstallDir\flutter_app\build\windows\x64\runner\Release\antigravity_mobile.exe"; Dir = "In" },
    @{ Name = "Antigravity Dev - Flutter Runner Out"; Program = "$InstallDir\flutter_app\build\windows\x64\runner\Release\antigravity_mobile.exe"; Dir = "Out" }
)

foreach ($item in $targets) {
    $dir = if ($item.Dir) { $item.Dir } else { "In" }
    netsh advfirewall firewall delete rule name="$($item.Name)" | Out-Null
    
    if ($item.Type -eq "Port") {
        netsh advfirewall firewall add rule name="$($item.Name)" dir=$dir action=allow protocol=$($item.Protocol) localport=$($item.Port) profile=any | Out-Null
        Write-Host " [OK] Allowed Port $($item.Port) ($($item.Protocol), $dir)" -ForegroundColor Green
    } elseif ($item.Program) {
        if (Test-Path $item.Program) {
            netsh advfirewall firewall add rule name="$($item.Name)" dir=$dir action=allow program="$($item.Program)" enable=yes profile=any | Out-Null
            Write-Host " [OK] Whitelisted binary ($dir): $($item.Program)" -ForegroundColor Green
        }
    }
}

# Purge any Windows "Block" entries for our binaries
Get-NetFirewallRule | Where-Object { 
    ($_.DisplayName -match "antigravity|cloudflared|adb" -or $_.Name -match "antigravity|cloudflared|adb") -and 
    $_.Action -eq "Block"
} | ForEach-Object {
    Write-Host " [PURGED] Removed conflicting BLOCK rule: $($_.DisplayName)" -ForegroundColor Yellow
    Remove-NetFirewallRule -Name $_.Name -ErrorAction SilentlyContinue
}

# Purge any Windows "Query User" entries so Windows Defender never prompts again
Get-NetFirewallRule | Where-Object { 
    $_.Name -match "Query User" -and (
        $_.DisplayName -match "adb|cloudflared|antigravity" -or 
        $_.Name -match "adb|cloudflared|antigravity"
    ) 
} | ForEach-Object {
    Write-Host " [PURGED] Removed pending query prompt rule: $($_.DisplayName)" -ForegroundColor Yellow
    Remove-NetFirewallRule -Name $_.Name -ErrorAction SilentlyContinue
}

Write-Host "Windows Defender Firewall configuration complete. No access prompts will be shown." -ForegroundColor Green
