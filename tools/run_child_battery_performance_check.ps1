param(
    [string]$DeviceId = "aae47d3e",
    [string]$PackageName = "com.navee.trustbridge",
    [string]$BrowserPackage = "com.android.chrome",
    [int]$IdleMinutes = 30,
    [string]$OutputJsonPath = "battery_performance_report.json"
)

$ErrorActionPreference = "Stop"
if ($PSVersionTable.PSVersion.Major -ge 7) {
    $PSNativeCommandUseErrorActionPreference = $false
}

function Invoke-AdbShell {
    param(
        [string]$Command,
        [switch]$AllowFailure
    )
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $output = & adb -s $DeviceId shell $Command 2>$null
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $oldPreference
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "adb shell failed: $Command`n$output"
    }
    return ($output | Out-String).Trim()
}

function Measure-AdbShell {
    param(
        [string]$Command,
        [switch]$AllowFailure
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $output = & adb -s $DeviceId shell $Command 2>$null
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $oldPreference
    $sw.Stop()
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "adb shell failed: $Command`n$output"
    }
    return [pscustomobject]@{
        ms = [int64]$sw.ElapsedMilliseconds
        output = ($output | Out-String).Trim()
    }
}

function Get-BatterySnapshot {
    $text = Invoke-AdbShell -Command "dumpsys battery"

    $level = [int]([regex]::Match($text, "(?m)^\s*level:\s*(\d+)").Groups[1].Value)
    $scale = [int]([regex]::Match($text, "(?m)^\s*scale:\s*(\d+)").Groups[1].Value)
    $status = [int]([regex]::Match($text, "(?m)^\s*status:\s*(\d+)").Groups[1].Value)
    $chargeCounter = [int64]([regex]::Match($text, "(?m)^\s*Charge counter:\s*(\d+)").Groups[1].Value)
    $usb = [regex]::Match($text, "(?m)^\s*USB powered:\s*(\w+)").Groups[1].Value
    $ac = [regex]::Match($text, "(?m)^\s*AC powered:\s*(\w+)").Groups[1].Value
    $wireless = [regex]::Match($text, "(?m)^\s*Wireless powered:\s*(\w+)").Groups[1].Value

    return [pscustomobject]@{
        raw = $text
        level = $level
        scale = $scale
        status = $status
        chargeCounterUah = $chargeCounter
        usbPowered = $usb
        acPowered = $ac
        wirelessPowered = $wireless
    }
}

function Get-ProcessSnapshot {
    $procPid = Invoke-AdbShell -Command "pidof $PackageName" -AllowFailure
    $cpuLine = Invoke-AdbShell -Command "dumpsys cpuinfo | grep -i $PackageName | head -n 1" -AllowFailure
    $topLine = Invoke-AdbShell -Command "top -b -n 1 | grep $PackageName | head -n 1" -AllowFailure
    $memText = Invoke-AdbShell -Command "dumpsys meminfo $PackageName | grep -E 'TOTAL PSS|TOTAL RSS|Java Heap|Native Heap' | head -n 10" -AllowFailure

    $pssMatch = [regex]::Match($memText, "TOTAL PSS:\s*(\d+)")
    $rssMatch = [regex]::Match($memText, "TOTAL RSS:\s*(\d+)")

    return [pscustomobject]@{
        pid = $procPid
        cpuLine = $cpuLine
        topLine = $topLine
        memSummary = $memText
        totalPssKb = if ($pssMatch.Success) { [int]$pssMatch.Groups[1].Value } else { $null }
        totalRssKb = if ($rssMatch.Success) { [int]$rssMatch.Groups[1].Value } else { $null }
    }
}

function Browse-DomainViaAdb {
    param([string]$Domain)

    [void](Invoke-AdbShell -Command "monkey -p $BrowserPackage -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1")
    Start-Sleep -Milliseconds 700
    [void](Invoke-AdbShell -Command "input keyevent 84")
    Start-Sleep -Milliseconds 250
    [void](Invoke-AdbShell -Command "input text $Domain")
    Start-Sleep -Milliseconds 250
    [void](Invoke-AdbShell -Command "input keyevent 66")
    Start-Sleep -Milliseconds 1200
}

function Get-ResolvedIp {
    param([string]$Domain)

    $pingText = Invoke-AdbShell -Command "ping -c 1 -W 1 $Domain" -AllowFailure
    $ipMatch = [regex]::Match($pingText, "\((\d{1,3}(?:\.\d{1,3}){3})\)")
    return [pscustomobject]@{
        ip = if ($ipMatch.Success) { $ipMatch.Groups[1].Value } else { $null }
        pingText = $pingText
    }
}

function Measure-DomainDnsEstimate {
    param(
        [string]$Domain,
        [string]$Class
    )

    Browse-DomainViaAdb -Domain $Domain

    $resolved = Get-ResolvedIp -Domain $Domain
    $domainConn = Measure-AdbShell -Command "echo | nc -w 3 $Domain 443" -AllowFailure

    $ipConn = $null
    if ($resolved.ip) {
        $ipConn = Measure-AdbShell -Command "echo | nc -w 3 $($resolved.ip) 443" -AllowFailure
    }

    $dnsEstimate = if ($ipConn) {
        [math]::Max(0, [int]($domainConn.ms - $ipConn.ms))
    } else {
        [int]$domainConn.ms
    }

    return [pscustomobject]@{
        domain = $Domain
        class = $Class
        resolvedIp = $resolved.ip
        domainConnectMs = $domainConn.ms
        ipConnectMs = if ($ipConn) { $ipConn.ms } else { $null }
        dnsEstimateMs = $dnsEstimate
        domainConnectOutput = $domainConn.output
        resolveOutputFirstLine = (($resolved.pingText -split "`n")[0]).Trim()
    }
}

function Get-AppUid {
    $pkgLine = Invoke-AdbShell -Command "cmd package list packages -U $PackageName"
    $uidMatch = [regex]::Match($pkgLine, "uid:(\d+)")
    if (-not $uidMatch.Success) {
        throw "Could not determine UID for $PackageName. Output: $pkgLine"
    }
    return [int]$uidMatch.Groups[1].Value
}

function Get-AppUidTag {
    param([int]$Uid)
    if ($Uid -ge 10000) {
        return "u0a$($Uid - 10000)"
    }
    return "u0i$Uid"
}

function Parse-AppMahFromBatterystats {
    param(
        [string]$BatterystatsText,
        [string]$UidTag
    )
    $m = [regex]::Match(
        $BatterystatsText,
        "(?im)^\s*UID\s+$([regex]::Escape($UidTag)):\s+([0-9.]+)\b"
    )
    if ($m.Success) {
        return [double]::Parse($m.Groups[1].Value)
    }
    return $null
}

function Average-Of {
    param([object[]]$Rows)
    if (-not $Rows -or $Rows.Count -eq 0) {
        return $null
    }
    $values = @()
    foreach ($row in $Rows) {
        if ($null -eq $row) {
            continue
        }
        $prop = $row.PSObject.Properties["dnsEstimateMs"]
        if ($null -eq $prop) {
            continue
        }
        $values += [double]$prop.Value
    }
    if ($values.Count -eq 0) {
        return $null
    }
    $avg = ($values | Measure-Object -Average).Average
    return [math]::Round([double]$avg, 2)
}

Write-Output "STEP=precheck"
$deviceText = (& adb devices | Out-String)
if ($deviceText -notmatch "(?m)^$([regex]::Escape($DeviceId))\s+device\s*$") {
    throw "Device not connected/authorized: $DeviceId"
}

$uid = Get-AppUid
$uidTag = Get-AppUidTag -Uid $uid

$baselineBattery = Get-BatterySnapshot
$baselineProc = Get-ProcessSnapshot

# Estimate battery capacity from charge counter and level.
$estimatedCapacityMah = $null
if ($baselineBattery.chargeCounterUah -gt 0 -and $baselineBattery.level -gt 0 -and $baselineBattery.scale -gt 0) {
    $pct = [double]$baselineBattery.level / [double]$baselineBattery.scale
    if ($pct -gt 0) {
        $estimatedCapacityMah = [math]::Round((($baselineBattery.chargeCounterUah / 1000.0) / $pct), 2)
    }
}

Write-Output "STEP=reset_batterystats uid=$uid uidTag=$uidTag"
Invoke-AdbShell -Command "dumpsys batterystats --reset" | Out-Null

$startedAtUtc = [DateTime]::UtcNow

$blockedDomains = @(
    "instagram.com",
    "www.instagram.com",
    "m.instagram.com",
    "help.instagram.com",
    "about.instagram.com",
    "api.instagram.com",
    "graph.instagram.com",
    "i.instagram.com",
    "l.instagram.com",
    "business.instagram.com"
)

$allowedDomains = @(
    "google.com",
    "wikipedia.org",
    "openai.com",
    "microsoft.com",
    "amazon.com",
    "bbc.com",
    "nytimes.com",
    "stackoverflow.com",
    "cloudflare.com",
    "github.com"
)

$rows = New-Object System.Collections.Generic.List[object]
$sequence = 0

Write-Output "STEP=domain_sweep count=20"
foreach ($domain in $blockedDomains) {
    $sequence++
    Write-Output "DOMAIN_START seq=$sequence class=blocked domain=$domain"
    $row = Measure-DomainDnsEstimate -Domain $domain -Class "blocked"
    $rows.Add($row)
    Write-Output "DOMAIN_END seq=$sequence dnsEstimateMs=$($row.dnsEstimateMs) domainConnectMs=$($row.domainConnectMs) ipConnectMs=$($row.ipConnectMs)"
}

foreach ($domain in $allowedDomains) {
    $sequence++
    Write-Output "DOMAIN_START seq=$sequence class=allowed domain=$domain"
    $row = Measure-DomainDnsEstimate -Domain $domain -Class "allowed"
    $rows.Add($row)
    Write-Output "DOMAIN_END seq=$sequence dnsEstimateMs=$($row.dnsEstimateMs) domainConnectMs=$($row.domainConnectMs) ipConnectMs=$($row.ipConnectMs)"
}

$afterSweepBattery = Get-BatterySnapshot

Write-Output "STEP=idle_wait minutes=$IdleMinutes"
Start-Sleep -Seconds ($IdleMinutes * 60)

$finalBattery = Get-BatterySnapshot
$finalProc = Get-ProcessSnapshot

$endedAtUtc = [DateTime]::UtcNow
$durationHours = [math]::Round((($endedAtUtc - $startedAtUtc).TotalHours), 4)

$batterystatsText = Invoke-AdbShell -Command "dumpsys batterystats --charged"
$appMah = Parse-AppMahFromBatterystats -BatterystatsText $batterystatsText -UidTag $uidTag

$blockedAvg = Average-Of -Rows @($rows | Where-Object { $_.class -eq "blocked" })
$allowedAvg = Average-Of -Rows @($rows | Where-Object { $_.class -eq "allowed" })

$appPercentPerHour = $null
if ($appMah -ne $null -and $estimatedCapacityMah -ne $null -and $estimatedCapacityMah -gt 0 -and $durationHours -gt 0) {
    $appPercentPerHour = [math]::Round((($appMah / $estimatedCapacityMah) * 100.0) / $durationHours, 3)
}

$result = [pscustomobject]@{
    deviceId = $DeviceId
    packageName = $PackageName
    uid = $uid
    uidTag = $uidTag
    startedAtUtc = $startedAtUtc.ToString("o")
    endedAtUtc = $endedAtUtc.ToString("o")
    durationHours = $durationHours
    idleMinutes = $IdleMinutes
    baseline = [pscustomobject]@{
        battery = $baselineBattery
        process = $baselineProc
    }
    afterSweepBattery = $afterSweepBattery
    final = [pscustomobject]@{
        battery = $finalBattery
        process = $finalProc
    }
    estimatedBatteryCapacityMah = $estimatedCapacityMah
    appPowerMah = $appMah
    appPercentPerHourEstimate = $appPercentPerHour
    targetPercentPerHour = 5.0
    targetMet = if ($appPercentPerHour -ne $null) { $appPercentPerHour -lt 5.0 } else { $null }
    dnsLatency = [pscustomobject]@{
        blockedAverageMs = $blockedAvg
        allowedAverageMs = $allowedAvg
        rows = $rows
    }
}

$result | ConvertTo-Json -Depth 7 | Set-Content -Path $OutputJsonPath -Encoding UTF8

Write-Output "STEP=complete report=$OutputJsonPath"
Write-Output "SUMMARY blockedAvgMs=$blockedAvg allowedAvgMs=$allowedAvg appMah=$appMah appPctPerHour=$appPercentPerHour targetMet=$($result.targetMet)"
