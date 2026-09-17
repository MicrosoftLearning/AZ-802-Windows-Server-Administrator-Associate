function Test-Lab03BaseImage {
    [CmdletBinding()]
    param(
        [string]$VhdPath = 'C:\Base\BaseImage.vhd'
    )

    if (-not (Test-Path -LiteralPath $VhdPath -PathType Leaf)) {
        return $false
    }

    $mountedVhd = $null
    try {
        $mountedVhd = Mount-VHD -Path $VhdPath -ReadOnly -Passthru -ErrorAction Stop
        $disk = $mountedVhd | Get-Disk
        if ($disk.PartitionStyle -ne 'MBR') {
            return $false
        }

        $partitions = $disk | Get-Partition
        if (-not ($partitions | Where-Object IsActive)) {
            return $false
        }

        $windowsVolume = $disk | Get-Partition | Get-Volume |
            Where-Object { $_.DriveLetter -and (Test-Path -LiteralPath "$($_.DriveLetter):\Windows\System32\ntoskrnl.exe") } |
            Select-Object -First 1

        if (-not $windowsVolume) {
            return $false
        }

        $kernel = Get-Item -LiteralPath "$($windowsVolume.DriveLetter):\Windows\System32\ntoskrnl.exe"
        return $kernel.VersionInfo.ProductVersion -like '10.0.20348*'
    }
    finally {
        if ($mountedVhd) {
            Dismount-VHD -Path $VhdPath -ErrorAction SilentlyContinue
        }
    }
}

function New-Lab03BaseImage {
    [CmdletBinding()]
    param(
        [uri]$VhdUri = 'https://go.microsoft.com/fwlink/p/?linkid=2195166&clcid=0x409&culture=en-us&country=us',
        [string]$VhdPath = 'C:\Base\BaseImage.vhd'
    )

    $ErrorActionPreference = 'Stop'

    if (Test-Path -LiteralPath $VhdPath) {
        if (Test-Lab03BaseImage -VhdPath $VhdPath) {
            Write-Output "Bootable parent image already exists at $VhdPath."
            return
        }

        throw "An existing but nonbootable file was found at $VhdPath. Restore a clean baseline or remove that file before retrying."
    }

    New-Item -Path (Split-Path -Parent $VhdPath) -ItemType Directory -Force | Out-Null

    if ($VhdUri.Scheme -ne 'https') {
        throw 'The Windows Server parent VHD URI must use HTTPS.'
    }

    $downloadPath = "$VhdPath.download"
    if (Test-Path -LiteralPath $downloadPath) {
        throw "An incomplete download exists at $downloadPath. Remove it before retrying."
    }

    Write-Output 'Downloading the Windows Server 2022 Datacenter Evaluation VHD. This is approximately 9.5 GiB.'
    Start-BitsTransfer -Source $VhdUri.AbsoluteUri -Destination $downloadPath -Priority Foreground
    if ((Get-Item -LiteralPath $downloadPath).Length -lt 9GB) {
        throw 'The downloaded VHD is smaller than expected.'
    }

    Move-Item -LiteralPath $downloadPath -Destination $VhdPath
    if (-not (Test-Lab03BaseImage -VhdPath $VhdPath)) {
        throw 'The downloaded parent disk is not an MBR-based Windows Server 2022 image.'
    }

    Write-Output "Bootable Windows Server 2022 parent image downloaded to $VhdPath."
}