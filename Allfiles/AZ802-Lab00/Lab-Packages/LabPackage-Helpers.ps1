# Shared helper functions for Setup-Lab scripts — dot-source from each lab package
$script:AllVMs = @('SEA-DC1', 'SEA-ADM1', 'SEA-SVR1', 'SEA-SVR2', 'SEA-SVR3')
$script:CheckpointName = 'Baseline'
$script:DomainName = 'contoso.com'
$script:NetBIOS = 'CONTOSO'

function Write-Step { param([string]$Msg) Write-Host "`n=== $Msg ===" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Msg) Write-Host "    $Msg" -ForegroundColor Green }
function Write-Info { param([string]$Msg) Write-Host "    $Msg" -ForegroundColor Yellow }

function Restore-LabBaseline {
    <# Stops all VMs, restores the Baseline checkpoint, starts only the VMs in $VMsToStart. #>
    param([string[]]$VMsToStart)

    Write-Step "Restoring Baseline checkpoint"

    foreach ($vm in $script:AllVMs) {
        if ((Get-VM -Name $vm).State -ne 'Off') {
            Stop-VM -Name $vm -TurnOff -Force
        }
    }
    Write-Ok "All VMs stopped"

    foreach ($vm in $script:AllVMs) {
        $cp = Get-VMCheckpoint -VMName $vm -Name $script:CheckpointName -ErrorAction SilentlyContinue
        if (-not $cp) { throw "Checkpoint '$($script:CheckpointName)' not found on $vm. Run Create-Baseline.ps1 first." }
        Restore-VMCheckpoint -VMName $vm -Name $script:CheckpointName -Confirm:$false
        Write-Ok "$vm restored"
    }

    Write-Step "Starting VMs: $($VMsToStart -join ', ')"
    foreach ($vm in $VMsToStart) {
        Start-VM -Name $vm
    }

    # Wait for PowerShell Direct
    $cred = Get-LabCredential
    foreach ($vm in $VMsToStart) {
        Write-Info "Waiting for $vm..."
        for ($i = 0; $i -lt 60; $i++) {
            try {
                Invoke-Command -VMName $vm -Credential $cred -ScriptBlock { $true } -ErrorAction Stop | Out-Null
                Write-Ok "$vm ready"
                break
            } catch { Start-Sleep -Seconds 5 }
        }
    }
}

function Get-LabCredential {
    <# Returns a CONTOSO\Administrator credential. Caches in script scope. #>
    if (-not $script:LabCred) {
        $pwd = ConvertTo-SecureString 'PA55w.rd1234' -AsPlainText -Force
        $script:LabCred = New-Object PSCredential("$($script:NetBIOS)\Administrator", $pwd)
    }
    return $script:LabCred
}

function Invoke-LabCommand {
    <# Runs a script block on a VM via PowerShell Direct. #>
    param(
        [string]$VMName,
        [scriptblock]$ScriptBlock,
        [object[]]$ArgumentList
    )
    $cred = Get-LabCredential
    $params = @{
        VMName      = $VMName
        Credential  = $cred
        ScriptBlock = $ScriptBlock
    }
    if ($ArgumentList) { $params.ArgumentList = $ArgumentList }
    Invoke-Command @params
}
