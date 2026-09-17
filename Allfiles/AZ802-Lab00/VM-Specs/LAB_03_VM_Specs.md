# Lab 03: Implementing and configuring virtualization in Windows Server — VM Specs

## VMs Required

### SEA-ADM1 (Management workstation)

- **OS**: Windows Server 2022 (Desktop Experience)
- **Domain**: Joined to contoso.com
- **Role**: Management workstation — uses Hyper-V Manager remotely, installs WAC
- **Pre-installed software**:
  - Hyper-V Manager (RSAT Hyper-V tools)
  - Server Manager
  - PowerShell
  - Microsoft Edge
  - BITS
- **Network**: Internet access required (downloads WAC, Docker CE, container images)

### SEA-SVR1 (Hyper-V host)

- **OS**: Windows Server 2022 (Desktop Experience or Core)
- **Domain**: Joined to contoso.com
- **Roles pre-installed**:
  - Hyper-V
- **Pre-staged files**:
  - `C:\Base\BaseImage.vhd` — a bootable 40-GB dynamic VHD containing Windows Server 2022 Datacenter Core, used as a parent for differencing disks
- **Network**: Reachable from SEA-ADM1, internet access required (Docker CE install, container image pull)
- **Nested virtualization**: Must be enabled if SEA-SVR1 is itself a VM

## Domain Requirements

- **Forest/Domain**: contoso.com

## Internet Access Required

- SEA-ADM1: Downloads WAC
- SEA-SVR1: Downloads Docker CE from GitHub, pulls Nano Server container image from `mcr.microsoft.com`

## Pre-staged Files

| VM | Path | Description |
|----|------|-------------|
| SEA-SVR1 | `C:\Base\BaseImage.vhd` | Bootable Windows Server 2022 Datacenter Core parent VHD for differencing disks |
