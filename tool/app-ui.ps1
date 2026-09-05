param(
  [string]$DeviceId,
  [string]$Action,           # swipe | tap | screenshot | info
  [int]$X1, [int]$Y1,        # swipe 起点 / tap 坐标
  [int]$X2, [int]$Y2,        # swipe 终点
  [int]$DurationMs = 200,
  [int]$Times = 1,
  [int]$DelayMs = 400,
  [string]$OutFile           # screenshot 落盘路径
)

$ErrorActionPreference = 'Stop'

function Resolve-DeviceId {
  param([string]$Explicit)
  if ($Explicit) { return $Explicit }
  $deviceLines = @(& adb devices | Where-Object { $_ -match '\sdevice$' })
  if ($deviceLines.Count -eq 0) { throw 'adb 未检测到任何 device' }
  if ($deviceLines.Count -gt 1) { throw "检测到多台设备，请用 -DeviceId 指定" }
  return ($deviceLines[0] -split '\s+')[0].Trim()
}

$device = Resolve-DeviceId -Explicit $DeviceId

switch ($Action) {
  'info' {
    Write-Host "--- device=$device 分辨率 ---"
    & adb -s $device shell wm size
    Write-Host "--- 前台 app ---"
    & adb -s $device shell dumpsys window | Select-String 'mCurrentFocus'
  }
  'swipe' {
    if (-not $X1 -or -not $Y1 -or -not $X2 -or -not $Y2) {
      throw 'swipe 需要 -X1 -Y1 -X2 -Y2（及可选 -DurationMs）'
    }
    Write-Host "[app-ui] swipe ($X1,$Y1)->($X2,$Y2) x$Times dur=${DurationMs}ms" -ForegroundColor Cyan
    for ($i = 0; $i -lt $Times; $i++) {
      & adb -s $device shell input swipe $X1 $Y1 $X2 $Y2 $DurationMs
      if ($i -lt ($Times - 1)) { Start-Sleep -Milliseconds $DelayMs }
    }
    Write-Host '[app-ui] swipe done' -ForegroundColor Green
  }
  'tap' {
    if (-not $X1 -or -not $Y1) { throw 'tap 需要 -X1 -Y1' }
    Write-Host "[app-ui] tap ($X1,$Y1)" -ForegroundColor Cyan
    for ($i = 0; $i -lt $Times; $i++) {
      & adb -s $device shell input tap $X1 $Y1
      if ($i -lt ($Times - 1)) { Start-Sleep -Milliseconds $DelayMs }
    }
    Write-Host '[app-ui] tap done' -ForegroundColor Green
  }
  'screenshot' {
    if (-not $OutFile) { $OutFile = Join-Path $PWD 'screenshot.png' }
    Write-Host "[app-ui] screenshot -> $OutFile" -ForegroundColor Cyan
    $tmp = '/sdcard/_ui_shot.png'
    & adb -s $device shell screencap -p $tmp
    & adb -s $device pull $tmp $OutFile
    & adb -s $device shell rm $tmp
    Write-Host "[app-ui] screenshot saved: $OutFile" -ForegroundColor Green
  }
  default { throw "未知 Action: $Action（可选 swipe|tap|screenshot|info）" }
}
