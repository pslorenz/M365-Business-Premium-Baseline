<#
.SYNOPSIS
    Adds a user to the travel exception group for a bounded time window.

.DESCRIPTION
    Runbook 05 - Named Locations and Travel Exception Workflow.
    Applies to: All variants.

    Adds the specified user to the CA-Exclude-Travel-Temporary group. The group is
    excluded from CA006 (country block policy). The exception is logged with end date
    and ticket reference; 05-Review-TravelExceptions.ps1 expires stale entries.

.PARAMETER UserUPN
    The UPN of the user requiring the exception.

.PARAMETER Countries
    Two-letter ISO codes of countries the user will travel to. For logging; does not
    add countries to the allowed list.

.PARAMETER StartDate
    Start of the exception window. Must not be in the past.

.PARAMETER EndDate
    End of the exception window. Must not exceed 30 days from StartDate.

.PARAMETER TicketReference
    Ticket or request reference for audit trail.

.PARAMETER Justification
    Business reason for the travel.

.PARAMETER ExceptionGroupName
    The travel exception group. Default: "CA-Exclude-Travel-Temporary".

.PARAMETER LogPath
    Path to the persistent exception log file. Default: "./travel-exception-log.json".

.EXAMPLE
    ./05-Add-TravelException.ps1 `
        -UserUPN "jane.user@contoso.com" `
        -Countries @("FR", "DE") `
        -StartDate "2026-05-01" `
        -EndDate "2026-05-15" `
        -TicketReference "TRAVEL-1234" `
        -Justification "Client meetings in Paris and Berlin"

.NOTES
    Required Graph scopes:
        Group.ReadWrite.All
        User.Read.All
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$UserUPN,

    [Parameter(Mandatory = $true)]
    [string[]]$Countries,

    [Parameter(Mandatory = $true)]
    [datetime]$StartDate,

    [Parameter(Mandatory = $true)]
    [datetime]$EndDate,

    [Parameter(Mandatory = $true)]
    [string]$TicketReference,

    [Parameter(Mandatory = $true)]
    [string]$Justification,

    [string]$ExceptionGroupName = "CA-Exclude-Travel-Temporary",

    [string]$LogPath = "./travel-exception-log.json"
)

$ErrorActionPreference = "Stop"

$context = Get-MgContext
if (-not $context) { throw "Not connected to Microsoft Graph." }

# Validation
if ($UserUPN -like "breakglass*") {
    throw "Break glass accounts do not require travel exceptions; they are excluded from all CA policies by design."
}

if ($StartDate -lt (Get-Date).Date) {
    throw "Start date is in the past. Travel exceptions must be forward-dated or effective today."
}

$windowDays = ($EndDate - $StartDate).TotalDays
if ($windowDays -gt 30) {
    throw "Exception window is $windowDays days, exceeding the 30-day maximum. Split into multiple exceptions with re-approval, or revisit the allowed-countries list if the travel is recurring."
}

if ($Justification.Length -lt 20) {
    throw "Justification must be at least 20 characters. Document the business purpose of the travel."
}

# Verify user exists
$user = Get-MgUser -Filter "userPrincipalName eq '$UserUPN'" -ErrorAction SilentlyContinue
if (-not $user) { throw "User not found: $UserUPN" }

# Get exception group
$group = Get-MgGroup -Filter "displayName eq '$ExceptionGroupName'" -ErrorAction SilentlyContinue
if (-not $group) { throw "Exception group not found: $ExceptionGroupName. Was Runbook 02 deployment completed?" }

Write-Host "=== Add Travel Exception ===" -ForegroundColor Cyan
Write-Host "User:        $UserUPN"
Write-Host "Countries:   $($Countries -join ', ')"
Write-Host "Start:       $($StartDate.ToString('yyyy-MM-dd'))"
Write-Host "End:         $($EndDate.ToString('yyyy-MM-dd'))"
Write-Host "Window:      $windowDays days"
Write-Host "Ticket:      $TicketReference"
Write-Host ""

# Add to group
$members = Get-MgGroupMember -GroupId $group.Id -All
if ($user.Id -in $members.Id) {
    Write-Host "User is already in the exception group. Existing exception will be overwritten in the log." -ForegroundColor Yellow
} else {
    New-MgGroupMember -GroupId $group.Id `
        -BodyParameter @{ "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($user.Id)" }
    Write-Host "User added to $ExceptionGroupName." -ForegroundColor Green
}

# Log the exception
$exceptionRecord = [PSCustomObject]@{
    UPN              = $UserUPN
    UserId           = $user.Id
    Countries        = $Countries
    StartDate        = $StartDate.ToString("yyyy-MM-dd")
    EndDate          = $EndDate.ToString("yyyy-MM-dd")
    TicketReference  = $TicketReference
    Justification    = $Justification
    AddedAt          = (Get-Date).ToString("o")
    AddedBy          = $context.Account
    Status           = "Active"
}

# Read existing log or create new
$log = @()
if (Test-Path $LogPath) {
    $existing = Get-Content $LogPath -Raw | ConvertFrom-Json
    if ($existing -is [Array]) {
        $log = $existing
    } else {
        $log = @($existing)
    }
}

# Mark any prior entries for this user as superseded
foreach ($entry in $log) {
    if ($entry.UPN -eq $UserUPN -and $entry.Status -eq "Active") {
        $entry.Status = "Superseded"
    }
}

$log += $exceptionRecord
$log | ConvertTo-Json -Depth 5 | Out-File -FilePath $LogPath -Encoding UTF8

Write-Host "Exception logged to $LogPath" -ForegroundColor Green
Write-Host ""
Write-Host "Follow-up: ./05-Review-TravelExceptions.ps1 (run weekly to expire stale entries)" -ForegroundColor Cyan
