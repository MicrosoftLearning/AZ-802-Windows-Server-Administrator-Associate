[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$EncodedAdminPassword,

    [uri]$VhdUri = 'https://go.microsoft.com/fwlink/p/?linkid=2195166&clcid=0x409&culture=en-us&country=us',

    [string]$DataDriveLetter = 'F',

    [ValidateSet(
        'All', 'PrepareHost', 'CreateDomainController', 'PromoteDomainController',
        'CreateServer', 'JoinServer', 'CreateAdmin', 'JoinAdmin', 'ConfigureLab', 'Validate'
    )]
    [string]$Phase = 'All'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$domainName = 'contoso.com'
$netBiosName = 'CONTOSO'
$switchName = 'LabSwitch'
$natName = 'Lab04NAT'
$labRoot = "${DataDriveLetter}:\Lab04"
$baseVhdPath = "$labRoot\Base\WindowsServer2022.vhd"
$vmRoot = "$labRoot\VMs"
$plainPassword = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String($EncodedAdminPassword)
)
$securePassword = ConvertTo-SecureString $plainPassword -AsPlainText -Force
$localCredential = [pscredential]::new('Administrator', $securePassword)
$domainCredential = [pscredential]::new("$netBiosName\Administrator", $securePassword)

$vmDefinitions = @(
    @{ Name = 'SEA-DC1'; IPAddress = '172.16.10.10'; Memory = 4GB; MaximumMemory = 6GB }
    @{ Name = 'SEA-ADM1'; IPAddress = '172.16.10.11'; Memory = 6GB; MaximumMemory = 10GB }
    @{ Name = 'SEA-SVR1'; IPAddress = '172.16.10.12'; Memory = 4GB; MaximumMemory = 8GB }
)

function Write-Step {
    param([string]$Message)
    Write-Output "`n=== $Message ==="
}

function Initialize-LabDataDisk {
    $dataDisk = Get-Disk |
        Where-Object {
            -not $_.IsBoot -and -not $_.IsSystem -and
            $_.Size -ge 500GB -and $_.Size -le 513GB
        } |
        Select-Object -First 1

    if (-not $dataDisk) {
        throw 'The Lab 4 data disk was not found. A data disk of at least 400 GB is required.'
    }

    if ($dataDisk.PartitionStyle -eq 'RAW') {
        Initialize-Disk -Number $dataDisk.Number -PartitionStyle GPT | Out-Null
        $partition = New-Partition -DiskNumber $dataDisk.Number -UseMaximumSize -DriveLetter $DataDriveLetter
        Format-Volume -Partition $partition -FileSystem NTFS -NewFileSystemLabel 'Lab04Data' -Confirm:$false | Out-Null
    }
    else {
        $partition = Get-Partition -DiskNumber $dataDisk.Number |
            Where-Object { $_.Type -eq 'Basic' } |
            Select-Object -First 1
        if (-not $partition) {
            throw 'The Lab 4 data disk has no usable partition.'
        }
        if (-not $partition.DriveLetter) {
            Set-Partition -DiskNumber $dataDisk.Number -PartitionNumber $partition.PartitionNumber `
                -NewDriveLetter $DataDriveLetter
        }
        elseif ($partition.DriveLetter -ne $DataDriveLetter) {
            throw "The Lab 4 data disk is mounted as $($partition.DriveLetter): instead of ${DataDriveLetter}:."
        }
    }

    New-Item -Path (Split-Path -Parent $baseVhdPath), $vmRoot -ItemType Directory -Force | Out-Null
}

function Get-OfflineInstallationType {
    param([Parameter(Mandatory)][string]$VhdPath)

    $mountedVhd = $null
    $registryLoaded = $false
    try {
        $mountedVhd = Mount-VHD -Path $VhdPath -ReadOnly -Passthru
        $disk = $mountedVhd | Get-Disk
        if ($disk.PartitionStyle -ne 'MBR') {
            throw "The parent VHD uses $($disk.PartitionStyle) partitioning. A Generation 1 MBR image is required."
        }
        if (-not ($disk | Get-Partition | Where-Object IsActive)) {
            throw 'The parent VHD has no active boot partition.'
        }
        $windowsVolume = $disk | Get-Partition | Get-Volume |
            Where-Object {
                $_.DriveLetter -and
                (Test-Path -LiteralPath "$($_.DriveLetter):\Windows\System32\ntoskrnl.exe")
            } |
            Select-Object -First 1
        if (-not $windowsVolume) {
            throw "No Windows installation was found in $VhdPath."
        }

        $kernel = Get-Item -LiteralPath "$($windowsVolume.DriveLetter):\Windows\System32\ntoskrnl.exe"
        if ($kernel.VersionInfo.ProductVersion -notlike '10.0.20348*') {
            throw "The parent VHD contains Windows version $($kernel.VersionInfo.ProductVersion), not Windows Server 2022."
        }

        $softwareHive = "$($windowsVolume.DriveLetter):\Windows\System32\Config\SOFTWARE"
        if (Test-Path -LiteralPath 'Registry::HKEY_LOCAL_MACHINE\Lab04OfflineSoftware') {
            [gc]::Collect()
            [gc]::WaitForPendingFinalizers()
            & reg.exe unload HKLM\Lab04OfflineSoftware | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw 'A stale Lab04OfflineSoftware registry hive could not be unloaded. Restart the host and retry.'
            }
        }
        & reg.exe load HKLM\Lab04OfflineSoftware $softwareHive | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw 'Failed to load the offline Windows SOFTWARE registry hive.'
        }
        $registryLoaded = $true
        return (Get-ItemProperty -Path 'HKLM:\Lab04OfflineSoftware\Microsoft\Windows NT\CurrentVersion').InstallationType
    }
    finally {
        if ($registryLoaded) {
            [gc]::Collect()
            [gc]::WaitForPendingFinalizers()
            & reg.exe unload HKLM\Lab04OfflineSoftware | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Warning 'The offline SOFTWARE registry hive did not unload cleanly. Restart the host before retrying.'
            }
        }
        if ($mountedVhd) {
            Dismount-VHD -Path $VhdPath -ErrorAction SilentlyContinue
        }
    }
}

function Get-Lab04ParentVhd {
    if (-not (Test-Path -LiteralPath $baseVhdPath -PathType Leaf)) {
        if ($VhdUri.Scheme -ne 'https') {
            throw 'The Windows Server parent VHD URI must use HTTPS.'
        }

        $downloadPath = "$baseVhdPath.download"
        if (Test-Path -LiteralPath $downloadPath) {
            Write-Output "Removing incomplete parent VHD download at $downloadPath before retrying."
            Remove-Item -LiteralPath $downloadPath -Force
        }

        Write-Output 'Downloading the Windows Server 2022 Evaluation VHD. This is approximately 9.5 GiB.'
        Start-BitsTransfer -Source $VhdUri.AbsoluteUri -Destination $downloadPath -Priority Foreground
        if ((Get-Item -LiteralPath $downloadPath).Length -lt 9GB) {
            throw 'The downloaded Windows Server VHD is smaller than expected.'
        }
        Move-Item -LiteralPath $downloadPath -Destination $baseVhdPath
    }
    elseif ((Get-Item -LiteralPath $baseVhdPath).Length -lt 9GB) {
        throw "The existing parent VHD at $baseVhdPath is smaller than expected. Supply a valid Desktop Experience VHD before retrying."
    }

    $installationType = Get-OfflineInstallationType -VhdPath $baseVhdPath
    if ($installationType -ne 'Server') {
        throw "The parent VHD installation type is '$installationType'. Lab 4 requires Windows Server with Desktop Experience, not Server Core."
    }
    Write-Output "Validated Desktop Experience parent VHD at $baseVhdPath."
}

function Initialize-LabSwitch {
    $switch = Get-VMSwitch -Name $switchName -ErrorAction SilentlyContinue
    if (-not $switch) {
        $switch = New-VMSwitch -Name $switchName -SwitchType Internal
    }
    elseif ($switch.SwitchType -ne 'Internal') {
        throw "The existing $switchName switch is not an internal Hyper-V switch."
    }

    $adapterAlias = "vEthernet ($switchName)"
    $gateway = Get-NetIPAddress -InterfaceAlias $adapterAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -eq '172.16.10.1' -and $_.PrefixLength -eq 16 }
    if (-not $gateway) {
        Get-NetIPAddress -InterfaceAlias $adapterAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Remove-NetIPAddress -Confirm:$false
        New-NetIPAddress -InterfaceAlias $adapterAlias -IPAddress '172.16.10.1' -PrefixLength 16 | Out-Null
    }

    $nat = Get-NetNat -Name $natName -ErrorAction SilentlyContinue
    if (-not $nat) {
        New-NetNat -Name $natName -InternalIPInterfaceAddressPrefix '172.16.0.0/16' | Out-Null
    }
    elseif ($nat.InternalIPInterfaceAddressPrefix -ne '172.16.0.0/16') {
        throw "The existing $natName NAT does not use 172.16.0.0/16."
    }
}

function New-UnattendContent {
    param([Parameter(Mandatory)][string]$ComputerName)

    $escapedPassword = [Security.SecurityElement]::Escape($plainPassword)
    return @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="specialize">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
      <ComputerName>$ComputerName</ComputerName>
    </component>
  </settings>
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
      <InputLocale>en-US</InputLocale>
      <SystemLocale>en-US</SystemLocale>
      <UILanguage>en-US</UILanguage>
      <UserLocale>en-US</UserLocale>
    </component>
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideLocalAccountScreen>true</HideLocalAccountScreen>
        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
        <NetworkLocation>Work</NetworkLocation>
        <ProtectYourPC>3</ProtectYourPC>
      </OOBE>
      <UserAccounts>
        <AdministratorPassword>
          <Value>$escapedPassword</Value>
          <PlainText>true</PlainText>
        </AdministratorPassword>
      </UserAccounts>
    </component>
  </settings>
</unattend>
"@
}

function Set-GuestUnattend {
    param(
        [Parameter(Mandatory)][string]$VhdPath,
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][string]$IPAddress
    )

    $mountedVhd = $null
    try {
        $mountedVhd = Mount-VHD -Path $VhdPath -Passthru
        $disk = $mountedVhd | Get-Disk
        $windowsVolume = $disk | Get-Partition | Get-Volume |
            Where-Object {
                $_.DriveLetter -and
                (Test-Path -LiteralPath "$($_.DriveLetter):\Windows\System32\ntoskrnl.exe")
            } |
            Select-Object -First 1
        if (-not $windowsVolume) {
            throw "No Windows installation was found in $VhdPath."
        }

        $windowsRoot = "$($windowsVolume.DriveLetter):\Windows"
        $pantherPath = Join-Path $windowsRoot 'Panther'
        New-Item -Path $pantherPath -ItemType Directory -Force | Out-Null
        $unattendContent = New-UnattendContent -ComputerName $ComputerName
        Set-Content -LiteralPath (Join-Path $pantherPath 'unattend.xml') `
            -Value $unattendContent -Encoding UTF8

        $setupScriptsPath = Join-Path $windowsRoot 'Setup\Scripts'
        New-Item -Path $setupScriptsPath -ItemType Directory -Force | Out-Null
        $setupComplete = @"
@echo off
netsh.exe interface ipv4 set address name="Ethernet" source=static address=$IPAddress mask=255.255.0.0 gateway=172.16.10.1 store=persistent
netsh.exe interface ipv4 set dnsservers name="Ethernet" source=static address=172.16.10.10 validate=no
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Enable-PSRemoting -Force -SkipNetworkProfileCheck; Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0; Enable-NetFirewallRule -Name 'RemoteDesktop-UserMode-In-TCP','RemoteDesktop-UserMode-In-UDP'; Set-Service -Name TermService -StartupType Automatic; Start-Service -Name TermService"
exit /b 0
"@
        Set-Content -LiteralPath (Join-Path $setupScriptsPath 'SetupComplete.cmd') `
            -Value $setupComplete -Encoding ASCII
    }
    finally {
        if ($mountedVhd) {
            Dismount-VHD -Path $VhdPath -ErrorAction SilentlyContinue
        }
    }
}

function New-LabGuest {
    param([Parameter(Mandatory)][hashtable]$Definition)

    $name = $Definition.Name
    $vmPath = Join-Path $vmRoot $name
    $childVhdPath = Join-Path $vmPath "$name.vhd"
    if (Get-VM -Name $name -ErrorAction SilentlyContinue) {
        Write-Output "$name already exists."
        return
    }

    New-Item -Path $vmPath -ItemType Directory -Force | Out-Null
    if (-not (Test-Path -LiteralPath $childVhdPath -PathType Leaf)) {
        New-VHD -Path $childVhdPath -ParentPath $baseVhdPath -Differencing | Out-Null
    }
    else {
        $childVhd = Get-VHD -Path $childVhdPath
        if ($childVhd.VhdType -ne 'Differencing' -or
            $childVhd.ParentPath -ne $baseVhdPath) {
            throw "The existing disk at $childVhdPath is not a child of the validated Lab 4 parent VHD."
        }
    }
    Set-GuestUnattend -VhdPath $childVhdPath -ComputerName $name `
        -IPAddress $Definition.IPAddress

    New-VM -Name $name -Generation 1 -Path $vmPath -VHDPath $childVhdPath `
        -MemoryStartupBytes $Definition.Memory -SwitchName $switchName | Out-Null
    Set-VM -Name $name -ProcessorCount 2 -DynamicMemory `
        -MemoryMinimumBytes 2GB -MemoryStartupBytes $Definition.Memory `
        -MemoryMaximumBytes $Definition.MaximumMemory -AutomaticCheckpointsEnabled $false
    Enable-VMIntegrationService -VMName $name -Name 'Guest Service Interface'
}

function Wait-LabGuest {
    param(
        [Parameter(Mandatory)][string]$VMName,
        [pscredential[]]$Credentials = @($localCredential, $domainCredential),
        [int]$MaximumAttempts = 90
    )

    for ($attempt = 1; $attempt -le $MaximumAttempts; $attempt++) {
        foreach ($credential in $Credentials) {
            try {
                Invoke-Command -VMName $VMName -Credential $credential -ScriptBlock {
                    $env:COMPUTERNAME
                } -ErrorAction Stop | Out-Null
                return $credential
            }
            catch {
            }
        }
        Start-Sleep -Seconds 10
    }
    throw "Timed out waiting for $VMName to accept PowerShell Direct connections."
}

function Restart-LabGuest {
    param(
        [Parameter(Mandatory)][string]$VMName,
        [Parameter(Mandatory)][pscredential]$Credential,
        [pscredential[]]$ReconnectCredentials = @($Credential),
        [datetime]$PreviousBootTime,
        [switch]$RestartRequested,
        [int]$MaximumAttempts = 90
    )

    if (-not $PreviousBootTime) {
        $PreviousBootTime = Invoke-Command -VMName $VMName -Credential $Credential -ScriptBlock {
            (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
        } -ErrorAction Stop
    }
    if (-not $RestartRequested) {
        Invoke-Command -VMName $VMName -Credential $Credential -ScriptBlock {
            shutdown.exe /r /t 5 /f
            if ($LASTEXITCODE -ne 0) {
                throw 'Windows rejected the restart request.'
            }
        } -ErrorAction Stop
    }

    for ($attempt = 1; $attempt -le $MaximumAttempts; $attempt++) {
        foreach ($reconnectCredential in $ReconnectCredentials) {
            try {
                $currentBootTime = Invoke-Command -VMName $VMName `
                    -Credential $reconnectCredential -ScriptBlock {
                    (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
                } -ErrorAction Stop
                if ($currentBootTime -gt $PreviousBootTime) {
                    return $reconnectCredential
                }
            }
            catch {
            }
        }
        Start-Sleep -Seconds 10
    }
    throw "Timed out waiting for $VMName to complete a graceful restart."
}

function Wait-LabGuestSetupComplete {
    param(
        [Parameter(Mandatory)][string]$VMName,
        [pscredential[]]$Credentials = @($localCredential, $domainCredential),
        [int]$MaximumAttempts = 90
    )

    for ($attempt = 1; $attempt -le $MaximumAttempts; $attempt++) {
        foreach ($credential in $Credentials) {
            try {
                $setupComplete = Invoke-Command -VMName $VMName -Credential $credential -ScriptBlock {
                    $setup = Get-ItemProperty -Path 'HKLM:\SYSTEM\Setup'
                    $state = Get-ItemProperty `
                        -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State' `
                        -ErrorAction SilentlyContinue
                    return [bool](
                        $setup.OOBEInProgress -eq 0 -and
                        $setup.SystemSetupInProgress -eq 0 -and
                        $setup.SetupType -eq 0 -and
                        $state.ImageState -eq 'IMAGE_STATE_COMPLETE' -and
                        -not (Get-Process -Name setuphost, windeploy -ErrorAction SilentlyContinue)
                    )
                } -ErrorAction Stop
                if ($setupComplete | Select-Object -Last 1) {
                    return $credential
                }
            }
            catch {
            }
        }
        Start-Sleep -Seconds 10
    }
    throw "Timed out waiting for Windows setup to complete on $VMName."
}

function Wait-LabDomain {
    param([int]$MaximumAttempts = 60)

    for ($attempt = 1; $attempt -le $MaximumAttempts; $attempt++) {
        try {
            $ready = Invoke-Command -VMName 'SEA-DC1' -Credential $domainCredential -ScriptBlock {
                $services = Get-Service -Name NTDS, DNS, Kdc, Netlogon, ADWS -ErrorAction Stop
                if (@($services | Where-Object Status -ne 'Running').Count -gt 0) {
                    return $false
                }
                Import-Module ActiveDirectory -ErrorAction Stop
                Get-ADDomain -Identity 'contoso.com' -ErrorAction Stop | Out-Null
                Resolve-DnsName -Name '_ldap._tcp.dc._msdcs.contoso.com' -Type SRV `
                    -Server '172.16.10.10' -ErrorAction Stop | Out-Null
                return $true
            } -ErrorAction Stop
            if ($ready | Select-Object -Last 1) {
                return
            }
        }
        catch {
        }
        Start-Sleep -Seconds 10
    }
    throw 'Timed out waiting for contoso.com AD DS and DNS services to become ready.'
}

function Set-LabGuestNetwork {
    param(
        [Parameter(Mandatory)][hashtable]$Definition,
        [Parameter(Mandatory)][pscredential]$Credential
    )

    Invoke-Command -VMName $Definition.Name -Credential $Credential -ScriptBlock {
        param($IPAddress, $ComputerName)
        $ErrorActionPreference = 'Stop'
        $adapter = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1
        if (-not $adapter) {
            throw 'No active network adapter was found.'
        }

        $expectedAddress = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 `
            -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -eq $IPAddress -and $_.PrefixLength -eq 16 }
        $expectedGateway = Get-NetRoute -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 `
            -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
            Where-Object NextHop -eq '172.16.10.1'
        $dhcpEnabled = (Get-NetIPInterface -InterfaceIndex $adapter.ifIndex `
            -AddressFamily IPv4).Dhcp -eq 'Enabled'
        if (-not $expectedAddress -or -not $expectedGateway -or $dhcpEnabled) {
            & netsh.exe interface ipv4 set address name="$($adapter.Name)" source=static `
                address=$IPAddress mask=255.255.0.0 gateway=172.16.10.1 store=persistent | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to persist the IPv4 address on $ComputerName."
            }
        }
        & netsh.exe interface ipv4 set dnsservers name="$($adapter.Name)" source=static `
            address=172.16.10.10 validate=no | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to persist the DNS server on $ComputerName."
        }

        $networkRepairPath = 'C:\Windows\Temp\Set-Lab04Network.ps1'
        @'
param([Parameter(Mandatory)][string]$IPAddress)
$ErrorActionPreference = 'Stop'
for ($attempt = 1; $attempt -le 60; $attempt++) {
    $adapter = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1
    if ($adapter) {
        break
    }
    Start-Sleep -Seconds 5
}
if (-not $adapter) {
    throw 'No active network adapter was found.'
}
Start-Sleep -Seconds 30
& netsh.exe interface ipv4 set address name="$($adapter.Name)" source=static address=$IPAddress mask=255.255.0.0 gateway=172.16.10.1 store=persistent | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to restore the Lab 4 IPv4 address.'
}
& netsh.exe interface ipv4 set dnsservers name="$($adapter.Name)" source=static address=172.16.10.10 validate=no | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to restore the Lab 4 DNS server.'
}
Unregister-ScheduledTask -TaskName 'Lab04NetworkRepair' -Confirm:$false -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
'@ | Set-Content -LiteralPath $networkRepairPath -Encoding ASCII
        $repairAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument `
            "-NoProfile -ExecutionPolicy Bypass -File `"$networkRepairPath`" -IPAddress $IPAddress"
        $repairTrigger = New-ScheduledTaskTrigger -AtStartup
        $repairPrincipal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount `
            -RunLevel Highest
        Register-ScheduledTask -TaskName 'Lab04NetworkRepair' -Action $repairAction `
            -Trigger $repairTrigger -Principal $repairPrincipal -Force | Out-Null

        if ($env:COMPUTERNAME -ne $ComputerName) {
            Rename-Computer -NewName $ComputerName -Force
        }
        Enable-PSRemoting -Force -SkipNetworkProfileCheck
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' `
            -Name fDenyTSConnections -Value 0
        Enable-NetFirewallRule -Name 'RemoteDesktop-UserMode-In-TCP', 'RemoteDesktop-UserMode-In-UDP'
        Set-Service -Name TermService -StartupType Automatic
        Start-Service -Name TermService
        Remove-Item -LiteralPath 'C:\Windows\Panther\unattend.xml' -Force -ErrorAction SilentlyContinue
    } -ArgumentList $Definition.IPAddress, $Definition.Name
}

function Test-LabGuestNetwork {
    param(
        [Parameter(Mandatory)][hashtable]$Definition,
        [Parameter(Mandatory)][pscredential]$Credential
    )

    return Invoke-Command -VMName $Definition.Name -Credential $Credential -ScriptBlock {
        param($ExpectedIPAddress)
        $adapter = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1
        if (-not $adapter) {
            return $false
        }
        $address = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 `
            -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -eq $ExpectedIPAddress -and $_.PrefixLength -eq 16 }
        $gateway = Get-NetRoute -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 `
            -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
            Where-Object NextHop -eq '172.16.10.1'
        $dns = (Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex `
            -AddressFamily IPv4).ServerAddresses
        $dhcpDisabled = (Get-NetIPInterface -InterfaceIndex $adapter.ifIndex `
            -AddressFamily IPv4).Dhcp -eq 'Disabled'
        return [bool]($address -and $gateway -and $dns -contains '172.16.10.10' -and $dhcpDisabled)
    } -ArgumentList $Definition.IPAddress
}

function Wait-LabGuestNetwork {
    param(
        [Parameter(Mandatory)][hashtable]$Definition,
        [Parameter(Mandatory)][pscredential]$Credential,
        [int]$MaximumAttempts = 30
    )

    for ($attempt = 1; $attempt -le $MaximumAttempts; $attempt++) {
        if (Test-LabGuestNetwork -Definition $Definition -Credential $Credential) {
            return $true
        }
        Start-Sleep -Seconds 5
    }
    return $false
}

function Initialize-LabGuest {
    param([Parameter(Mandatory)][hashtable]$Definition)

    New-LabGuest -Definition $Definition
    if ((Get-VM -Name $Definition.Name).State -ne 'Running') {
        Start-VM -Name $Definition.Name
    }

    $credential = Wait-LabGuestSetupComplete -VMName $Definition.Name
    Set-LabGuestNetwork -Definition $Definition -Credential $credential
    $credential = Restart-LabGuest -VMName $Definition.Name -Credential $credential
    if (-not (Wait-LabGuestNetwork -Definition $Definition -Credential $credential)) {
        Write-Output "$($Definition.Name) networking was reset during first boot; reapplying it."
        Set-LabGuestNetwork -Definition $Definition -Credential $credential
        $credential = Restart-LabGuest -VMName $Definition.Name -Credential $credential
    }
    if (-not (Wait-LabGuestNetwork -Definition $Definition -Credential $credential)) {
        throw "$($Definition.Name) did not retain its Lab 4 network configuration after two restarts."
    }
}

function Join-LabDomain {
    param([Parameter(Mandatory)][hashtable]$Definition)

    $VMName = $Definition.Name
    $memberCredential = Wait-LabGuest -VMName $VMName
    $memberBootTime = Invoke-Command -VMName $VMName -Credential $memberCredential -ScriptBlock {
        (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    }
    $joined = Invoke-Command -VMName $VMName -Credential $memberCredential -ScriptBlock {
        param($Password)
        $ErrorActionPreference = 'Stop'
        $computerSystem = Get-CimInstance Win32_ComputerSystem
        if ($computerSystem.PartOfDomain -and $computerSystem.Domain -eq 'contoso.com') {
            return $false
        }
        if ($computerSystem.PartOfDomain) {
            throw "The computer is joined to $($computerSystem.Domain), not contoso.com."
        }
        $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
        $credential = [pscredential]::new('CONTOSO\Administrator', $securePassword)
        Add-Computer -DomainName 'contoso.com' -Credential $credential -Force
        shutdown.exe /r /t 5 /f
        if ($LASTEXITCODE -ne 0) {
            throw 'Windows rejected the post-domain-join restart request.'
        }
        return $true
    } -ArgumentList $plainPassword
    if ($joined | Select-Object -Last 1) {
        Restart-LabGuest -VMName $VMName -Credential $domainCredential `
            -ReconnectCredentials @($domainCredential) -PreviousBootTime $memberBootTime `
            -RestartRequested | Out-Null
    }
    Wait-LabGuest -VMName $VMName -Credentials @($domainCredential) | Out-Null
    if (-not (Wait-LabGuestNetwork -Definition $Definition -Credential $domainCredential)) {
        throw "$VMName did not retain its Lab 4 network configuration after joining the domain."
    }
}

Write-Step 'Verifying Hyper-V'
if (-not (Get-WindowsFeature -Name Hyper-V).Installed) {
    throw 'The Hyper-V role is not installed on the Azure host.'
}
if ((Get-Service -Name vmms).Status -ne 'Running') {
    throw 'The Hyper-V Virtual Machine Management service is not running.'
}

if ($Phase -in @('All', 'PrepareHost')) {
    Write-Step 'Preparing storage, networking, and the parent VHD'
    Initialize-LabDataDisk
    Initialize-LabSwitch
    Get-Lab04ParentVhd
}

if ($Phase -in @('All', 'CreateDomainController', 'CreateServer', 'CreateAdmin')) {
    $phaseDefinitions = switch ($Phase) {
        'CreateDomainController' { @($vmDefinitions | Where-Object Name -eq 'SEA-DC1') }
        'CreateServer' { @($vmDefinitions | Where-Object Name -eq 'SEA-SVR1') }
        'CreateAdmin' { @($vmDefinitions | Where-Object Name -eq 'SEA-ADM1') }
        default { $vmDefinitions }
    }
    Write-Step "Creating $($phaseDefinitions.Name -join ', ')"
    Initialize-LabDataDisk
    Initialize-LabSwitch
    Get-Lab04ParentVhd
    foreach ($definition in $phaseDefinitions) {
        Initialize-LabGuest -Definition $definition
    }
}

if ($Phase -in @('All', 'PromoteDomainController')) {
    Write-Step 'Creating the contoso.com domain'
    $dcCredential = Wait-LabGuest -VMName 'SEA-DC1'
    $dcBootTime = Invoke-Command -VMName 'SEA-DC1' -Credential $dcCredential -ScriptBlock {
        (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    }
    $promoted = Invoke-Command -VMName 'SEA-DC1' -Credential $dcCredential -ScriptBlock {
        param($Password)
        $ErrorActionPreference = 'Stop'
        $computerSystem = Get-CimInstance Win32_ComputerSystem
        if ($computerSystem.DomainRole -ge 4 -and $computerSystem.Domain -eq 'contoso.com') {
            return $false
        }
        Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools | Out-Null
        Import-Module ADDSDeployment
        $safeModePassword = ConvertTo-SecureString $Password -AsPlainText -Force
        Install-ADDSForest -DomainName 'contoso.com' -DomainNetbiosName 'CONTOSO' `
            -SafeModeAdministratorPassword $safeModePassword -InstallDns:$true `
            -NoRebootOnCompletion:$true -Force:$true | Out-Null
        shutdown.exe /r /t 5 /f
        if ($LASTEXITCODE -ne 0) {
            throw 'Windows rejected the post-promotion restart request.'
        }
        return $true
    } -ArgumentList $plainPassword
    if ($promoted | Select-Object -Last 1) {
        Restart-LabGuest -VMName 'SEA-DC1' -Credential $domainCredential `
            -ReconnectCredentials @($domainCredential) -PreviousBootTime $dcBootTime `
            -RestartRequested | Out-Null
    }
    Wait-LabGuest -VMName 'SEA-DC1' -Credentials @($domainCredential) | Out-Null
    Invoke-Command -VMName 'SEA-DC1' -Credential $domainCredential -ScriptBlock {
        $ErrorActionPreference = 'Stop'
        $adapter = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1
        Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses '172.16.10.10'
        Set-Service -Name ADWS -StartupType Automatic
        Start-Service -Name ADWS
        Set-Service -Name Kdc -StartupType Automatic
        Start-Service -Name Kdc
        Restart-Service -Name DNS
        Restart-Service -Name Netlogon
        ipconfig.exe /registerdns | Out-Null
        nltest.exe /dsregdns | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw 'The domain controller DNS records could not be registered.'
        }
    }
    Wait-LabDomain
    $dcDefinition = $vmDefinitions | Where-Object Name -eq 'SEA-DC1'
    if (-not (Wait-LabGuestNetwork -Definition $dcDefinition -Credential $domainCredential)) {
        throw 'SEA-DC1 did not retain its Lab 4 network configuration after promotion.'
    }

}

if ($Phase -in @('All', 'JoinServer')) {
    Write-Step 'Joining SEA-SVR1 to contoso.com'
    Join-LabDomain -Definition ($vmDefinitions | Where-Object Name -eq 'SEA-SVR1')
}

if ($Phase -in @('All', 'JoinAdmin')) {
    Write-Step 'Joining SEA-ADM1 to contoso.com'
    Join-LabDomain -Definition ($vmDefinitions | Where-Object Name -eq 'SEA-ADM1')
}

if ($Phase -in @('All', 'ConfigureLab')) {
    Write-Step 'Applying Lab 4 prerequisites'
    Invoke-Command -VMName 'SEA-DC1' -Credential $domainCredential -ScriptBlock {
    $ErrorActionPreference = 'Stop'
    Install-WindowsFeature -Name DHCP -IncludeManagementTools | Out-Null
    Import-Module DhcpServer
    if (-not (Get-DhcpServerInDC | Where-Object IPAddress -eq '172.16.10.10')) {
        Add-DhcpServerInDC -DnsName 'SEA-DC1.contoso.com' -IPAddress '172.16.10.10'
    }
    if (-not (Get-DhcpServerv4Scope -ScopeId '172.16.0.0' -ErrorAction SilentlyContinue)) {
        Add-DhcpServerv4Scope -Name 'Contoso' -StartRange '172.16.0.100' `
            -EndRange '172.16.0.200' -SubnetMask '255.255.0.0' -State Active
    }
    $scope = Get-DhcpServerv4Scope -ScopeId '172.16.0.0'
    if ($scope.Name -ne 'Contoso' -or $scope.StartRange -ne '172.16.0.100' -or
        $scope.EndRange -ne '172.16.0.200' -or $scope.SubnetMask -ne '255.255.0.0') {
        throw 'The existing 172.16.0.0 DHCP scope does not match the Lab 4 baseline.'
    }
    Set-DhcpServerv4OptionValue -ScopeId '172.16.0.0' -DnsServer '172.16.10.10' `
        -DnsDomain 'contoso.com' -Router '172.16.10.1'
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager\Roles\12' `
        -Name ConfigurationState -Value 2 -ErrorAction SilentlyContinue
    Start-Service -Name DHCPServer
    }

    Invoke-Command -VMName 'SEA-ADM1' -Credential $domainCredential -ScriptBlock {
    $ErrorActionPreference = 'Stop'
    $features = @('RSAT-DHCP', 'RSAT-DNS-Server', 'RSAT-AD-Tools')
    Install-WindowsFeature -Name $features -IncludeAllSubFeature | Out-Null
    if (Get-WindowsFeature -Name $features | Where-Object { -not $_.Installed }) {
        throw 'One or more required DHCP, DNS, or AD management tools failed to install.'
    }
    if (-not (Test-Path 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe')) {
        throw 'Microsoft Edge is required but was not found.'
    }
    if (-not (Get-Service -Name BITS -ErrorAction SilentlyContinue)) {
        throw 'Background Intelligent Transfer Service (BITS) is required but was not found.'
    }
    $endpointReady = $false
    for ($attempt = 1; $attempt -le 12; $attempt++) {
        if (Test-NetConnection -ComputerName 'aka.ms' -Port 443 `
                -InformationLevel Quiet -WarningAction SilentlyContinue) {
            $endpointReady = $true
            break
        }
        Start-Sleep -Seconds 10
    }
    if (-not $endpointReady) {
        throw 'SEA-ADM1 cannot connect to the Windows Admin Center download endpoint over HTTPS.'
    }
    Set-Item WSMan:\localhost\client\trustedhosts -Value '*.contoso.com' -Force
    }

    Invoke-Command -VMName 'SEA-SVR1' -Credential $domainCredential -ScriptBlock {
    $ErrorActionPreference = 'Stop'
    Enable-PSRemoting -Force -SkipNetworkProfileCheck
        if ((Get-Service -Name WinRM).Status -ne 'Running') {
            throw 'WinRM is not running on SEA-SVR1.'
        }
    }

    foreach ($definition in $vmDefinitions) {
        Invoke-Command -VMName $definition.Name -Credential $domainCredential -ScriptBlock {
            $ErrorActionPreference = 'Stop'
            Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' `
                -Name fDenyTSConnections -Value 0
            Enable-NetFirewallRule -DisplayGroup 'Remote Desktop'
            Set-Service -Name TermService -StartupType Automatic
            Start-Service -Name TermService
            if (-not (Get-NetTCPConnection -LocalPort 3389 -State Listen -ErrorAction SilentlyContinue)) {
                throw "Remote Desktop is not listening on $env:COMPUTERNAME."
            }
        }
    }
}

if ($Phase -in @('All', 'Validate')) {
    Write-Step 'Validating the Lab 4 environment'
    $validation = foreach ($definition in $vmDefinitions) {
        Invoke-Command -VMName $definition.Name -Credential $domainCredential -ScriptBlock {
            param($ExpectedIPAddress)
            $computerSystem = Get-CimInstance Win32_ComputerSystem
            $adapter = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1
            $ipv4Address = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 |
                Where-Object IPAddress -like '172.16.*' |
                Select-Object -First 1 -ExpandProperty IPAddress
            $ipInterface = Get-NetIPInterface -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4
            $dnsServers = (Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex `
                -AddressFamily IPv4).ServerAddresses
            $defaultGateway = Get-NetRoute -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 `
                -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
                Select-Object -First 1 -ExpandProperty NextHop
            if ($computerSystem.Domain -ne 'contoso.com') {
                throw "$env:COMPUTERNAME is joined to $($computerSystem.Domain), not contoso.com."
            }
            if ($ipv4Address -ne $ExpectedIPAddress) {
                throw "$env:COMPUTERNAME uses $ipv4Address instead of $ExpectedIPAddress."
            }
            if ($ipInterface.Dhcp -ne 'Disabled' -or $defaultGateway -ne '172.16.10.1' -or
                $dnsServers -notcontains '172.16.10.10') {
                throw "$env:COMPUTERNAME does not have the required persistent static network configuration."
            }
            if ((Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' `
                    -Name fDenyTSConnections).fDenyTSConnections -ne 0) {
                throw "Remote Desktop is disabled on $env:COMPUTERNAME."
            }
            if (-not (Get-NetTCPConnection -LocalPort 3389 -State Listen -ErrorAction SilentlyContinue)) {
                throw "Remote Desktop is not listening on $env:COMPUTERNAME."
            }
            [pscustomobject]@{
                ComputerName = $env:COMPUTERNAME
                Domain = $computerSystem.Domain
                IPv4Address = $ipv4Address
            }
        } -ArgumentList $definition.IPAddress
    }

    Invoke-Command -VMName 'SEA-DC1' -Credential $domainCredential -ScriptBlock {
        Import-Module ActiveDirectory
        Resolve-DnsName -Name '_ldap._tcp.dc._msdcs.contoso.com' -Type SRV `
            -Server '172.16.10.10' -ErrorAction Stop | Out-Null
        Get-ADDomain -Identity 'contoso.com' -ErrorAction Stop | Out-Null
        if (-not (Get-WindowsFeature -Name DHCP).Installed) {
            throw 'The DHCP Server role is not installed on SEA-DC1.'
        }
        if ((Get-Service -Name DHCPServer).Status -ne 'Running') {
            throw 'The DHCP Server service is not running on SEA-DC1.'
        }
        $scope = Get-DhcpServerv4Scope -ScopeId '172.16.0.0' -ErrorAction SilentlyContinue
        if (-not $scope) {
            throw 'The Contoso DHCP scope is missing on SEA-DC1.'
        }
        if ($scope.Name -ne 'Contoso' -or $scope.StartRange -ne '172.16.0.100' -or
            $scope.EndRange -ne '172.16.0.200' -or $scope.SubnetMask -ne '255.255.0.0') {
            throw 'The Contoso DHCP scope does not match the Lab 4 starting state.'
        }
        if (-not (Get-DhcpServerInDC | Where-Object IPAddress -eq '172.16.10.10')) {
            throw 'SEA-DC1 is not authorized as a DHCP server in Active Directory.'
        }
    }

    Invoke-Command -VMName 'SEA-ADM1' -Credential $domainCredential -ScriptBlock {
        $requiredFeatures = @('RSAT-DHCP', 'RSAT-DNS-Server', 'RSAT-AD-Tools')
        if (Get-WindowsFeature -Name $requiredFeatures | Where-Object { -not $_.Installed }) {
            throw 'SEA-ADM1 is missing required DHCP, DNS, or AD management tools.'
        }
        if (-not (Test-Path 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe')) {
            throw 'Microsoft Edge is missing on SEA-ADM1.'
        }
    }

    Invoke-Command -VMName 'SEA-SVR1' -Credential $domainCredential -ScriptBlock {
        if (Get-WindowsFeature -Name DHCP, DNS | Where-Object Installed) {
            throw 'SEA-SVR1 already has DHCP or DNS installed; the learner starting state is not clean.'
        }
    }

    foreach ($definition in $vmDefinitions) {
        if (-not (Test-NetConnection -ComputerName $definition.IPAddress -Port 3389 `
                -InformationLevel Quiet)) {
            throw "The Hyper-V host cannot reach $($definition.Name) on TCP 3389."
        }
    }
    $validation | Format-Table -AutoSize | Out-String | Write-Output

    foreach ($definition in $vmDefinitions) {
        if (-not (Get-VMCheckpoint -VMName $definition.Name -Name 'Lab04-Ready' -ErrorAction SilentlyContinue)) {
            Checkpoint-VM -VMName $definition.Name -SnapshotName 'Lab04-Ready'
        }
    }

    Write-Output 'Lab 4 nested environment is ready. RDP to this host, then connect to 172.16.10.11 as CONTOSO\Administrator.'
}

Write-Output "LAB04_PHASE_COMPLETE:$Phase"