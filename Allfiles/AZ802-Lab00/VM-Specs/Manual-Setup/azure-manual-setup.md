# Manual Azure Setup — AZ-802 Lab Environment

Step-by-step instructions to build the lab environment in Azure using the portal and CLI.

## Prerequisites

- Azure subscription with Contributor access
- Azure CLI installed or use Cloud Shell

---

## Step 1: Create Resource Group

**Portal**: Resource groups > Create > Name: `AZ802-Lab-RG`, Region: `East US`

**CLI**:
```bash
az group create --name AZ802-Lab-RG --location eastus
```

---

## Step 2: Create Virtual Network

**Portal**: Virtual networks > Create

| Setting | Value |
|---------|-------|
| Name | `AZ802-VNet` |
| Address space | `172.16.0.0/16` |
| Subnet name | `LabSubnet` |
| Subnet range | `172.16.10.0/24` |

**CLI**:
```bash
az network vnet create \
  --resource-group AZ802-Lab-RG \
  --name AZ802-VNet \
  --address-prefix 172.16.0.0/16 \
  --subnet-name LabSubnet \
  --subnet-prefix 172.16.10.0/24
```

---

## Step 3: Create Network Security Group

**Portal**: Network security groups > Create > Name: `AZ802-NSG`

Add inbound rules:
- **Allow-RDP**: Priority 1000, TCP, Port 3389, Source: Your IP
- **Allow-WAC**: Priority 1010, TCP, Port 443, Source: Your IP

Associate NSG with `LabSubnet`.

**CLI**:
```bash
az network nsg create --resource-group AZ802-Lab-RG --name AZ802-NSG

az network nsg rule create \
  --resource-group AZ802-Lab-RG --nsg-name AZ802-NSG \
  --name Allow-RDP --priority 1000 --direction Inbound \
  --access Allow --protocol Tcp --destination-port-range 3389

az network vnet subnet update \
  --resource-group AZ802-Lab-RG --vnet-name AZ802-VNet \
  --name LabSubnet --network-security-group AZ802-NSG
```

---

## Step 4: Create VMs

Create each VM with these common settings:
- **Size**: `Standard_D4s_v5` (required for nested virtualization)
- **OS**: Windows Server 2022 Datacenter (Gen 2)
- **VNet/Subnet**: AZ802-VNet / LabSubnet
- **Admin username**: `labadmin`
- **Security type**: Trusted launch
- **Public IP**: Standard SKU, Static

### VM 1: SEA-DC1

| Setting | Value |
|---------|-------|
| Name | `SEA-DC1` |
| Image | Windows Server 2022 Datacenter: Azure Edition — Gen2 |
| Private IP | `172.16.10.10` (static) |

**CLI**:
```bash
az vm create \
  --resource-group AZ802-Lab-RG --name SEA-DC1 \
  --image MicrosoftWindowsServer:WindowsServer:2022-datacenter-g2:latest \
  --size Standard_D4s_v5 \
  --admin-username labadmin --admin-password 'PA55w.rd1234' \
  --vnet-name AZ802-VNet --subnet LabSubnet \
  --private-ip-address 172.16.10.10 \
  --public-ip-sku Standard --security-type TrustedLaunch
```

### VM 2: SEA-ADM1

| Setting | Value |
|---------|-------|
| Name | `SEA-ADM1` |
| Image | Windows Server 2022 Datacenter: Azure Edition — Gen2 |
| Private IP | `172.16.10.11` (static) |

```bash
az vm create \
  --resource-group AZ802-Lab-RG --name SEA-ADM1 \
  --image MicrosoftWindowsServer:WindowsServer:2022-datacenter-g2:latest \
  --size Standard_D4s_v5 \
  --admin-username labadmin --admin-password 'PA55w.rd1234' \
  --vnet-name AZ802-VNet --subnet LabSubnet \
  --private-ip-address 172.16.10.11 \
  --public-ip-sku Standard --security-type TrustedLaunch
```

### VM 3: SEA-SVR1 (Server Core)

| Setting | Value |
|---------|-------|
| Name | `SEA-SVR1` |
| Image | Windows Server 2022 Datacenter **Core** — Gen2 |
| Private IP | `172.16.10.12` (static) |

```bash
az vm create \
  --resource-group AZ802-Lab-RG --name SEA-SVR1 \
  --image MicrosoftWindowsServer:WindowsServer:2022-datacenter-core-g2:latest \
  --size Standard_D4s_v5 \
  --admin-username labadmin --admin-password 'PA55w.rd1234' \
  --vnet-name AZ802-VNet --subnet LabSubnet \
  --private-ip-address 172.16.10.12 \
  --public-ip-sku Standard --security-type TrustedLaunch
```

### VM 4: SEA-SVR2

| Setting | Value |
|---------|-------|
| Name | `SEA-SVR2` |
| Image | Windows Server 2022 Datacenter: Azure Edition — Gen2 |
| Private IP | `172.16.10.13` (static) |

```bash
az vm create \
  --resource-group AZ802-Lab-RG --name SEA-SVR2 \
  --image MicrosoftWindowsServer:WindowsServer:2022-datacenter-g2:latest \
  --size Standard_D4s_v5 \
  --admin-username labadmin --admin-password 'PA55w.rd1234' \
  --vnet-name AZ802-VNet --subnet LabSubnet \
  --private-ip-address 172.16.10.13 \
  --public-ip-sku Standard --security-type TrustedLaunch
```

### VM 5: SEA-SVR3 (Server Core + 4 data disks)

| Setting | Value |
|---------|-------|
| Name | `SEA-SVR3` |
| Image | Windows Server 2022 Datacenter **Core** — Gen2 |
| Private IP | `172.16.10.14` (static) |
| Data disks | 4 × 128 GB Standard LRS |

```bash
az vm create \
  --resource-group AZ802-Lab-RG --name SEA-SVR3 \
  --image MicrosoftWindowsServer:WindowsServer:2022-datacenter-core-g2:latest \
  --size Standard_D4s_v5 \
  --admin-username labadmin --admin-password 'PA55w.rd1234' \
  --vnet-name AZ802-VNet --subnet LabSubnet \
  --private-ip-address 172.16.10.14 \
  --public-ip-sku Standard --security-type TrustedLaunch \
  --data-disk-sizes-gb 128 128 128 128
```

---

## Step 5: Promote SEA-DC1 to Domain Controller

RDP into SEA-DC1 and run in an elevated PowerShell:

```powershell
# Install AD DS
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools

# Promote to DC
$password = ConvertTo-SecureString 'PA55w.rd1234' -AsPlainText -Force
Install-ADDSForest `
    -DomainName 'contoso.com' `
    -DomainNetbiosName 'CONTOSO' `
    -SafeModeAdministratorPassword $password `
    -InstallDns:$true `
    -Force:$true
```

The VM will restart automatically. Wait 5-10 minutes.

---

## Step 6: Update VNet DNS

After SEA-DC1 restarts and AD DS is operational, update the VNet DNS so other VMs can find the domain.

**Portal**: Virtual networks > AZ802-VNet > DNS servers > Custom: `172.16.10.10` > Save

**CLI**:
```bash
az network vnet update \
  --resource-group AZ802-Lab-RG --name AZ802-VNet \
  --dns-servers 172.16.10.10
```

After updating DNS, **restart all member VMs** to pick up the DNS change:
```bash
az vm restart --resource-group AZ802-Lab-RG --name SEA-ADM1
az vm restart --resource-group AZ802-Lab-RG --name SEA-SVR1
az vm restart --resource-group AZ802-Lab-RG --name SEA-SVR2
az vm restart --resource-group AZ802-Lab-RG --name SEA-SVR3
```

---

## Step 7: Domain-Join Member Servers

RDP into each member server and run:

```powershell
$cred = Get-Credential -Message "Enter CONTOSO\Administrator credentials"
Add-Computer -DomainName 'contoso.com' -Credential $cred -Restart -Force
```

For Server Core VMs (SEA-SVR1, SEA-SVR3), you can run this from SEA-ADM1 via Invoke-Command:

```powershell
$cred = Get-Credential 'CONTOSO\Administrator'
Invoke-Command -ComputerName 172.16.10.12 -ScriptBlock {
    param($c) Add-Computer -DomainName 'contoso.com' -Credential $c -Restart -Force
} -ArgumentList $cred -Credential (Get-Credential 'labadmin')
```

---

## Step 8: Lab-Specific Setup

Refer to the per-lab config scripts in `Deploy/scripts/Configure-Lab<##>.ps1` for:
- Role installations
- File/folder creation
- AD object creation
- Tool downloads

---

## Step 9: Verify

RDP into SEA-ADM1 and verify:

```powershell
# All VMs should be pingable by name
Test-NetConnection SEA-DC1 -Port 5985
Test-NetConnection SEA-SVR1 -Port 5985
Test-NetConnection SEA-SVR2 -Port 5985
Test-NetConnection SEA-SVR3 -Port 5985

# Domain should be reachable
Get-ADDomain
```

---

## Cleanup

```bash
az group delete --name AZ802-Lab-RG --yes --no-wait
```
