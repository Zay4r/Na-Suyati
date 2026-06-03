# setup.ps1 — Run this once before building
# Usage: Right-click → Run with PowerShell
#        OR: powershell -ExecutionPolicy Bypass -File setup.ps1

Write-Host "=== Ultrasonic Detector Setup ===" -ForegroundColor Cyan

# 1. Patch record_linux stub
$linuxPath = "$env:LOCALAPPDATA\Pub\Cache\hosted\pub.dev\record_linux-0.6.0\lib\record_linux.dart"
if (Test-Path $linuxPath) {
    Set-Content $linuxPath "import 'package:record_platform_interface/record_platform_interface.dart';`n`nclass RecordLinux extends RecordPlatform {}"
    Write-Host "[OK] Patched record_linux stub" -ForegroundColor Green
} else {
    Write-Host "[SKIP] record_linux not cached yet — run 'flutter pub get' first, then re-run this script" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Next steps ===" -ForegroundColor Cyan
Write-Host "1. flutter pub get"
Write-Host "2. Re-run this script if record_linux was not found above"
Write-Host "3. flutter build apk --release"
Write-Host ""
Write-Host "Done!" -ForegroundColor Green
