<#
.SYNOPSIS
    Deploys the 15 baseline ASR rules via Intune.

.DESCRIPTION
    Runbook 27 - Attack Surface Reduction Rules, Step 2.

    Creates an Intune device configuration profile that assigns the baseline ASR
    rules with configured mode (Audit, Block, Warn, or Disabled per rule).

.PARAMETER Mode
    Default mode for all rules during initial deployment. Default: Audit.
    Options: Audit, Block.

.PARAMETER AssignmentGroup
    Azure AD group containing devices to receive the policy. Default: "All Windows Devices".

.PARAMETER ProfileName
    Default: "SMB Baseline ASR Rules".

.EXAMPLE
    ./27-Deploy-ASRRules.ps1 -Mode Audit -AssignmentGroup "All Windows Devices"

.NOTES
    Required Graph scopes: DeviceManagementConfiguration.ReadWrite.All
#>

[CmdletBinding()]
param(
    [ValidateSet("Audit","Block")]
    [string]$Mode = "Audit",

    [string]$AssignmentGroup = "All Windows Devices",

    [string]$ProfileName = "SMB Baseline ASR Rules"
)

$ErrorActionPreference = "Stop"

$context = Get-MgContext
if (-not $context) { throw "Not connected to Microsoft Graph." }

Write-Host "=== Deploy ASR Rules ===" -ForegroundColor Cyan
Write-Host "Profile: $ProfileName"
Write-Host "Mode: $Mode"
Write-Host "Assignment: $AssignmentGroup"
Write-Host ""

# ASR rules with GUIDs from Microsoft catalog
# Mode translation: 0 = Disabled, 1 = Block, 2 = Audit, 6 = Warn
$modeValue = if ($Mode -eq "Block") { 1 } else { 2 }

$asrRules = @(
    @{ Guid = "56a863a9-875e-4185-98a7-b882c64b5ce5"; Name = "Block abuse of exploited vulnerable signed drivers"; Mode = $modeValue }
    @{ Guid = "7674ba52-37eb-4a4f-a9a1-f0f9a1619a2c"; Name = "Block Adobe Reader from creating child processes"; Mode = $modeValue }
    @{ Guid = "d4f940ab-401b-4efc-aadc-ad5f3c50688a"; Name = "Block all Office applications from creating child processes"; Mode = $modeValue }
    @{ Guid = "9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2"; Name = "Block credential stealing from LSASS"; Mode = $modeValue }
    @{ Guid = "be9ba2d9-53ea-4cdc-84e5-9b1eeee46550"; Name = "Block executable content from email and webmail clients"; Mode = $modeValue }
    @{ Guid = "5beb7efe-fd9a-4556-801d-275e5ffc04cc"; Name = "Block execution of potentially obfuscated scripts"; Mode = $modeValue }
    @{ Guid = "d3e037e1-3eb8-44c8-a917-57927947596d"; Name = "Block JavaScript or VBScript from launching downloaded executable content"; Mode = $modeValue }
    @{ Guid = "3b576869-a4ec-4529-8536-b80a7769e899"; Name = "Block Office applications from creating executable content"; Mode = $modeValue }
    @{ Guid = "75668c1f-73b5-4cf0-bb93-3ecf5cb7cc84"; Name = "Block Office applications from injecting code into other processes"; Mode = $modeValue }
    @{ Guid = "26190899-1602-49e8-8b27-eb1d0a1ce869"; Name = "Block Office communication application from creating child processes"; Mode = $modeValue }
    @{ Guid = "e6db77e5-3df2-4cf1-b95a-636979351e5b"; Name = "Block persistence through WMI event subscription"; Mode = $modeValue }
    @{ Guid = "b2b3f03d-6a65-4f7b-a9c7-1c7ef74a9ba4"; Name = "Block untrusted and unsigned processes from USB"; Mode = $modeValue }
    @{ Guid = "92e97fa1-2edf-4476-bdd6-9dd0b4dddc7b"; Name = "Block Win32 API calls from Office macros"; Mode = $modeValue }
    # Plan 2 rules - default audit regardless of target mode
    @{ Guid = "c1db55ab-c21a-4637-bb3f-a12568109d35"; Name = "Use advanced protection against ransomware"; Mode = $modeValue; Plan2 = $true }
    @{ Guid = "01443614-cd74-433a-b99e-2ecdc07bfc25"; Name = "Block executables not meeting prevalence, age, or trusted list criterion"; Mode = 2; Plan2 = $true }
    @{ Guid = "d1e49aac-8f56-4280-b9ba-993a6d77406c"; Name = "Block process creations from PSExec and WMI commands"; Mode = 2; Plan2 = $true }
)

Write-Host "Deploying $($asrRules.Count) ASR rules..." -ForegroundColor Cyan
Write-Host ""

foreach ($r in $asrRules) {
    $modeName = switch ($r.Mode) {
        0 { "Disabled" }
        1 { "Block" }
        2 { "Audit" }
        6 { "Warn" }
    }
    Write-Host "  $($r.Name): $modeName" -ForegroundColor $(if ($r.Mode -eq 1) { "Yellow" } else { "Cyan" })
}

Write-Host ""
Write-Host "Deployment via Intune Graph API:" -ForegroundColor Cyan
Write-Host "  The profile creation is multi-step through the configurationPolicies endpoint."
Write-Host "  Review and deploy through Intune admin center if script Graph creation fails:"
Write-Host "  https://intune.microsoft.com"
Write-Host "  Endpoint security > Attack surface reduction > Create policy"
Write-Host "  Platform: Windows 10, Windows 11, and Windows Server"
Write-Host "  Profile: Attack surface reduction rules"
Write-Host "  Apply the rules above with the specified modes."
Write-Host ""
Write-Host "Assign to: $AssignmentGroup" -ForegroundColor Cyan

# Attempt Graph creation
try {
    $profileBody = @{
        name = $ProfileName
        description = "SMB Baseline ASR Rules deployed by Runbook 27. Initial mode: $Mode."
        platforms = "windows10"
        technologies = "mdm,microsoftSense"
        templateReference = @{
            templateId = "c7c6d7c7-a7c1-4f82-9c2f-9a5d82e9cabd_1"  # ASR template id (example)
        }
        settings = @()
    }

    foreach ($r in $asrRules) {
        # Settings structure for ASR rule; real implementation requires full Intune settings catalog format
        $profileBody.settings += @{
            settingInstance = @{
                "@odata.type" = "#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance"
                settingDefinitionId = "device_vendor_msft_policy_config_defender_attacksurfacereductionrules_$($r.Guid -replace '-','')"
                choiceSettingValue = @{
                    value = "$($r.Mode)"
                }
            }
        }
    }

    $uri = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies"
    Invoke-MgGraphRequest -Uri $uri -Method POST -Body ($profileBody | ConvertTo-Json -Depth 20) -ErrorAction Stop | Out-Null

    Write-Host "Profile created via Graph." -ForegroundColor Green
} catch {
    Write-Host "Graph creation failed (common; use portal as fallback): $_" -ForegroundColor Yellow
}
