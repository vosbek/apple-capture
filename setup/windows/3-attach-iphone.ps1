#Requires -RunAsAdministrator
# Step 3 (Windows, each session): pass the iPhone's USB connection into WSL.
# Plug in the iPhone, unlock it, then from an ADMIN PowerShell in the repo folder:
#   powershell -ExecutionPolicy Bypass -File .\setup\windows\3-attach-iphone.ps1
# Leave this window open while you work: --auto-attach re-attaches when the phone reconnects
# (it does that during pairing and install).
$ErrorActionPreference = "Stop"

$line = usbipd list | Select-String -Pattern '05ac:' | Select-Object -First 1   # 05ac = Apple's USB vendor ID
if (-not $line) { throw "No Apple device found. Plug in the iPhone, unlock it, and tap Trust if asked." }
$busid = ($line.ToString().Trim() -split '\s+')[0]
Write-Host "Apple device on bus $busid -> $line"

usbipd bind --busid $busid
Write-Host "Attaching to WSL (Ctrl+C to stop)..."
usbipd attach --wsl --busid $busid --auto-attach
