$srvName = 'SEA-SVR1'
$rgName = 'AZ802-L0501-RG'
$fsName = 'FileSync1'

New-Item -Type Directory -Path "\\$srvName\c$\Temp" -Force
Copy-Item -Path C:\Labfiles\Lab05\StorageSyncAgent_WS2022.msi -Destination "\\$srvName\c$\Temp\" -PassThru

Invoke-Command -ComputerName $srvName -ArgumentList ($rgName, $fsName) {
    param($rgName, $fsName)
    Write-Output "Step 1/5: Installing NuGet package provider..."
    Install-PackageProvider -Name NuGet -Force
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    Write-Output "Step 2/5: Installing az.StorageSync module..."
    Install-Module az.StorageSync -Force
    Write-Output "Step 3/5: Installing Azure File Sync agent (see C:\Temp\StorageSyncAgent_install.log for progress)..."
    Start-Process -FilePath "msiexec.exe" -ArgumentList '/i "C:\Temp\StorageSyncAgent_WS2022.msi" /quiet /norestart /l*v C:\Temp\StorageSyncAgent_install.log' -Wait
    Write-Output "Step 4/5: Sign in to register this server..."
    Connect-AzAccount -UseDeviceAuthentication
    Write-Output "Step 5/5: Registering server with Storage Sync Service..."
    Register-AzStorageSyncServer -ResourceGroupName $rgName -StorageSyncServiceName $fsName | Out-Null
    Write-Output "Script finished"
}
