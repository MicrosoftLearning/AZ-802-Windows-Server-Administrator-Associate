<#
.SYNOPSIS
    Lab 01: Implementing identity services and Group Policy
    Restores baseline, configures SEA-DC1 + SEA-ADM1 + SEA-SVR1.
#>
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\LabPackage-Helpers.ps1"

$LabVMs = @('SEA-DC1', 'SEA-ADM1', 'SEA-SVR1')
Restore-LabBaseline -VMsToStart $LabVMs

Write-Step "Configuring for Lab 01"

# SEA-ADM1: Install RSAT tools for AD, DNS, Group Policy
Invoke-LabCommand -VMName 'SEA-ADM1' -ScriptBlock {
    Install-WindowsFeature -Name RSAT-AD-Tools, RSAT-DNS-Server, GPMC, RSAT-ADDS-Tools -IncludeAllSubFeature
    Set-Item WSMan:\localhost\client\trustedhosts -Value '*.contoso.com' -Force
}
Write-Ok "SEA-ADM1: RSAT tools installed"

# SEA-SVR1: Ensure WinRM is ready (AD DS installed during the lab)
Invoke-LabCommand -VMName 'SEA-SVR1' -ScriptBlock {
    Enable-PSRemoting -Force -SkipNetworkProfileCheck
}
Write-Ok "SEA-SVR1: WinRM enabled"

Write-Step "Lab 01 is ready"
Write-Host "  Connect to SEA-ADM1 and begin the lab." -ForegroundColor White
Write-Host "  VMs running: $($LabVMs -join ', ')" -ForegroundColor White
