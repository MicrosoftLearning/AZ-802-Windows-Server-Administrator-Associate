# Configure-Lab05.ps1 - Implementing Azure File Sync
# Runs on: SEA-DC1, SEA-ADM1, SEA-SVR1, SEA-SVR2

$ErrorActionPreference = 'Stop'
$hostname = $env:COMPUTERNAME

switch ($hostname) {
    'SEA-DC1' {
        Write-Output "[SEA-DC1] No additional config needed for Lab 05."
    }

    'SEA-ADM1' {
        Write-Output "[SEA-ADM1] Installing RSAT tools..."
        Install-WindowsFeature -Name RSAT-AD-Tools

        $requiredFiles = @(
            'C:\Labfiles\Lab05\DeployDFS.ps1'
            'C:\Labfiles\Lab05\Install-FileSyncServerCore.ps1'
            'C:\Labfiles\Lab05\File1.txt'
        )
        foreach ($requiredFile in $requiredFiles) {
            if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
                throw "Required Lab 5 file is missing: $requiredFile"
            }
        }

        Write-Output "[SEA-ADM1] Enabling PS Remoting trust..."
        Set-Item WSMan:\localhost\client\trustedhosts -Value '*.contoso.com' -Force

        Write-Output "[SEA-ADM1] NOTE: Azure File Sync agent MSI must be downloaded during the lab."
        Write-Output "[SEA-ADM1] NOTE: Azure subscription required for this lab."
        Write-Output "[SEA-ADM1] Lab 05 config complete."
    }

    'SEA-SVR1' {
        Write-Output "[SEA-SVR1] Enabling WinRM..."
        Enable-PSRemoting -Force -SkipNetworkProfileCheck
        Write-Output "[SEA-SVR1] Enabling File and Printer Sharing (SMB)..."
        Enable-NetFirewallRule -DisplayGroup 'File and Printer Sharing'
        $dataDisk = Get-Disk -Number 1 -ErrorAction Stop
        if ($dataDisk.PartitionStyle -ne 'RAW') {
            throw 'Disk 1 must be raw before the learner runs DeployDFS.ps1.'
        }
        if ($dataDisk.IsReadOnly) {
            Set-Disk -Number 1 -IsReadOnly $false
        }
        if ($dataDisk.IsOffline) {
            Set-Disk -Number 1 -IsOffline $false
        }
        Write-Output "[SEA-SVR1] Lab 05 config complete."
    }

    'SEA-SVR2' {
        Write-Output "[SEA-SVR2] Enabling WinRM..."
        Enable-PSRemoting -Force -SkipNetworkProfileCheck
        Write-Output "[SEA-SVR2] Enabling File and Printer Sharing (SMB)..."
        Enable-NetFirewallRule -DisplayGroup 'File and Printer Sharing'
        $dataDisk = Get-Disk -Number 1 -ErrorAction Stop
        if ($dataDisk.PartitionStyle -ne 'RAW') {
            throw 'Disk 1 must be raw before the learner runs DeployDFS.ps1.'
        }
        if ($dataDisk.IsReadOnly) {
            Set-Disk -Number 1 -IsReadOnly $false
        }
        if ($dataDisk.IsOffline) {
            Set-Disk -Number 1 -IsOffline $false
        }
        Write-Output "[SEA-SVR2] Lab 05 config complete."
    }
}
