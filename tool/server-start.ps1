param(
  [string]$RootDir,
  [int]$Port = 9090,
  [string]$LogFile
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$serverDir = Join-Path $root 'server'

if (-not $RootDir) { $RootDir = 'E:/video/output' }

$args = @('run',
  "-DFILE_SERVER_ROOT_DIR=$RootDir",
  "-DFILE_SERVER_API_PORT=$Port",
  'bin/main.dart'
)

Push-Location $serverDir
try {
  Write-Host "[server-start] dir=$RootDir port=$Port cwd=$serverDir" -ForegroundColor Cyan

  if ($LogFile) {
    Write-Host "[server-start] 输出重定向到 $LogFile" -ForegroundColor DarkGray
    & dart @args | Tee-Object -FilePath $LogFile
  } else {
    & dart @args
  }
  exit $LASTEXITCODE
} finally {
  Pop-Location
}
