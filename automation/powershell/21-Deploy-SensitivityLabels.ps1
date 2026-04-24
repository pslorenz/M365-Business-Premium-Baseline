<#
.SYNOPSIS
    Deploys the five-label taxonomy (Public, General, Internal, Confidential, Highly Confidential).

.DESCRIPTION
    Runbook 21 - Sensitivity Labels Baseline, Step 2.

    Creates the five baseline labels with configured protection. Encryption enforcement
    requires Purview Suite or E5 Compliance; Plain BP tenants can still deploy the labels
    for classification without encryption by setting -EnableEncryption $false.

.PARAMETER EnableEncryption
    Apply encryption to Confidential and Highly Confidential labels. Default: true.

.PARAMETER ConfidentialGroups
    Groups with access to Confidential-labeled content. Default: "All Employees" group UPN or ObjectId.

.PARAMETER HighlyConfidentialGroups
    Groups with access to Highly Confidential content. Restricted subset.

.EXAMPLE
    ./21-Deploy-SensitivityLabels.ps1 -EnableEncryption $true -HighlyConfidentialGroups @("Executives")

.NOTES
    Required: Connect-IPPSSession.
#>

[CmdletBinding()]
param(
    [bool]$EnableEncryption = $true,

    [string[]]$ConfidentialGroups = @(),

    [string[]]$HighlyConfidentialGroups = @()
)

$ErrorActionPreference = "Stop"

$ippsAvailable = Get-Command New-Label -ErrorAction SilentlyContinue
if (-not $ippsAvailable) { throw "Run Connect-IPPSSession first." }

Write-Host "=== Deploy Sensitivity Labels ===" -ForegroundColor Cyan
Write-Host "Encryption enforcement: $EnableEncryption"
Write-Host ""

function New-OrUpdateLabel {
    param([string]$Name, [hashtable]$Params)

    $existing = Get-Label -Identity $Name -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "  Updating: $Name" -ForegroundColor Yellow
        $Params.Remove("Name") | Out-Null
        $Params["Identity"] = $Name
        Set-Label @Params | Out-Null
    } else {
        Write-Host "  Creating: $Name" -ForegroundColor Cyan
        New-Label @Params | Out-Null
    }
}

# Label 1: Public
New-OrUpdateLabel -Name "Public" -Params @{
    Name = "Public"
    DisplayName = "Public"
    Tooltip = "Content approved for public disclosure. No protection applied."
    ContentType = "File, Email, Site, UnifiedGroup, SchematizedData, PurviewAssets"
    ApplyContentMarkingFooterEnabled = $true
    ApplyContentMarkingFooterText = "Public"
    ApplyContentMarkingFooterAlignment = "Center"
    ApplyContentMarkingFooterFontSize = 10
}

# Label 2: General (Default)
New-OrUpdateLabel -Name "General" -Params @{
    Name = "General"
    DisplayName = "General"
    Tooltip = "Ordinary business content with no specific sensitivity. Default for most communications."
    ContentType = "File, Email, Site, UnifiedGroup, SchematizedData, PurviewAssets"
}

# Label 3: Internal
New-OrUpdateLabel -Name "Internal" -Params @{
    Name = "Internal"
    DisplayName = "Internal"
    Tooltip = "For employees and contracted partners only. Not for public disclosure."
    ContentType = "File, Email, Site, UnifiedGroup, SchematizedData, PurviewAssets"
    ApplyContentMarkingHeaderEnabled = $true
    ApplyContentMarkingHeaderText = "Internal - Do Not Distribute Externally"
    ApplyContentMarkingHeaderAlignment = "Center"
    ApplyContentMarkingHeaderFontSize = 10
}

# Label 4: Confidential
$confidentialParams = @{
    Name = "Confidential"
    DisplayName = "Confidential"
    Tooltip = "Business-sensitive content. Disclosure would cause meaningful harm."
    ContentType = "File, Email, Site, UnifiedGroup, SchematizedData, PurviewAssets"
    ApplyContentMarkingHeaderEnabled = $true
    ApplyContentMarkingHeaderText = "CONFIDENTIAL"
    ApplyContentMarkingHeaderAlignment = "Center"
    ApplyContentMarkingHeaderFontSize = 12
    ApplyContentMarkingHeaderFontColor = "#C00000"
    ApplyContentMarkingFooterEnabled = $true
    ApplyContentMarkingFooterText = "Confidential - Handle Per Company Policy"
    ApplyContentMarkingFooterAlignment = "Center"
    ApplyContentMarkingFooterFontSize = 10
    ApplyWaterMarkingEnabled = $true
    ApplyWaterMarkingText = "CONFIDENTIAL"
}

if ($EnableEncryption) {
    $confidentialParams["EncryptionEnabled"] = $true
    $confidentialParams["EncryptionProtectionType"] = "Template"
    $confidentialParams["EncryptionContentExpiredOnDateInDaysOrNever"] = "Never"
    $confidentialParams["EncryptionOfflineAccessDays"] = 30

    if ($ConfidentialGroups.Count -gt 0) {
        $confidentialParams["EncryptionRightsDefinitions"] = ($ConfidentialGroups | ForEach-Object { "$_`:VIEW,VIEWRIGHTSDATA,DOCEDIT,EDIT,PRINT,REPLY,REPLYALL,FORWARD" }) -join ";"
    } else {
        $confidentialParams["EncryptionRightsDefinitions"] = "AuthenticatedUsers:VIEW,VIEWRIGHTSDATA,DOCEDIT,EDIT,PRINT,REPLY,REPLYALL,FORWARD"
    }
}

New-OrUpdateLabel -Name "Confidential" -Params $confidentialParams

# Label 5: Highly Confidential
$highlyConfidentialParams = @{
    Name = "HighlyConfidential"
    DisplayName = "Highly Confidential"
    Tooltip = "Extremely sensitive. Disclosure would cause serious organizational harm."
    ContentType = "File, Email, Site, UnifiedGroup, SchematizedData, PurviewAssets"
    ApplyContentMarkingHeaderEnabled = $true
    ApplyContentMarkingHeaderText = "HIGHLY CONFIDENTIAL - RESTRICTED"
    ApplyContentMarkingHeaderAlignment = "Center"
    ApplyContentMarkingHeaderFontSize = 14
    ApplyContentMarkingHeaderFontColor = "#C00000"
    ApplyContentMarkingFooterEnabled = $true
    ApplyContentMarkingFooterText = "Highly Confidential - Named Recipients Only"
    ApplyContentMarkingFooterAlignment = "Center"
    ApplyContentMarkingFooterFontSize = 10
    ApplyWaterMarkingEnabled = $true
    ApplyWaterMarkingText = "HIGHLY CONFIDENTIAL"
}

if ($EnableEncryption) {
    $highlyConfidentialParams["EncryptionEnabled"] = $true
    $highlyConfidentialParams["EncryptionProtectionType"] = "Template"
    $highlyConfidentialParams["EncryptionContentExpiredOnDateInDaysOrNever"] = "Never"
    $highlyConfidentialParams["EncryptionOfflineAccessDays"] = 7

    if ($HighlyConfidentialGroups.Count -gt 0) {
        # Highly Confidential: View + Edit only; no print, no forward
        $highlyConfidentialParams["EncryptionRightsDefinitions"] = ($HighlyConfidentialGroups | ForEach-Object { "$_`:VIEW,VIEWRIGHTSDATA,EDIT,DOCEDIT" }) -join ";"
    } else {
        # Default: authenticated users only
        $highlyConfidentialParams["EncryptionRightsDefinitions"] = "AuthenticatedUsers:VIEW,VIEWRIGHTSDATA,EDIT,DOCEDIT"
    }
}

New-OrUpdateLabel -Name "HighlyConfidential" -Params $highlyConfidentialParams

Write-Host ""
Write-Host "Baseline labels deployed." -ForegroundColor Green
Write-Host ""
Write-Host "Next: publish the labels to users with ./21-Deploy-LabelPolicy.ps1" -ForegroundColor Cyan
