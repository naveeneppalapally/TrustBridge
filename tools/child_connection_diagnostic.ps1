param(
    [string]$DeviceId = "emulator-5556",
    [Parameter(Mandatory = $true)]
    [string]$ParentEmail,
    [Parameter(Mandatory = $true)]
    [string]$ParentPassword,
    [string]$ChildId = "",
    [bool]$UseEmulators = $true,
    [string]$EmulatorHost = "10.0.2.2",
    [int]$AuthPort = 9099,
    [int]$FirestorePort = 8080,
    [bool]$AutoCreateParent = $true,
    [bool]$AutoCreateChild = $true,
    [string]$OutputPath = "docs/CHILD_CONNECTION_DIAGNOSTIC_REPORT.md"
)

$ErrorActionPreference = "Stop"

function Get-IsoNow {
    return (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff zzz")
}

function Assert-DeviceConnected {
    param(
        [string]$Device,
        [string]$AdbListOutput
    )

    if (-not ($AdbListOutput -match "$Device\s+device")) {
        throw "Required device '$Device' is not connected in adb devices output."
    }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$startedAt = Get-IsoNow
$status = "PASS"
$failure = ""
$diagLogs = @()

try {
    $adbDevices = adb devices
    Assert-DeviceConnected -Device $DeviceId -AdbListOutput $adbDevices

    Push-Location $repoRoot
    try {
        Write-Host "[RUN] flutter pub get"
        & flutter pub get
        if ($LASTEXITCODE -ne 0) {
            throw "flutter pub get failed with exit code $LASTEXITCODE"
        }

        $args = @(
            "test",
            "integration_test/child_parent_account_connection_diagnostic_test.dart",
            "-d", $DeviceId,
            "--dart-define=TB_DIAG_PARENT_EMAIL=$ParentEmail",
            "--dart-define=TB_DIAG_PARENT_PASSWORD=$ParentPassword",
            "--dart-define=TB_DIAG_AUTO_CREATE_PARENT=$(if ($AutoCreateParent) { 'true' } else { 'false' })",
            "--dart-define=TB_DIAG_AUTO_CREATE_CHILD=$(if ($AutoCreateChild) { 'true' } else { 'false' })"
        )

        if ($ChildId.Trim().Length -gt 0) {
            $args += "--dart-define=TB_DIAG_CHILD_ID=$ChildId"
        }
        if ($UseEmulators) {
            $args += "--dart-define=TB_DIAG_EMULATOR_HOST=$EmulatorHost"
            $args += "--dart-define=TB_DIAG_AUTH_PORT=$AuthPort"
            $args += "--dart-define=TB_DIAG_FIRESTORE_PORT=$FirestorePort"
        }

        $escapedArgs = $args | ForEach-Object {
            if ($_ -match '\s') {
                '"' + $_ + '"'
            } else {
                $_
            }
        }
        $flutterCommand = "flutter " + ($escapedArgs -join " ")

        if ($UseEmulators) {
            Write-Host "[RUN] firebase emulators:exec (auth,firestore) + flutter diagnostic on $DeviceId"
            $diagLogs = & firebase emulators:exec --only "auth,firestore" $flutterCommand 2>&1
        } else {
            Write-Host "[RUN] flutter integration diagnostic on $DeviceId"
            $diagLogs = & flutter @args 2>&1
        }
        $diagLogs | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) {
            throw "Diagnostic integration test failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
} catch {
    $status = "FAIL"
    $failure = $_.Exception.Message
}

$endedAt = Get-IsoNow

$report = @()
$report += "# Child Connection Diagnostic"
$report += ""
$report += "- Started: $startedAt"
$report += "- Ended: $endedAt"
$report += "- Status: **$status**"
$report += "- Device: $DeviceId"
$report += "- Parent email: $ParentEmail"
$report += "- Child ID: " + ($(if ($ChildId.Trim().Length -gt 0) { $ChildId } else { "(auto-resolved)" }))
$report += "- Firebase target: " + ($(if ($UseEmulators) { "Emulators (${EmulatorHost}:$AuthPort / ${EmulatorHost}:$FirestorePort)" } else { "Live project" }))
$report += ""

if ($failure.Trim().Length -gt 0) {
    $report += "## Failure"
    $report += ""
    $report += "- $failure"
    $report += ""
}

$report += "## Diagnostic Log"
$report += ""
if ($diagLogs.Count -eq 0) {
    $report += "_No integration output captured._"
} else {
    foreach ($line in $diagLogs) {
        $report += "- " + ($line.ToString())
    }
}
$report += ""

$reportDir = Split-Path -Parent $OutputPath
if ($reportDir -and !(Test-Path $reportDir)) {
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
}

Set-Content -Path $OutputPath -Value $report -Encoding UTF8

Write-Host ""
Write-Host "Diagnostic complete."
Write-Host "Report: $OutputPath"
Write-Host "Status: $status"

if ($status -eq "FAIL") {
    exit 1
}
