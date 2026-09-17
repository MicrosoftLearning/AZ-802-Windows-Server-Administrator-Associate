# Lab 04: Implementing and configuring network infrastructure services in Windows Server — VM Specs

## VMs Required

### SEA-ADM1 (Management workstation)

- **OS**: Windows Server 2022 (Desktop Experience)
- **Domain**: Joined to contoso.com
- **Role**: Management workstation — installs WAC, runs DHCP/DNS admin tools
- **Pre-installed software**:
  - Server Manager
  - PowerShell
  - Microsoft Edge
  - BITS
  - DHCP Management Console (RSAT)
  - DNS Manager (RSAT)
- **Network**: 172.16.10.11/16 static IP, DNS pointing to SEA-DC1 (172.16.10.10), internet access required (WAC download)

### SEA-SVR1 (DHCP/DNS target server)

- **OS**: Windows Server 2022 (Desktop Experience or Core)
- **Domain**: Joined to contoso.com
- **Role**: Target for DHCP and DNS role install
- **Pre-installed**: None — lab installs DHCP and DNS remotely via WAC
- **Network**: 172.16.10.12, reachable from SEA-ADM1

### SEA-DC1 (Domain controller)

- **OS**: Windows Server 2022 (Desktop Experience or Core)
- **Domain**: contoso.com domain controller
- **Roles pre-installed**:
  - AD DS
  - DNS Server
  - DHCP Server (pre-authorized, with existing scope `172.16.0.0 Contoso`)
- **Network**: 172.16.10.10

## Domain Requirements

- **Forest/Domain**: contoso.com
- **DHCP**: SEA-DC1 must be pre-authorized in AD as a DHCP server with an existing scope named "Contoso" (172.16.0.0)

## Network Requirements

- Subnet: 172.16.0.0/16
- Lab creates scope 10.100.150.0/24 on SEA-SVR1
- DHCP failover configured between SEA-SVR1 and SEA-DC1
- SEA-ADM1 IP temporarily changed during lab (DHCP, then 172.16.11.11)

### Azure nested network

The Lab 0 Azure deployment creates one Hyper-V host and runs SEA-DC1, SEA-ADM1, and SEA-SVR1 as nested VMs on an internal `LabSwitch`. The switch uses `172.16.0.0/16`, and the host provides the `172.16.10.1` gateway through NAT. This private Layer-2 network supports the DHCP broadcasts and temporary SEA-ADM1 IP changes required by the original Lab 4 instructions.

## Internet Access Required

- SEA-ADM1: Downloads WAC

## No Pre-staged Files Required
