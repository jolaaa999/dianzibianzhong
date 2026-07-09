# 恢复优化前的用户 PATH（如需回滚，在 PowerShell 中运行此脚本）
$backupFile = Join-Path $PSScriptRoot "user_path_20260709_184600.txt"
if (-not (Test-Path $backupFile)) {
  Write-Error "找不到备份文件: $backupFile"
  exit 1
}
$original = Get-Content $backupFile -Raw
[Environment]::SetEnvironmentVariable("Path", $original.Trim(), "User")
Write-Host "已恢复用户 PATH。请重新打开所有终端窗口。"
