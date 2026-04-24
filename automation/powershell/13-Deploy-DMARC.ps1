<#
.SYNOPSIS
    Generates a DMARC record for DNS publication.

.DESCRIPTION
    Runbook 13 - SPF, DKIM, and DMARC Email Authentication, Step 4.
    Applies to: All variants.

    Produces the DMARC record text for the specified domain. Does NOT publish to
    DNS; the output is the record text for the domain's DNS administrator.

.PARAMETER Domain
    Sending domain.

.PARAMETER Policy
    none, quarantine, or reject.

    none        - Initial deployment; monitors without enforcement. Start here.
    quarantine  - Receiving systems junk/quarantine failing mail.
    reject      - Receiving systems reject failing mail. Final target.

.PARAMETER SubdomainPolicy
    Policy for subdomains. Default: same as main policy.

.PARAMETER AggregateReportAddress
    rua= destination for aggregate reports. Required.

.PARAMETER FailureReportAddress
    ruf= destination for per-message failure reports. Optional.

.PARAMETER Percentage
    pct= value. Default: 100.

.PARAMETER StrictAlignment
    If set, uses adkim=s and aspf=s (strict alignment). Appropriate for p=reject phase.

.EXAMPLE
    ./13-Deploy-DMARC.ps1 `
        -Domain "contoso.com" `
        -Policy "none" `
        -AggregateReportAddress "dmarc-reports@contoso.com" `
        -FailureReportAddress "dmarc-failures@contoso.com"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Domain,

    [Parameter(Mandatory = $true)]
    [ValidateSet("none", "quarantine", "reject")]
    [string]$Policy,

    [ValidateSet("none", "quarantine", "reject")]
    [string]$SubdomainPolicy,

    [Parameter(Mandatory = $true)]
    [string]$AggregateReportAddress,

    [string]$FailureReportAddress,

    [ValidateRange(0, 100)]
    [int]$Percentage = 100,

    [switch]$StrictAlignment
)

$ErrorActionPreference = "Stop"

if (-not $SubdomainPolicy) { $SubdomainPolicy = $Policy }

Write-Host "=== Generate DMARC Record ===" -ForegroundColor Cyan
Write-Host "Domain: $Domain"
Write-Host "Policy: $Policy"
Write-Host ""

$parts = @("v=DMARC1", "p=$Policy")

if ($SubdomainPolicy -ne $Policy) {
    $parts += "sp=$SubdomainPolicy"
}

$parts += "pct=$Percentage"
$parts += "rua=mailto:$AggregateReportAddress"

if ($FailureReportAddress) {
    $parts += "ruf=mailto:$FailureReportAddress"
    $parts += "fo=1"   # Generate reports on any authentication failure
}

if ($StrictAlignment) {
    $parts += "adkim=s"
    $parts += "aspf=s"
}

# rf=afrf is standard format for failure reports
if ($FailureReportAddress) {
    $parts += "rf=afrf"
}

$record = $parts -join "; "

Write-Host "Generated DMARC record:" -ForegroundColor Green
Write-Host ""
Write-Host "  Name:    _dmarc.$Domain" -ForegroundColor White
Write-Host "  Type:    TXT"
Write-Host "  Value:   $record"
Write-Host ""

if ($Policy -eq "none") {
    Write-Host "This is the initial monitoring state. Observe for 30 to 60 days before tightening to quarantine." -ForegroundColor Yellow
} elseif ($Policy -eq "quarantine") {
    Write-Host "Monitoring state: receivers will junk or quarantine failing mail." -ForegroundColor Yellow
} elseif ($Policy -eq "reject") {
    Write-Host "Enforcement state: receivers will reject failing mail. Ensure SPF and DKIM are fully aligned first." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Publish the TXT record in DNS. Verify with: nslookup -type=txt _dmarc.$Domain" -ForegroundColor Cyan

[PSCustomObject]@{
    Domain = $Domain
    RecordName = "_dmarc.$Domain"
    Record = $record
    Policy = $Policy
}
