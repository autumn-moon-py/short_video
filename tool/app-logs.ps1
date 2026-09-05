param(
  [string]$DeviceId,
  [int]$Tail = 200,
  [int]$SinceSeconds = 0,
  [string]$Package = 'com.autumnmoon.short_video',
  [string]$OutFile
)

$ErrorActionPreference = 'Stop'

function Resolve-DeviceId {
  param([string]$Explicit)
  if ($Explicit) { return $Explicit }
  $deviceLines = @(& adb devices | Where-Object { $_ -match '\sdevice$' })
  if ($deviceLines.Count -eq 0) {
    throw 'adb 未检测到任何 device，请先连接手机并启用 USB 调试'
  }
  if ($deviceLines.Count -gt 1) {
    throw "检测到多台设备，请用 -DeviceId 指定：$($deviceLines -join '; ')"
  }
  return ($deviceLines[0] -split '\s+')[0].Trim()
}

$device = Resolve-DeviceId -Explicit $DeviceId

if ($SinceSeconds -gt 0) {
  $since = (Get-Date).AddSeconds(-1 * $SinceSeconds)
  $timeArg = $since.ToString('MM-dd HH:mm:ss.fff')
  $args = @('-s', $device, 'logcat', '-d', '-T', $timeArg, 'flutter:I', '*:S')
} else {
  $args = @('-s', $device, 'logcat', '-d', '-t', "$Tail", 'flutter:I', '*:S')
}

Write-Host "[app-logs] device=$device tail=$Tail since=${SinceSeconds}s pkg=$Package" -ForegroundColor Cyan

if ($OutFile) {
  & adb @args | Tee-Object -FilePath $OutFile | Select-Object -Last 200
  Write-Host "[app-logs] 已写入 $OutFile" -ForegroundColor Green
} else {
  & adb @args
}
