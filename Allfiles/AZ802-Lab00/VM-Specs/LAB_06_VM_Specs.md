# Lab 06: Implementing storage solutions in Windows Server — VM Specs

## VMs Required

### SEA-ADM1 (Management workstation)

- **OS**: Windows Server 2022 (Desktop Experience)
- **Domain**: Joined to contoso.com
- **Role**: Management workstation — Server Manager, WAC, PowerShell, File Explorer
- **Pre-installed software**:
  - Server Manager
  - PowerShell
  - Microsoft Edge
  - BITS
  - File Explorer
- **Pre-staged files**:
  - `C:\Labfiles\` directory shared with Users group (or lab shares during exercise)
  - `C:\Labfiles\Lab06\CreateLabFiles.cmd` — script to create sample dedup files
- **Network**: Internet access required (WAC download)

### SEA-SVR3 (Storage server)

- **OS**: Windows Server 2022 Server Core
- **Domain**: Joined to contoso.com
- **Role**: Target for Data Dedup, iSCSI target, Storage Spaces
- **Pre-installed**: None — roles installed during lab
- **Disk requirements**:
  - **Disk 0**: OS disk
  - **Disk 1**: ~127 GB (used for ReFS volume M: for dedup, then Storage Spaces)
  - **Disk 2**: ~127 GB (used for iSCSI target volume, then Storage Spaces)
  - **Disk 3**: ~127 GB (used for iSCSI target volume, then Storage Spaces)
  - **Disk 4**: ~127 GB (used as hot spare in Storage Spaces)
- **Network**: Reachable from SEA-ADM1 and SEA-DC1

### SEA-DC1 (Domain controller / iSCSI initiator)

- **OS**: Windows Server 2022 Server Core
- **Domain**: contoso.com domain controller
- **Roles pre-installed**:
  - AD DS
  - DNS Server
- **Role during lab**: iSCSI initiator — connects to iSCSI targets hosted on SEA-SVR3
- **Disk**: Only OS disk initially; iSCSI disks appear after connecting to targets

## Domain Requirements

- **Forest/Domain**: contoso.com

## Pre-staged Files

| VM | Path | Description |
|----|------|-------------|
| SEA-ADM1 | `C:\Labfiles\Lab06\CreateLabFiles.cmd` | Generates sample files for Data Dedup testing |

## Disk Configuration (Critical)

SEA-SVR3 must have **5 disks total** (1 OS + 4 data):

| Disk # | Size | Initial State | Used In |
|--------|------|---------------|---------|
| 0 | OS disk | Online | OS |
| 1 | ~127 GB | Offline/Raw | Ex 1 (Dedup), Ex 3 (Storage Spaces) |
| 2 | ~127 GB | Offline/Raw | Ex 2 (iSCSI), Ex 3 (Storage Spaces) |
| 3 | ~127 GB | Offline/Raw | Ex 2 (iSCSI), Ex 3 (Storage Spaces) |
| 4 | ~127 GB | Offline/Raw | Ex 3 (Storage Spaces — hot spare) |

> **Note**: Disks are reset between exercises using `Clear-Disk` and `Set-Disk -IsOffline $true`. The lab note says "be sure to revert the VMs between each exercise" — disks must return to raw/offline state between exercises.

## Internet Access Required

- SEA-ADM1: Downloads WAC

## No Azure Requirements
