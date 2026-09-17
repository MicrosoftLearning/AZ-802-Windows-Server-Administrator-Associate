# Configure-Lab07.ps1 — Configuring security in Windows Server
# Runs on: SEA-DC1, SEA-SVR1, SEA-SVR2

$ErrorActionPreference = 'Stop'
$hostname = $env:COMPUTERNAME

switch ($hostname) {
    'SEA-DC1' {
        Import-Module ActiveDirectory

        Write-Output "[SEA-DC1] Granting the lab administrator forest administration rights..."
        foreach ($group in 'Enterprise Admins', 'Schema Admins') {
            if (-not (Get-ADGroupMember -Identity $group | Where-Object SamAccountName -eq 'Administrator')) {
                Add-ADGroupMember -Identity $group -Members 'Administrator'
            }
        }

        Write-Output "[SEA-DC1] Creating IT OU..."
        New-ADOrganizationalUnit -Name 'IT' -Path 'DC=contoso,DC=com' -ErrorAction SilentlyContinue

        Write-Output "[SEA-DC1] Creating test user accounts with non-expiring passwords..."
        $testUsers = @('LabUser1', 'LabUser2', 'LabUser3', 'LabUser4', 'LabUser5')
        foreach ($user in $testUsers) {
            $password = ConvertTo-SecureString 'Pa55w.rd1234' -AsPlainText -Force
            New-ADUser -Name $user -SamAccountName $user -AccountPassword $password `
                -Enabled $true -PasswordNeverExpires $true -Path 'CN=Users,DC=contoso,DC=com' `
                -ErrorAction SilentlyContinue
        }

        Write-Output "[SEA-DC1] Lab 07 config complete (IT OU and test users created)."
    }

    'SEA-SVR1' {
        Write-Output "[SEA-SVR1] Enabling WinRM..."
        Enable-PSRemoting -Force -SkipNetworkProfileCheck

        Write-Output "[SEA-SVR1] Ready for Lab 07 (LAPS client installed during lab)."
    }

    'SEA-SVR2' {
        Write-Output "[SEA-SVR2] Installing RSAT tools..."
        $featureResult = Install-WindowsFeature -Name RSAT-AD-Tools, GPMC
        if (-not $featureResult.Success) {
            throw 'Failed to install the Lab 7 RSAT tools.'
        }

        Write-Output "[SEA-SVR2] Verifying staged Lab 07 files..."
        foreach ($path in 'C:\Labfiles\Lab07\DG_Readiness_Tool.ps1', 'C:\Labfiles\Lab07\LAPS.x64.msi') {
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                throw "Required Lab 7 file not found: $path"
            }
        }

        Write-Output "[SEA-SVR2] Lab 07 config complete."
    }
}
