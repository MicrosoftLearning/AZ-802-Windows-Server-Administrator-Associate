<#
.SYNOPSIS
    Lab 07: Configuring security in Windows Server
    Restores baseline, configures SEA-DC1 + SEA-SVR1 + SEA-SVR2.
#>
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\LabPackage-Helpers.ps1"

$LabVMs = @('SEA-DC1', 'SEA-SVR1', 'SEA-SVR2')
Restore-LabBaseline -VMsToStart $LabVMs

Write-Step "Configuring for Lab 07"

# SEA-DC1: Create IT OU, test users with non-expiring passwords
Invoke-LabCommand -VMName 'SEA-DC1' -ScriptBlock {
    Import-Module ActiveDirectory
    New-ADOrganizationalUnit -Name 'IT' -Path 'DC=contoso,DC=com' -ErrorAction SilentlyContinue

    $pwd = ConvertTo-SecureString 'Pa55w.rd1234' -AsPlainText -Force
    foreach ($name in @('LabUser1','LabUser2','LabUser3','LabUser4','LabUser5')) {
        New-ADUser -Name $name -SamAccountName $name -AccountPassword $pwd `
            -Enabled $true -PasswordNeverExpires $true `
            -Path 'CN=Users,DC=contoso,DC=com' -ErrorAction SilentlyContinue
    }
}
Write-Ok "SEA-DC1: IT OU and test users created"

# SEA-SVR2: Install RSAT, create lab files (Credential Guard tool, LAPS)
Invoke-LabCommand -VMName 'SEA-SVR2' -ScriptBlock {
    Install-WindowsFeature -Name RSAT-AD-Tools, GPMC -IncludeAllSubFeature

    New-Item -Path 'C:\Labfiles\Lab01' -ItemType Directory -Force | Out-Null

    # Credential Guard readiness tool
    @'
param([switch]$Enable, [switch]$AutoReboot)
Write-Host "Checking Device Guard / Credential Guard readiness..."
$vbs = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction SilentlyContinue
if ($vbs) {
    Write-Host "VBS Status: $($vbs.VirtualizationBasedSecurityStatus)"
    Write-Host "Required Properties: $($vbs.RequiredSecurityProperties -join ', ')"
    Write-Host "Available Properties: $($vbs.AvailableSecurityProperties -join ', ')"
} else { Write-Host "WARNING: Cannot query Device Guard status in this VM." }
if ($Enable) {
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard" /v EnableVirtualizationBasedSecurity /t REG_DWORD /d 1 /f | Out-Null
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v LsaCfgFlags /t REG_DWORD /d 1 /f | Out-Null
}
if ($AutoReboot) { Restart-Computer -Force }
'@ | Out-File -FilePath 'C:\Labfiles\Lab01\DG_Readiness_Tool.ps1' -Encoding UTF8

    # Download LAPS
    try {
        $lapsUrl = 'https://download.microsoft.com/download/C/7/A/C7AAD914-A8A6-4904-88A1-29E657445D03/LAPS.x64.msi'
        if (-not (Test-Path 'C:\Labfiles\Lab01\LAPS.x64.msi')) {
            Invoke-WebRequest -Uri $lapsUrl -OutFile 'C:\Labfiles\Lab01\LAPS.x64.msi' -UseBasicParsing
        }
    } catch {
        Write-Output "WARNING: Could not download LAPS. Download manually from Microsoft."
    }

    # Enable SMB for LAPS remote install to SEA-SVR1
    $rule = Get-NetFirewallRule | Where-Object { $_.DisplayName -eq 'File and Printer Sharing (SMB-In)' }
    $rule | Set-NetFirewallRule -Profile Domain
    $rule | Enable-NetFirewallRule
}
Write-Ok "SEA-SVR2: RSAT, Credential Guard tool, LAPS installer ready"

# SEA-SVR1: Enable WinRM and SMB
Invoke-LabCommand -VMName 'SEA-SVR1' -ScriptBlock {
    Enable-PSRemoting -Force -SkipNetworkProfileCheck
    $rule = Get-NetFirewallRule | Where-Object { $_.DisplayName -eq 'File and Printer Sharing (SMB-In)' }
    $rule | Set-NetFirewallRule -Profile Domain
    $rule | Enable-NetFirewallRule
}
Write-Ok "SEA-SVR1: WinRM and SMB enabled"

Write-Step "Lab 07 is ready"
Write-Host "  Connect to SEA-SVR2 and begin the lab." -ForegroundColor White
Write-Host "  VMs running: $($LabVMs -join ', ')" -ForegroundColor White
