param(
    [string]$RunId = "sch202602240155",
    [string]$ParentDeviceId = "13973155520008G",
    [string]$ChildDeviceId = "aae47d3e",
    [int]$OpTimeoutSeconds = 20,
    [int]$ProbeTimeoutSeconds = 45,
    [int]$ObservePollMs = 50,
    [int]$ChildTimeoutMinutes = 30,
    [int]$ChildReadyTimeoutMinutes = 10,
    [ValidateSet("auto", "direct")]
    [string]$ChildLaunchMode = "auto",
    [string]$SetupLogPath = "stress_setup.log",
    [string]$DriveLogPath = "stress_drive.log",
    [string]$ChildLogPath = "stress_child.log",
    [string]$ChildErrPath = "stress_child.err",
    [string]$RealtimeLogPath = "tmp_vpn_start_blocking.log",
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

Write-Output "RUN_ID=$RunId"

# Clean stale child-side flutter runs for this test file.
$stale = Get-CimInstance Win32_Process | Where-Object {
    ($_.Name -eq "dart.exe" -or $_.Name -eq "dartvm.exe" -or $_.Name -eq "flutter.bat" -or $_.Name -eq "cmd.exe") -and
    $_.CommandLine -like "*real_device_policy_sync_stress_test.dart*"
}
foreach ($p in $stale) {
    try {
        Stop-Process -Id $p.ProcessId -Force
    } catch {
    }
}

foreach ($path in @($SetupLogPath, $DriveLogPath, $ChildLogPath, $ChildErrPath)) {
    if (Test-Path $path) {
        try {
            Remove-Item $path -Force
        } catch {
        }
    }
}

$initialRealtimeLines = 0
if (Test-Path $RealtimeLogPath) {
    try {
        $initialRealtimeLines = (Get-Content $RealtimeLogPath).Count
    } catch {
        $initialRealtimeLines = 0
    }
}

Write-Output "STEP=setup_start"
$setupOutput = & flutter test integration_test/real_device_policy_sync_stress_test.dart `
    -d $ParentDeviceId `
    --dart-define=TB_ROLE=setup `
    --dart-define=TB_RUN_ID=$RunId 2>&1
$setupOutput | Tee-Object -FilePath $SetupLogPath
$setupExit = $LASTEXITCODE
Write-Output "SETUP_EXIT=$setupExit"
if ($setupExit -ne 0) {
    Restore-NormalApps
    exit $setupExit
}

$setupText = ($setupOutput | Out-String)
$pairMatch = [regex]::Match($setupText, "pairingCode=(\d{6})")
if (-not $pairMatch.Success) {
    Write-Output "ERROR=pairing_code_not_found_in_setup_output"
    Restore-NormalApps
    exit 3
}
$pairingCode = $pairMatch.Groups[1].Value
Write-Output "PAIRING_CODE=$pairingCode"

Write-Output "STEP=child_start"
$childReadyLogPath = $ChildLogPath
if ($ChildLaunchMode -eq "direct") {
    if (Test-Path $RealtimeLogPath) {
        try { Remove-Item $RealtimeLogPath -Force } catch {}
    }
    $childCmd = @(
        "flutter test integration_test/real_device_policy_sync_stress_test.dart",
        "-d $ChildDeviceId",
        "--dart-define=TB_ROLE=observe",
        "--dart-define=TB_RUN_ID=$RunId",
        "--dart-define=TB_PAIRING_CODE=$pairingCode",
        "--dart-define=TB_OP_TIMEOUT_SECONDS=$OpTimeoutSeconds",
        "--dart-define=TB_PROBE_TIMEOUT_SECONDS=$ProbeTimeoutSeconds",
        "--dart-define=TB_OBSERVE_POLL_MS=$ObservePollMs"
    ) -join " "
    $childProc = Start-Process `
        -FilePath "cmd.exe" `
        -ArgumentList "/c", $childCmd `
        -RedirectStandardOutput $ChildLogPath `
        -RedirectStandardError $ChildErrPath `
        -PassThru
} else {
    $childDefines = @(
        "TB_ROLE=observe",
        "TB_RUN_ID=$RunId",
        "TB_PAIRING_CODE=$pairingCode",
        "TB_OP_TIMEOUT_SECONDS=$OpTimeoutSeconds",
        "TB_PROBE_TIMEOUT_SECONDS=$ProbeTimeoutSeconds",
        "TB_OBSERVE_POLL_MS=$ObservePollMs"
    ) -join ","
    $childArgList = @(
        "-ExecutionPolicy", "Bypass",
        "-File", "tools/auto_accept_vpn_and_run.ps1",
        "-DeviceId", $ChildDeviceId,
        "-TestFile", "integration_test/real_device_policy_sync_stress_test.dart",
        "-DartDefines", $childDefines,
        "-TimeoutMinutes", $ChildTimeoutMinutes.ToString()
    )
    $childProc = Start-Process `
        -FilePath "powershell" `
        -ArgumentList $childArgList `
        -RedirectStandardOutput $ChildLogPath `
        -RedirectStandardError $ChildErrPath `
        -PassThru
    $childReadyLogPath = $RealtimeLogPath
}
Write-Output "CHILD_PID=$($childProc.Id)"

Write-Output "STEP=child_ready_wait"
$readyDeadline = (Get-Date).AddMinutes($ChildReadyTimeoutMinutes)
$childReady = $false
while ((Get-Date) -lt $readyDeadline) {
    $childProc.Refresh()
    if ($childProc.HasExited) {
        break
    }

    $logText = ""
    if (Test-Path $childReadyLogPath) {
        try {
            $lines = Get-Content $childReadyLogPath
            if ($ChildLaunchMode -ne "direct" -and $initialRealtimeLines -gt 0 -and $lines.Count -ge $initialRealtimeLines) {
                $logText = ($lines | Select-Object -Skip $initialRealtimeLines) -join "`n"
            } else {
                $logText = $lines -join "`n"
            }
        } catch {
            $logText = ""
        }
    }

    if ($logText -match "\[SYNC_STRESS_OBSERVE\] ready") {
        $childReady = $true
        break
    }
    if ($logText -match "Some tests failed\." -or $logText -match "\[E\]") {
        break
    }

    Start-Sleep -Seconds 5
}
Write-Output "CHILD_READY=$childReady"

$driveExit = 2
if ($childReady) {
    Write-Output "STEP=drive_start"
    $driveOutput = & flutter test integration_test/real_device_policy_sync_stress_test.dart `
        -d $ParentDeviceId `
        --dart-define=TB_ROLE=drive `
        --dart-define=TB_RUN_ID=$RunId `
        --dart-define=TB_PAIRING_CODE=$pairingCode 2>&1
    $driveOutput | Tee-Object -FilePath $DriveLogPath
    $driveExit = $LASTEXITCODE
    Write-Output "DRIVE_EXIT=$driveExit"
} else {
    Write-Output "DRIVE_EXIT=$driveExit"
}

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

# Parse timing report from parent and child logs.
$parentSaved = @{}
$childEnforced = @{}
$childStatus = @{}
$lost = @()

if (Test-Path $DriveLogPath) {
    $driveText = Get-Content $DriveLogPath -Raw
    $driveMatches = [regex]::Matches(
        $driveText,
        '\[SYNC_STRESS_DRIVE\]\s+seq=(\d+).*?savedAtMs=(\d+)'
    )
    foreach ($m in $driveMatches) {
        $seq = [int]$m.Groups[1].Value
        $saved = [int64]$m.Groups[2].Value
        $parentSaved[$seq] = $saved
    }
}

if (Test-Path $ChildLogPath) {
    $childText = Get-Content $ChildLogPath -Raw
    $enforcedMatches = [regex]::Matches(
        $childText,
        '\[SYNC_STRESS_OBSERVE_RESULT\]\s+seq=(\d+).*?status=enforced\s+enforcedAtMs=(\d+)'
    )
    foreach ($m in $enforcedMatches) {
        $seq = [int]$m.Groups[1].Value
        $enforcedAt = [int64]$m.Groups[2].Value
        $childEnforced[$seq] = $enforcedAt
        $childStatus[$seq] = "enforced"
    }

    $lostMatches = [regex]::Matches(
        $childText,
        '\[SYNC_STRESS_OBSERVE_RESULT\]\s+seq=(\d+).*?status=lost'
    )
    foreach ($m in $lostMatches) {
        $seq = [int]$m.Groups[1].Value
        if (-not $childStatus.ContainsKey($seq)) {
            $childStatus[$seq] = "lost"
        }
    }
}

$latencies = @()
for ($seq = 1; $seq -le 10; $seq++) {
    $hasSaved = $parentSaved.ContainsKey($seq)
    $hasEnforced = $childEnforced.ContainsKey($seq)
    if ($hasSaved -and $hasEnforced) {
        $latency = [int64]$childEnforced[$seq] - [int64]$parentSaved[$seq]
        $latencies += $latency
        Write-Output "SYNC_LATENCY seq=$seq latencyMs=$latency"
    } else {
        $status = if ($childStatus.ContainsKey($seq)) { $childStatus[$seq] } else { "missing" }
        $lost += $seq
        Write-Output "SYNC_LATENCY seq=$seq latencyMs=NA status=$status"
    }
}

if ($latencies.Count -gt 0) {
    $fastest = ($latencies | Measure-Object -Minimum).Minimum
    $slowest = ($latencies | Measure-Object -Maximum).Maximum
    $average = [int][Math]::Round(($latencies | Measure-Object -Average).Average)
} else {
    $fastest = "NA"
    $slowest = "NA"
    $average = "NA"
}
Write-Output "SYNC_METRICS fastestMs=$fastest slowestMs=$slowest averageMs=$average"
Write-Output "SYNC_LOST seqs=$($lost -join ',')"
Write-Output "SYNC_DEBUG parentSavedCount=$($parentSaved.Count) childEnforcedCount=$($childEnforced.Count)"

$parentFinal = "unknown"
$childFinal = "unknown"
if (Test-Path $DriveLogPath) {
    $driveText = Get-Content $DriveLogPath -Raw
    $parentFinalMatch = [regex]::Match(
        $driveText,
        '\[SYNC_STRESS_DRIVE_FINAL\].*?finalStateOk=([a-zA-Z]+)'
    )
    if ($parentFinalMatch.Success) {
        $parentFinal = $parentFinalMatch.Groups[1].Value.ToLowerInvariant()
    }
}
if (Test-Path $ChildLogPath) {
    $childText = Get-Content $ChildLogPath -Raw
    $childFinalMatch = [regex]::Match(
        $childText,
        '\[SYNC_STRESS_OBSERVE_FINAL\].*?finalStateOk=([a-zA-Z]+)'
    )
    if ($childFinalMatch.Success) {
        $childFinal = $childFinalMatch.Groups[1].Value.ToLowerInvariant()
    }
}
Write-Output "SYNC_FINAL parentFinalStateOk=$parentFinal childFinalStateOk=$childFinal"

if ($driveExit -ne 0) {
    Restore-NormalApps
    exit $driveExit
}
Restore-NormalApps
exit $childExit
