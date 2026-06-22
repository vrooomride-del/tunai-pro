# TUNAI Pro Windows Installer Builder
# Run from the tunai_pro project root on a Windows machine:
#   PowerShell -ExecutionPolicy Bypass -File installer\build_installer.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=== TUNAI Pro Windows Installer Build ===" -ForegroundColor Cyan

# 1. Flutter build
Write-Host "[1/3] Flutter build windows --release..." -ForegroundColor Yellow
flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw "flutter build failed" }

# 2. Create output dir
$outputDir = "installer\output"
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

# 3. Inno Setup compile
Write-Host "[2/3] Running Inno Setup..." -ForegroundColor Yellow
$iscc = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
if (-not (Test-Path $iscc)) {
    Write-Host "Inno Setup not found. Install with: choco install innosetup" -ForegroundColor Red
    exit 1
}
& $iscc "installer\tunai_pro.iss"
if ($LASTEXITCODE -ne 0) { throw "Inno Setup compile failed" }

# 4. Done
$installer = "installer\output\TUNAIPro_Setup.exe"
if (Test-Path $installer) {
    $size = [math]::Round((Get-Item $installer).Length / 1MB, 1)
    Write-Host "[3/3] Done! Installer: $installer ($size MB)" -ForegroundColor Green
    Write-Host "Boot Camp 테스트: USB에 복사 후 Windows에서 더블클릭 설치" -ForegroundColor Cyan
} else {
    throw "Installer not found after build"
}
