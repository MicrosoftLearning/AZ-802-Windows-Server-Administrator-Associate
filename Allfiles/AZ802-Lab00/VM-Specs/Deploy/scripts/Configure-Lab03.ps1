# Configure-Lab03.ps1 — Implementing and configuring virtualization in Windows Server
# Runs on: SEA-DC1, SEA-ADM1, SEA-SVR1

$ErrorActionPreference = 'Stop'
$hostname = $env:COMPUTERNAME

switch ($hostname) {
    'SEA-DC1' {
        Write-Output "[SEA-DC1] No additional config needed for Lab 03."
    }

    'SEA-ADM1' {
        Write-Output "[SEA-ADM1] Installing Hyper-V management tools (RSAT)..."
        $rsatFeatures = @('RSAT-Hyper-V-Tools', 'RSAT-AD-Tools')
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
        if (-not (Test-NetConnection -ComputerName 'aka.ms' -Port 443 -InformationLevel Quiet)) {
            throw 'SEA-ADM1 cannot connect to the Windows Admin Center download endpoint over HTTPS.'
        }

        Write-Output "[SEA-ADM1] Enabling PS Remoting trust..."
        Set-Item WSMan:\localhost\client\trustedhosts -Value '*.contoso.com' -Force

        Write-Output "[SEA-ADM1] Lab 03 config complete."
    }

    'SEA-SVR1' {
        Write-Output "[SEA-SVR1] Installing Hyper-V role..."
        Install-WindowsFeature -Name Hyper-V -IncludeManagementTools -Restart:$false | Out-Null
        if (-not (Get-WindowsFeature -Name Hyper-V).Installed) {
            throw 'The Hyper-V role failed to install.'
        }

        Write-Output "[SEA-SVR1] Creating C:\Base directory..."
        New-Item -Path 'C:\Base' -ItemType Directory -Force | Out-Null

        Write-Output "[SEA-SVR1] Enabling WinRM..."
        Enable-PSRemoting -Force -SkipNetworkProfileCheck
        if ((Get-Service -Name WinRM).Status -ne 'Running') {
            throw 'WinRM is not running on SEA-SVR1.'
        }
        foreach ($endpoint in @('raw.githubusercontent.com', 'mcr.microsoft.com')) {
            if (-not (Test-NetConnection -ComputerName $endpoint -Port 443 -InformationLevel Quiet)) {
                throw "SEA-SVR1 cannot connect to $endpoint over HTTPS."
            }
        }

        Write-Output "[SEA-SVR1] NOTE: Docker CE will be downloaded during the lab (requires internet)."
        Write-Output "[SEA-SVR1] Lab 03 config complete."
    }
}
