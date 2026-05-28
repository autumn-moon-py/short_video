param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$FlutterArgs
)

$proxyKeys = @(
  'HTTP_PROXY',
  'HTTPS_PROXY',
  'ALL_PROXY',
  'http_proxy',
  'https_proxy',
  'all_proxy'
)
$loopbackHosts = @('localhost', '127.0.0.1', '::1')

function Merge-NoProxy([string]$name) {
  $existing = [Environment]::GetEnvironmentVariable($name)
  $entries = @()

  if (-not [string]::IsNullOrWhiteSpace($existing)) {
    $entries = $existing.Split(',') |
      ForEach-Object { $_.Trim() } |
      Where-Object { $_ }
  }

  foreach ($loopbackHost in $loopbackHosts) {
    if ($entries -notcontains $loopbackHost) {
      $entries += $loopbackHost
    }
  }

  Set-Item -Path "Env:$name" -Value ($entries -join ',')
}

$hasProxy = $false
foreach ($key in $proxyKeys) {
  if (-not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($key))) {
    $hasProxy = $true
    break
  }
}

if ($hasProxy) {
  Merge-NoProxy 'NO_PROXY'
  Merge-NoProxy 'no_proxy'
}

& fvm flutter @FlutterArgs
exit $LASTEXITCODE
