param(
    [string]$RunId = "sch202602240155",
    [string]$ParentDeviceId = "13973155520008G",
    [string]$ChildDeviceId = "aae47d3e",
    [int]$OfflineSeconds = 120,
    [int]$FlakyIntervalSeconds = 15,
    [int]$FlakyCycles = 3,
    [int]$ChildWatchSeconds = 1200,
    [int]$ChildPollMs = 1000,
    [int]$ChildReadyTimeoutSeconds = 300,
    [int]$ResyncTimeoutSeconds = 180,
    [string]$SetupLogPath = "offline_setup.log",
    [string]$ParentLogPath = "offline_parent.log",
    [string]$ChildLogPath = "offline_child.log",
    [string]$ChildErrPath = "offline_child.err",
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

trap {
    Restore-NormalApps
    throw
}

function EpochMsNow {
    return [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
}

function Cleanup-Logs {
    param([string[]]$Paths)
    foreach ($path in $Paths) {
        if (Test-Path $path) {
            try { Remove-Item $path -Force } catch {}
        }
    }
}

function Parse-PairingCode {
    param([string]$Text)
    $m = [regex]::Match($Text, "pairingCode=(\d{6})")
    if ($m.Success) { return $m.Groups[1].Value }
    return ""
}

function Try-AcceptVpnDialog {
    param([string]$DeviceId)

    try {
        adb -s $DeviceId shell input keyevent 224 | Out-Null
        adb -s $DeviceId shell uiautomator dump /sdcard/uidump_offline.xml | Out-Null
        $dump = adb -s $DeviceId shell cat /sdcard/uidump_offline.xml 2>$null
        if ([string]::IsNullOrWhiteSpace($dump)) {
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
            if (-not $match.Success) {
                adb -s $DeviceId shell input keyevent 66 | Out-Null
                return $false
            }
            $x1 = [int]$match.Groups[2].Value
            $y1 = [int]$match.Groups[3].Value
            $x2 = [int]$match.Groups[4].Value
            $y2 = [int]$match.Groups[5].Value
            $x = [int](($x1 + $x2) / 2)
            $y = [int](($y1 + $y2) / 2)
            adb -s $DeviceId shell input tap $x $y | Out-Null
            return $true
        }

        $x1 = [int]$match.Groups[1].Value
        $y1 = [int]$match.Groups[2].Value
        $x2 = [int]$match.Groups[3].Value
        $y2 = [int]$match.Groups[4].Value
        $x = [int](($x1 + $x2) / 2)
        $y = [int](($y1 + $y2) / 2)
        adb -s $DeviceId shell input tap $x $y | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Run-ParentOp {
    param(
        [string]$Op,
        [string]$RunId,
        [string]$PairingCode,
        [string]$ParentDeviceId,
        [string]$ParentLogPath
    )
    $output = & flutter test integration_test/real_device_offline_resilience_test.dart `
        -d $ParentDeviceId `
        --dart-define=TB_ROLE=parent_apply `
        --dart-define=TB_RUN_ID=$RunId `
        --dart-define=TB_PAIRING_CODE=$PairingCode `
        --dart-define=TB_OP=$Op 2>&1
    $output | Tee-Object -FilePath $ParentLogPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Parent op failed: $Op"
    }
    $text = ($output | Out-String)
    $m = [regex]::Match($text, "\[OFFLINE_PARENT\]\s+op=$Op\s+savedAtMs=(\d+)")
    if (-not $m.Success) {
        throw "Could not parse savedAtMs for op $Op"
    }
    return [int64]$m.Groups[1].Value
}

function Wait-ChildReady {
    param(
        [System.Diagnostics.Process]$ChildProc,
        [string]$ChildLogPath,
        [string]$ChildStdLogPath,
        [int]$TimeoutSeconds,
        [string]$ChildDeviceId
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $ChildProc.Refresh()
        if ($ChildProc.HasExited) {
            return $false
        }
        [void](Try-AcceptVpnDialog -DeviceId $ChildDeviceId)
        $text = ""
        if (Test-Path $ChildLogPath) {
            try { $text = Get-Content $ChildLogPath -Raw } catch { $text = "" }
        }

        $stdText = ""
        if (Test-Path $ChildStdLogPath) {
            try { $stdText = Get-Content $ChildStdLogPath -Raw } catch { $stdText = "" }
        }

        if ($text -match "VPN permission missing on child device" -or
            $stdText -match "VPN permission missing on child device") {
            [void](Try-AcceptVpnDialog -DeviceId $ChildDeviceId)
            Start-Sleep -Milliseconds 500
            try { $text = Get-Content $ChildLogPath -Raw } catch { $text = "" }
            try { $stdText = Get-Content $ChildStdLogPath -Raw } catch { $stdText = "" }
            if ($text -match "VPN permission missing on child device" -or
                $stdText -match "VPN permission missing on child device") {
                throw "VPN permission missing on child device. Human action required."
            }
        }
        if ($text -match "\[OFFLINE_WATCH\]\s+ready") {
            return $true
        }
        Start-Sleep -Seconds 2
    }
    return $false
}

function Parse-WatchSamples {
    param([string]$Text)
    $matches = [regex]::Matches(
        $Text,
        '\[OFFLINE_WATCH\]\s+tsMs=(\d+)\s+running=(true|false)\s+cats=(\d+)\s+domains=(\d+)\s+insta=(true|false)\s+youtube=(true|false)'
    )
    $rows = @()
    foreach ($m in $matches) {
        $rows += [pscustomobject]@{
            TsMs = [int64]$m.Groups[1].Value
            Running = ($m.Groups[2].Value -eq "true")
            Cats = [int]$m.Groups[3].Value
            Domains = [int]$m.Groups[4].Value
            Insta = ($m.Groups[5].Value -eq "true")
            Youtube = ($m.Groups[6].Value -eq "true")
        }
    }
    return $rows
}

function Wait-ForWatchState {
    param(
        [System.Diagnostics.Process]$ChildProc,
        [string]$ChildLogPath,
        [int64]$AfterTsMs,
        [bool]$Insta,
        [bool]$Youtube,
        [int]$TimeoutSeconds
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $ChildProc.Refresh()
        if ($ChildProc.HasExited) {
            return $null
        }
        $text = ""
        if (Test-Path $ChildLogPath) {
            try { $text = Get-Content $ChildLogPath -Raw } catch { $text = "" }
        }
        $rows = Parse-WatchSamples -Text $text
        foreach ($row in $rows) {
            if ($row.TsMs -lt $AfterTsMs) { continue }
            if ($row.Insta -eq $Insta -and $row.Youtube -eq $Youtube) {
                return $row
            }
        }
        Start-Sleep -Seconds 1
    }
    return $null
}

function Check-OfflineWindowBlocked {
    param(
        [string]$ChildLogPath,
        [int64]$StartTsMs,
        [int64]$EndTsMs
    )
    $text = ""
    if (Test-Path $ChildLogPath) {
        try { $text = Get-Content $ChildLogPath -Raw } catch { $text = "" }
    }
    $rows = Parse-WatchSamples -Text $text | Where-Object {
        $_.TsMs -ge $StartTsMs -and $_.TsMs -le $EndTsMs
    }
    if ($rows.Count -eq 0) {
        return [pscustomobject]@{
            Ok = $false
            Reason = "no_samples_during_offline_window"
            Violations = 0
            Samples = 0
        }
    }

    $violations = @($rows | Where-Object { $_.Insta -ne $true })
    return [pscustomobject]@{
        Ok = ($violations.Count -eq 0)
        Reason = if ($violations.Count -eq 0) { "ok" } else { "insta_not_blocked_offline" }
        Violations = $violations.Count
        Samples = $rows.Count
    }
}

function Check-ChildErrors {
    param([string]$ChildLogPath)
    if (-not (Test-Path $ChildLogPath)) {
        return $false
    }
    $text = ""
    try { $text = Get-Content $ChildLogPath -Raw } catch { $text = "" }
    if ($text -match "Test failed" -or $text -match "\[E\]" -or $text -match "Exception") {
        return $true
    }
    return $false
}

function Toggle-Wifi {
    param(
        [string]$DeviceId,
        [bool]$Enable
    )
    if ($Enable) {
        adb -s $DeviceId shell svc wifi enable | Out-Null
    } else {
        adb -s $DeviceId shell svc wifi disable | Out-Null
    }
}

# 1) Preconditions
$devices = adb devices
$deviceText = ($devices -join "`n")
Write-Output $devices
$parentPattern = "(?m)^$([regex]::Escape($ParentDeviceId))\s+device$"
$childPattern = "(?m)^$([regex]::Escape($ChildDeviceId))\s+device$"
if ($deviceText -notmatch $parentPattern) {
    throw "Parent device not connected: $ParentDeviceId"
}
if ($deviceText -notmatch $childPattern) {
    throw "Child device not connected: $ChildDeviceId"
}

Cleanup-Logs -Paths @($SetupLogPath, $ParentLogPath, $ChildLogPath, $ChildErrPath, $ChildRealtimeLogPath)

# 2) Setup
Write-Output "STEP=setup_start runId=$RunId"
$setupOutput = & flutter test integration_test/real_device_offline_resilience_test.dart `
    -d $ParentDeviceId `
    --dart-define=TB_ROLE=setup `
    --dart-define=TB_RUN_ID=$RunId 2>&1
$setupOutput | Tee-Object -FilePath $SetupLogPath
if ($LASTEXITCODE -ne 0) {
    throw "Setup failed."
}
$setupText = ($setupOutput | Out-String)
$pairingCode = Parse-PairingCode -Text $setupText
if ([string]::IsNullOrWhiteSpace($pairingCode)) {
    throw "Could not parse pairingCode from setup output."
}
Write-Output "PAIRING_CODE=$pairingCode"

# 3) Start child watcher (auto-tap VPN consent when needed)
$childDefines = @(
    "TB_ROLE=child_watch",
    "TB_RUN_ID=$RunId",
    "TB_PAIRING_CODE=$pairingCode",
    "TB_WATCH_SECONDS=$ChildWatchSeconds",
    "TB_POLL_MS=$ChildPollMs"
) -join ","
$childTimeoutMinutes = [Math]::Ceiling($ChildWatchSeconds / 60.0) + 10
$childArgList = @(
    "-ExecutionPolicy", "Bypass",
    "-File", "tools/auto_accept_vpn_and_run.ps1",
    "-DeviceId", $ChildDeviceId,
    "-TestFile", "integration_test/real_device_offline_resilience_test.dart",
    "-DartDefines", $childDefines,
    "-TimeoutMinutes", $childTimeoutMinutes.ToString()
)
$childProc = Start-Process `
    -FilePath "powershell" `
    -ArgumentList $childArgList `
    -RedirectStandardOutput $ChildLogPath `
    -RedirectStandardError $ChildErrPath `
    -PassThru
Write-Output "CHILD_PID=$($childProc.Id)"

$ready = Wait-ChildReady `
    -ChildProc $childProc `
    -ChildLogPath $ChildRealtimeLogPath `
    -ChildStdLogPath $ChildLogPath `
    -TimeoutSeconds $ChildReadyTimeoutSeconds `
    -ChildDeviceId $ChildDeviceId
if (-not $ready) {
    throw "Child watcher not ready in time."
}
Write-Output "STEP=child_ready"

# 4) Ensure blocking active before offline
$tBlockInstagramSaved = Run-ParentOp -Op "block_instagram" -RunId $RunId -PairingCode $pairingCode -ParentDeviceId $ParentDeviceId -ParentLogPath $ParentLogPath
Write-Output "PARENT_OP=block_instagram savedAtMs=$tBlockInstagramSaved"
$blockedRow = Wait-ForWatchState `
    -ChildProc $childProc `
    -ChildLogPath $ChildLogPath `
    -AfterTsMs $tBlockInstagramSaved `
    -Insta $true `
    -Youtube $false `
    -TimeoutSeconds 120
if ($null -eq $blockedRow) {
    Write-Output "OFFLINE_PRECHECK failed=insta_not_blocked_before_offline"
} else {
    Write-Output "OFFLINE_PRECHECK ok=true tsMs=$($blockedRow.TsMs)"
}

# 5) Offline window: Wi-Fi off for 2 minutes, parent change during offline.
$offlineStartMs = EpochMsNow
Toggle-Wifi -DeviceId $ChildDeviceId -Enable $false
Write-Output "WIFI_EVENT off tsMs=$offlineStartMs"

Start-Sleep -Seconds 20
$tBlockYoutubeSaved = Run-ParentOp -Op "block_youtube" -RunId $RunId -PairingCode $pairingCode -ParentDeviceId $ParentDeviceId -ParentLogPath $ParentLogPath
Write-Output "PARENT_OP=block_youtube savedAtMs=$tBlockYoutubeSaved (during offline)"

$remaining = $OfflineSeconds - 20
if ($remaining -gt 0) {
    Start-Sleep -Seconds $remaining
}

$offlineEndMs = EpochMsNow
Toggle-Wifi -DeviceId $ChildDeviceId -Enable $true
Write-Output "WIFI_EVENT on tsMs=$offlineEndMs"

$offlineCheck = Check-OfflineWindowBlocked -ChildLogPath $ChildLogPath -StartTsMs $offlineStartMs -EndTsMs $offlineEndMs
Write-Output "OFFLINE_BLOCK_CHECK ok=$($offlineCheck.Ok) reason=$($offlineCheck.Reason) samples=$($offlineCheck.Samples) violations=$($offlineCheck.Violations)"

# 6) Reconnect and re-sync check (expect insta=false, youtube=true)
$resyncRow = Wait-ForWatchState `
    -ChildProc $childProc `
    -ChildLogPath $ChildLogPath `
    -AfterTsMs $offlineEndMs `
    -Insta $false `
    -Youtube $true `
    -TimeoutSeconds $ResyncTimeoutSeconds

$resyncOk = $null -ne $resyncRow
$resyncLatency = if ($resyncOk) { [int64]$resyncRow.TsMs - [int64]$tBlockYoutubeSaved } else { -1 }
Write-Output "RESYNC_CHECK ok=$resyncOk latencyMs=$resyncLatency"

# 7) Flaky network cycles: off/on every 15s for 3 cycles.
$flakyOk = $true
for ($i = 1; $i -le $FlakyCycles; $i++) {
    $offTs = EpochMsNow
    Toggle-Wifi -DeviceId $ChildDeviceId -Enable $false
    Write-Output "FLAKY cycle=$i event=off tsMs=$offTs"
    Start-Sleep -Seconds $FlakyIntervalSeconds

    $onTs = EpochMsNow
    Toggle-Wifi -DeviceId $ChildDeviceId -Enable $true
    Write-Output "FLAKY cycle=$i event=on tsMs=$onTs"
    Start-Sleep -Seconds $FlakyIntervalSeconds

    $childProc.Refresh()
    if ($childProc.HasExited) {
        $flakyOk = $false
        Write-Output "FLAKY cycle=$i recovered=false reason=child_process_exited"
        break
    }
    $stateAfterCycle = Wait-ForWatchState `
        -ChildProc $childProc `
        -ChildLogPath $ChildLogPath `
        -AfterTsMs $onTs `
        -Insta $false `
        -Youtube $true `
        -TimeoutSeconds 45
    if ($null -eq $stateAfterCycle) {
        $flakyOk = $false
        Write-Output "FLAKY cycle=$i recovered=false reason=state_not_restored"
        break
    } else {
        Write-Output "FLAKY cycle=$i recovered=true tsMs=$($stateAfterCycle.TsMs)"
    }
}

$childErrors = Check-ChildErrors -ChildLogPath $ChildLogPath
Write-Output "CHILD_ERROR_SCAN hasErrors=$childErrors"

# 8) Cleanup policy
try {
    $tUnblockSaved = Run-ParentOp -Op "unblock_all" -RunId $RunId -PairingCode $pairingCode -ParentDeviceId $ParentDeviceId -ParentLogPath $ParentLogPath
    Write-Output "PARENT_OP=unblock_all savedAtMs=$tUnblockSaved"
} catch {
    Write-Output "PARENT_OP=unblock_all failed=true reason=$($_.Exception.Message)"
}

# 9) Final report
$overallOk = $offlineCheck.Ok -and $resyncOk -and $flakyOk -and (-not $childErrors)
Write-Output "OFFLINE_RESILIENCE_SUMMARY overallOk=$overallOk offlineBlockedOk=$($offlineCheck.Ok) resyncOk=$resyncOk flakyOk=$flakyOk childErrors=$childErrors resyncLatencyMs=$resyncLatency"

# 10) Stop watcher and print logs
try {
    $childProc.Refresh()
    if (-not $childProc.HasExited) {
        Stop-Process -Id $childProc.Id -Force
        Start-Sleep -Seconds 1
    }
} catch {}

Write-Output "--- CHILD LOG START ---"
if (Test-Path $ChildLogPath) { Get-Content $ChildLogPath }
Write-Output "--- CHILD LOG END ---"
Write-Output "--- CHILD ERR START ---"
if (Test-Path $ChildErrPath) { Get-Content $ChildErrPath }
Write-Output "--- CHILD ERR END ---"

if (-not $overallOk) {
    Restore-NormalApps
    exit 1
}
Restore-NormalApps
exit 0
