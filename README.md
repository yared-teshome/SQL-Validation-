Remote Windows and SQL Server Health Capture
Overview
Remote Windows and SQL Server Health Capture is a read-only Windows PowerShell diagnostic utility designed to collect health, connectivity, resource, Remote Desktop, event, and SQL Server service information from a remote Windows Server.

The tool is intended to provide Systems Administrators with a single diagnostic capture when investigating server responsiveness, Remote Desktop issues, resource concerns, network connectivity, or SQL Server host availability.

The script does not perform remediation or intentionally modify the target server.

Purpose
The primary purpose of this utility is to quickly answer questions such as:

Is the server reachable?
Are common management and application ports reachable?
Is PowerShell remoting responding?
Is the server experiencing memory or disk pressure?
What CPU information is being reported?
Is Remote Desktop Services running?
Are RDP listeners and user sessions present?
Which processes have accumulated the most CPU time?
Are recent System warnings or errors present?
Are SQL Server-related Windows services installed and running?
Is the configured SQL TCP port reachable?
Each diagnostic section is independently timed to reduce the possibility that one unresponsive remote operation prevents the remaining assessment from completing.

Operating Mode
READ-ONLY DIAGNOSTIC

The script is designed to collect information only.

It does not intentionally:

Change Windows configuration
Change SQL Server configuration
Start or stop services
Restart services
Terminate processes
Disconnect Remote Desktop sessions
Reset Remote Desktop sessions
Log off users
Delete files
Modify registry settings
Execute SQL queries
Compatibility
Designed for:

Windows PowerShell 5.1
Windows Server environments
Remote administrative troubleshooting
Individual checks depend on the management interfaces and permissions available on the target server.

Configuration
Configuration is maintained at the beginning of the PowerShell script.

$Server = "A"
$TestSqlPort = $true
$SqlPort = 1433
$TimeoutSeconds = 30
$EventLookbackHours = 2
$MaximumEvents = 100
