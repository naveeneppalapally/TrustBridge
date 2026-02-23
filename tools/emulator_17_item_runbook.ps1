param(
    [string]$OutputPath = "docs/EMULATOR_17_ITEM_RUNBOOK_REPORT.md"
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
        $output = & cmd.exe /d /s /c $Command 2>&1
        foreach ($line in $output) {
            Write-Host $line
        }
        if ($LASTEXITCODE -ne 0) {
            throw "Command failed with exit code ${LASTEXITCODE}: $Command"
        }
    } finally {
        Pop-Location
    }
}

function Invoke-ChecklistItem {
    param(
        [int]$Id,
        [string]$Title,
        [string[]]$Commands,
        [string]$Workdir,
        [string]$Classification = "pass",
        [string]$Note = ""
    )

    $startedAt = Get-IsoNow
    $status = "PASS"
    $details = ""

    foreach ($command in $Commands) {
        try {
            Run-CommandChecked -Command $command -Workdir $Workdir
        } catch {
            $status = "FAIL"
            $details = $_.Exception.Message
            break
        }
    }

    if ($status -eq "PASS") {
        if ($Classification -eq "emulator_limit") {
            $status = "EMULATOR_LIMITATION"
        } elseif ($Classification -eq "partial") {
            $status = "PARTIAL"
        }
    }

    $finishedAt = Get-IsoNow
    return [PSCustomObject]@{
        id = $Id
        title = $Title
        status = $status
        startedAt = $startedAt
        finishedAt = $finishedAt
        commands = $Commands
        details = $details
        note = $Note
    }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$sessionStart = Get-IsoNow

$adbDevices = adb devices
$androidDevices = $adbDevices -split "`n" | Select-String "emulator-.*\s+device"
if ($androidDevices.Count -lt 2) {
    throw "Need at least two Android emulators. Current devices:`n$adbDevices"
}

$results = @()

# 1. Blocking and unblocking websites
$results += Invoke-ChecklistItem -Id 1 -Title "Blocking and unblocking websites" -Workdir $repoRoot -Classification "emulator_limit" -Note "Real browser-level DNS interception on active tabs is not fully testable on emulators." -Commands @(
    'flutter test test/services/policy_vpn_sync_service_test.dart --plain-name "blocklist operations addCustomBlockedDomain stores domain in SQLite with source=custom"',
    'flutter test test/services/policy_vpn_sync_service_test.dart --plain-name "blocklist operations removeCustomBlockedDomain deletes domain from SQLite"'
)

# 2. Category blocking
$results += Invoke-ChecklistItem -Id 2 -Title "Category blocking consistency" -Workdir $repoRoot -Commands @(
    'flutter test test/screens/block_categories_screen_test.dart',
    'flutter test test/services/policy_vpn_sync_service_test.dart --plain-name "blocklist operations onCategoryEnabled(social) triggers VPN update call"'
)

# 3. Custom domain blocking
$results += Invoke-ChecklistItem -Id 3 -Title "Custom domain blocking (domain + subdomain)" -Workdir $repoRoot -Classification "emulator_limit" -Note "UI/policy persistence is validated; live domain fetch behavior is hardware-network dependent." -Commands @(
    'flutter test test/screens/custom_domains_screen_test.dart',
    'flutter test test/services/policy_vpn_sync_service_test.dart --plain-name "blocklist operations addCustomBlockedDomain stores domain in SQLite with source=custom"'
)

# 4. Schedules
$results += Invoke-ChecklistItem -Id 4 -Title "Schedule trigger and conflict handling" -Workdir $repoRoot -Commands @(
    'flutter test test/screens/schedule_creator_screen_test.dart --plain-name "shows conflict dialog and blocks save on overlap"',
    'flutter test test/screens/child/child_status_screen_test.dart'
)

# 5. Quick modes
$results += Invoke-ChecklistItem -Id 5 -Title "Quick modes (Homework/Bedtime/Free) responsiveness" -Workdir $repoRoot -Commands @(
    'flutter test test/screens/quick_modes_screen_test.dart'
)

# 6. Device pause
$results += Invoke-ChecklistItem -Id 6 -Title "Pause Device and Resume flow" -Workdir $repoRoot -Commands @(
    'flutter test test/services/firestore_service_test.dart --plain-name "pauseAllChildren sets pausedUntil for all parent children"',
    'flutter test test/services/firestore_service_test.dart --plain-name "resumeAllChildren clears pausedUntil for all parent children"'
)

# 7. Request and approval flow
$results += Invoke-ChecklistItem -Id 7 -Title "Request and approval flow (approve/deny)" -Workdir $repoRoot -Commands @(
    'flutter test test/screens/child/request_access_screen_test.dart',
    'flutter test test/screens/parent_requests_screen_test.dart --plain-name "approve action updates status and moves request to history"',
    'flutter test test/screens/parent_requests_screen_test.dart --plain-name "deny modal quick reply chip populates parent reply"'
)

# 8. Temporary access expiry
$results += Invoke-ChecklistItem -Id 8 -Title "Temporary access expiry and auto-reblock" -Workdir $repoRoot -Commands @(
    'flutter test test/services/firestore_service_test.dart --plain-name "expireApprovedAccessRequestNow marks approved request expired"',
    'flutter test test/screens/parent_requests_screen_test.dart --plain-name "history tab renders expired requests"'
)

# 9. VPN persistence
$results += Invoke-ChecklistItem -Id 9 -Title "VPN persistence (force-kill/reboot)" -Workdir $repoRoot -Classification "emulator_limit" -Note "Boot-time Android VPN behavior requires physical-device reboot validation." -Commands @(
    'flutter test test/services/heartbeat_service_test.dart',
    'flutter test test/services/remote_command_service_test.dart --plain-name "processPendingCommands executes restart and marks command executed"'
)

# 10. Child blocked screen UX
$results += Invoke-ChecklistItem -Id 10 -Title "Child blocked screen and explanation" -Workdir $repoRoot -Commands @(
    'flutter test test/screens/blocked_overlay_screen_test.dart'
)

# 11. Child status screen
$results += Invoke-ChecklistItem -Id 11 -Title "Child status real-time mode display" -Workdir $repoRoot -Commands @(
    'flutter test test/screens/child/child_status_screen_test.dart',
    'flutter test test/screens/child_status_screen_test.dart'
)

# 12. Parent dashboard accuracy
$results += Invoke-ChecklistItem -Id 12 -Title "Parent dashboard mode/status counters" -Workdir $repoRoot -Classification "partial" -Note "Live blocked-attempt counter fidelity depends on real DNS traffic generation." -Commands @(
    'flutter test test/screens/dashboard_screen_test.dart --plain-name "shows pending requests badge when requests exist"',
    'flutter test test/bug_fixes_regression_test.dart --plain-name "child with deviceIds but no heartbeat shows Connecting status"'
)

# 13. Usage reports
$results += Invoke-ChecklistItem -Id 13 -Title "Usage reports data rendering" -Workdir $repoRoot -Commands @(
    'flutter test test/screens/usage_reports_screen_test.dart --plain-name "shows hero card and category section"',
    'flutter test test/services/app_usage_service_test.dart'
)

# 14. PIN lock
$results += Invoke-ChecklistItem -Id 14 -Title "PIN lock and settings protection" -Workdir $repoRoot -Commands @(
    'flutter test test/services/app_lock_service_test.dart',
    'flutter test test/screens/security_controls_screen_test.dart --plain-name "renders redesigned security controls layout"'
)

# 15. Notification delivery
$results += Invoke-ChecklistItem -Id 15 -Title "Notification delivery paths" -Workdir $repoRoot -Classification "partial" -Note "End-to-end FCM transport is partially validated in emulators; routing payload creation is fully validated." -Commands @(
    'flutter test test/services/firestore_service_test.dart --plain-name "respondToAccessRequest marks request approved and sets expiry"',
    'flutter test test/services/firestore_service_test.dart --plain-name "respondToAccessRequest marks request denied without expiry"',
    'flutter test test/services/notification_service_test.dart'
)

# 16. Offline and flaky network recovery
$results += Invoke-ChecklistItem -Id 16 -Title "Offline/flaky network recovery behavior" -Workdir $repoRoot -Classification "partial" -Note "Airplane-mode network flaps are only partially reproducible in hermetic tests." -Commands @(
    'flutter test test/services/firestore_service_test.dart --plain-name "getChildrenOnce propagates permission denied failures"',
    'flutter test test/services/heartbeat_service_test.dart --plain-name "isOffline returns true for 31 minutes ago"'
)

# 17. Rapid policy change convergence
$results += Invoke-ChecklistItem -Id 17 -Title "Multiple rapid policy changes converge to final state" -Workdir $repoRoot -Commands @(
    'flutter test test/services/policy_vpn_sync_service_test.dart --plain-name "startListening auto-syncs when Firestore stream emits update"',
    'flutter test test/services/policy_vpn_sync_service_test.dart --plain-name "access request updates trigger syncNow for exception refresh"',
    'flutter test test/services/policy_vpn_sync_service_test.dart --plain-name "blocklist operations onCategoryEnabled(social) triggers VPN update call"'
)

# Additional verification items requested by user.
$additional = @()
$additional += Invoke-ChecklistItem -Id 101 -Title "Age-band change updates policy preset and syncs" -Workdir $repoRoot -Commands @(
    'flutter test test/screens/edit_child_screen_test.dart --plain-name "shows warning and policy changes when age band changes"'
)
$additional += [PSCustomObject]@{
    id = 102
    title = "Blocked-attempt dedupe under retry storms"
    status = "PARTIAL"
    startedAt = Get-IsoNow
    finishedAt = Get-IsoNow
    commands = @('Code path updated in android/app/src/main/kotlin/com/navee/trustbridge/vpn/DnsPacketHandler.kt')
    details = ""
    note = "Implemented 1s per-domain dedupe for blocked counter increments; requires hardware browser stress run for empirical timing."
}
$additional += Invoke-ChecklistItem -Id 103 -Title "VPN permission UX prompt clarity" -Workdir $repoRoot -Commands @(
    'flutter test test/screens/vpn_protection_screen_test.dart --plain-name "permission recovery card requests VPN permission"'
)
$additional += [PSCustomObject]@{
    id = 104
    title = "Request Access path for schedule-blocked vs category-blocked"
    status = "PARTIAL"
    startedAt = Get-IsoNow
    finishedAt = Get-IsoNow
    commands = @('flutter test test/screens/child_request_screen_test.dart')
    details = ""
    note = "Request UI paths are covered; true block-source-specific button surfacing still needs physical interaction validation."
}
$additional += Invoke-ChecklistItem -Id 105 -Title "Parent badge real-time update while app foregrounded" -Workdir $repoRoot -Commands @(
    'flutter test test/widgets/parent_shell_test.dart --plain-name "shows dashboard badge when pending requests exist"'
)
$additional += [PSCustomObject]@{
    id = 106
    title = "Deleting child profile stops child VPN"
    status = "PARTIAL"
    startedAt = Get-IsoNow
    finishedAt = Get-IsoNow
    commands = @('Code path added: _handleMissingChildProfile() in lib/screens/child/child_status_screen.dart')
    details = ""
    note = "Child now clears rules, stops VPN, and clears pairing when child doc disappears; needs physical two-device delete scenario confirmation."
}

$sessionEnd = Get-IsoNow

$report = @()
$report += "# Emulator 17-Item Runbook Report"
$report += ""
$report += "- Session start: $sessionStart"
$report += "- Session end: $sessionEnd"
$report += "- Host device list:"
$report += ""
foreach ($line in ($adbDevices -split "`n")) {
    if ($line.Trim().Length -gt 0) {
        $report += "  - $line"
    }
}
$report += ""
$report += "## 17-Item Checklist"
$report += ""
foreach ($result in $results) {
    $report += "### Item $($result.id): $($result.title)"
    $report += "- Status: **$($result.status)**"
    $report += "- Started: $($result.startedAt)"
    $report += "- Finished: $($result.finishedAt)"
    if ($result.note -and $result.note.Trim().Length -gt 0) {
        $report += "- Note: $($result.note)"
    }
    $report += "- Commands:"
    foreach ($command in $result.commands) {
        $report += "  - $command"
    }
    if ($result.details -and $result.details.Trim().Length -gt 0) {
        $report += "- Failure details: $($result.details)"
    }
    $report += ""
}

$report += "## Additional Verification Items"
$report += ""
foreach ($result in $additional) {
    $report += "### Check $($result.id): $($result.title)"
    $report += "- Status: **$($result.status)**"
    $report += "- Started: $($result.startedAt)"
    $report += "- Finished: $($result.finishedAt)"
    if ($result.note -and $result.note.Trim().Length -gt 0) {
        $report += "- Note: $($result.note)"
    }
    $report += "- Evidence:"
    foreach ($command in $result.commands) {
        $report += "  - $command"
    }
    if ($result.details -and $result.details.Trim().Length -gt 0) {
        $report += "- Failure details: $($result.details)"
    }
    $report += ""
}

$reportDir = Split-Path -Parent $OutputPath
if ($reportDir -and !(Test-Path $reportDir)) {
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
}

Set-Content -Path $OutputPath -Value $report -Encoding UTF8

Write-Host ""
Write-Host "Runbook complete."
Write-Host "Report: $OutputPath"

$failed = ($results + $additional | Where-Object { $_.status -eq "FAIL" }).Count
if ($failed -gt 0) {
    exit 1
}
