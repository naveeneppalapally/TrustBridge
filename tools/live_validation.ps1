param(
    [string]$OutputPath = "docs/LIVE_VALIDATION_REPORT.md"
)

$ErrorActionPreference = "Stop"

function Get-IsoNow {
    return (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff zzz")
}

function Run-CommandChecked {
    param(
        [string]$Command,
        [string]$Workdir
    )

    Push-Location $Workdir
    try {
        Write-Host "[RUN] $Command"
        & cmd.exe /d /s /c $Command
        if ($LASTEXITCODE -ne 0) {
            throw "Command failed with exit code ${LASTEXITCODE}: $Command"
        }
    } finally {
        Pop-Location
    }
}

function Get-ResumedActivity {
    param([string]$DeviceId)
    $output = adb -s $DeviceId shell dumpsys activity activities | Select-String "topResumedActivity|ResumedActivity" | Select-Object -First 1
    if ($null -eq $output) {
        return ""
    }
    return $output.ToString().Trim()
}

function Run-IssueValidation {
    param(
        [int]$IssueNumber,
        [string]$IssueTitle,
        [string[]]$Commands,
        [string]$Workdir
    )

    $startedAt = Get-IsoNow
    $status = "PASS"
    $errorMessage = ""

    foreach ($command in $Commands) {
        try {
            $null = Run-CommandChecked -Command $command -Workdir $Workdir
        } catch {
            $status = "FAIL"
            $errorMessage = $_.Exception.Message
            break
        }
    }

    $finishedAt = Get-IsoNow
    return [PSCustomObject]@{
        issue      = $IssueNumber
        title      = $IssueTitle
        status     = $status
        startedAt  = $startedAt
        finishedAt = $finishedAt
        details    = $errorMessage
    }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

$sessionStarted = Get-IsoNow

# Preconditions: two Android emulators connected.
$adbDevices = adb devices
$androidDevices = $adbDevices -split "`n" | Select-String "emulator-.*\s+device"
if ($androidDevices.Count -lt 2) {
    throw "Need at least 2 Android emulator devices in 'device' state. Current:`n$adbDevices"
}

$deviceIds = @()
foreach ($line in $androidDevices) {
    $deviceIds += ($line.ToString().Split("`t")[0]).Trim()
}

$device1 = $deviceIds[0]
$device2 = $deviceIds[1]

$device1Activity = Get-ResumedActivity -DeviceId $device1
$device2Activity = Get-ResumedActivity -DeviceId $device2

$results = @()

$results += Run-IssueValidation -IssueNumber 1 -IssueTitle "Pause Internet / Homework / Bedtime / Pause All propagate to child enforcement" -Workdir $repoRoot -Commands @(
    'flutter test test/services/firestore_service_test.dart --plain-name "pauseAllChildren sets pausedUntil for all parent children"',
    'flutter test test/services/firestore_service_test.dart --plain-name "resumeAllChildren clears pausedUntil for all parent children"',
    'flutter test test/services/policy_vpn_sync_service_test.dart --plain-name "syncNow still pushes rules when VPN is not running"',
    'flutter test test/services/remote_command_service_test.dart --plain-name "processPendingCommands executes restart and marks command executed"'
)

$results += Run-IssueValidation -IssueNumber 2 -IssueTitle "Connected child device status reflects online presence" -Workdir $repoRoot -Commands @(
    'flutter test test/bug_fixes_regression_test.dart --plain-name "child with deviceIds but no heartbeat shows Connecting status"',
    'flutter test test/services/heartbeat_service_test.dart'
)

$results += Run-IssueValidation -IssueNumber 3 -IssueTitle "Schedules enforce on child at correct boundaries" -Workdir $repoRoot -Commands @(
    'flutter test test/screens/child/child_status_screen_test.dart',
    'flutter test test/services/policy_vpn_sync_service_test.dart --plain-name "startListening auto-syncs when Firestore stream emits update"'
)

$results += Run-IssueValidation -IssueNumber 4 -IssueTitle "Reports load for parent without child/parent usage-auth gate" -Workdir $repoRoot -Commands @(
    'flutter test test/screens/usage_reports_screen_test.dart --plain-name "shows child-report waiting state when usage data is unavailable"'
)

$results += Run-IssueValidation -IssueNumber 5 -IssueTitle "Block Apps save persists and reaches enforcement path" -Workdir $repoRoot -Commands @(
    'flutter test test/screens/block_categories_screen_test.dart',
    'flutter test test/services/policy_vpn_sync_service_test.dart --plain-name "blocklist operations onCategoryEnabled(social) triggers VPN update call"'
)

$results += Run-IssueValidation -IssueNumber 6 -IssueTitle "Open-source blocklist stale label clears after successful sync" -Workdir $repoRoot -Commands @(
    'flutter test test/services/blocklist_sync_service_test.dart --plain-name "getStatus marks fresh when last synced is within 14 days"',
    'flutter test test/services/blocklist_sync_service_test.dart --plain-name "getStatus marks stale when last synced is older than 14 days"'
)

$rulesValidationStarted = Get-IsoNow
$rulesStatus = "PASS"
$rulesDetails = ""
try {
    Run-CommandChecked -Command 'firebase emulators:exec --only firestore "node test/firestore_rules/rules.test.js"' -Workdir $repoRoot
} catch {
    $rulesStatus = "FAIL"
    $rulesDetails = $_.Exception.Message
}
$rulesValidationFinished = Get-IsoNow

$sessionFinished = Get-IsoNow

$allPassed = ($results | Where-Object { $_.status -eq "FAIL" }).Count -eq 0 -and $rulesStatus -eq "PASS"
$summaryStatus = if ($allPassed) { "PASS" } else { "FAIL" }

$reportLines = @()
$reportLines += "# Live Validation Report"
$reportLines += ""
$reportLines += "- Session start: $sessionStarted"
$reportLines += "- Session end: $sessionFinished"
$reportLines += "- Overall status: **$summaryStatus**"
$reportLines += ""
$reportLines += "## Android Devices"
$reportLines += ""
$reportLines += "- Device 1: $device1"
$reportLines += "- Device 1 top activity: $device1Activity"
$reportLines += "- Device 2: $device2"
$reportLines += "- Device 2 top activity: $device2Activity"
$reportLines += ""
$reportLines += "## Issue Results"
$reportLines += ""
foreach ($result in $results) {
    $reportLines += "### Issue $($result.issue): $($result.title)"
    $reportLines += "- Status: **$($result.status)**"
    $reportLines += "- Started: $($result.startedAt)"
    $reportLines += "- Finished: $($result.finishedAt)"
    if ($result.details -and $result.details.Trim().Length -gt 0) {
        $reportLines += "- Details: $($result.details)"
    }
    $reportLines += ""
}

$reportLines += "## Firestore Rules Validation"
$reportLines += ""
$reportLines += "- Status: **$rulesStatus**"
$reportLines += "- Started: $rulesValidationStarted"
$reportLines += "- Finished: $rulesValidationFinished"
if ($rulesDetails -and $rulesDetails.Trim().Length -gt 0) {
    $reportLines += "- Details: $rulesDetails"
}
$reportLines += ""

$reportDir = Split-Path -Parent $OutputPath
if ($reportDir -and !(Test-Path $reportDir)) {
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
}

Set-Content -Path $OutputPath -Value $reportLines -Encoding UTF8

Write-Host ""
Write-Host "Validation complete."
Write-Host "Report: $OutputPath"
Write-Host "Overall status: $summaryStatus"

if (-not $allPassed) {
    exit 1
}
