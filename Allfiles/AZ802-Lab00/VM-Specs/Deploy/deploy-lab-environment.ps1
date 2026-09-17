<#
.SYNOPSIS
    Deploys the AZ-802 lab environment to Azure and configures it for a specific lab.

.DESCRIPTION
    1. Creates a resource group and deploys the ARM template (VNet, NSG, 5 VMs)
    2. Promotes SEA-DC1 to domain controller for contoso.com
    3. Updates VNet DNS to point to SEA-DC1
    4. Domain-joins all member servers
    5. Runs lab-specific configuration

.PARAMETER LabNumber
    Which lab to configure (1-8). Determines which roles, files, and AD objects are set up.

.PARAMETER ResourceGroupName
    Azure resource group name. Default: AZ802-L<NN>-ENV (NN is the two-digit LabNumber)

.PARAMETER Location
    Azure region. Default: eastus

.PARAMETER AdminUsername
    Local admin username used to provision the Azure VMs. Default: labadmin

.PARAMETER AdminPassword
    Local admin password for all VMs (SecureString). Default: PA55w.rd1234

.PARAMETER VmSize
    Azure VM size. Must support nested virtualization. Default: Standard_D4s_v5

.PARAMETER SkipInfrastructure
    Skip ARM template deployment (use if VMs already exist).

.PARAMETER SkipDomainConfig
    Skip DC promotion and domain join (use if domain is already configured).

.EXAMPLE
    .\deploy-lab-environment.ps1 -LabNumber 1
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateRange(1, 8)]
    [int]$LabNumber,

    [string]$ResourceGroupName = "AZ802-L$('{0:D2}' -f $LabNumber)-ENV",
    [string]$Location = 'eastus',
    [string]$AdminUsername = 'labadmin',

    [SecureString]$AdminPassword = (ConvertTo-SecureString 'PA55w.rd1234' -AsPlainText -Force),

    [string]$VmSize = 'Standard_D4s_v5',
    [string]$Lab04HostVmSize = 'Standard_D8s_v5',
    [string]$AllowedRdpSourceIP = '*',
    [uri]$Lab04VhdUri = 'https://go.microsoft.com/fwlink/p/?linkid=2195166&clcid=0x409&culture=en-us&country=us',
    [ValidateSet(
        'PrepareHost', 'CreateDomainController', 'PromoteDomainController',
        'CreateServer', 'JoinServer', 'CreateAdmin', 'JoinAdmin', 'ConfigureLab', 'Validate'
    )]
    [string]$Lab04StartPhase = 'PrepareHost',
    [switch]$SkipInfrastructure,
    [switch]$SkipDomainConfig
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# VM names and which labs need them
$AllVMs = @('SEA-DC1', 'SEA-ADM1', 'SEA-SVR1', 'SEA-SVR2', 'SEA-SVR3')

$LabVMs = @{
    1 = @('SEA-DC1', 'SEA-ADM1', 'SEA-SVR1')
    2 = @('SEA-DC1', 'SEA-ADM1')
    3 = @('SEA-DC1', 'SEA-ADM1', 'SEA-SVR1')
    4 = @('SEA-DC1', 'SEA-ADM1', 'SEA-SVR1')
    5 = @('SEA-DC1', 'SEA-ADM1', 'SEA-SVR1', 'SEA-SVR2')
    6 = @('SEA-DC1', 'SEA-ADM1', 'SEA-SVR1', 'SEA-SVR2', 'SEA-SVR3')
    7 = @('SEA-DC1', 'SEA-SVR1', 'SEA-SVR2')
    8 = @('SEA-DC1', 'SEA-SVR2')
}

$PrimaryVMs = @{
    1 = 'SEA-ADM1'
    2 = 'SEA-ADM1'
    3 = 'SEA-ADM1'
    5 = 'SEA-ADM1'
    6 = 'SEA-ADM1'
    7 = 'SEA-SVR2'
    8 = 'SEA-SVR2'
}

$LabConfigVMs = @{
    3 = @('SEA-ADM1', 'SEA-SVR1')
}

$DomainName = 'contoso.com'
$NetBIOSName = 'CONTOSO'
$DomainAdminUsername = 'Administrator'
$SafeModePassword = $AdminPassword
$PlainPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($AdminPassword)
)
$EncodedPassword = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($PlainPassword))

$disallowedAzureUsernames = @(
    'administrator', 'admin', 'user', 'user1', 'test', 'user2', 'test1', 'user3',
    'admin1', '1', '123', 'a', 'actuser', 'adm', 'admin2', 'aspnet', 'backup',
    'console', 'david', 'guest', 'john', 'owner', 'root', 'server', 'sql', 'support',
    'support_388945a0', 'sys', 'test2', 'test3', 'user4', 'user5'
)
if ($AdminUsername.Length -gt 20 -or $AdminUsername.EndsWith('.') -or $AdminUsername.ToLowerInvariant() -in $disallowedAzureUsernames) {
    throw "'$AdminUsername' isn't permitted as an Azure Windows VM administrator username. Use a name such as 'labadmin'."
}

$complexityChecks = @(
    ($PlainPassword -cmatch '[a-z]')
    ($PlainPassword -cmatch '[A-Z]')
    ($PlainPassword -match '\d')
    ($PlainPassword -match '[^a-zA-Z0-9]')
)
$disallowedAzurePasswords = @(
    'abc@123', 'P@$$w0rd', 'P@ssw0rd', 'P@ssword123', 'Pa$$word',
    'pass@word1', 'Password!', 'Password1', 'Password22', 'iloveyou!'
)
if ($PlainPassword.Length -lt 8 -or $PlainPassword.Length -gt 123 -or
    ($complexityChecks | Where-Object { $_ }).Count -lt 3 -or
    $PlainPassword -cin $disallowedAzurePasswords) {
    throw 'The password does not meet Azure Windows VM requirements. Use 8-123 characters and at least three of: lowercase, uppercase, number, and special character.'
}

function Write-Step { param([string]$Message) Write-Host "`n=== $Message ===" -ForegroundColor Cyan }
function Write-Status { param([string]$Message) Write-Host "    $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "    WARNING: $Message" -ForegroundColor Yellow }

# ─── Verify Az module ───
Write-Step "Checking prerequisites"
if (-not (Get-Module -ListAvailable -Name Az.Compute)) {
    throw "Az PowerShell module not found. Run: Install-Module Az"
}

$context = Get-AzContext
if (-not $context) {
    Write-Status "Not logged in to Azure. Running Connect-AzAccount..."
    Connect-AzAccount
}
Write-Status "Subscription: $((Get-AzContext).Subscription.Name)"

if ($LabNumber -eq 4) {
    Write-Step 'Using the nested Hyper-V topology required by Lab 4'
    $lab04DeploymentScript = Join-Path $ScriptDir 'deploy-lab04-nested-environment.ps1'
    if (-not (Test-Path -LiteralPath $lab04DeploymentScript -PathType Leaf)) {
        throw "The Lab 4 deployment script was not found at $lab04DeploymentScript."
    }

    $lab04Parameters = @{
        ResourceGroupName = $ResourceGroupName
        Location = $Location
        AdminUsername = $AdminUsername
        AdminPassword = $AdminPassword
        HostVmSize = $Lab04HostVmSize
        AllowedRdpSourceIP = $AllowedRdpSourceIP
        VhdUri = $Lab04VhdUri
        StartPhase = $Lab04StartPhase
        SkipInfrastructure = $SkipInfrastructure.IsPresent
        SkipGuestConfiguration = $SkipDomainConfig.IsPresent
    }
    & $lab04DeploymentScript @lab04Parameters
    return
}

# ─── Step 1: Deploy ARM template ───
$requiredVMs = @($LabVMs[$LabNumber])
$existingVMNames = @()
if (-not $SkipInfrastructure -and (Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue)) {
    $existingVMNames = @(Get-AzVM -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
    if (@($requiredVMs | Where-Object { $_ -notin $existingVMNames }).Count -eq 0) {
        $SkipInfrastructure = $true
        Write-Status "Existing Lab $LabNumber VMs detected. Skipping ARM infrastructure deployment."
    }
}

if (-not $SkipInfrastructure) {
    Write-Step "Step 1: Deploying infrastructure (ARM template)"

    $rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
    if (-not $rg) {
        Write-Status "Creating resource group '$ResourceGroupName' in '$Location'"
        New-AzResourceGroup -Name $ResourceGroupName -Location $Location | Out-Null
    }

    $templateFile = Join-Path $ScriptDir 'azuredeploy.json'
    $deployParams = @{
        ResourceGroupName = $ResourceGroupName
        TemplateFile      = $templateFile
        adminUsername      = $AdminUsername
        adminPassword      = $AdminPassword
        vmSize             = $VmSize
        location           = $Location
        labNumber          = $LabNumber
        allowedRdpSourceIP = $AllowedRdpSourceIP
    }

    Write-Status "Deploying ARM template (this takes 10-15 minutes)..."
    $deployment = New-AzResourceGroupDeployment @deployParams -Name "AZ802-Deploy-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

    Write-Status "ARM deployment completed. Public IPs:"
    Write-Host "    SEA-DC1:  $($deployment.Outputs.seaDc1PublicIP.Value)"
    Write-Host "    SEA-ADM1: $($deployment.Outputs.seaAdm1PublicIP.Value)"
    Write-Host "    SEA-SVR1: $($deployment.Outputs.seaSvr1PublicIP.Value)"
    Write-Host "    SEA-SVR2: $($deployment.Outputs.seaSvr2PublicIP.Value)"
    Write-Host "    SEA-SVR3: $($deployment.Outputs.seaSvr3PublicIP.Value)"
}

# ─── Step 2: Configure Domain Controller ───
if (-not $SkipDomainConfig) {
    Write-Step "Step 2: Promoting SEA-DC1 to domain controller"
    Write-Status "Installing AD DS role and promoting to DC for $DomainName..."

    $dcScript = @"
`$ErrorActionPreference = 'Stop'
`$computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
if (`$computerSystem.DomainRole -ge 4 -and `$computerSystem.Domain -eq '$DomainName') {
    Write-Output 'SEA-DC1 is already a domain controller for $DomainName.'
    exit 0
}
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
Import-Module ADDSDeployment
`$plainPassword = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$EncodedPassword'))
`$secPassword = ConvertTo-SecureString `$plainPassword -AsPlainText -Force
Install-ADDSForest ``
    -DomainName '$DomainName' ``
    -DomainNetbiosName '$NetBIOSName' ``
    -SafeModeAdministratorPassword `$secPassword ``
    -InstallDns:`$true ``
    -Force:`$true ``
    -NoRebootOnCompletion:`$true
"@

    Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName 'SEA-DC1' `
        -CommandId 'RunPowerShellScript' -ScriptString $dcScript | Out-Null

    Write-Status "DC promotion completed. Restarting SEA-DC1..."
    Restart-AzVM -ResourceGroupName $ResourceGroupName -Name 'SEA-DC1' | Out-Null
    Start-Sleep -Seconds 60

    # Wait for DC to come back online
    $maxAttempts = 30
    $attempt = 0
    do {
        $attempt++
        Start-Sleep -Seconds 30
        $vmStatus = (Get-AzVM -ResourceGroupName $ResourceGroupName -Name 'SEA-DC1' -Status).Statuses |
            Where-Object { $_.Code -like 'PowerState/*' }
        Write-Status "Attempt $attempt/$maxAttempts - VM power state: $($vmStatus.DisplayStatus)"
    } while ($vmStatus.DisplayStatus -ne 'VM running' -and $attempt -lt $maxAttempts)

    # Verify AD DS is responding
    Write-Status "Verifying AD DS is operational..."
    Start-Sleep -Seconds 60
    $verifyScript = 'Get-ADDomain | Select-Object -ExpandProperty DNSRoot'
    $result = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName 'SEA-DC1' `
        -CommandId 'RunPowerShellScript' -ScriptString $verifyScript
    Write-Status "Domain verified: $($result.Value[0].Message)"

    Write-Status "Setting the CONTOSO\$DomainAdminUsername password..."
    $setDomainPasswordScript = @"
`$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory
`$plainPassword = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$EncodedPassword'))
`$securePassword = ConvertTo-SecureString `$plainPassword -AsPlainText -Force
`$domainAdmin = Get-ADUser -Filter "SamAccountName -eq '$DomainAdminUsername'"
if (`$domainAdmin) {
    Set-ADAccountPassword -Identity `$domainAdmin -Reset -NewPassword `$securePassword
    Enable-ADAccount -Identity `$domainAdmin
}
else {
    New-ADUser -Name '$DomainAdminUsername' ``
        -SamAccountName '$DomainAdminUsername' ``
        -AccountPassword `$securePassword ``
        -Enabled `$true ``
        -PasswordNeverExpires `$true
    Add-ADGroupMember -Identity 'Domain Admins' -Members '$DomainAdminUsername'
}
"@
    Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName 'SEA-DC1' `
        -CommandId 'RunPowerShellScript' -ScriptString $setDomainPasswordScript | Out-Null

    # ─── Step 3: Update VNet DNS ───
    Write-Step "Step 3: Updating VNet DNS to point to SEA-DC1"
    $vnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name 'AZ802-VNet'
    $vnet.DhcpOptions.DnsServers = @('172.16.10.10')
    Set-AzVirtualNetwork -VirtualNetwork $vnet | Out-Null
    Write-Status "VNet DNS updated to 172.16.10.10 (SEA-DC1)"

    # ─── Step 4: Domain-join member servers ───
    Write-Step "Step 4: Domain-joining member servers"

    # Only the member VMs actually deployed for this lab
    $memberVMsForLab = $LabVMs[$LabNumber] | Where-Object { $_ -ne 'SEA-DC1' }

    # Restart deployed member VMs to pick up new DNS
    foreach ($vm in $memberVMsForLab) {
        Write-Status "Restarting $vm to pick up DNS change..."
        Restart-AzVM -ResourceGroupName $ResourceGroupName -Name $vm | Out-Null
    }
    Start-Sleep -Seconds 60

    $configureDnsScript = @"
`$ErrorActionPreference = 'Stop'
`$interface = Get-NetIPConfiguration |
    Where-Object { `$_.IPv4DefaultGateway -and `$_.NetAdapter.Status -eq 'Up' } |
    Select-Object -First 1
if (-not `$interface) { throw 'An active IPv4 interface with a default gateway was not found.' }
Set-DnsClientServerAddress -InterfaceIndex `$interface.InterfaceIndex -ServerAddresses '172.16.10.10'
Clear-DnsClientCache
"@
    foreach ($vm in $memberVMsForLab) {
        Write-Status "Configuring $vm to use SEA-DC1 for DNS..."
        Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName $vm `
            -CommandId 'RunPowerShellScript' -ScriptString $configureDnsScript | Out-Null
    }

    $joinScript = @"
`$ErrorActionPreference = 'Stop'
`$computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
if (`$computerSystem.PartOfDomain -and `$computerSystem.Domain -eq '$DomainName') {
    Write-Output "`$env:COMPUTERNAME is already joined to $DomainName."
    exit 0
}
if (`$computerSystem.PartOfDomain) {
    throw "`$env:COMPUTERNAME is already joined to `$(`$computerSystem.Domain), not $DomainName."
}
`$plainPassword = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$EncodedPassword'))
`$password = ConvertTo-SecureString `$plainPassword -AsPlainText -Force
`$credential = New-Object System.Management.Automation.PSCredential('$NetBIOSName\$DomainAdminUsername', `$password)
Add-Computer -DomainName '$DomainName' -Credential `$credential -Force
"@

    foreach ($vm in $memberVMsForLab) {
        Write-Status "Joining $vm to $DomainName..."
        Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName $vm `
            -CommandId 'RunPowerShellScript' -ScriptString $joinScript | Out-Null
    }

    Write-Status "Restarting domain-joined member servers..."
    foreach ($vm in $memberVMsForLab) {
        Restart-AzVM -ResourceGroupName $ResourceGroupName -Name $vm | Out-Null
    }
    Start-Sleep -Seconds 60

    foreach ($vm in $memberVMsForLab) {
        $verifyJoinScript = @"
`$computerSystem = Get-CimInstance Win32_ComputerSystem
if (-not `$computerSystem.PartOfDomain -or `$computerSystem.Domain -ne '$DomainName') {
    throw "Computer is not joined to $DomainName. Current domain: `$(`$computerSystem.Domain)"
}
`$domainController = & nltest.exe /dsgetdc:$DomainName 2>&1
if (`$LASTEXITCODE -ne 0) {
    throw "Computer cannot discover the $DomainName domain controller. `$domainController"
}
"@
        Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName $vm `
            -CommandId 'RunPowerShellScript' -ScriptString $verifyJoinScript | Out-Null
        Write-Status "$vm joined to $DomainName"
    }
}

# ─── Step 5: Configure Server Manager server pool ───
if ('SEA-ADM1' -in $LabVMs[$LabNumber]) {
    Write-Step "Configuring Server Manager server pool"
    $serverManagerVMs = @($LabVMs[$LabNumber] | Where-Object { $_ -ne 'SEA-ADM1' })
    $serverManagerProfileScript = @"
`$ErrorActionPreference = 'Stop'
`$profile = Get-CimInstance Win32_UserProfile |
    Where-Object { `$_.LocalPath -like '`$env:SystemDrive\Users\Administrator*' -and -not `$_.Special } |
    Sort-Object LocalPath -Descending |
    Select-Object -First 1
if (-not `$profile) { throw 'The domain Administrator user profile was not found.' }
`$directory = Join-Path `$profile.LocalPath 'AppData\Roaming\Microsoft\Windows\ServerManager'
New-Item -Path `$directory -ItemType Directory -Force | Out-Null
`$path = Join-Path `$directory 'ServerList.xml'
`$xml = New-Object System.Xml.XmlDocument
`$xml.AppendChild(`$xml.CreateXmlDeclaration('1.0', 'utf-8', `$null)) | Out-Null
`$root = `$xml.CreateElement('ServerList')
`$root.SetAttribute('xmlns:xsd', 'http://www.w3.org/2001/XMLSchema')
`$root.SetAttribute('xmlns:xsi', 'http://www.w3.org/2001/XMLSchema-instance')
`$root.SetAttribute('localhostName', 'SEA-ADM1.contoso.com')
`$root.SetAttribute('xmlns', 'urn:serverpool-schema')
`$xml.AppendChild(`$root) | Out-Null
foreach (`$serverName in @('$($serverManagerVMs -join "','")')) {
    `$server = `$xml.CreateElement('ServerInfo')
    `$server.SetAttribute('name', "`$serverName.$DomainName")
    `$server.SetAttribute('status', '2')
    `$server.SetAttribute('lastUpdateTime', '0001-01-01T00:00:00')
    `$server.SetAttribute('locale', 'en-US')
    `$server.SetAttribute('xmlns', 'urn:serverpool-schema')
    `$root.AppendChild(`$server) | Out-Null
}
`$localServer = `$xml.CreateElement('ServerInfo')
`$localServer.SetAttribute('name', 'SEA-ADM1.contoso.com')
`$localServer.SetAttribute('status', '1')
`$localServer.SetAttribute('lastUpdateTime', (Get-Date).ToString('o'))
`$localServer.SetAttribute('locale', 'en-US')
`$localServer.SetAttribute('xmlns', 'urn:serverpool-schema')
`$root.AppendChild(`$localServer) | Out-Null
`$xml.Save(`$path)
Write-Output "Server Manager server pool configured: `$path"
"@
    Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName 'SEA-ADM1' `
        -CommandId 'RunPowerShellScript' -ScriptString $serverManagerProfileScript | Out-Null
    Write-Status "Server Manager server pool configured for $($serverManagerVMs -join ', ')"
}

# ─── Step 6: Lab-specific configuration ───
Write-Step "Step 6: Configuring environment for Lab $LabNumber"

if ($LabNumber -eq 5) {
    Write-Status 'Staging canonical Lab 5 files on SEA-ADM1...'
    $lab05SourceDirectory = [IO.Path]::GetFullPath((Join-Path $ScriptDir '..\..\..\AZ802-Lab05'))
    $lab05FileNames = @('DeployDFS.ps1', 'Install-FileSyncServerCore.ps1', 'File1.txt')
    $remoteCommands = [Collections.Generic.List[string]]::new()
    $remoteCommands.Add("`$ErrorActionPreference = 'Stop'")
    $remoteCommands.Add("New-Item -Path 'C:\Labfiles\Lab05' -ItemType Directory -Force | Out-Null")

    foreach ($fileName in $lab05FileNames) {
        $sourcePath = Join-Path $lab05SourceDirectory $fileName
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            throw "Canonical Lab 5 file not found: $sourcePath"
        }

        $encodedContent = [Convert]::ToBase64String([IO.File]::ReadAllBytes($sourcePath))
        $expectedHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
        $destinationPath = "C:\Labfiles\Lab05\$fileName"
        $remoteCommands.Add("[IO.File]::WriteAllBytes('$destinationPath', [Convert]::FromBase64String('$encodedContent'))")
        $remoteCommands.Add("if ((Get-FileHash -LiteralPath '$destinationPath' -Algorithm SHA256).Hash -ne '$expectedHash') { throw 'Hash verification failed for $destinationPath.' }")
    }

    Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName 'SEA-ADM1' `
        -CommandId 'RunPowerShellScript' -ScriptString ($remoteCommands -join [Environment]::NewLine) | Out-Null
    Write-Status 'Canonical Lab 5 files staged and verified on SEA-ADM1'
}

if ($LabNumber -eq 6) {
    Write-Status 'Staging canonical Lab 6 files on SEA-ADM1...'
    $lab06SourceDirectory = [IO.Path]::GetFullPath((Join-Path $ScriptDir '..\..\..\AZ802-Lab06'))
    $lab06FileName = 'Implement-StorageSpacesDirect.ps1'
    $lab06SourcePath = Join-Path $lab06SourceDirectory $lab06FileName
    if (-not (Test-Path -LiteralPath $lab06SourcePath -PathType Leaf)) {
        throw "Canonical Lab 6 file not found: $lab06SourcePath"
    }

    $lab06Content = Get-Content -LiteralPath $lab06SourcePath -Raw
    $lab06Content = $lab06Content.Replace('-StaticAddress 172.16.0.40', '-StaticAddress 172.16.10.40')
    $lab06Bytes = [Text.Encoding]::UTF8.GetBytes($lab06Content)
    $encodedContent = [Convert]::ToBase64String($lab06Bytes)
    $expectedHash = [BitConverter]::ToString(
        [Security.Cryptography.SHA256]::Create().ComputeHash($lab06Bytes)
    ).Replace('-', '')
    $lab06RemoteScript = @"
`$destinationPath = 'C:\Labfiles\Lab06\$lab06FileName'
[IO.File]::WriteAllBytes(`$destinationPath, [Convert]::FromBase64String('$encodedContent'))
if ((Get-FileHash -LiteralPath `$destinationPath -Algorithm SHA256).Hash -ne '$expectedHash') {
    throw 'Hash verification failed for `$destinationPath.'
}
"@
    Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName 'SEA-ADM1' `
        -CommandId 'RunPowerShellScript' -ScriptString $lab06RemoteScript | Out-Null
    Write-Status 'Lab 6 files adapted to the Azure subnet, staged, and verified on SEA-ADM1'
}

if ($LabNumber -eq 7) {
    Write-Status 'Staging canonical Lab 7 files on SEA-SVR2...'
    $lab07Files = @(
        @{
            Name = 'DG_Readiness_Tool.ps1'
            Hash = 'E343AA348B546F46A8875ED44C35EFBD96A4C754CD412440781E6E67C7A2DAD0'
        },
        @{
            Name = 'LAPS.x64.msi'
            Hash = '0001DD763CC74D37E3979E016FFCD0512D91494A0B3B7270C7A3BB4E1915F6D1'
        }
    )
    $lab07RemoteCommands = [Collections.Generic.List[string]]::new()
    $lab07RemoteCommands.Add("`$ErrorActionPreference = 'Stop'")
    $lab07RemoteCommands.Add("New-Item -Path 'C:\Labfiles\Lab07' -ItemType Directory -Force | Out-Null")
    foreach ($file in $lab07Files) {
        $url = "https://raw.githubusercontent.com/MicrosoftLearning/AZ-802-Windows-Server-Administrator-Associate/main/Allfiles/AZ802-Lab07/$($file.Name)"
        $path = "C:\Labfiles\Lab07\$($file.Name)"
        $lab07RemoteCommands.Add("Invoke-WebRequest -Uri '$url' -OutFile '$path' -UseBasicParsing")
        $lab07RemoteCommands.Add("if ((Get-FileHash -LiteralPath '$path' -Algorithm SHA256).Hash -ne '$($file.Hash)') { throw 'Hash verification failed for $path.' }")
    }
    $lab07StageResult = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName 'SEA-SVR2' `
        -CommandId 'RunPowerShellScript' -ScriptString ($lab07RemoteCommands -join [Environment]::NewLine)
    $lab07StageError = $lab07StageResult.Value |
        Where-Object { $_.Code -like '*StdErr*' -and $_.Message }
    if ($lab07StageError) {
        throw "Lab 7 file staging failed on SEA-SVR2. $($lab07StageError.Message)"
    }
    Write-Status 'Canonical Lab 7 files staged and verified on SEA-SVR2'
}

$labScript = Join-Path $ScriptDir ("scripts\Configure-Lab{0:D2}.ps1" -f $LabNumber)
if (Test-Path $labScript) {
    $labContent = Get-Content $labScript -Raw

    # Determine which VMs need lab config
    $vmsForLab = if ($LabConfigVMs.ContainsKey($LabNumber)) {
        $LabConfigVMs[$LabNumber]
    }
    else {
        $LabVMs[$LabNumber]
    }
    foreach ($vm in $vmsForLab) {
        Write-Status "Running lab config on $vm..."
        try {
            $result = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName $vm `
                -CommandId 'RunPowerShellScript' -ScriptString $labContent
            $remoteError = $result.Value |
                Where-Object { $_.Code -like '*StdErr*' -and $_.Message }
            if ($remoteError) {
                throw $remoteError.Message
            }
            if ($result.Value[0].Message) {
                Write-Host $result.Value[0].Message
            }
        }
        catch {
            throw "Lab $LabNumber configuration failed on $vm. $_"
        }
    }
}
else {
    Write-Warn "Lab config script not found: $labScript"
}

if ($LabNumber -eq 3) {
    Write-Step "Restarting SEA-SVR1 to activate Hyper-V"
    Restart-AzVM -ResourceGroupName $ResourceGroupName -Name 'SEA-SVR1' | Out-Null
    Start-Sleep -Seconds 60

    $verifyHyperVScript = @'
$ErrorActionPreference = 'Stop'
if (-not (Get-WindowsFeature -Name Hyper-V).Installed) {
    throw 'The Hyper-V role is not installed.'
}
if ((Get-Service -Name vmms).Status -ne 'Running') {
    throw 'The Hyper-V Virtual Machine Management service is not running.'
}
Get-VMHost | Out-Null
'@
    Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName 'SEA-SVR1' `
        -CommandId 'RunPowerShellScript' -ScriptString $verifyHyperVScript | Out-Null
    Write-Status "SEA-SVR1 restarted with Hyper-V operational"

    Write-Step "Creating the Lab 3 Windows Server parent image"
    $builderPath = Join-Path $ScriptDir 'scripts\New-Lab03BaseImage.ps1'
    if (-not (Test-Path -LiteralPath $builderPath -PathType Leaf)) {
        throw "Lab 3 image builder not found: $builderPath"
    }

    $builderContent = Get-Content -LiteralPath $builderPath -Raw
    $buildImageScript = @"
$builderContent
New-Lab03BaseImage
"@
    $buildResult = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName 'SEA-SVR1' `
        -CommandId 'RunPowerShellScript' -ScriptString $buildImageScript
    if ($buildResult.Value[0].Message) {
        Write-Host $buildResult.Value[0].Message
    }
    Write-Status "Bootable parent image created at C:\Base\BaseImage.vhd"
}

# ─── Summary ───
Write-Step "Deployment complete"
Write-Status "Lab $LabNumber environment is ready."
Write-Status "VMs deployed for this lab: $($LabVMs[$LabNumber] -join ', ')"
Write-Host ""
Write-Host "RDP addresses:" -ForegroundColor White
$rdpAddresses = @{}
foreach ($vm in $LabVMs[$LabNumber]) {
    $publicIP = (Get-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Name "$vm-pip" -ErrorAction Stop).IpAddress
    $rdpAddresses[$vm] = $publicIP
    Write-Host "    $vm`: $publicIP" -ForegroundColor White
}
Write-Host ""
Write-Host "Primary RDP target: $($PrimaryVMs[$LabNumber]) ($($rdpAddresses[$PrimaryVMs[$LabNumber]]))" -ForegroundColor White
Write-Host "Domain: $DomainName | Username: $NetBIOSName\$DomainAdminUsername" -ForegroundColor White
Write-Host "Lab files: C:\Labfiles\Lab$('{0:D2}' -f $LabNumber) on $($PrimaryVMs[$LabNumber])" -ForegroundColor White
Write-Host ""
Write-Warn "Remember to deallocate VMs when not in use to save costs."
Write-Warn "To delete everything: Remove-AzResourceGroup -Name $ResourceGroupName -Force"
