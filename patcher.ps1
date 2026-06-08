param([switch]$NoElevate)

# LightPDF Editor - Premium Unlock Patcher
# Requires: Administrator privileges (for hosts file modification)

$HostsPath = "$env:windir\System32\drivers\etc\hosts"
$AppDir = "C:\Program Files (x86)\LightPDF\LightPDF Editor"
$LicenseDir = "$env:APPDATA\LightPDF\LightPDF Editor"
$LicenseFile = "$LicenseDir\passport.userinfo"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Blocked domains
$Domains = @(
    "gw.aoscdn.com", "aw.aoscdn.com", "devgw.aoscdn.com", "devaw.aoscdn.com",
    "checkout.aoscdn.com", "myaccount.apowersoft.com", "api.aoscdn.com",
    "cdn.aoscdn.com", "download.aoscdn.com", "login.aoscdn.com",
    "gw.wangxutech.com", "aw.wangxutech.com",
    "gw.apsapp.cn", "aw.apsapp.cn",
    "download.wangxutech.com", "download.apsapp.cn"
)

# Auto-elevate if not admin
If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator") -and -not $NoElevate) {
    Write-Host "Requesting administrator privileges..." -ForegroundColor Yellow
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -NoElevate"
    Exit
}

Function Add-HostsBlock {
    Write-Host "[*] Blocking license verification servers..." -ForegroundColor Cyan
    $blockHeader = "`r`n# Block LightPDF license servers (added by patcher)"
    $hostsContent = Get-Content $HostsPath -Raw
    If ($hostsContent -match "LightPDF license servers") {
        Write-Host "    [-] Hosts already blocked, skipping" -ForegroundColor Yellow
        Return
    }
    $blockEntries = ""
    ForEach ($d in $Domains) {
        $blockEntries += "`r`n127.0.0.1 $d"
    }
    ForEach ($d in $Domains) {
        $blockEntries += "`r`n::1 $d"
    }
    Add-Content -Path $HostsPath -Value "$blockHeader$blockEntries" -Encoding Default
    Write-Host "    [+] Blocked $($Domains.Count) domains" -ForegroundColor Green
    ipconfig /flushdns | Out-Null
}

Function Install-LicenseFile {
    Write-Host "[*] Installing forged premium license..." -ForegroundColor Cyan
    If (-not (Test-Path $LicenseDir)) {
        New-Item -ItemType Directory -Path $LicenseDir -Force | Out-Null
    }
    $forgeFile = Join-Path $ScriptDir "files\passport.userinfo"
    If (-not (Test-Path $forgeFile)) {
        Write-Host "    [!] License file not found at $forgeFile" -ForegroundColor Red
        Return $false
    }
    If (Test-Path $LicenseFile) {
        Copy-Item $LicenseFile "$LicenseFile.original.bak" -Force
        Write-Host "    [+] Backed up original to passport.userinfo.original.bak" -ForegroundColor Green
    }
    Copy-Item $forgeFile $LicenseFile -Force
    Write-Host "    [+] Installed forged premium license" -ForegroundColor Green
    Return $true
}

Function Show-Status {
    Write-Host "`n========== LIGHTPDF EDITOR - PREMIUM UNLOCKED ==========" -ForegroundColor Green
    Write-Host "  License: Lifetime Commercial" -ForegroundColor Green
    Write-Host "  Status:  Activated" -ForegroundColor Green
    Write-Host "  Expiry:  2099-12-31" -ForegroundColor Green
    Write-Host "========================================================" -ForegroundColor Green
}

# --- MAIN ---
Write-Host "`n  LightPDF Editor - Premium Unlock Patcher" -ForegroundColor Magenta
Write-Host "  ========================================`n" -ForegroundColor Magenta

# Kill running instances
$procs = Get-Process -Name "LightPDF Editor" -ErrorAction SilentlyContinue
If ($procs) {
    Write-Host "[*] Closing running LightPDF instances..." -ForegroundColor Yellow
    $procs | Stop-Process -Force
    Start-Sleep 1
}

Add-HostsBlock
Install-LicenseFile
Show-Status

Write-Host "`n[+] Done! Launch LightPDF Editor - premium features are now unlocked.`n" -ForegroundColor Green
