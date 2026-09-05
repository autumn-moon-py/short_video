param(
  [switch]$ServerOnly,
  [switch]$ClientOnly
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

# 注意：不用 fvm（本机 fvm 的 stable 解析到 Flutter 3.24.0/Dart 3.5.0，不满足项目
# pubspec 要求 ^3.11.1）。直接使用 PATH 上的 flutter（3.41.6/Dart 3.11.4）。
$flutter = Get-Command flutter -ErrorAction Stop

if (-not $ServerOnly) {
  Write-Host "[app-analyze] client: flutter analyze" -ForegroundColor Cyan
  & $flutter.Source analyze
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

if (-not $ClientOnly) {
  Write-Host "[app-analyze] server: dart analyze" -ForegroundColor Cyan
  & dart analyze $root\server
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

Write-Host "[app-analyze] OK" -ForegroundColor Green
