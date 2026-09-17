---
lab:
  title: 'Lab 0: Set up the Windows Server lab environment'
  description: 'In this lab, you create the reusable AZ-802 baseline environment and prepare it for the lab you want to complete by using either Azure or local Hyper-V.'
  duration: 45 minutes
  level: 200
  islab: true
  status: 'live'
  targetDate: 2026-09-08
  primarytopics:
    - Windows Server
    - Azure Virtual Machines
    - Hyper-V
    - PowerShell
---

# Lab 0: Set up the Windows Server lab environment

Use this lab to create and prepare a self-hosted environment for AZ-802 Labs 1 through 8. Complete Lab 0 before starting another lab.

The setup has two layers:

- The **baseline** creates five Windows Server virtual machines (VMs), the `contoso.com` domain, domain membership, networking, and shared management prerequisites.
- The **lab-specific setup** starts from the baseline and applies only the prerequisites for the lab you select.

Choose one hosting option:

- **Azure**: The deployment script creates the baseline and applies the selected lab configuration in one operation. Lab 4 uses one Azure Hyper-V host with three nested VMs so that its DHCP exercises run on a private Layer-2 network. Other labs use separate Azure VMs. To obtain a clean environment for another lab, delete the resource group and redeploy it.
- **Local Hyper-V**: Create the baseline once. Each lab setup script restores the `Baseline` checkpoint before applying the selected lab configuration.

> **Important**: These scripts create a disposable training environment. Do not use them in a production environment.

## Exercise 1: Get the lab files

1. On the computer that you use to manage the lab environment, open Windows PowerShell.
1. Clone the AZ-802 lab repository:

   ```powershell
   git clone https://github.com/MicrosoftLearning/AZ-802-Windows-Server-Administrator-Associate.git
   ```

1. Change to the repository folder:

   ```powershell
   Set-Location .\AZ-802-Windows-Server-Administrator-Associate
   ```

The environment files are in the `Allfiles\AZ802-Lab00` folder.

## Exercise 2: Review the baseline

The baseline contains the following VMs:

| VM | Private IP address | Operating system | Baseline role |
|---|---|---|---|
| SEA-DC1 | 172.16.10.10 | Windows Server 2022 with Desktop Experience | Domain controller and DNS server |
| SEA-ADM1 | 172.16.10.11 | Windows Server 2022 with Desktop Experience | Management server |
| SEA-SVR1 | 172.16.10.12 | Windows Server 2022 Server Core | Member server |
| SEA-SVR2 | 172.16.10.13 | Windows Server 2022 with Desktop Experience | Member server |
| SEA-SVR3 | 172.16.10.14 | Windows Server 2022 Server Core | Storage server with four data disks |

Lab 5 also requires one 128-GB data disk on SEA-SVR1 and SEA-SVR2. The Azure deployment adds these disks when you select Lab 5. Include them in the local Hyper-V baseline and leave them uninitialized.

The automated setup creates the `contoso.com` domain and configures `CONTOSO\Administrator` as the lab administrator. When the lab instructions ask for credentials provided by the lab environment, use:

- **Username**: `CONTOSO\Administrator`
- **Password**: `PA55w.rd1234`

## Exercise 3: Create an Azure environment

Complete this exercise if you host the lab in an Azure subscription. Otherwise, continue to Exercise 4.

### Task 1: Review the Azure prerequisites

You need:

- An Azure subscription in which you have permission to create resource groups, networks, VMs, disks, and public IP addresses.
- Sufficient quota for five `Standard_D4s_v5` VMs in one Azure region. Lab 4 instead requires one `Standard_D8s_v5` VM that supports nested virtualization.
- Windows PowerShell 5.1 or later.
- The Azure PowerShell `Az` module.
- For Lab 3, a Windows Server 2022 installation ISO available through an HTTPS URL, such as a time-limited Azure Storage SAS URI. Obtain evaluation media from the [Microsoft Evaluation Center](https://www.microsoft.com/evalcenter/evaluate-windows-server-2022), if needed.

The five-VM environment costs approximately USD 2 to 4 per hour while all VMs are running. The nested Lab 4 environment costs approximately USD 0.85 to 0.90 per hour. Pricing varies by subscription and region.

### Task 2: Install Azure PowerShell and sign in

1. Open Windows PowerShell as an administrator.
1. If the `Az` module isn't installed, install it for your Windows account:

   ```powershell
   Install-Module Az -Scope CurrentUser
   ```

1. Sign in to Azure:

   ```powershell
   Connect-AzAccount
   ```

1. If you have access to multiple subscriptions, select the subscription to use:

   ```powershell
   Get-AzSubscription
   Set-AzContext -Subscription '<subscription name or ID>'
   ```

### Task 3: Deploy the baseline and prepare a lab

1. Change to the Azure deployment folder:

   ```powershell
   Set-Location .\Allfiles\AZ802-Lab00\VM-Specs\Deploy
   ```

1. Deploy the baseline and prepare it for the lab that you want to complete. Replace `<lab-number>` with a number from 1 through 8.

   ```powershell
   .\deploy-lab-environment.ps1 `
       -LabNumber <lab-number> `
       -Location 'eastus'
   ```

   The script automatically names the resource group `AZ802-L<NN>-ENV`, where `<NN>` is the two-digit lab number (for example, `AZ802-L05-ENV` for Lab 5). To use a different name or Azure region, pass `-ResourceGroupName` or `-Location`.

   Deployment typically takes 30 through 45 minutes. The script creates all five VMs, promotes SEA-DC1, joins the member servers to the domain, verifies domain membership, and applies the selected lab configuration.

   Lab 3 preparation downloads the Windows Server 2022 Datacenter Evaluation VHD from the [Microsoft Evaluation Center](https://www.microsoft.com/evalcenter/evaluate-windows-server-2022). Allow additional time to download approximately 9.5 GiB.

   Lab 4 uses a separate nested deployment automatically. It creates one Azure Hyper-V host, downloads the Windows Server 2022 Evaluation VHD, creates SEA-DC1, SEA-ADM1, and SEA-SVR1 as nested VMs, and configures their private network. Allow approximately 60 through 90 minutes for the first deployment.

### Task 4: Verify the Azure environment

1. List the public IP addresses. Replace `AZ802-L05-ENV` with the resource group name for the lab you deployed:

   ```powershell
   Get-AzPublicIpAddress -ResourceGroupName 'AZ802-L05-ENV' |
       Select-Object Name, IpAddress
   ```

1. For Labs 1 through 3 and 5 through 8, connect by Remote Desktop to the primary VM for your selected lab. Use:

   - **Username**: `CONTOSO\Administrator`
   - **Password**: `PA55w.rd1234`

1. For Lab 4, connect by Remote Desktop to `AZ802-L4-HOST` by using the public IP address, the local username `labadmin`, and the lab password. From the host, open Remote Desktop Connection and connect to `172.16.10.11` by using `CONTOSO\Administrator` and the lab password.
1. On SEA-ADM1, open Windows PowerShell as an administrator and verify the domain and baseline connectivity:

   ```powershell
   Get-ADDomain
   Test-NetConnection SEA-DC1 -Port 5985
   Test-NetConnection SEA-SVR1 -Port 5985
   ```

### Task 5: Reset or remove the Azure environment

Azure doesn't provide the checkpoint workflow used by the local Hyper-V scripts. To start another lab from a clean baseline, delete the resource group and repeat Task 3 with the new lab number.

> **Warning**: The following command permanently deletes the resource group and everything in it. Verify the resource group name before running it.

```powershell
Remove-AzResourceGroup -Name 'AZ802-L05-ENV' -Force
```

When you finish working for the day but want to retain the environment, deallocate the VMs to reduce compute charges:

```powershell
Get-AzVM -ResourceGroupName 'AZ802-L05-ENV' |
    ForEach-Object { Stop-AzVM -ResourceGroupName $_.ResourceGroupName -Name $_.Name -Force }
```

Managed disks and other resources continue to incur charges while the VMs are deallocated.

## Exercise 4: Create a local Hyper-V environment

Complete this exercise if you host the lab on a local Hyper-V server. Otherwise, continue to Exercise 5.

### Task 1: Review the Hyper-V prerequisites

You need:

- Windows 10 or Windows 11 Pro, or Windows Server 2019 or later, with Hyper-V enabled.
- At least 32 GB of RAM, eight processor cores, and 200 GB of free disk space. The recommended capacity is 64 GB of RAM, 12 processor cores, and 400 GB of SSD storage.
- A Windows Server 2022 installation ISO.
- Five VMs named SEA-DC1, SEA-ADM1, SEA-SVR1, SEA-SVR2, and SEA-SVR3.
- Nested virtualization enabled for SEA-SVR1 for Lab 3.

For VM creation, operating system installation, and virtual networking instructions, open `Allfiles\AZ802-Lab00\VM-Specs\Manual-Setup\local-hyperv-setup.md`.

### Task 2: Create the reusable baseline

1. Create and install the five VMs as described in the local Hyper-V setup guide.
1. Open Windows PowerShell as an administrator on the Hyper-V host.
1. Change to the local lab package folder:

   ```powershell
   Set-Location .\Allfiles\AZ802-Lab00\Lab-Packages
   ```

1. Run the baseline script:

   ```powershell
   .\Create-Baseline.ps1
   ```

The script configures networking, creates the `contoso.com` domain, joins the member servers, installs common management tools, and creates a checkpoint named `Baseline` on every VM.

### Task 3: Verify the Hyper-V baseline

1. Verify that every VM has a `Baseline` checkpoint:

   ```powershell
   'SEA-DC1', 'SEA-ADM1', 'SEA-SVR1', 'SEA-SVR2', 'SEA-SVR3' |
       ForEach-Object { Get-VMSnapshot -VMName $_ -Name 'Baseline' }
   ```

1. Connect to SEA-ADM1 and sign in with:

   - **Username**: `CONTOSO\Administrator`
   - **Password**: `PA55w.rd1234`

### Task 4: Prepare the environment for a lab

From an elevated Windows PowerShell session on the Hyper-V host, run the setup script for the lab that you want to complete. For example:

```powershell
.\Setup-Lab01.ps1
```

For Lab 3, run the setup without a parameter to download the parent VHD automatically:

```powershell
.\Setup-Lab03.ps1
```

To avoid waiting for the download during setup, download the Windows Server 2022 Datacenter Evaluation VHD from the [Microsoft Evaluation Center](https://www.microsoft.com/evalcenter/evaluate-windows-server-2022) ahead of time. Then, provide its path:

```powershell
.\Setup-Lab03.ps1 -BaseImageVhdPath 'D:\VHD\WindowsServer2022.vhd'
```

Each `Setup-Lab##.ps1` script restores all VMs to the `Baseline` checkpoint, starts the VMs needed for that lab, and applies its prerequisites. You can run the lab setup scripts in any order.

> **Warning**: Running a setup script discards changes made after the `Baseline` checkpoint. Confirm that you no longer need the current lab state before continuing.

### Task 5: Reset the Hyper-V environment

To discard the current lab changes and return all VMs to the baseline without preparing another lab, run the following commands on the Hyper-V host:

```powershell
$vmNames = 'SEA-DC1', 'SEA-ADM1', 'SEA-SVR1', 'SEA-SVR2', 'SEA-SVR3'
$vmNames | ForEach-Object {
    Stop-VM -Name $_ -TurnOff -Force -ErrorAction SilentlyContinue
    Restore-VMSnapshot -VMName $_ -Name 'Baseline' -Confirm:$false
}
```

## Exercise 5: Prepare for Labs 1 through 8

Use the following table to select the setup command and the first VM to connect to. The setup scripts prepare prerequisites only. Complete the learner tasks in the corresponding lab instructions after setup finishes.

| Lab | Focus | Hyper-V setup command | Primary VM | Additional requirement |
|---|---|---|---|---|
| 1 | Identity services and Group Policy | `.\Setup-Lab01.ps1` | SEA-ADM1 | None |
| 2 | Windows Server management | `.\Setup-Lab02.ps1` | SEA-ADM1 | Internet access |
| 3 | Virtualization | `.\Setup-Lab03.ps1` | SEA-ADM1 | Nested virtualization, internet access, and approximately 10 GB of free space on SEA-SVR1 |
| 4 | Network infrastructure services | `.\Setup-Lab04.ps1` | SEA-ADM1 | Internet access; Azure uses a nested Hyper-V host |
| 5 | Azure File Sync | `.\Setup-Lab05.ps1` | SEA-ADM1 | Azure subscription and internet access |
| 6 | Storage solutions | `.\Setup-Lab06.ps1` | SEA-ADM1 | Four data disks on SEA-SVR3 |
| 7 | Windows Server security | `.\Setup-Lab07.ps1` | SEA-SVR2 | None |
| 8 | Monitoring and troubleshooting | `.\Setup-Lab08.ps1` | SEA-SVR2 | None |

For Azure, use the same lab number with `deploy-lab-environment.ps1 -LabNumber <lab-number>`. For Hyper-V, run the command in the table from `Allfiles\AZ802-Lab00\Lab-Packages`.

### Prepare for Lab 1: Implement identity services and Group Policy

The Lab 1 setup starts SEA-DC1, SEA-ADM1, and SEA-SVR1. It installs the Active Directory and Group Policy management tools on SEA-ADM1 and enables Windows PowerShell remoting on SEA-SVR1.

- **Hyper-V**: Run `.\Setup-Lab01.ps1`.
- **Azure**: Deploy with `-LabNumber 1`.
- **Start the lab on**: SEA-ADM1.

### Prepare for Lab 2: Manage Windows Server

The Lab 2 setup starts SEA-DC1 and SEA-ADM1 and verifies the remote-management prerequisites. SEA-ADM1 needs internet access to download Windows Admin Center during the lab.

- **Hyper-V**: Run `.\Setup-Lab02.ps1`.
- **Azure**: Deploy with `-LabNumber 2`.
- **Start the lab on**: SEA-ADM1.

### Prepare for Lab 3: Implement virtualization

The Lab 3 setup starts SEA-DC1, SEA-ADM1, and SEA-SVR1. It installs Hyper-V on SEA-SVR1, stages the Windows Server 2022 Datacenter Evaluation VHD as the bootable parent disk, and installs the Hyper-V management tools on SEA-ADM1.

- **Hyper-V**: Run `.\Setup-Lab03.ps1` to download the parent VHD automatically. If you downloaded it ahead of time, run `.\Setup-Lab03.ps1 -BaseImageVhdPath '<VHD-path>'` instead.
- **Azure**: Deploy with `-LabNumber 3`. The default VM size supports nested virtualization, SEA-SVR1 uses the required Standard security type, and the parent VHD downloads automatically.
- **Start the lab on**: SEA-ADM1.

### Prepare for Lab 4: Implement network infrastructure services

The Lab 4 setup starts SEA-DC1, SEA-ADM1, and SEA-SVR1. It installs and authorizes DHCP on SEA-DC1, creates the Contoso DHCP scope, and installs DHCP and DNS management tools on SEA-ADM1. In Azure, these three machines run as nested VMs on a private Hyper-V switch so that DHCP broadcasts and temporary guest IP changes work as written in Lab 4.

- **Hyper-V**: Run `.\Setup-Lab04.ps1`.
- **Azure**: Deploy with `-LabNumber 4`. RDP to the Azure host, and then RDP from the host to `172.16.10.11` to begin the unchanged Lab 4 instructions.
- **Start the lab on**: SEA-ADM1.

### Prepare for Lab 5: Implement Azure File Sync

The Lab 5 setup starts SEA-DC1, SEA-ADM1, SEA-SVR1, and SEA-SVR2. It copies the canonical DFS and Azure File Sync files to SEA-ADM1 and verifies that SEA-SVR1 and SEA-SVR2 each have an online, writable, raw data disk. The learner script initializes those disks and creates the data folders during the lab. You also need an Azure subscription for the Azure File Sync resources created during the lab.

- **Hyper-V**: Run `.\Setup-Lab05.ps1`.
- **Azure**: Deploy with `-LabNumber 5`.
- **Start the lab on**: SEA-ADM1.

### Prepare for Lab 6: Implement storage solutions

The Lab 6 setup starts SEA-DC1, SEA-ADM1, and SEA-SVR3. It prepares the lab files on SEA-ADM1 and returns the four SEA-SVR3 data disks to the offline, raw state required by the lab.

- **Hyper-V**: Run `.\Setup-Lab06.ps1`.
- **Azure**: Deploy with `-LabNumber 6`.
- **Start the lab on**: SEA-ADM1.

Lab 6 contains multiple exercises that modify the same storage devices. Return the VMs to the baseline and rerun the Lab 6 setup when the lab instructions direct you to revert the VMs between exercises.

- **Hyper-V**: Rerun `.\Setup-Lab06.ps1`.
- **Azure**: Delete the resource group, redeploy with `-LabNumber 6`, and then continue with the next exercise.

### Prepare for Lab 7: Configure Windows Server security

The Lab 7 setup starts SEA-DC1, SEA-SVR1, and SEA-SVR2. It creates the required Active Directory organizational unit and test accounts and places the security lab files and tools on SEA-SVR2.

- **Hyper-V**: Run `.\Setup-Lab07.ps1`.
- **Azure**: Deploy with `-LabNumber 7`.
- **Start the lab on**: SEA-SVR2.

### Prepare for Lab 8: Monitor and troubleshoot Windows Server

The Lab 8 setup starts SEA-DC1 and SEA-SVR2. It places the CPU stress utility in the Lab 8 folder and configures the remote-management and event-log prerequisites.

- **Hyper-V**: Run `.\Setup-Lab08.ps1`.
- **Azure**: Deploy with `-LabNumber 8`.
- **Start the lab on**: SEA-SVR2.

### Reset before selecting another lab

Don't apply another lab setup over an environment that contains changes from a completed lab.

- **Hyper-V**: Running the next `Setup-Lab##.ps1` script automatically restores the `Baseline` checkpoint before applying the new prerequisites.
- **Azure**: Delete the existing resource group and deploy a new environment with the next lab number.

## Results

You created or deployed the AZ-802 baseline, applied the prerequisites for a selected lab, and verified that the environment is ready. Continue to the corresponding AZ-802 lab instructions.
