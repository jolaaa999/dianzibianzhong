# 本地联调启动脚本（Windows PowerShell）
# 用法: .\tools\start_dev.ps1
#       .\tools\start_dev.ps1 -MockOnly
#       .\tools\start_dev.ps1 -Camera

param(
    [switch]$MockOnly,
    [switch]$Camera,
    [string]$Device = "windows"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

Write-Host "== 虚拟数字编钟 开发环境 ==" -ForegroundColor Cyan
Write-Host "项目目录: $Root"

if ($Camera) {
    Write-Host "启动 OpenCV 视觉追踪服务..." -ForegroundColor Yellow
    Start-Process python -ArgumentList "tools/vision_tracking_server.py --preview" -WorkingDirectory $Root
} else {
    Write-Host "启动 Mock 视觉追踪 (--strike-demo)..." -ForegroundColor Yellow
    Start-Process python -ArgumentList "tools/mock_vision_server.py --strike-demo" -WorkingDirectory $Root
}

Start-Sleep -Seconds 2

if (-not $MockOnly) {
    Write-Host "启动 Flutter 客户端 (-d $Device)..." -ForegroundColor Yellow
    flutter pub get
    flutter run -d $Device
} else {
    Write-Host "仅 Mock 服务已启动: ws://127.0.0.1:8765" -ForegroundColor Green
    Write-Host "可另开终端运行: flutter run -d $Device"
}
