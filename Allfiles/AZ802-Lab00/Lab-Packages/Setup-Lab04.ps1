<#
.SYNOPSIS
    Lab 04: Implementing and configuring network infrastructure services
    Restores baseline, configures SEA-DC1 + SEA-ADM1 + SEA-SVR1.
#>
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\LabPackage-Helpers.ps1"

$LabVMs = @('SEA-DC1', 'SEA-ADM1', 'SEA-SVR1')
Restore-LabBaseline -VMsToStart $LabVMs

Write-Step "Configuring for Lab 04"

# SEA-DC1: Install DHCP, authorize, create pre-existing Contoso scope
Invoke-LabCommand -VMName 'SEA-DC1' -ScriptBlock {
    $ErrorActionPreference = 'Stop'
    $primaryAddress = Get-NetIPConfiguration |
        Where-Object { $_.IPv4DefaultGateway } |
        Select-Object -ExpandProperty IPv4Address -First 1
    if ($primaryAddress.IPAddress -ne '172.16.10.10' -or $primaryAddress.PrefixLength -ne 16) {
        throw 'SEA-DC1 must use 172.16.10.10/16 on the flat LabSwitch network for Lab 4.'
    }
    Install-WindowsFeature -Name DHCP -IncludeManagementTools | Out-Null
    if (-not (Get-WindowsFeature -Name DHCP).Installed) {
        throw 'The DHCP Server role failed to install on SEA-DC1.'
    }
    Import-Module DhcpServer

    $authorizedServer = Get-DhcpServerInDC |
        Where-Object { $_.IPAddress -eq '172.16.10.10' -or $_.DnsName -ieq 'SEA-DC1.contoso.com' }
    if (-not $authorizedServer) {
        Add-DhcpServerInDC -DnsName 'SEA-DC1.contoso.com' -IPAddress '172.16.10.10'
    }

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
    Set-DhcpServerv4OptionValue -ScopeId '172.16.0.0' -DnsServer '172.16.10.10' `
        -DnsDomain 'contoso.com' -Router '172.16.10.1'

    if ((Get-Service -Name DHCPServer).Status -ne 'Running') {
        Start-Service -Name DHCPServer
    }

    # Suppress post-install config flag
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager\Roles\12' `
        -Name 'ConfigurationState' -Value 2 -ErrorAction SilentlyContinue
}
Write-Ok "SEA-DC1: DHCP installed, authorized, Contoso scope created"

# SEA-ADM1: Install RSAT for DHCP, DNS, AD
Invoke-LabCommand -VMName 'SEA-ADM1' -ScriptBlock {
    $ErrorActionPreference = 'Stop'
    $primaryAddress = Get-NetIPConfiguration |
        Where-Object { $_.IPv4DefaultGateway } |
        Select-Object -ExpandProperty IPv4Address -First 1
    if ($primaryAddress.IPAddress -ne '172.16.10.11' -or $primaryAddress.PrefixLength -ne 16) {
        throw 'SEA-ADM1 must use 172.16.10.11/16 on the flat LabSwitch network for Lab 4.'
    }
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
    Set-Item WSMan:\localhost\client\trustedhosts -Value '*.contoso.com' -Force
}
Write-Ok "SEA-ADM1: RSAT and Windows Admin Center prerequisites verified"

# SEA-SVR1: Ensure WinRM (DHCP/DNS installed during lab via WAC)
Invoke-LabCommand -VMName 'SEA-SVR1' -ScriptBlock {
    $ErrorActionPreference = 'Stop'
    $primaryAddress = Get-NetIPConfiguration |
        Where-Object { $_.IPv4DefaultGateway } |
        Select-Object -ExpandProperty IPv4Address -First 1
    if ($primaryAddress.IPAddress -ne '172.16.10.12' -or $primaryAddress.PrefixLength -ne 16) {
        throw 'SEA-SVR1 must use 172.16.10.12/16 on the flat LabSwitch network for Lab 4.'
    }
    Enable-PSRemoting -Force -SkipNetworkProfileCheck
    if ((Get-Service -Name WinRM).Status -ne 'Running') {
        throw 'WinRM is not running on SEA-SVR1.'
    }
}
Write-Ok "SEA-SVR1: WinRM enabled"

Write-Step "Lab 04 is ready"
Write-Host "  Connect to SEA-ADM1 and begin the lab." -ForegroundColor White
Write-Host "  NOTE: WAC is downloaded during the lab (requires internet)." -ForegroundColor Yellow
Write-Host "  VMs running: $($LabVMs -join ', ')" -ForegroundColor White
