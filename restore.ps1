param([switch]$NoElevate)

# LightPDF Editor - Restore original state

$HostsPath = "$env:windir\System32\drivers\etc\hosts"
$LicenseDir = "$env:APPDATA\LightPDF\LightPDF Editor"
$LicenseFile = "$LicenseDir\passport.userinfo"

If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator") -and -not $NoElevate) {
    Write-Host "Requesting administrator privileges..." -ForegroundColor Yellow
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -NoElevate"
    Exit
}

Function Remove-HostsBlock {
    Write-Host "[*] Removing hosts file blocks..." -ForegroundColor Cyan
    $content = Get-Content $HostsPath -Raw
    $original = $content -replace "(?s)\r?\n# Block LightPDF license servers.*$", ""
    If ($original -ne $content) {
        Set-Content -Path $HostsPath -Value $original.TrimEnd() -Encoding Default
        Write-Host "    [+] Removed hosts block entries" -ForegroundColor Green
        ipconfig /flushdns | Out-Null
    } Else {
        Write-Host "    [-] No block entries found" -ForegroundColor Yellow
    }
}

Function Restore-LicenseFile {
    Write-Host "[*] Restoring original license..." -ForegroundColor Cyan
    $backup = "$LicenseFile.original.bak"
    If (Test-Path $backup) {
        Copy-Item $backup $LicenseFile -Force
        Write-Host "    [+] Restored original license from backup" -ForegroundColor Green
    } ElseIf (Test-Path $LicenseFile) {
        Remove-Item $LicenseFile -Force
        Write-Host "    [-] Removed forged license (no backup found)" -ForegroundColor Yellow
    } Else {
        Write-Host "    [-] No license file found" -ForegroundColor Yellow
    }
}

Write-Host "`n  LightPDF Editor - Restore Original State" -ForegroundColor Magenta
Write-Host "  ========================================`n" -ForegroundColor Magenta

$procs = Get-Process -Name "LightPDF Editor" -ErrorAction SilentlyContinue
If ($procs) { $procs | Stop-Process -Force; Start-Sleep 1 }

Remove-HostsBlock
Restore-LicenseFile

Write-Host "`n[+] Restore complete. Launch LightPDF Editor - it will revert to trial/free.`n" -ForegroundColor Green
