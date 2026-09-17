$ErrorActionPreference = 'Stop'

$parentPath = 'C:\Base\BaseImage.vhd'
$validationVmName = 'AZ802-Validation-VM'
$validationSwitchName = 'AZ802-Validation-Switch'
$validationDiskPath = 'C:\Base\AZ802-Validation-Diff.vhd'

$computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
if (-not $computerSystem.PartOfDomain -or $computerSystem.Domain -ne 'contoso.com') {
    throw "SEA-SVR1 isn't joined to contoso.com. Current domain: $($computerSystem.Domain)"
}
if (-not (Get-WindowsFeature -Name Hyper-V).Installed) {
    throw 'The Hyper-V role is not installed.'
}
if ((Get-Service -Name vmms).Status -ne 'Running') {
    throw 'The Hyper-V Virtual Machine Management service is not running.'
}
Get-VMHost | Out-Null

$githubReachable = Test-NetConnection -ComputerName 'raw.githubusercontent.com' -Port 443 -InformationLevel Quiet
$containerRegistryReachable = Test-NetConnection -ComputerName 'mcr.microsoft.com' -Port 443 -InformationLevel Quiet
if (-not $githubReachable -or -not $containerRegistryReachable) {
    throw 'One or more Lab 3 download endpoints are unavailable over HTTPS.'
}

$parentImage = Get-Item -LiteralPath $parentPath -ErrorAction Stop
if ($parentImage.Length -lt 9000000000) {
    throw "The parent VHD is unexpectedly small: $($parentImage.Length) bytes."
}

$mounted = $false
try {
    $diskImage = Mount-DiskImage -ImagePath $parentPath -Access ReadOnly -PassThru
    $mounted = $true
    $disk = $diskImage | Get-Disk
    if ($disk.PartitionStyle -ne 'MBR') {
        throw "The parent VHD partition style is $($disk.PartitionStyle), not MBR."
    }

    $partitions = $disk | Get-Partition
    if (-not ($partitions | Where-Object IsActive)) {
        throw 'The parent VHD has no active partition.'
    }

    $kernel = $partitions | Get-Volume -ErrorAction SilentlyContinue |
        Where-Object DriveLetter |
        ForEach-Object { Get-Item -LiteralPath "$($_.DriveLetter):\Windows\System32\ntoskrnl.exe" -ErrorAction SilentlyContinue } |
        Select-Object -First 1
    if (-not $kernel) {
        throw 'Windows\System32\ntoskrnl.exe was not found in the parent VHD.'
    }

    $kernelVersion = $kernel.VersionInfo.ProductVersion
    if ($kernelVersion -notlike '10.0.20348*') {
        throw "The parent VHD kernel version is $kernelVersion, not Windows Server 2022 build 20348."
    }
}
finally {
    if ($mounted) {
        Dismount-DiskImage -ImagePath $parentPath
    }
}

if (Get-VM -Name $validationVmName -ErrorAction SilentlyContinue) {
    throw "Temporary validation VM '$validationVmName' already exists."
}
if (Get-VMSwitch -Name $validationSwitchName -ErrorAction SilentlyContinue) {
    throw "Temporary validation switch '$validationSwitchName' already exists."
}
if (Test-Path -LiteralPath $validationDiskPath) {
    throw "Temporary validation disk '$validationDiskPath' already exists."
}

$runningStateVerified = $false
$heartbeatStatus = 'Unavailable'
try {
    New-VMSwitch -Name $validationSwitchName -SwitchType Private | Out-Null
    New-VHD -Path $validationDiskPath -ParentPath $parentPath -Differencing | Out-Null
    New-VM -Name $validationVmName -Generation 1 -MemoryStartupBytes 4GB `
        -VHDPath $validationDiskPath -SwitchName $validationSwitchName | Out-Null
    Start-VM -Name $validationVmName

    $validationVm = Get-VM -Name $validationVmName
    $runningStateVerified = $validationVm.State -eq 'Running'
    if (-not $runningStateVerified) {
        throw "The temporary nested VM state is $($validationVm.State), not Running."
    }

    $heartbeat = Get-VMIntegrationService -VMName $validationVmName -Name Heartbeat -ErrorAction SilentlyContinue
    if ($heartbeat) {
        $heartbeatStatus = $heartbeat.PrimaryStatusDescription
    }
}
finally {
    $temporaryVm = Get-VM -Name $validationVmName -ErrorAction SilentlyContinue
    if ($temporaryVm) {
        if ($temporaryVm.State -ne 'Off') {
            Stop-VM -Name $validationVmName -TurnOff -Force
        }
        Remove-VM -Name $validationVmName -Force
    }
    if (Get-VMSwitch -Name $validationSwitchName -ErrorAction SilentlyContinue) {
        Remove-VMSwitch -Name $validationSwitchName -Force
    }
    if (Test-Path -LiteralPath $validationDiskPath) {
        Remove-Item -LiteralPath $validationDiskPath -Force
    }
}

$cleanupVerified =
    -not (Get-VM -Name $validationVmName -ErrorAction SilentlyContinue) -and
    -not (Get-VMSwitch -Name $validationSwitchName -ErrorAction SilentlyContinue) -and
    -not (Test-Path -LiteralPath $validationDiskPath)
if (-not $cleanupVerified) {
    throw 'One or more temporary Hyper-V validation artifacts remain after cleanup.'
}

[pscustomobject]@{
    Domain = $computerSystem.Domain
    HyperVInstalled = $true
    VmmsStatus = 'Running'
    GitHub443 = $githubReachable
    Mcr443 = $containerRegistryReachable
    ParentVhdBytes = $parentImage.Length
    ParentPartitionStyle = 'MBR'
    ParentHasActivePartition = $true
    ParentKernelVersion = $kernelVersion
    NestedVmReachedRunning = $runningStateVerified
    NestedVmHeartbeat = $heartbeatStatus
    TemporaryArtifactsRemoved = $cleanupVerified
} | ConvertTo-Json -Compress