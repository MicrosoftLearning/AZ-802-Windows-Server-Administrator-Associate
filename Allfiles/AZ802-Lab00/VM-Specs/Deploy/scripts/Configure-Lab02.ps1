# Configure-Lab02.ps1 — Managing Windows Server
# Runs on: SEA-DC1, SEA-ADM1

$ErrorActionPreference = 'Stop'
$hostname = $env:COMPUTERNAME

switch ($hostname) {
    'SEA-DC1' {
        Write-Output "[SEA-DC1] Ensuring WinRM and PS Remoting are enabled..."
        Enable-PSRemoting -Force -SkipNetworkProfileCheck
        if ((Get-Service -Name WinRM).Status -ne 'Running') {
            throw 'WinRM is not running on SEA-DC1.'
        }
        Write-Output "[SEA-DC1] Ready for Lab 02."
    }

    'SEA-ADM1' {
        Write-Output "[SEA-ADM1] Installing RSAT tools..."
        $rsatFeatures = @('RSAT-AD-Tools', 'RSAT-DNS-Server')
        Install-WindowsFeature -Name $rsatFeatures -IncludeAllSubFeature | Out-Null
        if (Get-WindowsFeature -Name $rsatFeatures | Where-Object { -not $_.Installed }) {
            throw 'One or more required RSAT features failed to install.'
        }

        Write-Output "[SEA-ADM1] Verifying Microsoft Edge, BITS, and internet access..."
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

        Write-Output "[SEA-ADM1] Enabling PS Remoting trust..."
        Set-Item WSMan:\localhost\client\trustedhosts -Value '*.contoso.com' -Force

        # WAC is downloaded and installed during the lab exercise
        Write-Output "[SEA-ADM1] NOTE: WAC will be downloaded during the lab (requires internet)."
        Write-Output "[SEA-ADM1] Lab 02 config complete."
    }
}
