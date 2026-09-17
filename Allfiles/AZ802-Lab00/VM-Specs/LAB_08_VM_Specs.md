# Lab 08: Monitoring and troubleshooting Windows Server — VM Specs

## VMs Required

### SEA-SVR2 (Primary workstation for this lab)

- **OS**: Windows Server 2022 (Desktop Experience)
- **Domain**: Joined to contoso.com
- **Role**: Primary machine — runs Performance Monitor, Event Viewer, PowerShell, CPU stress tool
- **Pre-installed software**:
  - Performance Monitor
  - Event Viewer
  - PowerShell
  - Active Directory Users and Computers
  - File Explorer
- **Pre-staged files**:
  - `C:\Labfiles\Lab08\CPUSTRES64.EXE` — SysInternals CPU stress utility
- **Network**: Reachable from SEA-DC1 (file copy, WinRM, event forwarding)

### SEA-DC1 (Domain controller / event source)

- **OS**: Windows Server 2022 Server Core
- **Domain**: contoso.com domain controller
- **Roles pre-installed**:
  - AD DS
  - DNS Server
- **Role during lab**: Event forwarding source, file copy target for performance workload
- **Pre-configured**:
  - WinRM enabled
  - Accessible via `\\SEA-DC1.contoso.com\c$`
- **Network**: Reachable from SEA-SVR2

## Domain Requirements

- **Forest/Domain**: contoso.com
- **AD objects**: `Builtin\Event Log Readers` group (lab adds SEA-SVR2 computer account to it)

## Pre-staged Files

| VM | Path | Description |
|----|------|-------------|
| SEA-SVR2 | `C:\Labfiles\Lab08\CPUSTRES64.EXE` | SysInternals CPU Stress utility for simulating CPU load |

## No Internet Access Required

## No Azure Requirements
