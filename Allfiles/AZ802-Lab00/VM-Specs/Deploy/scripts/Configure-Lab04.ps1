# Configure-Lab04.ps1 — Implementing and configuring network infrastructure services
# Runs on: SEA-DC1, SEA-ADM1, SEA-SVR1

$ErrorActionPreference = 'Stop'
$hostname = $env:COMPUTERNAME

switch ($hostname) {
    'SEA-DC1' {
        Write-Output "[SEA-DC1] Installing DHCP role (pre-req for failover partner)..."
        Install-WindowsFeature -Name DHCP -IncludeManagementTools | Out-Null
        if (-not (Get-WindowsFeature -Name DHCP).Installed) {
            throw 'The DHCP Server role failed to install on SEA-DC1.'
        }
        Import-Module DhcpServer

        Write-Output "[SEA-DC1] Authorizing DHCP server in AD..."
        $authorizedServer = Get-DhcpServerInDC |
            Where-Object { $_.IPAddress -eq '172.16.10.10' -or $_.DnsName -ieq 'SEA-DC1.contoso.com' }
        if (-not $authorizedServer) {
            Add-DhcpServerInDC -DnsName 'SEA-DC1.contoso.com' -IPAddress '172.16.10.10'
        }

        Write-Output "[SEA-DC1] Creating pre-existing Contoso DHCP scope..."
        $scope = Get-DhcpServerv4Scope -ScopeId '172.16.0.0' -ErrorAction SilentlyContinue
        if (-not $scope) {
            Add-DhcpServerv4Scope -Name 'Contoso' -StartRange '172.16.0.100' -EndRange '172.16.0.200' `
                -SubnetMask '255.255.0.0' -State Active
            $scope = Get-DhcpServerv4Scope -ScopeId '172.16.0.0'
        }
        if ($scope.Name -ne 'Contoso' -or $scope.StartRange -ne '172.16.0.100' -or
            $scope.EndRange -ne '172.16.0.200' -or $scope.SubnetMask -ne '255.255.0.0') {
            throw 'The existing 172.16.0.0 DHCP scope does not match the Lab 4 baseline.'
        }

        Write-Output "[SEA-DC1] Setting DHCP scope options..."
        Set-DhcpServerv4OptionValue -ScopeId '172.16.0.0' -DnsServer '172.16.10.10' `
            -DnsDomain 'contoso.com' -Router '172.16.10.1'

        if ((Get-Service -Name DHCPServer).Status -ne 'Running') {
            Start-Service -Name DHCPServer
        }

        Write-Output "[SEA-DC1] Suppressing DHCP post-install config flag..."
        Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager\Roles\12' `
            -Name 'ConfigurationState' -Value 2

        Write-Output "[SEA-DC1] Lab 04 config complete."
    }

    'SEA-ADM1' {
        Write-Output "[SEA-ADM1] Installing RSAT tools (DHCP, DNS, AD)..."
        $rsatFeatures = @('RSAT-DHCP', 'RSAT-DNS-Server', 'RSAT-AD-Tools')
        Install-WindowsFeature -Name $rsatFeatures -IncludeAllSubFeature | Out-Null
        if (Get-WindowsFeature -Name $rsatFeatures | Where-Object { -not $_.Installed }) {
            throw 'One or more required DHCP, DNS, or AD management tools failed to install.'
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

        Write-Output "[SEA-ADM1] Lab 04 config complete."
    }

    'SEA-SVR1' {
        # DHCP and DNS roles are installed during the lab via WAC — do NOT pre-install
        Write-Output "[SEA-SVR1] Enabling WinRM..."
        Enable-PSRemoting -Force -SkipNetworkProfileCheck
        if ((Get-Service -Name WinRM).Status -ne 'Running') {
            throw 'WinRM is not running on SEA-SVR1.'
        }

        Write-Output "[SEA-SVR1] Ready for Lab 04 (DHCP/DNS installed during lab)."
    }
}
