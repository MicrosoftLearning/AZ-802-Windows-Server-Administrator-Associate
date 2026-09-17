<#
.SYNOPSIS
    One-time setup: configures the AZ-802 domain environment and creates a "Baseline" checkpoint.

.DESCRIPTION
    Assumes all 5 VMs exist with Windows Server 2022 installed and hostnames already set.
    Configures static IPs, promotes SEA-DC1 to DC, domain-joins members, installs common
    tools, then creates a "Baseline" checkpoint on all VMs.

    Run this ONCE. After that, use Setup-Lab##.ps1 for each lab.

.PARAMETER AdminPassword
    Password for the local Administrator account on all VMs. Default: PA55w.rd1234

.EXAMPLE
    .\Create-Baseline.ps1
#>
[CmdletBinding()]
param(
    [SecureString]$AdminPassword = (ConvertTo-SecureString 'PA55w.rd1234' -AsPlainText -Force)
)

$ErrorActionPreference = 'Stop'

$AllVMs = @('SEA-DC1', 'SEA-ADM1', 'SEA-SVR1', 'SEA-SVR2', 'SEA-SVR3')
$MemberVMs = @('SEA-ADM1', 'SEA-SVR1', 'SEA-SVR2', 'SEA-SVR3')
$CheckpointName = 'Baseline'
$DomainName = 'contoso.com'
$NetBIOS = 'CONTOSO'

$plainPwd = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($AdminPassword))
$localCred = New-Object PSCredential('Administrator', $AdminPassword)
$domainCred = New-Object PSCredential("$NetBIOS\Administrator", $AdminPassword)

$IPs = @{
    'SEA-DC1'  = '172.16.10.10'
    'SEA-ADM1' = '172.16.10.11'
    'SEA-SVR1' = '172.16.10.12'
    'SEA-SVR2' = '172.16.10.13'
    'SEA-SVR3' = '172.16.10.14'
}

function Write-Step { param([string]$Msg) Write-Host "`n=== $Msg ===" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Msg) Write-Host "    $Msg" -ForegroundColor Green }
function Write-Info { param([string]$Msg) Write-Host "    $Msg" -ForegroundColor Yellow }

# ── Verify VMs exist ──
Write-Step "Verifying VMs exist"
foreach ($vm in $AllVMs) {
    if (-not (Get-VM -Name $vm -ErrorAction SilentlyContinue)) {
        throw "VM '$vm' not found. Create all 5 VMs first (see Manual-Setup guide)."
    }
    Write-Ok "$vm found"
}

# ── Remove old baseline checkpoint if it exists ──
foreach ($vm in $AllVMs) {
    $existing = Get-VMCheckpoint -VMName $vm -Name $CheckpointName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Info "Removing old '$CheckpointName' checkpoint on $vm"
        Remove-VMCheckpoint -VMName $vm -Name $CheckpointName -Confirm:$false
    }
}

# ── Start all VMs ──
Write-Step "Starting all VMs"
foreach ($vm in $AllVMs) {
    if ((Get-VM -Name $vm).State -ne 'Running') {
        Start-VM -Name $vm
        Write-Ok "Started $vm"
    }
}

# Wait for VMs to accept PowerShell Direct
Write-Step "Waiting for VMs to boot (PowerShell Direct)"
foreach ($vm in $AllVMs) {
    $ready = $false
    for ($i = 0; $i -lt 60; $i++) {
        try {
            Invoke-Command -VMName $vm -Credential $localCred -ScriptBlock { $env:COMPUTERNAME } -ErrorAction Stop | Out-Null
            $ready = $true
            break
        } catch { Start-Sleep -Seconds 5 }
    }
    if (-not $ready) { throw "Timed out waiting for $vm to respond to PowerShell Direct." }
    Write-Ok "$vm is responding"
}

# ── Configure static IPs ──
Write-Step "Configuring static IPs"
foreach ($vm in $AllVMs) {
    $ip = $IPs[$vm]
    $dns = '172.16.10.10'
    $gateway = '172.16.10.1'

    Invoke-Command -VMName $vm -Credential $localCred -ScriptBlock {
        param($ip, $dns, $gw)
        $adapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
        # Remove existing IP config
        Remove-NetIPAddress -InterfaceIndex $adapter.ifIndex -Confirm:$false -ErrorAction SilentlyContinue
        Remove-NetRoute -InterfaceIndex $adapter.ifIndex -Confirm:$false -ErrorAction SilentlyContinue
        New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress $ip -PrefixLength 16 -DefaultGateway $gw -ErrorAction SilentlyContinue
        Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $dns
    } -ArgumentList $ip, $dns, $gateway

    Write-Ok "$vm → $ip"
}

# ── Promote SEA-DC1 ──
Write-Step "Promoting SEA-DC1 to domain controller"
Invoke-Command -VMName 'SEA-DC1' -Credential $localCred -ScriptBlock {
    param($domain, $netbios, $pwd)
    $secPwd = ConvertTo-SecureString $pwd -AsPlainText -Force

    # Check if already a DC
    $adFeature = Get-WindowsFeature AD-Domain-Services
    if ($adFeature.Installed) {
        try {
            Import-Module ActiveDirectory
            Get-ADDomain | Out-Null
            Write-Output "Already a domain controller — skipping promotion."
            return
        } catch {}
    }

    Install-WindowsFeature -Name AD-Domain-Services, DNS -IncludeManagementTools
    Import-Module ADDSDeployment
    Install-ADDSForest `
        -DomainName $domain `
        -DomainNetbiosName $netbios `
        -SafeModeAdministratorPassword $secPwd `
        -InstallDns:$true `
        -Force:$true `
        -NoRebootOnCompletion:$false
} -ArgumentList $DomainName, $NetBIOS, $plainPwd

Write-Info "SEA-DC1 will restart. Waiting..."
Start-Sleep -Seconds 30

# Wait for DC to come back
for ($i = 0; $i -lt 60; $i++) {
    try {
        Invoke-Command -VMName 'SEA-DC1' -Credential $domainCred -ScriptBlock {
            Import-Module ActiveDirectory; Get-ADDomain | Out-Null
        } -ErrorAction Stop
        break
    } catch { Start-Sleep -Seconds 10 }
}
Write-Ok "SEA-DC1 is operational as contoso.com DC"

# ── Domain-join member servers ──
Write-Step "Domain-joining member servers"
foreach ($vm in $MemberVMs) {
    Write-Info "Joining $vm..."
    try {
        Invoke-Command -VMName $vm -Credential $localCred -ScriptBlock {
            param($domain, $pwd, $netbios)
            $secPwd = ConvertTo-SecureString $pwd -AsPlainText -Force
            $cred = New-Object PSCredential("$netbios\Administrator", $secPwd)
            Add-Computer -DomainName $domain -Credential $cred -Restart -Force
        } -ArgumentList $DomainName, $plainPwd, $NetBIOS
    } catch {
        Write-Info "$vm may have restarted during join (expected)."
    }
}

Write-Info "Waiting for domain join restarts..."
Start-Sleep -Seconds 60

# Verify domain join
foreach ($vm in $MemberVMs) {
    for ($i = 0; $i -lt 30; $i++) {
        try {
            $result = Invoke-Command -VMName $vm -Credential $domainCred -ScriptBlock {
                (Get-CimInstance Win32_ComputerSystem).Domain
            } -ErrorAction Stop
            if ($result -eq $DomainName) { Write-Ok "$vm joined $DomainName"; break }
        } catch { Start-Sleep -Seconds 10 }
    }
}

# ── Install common tools ──
Write-Step "Installing common tools"

# RSAT on SEA-ADM1
Invoke-Command -VMName 'SEA-ADM1' -Credential $domainCred -ScriptBlock {
    Install-WindowsFeature -Name RSAT-AD-Tools, RSAT-DNS-Server, GPMC -IncludeAllSubFeature
    Set-Item WSMan:\localhost\client\trustedhosts -Value '*.contoso.com' -Force
}
Write-Ok "SEA-ADM1: RSAT tools installed"

# WinRM on all members
foreach ($vm in $MemberVMs) {
    Invoke-Command -VMName $vm -Credential $domainCred -ScriptBlock {
        Enable-PSRemoting -Force -SkipNetworkProfileCheck
    } -ErrorAction SilentlyContinue
}
Write-Ok "WinRM enabled on all member servers"

# ── Create Baseline checkpoint ──
Write-Step "Creating '$CheckpointName' checkpoint"

# Shut down all VMs cleanly for checkpoint
foreach ($vm in $AllVMs) {
    Stop-VM -Name $vm -Force
}
Write-Info "All VMs stopped"

Start-Sleep -Seconds 10

foreach ($vm in $AllVMs) {
    Checkpoint-VM -VMName $vm -SnapshotName $CheckpointName
    Write-Ok "$vm → checkpoint '$CheckpointName' created"
}

Write-Step "Baseline setup complete"
Write-Host ""
Write-Host "  Run any Setup-Lab##.ps1 to configure for a specific lab." -ForegroundColor White
Write-Host "  Each lab script restores this checkpoint first." -ForegroundColor White
Write-Host ""
