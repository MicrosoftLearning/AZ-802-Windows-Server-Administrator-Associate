<#
.SYNOPSIS
    Lab 06: Implementing storage solutions in Windows Server
    Restores baseline, configures SEA-DC1 + SEA-ADM1 + SEA-SVR3.
    NOTE: Re-run this script between exercises to reset SEA-SVR3 disks.
#>
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\LabPackage-Helpers.ps1"

$LabVMs = @('SEA-DC1', 'SEA-ADM1', 'SEA-SVR3')
Restore-LabBaseline -VMsToStart $LabVMs

Write-Step "Configuring for Lab 06"

# SEA-ADM1: Install RSAT, create and share Labfiles, create CreateLabFiles.cmd
Invoke-LabCommand -VMName 'SEA-ADM1' -ScriptBlock {
    Install-WindowsFeature -Name RSAT-AD-Tools, RSAT-File-Services -IncludeAllSubFeature
    Set-Item WSMan:\localhost\client\trustedhosts -Value '*.contoso.com' -Force

    New-Item -Path 'C:\Labfiles\Lab06' -ItemType Directory -Force | Out-Null
    New-SmbShare -Name 'Labfiles' -Path 'C:\Labfiles' -FullAccess 'Everyone' -ErrorAction SilentlyContinue

    @'
@echo off
echo Creating sample files for deduplication testing...
for /L %%i in (1,1,50) do (
    fsutil file createnew "M:\Data\File%%i.dat" 10485760
    copy "M:\Data\File%%i.dat" "M:\Data\Copy%%i.dat" >nul
)
echo Sample files created.
'@ | Out-File -FilePath 'C:\Labfiles\Lab06\CreateLabFiles.cmd' -Encoding ASCII
}
Write-Ok "SEA-ADM1: Labfiles shared, CreateLabFiles.cmd created"

# SEA-SVR3: Set data disks offline/raw, enable remote management
Invoke-LabCommand -VMName 'SEA-SVR3' -ScriptBlock {
    Enable-PSRemoting -Force -SkipNetworkProfileCheck
    Enable-NetFirewallRule -DisplayGroup 'Remote Service Management' -ErrorAction SilentlyContinue
    Enable-NetFirewallRule -DisplayGroup 'Remote Volume Management' -ErrorAction SilentlyContinue
    Enable-NetFirewallRule -DisplayGroup 'Windows Remote Management' -ErrorAction SilentlyContinue

    # Ensure all data disks are offline and raw
    foreach ($num in 1..4) {
        $disk = Get-Disk -Number $num -ErrorAction SilentlyContinue
        if ($disk) {
            if ($disk.PartitionStyle -ne 'RAW') {
                Clear-Disk -Number $num -RemoveData -RemoveOEM -Confirm:$false -ErrorAction SilentlyContinue
            }
            Set-Disk -Number $num -IsOffline $true -ErrorAction SilentlyContinue
        }
    }
}
Write-Ok "SEA-SVR3: Disks 1-4 offline/raw, remote management enabled"

# SEA-DC1: Enable WinRM (used as iSCSI initiator in Exercise 2)
Invoke-LabCommand -VMName 'SEA-DC1' -ScriptBlock {
    Enable-PSRemoting -Force -SkipNetworkProfileCheck
}
Write-Ok "SEA-DC1: WinRM enabled"

Write-Step "Lab 06 is ready"
Write-Host "  Connect to SEA-ADM1 and begin the lab." -ForegroundColor White
Write-Host "  NOTE: Lab says 'revert VMs between exercises.' Re-run this script to reset." -ForegroundColor Yellow
Write-Host "  VMs running: $($LabVMs -join ', ')" -ForegroundColor White
