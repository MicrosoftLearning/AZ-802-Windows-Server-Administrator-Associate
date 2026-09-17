# Lab 05: Implementing Azure File Sync — VM Specs

## VMs Required

### SEA-ADM1 (Management workstation)

- **OS**: Windows Server 2022 (Desktop Experience)
- **Domain**: Joined to contoso.com
- **Role**: Management workstation — runs DFS Management, PowerShell ISE, Edge for Azure portal
- **Pre-installed software**:
  - PowerShell
  - PowerShell ISE
  - Microsoft Edge
  - File Explorer
- **Network**: Internet access required (Azure portal, Azure File Sync agent download)

### SEA-SVR1 (DFS/File Sync server)

- **OS**: Windows Server 2022 (Server Core or Desktop Experience)
- **Domain**: Joined to contoso.com
- **Role**: DFS namespace/replication member, File Sync server endpoint
- **Pre-installed**: None — DFS and File Sync agent installed during lab
- **Pre-staged files**:
  - DFS Replication folder: `S:\Data` (S: drive must exist)
- **Network**: Reachable from SEA-ADM1

### SEA-SVR2 (DFS/File Sync server)

- **OS**: Windows Server 2022 (Desktop Experience)
- **Domain**: Joined to contoso.com
- **Role**: DFS namespace/replication member, File Sync server endpoint
- **Pre-installed**: None — DFS and File Sync agent installed during lab
- **Pre-staged files**:
  - DFS Replication folder: `S:\Data` (S: drive must exist)
- **Network**: Reachable from SEA-ADM1

## Domain Requirements

- **Forest/Domain**: contoso.com
- **DFS Namespace**: `\\contoso.com\Root` (created by `DeployDFS.ps1`)

## Pre-staged Files

| VM | Path | Description |
|----|------|-------------|
| SEA-ADM1 | `C:\Labfiles\Lab05\DeployDFS.ps1` | Script to deploy DFS Namespace and Replication |
| SEA-ADM1 | `C:\Labfiles\Lab05\Install-FileSyncServerCore.ps1` | Script to install Azure File Sync agent on Server Core |
| SEA-ADM1 | `C:\Labfiles\Lab05\File1.txt` | Sample file for Azure file share upload |

> **Note**: The `DeployDFS.ps1` script creates the DFS namespace, referrals, and replication group. The `S:\Data` folders on SEA-SVR1 and SEA-SVR2 are created by this script or must pre-exist.

## Azure Requirements

- **Azure subscription**: Required (Owner role for the user account)
- **Resources created during lab**:
  - Resource group: `AZ802-L0501-RG`
  - Storage account (LRS, any region)
  - Azure file share: `share1`
  - Storage Sync Service: `FileSync1`
  - Sync group: `Sync1`
- **Resources cleaned up at end of lab**: All of the above

## Internet Access Required

- SEA-ADM1: Azure portal, Azure File Sync agent download page
- SEA-SVR1: Device login for Azure File Sync registration
- SEA-SVR2: Device login for Azure File Sync registration
