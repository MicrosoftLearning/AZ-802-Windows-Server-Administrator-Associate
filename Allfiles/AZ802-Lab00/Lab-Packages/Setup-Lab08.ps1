<#
.SYNOPSIS
    Lab 08: Monitoring and troubleshooting Windows Server
    Restores baseline, configures SEA-DC1 + SEA-SVR2.
#>
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\LabPackage-Helpers.ps1"

$LabVMs = @('SEA-DC1', 'SEA-SVR2')
Restore-LabBaseline -VMsToStart $LabVMs

Write-Step "Configuring for Lab 08"

# SEA-SVR2: Install RSAT, download CPUSTRES64.EXE
Invoke-LabCommand -VMName 'SEA-SVR2' -ScriptBlock {
    Install-WindowsFeature -Name RSAT-AD-Tools -IncludeAllSubFeature
    Set-Item WSMan:\localhost\client\trustedhosts -Value '*.contoso.com' -Force

    New-Item -Path 'C:\Labfiles\Lab08' -ItemType Directory -Force | Out-Null

    try {
        if (-not (Test-Path 'C:\Labfiles\Lab08\CPUSTRES64.EXE')) {
            Invoke-WebRequest -Uri 'https://live.sysinternals.com/CPUSTRES64.EXE' `
                -OutFile 'C:\Labfiles\Lab08\CPUSTRES64.EXE' -UseBasicParsing
        }
    } catch {
        Write-Output "WARNING: Could not download CPUSTRES64.EXE. Download from https://live.sysinternals.com/"
    }
}
Write-Ok "SEA-SVR2: RSAT installed, CPUSTRES64.EXE downloaded"

# SEA-DC1: Enable WinRM, event log firewall rules
Invoke-LabCommand -VMName 'SEA-DC1' -ScriptBlock {
    Enable-PSRemoting -Force -SkipNetworkProfileCheck
    Set-NetFirewallRule -DisplayGroup 'Remote Event Log Management' -Enabled True -Profile Domain -ErrorAction SilentlyContinue
}
Write-Ok "SEA-DC1: WinRM and event log rules enabled"

Write-Step "Lab 08 is ready"
Write-Host "  Connect to SEA-SVR2 and begin the lab." -ForegroundColor White
Write-Host "  VMs running: $($LabVMs -join ', ')" -ForegroundColor White
