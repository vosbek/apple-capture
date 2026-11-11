#Requires -RunAsAdministrator
# Step 1 (Windows): WSL + Ubuntu 24.04, and usbipd for passing the iPhone's USB into WSL.
# From an ADMIN PowerShell in the repo folder:
#   powershell -ExecutionPolicy Bypass -File .\setup\windows\1-windows-setup.ps1
$ErrorActionPreference = "Stop"

Write-Host "== Checking WSL / Ubuntu =="
$distros = @((wsl.exe -l -q 2>$null) -replace "`0", "" | Where-Object { $_ -match '\S' })
if (-not ($distros -match '^Ubuntu')) {
    Write-Host "Installing WSL with Ubuntu 24.04. Windows may ask you to reboot."
    wsl.exe --install -d Ubuntu-24.04
    Write-Host ""
    Write-Host "After any reboot: open 'Ubuntu' from the Start menu once to create your Linux user,"
    Write-Host "then re-run this script to finish."
    exit 0
}
Write-Host "Found: $($distros -join ', ')"
wsl.exe --update

Write-Host "== Checking usbipd =="
if (-not (Get-Command usbipd -ErrorAction SilentlyContinue)) {
    winget install --exact --id dorssel.usbipd-win --accept-source-agreements --accept-package-agreements
    Write-Host "usbipd installed. Close and reopen PowerShell so it's on PATH."
} else {
    Write-Host "usbipd already installed."
}

Write-Host ""
Write-Host "Done. Next, open Ubuntu, cd to this repo under /mnt/c/..., and run:"
Write-Host "  bash setup/windows/2-wsl-setup.sh"
