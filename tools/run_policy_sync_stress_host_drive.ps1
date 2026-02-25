param(
    [string]$RunId = "stress20260224host",
    [string]$ChildDeviceId = "aae47d3e",
    [int]$OpTimeoutSeconds = 25,
    [int]$ObservePollMs = 50,
    [int]$ChildTimeoutMinutes = 35,
    [int]$ChildReadyTimeoutMinutes = 10,
    [ValidateSet("auto", "direct")]
    [string]$ChildLaunchMode = "direct",
    [string]$SetupLogPath = "stress_setup.log",
    [string]$ChildLogPath = "stress_child.log",
    [string]$ChildErrPath = "stress_child.err",
    [string]$RealtimeLogPath = "tmp_vpn_start_blocking.log"
)

$ErrorActionPreference = "Stop"

function Normalize-RunId {
    param([string]$Raw)
    $value = if ($null -eq $Raw) { "" } else { $Raw }
    return (($value.Trim().ToLowerInvariant()) -replace "[^a-z0-9]", "")
}

function Parent-EmailForRun {
    param([string]$RunIdValue)
    return "tb.schedule.$RunIdValue@trustbridge.local"
}

function Parent-PasswordForRun {
    param([string]$RunIdValue)
    $seed = if ($RunIdValue.Length -ge 8) {
        $RunIdValue.Substring(0, 8)
    } else {
        $RunIdValue.PadRight(8, '0')
    }
    return "Tb!${seed}Aa1"
}

function New-StringArrayField {
    param([string[]]$Values)
    if ($null -eq $Values -or $Values.Count -eq 0) {
        return @{ arrayValue = @{} }
    }
    $encoded = @()
    foreach ($value in $Values) {
        $encoded += @{ stringValue = $value }
    }
    return @{ arrayValue = @{ values = $encoded } }
}

function Update-ChildDocument {
    param(
        [string]$ProjectId,
        [string]$ChildId,
        [string]$IdToken,
        [string[]]$FieldPaths,
        [hashtable]$Fields
    )

    $masks = @()
    foreach ($path in $FieldPaths) {
        $masks += "updateMask.fieldPaths=$([uri]::EscapeDataString($path))"
    }
    $maskQuery = $masks -join "&"
    $uri = "https://firestore.googleapis.com/v1/projects/$ProjectId/databases/(default)/documents/children/$ChildId?$maskQuery"

    $headers = @{
        Authorization = "Bearer $IdToken"
    }
    $body = @{
        fields = $Fields
    } | ConvertTo-Json -Depth 20

    Invoke-RestMethod -Method Patch -Uri $uri -Headers $headers -ContentType "application/json" -Body $body | Out-Null
}

$normalizedRunId = Normalize-RunId -Raw $RunId
if ([string]::IsNullOrWhiteSpace($normalizedRunId)) {
    throw "RunId is empty after normalization."
}

$projectId = "trustbridge-navee"
$apiKey = "AIzaSyBg2mJjl3M-d1OsIA3Qm3CklOkgx_ZjKsI"

$email = Parent-EmailForRun -RunIdValue $normalizedRunId
$password = Parent-PasswordForRun -RunIdValue $normalizedRunId

Write-Output "RUN_ID=$normalizedRunId"

# Clean stale stress-test processes before launching a new run.
$stale = Get-CimInstance Win32_Process | Where-Object {
    ($_.Name -eq "dart.exe" -or $_.Name -eq "dartvm.exe" -or $_.Name -eq "flutter.bat" -or $_.Name -eq "cmd.exe" -or $_.Name -eq "powershell.exe") -and
    ($_.CommandLine -like "*real_device_policy_sync_stress_test.dart*" -or $_.CommandLine -like "*tmp_vpn_start_blocking.log*")
}
foreach ($p in $stale) {
    try {
        Stop-Process -Id $p.ProcessId -Force
    } catch {
    }
}
Start-Sleep -Seconds 1

foreach ($path in @($SetupLogPath, $ChildLogPath, $ChildErrPath)) {
    if (Test-Path $path) {
        try {
            Remove-Item $path -Force
        } catch {
        }
    }
}
if (Test-Path $RealtimeLogPath) {
    try {
        Remove-Item $RealtimeLogPath -Force
    } catch {
    }
}

Write-Output "STEP=setup_start"
$setupOutput = & flutter test integration_test/real_device_policy_sync_stress_test.dart `
    -d $ChildDeviceId `
    --dart-define=TB_ROLE=setup `
    --dart-define=TB_RUN_ID=$normalizedRunId 2>&1
$setupOutput | Tee-Object -FilePath $SetupLogPath
$setupExit = $LASTEXITCODE
Write-Output "SETUP_EXIT=$setupExit"
if ($setupExit -ne 0) {
    exit $setupExit
}

$setupText = ($setupOutput | Out-String)
$setupMatch = [regex]::Match(
    $setupText,
    '\[SYNC_STRESS_SETUP\].*parentId=([^\s]+)\s+childId=([^\s]+).*pairingCode=(\d{6})'
)
if (-not $setupMatch.Success) {
    Write-Output "ERROR=setup_metadata_not_found"
    exit 3
}
$parentId = $setupMatch.Groups[1].Value
$childId = $setupMatch.Groups[2].Value
$pairingCode = $setupMatch.Groups[3].Value
Write-Output "PARENT_ID=$parentId"
Write-Output "CHILD_ID=$childId"
Write-Output "PAIRING_CODE=$pairingCode"

$signInBody = @{
    email = $email
    password = $password
    returnSecureToken = $true
} | ConvertTo-Json
$signInResponse = Invoke-RestMethod `
    -Method Post `
    -Uri "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$apiKey" `
    -ContentType "application/json" `
    -Body $signInBody
$idToken = $signInResponse.idToken
if ([string]::IsNullOrWhiteSpace($idToken)) {
    throw "Failed to obtain Firebase ID token."
}

$childDefines = @(
    "TB_ROLE=observe",
    "TB_RUN_ID=$normalizedRunId",
    "TB_PAIRING_CODE=$pairingCode",
    "TB_OP_TIMEOUT_SECONDS=$OpTimeoutSeconds",
    "TB_PROBE_TIMEOUT_SECONDS=45",
    "TB_OBSERVE_POLL_MS=$ObservePollMs"
) -join ","

Write-Output "STEP=child_start"
$childReadyLogPath = $RealtimeLogPath
if ($ChildLaunchMode -eq "direct") {
    if (Test-Path $RealtimeLogPath) {
        try { Remove-Item $RealtimeLogPath -Force } catch {}
    }
    $childCmd = @(
        "flutter test integration_test/real_device_policy_sync_stress_test.dart",
        "-d $ChildDeviceId",
        "--dart-define=TB_ROLE=observe",
        "--dart-define=TB_RUN_ID=$normalizedRunId",
        "--dart-define=TB_PAIRING_CODE=$pairingCode",
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
    $childReadyLogPath = $ChildLogPath
} else {
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
            $logText = Get-Content $childReadyLogPath -Raw
        } catch {
            $logText = ""
        }
    }

    if ($logText -match "\[SYNC_STRESS_OBSERVE\] ready runId=$([regex]::Escape($normalizedRunId))") {
        $childReady = $true
        break
    }
    if ($logText -match "Some tests failed\." -or $logText -match "\[E\]") {
        break
    }

    Start-Sleep -Seconds 4
}
Write-Output "CHILD_READY=$childReady"

if (-not $childReady) {
    Write-Output "ERROR=child_not_ready"
    if (-not $childProc.HasExited) {
        try { Stop-Process -Id $childProc.Id -Force } catch {}
    }
    exit 4
}

$safeSearchEnabled = $true
$lastBlockedCategories = @()
$lastBlockedDomains = @()

function Apply-PolicyOperation {
    param(
        [string[]]$BlockedCategories,
        [string[]]$BlockedDomains
    )
    $script:lastBlockedCategories = @($BlockedCategories)
    $script:lastBlockedDomains = @($BlockedDomains)
    Update-ChildDocument `
        -ProjectId $projectId `
        -ChildId $childId `
        -IdToken $idToken `
        -FieldPaths @("policy", "updatedAt") `
        -Fields @{
            policy = @{
                mapValue = @{
                    fields = @{
                        blockedCategories = (New-StringArrayField -Values $BlockedCategories)
                        blockedDomains = (New-StringArrayField -Values $BlockedDomains)
                        schedules = @{ arrayValue = @{} }
                        safeSearchEnabled = @{ booleanValue = $safeSearchEnabled }
                    }
                }
            }
            updatedAt = @{ timestampValue = (Get-Date).ToUniversalTime().ToString("o") }
        }
}

function Apply-ManualMode {
    param([string]$Mode)
    $manualField = if ([string]::IsNullOrWhiteSpace($Mode)) {
        @{ nullValue = $null }
    } else {
        @{
            mapValue = @{
                fields = @{
                    mode = @{ stringValue = $Mode }
                    setAt = @{ timestampValue = (Get-Date).ToUniversalTime().ToString("o") }
                    expiresAt = @{ timestampValue = (Get-Date).ToUniversalTime().AddMinutes(20).ToString("o") }
                }
            }
        }
    }
    Update-ChildDocument `
        -ProjectId $projectId `
        -ChildId $childId `
        -IdToken $idToken `
        -FieldPaths @("manualMode", "updatedAt") `
        -Fields @{
            manualMode = $manualField
            updatedAt = @{ timestampValue = (Get-Date).ToUniversalTime().ToString("o") }
        }
}

function Apply-Pause {
    param([bool]$Enabled)
    $pausedField = if ($Enabled) {
        @{ timestampValue = (Get-Date).ToUniversalTime().AddMinutes(20).ToString("o") }
    } else {
        @{ nullValue = $null }
    }
    Update-ChildDocument `
        -ProjectId $projectId `
        -ChildId $childId `
        -IdToken $idToken `
        -FieldPaths @("pausedUntil", "updatedAt") `
        -Fields @{
            pausedUntil = $pausedField
            updatedAt = @{ timestampValue = (Get-Date).ToUniversalTime().ToString("o") }
        }
}

$operations = @(
    @{ seq = 1; id = "op01_block_domain"; kind = "block_domain" },
    @{ seq = 2; id = "op02_unblock_domain"; kind = "unblock_domain" },
    @{ seq = 3; id = "op03_block_category"; kind = "block_category" },
    @{ seq = 4; id = "op04_unblock_category"; kind = "unblock_category" },
    @{ seq = 5; id = "op05_add_custom_domain"; kind = "add_custom_domain" },
    @{ seq = 6; id = "op06_remove_custom_domain"; kind = "remove_custom_domain" },
    @{ seq = 7; id = "op07_enable_quick_mode"; kind = "enable_quick_mode" },
    @{ seq = 8; id = "op08_disable_quick_mode"; kind = "disable_quick_mode" },
    @{ seq = 9; id = "op09_pause_device"; kind = "pause_device" },
    @{ seq = 10; id = "op10_unpause_device"; kind = "unpause_device" }
)

$domainA = "sync-speed-a.trustbridge.test"
$domainB = "sync-speed-b.trustbridge.test"
$parentSaved = @{}

Write-Output "STEP=drive_start"
Apply-PolicyOperation -BlockedCategories @() -BlockedDomains @()
Apply-ManualMode -Mode ""
Apply-Pause -Enabled $false

foreach ($op in $operations) {
    $startedAtMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    switch ($op.kind) {
        "block_domain" { Apply-PolicyOperation -BlockedCategories @() -BlockedDomains @($domainA) }
        "unblock_domain" { Apply-PolicyOperation -BlockedCategories @() -BlockedDomains @() }
        "block_category" { Apply-PolicyOperation -BlockedCategories @("social-networks") -BlockedDomains @() }
        "unblock_category" { Apply-PolicyOperation -BlockedCategories @() -BlockedDomains @() }
        "add_custom_domain" { Apply-PolicyOperation -BlockedCategories @() -BlockedDomains @($domainB) }
        "remove_custom_domain" { Apply-PolicyOperation -BlockedCategories @() -BlockedDomains @() }
        "enable_quick_mode" { Apply-ManualMode -Mode "bedtime" }
        "disable_quick_mode" { Apply-ManualMode -Mode "" }
        "pause_device" { Apply-Pause -Enabled $true }
        "unpause_device" { Apply-Pause -Enabled $false }
        default { throw "Unsupported op kind: $($op.kind)" }
    }
    $savedAtMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $parentSaved[$op.seq] = $savedAtMs
    Write-Output "[SYNC_STRESS_DRIVE] seq=$($op.seq) opId=$($op.id) kind=$($op.kind) startedAtMs=$startedAtMs savedAtMs=$savedAtMs"
    Start-Sleep -Milliseconds 120
}

$waitOk = $true
try {
    Wait-Process -Id $childProc.Id -Timeout ($ChildTimeoutMinutes * 60)
} catch {
    $waitOk = $false
}
if (-not $waitOk -and -not $childProc.HasExited) {
    try { Stop-Process -Id $childProc.Id -Force } catch {}
}

$childProc.Refresh()
$childExit = if ($childProc.HasExited) { $childProc.ExitCode } else { 124 }
Write-Output "CHILD_EXIT=$childExit"

$childEnforced = @{}
$childStatus = @{}
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
$lost = @()
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

exit $childExit
