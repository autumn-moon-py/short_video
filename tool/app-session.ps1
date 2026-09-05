param(
  [string]$DeviceId,
  [int]$Swipes = 0,             # 切几条视频
  [int]$FinalPauseSeconds = 0,  # 最后一次滑动后停留秒数（模拟真实观看）
  [int]$LogSeconds = 10,        # 日志采集秒数
  [string]$LogFile = 'session_log.txt',
  [string]$ScreenshotDir
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Resolve-DeviceId {
  param([string]$Explicit)
  if ($Explicit) { return $Explicit }
  $deviceLines = @(& adb devices | Where-Object { $_ -match '\sdevice$' })
  if ($deviceLines.Count -eq 0) { throw 'adb 未检测到任何 device' }
  if ($deviceLines.Count -gt 1) { throw "检测到多台设备，请用 -DeviceId 指定" }
  return ($deviceLines[0] -split '\s+')[0].Trim()
}

$device = Resolve-DeviceId -Explicit $DeviceId

# 1) 启动 app
Write-Host "[app-session] 启动 app..." -ForegroundColor Cyan
& adb -s $device shell am force-stop com.autumnmoon.short_video
& adb -s $device shell am start -n com.autumnmoon.short_video/.MainActivity
Start-Sleep -Seconds 3

# 2) 屏幕尺寸
$sizeLine = (& adb -s $device shell wm size) | Select-String '\d+x\d+' | Select-Object -First 1
if ($sizeLine -match '(\d+)x(\d+)') {
  $w = [int]$Matches[1]; $h = [int]$Matches[2]
} else { throw '无法读取屏幕分辨率' }
Write-Host "[app-session] 分辨率 ${w}x$h，等待首屏加载..." -ForegroundColor Cyan
Start-Sleep -Seconds 2

# 3) 预滑动几次让封面/播放器真正就绪
Write-Host "[app-session] 预热滑动 x2" -ForegroundColor DarkGray
foreach ($i in 1..2) {
  $yTop = [int]($h * 0.7); $yBot = [int]($h * 0.3)
  & adb -s $device shell input swipe ($w / 2) $yTop ($w / 2) $yBot 250
  Start-Sleep -Milliseconds 800
}

# 4) 目标滑动 N 条，间隔记录
if ($Swipes -gt 0) {
  Write-Host "[app-session] 目标滑动 x$Swipes" -ForegroundColor Cyan
  $yTop = [int]($h * 0.7); $yBot = [int]($h * 0.3)
  for ($i = 1; $i -le $Swipes; $i++) {
    & adb -s $device shell input swipe ($w / 2) $yTop ($w / 2) $yBot 250
    Start-Sleep -Milliseconds 500
    Write-Host "[app-session] 已滑动 $i 条，采集 500ms 日志..." -ForegroundColor DarkGray
  }
}

# 5) 尾停：模拟在最后一页停留观看
if ($FinalPauseSeconds -gt 0) {
  Write-Host "[app-session] 尾停 ${FinalPauseSeconds}s..." -ForegroundColor Cyan
  Start-Sleep -Seconds $FinalPauseSeconds
}

# 6) 采集日志
Write-Host "[app-session] 采集 ${LogSeconds}s 日志到 $LogFile ..." -ForegroundColor Cyan
if ($LogSeconds -gt 0) {
  $since = (Get-Date).AddSeconds(-1 * $LogSeconds)
  $timeArg = $since.ToString('MM-dd HH:mm:ss.fff')
  & adb -s $device logcat -d -T $timeArg flutter:I '*:S' > $LogFile
} else {
  & adb -s $device logcat -d flutter:I '*:S' > $LogFile
}
Write-Host "[app-session] 日志条数: $((Get-Content $LogFile).Count)" -ForegroundColor Green

# 6) 截图
if ($ScreenshotDir) {
  if (-not (Test-Path $ScreenshotDir)) { New-Item -ItemType Directory -Path $ScreenshotDir | Out-Null }
  $shot = Join-Path $ScreenshotDir 'session_end.png'
  & adb -s $device shell screencap -p /sdcard/_s.png
  & adb -s $device pull /sdcard/_s.png $shot | Out-Null
  & adb -s $device shell rm /sdcard/_s.png
  Write-Host "[app-session] 截图: $shot" -ForegroundColor Green
}

Write-Host '[app-session] 完成' -ForegroundColor Green
