<#
.SYNOPSIS
    Lab 05: Implementing Azure File Sync
    Restores baseline, configures SEA-DC1 + SEA-ADM1 + SEA-SVR1 + SEA-SVR2.
#>
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\LabPackage-Helpers.ps1"

$LabVMs = @('SEA-DC1', 'SEA-ADM1', 'SEA-SVR1', 'SEA-SVR2')
Restore-LabBaseline -VMsToStart $LabVMs

Write-Step "Configuring for Lab 05"

# SEA-ADM1: Install DFS tools and stage the canonical lab files
Invoke-LabCommand -VMName 'SEA-ADM1' -ScriptBlock {
    Install-WindowsFeature -Name RSAT-DFS-Mgmt-Con, RSAT-AD-Tools -IncludeManagementTools
    Set-Item WSMan:\localhost\client\trustedhosts -Value '*.contoso.com' -Force

    New-Item -Path 'C:\Labfiles\Lab05' -ItemType Directory -Force | Out-Null
}

$lab05SourceDirectory = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\AZ802-Lab05'))
$lab05FileNames = @('DeployDFS.ps1', 'Install-FileSyncServerCore.ps1', 'File1.txt')
$session = New-PSSession -VMName 'SEA-ADM1' -Credential (Get-LabCredential)
try {
    foreach ($fileName in $lab05FileNames) {
        $sourcePath = Join-Path $lab05SourceDirectory $fileName
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            throw "Canonical Lab 5 file not found: $sourcePath"
        }

        $destinationPath = "C:\Labfiles\Lab05\$fileName"
        Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -ToSession $session -Force
        $expectedHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
        $actualHash = Invoke-Command -Session $session -ScriptBlock {
            param($Path)
            (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
        } -ArgumentList $destinationPath
        if ($actualHash -ne $expectedHash) {
            throw "Hash verification failed for $destinationPath."
        }
    }
}
finally {
    Remove-PSSession -Session $session -ErrorAction SilentlyContinue
}
Write-Ok "SEA-ADM1: DFS tools installed and canonical lab files staged"

# SEA-SVR1 and SEA-SVR2: Validate the raw learner data disk and enable WinRM
foreach ($vm in @('SEA-SVR1', 'SEA-SVR2')) {
    Invoke-LabCommand -VMName $vm -ScriptBlock {
        Enable-PSRemoting -Force -SkipNetworkProfileCheck
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
    }
    Write-Ok "${vm}: WinRM enabled and raw disk 1 verified"
}

Write-Step "Lab 05 is ready"
Write-Host "  Connect to SEA-ADM1 and begin the lab." -ForegroundColor White
Write-Host "  NOTE: This lab REQUIRES an Azure subscription." -ForegroundColor Yellow
Write-Host "  NOTE: Azure File Sync agent MSI must be downloaded during the lab." -ForegroundColor Yellow
Write-Host "  VMs running: $($LabVMs -join ', ')" -ForegroundColor White
