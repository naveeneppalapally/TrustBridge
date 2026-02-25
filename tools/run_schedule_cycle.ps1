param(
    [string]$RunId = "sch202602240155",
    [string]$PairingCode,
    [string]$ParentDeviceId = "13973155520008G",
    [string]$ChildDeviceId = "aae47d3e",
    [int]$ChildObserveMinutes = 32,
    [int]$ChildPollSeconds = 15,
    [string]$ObserveDomain = "instagram.com",
    [int]$StartupDelaySeconds = 15,
    [int]$ChildReadyTimeoutMinutes = 12,
    [int]$ChildTimeoutMinutes = 45,
    [string]$ChildLogPath = "child_observe.log",
    [string]$ChildErrPath = "child_observe.err",
    [string]$ChildRealtimeLogPath = "tmp_vpn_start_blocking.log",
    [switch]$RestoreAppsAfterRun = $true
)

$ErrorActionPreference = "Stop"
$script:__restoreDone = $false

function Restore-NormalApps {
    if (-not $RestoreAppsAfterRun -or $script:__restoreDone) {
        return
    }
    $script:__restoreDone = $true
    try {
        Write-Output "STEP=restore_apps_start"
        & flutter build apk --debug --target lib/main.dart | Out-Null
        & adb -s $ParentDeviceId install -r -t build\app\outputs\flutter-apk\app-debug.apk | Out-Null
        & adb -s $ChildDeviceId install -r -t build\app\outputs\flutter-apk\app-debug.apk | Out-Null
        Write-Output "STEP=restore_apps_done"
    } catch {
        Write-Output "STEP=restore_apps_failed error=$($_.Exception.Message)"
    }
}

if ([string]::IsNullOrWhiteSpace($PairingCode)) {
    throw "PairingCode is required."
}

if (Test-Path $ChildLogPath) {
    try {
        Remove-Item $ChildLogPath -Force
    } catch {
    }
}
if (Test-Path $ChildErrPath) {
    try {
        Remove-Item $ChildErrPath -Force
    } catch {
    }
}
if (Test-Path $ChildRealtimeLogPath) {
    try {
        Remove-Item $ChildRealtimeLogPath -Force
    } catch {
    }
}

$initialRealtimeLines = 0
if (Test-Path $ChildRealtimeLogPath) {
    try {
        $initialRealtimeLines = (Get-Content $ChildRealtimeLogPath).Count
    } catch {
        $initialRealtimeLines = 0
    }
}

$childDefines = @(
    "TB_ROLE=observe",
    "TB_RUN_ID=$RunId",
    "TB_PAIRING_CODE=$PairingCode",
    "TB_OBSERVE_MINUTES=$ChildObserveMinutes",
    "TB_OBSERVE_POLL_SECONDS=$ChildPollSeconds",
    "TB_OBSERVE_DOMAIN=$ObserveDomain"
) -join ","

$childArgList = @(
    "-ExecutionPolicy", "Bypass",
    "-File", "tools/auto_accept_vpn_and_run.ps1",
    "-DeviceId", $ChildDeviceId,
    "-TestFile", "integration_test/real_device_schedule_cycle_test.dart",
    "-DartDefines",
    $childDefines,
    "-TimeoutMinutes", $ChildTimeoutMinutes.ToString()
)

$childProc = Start-Process `
    -FilePath "powershell" `
    -ArgumentList $childArgList `
    -RedirectStandardOutput $ChildLogPath `
    -RedirectStandardError $ChildErrPath `
    -PassThru

Write-Output "CHILD_PID=$($childProc.Id)"

Start-Sleep -Seconds $StartupDelaySeconds

Write-Output "CHILD_READY_WAIT_START=true"
$readyDeadline = (Get-Date).AddMinutes($ChildReadyTimeoutMinutes)
$childReady = $false
while ((Get-Date) -lt $readyDeadline) {
    $childProc.Refresh()
    if ($childProc.HasExited) {
        break
    }

    $logText = ""
    if (Test-Path $ChildRealtimeLogPath) {
        try {
            $logLines = Get-Content $ChildRealtimeLogPath
            if ($initialRealtimeLines -gt 0 -and $logLines.Count -ge $initialRealtimeLines) {
                $logText = ($logLines | Select-Object -Skip $initialRealtimeLines) -join "`n"
            } else {
                $logText = $logLines -join "`n"
            }
        } catch {
            $logText = ""
        }
    }

    if ($logText -match "real-device schedule cycle role runner") {
        $childReady = $true
        break
    }

    if ($logText -match "Some tests failed\." -or $logText -match "\[E\]") {
        break
    }

    Start-Sleep -Seconds 5
}

Write-Output "CHILD_READY=$childReady"
if (-not $childReady) {
    Write-Output "Skipping parent cycle because child observe did not become ready."
    $cycleExit = 2
} else {
flutter test integration_test/real_device_schedule_cycle_test.dart `
    -d $ParentDeviceId `
    --dart-define=TB_ROLE=cycle `
    --dart-define=TB_RUN_ID=$RunId `
    --dart-define=TB_PAIRING_CODE=$PairingCode `
    --dart-define=TB_FIRST_START_IN_MINUTES=3 `
    --dart-define=TB_FIRST_DURATION_MINUTES=10 `
    --dart-define=TB_SECOND_A_DURATION_MINUTES=3 `
    --dart-define=TB_GAP_MINUTES=1 `
    --dart-define=TB_SECOND_B_DURATION_MINUTES=3

    $cycleExit = $LASTEXITCODE
}
Write-Output "CYCLE_EXIT=$cycleExit"

$waitOk = $true
try {
    Wait-Process -Id $childProc.Id -Timeout ($ChildTimeoutMinutes * 60)
} catch {
    $waitOk = $false
}

if (-not $waitOk -and -not $childProc.HasExited) {
    Write-Output "CHILD_TIMEOUT=true"
    try {
        Stop-Process -Id $childProc.Id -Force
        Start-Sleep -Seconds 1
    } catch {
    }
}

$childProc.Refresh()
$childExit = if ($childProc.HasExited) { $childProc.ExitCode } else { 124 }
Write-Output "CHILD_EXIT=$childExit"

Write-Output "--- CHILD LOG START ---"
if (Test-Path $ChildLogPath) {
    Get-Content $ChildLogPath
}
Write-Output "--- CHILD LOG END ---"

if (Test-Path $ChildErrPath) {
    Write-Output "--- CHILD ERR START ---"
    Get-Content $ChildErrPath
    Write-Output "--- CHILD ERR END ---"
}

if ($cycleExit -ne 0) {
    Restore-NormalApps
    exit $cycleExit
}
Restore-NormalApps
exit $childExit
