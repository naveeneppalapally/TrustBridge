param(
  [Parameter(Mandatory = $true)][string]$RunId,
  [Parameter(Mandatory = $true)][string]$ParentDevice,
  [Parameter(Mandatory = $true)][string]$ChildDevice,
  [Parameter(Mandatory = $true)][string]$ParentEmail,
  [Parameter(Mandatory = $true)][string]$ParentPassword,
  [Parameter(Mandatory = $true)][string]$PairingCode,
  [int]$WatchSeconds = 160
)

$ErrorActionPreference = 'Stop'

function Start-LoggedProcess {
  param(
    [Parameter(Mandatory = $true)][string]$Command,
    [Parameter(Mandatory = $true)][string]$StdOutPath,
    [Parameter(Mandatory = $true)][string]$StdErrPath,
    [string]$WorkingDirectory = (Get-Location).Path
  )

  Remove-Item $StdOutPath, $StdErrPath -Force -ErrorAction SilentlyContinue
  $wrapped = "Set-Location '$WorkingDirectory'; $Command"
  return Start-Process `
    -FilePath powershell `
    -ArgumentList '-NoProfile', '-Command', $wrapped `
    -PassThru `
    -WindowStyle Hidden `
    -RedirectStandardOutput $StdOutPath `
    -RedirectStandardError $StdErrPath
}

function Wait-ForTextInFile {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Pattern,
    [int]$TimeoutSeconds = 240
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    if (Test-Path $Path) {
      $text = Get-Content $Path -Raw -ErrorAction SilentlyContinue
      if ($text -match $Pattern) {
        return $true
      }
    }
    Start-Sleep -Seconds 2
  }
  return $false
}

function Get-FileText {
  param([string]$Path)
  if (!(Test-Path $Path)) { return '' }
  return (Get-Content $Path -Raw -ErrorAction SilentlyContinue)
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$logDir = Join-Path $repoRoot 'docs\hardware_tmp'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$parentOut = Join-Path $logDir "parent_dashboard_watch_$RunId.log"
$parentErr = Join-Path $logDir "parent_dashboard_watch_$RunId.err.log"
$childOut = Join-Path $logDir "child_signin_pair_watch_$RunId.log"
$childErr = Join-Path $logDir "child_signin_pair_watch_$RunId.err.log"

$parentCmd = @(
  'flutter test integration_test/two_device_authenticated_acceptance_test.dart'
  "-d $ParentDevice"
  '--dart-define=TB_ROLE=parent_dashboard_watch'
  "--dart-define=TB_RUN_ID=$RunId"
  '--dart-define=TB_USE_EMULATORS=false'
  "--dart-define=TB_WATCH_SECONDS=$WatchSeconds"
) -join ' '

$childCmd = @(
  'flutter test integration_test/real_device_vpn_smoke_test.dart'
  "-d $ChildDevice"
  '--dart-define=TB_ROLE=sign_in_pair_start_watch'
  "--dart-define=TB_PARENT_EMAIL=$ParentEmail"
  "--dart-define=TB_PARENT_PASSWORD=$ParentPassword"
  "--dart-define=TB_PAIRING_CODE=$PairingCode"
  '--dart-define=TB_BLOCKED_DOMAIN=reddit.com'
  "--dart-define=TB_WATCH_SECONDS=$WatchSeconds"
) -join ' '

Write-Output "RUN_ID=$RunId"
Write-Output "PARENT_DEVICE=$ParentDevice"
Write-Output "CHILD_DEVICE=$ChildDevice"
Write-Output "PARENT_LOG=$parentOut"
Write-Output "CHILD_LOG=$childOut"
Write-Output 'NOTE: If VPN permission prompt appears on child, tap Allow.'

$parentProc = $null
$childProc = Start-LoggedProcess -Command $childCmd -StdOutPath $childOut -StdErrPath $childErr -WorkingDirectory $repoRoot
Write-Output "CHILD_PID=$($childProc.Id)"

$vpnStarted = Wait-ForTextInFile -Path $childOut -Pattern 'startVpn returned=true' -TimeoutSeconds 240
$childText = Get-FileText -Path $childOut
if (!$vpnStarted -and ($childText -match 'VPN permission not granted')) {
  Write-Output 'VPN_STARTED=false (permission not granted)'
} elseif (!$vpnStarted -and ($childText -match 'Pairing failed')) {
  Write-Output 'VPN_STARTED=false (pairing failed)'
} else {
  Write-Output "VPN_STARTED=$vpnStarted"
}

if ($vpnStarted) {
  $parentProc = Start-LoggedProcess -Command $parentCmd -StdOutPath $parentOut -StdErrPath $parentErr -WorkingDirectory $repoRoot
  Write-Output "PARENT_PID=$($parentProc.Id)"
  # Give the parent watcher enough time to install and begin printing values.
  $null = Wait-ForTextInFile -Path $parentOut -Pattern '\[E2E dashboard_watch\]' -TimeoutSeconds 240

  $urls = @(
    'https://www.reddit.com',
    'https://www.reddit.com/r/all',
    'https://m.reddit.com',
    'https://old.reddit.com',
    'https://www.reddit.com/r/popular',
    'https://www.example.com'
  )
  foreach ($url in $urls) {
    Write-Output "OPEN_URL=$url"
    & adb -s $ChildDevice shell am start -W -a android.intent.action.VIEW -d $url com.android.chrome | Out-Null
    Start-Sleep -Seconds 5
  }

  for ($i = 0; $i -lt 4; $i++) {
    $url = "https://www.reddit.com?tb=$i"
    Write-Output "OPEN_URL=$url"
    & adb -s $ChildDevice shell am start -W -a android.intent.action.VIEW -d $url com.android.chrome | Out-Null
    Start-Sleep -Seconds 3
  }
}

if ($parentProc -ne $null) {
  $parentExited = $parentProc.WaitForExit(480000)
  if ($parentExited) {
    Write-Output "PARENT_EXIT=$($parentProc.ExitCode)"
  } else {
    Write-Output "PARENT_EXIT=timeout_running"
  }
} else {
  Write-Output 'PARENT_EXIT=not_started'
}

$childExited = $childProc.WaitForExit(480000)
if ($childExited) {
  Write-Output "CHILD_EXIT=$($childProc.ExitCode)"
} else {
  Write-Output "CHILD_EXIT=timeout_running"
}

$parentLogText = Get-FileText -Path $parentOut
$dashboardMatches = [regex]::Matches(
  $parentLogText,
  'blockedAttempts=([0-9?]+)\s+screenTime=([^\r\n]+)'
)
if ($dashboardMatches.Count -gt 0) {
  $values = @()
  foreach ($m in $dashboardMatches) {
    $raw = $m.Groups[1].Value
    if ($raw -match '^\d+$') {
      $values += [int]$raw
    }
  }
  if ($values.Count -gt 0) {
    Write-Output "DASHBOARD_BLOCKED_ATTEMPTS_FIRST=$($values[0])"
    Write-Output "DASHBOARD_BLOCKED_ATTEMPTS_MAX=$(([Linq.Enumerable]::Max([int[]]$values)))"
    Write-Output "DASHBOARD_BLOCKED_ATTEMPTS_LAST=$($values[$values.Count-1])"
  } else {
    Write-Output 'DASHBOARD_BLOCKED_ATTEMPTS_VALUES=none'
  }
} else {
  Write-Output 'DASHBOARD_LOG_PARSE=no_matches'
}

Write-Output '--- PARENT DASHBOARD TAIL ---'
Get-Content $parentOut -Tail 80 -ErrorAction SilentlyContinue
Write-Output '--- CHILD WATCH TAIL ---'
Get-Content $childOut -Tail 120 -ErrorAction SilentlyContinue

$parentErrText = Get-FileText -Path $parentErr
if ($parentErrText.Trim()) {
  Write-Output '--- PARENT STDERR ---'
  Write-Output $parentErrText
}
$childErrText = Get-FileText -Path $childErr
if ($childErrText.Trim()) {
  Write-Output '--- CHILD STDERR ---'
  Write-Output $childErrText
}
