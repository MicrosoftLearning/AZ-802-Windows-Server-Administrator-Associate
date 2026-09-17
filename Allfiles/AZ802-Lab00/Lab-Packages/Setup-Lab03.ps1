<#
.SYNOPSIS
    Lab 03: Implementing and configuring virtualization in Windows Server
    Restores baseline, configures SEA-DC1 + SEA-ADM1 + SEA-SVR1.
#>
[CmdletBinding()]
param(
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$BaseImageVhdPath
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\LabPackage-Helpers.ps1"

if ($BaseImageVhdPath) {
    $BaseImageVhdPath = (Resolve-Path -LiteralPath $BaseImageVhdPath).Path
    if ((Get-Item -LiteralPath $BaseImageVhdPath).Length -lt 9GB) {
        throw 'The supplied parent VHD is smaller than the Windows Server 2022 Evaluation VHD.'
    }
}

$LabVMs = @('SEA-DC1', 'SEA-ADM1', 'SEA-SVR1')
Restore-LabBaseline -VMsToStart $LabVMs

Write-Step "Configuring for Lab 03"

# Enable nested virtualization on SEA-SVR1 from the host (must be done while VM is off)
Write-Info "Enabling nested virtualization on SEA-SVR1..."
Stop-VM -Name 'SEA-SVR1' -Force -ErrorAction SilentlyContinue
Set-VMProcessor -VMName 'SEA-SVR1' -ExposeVirtualizationExtensions $true
Start-VM -Name 'SEA-SVR1'

# Wait for SEA-SVR1 to come back
$cred = Get-LabCredential
$svr1Ready = $false
for ($i = 0; $i -lt 60; $i++) {
    try {
        Invoke-Command -VMName 'SEA-SVR1' -Credential $cred -ScriptBlock { $true } -ErrorAction Stop | Out-Null
        $svr1Ready = $true
        break
    }
    catch { Start-Sleep -Seconds 5 }
}
if (-not $svr1Ready) { throw 'Timed out waiting for SEA-SVR1 after enabling nested virtualization.' }
Write-Ok "SEA-SVR1: Nested virtualization enabled"

# SEA-SVR1: Install Hyper-V
Invoke-LabCommand -VMName 'SEA-SVR1' -ScriptBlock {
    Install-WindowsFeature -Name Hyper-V -IncludeManagementTools -Restart:$false | Out-Null
    if (-not (Get-WindowsFeature -Name Hyper-V).Installed) {
        throw 'The Hyper-V role failed to install.'
    }
    Enable-PSRemoting -Force -SkipNetworkProfileCheck

    New-Item -Path 'C:\Base' -ItemType Directory -Force | Out-Null
    $systemVolume = Get-Volume -DriveLetter C
    if ($systemVolume.SizeRemaining -lt 20GB) {
        throw 'SEA-SVR1 requires at least 20 GB of free space on C: for the Lab 3 parent and differencing disks.'
    }
    foreach ($endpoint in @('raw.githubusercontent.com', 'mcr.microsoft.com')) {
        if (-not (Test-NetConnection -ComputerName $endpoint -Port 443 -InformationLevel Quiet)) {
            throw "SEA-SVR1 cannot connect to $endpoint over HTTPS."
        }
    }
}
Write-Ok "SEA-SVR1: Hyper-V installed"

# Restart SEA-SVR1 so Hyper-V is fully functional
Write-Info "Restarting SEA-SVR1 to activate Hyper-V..."
Invoke-LabCommand -VMName 'SEA-SVR1' -ScriptBlock { Restart-Computer -Force }
Start-Sleep -Seconds 30
$svr1Ready = $false
for ($i = 0; $i -lt 60; $i++) {
    try {
        Invoke-Command -VMName 'SEA-SVR1' -Credential $cred -ScriptBlock { $true } -ErrorAction Stop | Out-Null
        $svr1Ready = $true
        break
    }
    catch { Start-Sleep -Seconds 5 }
}
if (-not $svr1Ready) { throw 'Timed out waiting for SEA-SVR1 after installing Hyper-V.' }
Invoke-LabCommand -VMName 'SEA-SVR1' -ScriptBlock {
    if ((Get-Service -Name vmms).Status -ne 'Running') {
        throw 'The Hyper-V Virtual Machine Management service is not running.'
    }
    Get-VMHost | Out-Null
}
Write-Ok "SEA-SVR1: Restarted with Hyper-V active"

# Reuse a host VHD when supplied; otherwise download the Evaluation Center VHD
$builderPath = Join-Path $PSScriptRoot '..\VM-Specs\Deploy\scripts\New-Lab03BaseImage.ps1'
if (-not (Test-Path -LiteralPath $builderPath -PathType Leaf)) {
    throw "Lab 3 image builder not found: $builderPath"
}
if ($BaseImageVhdPath) {
    Write-Info "Copying the supplied Windows Server 2022 parent VHD to SEA-SVR1..."
    Enable-VMIntegrationService -VMName 'SEA-SVR1' -Name 'Guest Service Interface'
    Copy-VMFile -VMName 'SEA-SVR1' `
        -SourcePath $BaseImageVhdPath `
        -DestinationPath 'C:\Base\BaseImage.vhd' `
        -FileSource Host `
        -CreateFullPath `
        -Force
}
$builderContent = Get-Content -LiteralPath $builderPath -Raw
$buildScriptBlock = [scriptblock]::Create("$builderContent`nNew-Lab03BaseImage")
Invoke-LabCommand -VMName 'SEA-SVR1' -ScriptBlock $buildScriptBlock
Write-Ok "SEA-SVR1: Bootable parent image created at C:\Base\BaseImage.vhd"

# SEA-ADM1: Install Hyper-V management tools
Invoke-LabCommand -VMName 'SEA-ADM1' -ScriptBlock {
    $rsatFeatures = @('RSAT-Hyper-V-Tools', 'RSAT-AD-Tools')
    Install-WindowsFeature -Name $rsatFeatures -IncludeAllSubFeature | Out-Null
    if (Get-WindowsFeature -Name $rsatFeatures | Where-Object { -not $_.Installed }) {
        throw 'One or more required RSAT features failed to install.'
    }
    if (-not (Test-Path 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe')) {
        throw 'Microsoft Edge is required but was not found.'
    }
    if (-not (Get-Service -Name BITS -ErrorAction SilentlyContinue)) {
        throw 'Background Intelligent Transfer Service (BITS) is required but was not found.'
    }
    if (-not (Test-NetConnection -ComputerName 'aka.ms' -Port 443 -InformationLevel Quiet)) {
        throw 'SEA-ADM1 cannot connect to the Windows Admin Center download endpoint over HTTPS.'
    }
    Set-Item WSMan:\localhost\client\trustedhosts -Value '*.contoso.com' -Force
}
Write-Ok "SEA-ADM1: Hyper-V RSAT, Edge, BITS, and WAC download access verified"

Write-Step "Lab 03 is ready"
Write-Host "  Connect to SEA-ADM1 and begin the lab." -ForegroundColor White
Write-Host "  NOTE: Docker CE is downloaded during the lab (requires internet on SEA-SVR1)." -ForegroundColor Yellow
Write-Host "  VMs running: $($LabVMs -join ', ')" -ForegroundColor White
