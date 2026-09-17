# Lab 07: Configuring security in Windows Server — VM Specs

## VMs Required

### SEA-SVR2 (Primary workstation for this lab)

- **OS**: Windows Server 2022 (Desktop Experience)
- **Domain**: Joined to contoso.com
- **Role**: Primary machine — runs GPO creation, security tools, LAPS install, AD management
- **Pre-installed software**:
  - PowerShell
  - Group Policy Management Console (GPMC)
  - Active Directory Users and Computers
  - AD PowerShell module (`Get-ADUser`, `Set-ADUser`, `New-ADOrganizationalUnit`, etc.)
- **Pre-staged files**:
  - `C:\Labfiles\Lab01\DG_Readiness_Tool.ps1` — HVCI/Credential Guard readiness tool
  - `C:\Labfiles\Lab01\LAPS.x64.msi` — LAPS installer
- **Network**: Reachable from SEA-SVR1, able to share `C$` (for LAPS remote install)

### SEA-SVR1 (LAPS target server)

- **OS**: Windows Server 2022 Server Core
- **Domain**: Joined to contoso.com
- **Role**: Target for LAPS deployment — receives LAPS client-side extension remotely
- **Pre-installed**: None
- **Network**: Reachable from SEA-SVR2 (SMB for `\\SEA-SVR2.contoso.com\c$\Labfiles\Lab01\LAPS.x64.msi`)

### SEA-DC1 (Domain controller)

- **OS**: Windows Server 2022 (Desktop Experience or Core)
- **Domain**: contoso.com domain controller
- **Roles pre-installed**:
  - AD DS
  - DNS Server
- **Pre-configured AD objects**:
  - `IT` OU (Credential Guard GPO linked here)
  - User accounts with `PasswordNeverExpires` set to `$true` (for Exercise 2)

## Domain Requirements

- **Forest/Domain**: contoso.com
- **OUs needed**:
  - `IT` OU — must exist before lab starts (Credential Guard GPO linked here)
  - `Seattle_Servers` OU — created during lab by PowerShell
- **User accounts**: Multiple enabled accounts with `PasswordNeverExpires = $true` for discovery exercise
- **AD Schema**: Must support LAPS schema extension (`Update-AdmPwdADSchema`)

## Pre-staged Files

| VM | Path | Description |
|----|------|-------------|
| SEA-SVR2 | `C:\Labfiles\Lab01\DG_Readiness_Tool.ps1` | HVCI/Credential Guard hardware readiness tool |
| SEA-SVR2 | `C:\Labfiles\Lab01\LAPS.x64.msi` | Local Administrator Password Solution installer |

## No Internet Access Required

## No Azure Requirements
