param(
    [string]$DeviceId = "aae47d3e",
    [string]$TestFile = "integration_test/real_device_vpn_smoke_test.dart",
    [string[]]$DartDefines = @(
        "TB_ROLE=start_blocking",
        "TB_BLOCKED_DOMAIN=instagram.com"
    ),
    [int]$TimeoutMinutes = 7
)

$ErrorActionPreference = "Stop"
$logFile = "tmp_vpn_start_blocking.log"
if (Test-Path $logFile) {
    Remove-Item $logFile -Force
}

$resolvedDefines = @($DartDefines)
if ($resolvedDefines.Count -eq 1 -and $resolvedDefines[0].Contains(",")) {
    $resolvedDefines = $resolvedDefines[0].Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
}

$defineArgs = $resolvedDefines | ForEach-Object { "--dart-define=$_" }
$allArgs = @("test", $TestFile, "-d", $DeviceId) + $defineArgs
$argsString = ($allArgs -join " ")
$cmd = "flutter $argsString > `"$logFile`" 2>&1"
Write-Output "RUN_CMD=$cmd"
$proc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $cmd -PassThru

$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
$activeTapUntil = (Get-Date).AddMinutes(3)
$tapCount = 0

while ((Get-Date) -lt $deadline -and -not $proc.HasExited) {
    if ((Get-Date) -ge $activeTapUntil) {
        Start-Sleep -Seconds 5
        continue
    }

    adb -s $DeviceId shell input keyevent 224 | Out-Null
    adb -s $DeviceId shell uiautomator dump /sdcard/uidump.xml | Out-Null
    $dump = adb -s $DeviceId shell cat /sdcard/uidump.xml 2>$null
    $clicked = $false

    if ($dump) {
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
                $tapCount++
                $clicked = $true
            }
        } else {
            $x1 = [int]$match.Groups[1].Value
            $y1 = [int]$match.Groups[2].Value
            $x2 = [int]$match.Groups[3].Value
            $y2 = [int]$match.Groups[4].Value
            $x = [int](($x1 + $x2) / 2)
            $y = [int](($y1 + $y2) / 2)
            adb -s $DeviceId shell input tap $x $y | Out-Null
            $tapCount++
            $clicked = $true
        }
    }

    if (-not $clicked) {
        adb -s $DeviceId shell input keyevent 66 | Out-Null
    }
    Start-Sleep -Milliseconds 900
}

if (-not $proc.HasExited) {
    try {
        $proc.Kill()
    } catch {
    }
}

$exitCode = if ($proc.HasExited) { $proc.ExitCode } else { 124 }
Write-Output "AUTOMATION_TAPS=$tapCount"
if (Test-Path $logFile) {
    Get-Content $logFile
}
exit $exitCode
