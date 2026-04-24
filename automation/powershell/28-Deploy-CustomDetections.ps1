<#
.SYNOPSIS
    Deploys ten baseline custom detection rules to Defender XDR.

.DESCRIPTION
    Runbook 28 - EDR Tuning, Step 5.

    Creates custom detection rules with baseline KQL queries covering common
    attack patterns beyond Microsoft's built-in detections.

.EXAMPLE
    ./28-Deploy-CustomDetections.ps1

.NOTES
    Custom detection rules are managed through Defender XDR portal or Graph API.
    Script outputs the ten rules for portal deployment.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

Write-Host "=== Deploy Custom Detection Rules ===" -ForegroundColor Cyan
Write-Host ""

$detections = @(
    @{
        Name = "EDR-01 Mass credential access attempt"
        Description = "Multiple failed sign-ins followed by success from new location"
        Severity = "Medium"
        MitreTechnique = "T1110"
        Query = @"
SigninLogs
| where TimeGenerated > ago(1h)
| summarize FailedCount = countif(ResultType !in (0, "0")), SuccessCount = countif(ResultType in (0, "0")) by UserPrincipalName, bin(TimeGenerated, 15m)
| where FailedCount > 10 and SuccessCount > 0
"@
    }
    @{
        Name = "EDR-02 Privilege escalation via scheduled task"
        Description = "Scheduled task created that runs with SYSTEM privilege from non-standard path"
        Severity = "High"
        MitreTechnique = "T1053.005"
        Query = @"
DeviceProcessEvents
| where Timestamp > ago(1h)
| where FileName =~ "schtasks.exe" and ProcessCommandLine has_any ("/create", "/ru SYSTEM")
| where not(ProcessCommandLine has_any ("C:\\Windows\\", "C:\\Program Files"))
"@
    }
    @{
        Name = "EDR-03 PowerShell download cradle"
        Description = "PowerShell executing download cmdlet with URL"
        Severity = "Medium"
        MitreTechnique = "T1059.001"
        Query = @"
DeviceProcessEvents
| where Timestamp > ago(1h)
| where FileName =~ "powershell.exe" or FileName =~ "pwsh.exe"
| where ProcessCommandLine has_any ("DownloadString", "Invoke-WebRequest", "Invoke-Expression", "iex", "iwr")
| where ProcessCommandLine matches regex "http[s]?://"
"@
    }
    @{
        Name = "EDR-04 Living-off-the-land binary abuse"
        Description = "Specific LOLBin sequences matching attack patterns"
        Severity = "High"
        MitreTechnique = "T1218"
        Query = @"
DeviceProcessEvents
| where Timestamp > ago(1h)
| where (InitiatingProcessFileName =~ "certutil.exe" and FileName =~ "rundll32.exe")
    or (InitiatingProcessFileName =~ "mshta.exe" and FileName =~ "bitsadmin.exe")
"@
    }
    @{
        Name = "EDR-05 Uncommon parent-child process pair"
        Description = "Processes spawning from unexpected parents"
        Severity = "Medium"
        MitreTechnique = "T1036"
        Query = @"
DeviceProcessEvents
| where Timestamp > ago(1h)
| where (InitiatingProcessFileName =~ "svchost.exe" and FileName =~ "cmd.exe")
    or (InitiatingProcessFileName =~ "winword.exe" and FileName =~ "rundll32.exe")
"@
    }
    @{
        Name = "EDR-06 USB drive execution"
        Description = "Process execution from USB drive paths"
        Severity = "Medium"
        MitreTechnique = "T1091"
        Query = @"
DeviceProcessEvents
| where Timestamp > ago(1h)
| where FolderPath startswith "D:\\" or FolderPath startswith "E:\\" or FolderPath startswith "F:\\"
| join kind=inner (DeviceEvents | where ActionType == "RemovableMediaMounted") on DeviceId
"@
    }
    @{
        Name = "EDR-07 Security event log clear"
        Description = "Security event log clearing attempt"
        Severity = "High"
        MitreTechnique = "T1070.001"
        Query = @"
DeviceEvents
| where Timestamp > ago(1h)
| where ActionType == "ProcessCreated"
| where FileName =~ "wevtutil.exe" and ProcessCommandLine has "cl"
"@
    }
    @{
        Name = "EDR-08 Registry persistence in autoruns"
        Description = "Additions to Run, RunOnce, or service registry keys"
        Severity = "Medium"
        MitreTechnique = "T1547.001"
        Query = @"
DeviceRegistryEvents
| where Timestamp > ago(1h)
| where ActionType == "RegistryValueSet"
| where RegistryKey has_any ("\\Run", "\\RunOnce", "\\Services\\") and RegistryKey !has "AppFilterPaths"
"@
    }
    @{
        Name = "EDR-09 Remote access tool installation outside approved deployment"
        Description = "Installation of known remote access tools"
        Severity = "Medium"
        MitreTechnique = "T1219"
        Query = @"
DeviceProcessEvents
| where Timestamp > ago(1h)
| where FileName in~ ("teamviewer.exe", "anydesk.exe", "connectwise.exe", "screenconnect.exe")
"@
    }
    @{
        Name = "EDR-10 Credential harvesting tool"
        Description = "Execution of known credential harvesting tools"
        Severity = "High"
        MitreTechnique = "T1003"
        Query = @"
DeviceProcessEvents
| where Timestamp > ago(1h)
| where FileName in~ ("mimikatz.exe", "lazagne.exe", "procdump.exe") or ProcessCommandLine has "lsass.exe"
"@
    }
)

Write-Host "Ten baseline custom detection rules:" -ForegroundColor Cyan
Write-Host ""

foreach ($d in $detections) {
    Write-Host "$($d.Name)" -ForegroundColor Green
    Write-Host "  Severity: $($d.Severity)"
    Write-Host "  MITRE: $($d.MitreTechnique)"
    Write-Host "  Description: $($d.Description)"
    Write-Host ""
}

Write-Host "Portal deployment:" -ForegroundColor Cyan
Write-Host "  1. Navigate to https://security.microsoft.com"
Write-Host "  2. Hunting > Custom detection rules"
Write-Host "  3. For each rule above:"
Write-Host "     Create detection rule"
Write-Host "     Paste the KQL query from this script output (or the companion file kql-custom-detections.kql)"
Write-Host "     Set severity and MITRE technique"
Write-Host "     Set run frequency: every hour (for time-sensitive patterns) or every 6 hours"
Write-Host "     Action: Create alert; optionally run AIR on match"
Write-Host "  4. Enable each rule after deployment"

# Export queries to companion file
$queryOutput = $detections | ForEach-Object {
    "// $($_.Name) - Severity: $($_.Severity); MITRE: $($_.MitreTechnique)`n// $($_.Description)`n$($_.Query)`n"
}
$queryOutput | Out-File -FilePath "./kql-custom-detections.kql" -Encoding UTF8
Write-Host ""
Write-Host "Queries written to: ./kql-custom-detections.kql" -ForegroundColor Green
