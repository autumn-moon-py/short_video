param(
  [int]$Port = 9090
)

$ErrorActionPreference = 'Stop'

$conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
  Select-Object -First 1
if (-not $conn) {
  Write-Host "[server-stop] 端口 $Port 没有监听中的进程" -ForegroundColor Yellow
  exit 0
}

$pid = $conn.OwningProcess
Write-Host "[server-stop] 占用端口 $Port 的 PID=$pid，正在终止..." -ForegroundColor Cyan
Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 300

$still = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($still) {
  Write-Host "[server-stop] 终止失败，端口仍被占用" -ForegroundColor Red
  exit 1
}
Write-Host "[server-stop] OK" -ForegroundColor Green
