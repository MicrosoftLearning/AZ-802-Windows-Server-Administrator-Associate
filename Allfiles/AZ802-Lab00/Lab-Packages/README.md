# AZ-802 Lab Packages — Checkpoint-Based Lab Setup

## How It Works

1. **One-time setup**: Run `Create-Baseline.ps1` to configure the domain environment and create a "Baseline" Hyper-V checkpoint on all VMs.
2. **Per lab**: Run `Setup-Lab##.ps1` — it restores all VMs to the Baseline checkpoint, starts only the VMs you need, and applies lab-specific configuration.

Every lab starts from a known-good state. No conflicts, no leftover config from previous labs.

## Prerequisites

- Local Hyper-V host (Windows 10/11 Pro or Windows Server with Hyper-V)
- 5 VMs already created and named: `SEA-DC1`, `SEA-ADM1`, `SEA-SVR1`, `SEA-SVR2`, `SEA-SVR3`
- Windows Server 2022 installed on all VMs
- See [Manual-Setup/local-hyperv-setup.md](../VM-Specs/Manual-Setup/local-hyperv-setup.md) for VM creation steps
- Run all scripts from an **elevated PowerShell** on the Hyper-V host

## Quick Start

```powershell
# Step 1: One-time baseline setup (~20 min)
.\Create-Baseline.ps1

# Step 2: Set up for any lab
.\Setup-Lab01.ps1    # Restores baseline, configures for Lab 01
.\Setup-Lab03.ps1    # Downloads the Lab 03 parent VHD automatically
.\Setup-Lab06.ps1    # etc — any order, any time
```

After running a lab setup script, connect to the primary VM identified by the script and sign in with:

- **Username**: `CONTOSO\Administrator`
- **Password**: `PA55w.rd1234`

## What Each Script Does

| Script | Restores Baseline | Starts VMs | Configures |
|--------|:-:|---|---|
| `Create-Baseline.ps1` | — | All 5 | DC promo, domain join, common tools, creates checkpoint |
| `Setup-Lab01.ps1` | Yes | DC1, ADM1, SVR1 | RSAT on ADM1, WinRM on SVR1 |
| `Setup-Lab02.ps1` | Yes | DC1, ADM1 | WinRM, Edge check |
| `Setup-Lab03.ps1` | Yes | DC1, ADM1, SVR1 | Hyper-V on SVR1, Windows Server 2022 Evaluation BaseImage.vhd, RSAT Hyper-V |
| `Setup-Lab04.ps1` | Yes | DC1, ADM1, SVR1 | DHCP on DC1 w/ Contoso scope, RSAT DHCP/DNS |
| `Setup-Lab05.ps1` | Yes | DC1, ADM1, SVR1, SVR2 | DFS scripts, S: drives, File1.txt |
| `Setup-Lab06.ps1` | Yes | DC1, ADM1, SVR3 | Disks offline/raw, CreateLabFiles.cmd, labfiles share |
| `Setup-Lab07.ps1` | Yes | DC1, SVR1, SVR2 | IT OU, test users, LAPS MSI, Credential Guard tool |
| `Setup-Lab08.ps1` | Yes | DC1, SVR2 | CPUSTRES64.EXE download, WinRM/event log rules |

## Notes

- **PowerShell Direct**: Scripts use `Invoke-Command -VMName` to configure VMs from the host — no network dependency.
- **Credentials**: The standard password is `PA55w.rd1234`. The default username is `CONTOSO\Administrator` (or local `Administrator` for baseline creation).
- **Lab 03 parent image**: The setup downloads the Windows Server 2022 Datacenter Evaluation VHD directly to SEA-SVR1. To reuse a copy downloaded ahead of time, run `Setup-Lab03.ps1 -BaseImageVhdPath '<VHD-path>'`.
- **Lab 05 requires Azure**: The setup script handles on-prem prerequisites only. You still need an Azure subscription for the Azure File Sync exercises.
- **Lab 06 disk resets**: The lab itself says to revert VMs between exercises. You can re-run `Setup-Lab06.ps1` to reset between exercises.
- **Estimated time**: Baseline creation ~20 min. Most lab setups take ~3-5 min. Lab 03 takes additional time if it downloads the approximately 9.5-GiB parent image.
