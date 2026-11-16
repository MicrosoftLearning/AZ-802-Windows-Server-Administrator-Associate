---
lab:
  title: 'Lab: Configuring security in Windows Server'
  description: You configure Windows Defender Credential Guard by using Group Policy and the hardware readiness tool. You identify and remediate risky domain account settings, and deploy Local Administrator Password Solution across domain-joined servers.
  duration: 40 minutes
  level: 300
  islab: true
  status: 'live'
  targetDate: 2026-08-28
  primarytopics:
    - Windows Server
    - Security
    - Active Directory
    - LAPS
    - Group Policy
---

# Lab: Configuring security in Windows Server

This lab should take approximately **40** minutes to complete.

## Exercise 1: Configuring Windows Defender Credential Guard

> **Note**: In the lab environment, Credential Guard will not be available on VMs because they don't meet the prerequisites. This, however, will not prevent you from stepping through the process of implementing it by using Group Policy and evaluating its readiness by using corresponding tools.

#### Task 1: Enable Windows Defender Credential Guard using Group Policy 

1. Connect to **SEA-SVR2** and, if needed, sign in with the credentials provided by the instructor.
1. In the **Type here to search** text box next to the **Start** button, enter **Group Policy Management**.
1. In the list of results, select **Group Policy Management**.
1. In the **Group Policy Management** console, expand **Forest: contoso.com**, expand **Domains**, expand **contoso.com**, right-click or access the **context** menu for the **IT** Organizational Unit (OU), and then select **Create a GPO in this domain, and Link it here**.
1. In the **New GPO** dialog box, in the **Name** text box, enter `CredentialGuard_GPO`, and then select **OK**.
1. In the **Group Policy Management** window, under **IT**, right-click or access the **context** menu for **CredentialGuard_GPO**, and then select **Edit**.
1. In the **Group Policy Management Editor**, browse to **Computer Configuration\\Policies\\Administrative Templates\\System\\Device Guard**.
1. Select **Turn On Virtualization Based Security**, and then select the **policy setting** link.
1. In the **Turn On Virtualization Based Security** window, select the **Enabled** option.
1. In the **Select Platform Security Level** drop-down list, ensure that the **Secure Boot and DMA Protection** entry is selected.
1. In the **Credential Guard Configuration** drop-down list, select the **Enabled with UEFI lock** entry.
1. In the **Secure Launch Configuration** drop-down list, select the **Enabled** entry, and then select **OK**.
1. Close the **Group Policy Management Editor** window.
1. Close the **Group Policy Management** console window.

#### Task 2: Enable Windows Defender Credential Guard using the Hypervisor-Protected Code Integrity (HVCI) and Windows Defender Credential Guard hardware readiness tool

1. On **SEA-SVR2**, select **Start**, right-click or access the **context** menu for **Windows PowerShell**, and then select **Run as administrator**.
1. At the Windows PowerShell command prompt, set the current location to **C:\Allfiles\AZ802-Lab07**, and then run the HVCI and Windows Defender Credential Guard hardware readiness tool. If a security warning appears, select **[R] Run once**. If the warning doesn't appear, continue to the next step. Press Enter for any other prompts:

   ```powershell
   Set-Location -Path 'C:\Allfiles\AZ802-Lab07'
   .\DG_Readiness_Tool.ps1 -Enable -AutoReboot
   ```

1. Wait until the tool completes its run and, when prompted, in the **You're about to be signed out** dialog box, select **Close**.

   > **Note**: The operating system will restart. 

1. Once the restart completes, sign back into **SEA-SVR2** with the credentials provided by the instructor.

## Exercise 2: Locating problematic accounts

#### Task 1: Locate and reconfigure domain accounts with non-expiring passwords

1. On **SEA-SVR2**, select **Start**, right-click or access the **context** menu for **Windows PowerShell**, and then select **Run as administrator**.
1. To list Active Directory-enabled user accounts with a non-expiring password, at the Windows PowerShell command prompt, enter the following command and press Enter:

   ```powershell
   Get-ADUser -Filter {Enabled -eq $true -and PasswordNeverExpires -eq $true}
   ```

1. Review the list of user accounts returned.
1. To enable password expiration for all user accounts in the result set, at the Windows PowerShell command prompt, enter the following command and press Enter:

   ```powershell
   Get-ADUser -Filter {Enabled -eq $true -and PasswordNeverExpires -eq $true} | Set-ADUser -PasswordNeverExpires $false
   ```

1. To verify the outcome, rerun the command from step 2 and notice that no results are returned.

#### Task 2: Locate and disable domain accounts that have not been used to sign in for at least 90 days

1. To identify Active Directory user accounts that have not been used to sign in for at least 90 days, at the Windows PowerShell command prompt, enter the following command and press Enter:

   ```powershell
   $days = (Get-Date).AddDays(-90)
   Get-ADUser -Filter {LastLogonTimeStamp -lt $days -and enabled -eq $true} -Properties LastLogonTimeStamp
   ```

   > **Note**: In the lab environment, no results will be returned.

1. To disable Active Directory user accounts that have not been used to sign in for at least 90 days, enter the following command and press Enter:

   ```powershell
   Get-ADUser -Filter {LastLogonTimeStamp -lt $days -and enabled -eq $true} -Properties LastLogonTimeStamp | Disable-ADAccount
   ```

   > **Note**: In the lab environment, no results will be returned.

## Exercise 3: Implementing legacy Microsoft LAPS (Windows Server 2022 only)

> **Important**: Complete **only one** of Exercises 3 and 4 in this lab environment. This exercise uses legacy Microsoft LAPS on Windows Server 2022; its installer is blocked on Windows Server 2025. For the current, recommended solution, skip this exercise and complete **Exercise 4: Implementing Windows LAPS** on Windows Server 2025 or Windows Server 2022 with the April 11, 2023 or later updates. Both exercises configure the same server, OU, and GPO. If you want to try the other option later, start with a fresh lab environment.

#### Task 1: Prepare computer accounts for implementing LAPS (Local Administrator Password Solution)

1. To create a designated OU and move the **SEA-SVR1** computer account to it, on **SEA-SVR2**, at the Windows PowerShell command prompt, enter the following command and press Enter: 

   ```powershell
   New-ADOrganizationalUnit -Name "Seattle_Servers"
   Get-ADComputer SEA-SVR1 | Move-ADObject -TargetPath "OU=Seattle_Servers,DC=Contoso,DC=com"
   ```

1. To install LAPS, at the Windows PowerShell command prompt, enter the following command and press Enter:

   ```powershell
   Msiexec /i 'C:\Allfiles\AZ802-Lab07\LAPS.x64.msi'
   ```

1. On the **Welcome to the Local Administrator Password Solution Setup Wizard** page of the **Local Administrator Password Solution Setup** wizard, select **Next**.
1. On the **End-User License Agreement** page of the **Local Administrator Password Solution Setup** wizard, select **I accept the terms in the License Agreement**, and then select **Next**.
1. On the **Custom Setup** page of the **Local Administrator Password Solution Setup** wizard, in the drop-down menu next to **Management Tools**, select **Entire feature will be installed on the local hard drive**, and then select **Next**.
1. On the **Ready to install Local Administrator Password Solution** page of the **Local Administrator Password Solution Setup** wizard, select **Install**. 
1. Once the installation completes, on the final page of the **Local Administrator Password Solution Setup** wizard, select **Finish**.
1. To enable the Windows Defender Firewall with Advanced Security rule that allows incoming Server Message Block (SMB) connections from other domain-joined servers, at the Windows PowerShell command prompt, enter the following commands and, after each, press Enter:

   ```powershell
   $rule = Get-NetFirewallRule | Where-Object DisplayName -eq 'File and Printer Sharing (SMB-In)' 
   $rule | Set-NetFirewallRule -Profile Domain
   $rule | Enable-NetFirewallRule
   ```

   > **Note**: This is required to connect to **SEA-SVR2** from **SEA-SVR1** later in this lab.

#### Task 2: Prepare AD DS for LAPS

1. To prepare the domain for LAPS, on **SEA-SVR2**, at the Windows PowerShell command prompt, enter the following commands, and after each, press Enter:

   ```powershell
   Import-Module admpwd.ps
   Update-AdmPwdADSchema
   Set-AdmPwdComputerSelfPermission -Identity "Seattle_Servers"
   ```

1. On **SEA-SVR2**, in the **Type here to search** text box next to the **Start** button, enter **Group Policy Management**.
1. In the list of results, select **Group Policy Management**.
1. In the **Group Policy Management** console, expand **Forest: contoso.com**, expand **Domains**, expand **contoso.com**, right-click or access the **context** menu for the **Seattle_Servers** OU, and then select **Create a GPO in this domain, and Link it here**.
1. In the **New GPO** dialog box, in the **Name** text box, enter **LAPS_GPO**, and then select **OK**.
1. In the **Group Policy Management** window, under **Seattle_Servers**, right-click or access the **context** menu for **LAPS_GPO**, and then select **Edit**.
1. In the **Group Policy Management Editor** window, under **Computer Configuration**, expand the **Policies** node, expand the **Administrative Templates** node, and then select **LAPS**.
1. Select the **Enable local admin password management** policy, and then select the **policy settings** link.
1. In the **Enable local admin password management** window, select **Enabled**, and then select **OK**.
1. Select the **Password Settings** policy, and then select the **policy settings** link.
1. In the **Password Settings** policy dialog box, select **Enabled**, and then configure **Password Length** to **20**.
1. Verify that the **Password Age (Days)** is configured to **30**, and then select **OK**.
1. Close the Group Policy Management Editor.

#### Task 3: Deploy LAPS client-side extension

1. Switch to the console session to **SEA-SVR1** and then, if needed, sign in with the credentials provided by the instructor.

   > **Note:** You may be prompted to change your password. If prompted, choose an arbitrary password and use it throughout the remainder of the lab.

1. Once you sign in, to access the Windows PowerShell command prompt, at the **SConfig** menu prompt, enter **15** and press Enter.
   
   > **Note**: To open Notepad from PowerShell, type **Notepad** and press enter.

1. To install LAPS silently with the default settings, at the Windows PowerShell command prompt, enter the following command and press Enter:

   ```powershell
   Start-Process msiexec.exe -Wait -ArgumentList '/i \\SEA-SVR2.contoso.com\c$\Labfiles\Lab07\LAPS.x64.msi /quiet'
   ```

1. To trigger the processing of Group Policy that will apply **LAPS** settings locally, at the Windows PowerShell command prompt, enter the following command and press Enter:

   ```powershell
   gpupdate /force
   ```

#### Task 4: Verify LAPS

1. Switch to the console session to **SEA-SVR2**.
1. Select **Start**. In the **Start** menu, select **LAPS**, and then select **LAPS UI**.
1. In the **LAPS UI** dialog box, in the **Computer name** text box, enter **SEA-SVR1**, and then select **Search**.
1. Review the **Password** and the **Password expires** values, and then select **Exit**.
1. Switch to the **Windows PowerShell** console and then, to verify the value of the password, at the Windows PowerShell command prompt, enter the following command and press Enter:

   ```powershell
   Get-ADComputer -Identity SEA-SVR1 -Properties ms-Mcs-AdmPwd
   ```

1. Review the password assigned to SEA-SVR1 and note that it matches the one displayed in the **LAPS UI** tool.

   > **Note:** The value of the password is, in this case, enclosed in a pair of braces.

## Exercise 4: Implementing Windows LAPS

> **Important**: Complete **only one** of Exercises 3 and 4 in this lab environment. Windows LAPS is the current, recommended solution and is built into Windows Server 2025 and Windows Server 2022 with the April 11, 2023 or later updates. Exercise 3 is the legacy Microsoft LAPS alternative for Windows Server 2022 only. If you completed Exercise 3, start with a fresh lab environment before attempting this exercise; both alternatives configure the same server, OU, and GPO.

Windows Local Administrator Password Solution (Windows LAPS) manages SEA-SVR1's local administrator password and backs it up to Active Directory. Don't install the legacy **LAPS.x64.msi** package for this exercise.

> **Important**: Use **CONTOSO\Administrator** for this exercise, not a local Administrator account. Preparing the schema requires membership in **Schema Admins**; configuring permissions requires appropriate domain administrative rights. Password encryption requires a Windows Server 2016 or later domain functional level. **SEA-SVR1** must be a domain member server, not a domain controller.

#### Task 1: Prepare the computer account for Windows LAPS

1. On **SEA-SVR2**, sign in as **CONTOSO\Administrator**. Select **Start**, enter **Windows PowerShell**, and then select **Run as administrator**.
1. Run the following commands to confirm that the Windows LAPS module is available and review the domain functional level:

   ```powershell
   Get-Command -Module LAPS
   Get-ADDomain | Select-Object DNSRoot,DomainMode
   ```

   > **Note**: If the LAPS module is unavailable or the domain functional level is earlier than Windows Server 2016, stop and contact your instructor. Don't raise the domain functional level as part of this exercise.

1. Create an OU and move the **SEA-SVR1** computer account into it:

   ```powershell
   New-ADOrganizationalUnit -Name "Seattle_Servers"
   Get-ADComputer SEA-SVR1 | Move-ADObject -TargetPath "OU=Seattle_Servers,DC=Contoso,DC=com"
   ```

#### Task 2: Prepare AD DS and configure Windows LAPS policy

1. On **SEA-SVR2**, in the elevated Windows PowerShell window, run the following commands one at a time. When `Update-LapsADSchema` prompts you to add schema attributes, enter **A** (**Yes to All**) and press Enter. After the schema update completes without errors, run the permission command:

   ```powershell
   Import-Module LAPS
   Update-LapsADSchema
   Set-LapsADComputerSelfPermission -Identity "OU=Seattle_Servers,DC=contoso,DC=com"
   ```

   > **Note**: The schema update is a one-time forest operation. The permission command allows computers in this OU to update their own Windows LAPS password attributes. Domain Admins already have password retrieval rights and are the default authorized decryptors.

1. On **SEA-SVR2**, select **Start**, enter **Group Policy Management**, and then open **Group Policy Management**.
1. In the **Group Policy Management** console, expand **Forest: contoso.com**, expand **Domains**, expand **contoso.com**, right-click or access the **context** menu for the **Seattle_Servers** OU, and then select **Create a GPO in this domain, and Link it here**.
1. In the **New GPO** dialog box, in the **Name** text box, enter `LAPS_GPO`, and then select **OK**.
1. In the **Group Policy Management** window, under **Seattle_Servers**, right-click or access the **context** menu for **LAPS_GPO**, and then select **Edit**.
1. In **Group Policy Management Editor**, browse to **Computer Configuration\Policies\Administrative Templates\System\LAPS**.
1. Open **Configure password backup directory**, select **Enabled**, select **Active Directory** as the backup directory, and then select **OK**.
1. Open **Password Settings**, select **Enabled**, set **Password Length** to **20** and **Password Age (Days)** to **30**, and then select **OK**. Leave password complexity at its default value.
1. Open **Enable password encryption**, select **Enabled**, and then select **OK**.

   > **Note**: Leave **Name of administrator account to manage** and automatic account management settings **Not Configured**. Windows LAPS manages the existing built-in local administrator account by its identifier, even if it has been renamed. Leave **Configure authorized password decryptors** **Not Configured** to use the default Domain Admins group.

1. Close the Group Policy Management Editor.

#### Task 3: Apply Windows LAPS policy on SEA-SVR1

1. Switch to the console session for **SEA-SVR1**, and sign in as **CONTOSO\Administrator**.

   > **Important**: Windows LAPS changes the password of SEA-SVR1's local administrator account, not the domain Administrator account. Continue using **CONTOSO\Administrator** for lab administration.

1. If the **SConfig** menu appears, enter **15** and press Enter to open PowerShell. If a desktop appears instead, select **Start**, enter **Windows PowerShell**, and then select **Run as administrator**.
1. Run the following commands to refresh Group Policy and process Windows LAPS policy:

   ```powershell
   gpupdate /force
   Invoke-LapsPolicyProcessing
   ```

1. Review the latest Windows LAPS events:

   ```powershell
   Get-WinEvent -LogName 'Microsoft-Windows-LAPS/Operational' -MaxEvents 10 | Format-List TimeCreated,Id,Message
   ```

   > **Note**: Event **10018** records a successful password backup to Active Directory, and event **10004** records successful policy processing. If processing fails, review the event messages and resolve the reported error before continuing.

#### Task 4: Retrieve the Windows LAPS password

1. Switch to **SEA-SVR2**. In an elevated Windows PowerShell window running as **CONTOSO\Administrator**, run:

   ```powershell
   Get-LapsADPassword -Identity SEA-SVR1 -AsPlainText
   ```

1. Review **ComputerName**, **Account**, **Password**, and **ExpirationTimestamp**. Verify that **Source** is **EncryptedPassword** and **DecryptionStatus** is **Success**.

   > **Important**: The `-AsPlainText` parameter displays the managed password. Don't include it in screenshots, reports, or shared notes. Without this parameter, the cmdlet returns the password as a secure string.

   > **Note**: If no password is returned, confirm that policy processing succeeded on SEA-SVR1 and allow time for AD replication before retrying. An access or decryption error requires checking the account's permissions rather than reinstalling LAPS.
