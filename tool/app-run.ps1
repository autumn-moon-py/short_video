param(
  [string]$DeviceId,
  [string[]]$DartDefine = @(),
  [switch]$NoAttach
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Resolve-DeviceId {
  param([string]$Explicit)
  if ($Explicit) { return $Explicit }
  $deviceLines = @(& adb devices | Where-Object { $_ -match '\sdevice$' })
  if ($deviceLines.Count -eq 0) {
    throw 'adb 未检测到任何 device'
  }
  if ($deviceLines.Count -gt 1) {
    throw "检测到多台设备，请用 -DeviceId 指定"
  }
  return ($deviceLines[0] -split '\s+')[0].Trim()
}

# 注意：不用 fvm（见 app-analyze.ps1 说明）。使用 PATH 上的 flutter。
$flutter = Get-Command flutter -ErrorAction Stop

$flutterArgs = @('run')
if ($DartDefine) {
  foreach ($d in $DartDefine) { $flutterArgs += @('--dart-define', $d) }
}
if (-not $NoAttach) {
  $device = Resolve-DeviceId -Explicit $DeviceId
  $flutterArgs += @('-d', $device)
}

Write-Host "[app-run] flutter $($flutterArgs -join ' ')" -ForegroundColor Cyan
& $flutter.Source @flutterArgs
exit $LASTEXITCODE
