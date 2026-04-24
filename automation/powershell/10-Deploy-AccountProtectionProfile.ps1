<#
.SYNOPSIS
    Deploys the Intune Endpoint Security Account Protection profile (VBS, Credential Guard, HVCI).

.DESCRIPTION
    Runbook 10 - VBS, Credential Guard, and TPM Hardware Enforcement, Step 3.
    Applies to: All variants.

    Creates an Endpoint Security Account Protection profile with VBS, Credential Guard,
    and HVCI all set to Enable with UEFI Lock. UEFI Lock prevents software-based disable
    from within Windows; it is a one-way setting per device (disable requires physical
    access to the device's UEFI firmware).

.PARAMETER ProfileName
    Display name.

.PARAMETER EnableUEFILock
    Enable UEFI Lock. Default: true. Set false if the organization needs the ability
    to disable VBS remotely.

.EXAMPLE
    ./10-Deploy-AccountProtectionProfile.ps1 -ProfileName "Windows VBS and Credential Guard" -EnableUEFILock

.NOTES
    Required Graph scopes:
        DeviceManagementConfiguration.ReadWrite.All
#>

[CmdletBinding()]
param(
    [string]$ProfileName = "Windows VBS and Credential Guard",

    [switch]$EnableUEFILock,

    [switch]$AssignToAllDevices
)

$ErrorActionPreference = "Stop"

$context = Get-MgContext
if (-not $context) { throw "Not connected to Microsoft Graph." }

Write-Host "=== Deploy Endpoint Security Account Protection Profile ===" -ForegroundColor Cyan
Write-Host "Profile: $ProfileName"
Write-Host "UEFI Lock: $([bool]$EnableUEFILock)"
Write-Host ""

if ($EnableUEFILock) {
    Write-Host "UEFI Lock is enabled. Disabling VBS on affected devices will require physical UEFI access." -ForegroundColor Yellow
    $confirm = Read-Host "Confirm UEFI Lock deployment? (type 'yes')"
    if ($confirm -ne "yes") { Write-Host "Aborted."; exit 1 }
}

# UEFI Lock value: 1 = Enable with UEFI Lock; 2 = Enable without UEFI Lock; 0 = Disable
$vbsMode = if ($EnableUEFILock) { 1 } else { 2 }
$cgMode  = if ($EnableUEFILock) { 1 } else { 2 }
$hvciMode = if ($EnableUEFILock) { 1 } else { 2 }

# Settings Catalog format for Endpoint Security
$body = @{
    name = $ProfileName
    description = "Created by Runbook 10. VBS, Credential Guard, HVCI with UEFI Lock = $([bool]$EnableUEFILock)"
    platforms = "windows10"
    technologies = "mdm"
    templateReference = @{
        templateId = "d1174162-1dd2-4976-affc-6667049ab0ae_1"  # Account Protection template
    }
    settings = @(
        @{
            "@odata.type" = "#microsoft.graph.deviceManagementConfigurationSetting"
            settingInstance = @{
                "@odata.type" = "#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance"
                settingDefinitionId = "device_vendor_msft_policy_config_virtualizationbasedtechnology_hypervisorenforcedcodeintegrity"
                choiceSettingValue = @{
                    "@odata.type" = "#microsoft.graph.deviceManagementConfigurationChoiceSettingValue"
                    value = "device_vendor_msft_policy_config_virtualizationbasedtechnology_hypervisorenforcedcodeintegrity_$hvciMode"
                }
            }
        }
        @{
            "@odata.type" = "#microsoft.graph.deviceManagementConfigurationSetting"
            settingInstance = @{
                "@odata.type" = "#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance"
                settingDefinitionId = "device_vendor_msft_policy_config_deviceguard_lsacfgflags"
                choiceSettingValue = @{
                    "@odata.type" = "#microsoft.graph.deviceManagementConfigurationChoiceSettingValue"
                    value = "device_vendor_msft_policy_config_deviceguard_lsacfgflags_$cgMode"
                }
            }
        }
    )
}

try {
    $profile = Invoke-MgGraphRequest -Method POST `
        -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies" `
        -Body ($body | ConvertTo-Json -Depth 10) `
        -ContentType "application/json"

    Write-Host "Profile created: $($profile.id)" -ForegroundColor Green
} catch {
    Write-Host "Failed: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Account Protection settings are also available through the Endpoint Security portal:" -ForegroundColor Yellow
    Write-Host "  Intune > Endpoint security > Account protection > Create Policy > Windows 10 and later" -ForegroundColor Yellow
    exit 1
}

if ($AssignToAllDevices) {
    $assignment = @{
        assignments = @(
            @{ target = @{ "@odata.type" = "#microsoft.graph.allDevicesAssignmentTarget" } }
        )
    }

    try {
        Invoke-MgGraphRequest -Method POST `
            -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($profile.id)/assign" `
            -Body ($assignment | ConvertTo-Json -Depth 10) `
            -ContentType "application/json"
        Write-Host "Assigned." -ForegroundColor Green
    } catch {
        Write-Warning "Assignment failed: $_"
    }
}

[PSCustomObject]@{
    ProfileId = $profile.id
    ProfileName = $ProfileName
    UEFILock = [bool]$EnableUEFILock
} | ConvertTo-Json
