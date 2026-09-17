# Configure-Lab08.ps1 — Monitoring and troubleshooting Windows Server
# Runs on: SEA-DC1, SEA-SVR2

$ErrorActionPreference = 'Stop'
$hostname = $env:COMPUTERNAME

switch ($hostname) {
    'SEA-DC1' {
        Write-Output "[SEA-DC1] Ready for Lab 08 (WinRM and firewall configuration completed during lab)."
    }

    'SEA-SVR2' {
        Write-Output "[SEA-SVR2] Installing RSAT tools..."
        $featureResult = Install-WindowsFeature -Name RSAT-AD-Tools
        if (-not $featureResult.Success) {
            throw 'Failed to install the Lab 8 RSAT tools.'
        }

        Write-Output "[SEA-SVR2] Creating C:\Labfiles\Lab08 directory..."
        New-Item -Path 'C:\Labfiles\Lab08' -ItemType Directory -Force | Out-Null

        # Download CPUSTRES64.EXE from SysInternals
        Write-Output "[SEA-SVR2] Downloading CPUSTRES64.EXE from SysInternals..."
        $cpuStressUrl = 'https://live.sysinternals.com/CPUSTRES64.EXE'
        $cpuStressPath = 'C:\Labfiles\Lab08\CPUSTRES64.EXE'
        Invoke-WebRequest -Uri $cpuStressUrl -OutFile $cpuStressPath -UseBasicParsing
        if ((Get-AuthenticodeSignature -LiteralPath $cpuStressPath).Status -ne 'Valid') {
            throw 'CPUSTRES64.EXE does not have a valid Authenticode signature.'
        }
        Write-Output "[SEA-SVR2] CPUSTRES64.EXE downloaded and verified."

        Write-Output "[SEA-SVR2] Lab 08 config complete."
    }
}
