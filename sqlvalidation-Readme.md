# Remote Windows and SQL Server Health Capture

Read-only PowerShell capture for one remote Windows Server. It checks ping, RDP, SMB, the SQL TCP port, WinRM, memory, CPU, disk, Remote Desktop, sessions, top processes, recent System warnings and errors, and SQL Server services.

Use it when a server is slow to answer, Remote Desktop is failing, or you need a quick read on whether the SQL host is up before changing anything. It does not remediate. It does not change Windows or SQL configuration, start or stop services, kill processes, touch sessions, or run SQL queries.

Each section runs in its own job with a 30-second timeout. If one remote call hangs, the rest of the capture still runs. The console ends with a pass/fail summary.

## Platform

- Windows PowerShell 5.1
- Run from an admin workstation that can reach the target
- Uses the current account. There is no credential prompt.

OS, CPU, and disk go out through CIM over WinRM. The process list uses `Invoke-Command`. Ping and the port tests do not. A WinRM failure does not mean the server is down.

## What it checks

1. Ping
2. RDP, TCP 3389
3. SMB, TCP 445
4. SQL TCP port, default 1433, unless `$TestSqlPort` is `$false`
5. WinRM
6. Operating system, last boot, free memory
7. CPU name, core count, and load
8. Fixed disks, size and free space
9. Remote Desktop service (`TermService`)
10. RDP listener and sessions (`qwinsta`)
11. User sessions (`quser`)
12. Top 20 processes by CPU time
13. System critical, error, and warning events
14. Services named `MSSQL*`, `SQLAgent*`, or `SQLBrowser*`

SQL coverage is the port and those services. It does not check `SQLWriter`, telemetry, or Reporting Services, and it does not connect to the database.

## How to read a failed section

Ping can time out when ICMP is blocked. Use the port and WinRM lines before calling the server down.

`quser` exits with an error when no one is logged on. Section 11 can show FAILED on an idle server. `qwinsta` is the listener check.

`Get-WinEvent` throws when the filter matches nothing. Section 13 can show FAILED when there are no recent System warnings or errors.

A TIMEOUT means that section did not answer within `$TimeoutSeconds`. It does not stop the capture.

Do not commit or paste a raw capture. Session names, usernames, process lists, and event text are from the target, not from this script.

## Configuration

Set these at the top of the script:

```powershell
$Server             = "SERVER01"
$TestSqlPort        = $true
$SqlPort            = 1433
$TimeoutSeconds     = 30
$EventLookbackHours = 2
$MaximumEvents      = 100
```

## Run

Open the script in Windows PowerShell 5.1, set `$Server`, and run it. Worst case is about seven minutes if every section hits the timeout.
