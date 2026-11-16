---
lab:
  title: 'Lab: Implementing and configuring virtualization in Windows Server'
  description: 'In this lab, you create and configure Hyper-V virtual machines, including virtual switches and virtual hard disks. You also deploy and manage Windows containers to practice host virtualization and container-based workloads.'
  duration: 60 minutes
  level: 300
  islab: true
  status: 'live'
  targetDate: 2026-08-28
  primarytopics:
    - Hyper-V
    - Windows Containers
    - Windows Server
    - Virtualization
---

# Lab: Implementing and configuring virtualization in Windows Server

This lab should take approximately **60** minutes to complete.

### Exercise 1: Creating and configuring VMs

#### Task 1: Create a Hyper-V virtual switch

1. Connect to **SEA-ADM1** and, if needed, sign in with the credentials provided by the instructor.
1. On **SEA-ADM1**, select **Start**, and then select **Server Manager**.
1. In Server Manager, select **All Servers**.
1. In the Servers list, select the **SEA-SVR1** entry, display its context menu, and then select **Hyper-V Manager**.
1. In Hyper-V Manager, ensure that **SEA-SVR1.CONTOSO.COM** is selected.
1. In the Actions pane, select **Virtual Switch Manager**.
1. In the **Virtual Switch Manager**, in the **Create virtual switch** pane, select **Private**, and then select **Create Virtual Switch**.
1. In the **Virtual Switch Properties** box, specify the following settings, and then select **OK**:

   - Name: `Contoso Private Switch`
   - Connection type: **Private network**

#### Task 2: Create a virtual hard disk

1. On **SEA-ADM1**, in Hyper-V Manager connected to **SEA-SVR1**, select **New**, and then select **Hard Disk**. The **New Virtual Hard Disk Wizard** starts.
1. On the **Before You Begin** page, select **Next**.
1. On the **Choose Disk Format** page, select **VHD** and then select **Next**.
1. On the **Choose Disk Type** page, select **Differencing**, and then select **Next**.
1. On the **Specify Name and Location** page, specify the following settings, and then select **Next**:

   - Name: `SEA-VM1`
   - Location: `C:\Base`

1. On the **Configure Disk** page, in the **Location** box, enter `C:\Base\BaseImage.vhd`, and then select **Next**.
1. On the **Summary** page, select **Finish**.

#### Task 3: Create a virtual machine

1. On **SEA-ADM1**, in Hyper-V Manager, verify that **SEA-SVR1.CONTOSO.COM** is selected. In the **Actions** pane, under **SEA-SVR1.CONTOSO.COM**, select **New**, and then select **Virtual Machine**. The **New Virtual Machine Wizard** starts.
1. On the **Before You Begin** page, select **Next**.
1. On the **Specify Name and Location** page, enter `SEA-VM1`, and then select the check box next to **Store the virtual machine in a different location**.
1. In the **Location** box, enter `C:\Base`, and then select **Next**.
1. On the **Specify Generation** page, select **Generation 1**, and then select **Next**.
1. On the **Assign Memory** page, enter **4096**, and then select **Next**.
1. On the **Configure Networking** page, select the Connection drop-down menu, select **Contoso Private Switch**, and then select **Next**.
1. On the **Connect Virtual Hard Disk** page, select **Use an existing virtual hard disk**, and then select **Browse**.
1. Browse to **C:\Base**, select **SEA-VM1.vhd**, select **Open**, and then select **Next**.
1. On the **Summary** page, select **Finish**. Notice that **SEA-VM1** displays in the Virtual Machines list.
1. Select **SEA-VM1**, and then in the Actions pane, under **SEA-VM1**, select **Settings**.
1. In the **Hardware** list, select **Memory**.
1. In the **Dynamic Memory** section, select the check box next to **Enable Dynamic Memory**.
1. Next to **Maximum RAM**, enter `4096`, and then select **OK**.
1. Close Hyper-V Manager.

#### Task 4: Manage Virtual Machines using Windows Admin Center

1. On **SEA-ADM1**, select **Start**, and then select **Windows PowerShell (Admin)**.
1. In the **Windows PowerShell** console, enter the following command, and then press Enter to use **C:\Allfiles** as the working folder for downloading and running the installer:

   ```powershell
   Set-Location C:\Allfiles
   ```

   >**Note**: Perform the next two steps to install Windows Admin Center on **SEA-ADM1**.

1. In the **Windows PowerShell** console, enter the following command. and then press Enter to download the latest version of Windows Admin Center:
	
   ```powershell
   $parameters = @{
     Source = "https://aka.ms/WACdownload"
     Destination = ".\WindowsAdminCenter.exe"
     }
   Start-BitsTransfer @parameters
   ```
1. Enter the following command, and then press Enter to install Windows Admin Center:
	
   ```powershell
   .\WindowsAdminCenter.exe /SILENT
   ```

   > **Note**: Wait until the installation completes. This might take several minutes.

1. In the Windows PowerShell window, enter the following command, and then press Enter:

   ```powershell
   Get-Service -Name WindowsAdminCenter
   ```

1. If the **WindowsAdminCenter** service has a status of **Stopped**, enter the following command, and then press Enter:

   ```powershell
   Start-Service -Name WindowsAdminCenter
   ```

1. Run `Get-Service -Name WindowsAdminCenter` again and verify that the service has a status of **Running**.

1. On **SEA-ADM1**, start Microsoft Edge, and then go to `https://SEA-ADM1.contoso.com`. 
   
   > **Note**: If the page displays **ERR_CONNECTION_REFUSED**, run `Get-Service -Name WindowsAdminCenter` in an elevated Windows PowerShell window. If the service is stopped, run `Start-Service -Name WindowsAdminCenter`, and then refresh Microsoft Edge.

   >**Note**: If you get **NET::ERR_CERT_DATE_INVALID** error, select **Advanced** on the Edge browser page, at the bottom of page select **Continue to sea-adm1-contoso.com (unsafe)**.
   
1. If prompted, in the **Windows Security** dialog box, enter with the credentials provided by the instructor, and then select **OK**.

1. Review all tabs on the **Configure your Windows Admin Center Settings and environment** pop-up window, including the **Extensions** tab and select **Complete** to close the window.
1. Review the **New in this release** pop-up window and select **Close** in its upper-right corner.

1. On the **All connections** pane, select **+ Add**.
1. Select **Add manually**.
1. On the **Add or create resources** pane, on the **Servers** tile, select **Add**.
1. In the **Server name** text box, enter `sea-svr1.contoso.com`.
1. Select **Add**.
1. On the **All connections** page, select **sea-svr1.contoso.com**, and then select **Connect**.

   > **Note**: If prompted for credentials, enter **CONTOSO\Administrator** and the password provided by the instructor.

   > **Note**: To perform single sign-on, you would need to set up Kerberos constrained delegation.

1. On the **sea-svr1.contoso.com** page, in the **Tools** list, select **Virtual machines**.
1. If necessary, select **Detailed mode** to display the **Summary** and **Inventory** tabs.
1. Select the **Summary** tab, and then review its content.
1. Select the **Inventory** tab and verify that it contains SEA-VM1.
1.  Select **SEA-VM1** and review its Properties pane.
1. Select **Settings**, and then select **Disks**. If **Settings** isn't visible, select the ellipsis (**...**) menu to find it.
1. Scroll to the bottom of the pane and select **+ Add disk**.
1. Select **New Virtual Hard Disk**.
1. On the **New Virtual Hard Disk** pane, in the **Size (GB)** text box, type **5**, leave other settings with their default values, and then select **Create**.
1. Select **Save disks settings**, and then select **Close**.
1. Back on the **Properties** pane of **SEA-VM1**, select **Power**, and then select **Start** to start **SEA-VM1**.
1. Scroll down and display the statistics for the running VM.
1. Refresh the page, select **Power**, select **Shut down**, and then select **Yes** to confirm.
1. In the **Tools** list, select **Virtual switches** and identify the existing switches.

### Exercise 1 results

After this exercise, you should have used Hyper-V Manager and Windows Admin Center to create a virtual switch, a virtual hard disk, a virtual machine, and then manage the virtual machine.

### Exercise 2: Installing and configuring containers

#### Task 1: Install Docker on Windows Server

1. On **SEA-ADM1**, in Windows Admin Center, return to the **Overview** page for **sea-svr1.contoso.com**.
1. On **SEA-ADM1**, in the **Tools** listing for **SEA-SVR1**, select **PowerShell**. If prompted, authenticate with the credentials provided by the instructor, and then press Enter.

   > **Note**: This establishes a PowerShell Remoting connection to SEA-SVR1.

   > **Note**: The Powershell connection in Windows Admin Center may be relatively slow due to nested virtualization used in the lab, so an alternate method is to run `Enter-PSSession -ComputerName SEA-SVR1` from a Windows Powershell console on **SEA-ADM1**.

1. In the PowerShell session connected to **SEA-SVR1**, run the following commands to create **C:\Allfiles** if it doesn't exist and use it as the working folder:

   ```powershell
   New-Item -Path C:\Allfiles -ItemType Directory -Force
   Set-Location C:\Allfiles
   ```

1. In the **Windows PowerShell** console, enter the following commands, and then press Enter to install the Docker CE (Community Edition) on **SEA-SVR1**:

   ```powershell
   Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/microsoft/Windows-Containers/Main/helpful_tools/Install-DockerCE/install-docker-ce.ps1" -o install-docker-ce.ps1

   .\install-docker-ce.ps1
   ```
 
1. After the installation completes, enter the following command, and then press Enter to restart **SEA-SVR1**:

   ```powershell
   Restart-Computer -Force
   ```

#### Task 2: Install and run a Windows container

1. After **SEA-SVR1** restarts, use the PowerShell tool again to establish a new PowerShell Remoting session to **SEA-SVR1**.

   > **Note**: Run all commands in this task in the PowerShell session connected to **SEA-SVR1**. The container commands run without an interactive terminal and work in the Windows Admin Center PowerShell tool or an `Enter-PSSession` session.

1. In the session connected to **SEA-SVR1**, run the following command to return to the working folder:

   ```powershell
   Set-Location C:\Allfiles
   ```

   > **Note**: After each restart or reconnection, return to **C:\Allfiles** before continuing host-side PowerShell commands on **SEA-SVR1**.

1. In the **Windows PowerShell** console, enter the following command, and then press Enter to identify Docker images currently present on **SEA-SVR1**: 

   ```powershell
   docker images
   ```

   > **Note**: Verify that there are no images in the local repository store.

1. Enter the following command, and then press Enter to download a Nano Server image:

   ```powershell
   docker pull mcr.microsoft.com/windows/nanoserver:ltsc2022
   ```

   > **Note**: The time it takes to complete the download will depend on the available bandwidth of the network connection from the lab VM to the Microsoft container registry.

1. Enter the following command, and then press Enter to verify that the Docker image has been successfully downloaded:

   ```powershell
   docker images
   ```

1. In the PowerShell session connected to **SEA-SVR1**, run the following command to start a container, display its hostname, and create **Hello.txt** inside it:

   ```powershell
   docker run mcr.microsoft.com/windows/nanoserver:ltsc2022 cmd.exe /s /c "hostname & echo Hello World! > C:\Users\Public\Hello.txt"
   ```

   > **Note**: The displayed hostname belongs to the container, not **SEA-SVR1**. The container stops automatically after creating the file, and control returns to the PowerShell prompt on **SEA-SVR1**. Don't enter `exit`, because that would close your remote PowerShell session.

1. To find the ID of the container you just created, run the following command on **SEA-SVR1**:

   ```powershell
   docker ps -a
   ```
   > **Note**: The `-a` switch lists all containers, including those that are not currently running.

1. Create a new **helloworld** image that includes the file you added. Run the following command, replacing \<containerID\> with the **CONTAINER ID** of the container you just created:

   ```powershell
   docker commit <containerID> helloworld
   ```

1. You now have a custom image that contains the Hello.txt file. You can use the docker images command to see the new image.

   ```powershell
   docker images
   ```

1. Run the new container by using the docker run command with the --rm option. When you use this option, Docker automatically removes the container when the command, cmd.exe in this case, stops.

   ```powershell
   docker run --rm helloworld cmd.exe /s /c type C:\Users\Public\Hello.txt
   ```
   > **Note**: This command line outputs the content of the file you created earlier and stops the container again.

1. Enter the following command, and then press Enter to launch a new container instance of the original image and check if the file you created is present:

   ```powershell
   docker run --rm mcr.microsoft.com/windows/nanoserver:ltsc2022 cmd.exe /s /c type C:\Users\Public\Hello.txt
   ```
   > **Note**: Expect the message **The system cannot find the file specified.** The original Nano Server image doesn't contain **Hello.txt**. The file exists only in the **helloworld** image you created with `docker commit`. This error is expected and confirms that the original image remains unchanged.


#### Task 3: Use Windows Admin Center to manage containers

1. On **SEA-ADM1**, in the Windows Admin Center, go to the settings icon in the top left corner, and then select **Extensions**.

1. In the **Extensions** pane, verify the **Containers** extension is installed and updated under **Installed Extension**. If the extension is not installed, add it from the **Available Extensions** pane.

1. On **SEA-ADM1**, in the Windows Admin Center, in the Tools menu of **sea-svr1.contoso.com**, select **Containers**. When prompted to close the **PowerShell** session, select **Continue**.

1. In the Containers pane, browse through the **Overview**, **Containers**, **Images**, **Networks**, and **Volumes** tabs.

### Exercise 2 results

After this exercise, you should have installed Docker on Windows Server, downloaded a Windows container image containing web services, and verified its functionality.
