<#
.SYNOPSIS
    Deploys the Azure-hosted nested Hyper-V environment for AZ-802 Lab 4.

.DESCRIPTION
    Creates one Azure VM that hosts SEA-DC1, SEA-ADM1, and SEA-SVR1 on an
    internal Hyper-V switch. The nested network supports the DHCP broadcasts
    and guest IP changes required by the original Lab 4 instructions.
#>
[CmdletBinding()]
param(
    [string]$ResourceGroupName = 'AZ802-Lab04-RG',
    [string]$Location = 'eastus',
    [string]$AdminUsername = 'labadmin',

    [SecureString]$AdminPassword = (ConvertTo-SecureString 'PA55w.rd1234' -AsPlainText -Force),

    [string]$HostVmSize = 'Standard_D8s_v5',
    [string]$AllowedRdpSourceIP = '*',

    [uri]$VhdUri = 'https://go.microsoft.com/fwlink/p/?linkid=2195166&clcid=0x409&culture=en-us&country=us',

    [switch]$SkipInfrastructure,
    [switch]$SkipGuestConfiguration,

    [ValidateSet(
        'PrepareHost', 'CreateDomainController', 'PromoteDomainController',
        'CreateServer', 'JoinServer', 'CreateAdmin', 'JoinAdmin', 'ConfigureLab', 'Validate'
    )]
    [string]$StartPhase = 'PrepareHost'
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$hostName = 'AZ802-L4-HOST'

function Write-Step {
    param([string]$Message)
    Write-Host "`n=== $Message ===" -ForegroundColor Cyan
}

function Write-Status {
    param([string]$Message)
    Write-Host "    $Message" -ForegroundColor Green
}

function Invoke-LabRunCommand {
    param(
        [Parameter(Mandatory)][string]$ScriptString,
        [hashtable]$Parameter,
        [int]$MaximumAttempts = 12
    )

    $invokeParameters = @{
        ResourceGroupName = $ResourceGroupName
        VMName = $hostName
        CommandId = 'RunPowerShellScript'
        ScriptString = $ScriptString
        ErrorAction = 'Stop'
    }
    if ($Parameter) {
        $invokeParameters.Parameter = $Parameter
    }

    for ($attempt = 1; $attempt -le $MaximumAttempts; $attempt++) {
        try {
            return Invoke-AzVMRunCommand @invokeParameters
        }
        catch {
            $isBusyConflict = $_.Exception.Message -match 'execution is in progress|StatusCode:\s*409'
            if (-not $isBusyConflict -or $attempt -eq $MaximumAttempts) {
                throw
            }
            Write-Status "Azure Run Command is busy; retrying ($attempt/$MaximumAttempts)..."
            Start-Sleep -Seconds 10
        }
    }
}

function Wait-AzureGuestAgent {
    param([int]$MaximumAttempts = 30)

    for ($attempt = 1; $attempt -le $MaximumAttempts; $attempt++) {
        try {
            Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName $hostName `
                -CommandId 'RunPowerShellScript' -ScriptString "Write-Output 'ready'" `
                -ErrorAction Stop | Out-Null
            return
        }
        catch {
            Write-Status "Waiting for the Azure guest agent ($attempt/$MaximumAttempts)..."
            Start-Sleep -Seconds 20
        }
    }
    throw "The Azure guest agent on $hostName did not become ready."
}

function Copy-BuilderToHost {
    param(
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][string]$Destination
    )

    $bytes = [Text.Encoding]::UTF8.GetBytes($Content)
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $expectedHash = [BitConverter]::ToString($sha256.ComputeHash($bytes)).Replace('-', '')
    }
    finally {
        $sha256.Dispose()
    }

    $existingBuilderCheck = @"
if (Test-Path -LiteralPath '$Destination' -PathType Leaf) {
    Write-Output ('LAB04_EXISTING_BUILDER_HASH:' + (Get-FileHash -Algorithm SHA256 -LiteralPath '$Destination').Hash)
}
"@
    $existingBuilder = Invoke-LabRunCommand -ScriptString $existingBuilderCheck
    $existingBuilderOutput = @($existingBuilder.Value |
        Where-Object Code -like '*StdOut*' |
        ForEach-Object Message) -join "`n"
    if ($existingBuilderOutput -match "LAB04_EXISTING_BUILDER_HASH:$expectedHash") {
        Write-Status 'The current nested host builder is already present; skipping upload.'
        return
    }

    $compressedStream = [IO.MemoryStream]::new()
    try {
        $gzipStream = [IO.Compression.GzipStream]::new(
            $compressedStream,
            [IO.Compression.CompressionLevel]::Optimal,
            $true
        )
        try {
            $gzipStream.Write($bytes, 0, $bytes.Length)
        }
        finally {
            $gzipStream.Dispose()
        }
        $uploadBytes = $compressedStream.ToArray()
    }
    finally {
        $compressedStream.Dispose()
    }

    $compressedDestination = "$Destination.gz"
    $initializeUpload = @"
`$directory = Split-Path -Parent '$Destination'
New-Item -Path `$directory -ItemType Directory -Force | Out-Null
[IO.File]::WriteAllBytes('$compressedDestination', [byte[]]::new(0))
"@
    Invoke-LabRunCommand -ScriptString $initializeUpload | Out-Null

    $chunkSize = 2000
    $chunkCount = [Math]::Ceiling($uploadBytes.Length / $chunkSize)
    Write-Status "Uploading compressed builder in $chunkCount chunks..."
    $chunkNumber = 0
    for ($offset = 0; $offset -lt $uploadBytes.Length; $offset += $chunkSize) {
        $chunkNumber++
        $length = [Math]::Min($chunkSize, $uploadBytes.Length - $offset)
        $chunk = [byte[]]::new($length)
        [Array]::Copy($uploadBytes, $offset, $chunk, 0, $length)
        $encodedChunk = [Convert]::ToBase64String($chunk)
        $appendChunk = @"
`$chunk = [Convert]::FromBase64String('$encodedChunk')
`$stream = [IO.File]::Open('$compressedDestination', [IO.FileMode]::Append, [IO.FileAccess]::Write)
try { `$stream.Write(`$chunk, 0, `$chunk.Length) } finally { `$stream.Dispose() }
"@
        Invoke-LabRunCommand -ScriptString $appendChunk | Out-Null
        Write-Status "Uploaded builder chunk $chunkNumber/$chunkCount."
    }

    $verifyUpload = @"
`$temporaryDestination = '$Destination.new'
`$inputStream = [IO.File]::OpenRead('$compressedDestination')
`$gzipStream = [IO.Compression.GzipStream]::new(`$inputStream, [IO.Compression.CompressionMode]::Decompress)
`$outputStream = [IO.File]::Create(`$temporaryDestination)
try { `$gzipStream.CopyTo(`$outputStream) } finally {
    `$outputStream.Dispose()
    `$gzipStream.Dispose()
    `$inputStream.Dispose()
}
Move-Item -LiteralPath `$temporaryDestination -Destination '$Destination' -Force
Remove-Item -LiteralPath '$compressedDestination' -Force
`$tokens = `$null
`$parseErrors = `$null
[System.Management.Automation.Language.Parser]::ParseFile('$Destination', [ref]`$tokens, [ref]`$parseErrors) | Out-Null
if (`$parseErrors.Count -gt 0) {
    throw (`$parseErrors | ForEach-Object { 'Line {0}: {1}' -f `$_.Extent.StartLineNumber, `$_.Message } | Out-String)
}
Write-Output ('LAB04_BUILDER_HASH:' + (Get-FileHash -Algorithm SHA256 -LiteralPath '$Destination').Hash)
Write-Output 'LAB04_BUILDER_PARSE_OK'
"@
    $verification = Invoke-LabRunCommand -ScriptString $verifyUpload
    $verificationOutput = @($verification.Value |
        Where-Object Code -like '*StdOut*' |
        ForEach-Object Message) -join "`n"
    if ($verificationOutput -notmatch "LAB04_BUILDER_HASH:$expectedHash" -or
        $verificationOutput -notmatch 'LAB04_BUILDER_PARSE_OK') {
        throw 'The Lab 4 host builder could not be verified after upload.'
    }
}

Write-Step 'Checking Azure prerequisites'
if (-not (Get-Module -ListAvailable -Name Az.Compute)) {
    throw 'The Az PowerShell module is required. Run Install-Module Az from an elevated PowerShell session.'
}
if (-not (Get-AzContext)) {
    Connect-AzAccount | Out-Null
}
Write-Status "Subscription: $((Get-AzContext).Subscription.Name)"

$supportedHostSizes = @('Standard_D8s_v5', 'Standard_D16s_v5', 'Standard_D32s_v5')
if ($HostVmSize -notin $supportedHostSizes) {
    throw "Unsupported Lab 4 host size '$HostVmSize'. Use one of: $($supportedHostSizes -join ', ')."
}

$plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($AdminPassword)
)
$encodedPassword = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($plainPassword))

if (-not $SkipInfrastructure) {
    Write-Step 'Deploying the Lab 4 Hyper-V host'
    if (-not (Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue)) {
        New-AzResourceGroup -Name $ResourceGroupName -Location $Location | Out-Null
    }

    $templateFile = Join-Path $scriptDir 'azuredeploy-lab04-nested.json'
    $deployment = New-AzResourceGroupDeployment `
        -ResourceGroupName $ResourceGroupName `
        -Name "AZ802-Lab04-$(Get-Date -Format 'yyyyMMdd-HHmmss')" `
        -TemplateFile $templateFile `
        -adminUsername $AdminUsername `
        -adminPassword $AdminPassword `
        -hostVmSize $HostVmSize `
        -allowedRdpSourceIP $AllowedRdpSourceIP `
        -location $Location

    Write-Status "Host public IP: $($deployment.Outputs.hostPublicIP.Value)"
    Write-Status 'Waiting for the new host guest agent...'
    Wait-AzureGuestAgent
}
elseif (-not (Get-AzVM -ResourceGroupName $ResourceGroupName -Name $hostName -ErrorAction SilentlyContinue)) {
    throw "$hostName was not found in resource group $ResourceGroupName."
}

if (-not $SkipGuestConfiguration) {
    Write-Step 'Checking Hyper-V on the Azure host'
    $installHyperV = @'
$ErrorActionPreference = 'Stop'
$feature = Get-WindowsFeature -Name Hyper-V
$restartRequired = $false
if (-not $feature.Installed) {
    Install-WindowsFeature -Name Hyper-V -IncludeManagementTools -Restart:$false | Out-Null
    $restartRequired = $true
}
if (-not (Get-WindowsFeature -Name Hyper-V).Installed) {
    throw 'The Hyper-V role failed to install.'
}
if (-not (Get-Service -Name vmms -ErrorAction SilentlyContinue)) {
    $restartRequired = $true
}
Write-Output "LAB04_HYPERV_RESTART_REQUIRED:$restartRequired"
'@
    $hyperVResult = Invoke-LabRunCommand -ScriptString $installHyperV
    $hyperVOutput = @($hyperVResult.Value |
        Where-Object Code -like '*StdOut*' |
        ForEach-Object Message) -join "`n"
    if ($hyperVOutput -match 'LAB04_HYPERV_RESTART_REQUIRED:True') {
        Write-Status 'Restarting the host to activate Hyper-V...'
        Restart-AzVM -ResourceGroupName $ResourceGroupName -Name $hostName | Out-Null
        Wait-AzureGuestAgent
    }
    elseif ($hyperVOutput -notmatch 'LAB04_HYPERV_RESTART_REQUIRED:False') {
        throw 'The Hyper-V prerequisite check did not return a completion marker.'
    }

    Write-Step 'Creating and configuring the nested Lab 4 guests'
    $builderPath = Join-Path $scriptDir 'scripts\Initialize-Lab04NestedHost.ps1'
    if (-not (Test-Path -LiteralPath $builderPath -PathType Leaf)) {
        throw "The Lab 4 nested host builder was not found at $builderPath."
    }
    $builderContent = Get-Content -LiteralPath $builderPath -Raw
    $remoteBuilderPath = 'C:\Lab04\Initialize-Lab04NestedHost.ps1'
    Write-Status 'Uploading the nested host builder...'
    Copy-BuilderToHost -Content $builderContent -Destination $remoteBuilderPath
    $phaseRunner = @"
param(`$EncodedAdminPassword, `$VhdUri, `$Phase)
& '$remoteBuilderPath' -EncodedAdminPassword `$EncodedAdminPassword -VhdUri `$VhdUri -Phase `$Phase
"@
    $allPhases = @(
        'PrepareHost', 'CreateDomainController', 'PromoteDomainController',
        'CreateServer', 'JoinServer', 'CreateAdmin', 'JoinAdmin', 'ConfigureLab', 'Validate'
    )
    $startPhaseIndex = [Array]::IndexOf($allPhases, $StartPhase)
    $phases = $allPhases[$startPhaseIndex..($allPhases.Count - 1)]
    Write-Status "Running phases: $($phases -join ', ')"
    foreach ($phase in $phases) {
        Write-Status "Running phase: $phase"
        $runParameters = @{
            EncodedAdminPassword = $encodedPassword
            VhdUri = $VhdUri.AbsoluteUri
            Phase = $phase
        }
        $result = Invoke-LabRunCommand -ScriptString $phaseRunner -Parameter $runParameters
        $stdout = @($result.Value |
            Where-Object Code -like '*StdOut*' |
            ForEach-Object Message) -join "`n"
        $stderr = @($result.Value |
            Where-Object Code -like '*StdErr*' |
            ForEach-Object Message) -join "`n"
        if ($stdout) {
            Write-Host $stdout
        }
        if ($stderr) {
            throw "Lab 4 phase '$phase' failed:`n$stderr"
        }
        $completionMarker = "LAB04_PHASE_COMPLETE:$phase"
        if ($stdout -notmatch [regex]::Escape($completionMarker)) {
            throw "Lab 4 phase '$phase' did not return its completion marker. The remote command output was empty or incomplete."
        }
    }
}

$publicIp = (Get-AzPublicIpAddress -ResourceGroupName $ResourceGroupName `
    -Name 'AZ802-Lab04-Host-pip').IpAddress

Write-Step 'Lab 4 deployment complete'
Write-Status "RDP to the Hyper-V host at $publicIp as $AdminUsername."
Write-Status 'From the host, RDP to 172.16.10.11 as CONTOSO\Administrator.'
Write-Host '    Use the lab password supplied during deployment.' -ForegroundColor White
Write-Host '    Delete the resource group when the lab is complete to stop all charges.' -ForegroundColor Yellow