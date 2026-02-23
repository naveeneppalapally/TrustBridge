param(
    [string]$ParentDevice = "emulator-5554",
    [string]$ChildDevice = "emulator-5556",
    [bool]$UseEmulators = $true,
    [string]$OutputPath = "docs/TWO_DEVICE_ACCEPTANCE_REPORT.md"
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

function Run-CommandBestEffort {
    param(
        [string]$Command,
        [string]$Workdir
    )

    Push-Location $Workdir
    try {
        Write-Host "[RUN] $Command"
        & cmd.exe /d /s /c $Command
    } finally {
        Pop-Location
    }
}

function Assert-DeviceConnected {
    param(
        [string]$DeviceId,
        [string]$AdbListOutput
    )

    if (-not ($AdbListOutput -match "$DeviceId\s+device")) {
        throw "Required device '$DeviceId' is not connected in adb devices output."
    }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$sessionStart = Get-IsoNow
$status = "PASS"
$errorMessage = ""
$runId = ("{0:yyyyMMddHHmmss}" -f (Get-Date)) + (Get-Random -Minimum 1000 -Maximum 9999)

try {
    $adbDevices = adb devices
    Assert-DeviceConnected -DeviceId $ParentDevice -AdbListOutput $adbDevices
    Assert-DeviceConnected -DeviceId $ChildDevice -AdbListOutput $adbDevices

    Run-CommandChecked -Command "flutter pub get" -Workdir $repoRoot

    # Avoid debug-key signature mismatch with previously installed builds.
    Run-CommandBestEffort -Command "adb -s $ParentDevice uninstall com.navee.trustbridge" -Workdir $repoRoot
    Run-CommandBestEffort -Command "adb -s $ChildDevice uninstall com.navee.trustbridge" -Workdir $repoRoot
    Run-CommandBestEffort -Command "adb -s $ParentDevice shell pm clear com.navee.trustbridge" -Workdir $repoRoot
    Run-CommandBestEffort -Command "adb -s $ChildDevice shell pm clear com.navee.trustbridge" -Workdir $repoRoot

    $commonDefines = "--dart-define=TB_RUN_ID=$runId --dart-define=TB_USE_EMULATORS=$(if ($UseEmulators) { 'true' } else { 'false' })"
    if ($UseEmulators) {
        $commonDefines += " --dart-define=TB_EMULATOR_HOST=10.0.2.2 --dart-define=TB_AUTH_PORT=9099 --dart-define=TB_FIRESTORE_PORT=8080"
    }

    $parentSetup = "flutter test integration_test/two_device_authenticated_acceptance_test.dart -d $ParentDevice --dart-define=TB_ROLE=parent_setup $commonDefines"
    $childValidate = "flutter test integration_test/two_device_authenticated_acceptance_test.dart -d $ChildDevice --dart-define=TB_ROLE=child_validate $commonDefines"
    $parentVerify = "flutter test integration_test/two_device_authenticated_acceptance_test.dart -d $ParentDevice --dart-define=TB_ROLE=parent_verify $commonDefines"
    $sequence = "$parentSetup && $childValidate && $parentVerify"
    if ($UseEmulators) {
        $emulatorExec = "firebase emulators:exec --only ""auth,firestore"" ""$sequence"""
        Run-CommandChecked -Command $emulatorExec -Workdir $repoRoot
    } else {
        Run-CommandChecked -Command $parentSetup -Workdir $repoRoot
        Run-CommandChecked -Command $childValidate -Workdir $repoRoot
        Run-CommandChecked -Command $parentVerify -Workdir $repoRoot
    }
} catch {
    $status = "FAIL"
    $errorMessage = $_.Exception.Message
}

$sessionEnd = Get-IsoNow

$reportLines = @()
$reportLines += "# Two-Device Authenticated Acceptance Report"
$reportLines += ""
$reportLines += "- Session start: $sessionStart"
$reportLines += "- Session end: $sessionEnd"
$reportLines += "- Overall status: **$status**"
$reportLines += "- Run ID: $runId"
$reportLines += "- Parent device: $ParentDevice"
$reportLines += "- Child device: $ChildDevice"
$reportLines += ""
$reportLines += "## Executed Flow"
$reportLines += ""
$reportLines += "1. Parent setup role (parent_setup) on parent device"
$reportLines += "2. Child validation role (child_validate) on child device"
$reportLines += "3. Parent verification role (parent_verify) on parent device"
$reportLines += ""
$reportLines += $(if ($UseEmulators) {
    "All steps were executed inside one Firebase emulator session (auth + firestore) to preserve shared test state."
} else {
    "All steps were executed against the live Firebase project on physical devices."
})
$reportLines += ""
if ($errorMessage -and $errorMessage.Trim().Length -gt 0) {
    $reportLines += "## Failure"
    $reportLines += ""
    $reportLines += "- Details: $errorMessage"
    $reportLines += ""
}

$reportDir = Split-Path -Parent $OutputPath
if ($reportDir -and !(Test-Path $reportDir)) {
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
}

Set-Content -Path $OutputPath -Value $reportLines -Encoding UTF8

Write-Host ""
Write-Host "Acceptance run complete."
Write-Host "Report: $OutputPath"
Write-Host "Run ID: $runId"
Write-Host "Overall status: $status"

if ($status -eq "FAIL") {
    exit 1
}
