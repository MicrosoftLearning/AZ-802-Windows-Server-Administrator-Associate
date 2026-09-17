# AZ-802 Lab Environment — Deployment Guide

## Overview

These scripts deploy the AZ-802 lab environment to Azure or guide manual setup locally. The environment consists of a contoso.com Active Directory domain with up to 5 Windows Server 2022 VMs.

## VM Inventory

| VM Name | Private IP | OS | Role |
|---------|-----------|-----|------|
| SEA-DC1 | 172.16.10.10 | WS 2022 Desktop | Domain controller |
| SEA-ADM1 | 172.16.10.11 | WS 2022 Desktop | Management workstation |
| SEA-SVR1 | 172.16.10.12 | WS 2022 Core | Member server |
| SEA-SVR2 | 172.16.10.13 | WS 2022 Desktop | Member server |
| SEA-SVR3 | 172.16.10.14 | WS 2022 Core | Storage server (4 extra disks) |

## Automated Deployment (Azure)

### Prerequisites

- Azure subscription with Contributor access
- Azure PowerShell module (`Az`) installed — `Install-Module Az`
- Authenticated to Azure — `Connect-AzAccount`

### Quick Start

```powershell
# Deploy all VMs and configure for a specific lab
.\Deploy\deploy-lab-environment.ps1 -LabNumber 1 -ResourceGroupName "AZ802-Lab" -Location "eastus"
```

### Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `-LabNumber` | Yes | — | Lab to configure (1–8) |
| `-ResourceGroupName` | No | `AZ802-Lab-RG` | Azure resource group name |
| `-Location` | No | `eastus` | Azure region |
| `-AdminUsername` | No | `labadmin` | Local username used to provision the Azure VMs |
| `-AdminPassword` | No | `PA55w.rd1234` | Optional VM admin password override (SecureString) |
| `-VmSize` | No | `Standard_D4s_v5` | VM size for Labs 1 through 3 and 5 through 8 |
| `-Lab04HostVmSize` | No | `Standard_D8s_v5` | Nested Hyper-V host size for Lab 4 |
| `-AllowedRdpSourceIP` | No | `*` | Source address or CIDR permitted to connect over RDP |
| `-Lab04VhdUri` | No | Microsoft Evaluation Center VHD | HTTPS URI for the Lab 4 parent VHD |
| `-SkipDomainConfig` | No | `$false` | Skip AD DS/domain setup if already done |

### What the Script Does

1. Creates a resource group
2. Deploys the ARM template (`azuredeploy.json`) to create the VNet, NSG, and VMs
3. Configures SEA-DC1 as the contoso.com domain controller
4. Updates VNet DNS to point to SEA-DC1
5. Domain-joins all member servers
6. Runs lab-specific configuration (roles, files, AD objects)

For Lab 3, SEA-SVR1 uses Standard security because Azure nested virtualization doesn't support Trusted Launch. After Hyper-V restarts, the deployment downloads the Windows Server 2022 Datacenter Evaluation VHD from the Microsoft Evaluation Center to `C:\Base\BaseImage.vhd` and validates it before reporting success.

For Lab 4, the entry point delegates to `deploy-lab04-nested-environment.ps1`. The dedicated template creates one `Standard_D8s_v5` Hyper-V host and a 512-GB data disk. The host builder downloads and validates the Windows Server 2022 Desktop Experience evaluation VHD, creates three differencing-disk guests, and places them on an internal `172.16.0.0/16` switch with NAT.

The deployment uses `labadmin` as the temporary local Azure VM administrator because Azure doesn't permit `Administrator` as the provisioning username. After domain configuration completes, connect to the primary VM with `CONTOSO\Administrator` and the password `PA55w.rd1234`.

If you supply an override, the password must contain 8–123 characters and meet at least three of these requirements: a lowercase letter, an uppercase letter, a number, and a special character. Common weak passwords such as `Password1` are rejected by Azure.

### Estimated Deployment Time

~30–45 minutes (ARM deployment + DC promotion + domain join + lab config). Labs 3 and 4 take additional time to download approximately 9.5 GiB from the Microsoft Evaluation Center. Allow 60–90 minutes for the first Lab 4 deployment.

### Estimated Cost

~$2–4/hour for all 5 direct Azure VMs running. The nested Lab 4 host is approximately $0.85–$0.90/hour in East US at retail rates. Deallocate VMs when not in use.

## Manual Setup

See the [Manual-Setup/](../Manual-Setup/) folder for step-by-step guides:

- **[azure-manual-setup.md](../Manual-Setup/azure-manual-setup.md)** — Azure portal and CLI steps
- **[local-hyperv-setup.md](../Manual-Setup/local-hyperv-setup.md)** — Local Hyper-V host steps

## Lab-Specific Requirements

| Lab | VMs Needed | Azure? | Internet? | Extra Requirements |
|-----|-----------|--------|-----------|-------------------|
| 01 | DC1, ADM1, SVR1 | No | No | RSAT on ADM1 |
| 02 | DC1, ADM1 | No | Yes | WAC download |
| 03 | DC1, ADM1, SVR1 | No | Yes | Hyper-V, BaseImage.vhd, Docker CE |
| 04 | DC1, ADM1, SVR1 | No | Yes | WAC, pre-existing DHCP scope on DC1 |
| 05 | ADM1, SVR1, SVR2 | **Yes** | Yes | Azure sub, DFS scripts, S: drives |
| 06 | DC1, ADM1, SVR3 | No | Yes | 4 extra disks on SVR3, WAC |
| 07 | DC1, SVR1, SVR2 | No | No | LAPS MSI, Credential Guard tool, IT OU |
| 08 | DC1, SVR2 | No | No | CPUSTRES64.EXE |

## Security Notes

- The ARM template creates public IPs with RDP access restricted to your current IP by default
- Change the admin password after deployment
- Delete the resource group when done to avoid charges
- Do not use these scripts for production environments
