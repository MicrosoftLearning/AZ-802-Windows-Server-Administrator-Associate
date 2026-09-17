# Manual Local Hyper-V Setup — AZ-802 Lab Environment

Step-by-step instructions to build the lab environment on a local Hyper-V host.

## Host Requirements

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| **RAM** | 32 GB | 64 GB |
| **CPU** | 8 cores | 12+ cores |
| **Free disk** | 200 GB | 400 GB (SSD) |
| **OS** | Windows 10/11 Pro or Windows Server 2019/2022 with Hyper-V |
| **Nested virt** | Required for Lab 03 (Hyper-V inside SEA-SVR1) |

## Windows Server 2022 ISO

Download from the Microsoft Evaluation Center:
https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022

---

## Step 1: Create Virtual Switch

1. Open **Hyper-V Manager**
2. **Virtual Switch Manager** > **New virtual network switch**
3. Create an **Internal** switch named `LabSwitch`

**PowerShell**:
```powershell
New-VMSwitch -Name 'LabSwitch' -SwitchType Internal
```

If you need internet access from the VMs (Labs 02, 03, 04, 05, 06), create a NAT network instead:

```powershell
New-VMSwitch -Name 'LabSwitch' -SwitchType Internal
$ifIndex = (Get-NetAdapter | Where-Object { $_.Name -like '*LabSwitch*' }).ifIndex
New-NetIPAddress -IPAddress 172.16.10.1 -PrefixLength 16 -InterfaceIndex $ifIndex
New-NetNat -Name 'LabNAT' -InternalIPInterfaceAddressPrefix '172.16.0.0/16'
```

---

## Step 2: Create VMs

### Common Settings

| Setting | Value |
|---------|-------|
| Generation | 2 |
| Memory | 4096 MB (dynamic recommended) |
| Switch | `LabSwitch` |
| Secure Boot | Microsoft UEFI CA |

### VM 1: SEA-DC1

```powershell
$VMName = 'SEA-DC1'
New-VM -Name $VMName -MemoryStartupBytes 4GB -Generation 2 -NewVHDPath "C:\VMs\$VMName\$VMName.vhdx" -NewVHDSizeBytes 128GB -SwitchName 'LabSwitch'
Set-VM -Name $VMName -DynamicMemory -MemoryMinimumBytes 2GB -MemoryMaximumBytes 4GB -ProcessorCount 2
Add-VMDvdDrive -VMName $VMName -Path 'C:\ISO\WindowsServer2022.iso'
Set-VMFirmware -VMName $VMName -FirstBootDevice (Get-VMDvdDrive -VMName $VMName)
```

### VM 2: SEA-ADM1

```powershell
$VMName = 'SEA-ADM1'
New-VM -Name $VMName -MemoryStartupBytes 4GB -Generation 2 -NewVHDPath "C:\VMs\$VMName\$VMName.vhdx" -NewVHDSizeBytes 128GB -SwitchName 'LabSwitch'
Set-VM -Name $VMName -DynamicMemory -MemoryMinimumBytes 2GB -MemoryMaximumBytes 4GB -ProcessorCount 2
Add-VMDvdDrive -VMName $VMName -Path 'C:\ISO\WindowsServer2022.iso'
Set-VMFirmware -VMName $VMName -FirstBootDevice (Get-VMDvdDrive -VMName $VMName)
```

### VM 3: SEA-SVR1

```powershell
$VMName = 'SEA-SVR1'
New-VM -Name $VMName -MemoryStartupBytes 4GB -Generation 2 -NewVHDPath "C:\VMs\$VMName\$VMName.vhdx" -NewVHDSizeBytes 128GB -SwitchName 'LabSwitch'
Set-VM -Name $VMName -DynamicMemory -MemoryMinimumBytes 2GB -MemoryMaximumBytes 4GB -ProcessorCount 2
Add-VMDvdDrive -VMName $VMName -Path 'C:\ISO\WindowsServer2022.iso'
Set-VMFirmware -VMName $VMName -FirstBootDevice (Get-VMDvdDrive -VMName $VMName)

# Add the Lab 05 data disk
$dataVhdPath = "C:\VMs\$VMName\$VMName-Data1.vhdx"
New-VHD -Path $dataVhdPath -SizeBytes 128GB -Dynamic
Add-VMHardDiskDrive -VMName $VMName -Path $dataVhdPath

# Enable nested virtualization (required for Lab 03)
Set-VMProcessor -VMName $VMName -ExposeVirtualizationExtensions $true
```

### VM 4: SEA-SVR2

```powershell
$VMName = 'SEA-SVR2'
New-VM -Name $VMName -MemoryStartupBytes 4GB -Generation 2 -NewVHDPath "C:\VMs\$VMName\$VMName.vhdx" -NewVHDSizeBytes 128GB -SwitchName 'LabSwitch'
Set-VM -Name $VMName -DynamicMemory -MemoryMinimumBytes 2GB -MemoryMaximumBytes 4GB -ProcessorCount 2
Add-VMDvdDrive -VMName $VMName -Path 'C:\ISO\WindowsServer2022.iso'
Set-VMFirmware -VMName $VMName -FirstBootDevice (Get-VMDvdDrive -VMName $VMName)

# Add the Lab 05 data disk
$dataVhdPath = "C:\VMs\$VMName\$VMName-Data1.vhdx"
New-VHD -Path $dataVhdPath -SizeBytes 128GB -Dynamic
Add-VMHardDiskDrive -VMName $VMName -Path $dataVhdPath
```

### VM 5: SEA-SVR3 (with 4 extra data disks)

```powershell
$VMName = 'SEA-SVR3'
New-VM -Name $VMName -MemoryStartupBytes 4GB -Generation 2 -NewVHDPath "C:\VMs\$VMName\$VMName.vhdx" -NewVHDSizeBytes 128GB -SwitchName 'LabSwitch'
Set-VM -Name $VMName -DynamicMemory -MemoryMinimumBytes 2GB -MemoryMaximumBytes 4GB -ProcessorCount 2
Add-VMDvdDrive -VMName $VMName -Path 'C:\ISO\WindowsServer2022.iso'
Set-VMFirmware -VMName $VMName -FirstBootDevice (Get-VMDvdDrive -VMName $VMName)

# Add 4 data disks (128 GB each)
for ($i = 1; $i -le 4; $i++) {
    $vhdPath = "C:\VMs\$VMName\$VMName-Data$i.vhdx"
    New-VHD -Path $vhdPath -SizeBytes 128GB -Dynamic
    Add-VMHardDiskDrive -VMName $VMName -Path $vhdPath
}
```

---

## Step 3: Install Windows Server 2022

Boot each VM and install from ISO:

| VM | Edition | Experience |
|----|---------|-----------|
| SEA-DC1 | Datacenter | **Desktop Experience** |
| SEA-ADM1 | Datacenter | **Desktop Experience** |
| SEA-SVR1 | Datacenter | **Server Core** (no Desktop Experience) |
| SEA-SVR2 | Datacenter | **Desktop Experience** |
| SEA-SVR3 | Datacenter | **Server Core** (no Desktop Experience) |

Set the local Administrator password to `PA55w.rd1234` on all VMs.

After install, remove the DVD drive and set the hard disk as first boot device.

---

## Step 4: Configure Networking

On each VM, assign a static IP. Run from an elevated PowerShell:

### SEA-DC1
```powershell
$adapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress 172.16.10.10 -PrefixLength 16 -DefaultGateway 172.16.10.1
Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses 172.16.10.10
Rename-Computer -NewName 'SEA-DC1' -Restart
```

### SEA-ADM1
```powershell
$adapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress 172.16.10.11 -PrefixLength 16 -DefaultGateway 172.16.10.1
Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses 172.16.10.10
Rename-Computer -NewName 'SEA-ADM1' -Restart
```

### SEA-SVR1
```powershell
$adapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress 172.16.10.12 -PrefixLength 16 -DefaultGateway 172.16.10.1
Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses 172.16.10.10
Rename-Computer -NewName 'SEA-SVR1' -Restart
```

### SEA-SVR2
```powershell
$adapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress 172.16.10.13 -PrefixLength 16 -DefaultGateway 172.16.10.1
Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses 172.16.10.10
Rename-Computer -NewName 'SEA-SVR2' -Restart
```

### SEA-SVR3
```powershell
$adapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress 172.16.10.14 -PrefixLength 16 -DefaultGateway 172.16.10.1
Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses 172.16.10.10
Rename-Computer -NewName 'SEA-SVR3' -Restart
```

---

## Step 5: Promote SEA-DC1 to Domain Controller

On SEA-DC1:

```powershell
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
Import-Module ADDSDeployment

$password = ConvertTo-SecureString 'PA55w.rd1234' -AsPlainText -Force
Install-ADDSForest `
    -DomainName 'contoso.com' `
    -DomainNetbiosName 'CONTOSO' `
    -SafeModeAdministratorPassword $password `
    -InstallDns:$true `
    -Force:$true
```

Wait for restart (~5 minutes). Sign back in as `CONTOSO\Administrator`.

---

## Step 6: Join Member Servers to Domain

After SEA-DC1 is operational, join each member server.

### From SEA-ADM1 and SEA-SVR2 (Desktop Experience)

```powershell
$cred = Get-Credential -Message "Enter CONTOSO\Administrator credentials"
Add-Computer -DomainName 'contoso.com' -Credential $cred -Restart -Force
```

### From SEA-SVR1 and SEA-SVR3 (Server Core — use SConfig)

1. At the SConfig menu, select **1) Domain/Workgroup**
2. Select **D** for Domain
3. Enter `contoso.com`
4. Enter `CONTOSO\Administrator` and password
5. Restart when prompted

Or via PowerShell:
```powershell
$cred = Get-Credential 'CONTOSO\Administrator'
Add-Computer -DomainName 'contoso.com' -Credential $cred -Restart -Force
```

---

## Step 7: Lab-Specific Configuration

### Lab 01: Identity Services and Group Policy
- On SEA-ADM1: Install RSAT (`Install-WindowsFeature RSAT-AD-Tools, GPMC, RSAT-DNS-Server`)
- SEA-SVR1: Ensure WinRM is enabled (`Enable-PSRemoting -Force`)

### Lab 02: Managing Windows Server
- On SEA-ADM1: Ensure internet access (WAC is downloaded during lab)

### Lab 03: Virtualization

From an elevated Windows PowerShell session on the Hyper-V host, run `Setup-Lab03.ps1`. The script enables nested virtualization, installs Hyper-V, downloads the Windows Server 2022 Datacenter Evaluation parent VHD, and installs the Hyper-V management tools:

```powershell
.\Setup-Lab03.ps1
```

If you downloaded the Evaluation Center VHD ahead of time, provide its location on the Hyper-V host:

```powershell
.\Setup-Lab03.ps1 -BaseImageVhdPath 'D:\VHD\WindowsServer2022.vhd'
```

SEA-SVR1 requires at least 20 GB of free space on its C: drive. The standard 128-GB virtual disk provides sufficient capacity after a normal Server Core installation.

### Lab 04: Network Infrastructure
- On SEA-DC1:
  - Install DHCP: `Install-WindowsFeature DHCP -IncludeManagementTools`
  - Authorize in AD: `Add-DhcpServerInDC -DnsName SEA-DC1.contoso.com -IPAddress 172.16.10.10`
  - Create Contoso scope: `Add-DhcpServerv4Scope -Name Contoso -StartRange 172.16.0.100 -EndRange 172.16.0.200 -SubnetMask 255.255.0.0 -State Active`
- On SEA-ADM1: Install RSAT (`RSAT-DHCP, RSAT-DNS-Server`)

### Lab 05: Azure File Sync
- On SEA-ADM1:
  - Install DFS tools: `Install-WindowsFeature RSAT-DFS-Mgmt-Con`
  - Copy `DeployDFS.ps1`, `File1.txt`, and `Install-FileSyncServerCore.ps1` from `Allfiles\AZ802-Lab05` to `C:\Labfiles\Lab05\`
- On SEA-SVR1 and SEA-SVR2: Verify that disk 1 is online, writable, and uninitialized (`RAW`)
- Requires Azure subscription

### Lab 06: Storage Solutions
- On SEA-SVR3:
  - Verify 4 data disks are present and offline: `Get-Disk`
  - Set all data disks offline: `1..4 | ForEach-Object { Set-Disk -Number $_ -IsOffline $true }`
- On SEA-ADM1:
  - Create `C:\Labfiles\Lab06\CreateLabFiles.cmd`
  - Share `C:\Labfiles` folder

### Lab 07: Security
- On SEA-DC1:
  - Create IT OU: `New-ADOrganizationalUnit -Name 'IT'`
  - Create test users with non-expiring passwords
- On SEA-SVR2:
  - Create `C:\Labfiles\Lab01\DG_Readiness_Tool.ps1`
  - Download LAPS.x64.msi to `C:\Labfiles\Lab01\`
  - Install RSAT: `Install-WindowsFeature RSAT-AD-Tools, GPMC`

### Lab 08: Monitoring and Troubleshooting
- On SEA-SVR2:
  - Download `CPUSTRES64.EXE` from `https://live.sysinternals.com/CPUSTRES64.EXE` to `C:\Labfiles\Lab08\`
  - Install RSAT: `Install-WindowsFeature RSAT-AD-Tools`

---

## Checkpoints (Recommended)

Create Hyper-V checkpoints at these stages for easy rollback:

1. **Post-install**: After OS install and naming/IP config (before domain)
2. **Post-domain-join**: After all VMs are joined to contoso.com
3. **Per-lab baseline**: After lab-specific config, before running the lab

```powershell
# Create checkpoints for all VMs
$vms = @('SEA-DC1', 'SEA-ADM1', 'SEA-SVR1', 'SEA-SVR2', 'SEA-SVR3')
$vms | ForEach-Object { Checkpoint-VM -Name $_ -SnapshotName 'Post-Domain-Join' }
```

---

## Cleanup / Reset

To revert all VMs to a checkpoint:
```powershell
$vms | ForEach-Object { Restore-VMSnapshot -Name 'Post-Domain-Join' -VMName $_ -Confirm:$false }
```

To remove all VMs entirely:
```powershell
$vms | ForEach-Object {
    Stop-VM -Name $_ -Force -TurnOff
    Remove-VM -Name $_ -Force
    Remove-Item "C:\VMs\$_" -Recurse -Force
}
```
