param(
    [string]$RunId = "stress20260224z",
    [string]$PairingCode = "737490",
    [string]$ParentDeviceId = "192.168.1.2:5555",
    [string]$ChildDeviceId = "192.168.1.3:5555",
    [int]$OpTimeoutSeconds = 12,
    [int]$ObservePollMs = 50,
    [int]$ChildReadyTimeoutMinutes = 8,
    [int]$ChildTimeoutMinutes = 12,
    [string]$ChildLogPath = "child_direct.log",
    [string]$ChildErrPath = "child_direct.err",
    [string]$DriveLogPath = "drive_direct.log"
)

$ErrorActionPreference = "Stop"

foreach ($path in @($ChildLogPath, $ChildErrPath, $DriveLogPath)) {
    if (Test-Path $path) {
        Remove-Item $path -Force
    }
}

$childCmd = @(
    "flutter test integration_test/real_device_policy_sync_stress_test.dart",
    "-d $ChildDeviceId",
    "--dart-define=TB_ROLE=observe",
    "--dart-define=TB_RUN_ID=$RunId",
    "--dart-define=TB_PAIRING_CODE=$PairingCode",
    "--dart-define=TB_OP_TIMEOUT_SECONDS=$OpTimeoutSeconds",
    "--dart-define=TB_PROBE_TIMEOUT_SECONDS=45",
    "--dart-define=TB_OBSERVE_POLL_MS=$ObservePollMs"
) -join " "

$childProc = Start-Process `
    -FilePath "cmd.exe" `
    -ArgumentList "/c", $childCmd `
    -RedirectStandardOutput $ChildLogPath `
    -RedirectStandardError $ChildErrPath `
    -PassThru
Write-Output "CHILD_PID=$($childProc.Id)"

$childReady = $false
$readyDeadline = (Get-Date).AddMinutes($ChildReadyTimeoutMinutes)
while ((Get-Date) -lt $readyDeadline) {
    $childProc.Refresh()
    if ($childProc.HasExited) {
        break
    }

    $logText = ""
    if (Test-Path $ChildLogPath) {
        $logText = Get-Content $ChildLogPath -Raw
    }

    if ($logText -match "\[SYNC_STRESS_OBSERVE\] ready runId=$([regex]::Escape($RunId))") {
        $childReady = $true
        break
    }
    if ($logText -match "Some tests failed\." -or $logText -match "\[E\]") {
        break
    }

    Start-Sleep -Seconds 3
}
Write-Output "CHILD_READY=$childReady"

$driveExit = 2
if ($childReady) {
    $driveOutput = & flutter test integration_test/real_device_policy_sync_stress_test.dart `
        -d $ParentDeviceId `
        --dart-define=TB_ROLE=drive `
        --dart-define=TB_RUN_ID=$RunId `
        --dart-define=TB_PAIRING_CODE=$PairingCode 2>&1
    $driveOutput | Tee-Object -FilePath $DriveLogPath
    $driveExit = $LASTEXITCODE
}
Write-Output "DRIVE_EXIT=$driveExit"

$waitOk = $true
try {
    Wait-Process -Id $childProc.Id -Timeout ($ChildTimeoutMinutes * 60)
} catch {
    $waitOk = $false
}
if (-not $waitOk -and -not $childProc.HasExited) {
    Stop-Process -Id $childProc.Id -Force
}
$childProc.Refresh()
$childExit = if ($childProc.HasExited) { $childProc.ExitCode } else { 124 }
Write-Output "CHILD_EXIT=$childExit"

Write-Output "--- CHILD LOG START ---"
if (Test-Path $ChildLogPath) {
    Get-Content $ChildLogPath
}
Write-Output "--- CHILD LOG END ---"

Write-Output "--- CHILD ERR START ---"
if (Test-Path $ChildErrPath) {
    Get-Content $ChildErrPath
}
Write-Output "--- CHILD ERR END ---"

exit $childExit
