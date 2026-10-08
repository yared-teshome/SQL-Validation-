<#
Remote Windows and SQL Server health capture.
PowerShell 5.1 compatible and read-only.
Change only the values in the CONFIGURATION section.
Each diagnostic section has a 30-second timeout.
#>

# CONFIGURATION
$Server = "A"
$TestSqlPort = $true
$SqlPort = 1433
$TimeoutSeconds = 30
$EventLookbackHours = 2
$MaximumEvents = 100

# INTERNAL VARIABLES
$ScriptStartTime = Get-Date
$Results = New-Object System.Collections.ArrayList

function Invoke-TimedCheck {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Code,

        [object[]]$Arguments = @(),

        [int]$Timeout = 30
    )

    Write-Host ""
    Write-Host "=== $Name ===" -ForegroundColor Yellow

    $Job = $null
    $CheckStartTime = Get-Date
    $Status = "FAILED"
    $Details = "The check did not complete."
    $ElapsedSeconds = 0

    try {
        $Job = Start-Job -ScriptBlock $Code -ArgumentList $Arguments -ErrorAction Stop
        $CompletedJob = Wait-Job -Job $Job -Timeout $Timeout
        $ElapsedSeconds = "{0:N2}" -f (((Get-Date) - $CheckStartTime).TotalSeconds)

        if ($null -eq $CompletedJob) {
            $Status = "TIMEOUT"
            $Details = "No response within $Timeout seconds."
            Write-Warning "[$Status] $Name - $Details"
            Stop-Job -Job $Job -ErrorAction SilentlyContinue
        }
        elseif ($Job.State -eq "Failed") {
            $Status = "FAILED"
            $Reason = $Job.ChildJobs[0].JobStateInfo.Reason

            if ($null -ne $Reason) {
                $Details = $Reason.Message
            }
            else {
                $Details = "The background job failed."
            }

            Write-Warning "[$Status] $Name - $Details"
        }
        else {
            $Output = @(Receive-Job -Job $Job -ErrorAction SilentlyContinue)

            if ($Output.Count -gt 0) {
                $Output
                $Status = "COMPLETED"
                $Details = "Output returned."
                Write-Host "[$Status] $ElapsedSeconds seconds" -ForegroundColor Green
            }
            else {
                $Status = "NO DATA"
                $Details = "The check completed without output."
                Write-Warning "[$Status] $Name - $Details"
            }
        }
    }
    catch {
        $ElapsedSeconds = "{0:N2}" -f (((Get-Date) - $CheckStartTime).TotalSeconds)
        $Status = "FAILED"
        $Details = $_.Exception.Message
        Write-Warning "[$Status] $Name - $Details"
    }
    finally {
        if ($null -ne $Job) {
            Stop-Job -Job $Job -ErrorAction SilentlyContinue
            Remove-Job -Job $Job -Force -ErrorAction SilentlyContinue
        }
    }

    $Result = New-Object PSObject -Property @{
        Section = $Name
        Status = $Status
        Seconds = $ElapsedSeconds
        Details = $Details
    }

    [void]$Results.Add($Result)
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " REMOTE WINDOWS / SQL SERVER HEALTH CAPTURE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Server          : $Server"
Write-Host "Start Time      : $ScriptStartTime"
Write-Host "Timeout         : $TimeoutSeconds seconds"
Write-Host "SQL Port Test   : $TestSqlPort"
Write-Host "SQL Port        : $SqlPort"
Write-Host "Event Lookback  : $EventLookbackHours hours"
Write-Host "Maximum Events  : $MaximumEvents"
Write-Host "Mode            : READ-ONLY"
Write-Host "============================================================" -ForegroundColor Cyan

Invoke-TimedCheck -Name "1. PING TEST" -Timeout $TimeoutSeconds -Arguments @($Server) -Code {
    param([string]$TargetServer)

    Test-Connection -ComputerName $TargetServer -Count 4 -ErrorAction Stop |
        Select-Object Address, ResponseTime, StatusCode |
        Format-Table -AutoSize |
        Out-String
}

Invoke-TimedCheck -Name "2. RDP TCP PORT 3389" -Timeout $TimeoutSeconds -Arguments @($Server) -Code {
    param([string]$TargetServer)

    Test-NetConnection -ComputerName $TargetServer -Port 3389 -InformationLevel Detailed -WarningAction SilentlyContinue |
        Out-String
}

Invoke-TimedCheck -Name "3. SMB TCP PORT 445" -Timeout $TimeoutSeconds -Arguments @($Server) -Code {
    param([string]$TargetServer)

    Test-NetConnection -ComputerName $TargetServer -Port 445 -InformationLevel Detailed -WarningAction SilentlyContinue |
        Out-String
}

if ($TestSqlPort) {
    Invoke-TimedCheck -Name "4. SQL TCP PORT $SqlPort" -Timeout $TimeoutSeconds -Arguments @($Server, $SqlPort) -Code {
        param([string]$TargetServer, [int]$TargetPort)

        Test-NetConnection -ComputerName $TargetServer -Port $TargetPort -InformationLevel Detailed -WarningAction SilentlyContinue |
            Out-String
    }
}
else {
    Write-Host ""
    Write-Host "=== 4. SQL TCP PORT ===" -ForegroundColor Yellow
    Write-Host "[SKIPPED] SQL port testing is disabled." -ForegroundColor DarkYellow

    $SkippedResult = New-Object PSObject -Property @{
        Section = "4. SQL TCP PORT"
        Status = "SKIPPED"
        Seconds = 0
        Details = "SQL port testing is disabled."
    }

    [void]$Results.Add($SkippedResult)
}

Invoke-TimedCheck -Name "5. WINRM" -Timeout $TimeoutSeconds -Arguments @($Server) -Code {
    param([string]$TargetServer)

    Test-WSMan -ComputerName $TargetServer -ErrorAction Stop |
        Format-List |
        Out-String
}

Invoke-TimedCheck -Name "6. OPERATING SYSTEM AND MEMORY" -Timeout $TimeoutSeconds -Arguments @($Server) -Code {
    param([string]$TargetServer)

    $OS = Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $TargetServer -ErrorAction Stop
    $FreeMemoryPercent = $null

    if ($OS.TotalVisibleMemorySize -gt 0) {
        $FreeMemoryPercent = "{0:N2}" -f (($OS.FreePhysicalMemory / $OS.TotalVisibleMemorySize) * 100)
    }

    $OSResult = New-Object PSObject -Property @{
        ComputerName = $OS.CSName
        OperatingSystem = $OS.Caption
        Version = $OS.Version
        LastBootUpTime = $OS.LastBootUpTime
        TotalMemoryGB = "{0:N2}" -f ($OS.TotalVisibleMemorySize / 1MB)
        FreeMemoryGB = "{0:N2}" -f ($OS.FreePhysicalMemory / 1MB)
        FreeMemoryPercent = $FreeMemoryPercent
    }

    $OSResult | Format-List | Out-String
}

Invoke-TimedCheck -Name "7. CPU" -Timeout $TimeoutSeconds -Arguments @($Server) -Code {
    param([string]$TargetServer)

    Get-CimInstance -ClassName Win32_Processor -ComputerName $TargetServer -ErrorAction Stop |
        Select-Object Name, NumberOfCores, NumberOfLogicalProcessors, LoadPercentage |
        Format-Table -AutoSize |
        Out-String
}

Invoke-TimedCheck -Name "8. DISK CAPACITY" -Timeout $TimeoutSeconds -Arguments @($Server) -Code {
    param([string]$TargetServer)

    $Disks = Get-CimInstance -ClassName Win32_LogicalDisk -ComputerName $TargetServer -Filter "DriveType=3" -ErrorAction Stop

    $DiskResults = foreach ($Disk in $Disks) {
        $FreePercent = $null

        if ($Disk.Size -gt 0) {
            $FreePercent = "{0:N2}" -f (($Disk.FreeSpace / $Disk.Size) * 100)
        }

        New-Object PSObject -Property @{
            Drive = $Disk.DeviceID
            VolumeName = $Disk.VolumeName
            SizeGB = "{0:N2}" -f ($Disk.Size / 1GB)
            FreeGB = "{0:N2}" -f ($Disk.FreeSpace / 1GB)
            FreePercent = $FreePercent
        }
    }

    $DiskResults |
        Select-Object Drive, VolumeName, SizeGB, FreeGB, FreePercent |
        Format-Table -AutoSize |
        Out-String
}

Invoke-TimedCheck -Name "9. REMOTE DESKTOP SERVICE" -Timeout $TimeoutSeconds -Arguments @($Server) -Code {
    param([string]$TargetServer)

    Get-Service -ComputerName $TargetServer -Name TermService -ErrorAction Stop |
        Select-Object MachineName, Name, DisplayName, Status, StartType |
        Format-Table -AutoSize |
        Out-String
}

Invoke-TimedCheck -Name "10. RDP LISTENER AND SESSIONS" -Timeout $TimeoutSeconds -Arguments @($Server) -Code {
    param([string]$TargetServer)

    $CommandOutput = @(
        & "$env:SystemRoot\System32\qwinsta.exe" "/server:$TargetServer" 2>&1
    )

    if ($LASTEXITCODE -ne 0) {
        $ErrorText = $CommandOutput -join " "
        throw "QWINSTA failed with exit code $LASTEXITCODE. $ErrorText"
    }

    $CommandOutput | Out-String
}

Invoke-TimedCheck -Name "11. USER SESSIONS" -Timeout $TimeoutSeconds -Arguments @($Server) -Code {
    param([string]$TargetServer)

    $CommandOutput = @(
        & "$env:SystemRoot\System32\quser.exe" "/server:$TargetServer" 2>&1
    )

    if ($LASTEXITCODE -ne 0) {
        $ErrorText = $CommandOutput -join " "
        throw "QUSER failed with exit code $LASTEXITCODE. $ErrorText"
    }

    $CommandOutput | Out-String
}

Invoke-TimedCheck -Name "12. TOP 20 PROCESSES BY CPU" -Timeout $TimeoutSeconds -Arguments @($Server) -Code {
    param([string]$TargetServer)

    $Processes = Invoke-Command -ComputerName $TargetServer -ErrorAction Stop -ScriptBlock {
        Get-Process |
            Sort-Object CPU -Descending |
            Select-Object -First 20
    }

    $ProcessResults = foreach ($Process in $Processes) {
        $CPUSeconds = $null

        if ($null -ne $Process.CPU) {
            $CPUSeconds = "{0:N2}" -f $Process.CPU
        }

        New-Object PSObject -Property @{
            ProcessName = $Process.ProcessName
            Id = $Process.Id
            CPUSeconds = $CPUSeconds
            WorkingSetMB = "{0:N2}" -f ($Process.WorkingSet64 / 1MB)
            PrivateMemoryMB = "{0:N2}" -f ($Process.PrivateMemorySize64 / 1MB)
        }
    }

    $ProcessResults |
        Select-Object ProcessName, Id, CPUSeconds, WorkingSetMB, PrivateMemoryMB |
        Format-Table -AutoSize |
        Out-String
}

Invoke-TimedCheck -Name "13. SYSTEM WARNINGS AND ERRORS" -Timeout $TimeoutSeconds -Arguments @($Server, $EventLookbackHours, $MaximumEvents) -Code {
    param([string]$TargetServer, [int]$LookbackHours, [int]$EventLimit)

    $EventStartTime = (Get-Date).AddHours(-$LookbackHours)

    $Events = @(
        Get-WinEvent -ComputerName $TargetServer -FilterHashtable @{
            LogName = "System"
            Level = 1, 2, 3
            StartTime = $EventStartTime
        } -ErrorAction Stop |
            Select-Object -First $EventLimit
    )

    if ($Events.Count -eq 0) {
        "No matching System events were found."
    }
    else {
        $Events |
            Select-Object TimeCreated, ProviderName, Id, LevelDisplayName, Message |
            Format-List |
            Out-String
    }
}

Invoke-TimedCheck -Name "14. SQL-RELATED SERVICES" -Timeout $TimeoutSeconds -Arguments @($Server) -Code {
    param([string]$TargetServer)

    $Services = Get-Service -ComputerName $TargetServer -ErrorAction Stop

    $SQLServices = @(
        $Services |
            Where-Object {
                ($_.Name -like "MSSQL*") -or
                ($_.Name -like "SQLAgent*") -or
                ($_.Name -like "SQLBrowser*")
            }
    )

    if ($SQLServices.Count -eq 0) {
        "No SQL-related services were found."
    }
    else {
        $SQLServices |
            Select-Object MachineName, Name, DisplayName, Status, StartType |
            Format-Table -AutoSize |
            Out-String
    }
}

$EndTime = Get-Date
$TotalSeconds = "{0:N2}" -f (($EndTime - $ScriptStartTime).TotalSeconds)

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " DIAGNOSTIC RESULT SUMMARY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Results |
    Select-Object Section, Status, Seconds, Details |
    Format-Table -AutoSize

$Problems = @(
    $Results |
        Where-Object {
            ($_.Status -eq "TIMEOUT") -or
            ($_.Status -eq "FAILED") -or
            ($_.Status -eq "NO DATA")
        }
)

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " TIMEOUTS, FAILURES, AND NO DATA" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

if ($Problems.Count -gt 0) {
    $Problems |
        Select-Object Section, Status, Seconds, Details |
        Format-Table -AutoSize
}
else {
    Write-Host "No checks timed out, failed, or returned no data." -ForegroundColor Green
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " REMOTE HEALTH CAPTURE COMPLETE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Server          : $Server"
Write-Host "Start Time      : $ScriptStartTime"
Write-Host "Completion Time : $EndTime"
Write-Host "Total Duration  : $TotalSeconds seconds"
Write-Host "Section Timeout : $TimeoutSeconds seconds"
Write-Host ""
Write-Host "No configuration changes were made." -ForegroundColor Green
Write-Host "No services were restarted or stopped." -ForegroundColor Green
Write-Host "No processes were terminated." -ForegroundColor Green
Write-Host "No user sessions were disconnected, reset, or logged off." -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
