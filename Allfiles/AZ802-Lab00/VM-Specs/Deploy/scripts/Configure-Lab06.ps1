# Configure-Lab06.ps1 — Implementing storage solutions in Windows Server
# Runs on: SEA-DC1, SEA-ADM1, SEA-SVR1, SEA-SVR2, SEA-SVR3

$ErrorActionPreference = 'SilentlyContinue'
$hostname = $env:COMPUTERNAME

switch ($hostname) {
    'SEA-DC1' {
        Write-Output "[SEA-DC1] Enabling WinRM..."
        Enable-PSRemoting -Force -SkipNetworkProfileCheck
        Write-Output "[SEA-DC1] Lab 06 config complete (iSCSI initiator configured during lab)."
    }

    'SEA-ADM1' {
        Write-Output "[SEA-ADM1] Installing RSAT tools..."
        Install-WindowsFeature -Name RSAT-AD-Tools, RSAT-File-Services

        Write-Output "[SEA-ADM1] Creating C:\Labfiles directory and sharing it..."
        New-Item -Path 'C:\Labfiles' -ItemType Directory -Force | Out-Null
        New-Item -Path 'C:\Labfiles\Lab06' -ItemType Directory -Force | Out-Null

        # Share C:\Labfiles for access from other VMs
        New-SmbShare -Name 'Labfiles' -Path 'C:\Labfiles' -FullAccess 'Everyone' -ErrorAction SilentlyContinue

        # Create CreateLabFiles.cmd — generates sample files for dedup testing
        Write-Output "[SEA-ADM1] Creating CreateLabFiles.cmd..."
        $createFilesCmd = @'
    fsutil file createnew M:\data\report.docx 2543210987
    fsutil file createnew M:\data\report2.docx 2543210987
    fsutil file createnew M:\data\report3.docx 2543210987
    fsutil file createnew M:\data\report4.docx 2543210987
    fsutil file createnew M:\data\report5.docx 2543210987
    fsutil file createnew M:\data\report6.docx 2543210987
    fsutil file createnew M:\data\report7.docx 2543210987
    fsutil file createnew M:\data\report8.docx 2543210987
    fsutil file createnew M:\data\report9.docx 2543210987
    fsutil file createnew M:\data\report10.docx 2543210987
    fsutil file createnew M:\data\report11.docx 2543210987
    fsutil file createnew M:\data\report12.docx 2543210987
    fsutil file createnew M:\data\report13.docx 2543210987
    fsutil file createnew M:\data\report14.docx 2543210987
    fsutil file createnew M:\data\report15.docx 2543210987
    fsutil file createnew M:\data\report16.docx 2543210987
    fsutil file createnew M:\data\report17.docx 2543210987
    fsutil file createnew M:\data\report18.docx 2543210987
    fsutil file createnew M:\data\report19.docx 2543210987
    fsutil file createnew M:\data\report20.docx 2543210987
    fsutil file createnew M:\data\report.xlsx 2543210987
    fsutil file createnew M:\data\program.exe 2543210987
    fsutil file createnew M:\data\script.cmd 2543210987
    fsutil file createnew M:\data\song1.mp3 2543210987
    fsutil file createnew M:\data\song2.mp3 2543210987
    fsutil file createnew M:\data\song3.mp3 2543210987
    fsutil file createnew M:\data\song4.mp3 2543210987
'@
        $createFilesCmd | Out-File -FilePath 'C:\Labfiles\Lab06\CreateLabFiles.cmd' -Encoding ASCII

        Write-Output "[SEA-ADM1] Enabling PS Remoting trust..."
        Set-Item WSMan:\localhost\client\trustedhosts -Value '*.contoso.com' -Force

        Write-Output "[SEA-ADM1] Lab 06 config complete."
    }

    { $_ -in @('SEA-SVR1', 'SEA-SVR2', 'SEA-SVR3') } {
        # Disks 1-4 should be offline and raw for the lab exercises
        foreach ($diskNum in 1..4) {
            $disk = Get-Disk -Number $diskNum -ErrorAction SilentlyContinue
            if ($disk) {
                if ($disk.PartitionStyle -ne 'RAW') {
                    Clear-Disk -Number $diskNum -RemoveData -RemoveOEM -Confirm:$false -ErrorAction SilentlyContinue
                }
                Set-Disk -Number $diskNum -IsOffline $true -ErrorAction SilentlyContinue
            }
        }


        Write-Output "[$hostname] Enabling WinRM..."
        Enable-PSRemoting -Force -SkipNetworkProfileCheck

        Write-Output "[$hostname] Enabling firewall rules for remote management..."
        Enable-NetFirewallRule -DisplayGroup 'Remote Service Management' -ErrorAction SilentlyContinue
        Enable-NetFirewallRule -DisplayGroup 'Remote Volume Management' -ErrorAction SilentlyContinue
        Enable-NetFirewallRule -DisplayGroup 'Windows Remote Management' -ErrorAction SilentlyContinue

        Write-Output "[$hostname] Lab 06 config complete."
        Write-Output "[$hostname] Disk 0 = OS, Disks 1-4 = 128GB each, offline/raw."
    }
}
