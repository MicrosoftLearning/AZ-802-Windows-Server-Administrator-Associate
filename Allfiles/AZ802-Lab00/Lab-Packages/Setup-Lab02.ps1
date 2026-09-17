<#
.SYNOPSIS
    Lab 02: Managing Windows Server
    Restores baseline, configures SEA-DC1 + SEA-ADM1.
#>
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\LabPackage-Helpers.ps1"

$LabVMs = @('SEA-DC1', 'SEA-ADM1')
Restore-LabBaseline -VMsToStart $LabVMs

Write-Step "Configuring for Lab 02"

Invoke-LabCommand -VMName 'SEA-ADM1' -ScriptBlock {
    $rsatFeatures = @('RSAT-AD-Tools', 'RSAT-DNS-Server')
    Install-WindowsFeature -Name $rsatFeatures -IncludeAllSubFeature | Out-Null
    if (Get-WindowsFeature -Name $rsatFeatures | Where-Object { -not $_.Installed }) {
        throw 'One or more required RSAT features failed to install.'
    }
    if (-not (Test-Path 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe')) {
        throw 'Microsoft Edge is required but was not found.'
    }
    if (-not (Get-Service -Name BITS -ErrorAction SilentlyContinue)) {
        throw 'Background Intelligent Transfer Service (BITS) is required but was not found.'
    }
    if (-not (Resolve-DnsName -Name 'aka.ms' -ErrorAction SilentlyContinue)) {
        throw 'SEA-ADM1 cannot resolve aka.ms.'
    }
    if (-not (Test-NetConnection -ComputerName 'aka.ms' -Port 443 -InformationLevel Quiet)) {
        throw 'SEA-ADM1 cannot connect to aka.ms over HTTPS.'
    }
    Set-Item WSMan:\localhost\client\trustedhosts -Value '*.contoso.com' -Force
}
Write-Ok "SEA-ADM1: RSAT, Edge, BITS, and internet access verified"

Invoke-LabCommand -VMName 'SEA-DC1' -ScriptBlock {
    Enable-PSRemoting -Force -SkipNetworkProfileCheck
    if ((Get-Service -Name WinRM).Status -ne 'Running') {
        throw 'WinRM is not running on SEA-DC1.'
    }
}
Write-Ok "SEA-DC1: WinRM enabled"

Write-Step "Lab 02 is ready"
Write-Host "  Connect to SEA-ADM1 and begin the lab." -ForegroundColor White
Write-Host "  NOTE: WAC is downloaded during the lab (requires internet access)." -ForegroundColor Yellow
Write-Host "  VMs running: $($LabVMs -join ', ')" -ForegroundColor White
