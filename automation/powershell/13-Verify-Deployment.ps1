<#
.SYNOPSIS
    Verifies Runbook 13 (SPF, DKIM, DMARC) deployment state for all tenant domains.

.DESCRIPTION
    End-to-end verification: iterates accepted domains and checks SPF, DKIM, and
    DMARC records for each.

.PARAMETER Domain
    Optional; verify a specific domain only. If omitted, all accepted domains.

.EXAMPLE
    ./13-Verify-Deployment.ps1

.EXAMPLE
    ./13-Verify-Deployment.ps1 -Domain "contoso.com"
#>

[CmdletBinding()]
param(
    [string]$Domain
)

$ErrorActionPreference = "Stop"

try {
    $null = Get-OrganizationConfig -ErrorAction Stop
} catch {
    throw "Not connected to Exchange Online."
}

$domainsToCheck = if ($Domain) {
    @([PSCustomObject]@{ DomainName = $Domain })
} else {
    Get-AcceptedDomain | Where-Object { $_.DomainType -eq "Authoritative" }
}

Write-Host "=== Runbook 13 Verification ===" -ForegroundColor Cyan
Write-Host "Domains to check: $($domainsToCheck.Count)"
Write-Host ""

$allPass = $true
$results = @()

foreach ($d in $domainsToCheck) {
    $dName = $d.DomainName
    $domainResult = [PSCustomObject]@{
        Domain = $dName
        SPF = "?"
        DKIM = "?"
        DMARC = "?"
        DMARCPolicy = ""
        OverallStatus = ""
    }

    # SPF
    try {
        $spf = Resolve-DnsName -Name $dName -Type TXT -ErrorAction Stop |
            Where-Object { $_.Strings -match "^v=spf1" }
        if ($spf) {
            $spfStr = $spf.Strings -join ""
            if ($spfStr -match "-all") {
                $domainResult.SPF = "PASS (-all)"
            } elseif ($spfStr -match "~all") {
                $domainResult.SPF = "SOFT (~all)"
                $allPass = $false
            } else {
                $domainResult.SPF = "WEAK"
                $allPass = $false
            }
        } else {
            $domainResult.SPF = "MISSING"
            $allPass = $false
        }
    } catch {
        $domainResult.SPF = "ERROR"
    }

    # DKIM
    try {
        $dkim = Get-DkimSigningConfig -Identity $dName -ErrorAction SilentlyContinue
        if ($dkim -and $dkim.Enabled) {
            $keySize = if ($dkim.PSObject.Properties.Name -contains "Selector1KeySize") { $dkim.Selector1KeySize } else { "?" }
            if ($keySize -ge 2048) {
                $domainResult.DKIM = "PASS ($keySize-bit)"
            } else {
                $domainResult.DKIM = "WEAK ($keySize-bit)"
                $allPass = $false
            }
        } else {
            $domainResult.DKIM = "DISABLED"
            $allPass = $false
        }
    } catch {
        $domainResult.DKIM = "ERROR"
    }

    # DMARC
    try {
        $dmarc = Resolve-DnsName -Name "_dmarc.$dName" -Type TXT -ErrorAction SilentlyContinue |
            Where-Object { $_.Strings -match "^v=DMARC1" }
        if ($dmarc) {
            $dmarcStr = $dmarc.Strings -join ""
            if ($dmarcStr -match "p=(\w+)") {
                $policy = $matches[1]
                $domainResult.DMARCPolicy = $policy
                if ($policy -eq "reject") {
                    $domainResult.DMARC = "PASS (reject)"
                } elseif ($policy -eq "quarantine") {
                    $domainResult.DMARC = "PROGRESSING (quarantine)"
                } else {
                    $domainResult.DMARC = "MONITORING (none)"
                }
            }
        } else {
            $domainResult.DMARC = "MISSING"
            $allPass = $false
        }
    } catch {
        $domainResult.DMARC = "ERROR"
    }

    $domainResult.OverallStatus = if (
        $domainResult.SPF -like "PASS*" -and
        $domainResult.DKIM -like "PASS*" -and
        $domainResult.DMARCPolicy -in @("quarantine", "reject")
    ) { "OK" } else { "In Progress" }

    $results += $domainResult
}

$results | Format-Table -AutoSize

Write-Host ""
if ($allPass) {
    Write-Host "All domains at baseline." -ForegroundColor Green
    exit 0
} else {
    Write-Host "One or more domains have work remaining." -ForegroundColor Yellow
    exit 1
}
