# Lab 02: Managing Windows Server — VM Specs

## VMs Required

### SEA-ADM1 (Management workstation)

- **OS**: Windows Server 2022 (Desktop Experience)
- **Domain**: Joined to contoso.com
- **Role**: Management workstation — installs WAC, runs PS Remoting
- **Pre-installed software**:
  - PowerShell
  - Microsoft Edge
  - BITS (Background Intelligent Transfer Service)
- **Network**: Internet access required (downloads WAC from aka.ms/WACdownload)

### SEA-DC1 (Domain controller)

- **OS**: Windows Server 2022 (Desktop Experience or Core)
- **Domain**: contoso.com domain controller
- **Roles pre-installed**:
  - AD DS
  - DNS Server
- **Network**: Reachable from SEA-ADM1 (used as WAC target, PS Remoting target)

## Domain Requirements

- **Forest/Domain**: contoso.com

## Internet Access Required

- SEA-ADM1 must be able to download Windows Admin Center from `https://aka.ms/WACdownload`

## No Pre-staged Files Required
