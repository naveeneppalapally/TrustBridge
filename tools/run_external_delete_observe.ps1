param(
    [string]$ParentDeviceId = "13973155520008G",
    [string]$ChildDeviceId = "aae47d3e",
    [string]$ParentEmail = "tb.schedule.stress20260224z@trustbridge.local",
    [string]$ParentPassword = "Tb!stress20Aa1",
    [string]$ChildId = "a74db3d2-fbb7-44c5-b862-06ed74e5bc4e",
    [string]$PairingCode = "",
    [int]$ReadyTimeoutMinutes = 8,
    [int]$ChildExitTimeoutMinutes = 5,
    [switch]$RestoreAppsAfterRun = $true
)

$ErrorActionPreference = "Stop"
$childLog = "child_external_delete.log"
$parentLog = "parent_delete_action.log"
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

function Invoke-ChildDialogTap {
    param([string]$DeviceId)

    adb -s $DeviceId shell input keyevent 224 | Out-Null
    adb -s $DeviceId shell uiautomator dump /sdcard/uidump_ext.xml | Out-Null
    $dump = adb -s $DeviceId shell cat /sdcard/uidump_ext.xml 2>$null
    if (-not $dump) {
        adb -s $DeviceId shell input keyevent 66 | Out-Null
        return $false
    }

    $match = [regex]::Match(
        $dump,
        'resource-id="android:id/button1"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"'
    )
    if (-not $match.Success) {
        $match = [regex]::Match(
            $dump,
            'text="(OK|Ok|ALLOW|Allow|Always|Continue|Yes)"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"'
        )
        if ($match.Success) {
            $x1 = [int]$match.Groups[2].Value
            $y1 = [int]$match.Groups[3].Value
            $x2 = [int]$match.Groups[4].Value
            $y2 = [int]$match.Groups[5].Value
            $x = [int](($x1 + $x2) / 2)
            $y = [int](($y1 + $y2) / 2)
            adb -s $DeviceId shell input tap $x $y | Out-Null
            return $true
        }
    } else {
        $x1 = [int]$match.Groups[1].Value
        $y1 = [int]$match.Groups[2].Value
        $x2 = [int]$match.Groups[3].Value
        $y2 = [int]$match.Groups[4].Value
        $x = [int](($x1 + $x2) / 2)
        $y = [int](($y1 + $y2) / 2)
        adb -s $DeviceId shell input tap $x $y | Out-Null
        return $true
    }

    adb -s $DeviceId shell input keyevent 66 | Out-Null
    return $false
}

if (Test-Path $childLog) {
    Remove-Item $childLog -Force
}
if (Test-Path $parentLog) {
    Remove-Item $parentLog -Force
}

$childArgs = @(
    "test",
    "integration_test/real_device_child_external_delete_observe_test.dart",
    "-d", $ChildDeviceId,
    "--dart-define=TB_PARENT_EMAIL=$ParentEmail",
    "--dart-define=TB_PARENT_PASSWORD=$ParentPassword",
    "--dart-define=TB_PAIRING_CODE=$PairingCode",
    "--dart-define=TB_BLOCKED_DOMAIN=instagram.com",
    "--dart-define=TB_WAIT_FOR_DELETE_SECONDS=180"
)
$childCmd = "flutter " + ($childArgs -join " ")
$childCmdWithRedirect = "$childCmd > `"$childLog`" 2>&1"
Write-Output "CHILD_CMD=$childCmdWithRedirect"
$childProc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $childCmdWithRedirect -PassThru

$ready = $false
$tapCount = 0
$readyDeadline = (Get-Date).AddMinutes($ReadyTimeoutMinutes)
while ((Get-Date) -lt $readyDeadline -and -not $childProc.HasExited) {
    if (Invoke-ChildDialogTap -DeviceId $ChildDeviceId) {
        $tapCount++
    }
    if (Test-Path $childLog) {
        $logText = Get-Content $childLog -Raw
        if ($logText -match '\[EXTERNAL_DELETE_OBSERVE\] ready') {
            $ready = $true
            break
        }
    }
    Start-Sleep -Milliseconds 900
}
Write-Output "AUTOMATION_TAPS=$tapCount"

if (-not $ready) {
    Write-Output "READY_MARKER_NOT_FOUND"
    if (Test-Path $childLog) {
        Get-Content $childLog
    }
    if (-not $childProc.HasExited) {
        try {
            $childProc.Kill()
        } catch {
        }
    }
    Restore-NormalApps
    exit 1
}
Write-Output "READY_MARKER_FOUND=1"

$parentArgs = @(
    "test",
    "integration_test/real_device_notification_probe_test.dart",
    "-d", $ParentDeviceId,
    "--dart-define=TB_ROLE=parent_delete_child",
    "--dart-define=TB_PARENT_EMAIL=$ParentEmail",
    "--dart-define=TB_PARENT_PASSWORD=$ParentPassword",
    "--dart-define=TB_CHILD_ID=$ChildId"
)
$parentCmd = "flutter " + ($parentArgs -join " ")
$parentCmdWithRedirect = "$parentCmd > `"$parentLog`" 2>&1"
Write-Output "PARENT_CMD=$parentCmdWithRedirect"
$deleteStart = Get-Date
$parentProc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $parentCmdWithRedirect -PassThru

$parentDeleteLineSeenAt = $null
$childVpnStoppedLineSeenAt = $null
$childResultLineSeenAt = $null

$childExitDeadline = (Get-Date).AddMinutes($ChildExitTimeoutMinutes)
while ((Get-Date) -lt $childExitDeadline) {
    if ((Test-Path $parentLog) -and $null -eq $parentDeleteLineSeenAt) {
        $parentText = Get-Content $parentLog -Raw
        if ($parentText -match '\[NOTIF_PROBE\] child deleted') {
            $parentDeleteLineSeenAt = Get-Date
        }
    }
    if ((Test-Path $childLog) -and $null -eq $childVpnStoppedLineSeenAt) {
        $childTextNow = Get-Content $childLog -Raw
        if ($childTextNow -match 'VPN stopped successfully') {
            $childVpnStoppedLineSeenAt = Get-Date
        }
    }
    if ((Test-Path $childLog) -and $null -eq $childResultLineSeenAt) {
        $childTextNow = Get-Content $childLog -Raw
        if ($childTextNow -match '\[EXTERNAL_DELETE_OBSERVE\] deleteDetectedMs=') {
            $childResultLineSeenAt = Get-Date
        }
    }

    if ($childProc.HasExited -and $parentProc.HasExited) {
        break
    }
    Start-Sleep -Milliseconds 800
}

if (-not $parentProc.HasExited) {
    try {
        $parentProc.Kill()
    } catch {
    }
}
if (-not $childProc.HasExited) {
    Write-Output "CHILD_TIMEOUT_KILL=1"
    try {
        $childProc.Kill()
    } catch {
    }
}

$parentExit = if ($parentProc.HasExited) { $parentProc.ExitCode } else { 124 }
Write-Output "PARENT_EXIT=$parentExit"

if (-not $childProc.HasExited) {
    try { $childProc.WaitForExit(2000) } catch {}
}
$childExit = if ($childProc.HasExited) { $childProc.ExitCode } else { 124 }
Write-Output "CHILD_EXIT=$childExit"
Write-Output "DELETE_TO_END_SEC=$([math]::Round(((Get-Date) - $deleteStart).TotalSeconds, 1))"
if ($parentDeleteLineSeenAt -ne $null) {
    Write-Output "PARENT_DELETE_LOG_SEEN_AT=$($parentDeleteLineSeenAt.ToString('o'))"
}
if ($childVpnStoppedLineSeenAt -ne $null) {
    Write-Output "CHILD_VPN_STOP_LOG_SEEN_AT=$($childVpnStoppedLineSeenAt.ToString('o'))"
}
if ($childResultLineSeenAt -ne $null) {
    Write-Output "CHILD_RESULT_LOG_SEEN_AT=$($childResultLineSeenAt.ToString('o'))"
}
if ($parentDeleteLineSeenAt -ne $null -and $childVpnStoppedLineSeenAt -ne $null) {
    $delta = ($childVpnStoppedLineSeenAt - $parentDeleteLineSeenAt).TotalSeconds
    Write-Output ("PARENT_DELETE_TO_CHILD_VPN_STOP_SEC={0:N1}" -f $delta)
}

Write-Output "--- PARENT LOG ---"
if (Test-Path $parentLog) {
    Get-Content $parentLog
}
Write-Output "--- CHILD LOG ---"
if (Test-Path $childLog) {
    Get-Content $childLog
}

if (Test-Path $childLog) {
    $childText = Get-Content $childLog -Raw
    $m = [regex]::Match(
        $childText,
        '\[EXTERNAL_DELETE_OBSERVE\] deleteDetectedMs=(\d+) vpnStopped=(\w+) localPairingCleared=(\w+) unpairedUi=(\w+)'
    )
    if ($m.Success) {
        Write-Output "RESULT_DELETE_DETECTED_MS=$($m.Groups[1].Value)"
        Write-Output "RESULT_VPN_STOPPED=$($m.Groups[2].Value)"
        Write-Output "RESULT_LOCAL_PAIRING_CLEARED=$($m.Groups[3].Value)"
        Write-Output "RESULT_UNPAIRED_UI=$($m.Groups[4].Value)"
    }
}

if ($parentExit -ne 0 -or $childExit -ne 0) {
    Restore-NormalApps
    exit 1
}
Restore-NormalApps
