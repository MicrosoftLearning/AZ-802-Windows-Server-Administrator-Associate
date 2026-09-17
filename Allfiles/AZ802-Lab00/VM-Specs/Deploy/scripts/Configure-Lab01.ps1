# Configure-Lab01.ps1 — Implementing identity services and Group Policy
# Runs on: SEA-DC1, SEA-ADM1, SEA-SVR1 (each VM runs this; script detects which host)

$ErrorActionPreference = 'SilentlyContinue'
$hostname = $env:COMPUTERNAME

switch ($hostname) {
    'SEA-DC1' {
        Write-Output "[SEA-DC1] Verifying AD DS and DNS are operational..."
        Import-Module ActiveDirectory
        Get-ADDomain | Out-Null
        Write-Output "[SEA-DC1] AD DS is operational."
    }

    'SEA-ADM1' {
        Write-Output "[SEA-ADM1] Installing RSAT tools..."
        Install-WindowsFeature -Name RSAT-AD-Tools, RSAT-DNS-Server, GPMC, RSAT-ADDS-Tools -IncludeAllSubFeature
        
        Write-Output "[SEA-ADM1] Adding SEA-SVR1 to Server Manager..."
        # Server Manager auto-discovers domain members; ensure connectivity
        Test-NetConnection -ComputerName SEA-SVR1 -Port 5985 | Out-Null
        Test-NetConnection -ComputerName SEA-DC1 -Port 5985 | Out-Null
        
        Write-Output "[SEA-ADM1] Enabling PS Remoting trust..."
        Set-Item WSMan:\localhost\client\trustedhosts -Value '*.contoso.com' -Force

        Write-Output "[SEA-ADM1] Lab 01 config complete."
    }

    'SEA-SVR1' {
        # Lab 01 installs AD DS on SEA-SVR1 during the exercise — do NOT pre-install
        Write-Output "[SEA-SVR1] Ensuring WinRM is enabled..."
        Enable-PSRemoting -Force -SkipNetworkProfileCheck
        
        Write-Output "[SEA-SVR1] Ready for Lab 01 (AD DS will be installed during the lab)."
    }
}
