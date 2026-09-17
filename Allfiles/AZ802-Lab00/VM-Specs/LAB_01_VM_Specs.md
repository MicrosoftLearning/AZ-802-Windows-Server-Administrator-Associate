# Lab 01: Implementing identity services and Group Policy — VM Specs

## VMs Required

### SEA-ADM1 (Management workstation)

- **OS**: Windows Server 2022 (Desktop Experience)
- **Domain**: Joined to contoso.com
- **Role**: Primary management workstation for all tasks
- **Pre-installed software**:
  - RSAT (Remote Server Administration Tools) including AD DS tools
  - Server Manager
  - PowerShell with AD module
  - Group Policy Management Console (GPMC)
- **Network**: 172.16.x.x subnet, DNS pointing to SEA-DC1

### SEA-SVR1 (Target server)

- **OS**: Windows Server 2022 Server Core
- **Domain**: Joined to contoso.com
- **Role**: Target for remote AD DS role install and DC promotion
- **Pre-installed**: None — lab installs AD DS remotely
- **Network**: Reachable from SEA-ADM1 via PowerShell Remoting

### SEA-DC1 (Domain controller)

- **OS**: Windows Server 2022 (Desktop Experience or Core)
- **Domain**: contoso.com domain controller (primary DC)
- **Roles pre-installed**:
  - AD DS (forest root DC for contoso.com)
  - DNS Server
- **Pre-configured AD objects**:
  - contoso.com forest and domain
  - Default-First-Site-Name AD site
- **Network**: 172.16.10.10

## Domain Requirements

- **Forest/Domain**: contoso.com
- **Forest functional level**: Must support standard AD DS operations
- **DNS**: Integrated AD DNS zone for contoso.com

## No Pre-staged Files Required
