param(
    [switch] $Silent,
    [switch] $ExportTelemetryFunctions,
    [string[]] $bcContainerHelperConfigFile = @(),
    [switch] $useVolumes
)

. (Join-Path $PSScriptRoot "InitializeModule.ps1") `
    -Silent:$Silent `
    -bcContainerHelperConfigFile $bcContainerHelperConfigFile `
    -moduleName $MyInvocation.MyCommand.Name `

. (Join-Path $PSScriptRoot "HelperFunctions.ps1")
. (Join-Path $PSScriptRoot "SaaSHelperFunctions.ps1")
. (Join-Path $PSScriptRoot "BC.HelperFunctions.ps1")

if ($isMacOS) {
    Write-Host "Running on macOS, PowerShell $($PSVersionTable.PSVersion)"
    Write-Host -ForegroundColor Red "BcContainerHelper is not supported on macOS, only limited features are available"
}
elseif (!$silent) {
    if ($isLinux) {
        Write-Host "Running on Linux, PowerShell $($PSVersionTable.PSVersion)"
    }
    else {
        Write-Host "Running on Windows, PowerShell $($PSVersionTable.PSVersion)"
    }
}

if ($useVolumes -or $isInsideContainer) {
    $bcContainerHelperConfig.UseVolumes = $true
}

$hypervState = "Unknown"
function GetHypervState {
    if ($isAdministrator -and $hypervState -eq "Unknown") {
        try {
            $feature = Get-WindowsOptionalFeature -FeatureName Microsoft-Hyper-V -Online
            if ($feature) {
                $script:hypervState = $feature.State
            }
            else {
                $script:hypervState = "Disabled"
            }
        }
        catch {
            if ($_.Exception.Message -match "Class not registered") {
                Write-Host "Cannot check Hyper-V status."
            }
            else {
                throw $_
            }    
        }
    }
    return $script:hypervState
}

function VolumeOrPath {
    Param(
        [string] $path
    )

    if (!($path.Contains(':') -or $path.Contains('\') -or $path.Contains('/'))) {
        $volumes = @(docker volume ls --format "{{.Name}}")
        if ($volumes -notcontains $path) {
            docker volume create $path
        }
        $inspect = (docker volume inspect $path) | ConvertFrom-Json
        return $inspect.MountPoint
    }
    else {
        return $path
    }
}

$bcContainerHelperConfig.bcartifactsCacheFolder = VolumeOrPath $bcContainerHelperConfig.bcartifactsCacheFolder
$bcContainerHelperConfig.bcNuGetCacheFolder = VolumeOrPath $bcContainerHelperConfig.bcNuGetCacheFolder
$bcContainerHelperConfig.hostHelperFolder = VolumeOrPath $bcContainerHelperConfig.HostHelperFolder
$usedContainerHelperConfigFile = $bcContainerHelperConfigFile

$ENV:DOCKER_SCAN_SUGGEST = "$($bcContainerHelperConfig.DOCKER_SCAN_SUGGEST)".ToLowerInvariant()

$sessions = @{}

$extensionsFolder = Join-Path $bcContainerHelperConfig.hostHelperFolder "Extensions"
if (!(Test-Path -Path $extensionsFolder -PathType Container)) {
    if (!(Test-Path -Path $bcContainerHelperConfig.hostHelperFolder -PathType Container)) {
        New-Item -Path $bcContainerHelperConfig.hostHelperFolder -ItemType Container -Force | Out-Null
    }
    New-Item -Path $extensionsFolder -ItemType Container -Force | Out-Null

    if ($isWindows -and !$isAdministrator) {
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($myUsername, 'FullControl', 3, 'InheritOnly', 'Allow')
        $acl = Get-Acl -Path $bcContainerHelperConfig.hostHelperFolder
        $acl.AddAccessRule($rule)
        Set-Acl -Path $bcContainerHelperConfig.hostHelperFolder -AclObject $acl | Out-Null
    }
}

if ($isWindows) {
    . (Join-Path $PSScriptRoot "Check-BcContainerHelperPermissions.ps1")
    if (!$silent) {
        Check-BcContainerHelperPermissions -Silent
    }
}

. (Join-Path $PSScriptRoot 'BC.ArtifactsHelper.ps1')
. (Join-Path $PSScriptRoot 'BC.AppSourceHelper.ps1')
. (Join-Path $PSScriptRoot 'BC.ALGoHelper.ps1')
. (Join-Path $PSScriptRoot 'BC.SaasHelper.ps1')
. (Join-Path $PSScriptRoot 'BC.NuGetHelper.ps1')

# Container Info functions
. (Join-Path $PSScriptRoot "ContainerInfo\Get-NavContainerNavVersion.ps1")
. (Join-Path $PSScriptRoot "ContainerInfo\Get-NavContainerPlatformVersion.ps1")
. (Join-Path $PSScriptRoot "ContainerInfo\Get-NavContainerImageName.ps1")
. (Join-Path $PSScriptRoot "ContainerInfo\Get-NavContainerArtifactUrl.ps1")
. (Join-Path $PSScriptRoot "ContainerInfo\Get-NavContainerGenericTag.ps1")
. (Join-Path $PSScriptRoot "ContainerInfo\Get-NavContainerOsVersion.ps1")
. (Join-Path $PSScriptRoot "ContainerInfo\Get-NavContainerEula.ps1")
. (Join-Path $PSScriptRoot "ContainerInfo\Get-NavContainerLegal.ps1")
. (Join-Path $PSScriptRoot "ContainerInfo\Get-NavContainerCountry.ps1")
. (Join-Path $PSScriptRoot "ContainerInfo\Get-NavContainerIpAddress.ps1")
. (Join-Path $PSScriptRoot "ContainerInfo\Get-NavContainerSharedFolders.ps1")
. (Join-Path $PSScriptRoot "ContainerInfo\Get-NavContainerPath.ps1")
. (Join-Path $PSScriptRoot "ContainerInfo\Get-NavContainerName.ps1")
. (Join-Path $PSScriptRoot "ContainerInfo\Get-NavContainerDebugInfo.ps1")
. (Join-Path $PSScriptRoot "ContainerInfo\Test-NavContainer.ps1")
. (Join-Path $PSScriptRoot "ContainerInfo\Get-NavContainerId.ps1")
. (Join-Path $PSScriptRoot "ContainerInfo\Get-NavContainers.ps1")
. (Join-Path $PSScriptRoot "ContainerInfo\Get-NavContainerEventLog.ps1")
. (Join-Path $PSScriptRoot "ContainerInfo\Get-NavContainerServerConfiguration.ps1")
. (Join-Path $PSScriptRoot "ContainerInfo\Get-NavContainerImageLabels.ps1")
. (Join-Path $PSScriptRoot "ContainerInfo\Get-NavContainerImageTags.ps1")
. (Join-Path $PSScriptRoot "ContainerInfo\Get-NavContainerLicenseInformation.ps1")
# CompilerFolder Handling Functions
. (Join-Path $PSScriptRoot "CompilerFolderHandling\New-BcCompilerFolder.ps1")
. (Join-Path $PSScriptRoot "CompilerFolderHandling\Remove-BcCompilerFolder.ps1")
. (Join-Path $PSScriptRoot "CompilerFolderHandling\Compile-AppWithBcCompilerFolder.ps1")
. (Join-Path $PSScriptRoot "CompilerFolderHandling\Copy-AppFilesToCompilerFolder.ps1")

# Container Handling Functions
. (Join-Path $PSScriptRoot "ContainerHandling\Get-NavContainerSession.ps1")
. (Join-Path $PSScriptRoot "ContainerHandling\Remove-NavContainerSession.ps1")
. (Join-Path $PSScriptRoot "ContainerHandling\New-NavContainer.ps1")
. (Join-Path $PSScriptRoot "ContainerHandling\New-NavImage.ps1")
. (Join-Path $PSScriptRoot "ContainerHandling\Restart-NavContainer.ps1")
. (Join-Path $PSScriptRoot "ContainerHandling\Stop-NavContainer.ps1")
. (Join-Path $PSScriptRoot "ContainerHandling\Start-NavContainer.ps1")
. (Join-Path $PSScriptRoot "ContainerHandling\Import-NavContainerLicense.ps1")
. (Join-Path $PSScriptRoot "ContainerHandling\Set-BcContainerKeyVaultAadAppAndCertificate.ps1")
. (Join-Path $PSScriptRoot "ContainerHandling\Remove-NavContainer.ps1")
. (Join-Path $PSScriptRoot "ContainerHandling\Wait-NavContainerReady.ps1")
. (Join-Path $PSScriptRoot "ContainerHandling\Extract-FilesFromNavContainerImage.ps1")
. (Join-Path $PSScriptRoot "ContainerHandling\Extract-FilesFromStoppedNavContainer.ps1")
. (Join-Path $PSScriptRoot "ContainerHandling\Get-BestNavContainerImageName.ps1")
. (Join-Path $PSScriptRoot "ContainerHandling\Get-BestGenericImageName.ps1")
. (Join-Path $PSScriptRoot "ContainerHandling\Invoke-ScriptInNavContainer.ps1")
. (Join-Path $PSScriptRoot "ContainerHandling\Flush-ContainerHelperCache.ps1")
. (Join-Path $PSScriptRoot "ContainerHandling\Get-LatestAlLanguageExtensionUrl.ps1")
. (Join-Path $PSScriptRoot "ContainerHandling\Get-AlLanguageExtensionFromArtifacts.ps1")
. (Join-Path $PSScriptRoot "ContainerHandling\traefik\Add-DomainToTraefikConfig.ps1")
. (Join-Path $PSScriptRoot "ContainerHandling\traefik\Create-CustomTraefikImage.ps1")
. (Join-Path $PSScriptRoot "ContainerHandling\Set-BcContainerServerConfiguration.ps1")
. (Join-Path $PSScriptRoot "ContainerHandling\Restart-BcContainerServiceTier.ps1")
. (Join-Path $PSScriptRoot "ObjectHandling\Import-TestToolkitToNavContainer.ps1")
. (Join-Path $PSScriptRoot "ObjectHandling\Invoke-NavContainerCodeunit.ps1")

# Tenant Handling functions
. (Join-Path $PSScriptRoot "TenantHandling\New-NavContainerTenant.ps1")
. (Join-Path $PSScriptRoot "TenantHandling\Remove-NavContainerTenant.ps1")
. (Join-Path $PSScriptRoot "TenantHandling\Get-NavContainerTenants.ps1")

# Bacpac Handling functions
. (Join-Path $PSScriptRoot "Bacpac\Export-NavContainerDatabasesAsBacpac.ps1")
. (Join-Path $PSScriptRoot "Bacpac\Backup-NavContainerDatabases.ps1")
. (Join-Path $PSScriptRoot "Bacpac\Restore-DatabasesInNavContainer.ps1")
. (Join-Path $PSScriptRoot "Bacpac\Restore-BcDatabaseFromArtifacts.ps1")
. (Join-Path $PSScriptRoot "Bacpac\Remove-BcDatabase.ps1")

# User Handling functions
. (Join-Path $PSScriptRoot "UserHandling\Get-NavContainerNavUser.ps1")
. (Join-Path $PSScriptRoot "UserHandling\New-NavContainerNavUser.ps1")
. (Join-Path $PSScriptRoot "UserHandling\New-NavContainerWindowsUser.ps1")
. (Join-Path $PSScriptRoot "UserHandling\Setup-NavContainerTestUsers.ps1")

# Misc functions
. (Join-Path $PSScriptRoot "Misc\Write-NavContainerHelperWelcomeText.ps1")
. (Join-Path $PSScriptRoot "Misc\Get-LocaleFromCountry.ps1")
. (Join-Path $PSScriptRoot "Misc\Get-NavVersionFromVersionInfo.ps1")
. (Join-Path $PSScriptRoot "Misc\Copy-FileFromNavContainer.ps1")
. (Join-Path $PSScriptRoot "Misc\Copy-FileToNavContainer.ps1")
. (Join-Path $PSScriptRoot "Misc\Copy-ItemFromBcContainer.ps1")
. (Join-Path $PSScriptRoot "Misc\Copy-ItemToBcContainer.ps1")
. (Join-Path $PSScriptRoot "Misc\Add-FontsToNavContainer.ps1")
. (Join-Path $PSScriptRoot "Misc\Set-BcContainerFeatureKeys.ps1")
. (Join-Path $PSScriptRoot "Misc\Import-PfxCertificateToNavContainer.ps1")
. (Join-Path $PSScriptRoot "Misc\Import-CertificateToNavContainer.ps1")

# Company Handling functions
. (Join-Path $PSScriptRoot "CompanyHandling\Copy-CompanyInNavContainer.ps1")
. (Join-Path $PSScriptRoot "CompanyHandling\Get-CompanyInNavContainer.ps1")
. (Join-Path $PSScriptRoot "CompanyHandling\New-CompanyInNavContainer.ps1")
. (Join-Path $PSScriptRoot "CompanyHandling\Remove-CompanyInNavContainer.ps1")

# App Handling functions
. (Join-Path $PSScriptRoot "AppHandling\Publish-NavContainerApp.ps1")
. (Join-Path $PSScriptRoot "AppHandling\Repair-NavContainerApp.ps1")
. (Join-Path $PSScriptRoot "AppHandling\Sync-NavContainerApp.ps1")
. (Join-Path $PSScriptRoot "AppHandling\Install-NavContainerApp.ps1")
. (Join-Path $PSScriptRoot "AppHandling\Start-NavContainerAppDataUpgrade.ps1")
. (Join-Path $PSScriptRoot "AppHandling\UnInstall-NavContainerApp.ps1")
. (Join-Path $PSScriptRoot "AppHandling\UnPublish-NavContainerApp.ps1")
. (Join-Path $PSScriptRoot "AppHandling\Get-NavContainerAppInfo.ps1")
. (Join-Path $PSScriptRoot "AppHandling\Compile-AppInNavContainer.ps1")
. (Join-Path $PSScriptRoot "AppHandling\Convert-ALCOutputToAzureDevOps.ps1")
. (Join-Path $PSScriptRoot "AppHandling\Install-NAVSipCryptoProviderFromNavContainer.ps1")
. (Join-Path $PSScriptRoot "AppHandling\Sign-NavContainerApp.ps1")
. (Join-Path $PSScriptRoot "AppHandling\Get-NavContainerAppRuntimePackage.ps1")
. (Join-Path $PSScriptRoot "AppHandling\Convert-BcAppsToRuntimePackages.ps1")
. (Join-Path $PSScriptRoot "AppHandling\Get-NavContainerApp.ps1")
. (Join-Path $PSScriptRoot "AppHandling\Extract-AppFileToFolder.ps1")
. (Join-Path $PSScriptRoot "AppHandling\Get-AppJsonFromAppFile.ps1")
. (Join-Path $PSScriptRoot "AppHandling\Create-SymbolsFileFromAppFile.ps1")
. (Join-Path $PSScriptRoot "AppHandling\Copy-AppFilesToFolder.ps1")
. (Join-Path $PSScriptRoot "AppHandling\Replace-DependenciesInAppFile.ps1")
. (Join-Path $PSScriptRoot "AppHandling\Run-TestsInNavContainer.ps1")
. (Join-Path $PSScriptRoot "AppHandling\Run-BCPTTestsInBcContainer.ps1")
. (Join-Path $PSScriptRoot "AppHandling\Run-ConnectionTestToNavContainer.ps1")
. (Join-Path $PSScriptRoot "AppHandling\Get-TestsFromNavContainer.ps1")
. (Join-Path $PSScriptRoot "AppHandling\Create-AlProjectFolderFromNavContainer.ps1")
. (Join-Path $PSScriptRoot "AppHandling\Publish-NewApplicationToNavContainer.ps1")
. (Join-Path $PSScriptRoot "AppHandling\Copy-AlSourceFiles.ps1")
. (Join-Path $PSScriptRoot "AppHandling\Clean-BcContainerDatabase.ps1")
. (Join-Path $PSScriptRoot "AppHandling\Add-GitToAlProjectFolder.ps1")
. (Join-Path $PSScriptRoot "AppHandling\Sort-AppFoldersByDependencies.ps1")
. (Join-Path $PSScriptRoot "AppHandling\Sort-AppFilesByDependencies.ps1")
. (Join-Path $PSScriptRoot "AppHandling\Run-AlPipeline.ps1")
. (Join-Path $PSScriptRoot "AppHandling\Run-AlValidation.ps1")
. (Join-Path $PSScriptRoot "AppHandling\Run-AlCops.ps1")

# Api Functions
. (Join-Path $PSScriptRoot "Api\Get-NavContainerApiCompanyId.ps1")
. (Join-Path $PSScriptRoot "Api\Invoke-NavContainerApi.ps1")

# Configuration Package Handling
. (Join-Path $PSScriptRoot "ConfigPackageHandling\Get-PackageInfoFromRapidStartFile.ps1")
. (Join-Path $PSScriptRoot "ConfigPackageHandling\Import-ConfigPackageInNavContainer.ps1")
. (Join-Path $PSScriptRoot "ConfigPackageHandling\Remove-ConfigPackageInNavContainer.ps1")
. (Join-Path $PSScriptRoot "ConfigPackageHandling\UploadImportAndApply-ConfigPackageInBcContainer.ps1")

# Container Handling functions
. (Join-Path $PSScriptRoot "ContainerHandling\Enter-NavContainer.ps1")
. (Join-Path $PSScriptRoot "ContainerHandling\Open-NavContainer.ps1")
. (Join-Path $PSScriptRoot "ContainerHandling\New-NavContainerWizard.ps1")

# Traefik Handling functions
. (Join-Path $PSScriptRoot "ContainerHandling\Setup-TraefikContainerForNavContainers.ps1")

# Object Handling functions
. (Join-Path $PSScriptRoot "ObjectHandling\Export-NavContainerObjects.ps1")
. (Join-Path $PSScriptRoot "ObjectHandling\Create-MyOriginalFolder.ps1")
. (Join-Path $PSScriptRoot "ObjectHandling\Create-MyDeltaFolder.ps1")
. (Join-Path $PSScriptRoot "ObjectHandling\Convert-Txt2Al.ps1")
. (Join-Path $PSScriptRoot "ObjectHandling\Export-ModifiedObjectsAsDeltas.ps1")
. (Join-Path $PSScriptRoot "ObjectHandling\Convert-ModifiedObjectsToAl.ps1")
. (Join-Path $PSScriptRoot "ObjectHandling\Import-ObjectsToNavContainer.ps1")
. (Join-Path $PSScriptRoot "ObjectHandling\Import-DeltasToNavContainer.ps1")
. (Join-Path $PSScriptRoot "ObjectHandling\Compile-ObjectsInNavContainer.ps1")

# Azure AD specific functions
. (Join-Path $PSScriptRoot "AzureAD\Create-AadAppsForNav.ps1")
. (Join-Path $PSScriptRoot "AzureAD\Create-AadUsersInNavContainer.ps1")
. (Join-Path $PSScriptRoot "AzureAD\New-AadAppsForBc.ps1")
. (Join-Path $PSScriptRoot "AzureAD\Remove-AadAppsForBc.ps1")

# Azure VM specific functions
. (Join-Path $PSScriptRoot "AzureVM\Replace-NavServerContainer.ps1")
. (Join-Path $PSScriptRoot "AzureVM\New-LetsEncryptCertificate.ps1")
. (Join-Path $PSScriptRoot "AzureVM\Renew-LetsEncryptCertificate.ps1")

# Symbol Handling
. (Join-Path $PSScriptRoot "SymbolHandling\Generate-SymbolsInNavContainer.ps1")

# PackageHandling
. (Join-Path $PSScriptRoot "PackageHandling\Resolve-DependenciesFromAzureFeed.ps1")
. (Join-Path $PSScriptRoot "PackageHandling\Publish-BuildOutputToAzureFeed.ps1")
. (Join-Path $PSScriptRoot "PackageHandling\Publish-BuildOutputToStorage.ps1")
. (Join-Path $PSScriptRoot "PackageHandling\Get-AzureFeedWildcardVersion.ps1")
. (Join-Path $PSScriptRoot "PackageHandling\Install-AzDevops.ps1")

# In Development mode only
if ($LatestGenericTagVersion -eq '0.0.0.0') {
    $labels = Get-BcContainerImageLabels -imageName 'mcr.microsoft.com/businesscentral:ltsc2022'
    if ($labels) {
        $LatestGenericTagVersion = $labels.tag
        Write-Host "LatestGenericTagVersion is $LatestGenericTagVersion"
    }
}

# SIG # Begin signature block
# MIInSQYJKoZIhvcNAQcCoIInOjCCJzYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCByZ+uXmg9p7GDg
# fH9J6T/swuveRfr0lN67z0hvb9yGgaCCDLowggX1MIID3aADAgECAhMzAAACHU0Z
# yE7XD1dIAAAAAAIdMA0GCSqGSIb3DQEBCwUAMFcxCzAJBgNVBAYTAlVTMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBD
# b2RlIFNpZ25pbmcgUENBIDIwMjQwHhcNMjYwNDE2MTg1OTQzWhcNMjcwNDE1MTg1
# OTQzWjB0MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYD
# VQQDExVNaWNyb3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IB
# DwAwggEKAoIBAQDQvewXxx9gZZFC6Ys1WBay8BJ8kGA4JQnH5CMafqOASlTpK9H8
# o5ZXTXt0caVQTNMUPt445wXYD+dFtaKWTwDn1I52oUSrC9vJin1Gsqt+zyKJL5Dg
# 3eQXbQNR61DmMy20GLTIO3SFed9Rfi/ophgCLGFLDR3r0KvHjwMb/jYWS0celV/4
# Lz27LfAekm8v9E5IXaeiXbAUYZKK090n4CVl3JBtbN+9DtI9SNu/yjvozW52/u7R
# X/Ttpa/KDlpuokZ+Zcbvmtd9ur9gFLvZzh41o9MsE/clQtdaFWGvuo6Jua/ntpgk
# ey3E5/vBFe+MJPG6phdnuo6r57ZudCudiI1bAgMBAAGjggGbMIIBlzAOBgNVHQ8B
# Af8EBAMCB4AwHwYDVR0lBBgwFgYKKwYBBAGCN0wIAQYIKwYBBQUHAwMwHQYDVR0O
# BBYEFH6QuMwqcPG0hQlQ6c5jCtTTLrVeMEUGA1UdEQQ+MDykOjA4MR4wHAYDVQQL
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xFjAUBgNVBAUTDTIzMDAxMis1MDc1NTkw
# HwYDVR0jBBgwFoAUf1k/VCHarU/vBeXmo9ctBpQSCDEwYAYDVR0fBFkwVzBVoFOg
# UYZPaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwvTWljcm9zb2Z0
# JTIwQ29kZSUyMFNpZ25pbmclMjBQQ0ElMjAyMDI0LmNybDBtBggrBgEFBQcBAQRh
# MF8wXQYIKwYBBQUHMAKGUWh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMv
# Y2VydHMvTWljcm9zb2Z0JTIwQ29kZSUyMFNpZ25pbmclMjBQQ0ElMjAyMDI0LmNy
# dDAMBgNVHRMBAf8EAjAAMA0GCSqGSIb3DQEBCwUAA4ICAQBKTbYOjzwTG/DXGaz9
# s6+fQeaTtDcFmMY+5UyVFCyj7Pv+5i37qfX8lSL/tBIfYQfWsMuBQlfZurJD6r4H
# VJ2CeH+1fgiq8dcHdVKoZ3Sa2qXoX3cq9iS8cVb06B7+5/XJ7I0OxHH9fDsvJ3T3
# w5V/ZtAIFmLrl+P0CtG+92uzRsn0nTbdFjOkLMLWPLAU3THohKRlSEMgFJpPkm5n
# 5UAZ35xX6FWCrDLsSKb555bTifwa8mJBwdlof0bmfYidH+dxZ1FdDxvLnNl9zeKs
# A4kejaaIqqIPguhwAti5Ql7BlTNoJNwxCvBmqW2MQLnCkYN/VVUsR3V2x/rcTNzo
# Bf/Z/SpROvdaA2ZOOd1uioXJt3tdLQ7vHpqpib0KfWr/FWXW10q38VxfCnRQBqzb
# SuztR7nEMuzX7Ck+B/XaPDXd1qh72+QYyB0Z2VzWmO9zsnb9Uq/dwu8LGeQqnyu6
# 7SDGACvnXii2fb9+US492VTnXSnFKyqwgzUyFMtZK1/sHYTv6bG4TtQUygQxTN+Z
# V+aJIlKO2MqZ7bKrAnOzS9m6NgoTdWOq11bTOZwKlIEV/EhV9SWkDmdpR/hPPT2v
# 6TEj4F8PT/zHjRezIU5c/DGlt/VhY/pK0XkJtEyMmmS1BMtjU/rqBZVMIm3dnxQs
# /TBByr+Cf8Z1r7aifQVQ+WSqzjCCBr0wggSloAMCAQICEzMAAAA5O7Y3Gb8GHWcA
# AAAAADkwDQYJKoZIhvcNAQEMBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRl
# IEF1dGhvcml0eSAyMDExMB4XDTI0MDgwODIwNTQxOFoXDTM2MDMyMjIyMTMwNFow
# VzELMAkGA1UEBhMCVVMxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEo
# MCYGA1UEAxMfTWljcm9zb2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAyNDCCAiIwDQYJ
# KoZIhvcNAQEBBQADggIPADCCAgoCggIBANgBnB7jOMeqlRYHNa265v4IY9fH8TKh
# emHfPINe1gpLaV3dhg324WwH06LcHbpnsBukCDNitryo0dtS/EW6I/yEL/bLSY8h
# KpbfQuWusBPr9qazYcDxCW/qnjb5JsI1s8bNOg3bVATvQVL4tcf03aTycsz8QeCd
# M0l/yHRObJ9QqazM1r6VPEOJ7LL+uEEb73w6QCuhs89a1uv1zerOYMnsneRRwCbp
# yW11IcggU0cRKDDq1pjVJzIbIF6+oiXXbReOsgeI8zu1FyQfK0fVkaya8SmVHQ/t
# Of23mZ4W9k0Ri22QW9p3UgSC5OUDktKxxcCmGL6tXLfOGSWHIIV4YrTJTT6PNty5
# REojHJuZHArkF9VnHTERWoTjAzfI3kP+5b4alUdhgAZ7ttOu1bVnXfHaqPYl2rPs
# 20ji03LOVWsh/radgE17es5hL+t6lV0eVHrVhsssROWJuz2MXMCt7iw7lFPG9LXK
# Gjsmonn2gotGdHIuEg5JnJMJVmixd5LRlkmgYRZKzhxSCwyoGIq0PhaA7Y+VPct5
# pCHkijcIIDm0nlkK+0KyepolcqGm0T/GYQRMhHJlGOOmVQop36wUVUYklUy++vDW
# eEgEo4s7hxN6mIbf2MSIQ/iIfMZgJxC69oukMUXCrOC3SkE/xIkgpfl22MM1itkZ
# 35nNXkMolU1lAgMBAAGjggFOMIIBSjAOBgNVHQ8BAf8EBAMCAYYwEAYJKwYBBAGC
# NxUBBAMCAQAwHQYDVR0OBBYEFH9ZP1Qh2q1P7wXl5qPXLQaUEggxMBkGCSsGAQQB
# gjcUAgQMHgoAUwB1AGIAQwBBMA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAU
# ci06AjGQQ7kUBU7h6qfHMdEjiTQwWgYDVR0fBFMwUTBPoE2gS4ZJaHR0cDovL2Ny
# bC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWljUm9vQ2VyQXV0MjAx
# MV8yMDExXzAzXzIyLmNybDBeBggrBgEFBQcBAQRSMFAwTgYIKwYBBQUHMAKGQmh0
# dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljUm9vQ2VyQXV0MjAx
# MV8yMDExXzAzXzIyLmNydDANBgkqhkiG9w0BAQwFAAOCAgEAFJQfOChP7onn6fLI
# MKrSlN1WYKwDFgAddymOUO3FrM8d7B/W/iQ6DxXsDn7D5W4wMwYeLystcEqfkjz4
# NURRgazyMu5yRzQh4LqjA4tStTcJh1opExo7nn5PuPBYnbu0+THSuVHTe0VTTPVh
# ily/piFrDo3axQ9P4C+Ol5yet+2gTfekICS5xS+cYfSIvgn0JksVBVMYVI5QFu/q
# hnLhsEFEUzG8fvv0hjgkO+lkpV9ty6GkN4vdnd7ya6Q6aR9y34aiM1qmxaxBi6OU
# nyNl6fkuun/diTFnYDLTppOkr/mg5WSfCiDVMNCxtj4wPKC5OmHm1DQIt/MNokbb
# H3UGsFP1QbzsLocuSqLCvH09Io3fDPTmscR9Y75G4qX7RTX8AdBPo0I6OEojf39z
# uFZt0qOHm65YWQE69cZM2ueE1MB05dNNgHK9gTE7zKvK/fg8B2qjW88MT/WF5V5u
# vZGtqa9FSL2RazArA+rDPuf6JGYz4HpgMZHB4S6szWSKYBv0VisCzfxgeU+dquXW
# 9bd0auYlOB58DPcOYKdc3Se94g+xL4pcEhbB54JOgAkwYTu/9dLeH2pDqeJZAABV
# DWRQCaXfO5LgyKwKCLYXpigrZYCjUSBcr+Ve8PFWMhVTQl0v4q8J/AUmQN5W4n10
# 1cY2L4A7GTQG1h32HHAvfQESWP0xghnlMIIZ4QIBATBuMFcxCzAJBgNVBAYTAlVT
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
# c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMjQCEzMAAAIdTRnITtcPV0gAAAAAAh0w
# DQYJYIZIAWUDBAIBBQCgga4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYK
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEID/d0B0z
# 6JGTp46NWdMhNNxWxaP6EA4tHshlDIyVqRZ1MEIGCisGAQQBgjcCAQwxNDAyoBSA
# EgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20w
# DQYJKoZIhvcNAQEBBQAEggEAmI7h757JoA6UfQNBE6TeKcs9NmzQY6vFmz9Km06/
# BO4QTsHDv+J1OnW8pWvgDE7+/t9F66S/xIC+clinkSP8Pcse6K02BNUP/3dn68qp
# xA1UXF7hEQnZeKHV5rpdyp191D4BktGfHeTqoAcqpJ+1TNVMBccgCrUsdl4B1W6S
# fdkxVqXz6g1RXCKeHZ4BNZo+r40bT+OlmaPTioA9Yd/ORXal5i0osvVZPDd89kBe
# WouWUsmdVvAiYK4EWf0fL75e+7KLUrJGQzrfGoF1NwxQlkj1l7PaJOVcS63uvsX6
# CwxMVXkLEhhEV35Pcf22gKnScvpikQ0jsHpRPhYjvlTNAKGCF5cwgheTBgorBgEE
# AYI3AwMBMYIXgzCCF38GCSqGSIb3DQEHAqCCF3AwghdsAgEDMQ8wDQYJYIZIAWUD
# BAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGEWQoD
# ATAxMA0GCWCGSAFlAwQCAQUABCBP2RjTHIkpmwbxvtPgTomKrw7v7ozeDt+3IzEX
# KTMatAIGaoUd1euyGBMyMDI2MDgyNzA2MzAzOC4yMzRaMASAAgH0oIHRpIHOMIHL
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxN
# aWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRT
# UyBFU046ODkwMC0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFNlcnZpY2WgghHtMIIHIDCCBQigAwIBAgITMwAAAiJB0vaq/8i1/wABAAAC
# IjANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAe
# Fw0yNjAyMTkxOTM5NTZaFw0yNzA1MTcxOTM5NTZaMIHLMQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmlj
# YSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046ODkwMC0wNUUw
# LUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIi
# MA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC1ueKJukIuUsAAJo/AY5DZRqH7
# bhgv7CWGNlEdbRGoITrdE6Wsn57NaNu1BTdjBbFcv7Rfixte0x+HRvXSqsD+WeSX
# /6/y9wE0Mz+xRPTGIY20K7aQDa68OyzVyUeUCypyZC/gW/3ytO/ZOnU9H2ri77kJ
# P8ABrqyy1UxX/OseEgvHsj8yikWT0ARtrjWbXMHFzSOo5hQcfUmMXKqWWz6+N0+U
# ynhGy1n+doW4WZgpH8Y5W7hpSokWj1M/Lu4wi3o6Dz9vVWukcgUFGjLAl4YZpOha
# h7HuiC/alXImMQf8C3A8q/6/1hFoeIZB4UGkywxB/OSTOSsL6+39pDqzM7CgOpf4
# V799kN94yM9uXJI5T/SiA5MdIZIhEW0+bh85RqDh5YW3/oav54RPxw5OPlH64QV6
# KJkl0FIElMVoLNo8UWRQcMD179x7WASjC6LsaNZ7yK0qcESIsL1wiQmdfQBxcqrF
# CpIQfnmQFkOp9IyXUWqza8tmpz8E6aXg9b1eiAT3PVTgrOlPi/hYZCfPxX/6jGty
# Pjy1CiwOmJamohmSU//COAenfRT2G2HMRUpCX1zs+AmDmdQM1XRab4YSALLAlDzG
# CsgI77nnuJjoXAliJmv7NfrvWAcA5KqCUOWQ6kSPt5r28MfKXWJJpSXtFeS/MkDz
# Jy/iJRVyHcFy/B+MtwIDAQABo4IBSTCCAUUwHQYDVR0OBBYEFFkHwGoDJ5ZbEEiu
# 8KstiusqaozQMB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1Ud
# HwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3Js
# L01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggr
# BgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNv
# bS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIw
# MTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgw
# DgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUAA4ICAQBiAM+nqrpwG29txSXv
# 42o+CsTe2C4boaRfFju9JaWkLTHwq7pknNONL3n+UG3x/B083EKXiFYrAmul7BTH
# CGXU63/xRsZ2wj3ZmR0A4d9nf9saCJVm4juPVFBai/oktOOYH2j+1+zM70woN5on
# gB/pvy7X8AfY6JB4XPvb80Qz7fY5eddbnwjzg1sZhUPFbbcweWeACINrzqFK62mM
# eXKmhtufMraoogJeJXfWY3x4/pbubgENT3+pXT65203CPF9kfdKE7GKAIRYy3xkB
# TDvFd8dufjOpCn38nK6qMlVtnBjDhWQG0PM3E/oxBs5UBrI6pBYkmIHtbjifDquH
# T+ThaVV7xHc6InoSc3aNzX49JHUgQmuvDdMjLkbYXeA0/1q5IxSg2U+ycZBOvAi3
# udZPKhA5VzODjf/ucu/vFtXrYcRkmGKN3jujaK3/yMZi2Ju5NEL3ISWorwp7RjeZ
# g+JMIK0fosuVj+YCm5r64LH/D9QJDAj+XfZaNeFdv90K5A0QRRGP/poB9yTIVjEX
# j/uJzp8L4Dd44sAquqDOiHdkLgxfK8nPqpCSWPZ9G+RCPm85o9cAfxENtrSuOwcp
# yKzxsRCYCL+PK4+98orit9EVJ/LLoCeG+jLlj0KaD4Qy6sZe4rWMr1brQLosTBZN
# wFnXxNjInCWBd0i7is1yTS/4qTCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkA
# AAAAABUwDQYJKoZIhvcNAQELBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRl
# IEF1dGhvcml0eSAyMDEwMB4XDTIxMDkzMDE4MjIyNVoXDTMwMDkzMDE4MzIyNVow
# fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMd
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwggIiMA0GCSqGSIb3DQEBAQUA
# A4ICDwAwggIKAoICAQDk4aZM57RyIQt5osvXJHm9DtWC0/3unAcH0qlsTnXIyjVX
# 9gF/bErg4r25PhdgM/9cT8dm95VTcVrifkpa/rg2Z4VGIwy1jRPPdzLAEBjoYH1q
# UoNEt6aORmsHFPPFdvWGUNzBRMhxXFExN6AKOG6N7dcP2CZTfDlhAnrEqv1yaa8d
# q6z2Nr41JmTamDu6GnszrYBbfowQHJ1S/rboYiXcag/PXfT+jlPP1uyFVk3v3byN
# pOORj7I5LFGc6XBpDco2LXCOMcg1KL3jtIckw+DJj361VI/c+gVVmG1oO5pGve2k
# rnopN6zL64NF50ZuyjLVwIYwXE8s4mKyzbnijYjklqwBSru+cakXW2dg3viSkR4d
# Pf0gz3N9QZpGdc3EXzTdEonW/aUgfX782Z5F37ZyL9t9X4C626p+Nuw2TPYrbqgS
# Uei/BQOj0XOmTTd0lBw0gg/wEPK3Rxjtp+iZfD9M269ewvPV2HM9Q07BMzlMjgK8
# QmguEOqEUUbi0b1qGFphAXPKZ6Je1yh2AuIzGHLXpyDwwvoSCtdjbwzJNmSLW6Cm
# gyFdXzB0kZSU2LlQ+QuJYfM2BjUYhEfb3BvR/bLUHMVr9lxSUV0S2yW6r1AFemzF
# ER1y7435UsSFF5PAPBXbGjfHCBUYP3irRbb1Hode2o+eFnJpxq57t7c+auIurQID
# AQABo4IB3TCCAdkwEgYJKwYBBAGCNxUBBAUCAwEAATAjBgkrBgEEAYI3FQIEFgQU
# KqdS/mTEmr6CkTxGNSnPEP8vBO4wHQYDVR0OBBYEFJ+nFV0AXmJdg/Tl0mWnG1M1
# GelyMFwGA1UdIARVMFMwUQYMKwYBBAGCN0yDfQEBMEEwPwYIKwYBBQUHAgEWM2h0
# dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0
# bTATBgNVHSUEDDAKBggrBgEFBQcDCDAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMA
# QTALBgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTV9lbL
# j+iiXGJo0T2UkFvXzpoYxDBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3JsLm1p
# Y3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXRfMjAxMC0w
# Ni0yMy5jcmwwWgYIKwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIz
# LmNydDANBgkqhkiG9w0BAQsFAAOCAgEAnVV9/Cqt4SwfZwExJFvhnnJL/Klv6lwU
# tj5OR2R4sQaTlz0xM7U518JxNj/aZGx80HU5bbsPMeTCj/ts0aGUGCLu6WZnOlNN
# 3Zi6th542DYunKmCVgADsAW+iehp4LoJ7nvfam++Kctu2D9IdQHZGN5tggz1bSNU
# 5HhTdSRXud2f8449xvNo32X2pFaq95W2KFUn0CS9QKC/GbYSEhFdPSfgQJY4rPf5
# KYnDvBewVIVCs/wMnosZiefwC2qBwoEZQhlSdYo2wh3DYXMuLGt7bj8sCXgU6ZGy
# qVvfSaN0DLzskYDSPeZKPmY7T7uG+jIa2Zb0j/aRAfbOxnT99kxybxCrdTDFNLB6
# 2FD+CljdQDzHVG2dY3RILLFORy3BFARxv2T5JL5zbcqOCb2zAVdJVGTZc9d/HltE
# AY5aGZFrDZ+kKNxnGSgkujhLmm77IVRrakURR6nxt67I6IleT53S0Ex2tVdUCbFp
# AUR+fKFhbHP+CrvsQWY9af3LwUFJfn6Tvsv4O+S3Fb+0zj6lMVGEvL8CwYKiexcd
# FYmNcP7ntdAoGokLjzbaukz5m/8K6TT4JDVnK+ANuOaMmdbhIurwJ0I9JZTmdHRb
# atGePu1+oDEzfbzL6Xu/OHBE0ZDxyKs6ijoIYn/ZcGNTTY3ugm2lBRDBcQZqELQd
# VTNYs6FwZvKhggNQMIICOAIBATCB+aGB0aSBzjCByzELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFtZXJpY2Eg
# T3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjg5MDAtMDVFMC1E
# OTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEw
# BwYFKw4DAhoDFQC7ycXVZx3bsDpJkr7VucgpksozuKCBgzCBgKR+MHwxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29m
# dCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBCwUAAgUA7jonBTAiGA8y
# MDI2MDgyNzAzMDEyNVoYDzIwMjYwODI4MDMwMTI1WjB3MD0GCisGAQQBhFkKBAEx
# LzAtMAoCBQDuOicFAgEAMAoCAQACAi15AgH/MAcCAQACAhPUMAoCBQDuO3iFAgEA
# MDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAI
# AgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBAJLYF049z8IhyiyG8bLYVWvnsHoh
# MfcuSJN5JIiBqFdgICgfBaCPshK6xgZGA8hV4DKEW9GkxAyybmjQi3IXCT1yF4PY
# k9l1DWoUocG/jV6C6KjNOdOWSptg0EUxYrwqmwx1fgMFYLyxTmrSxCO6xncV6KV/
# wkL7LwjSd0RcHg/X3MCV2+zsGWatoaoYjNYpH86rlmhJf7GUKE5TCFGwDh7IIXP8
# JJSfta+aV+RtqwL663Zw20nYBhHlTr18JUDmxU6CCHwuCgNjS9SZHpQ8wYkH4/EI
# 8VSiT6TCT052Ob65PDIWJ7gh7r21U7aCtieumHTmanYKq8TgtSTBgfBvVbkxggQN
# MIIECQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQ
# MA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
# MSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAiJB
# 0vaq/8i1/wABAAACIjANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0G
# CyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCB6bqPeQnEK7DbJ2opJFsPr9evP
# tMApJjOpmRlqJdTzhzCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EIAVgXQEK
# BOfGgjNskmDOmbcEIOnHGNwA+QcRufDR5AkTMIGYMIGApH4wfDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgUENBIDIwMTACEzMAAAIiQdL2qv/Itf8AAQAAAiIwIgQgSnk2/IMw
# babtanX1XPog0/LjFYevh4tj0cFkbkPGrC0wDQYJKoZIhvcNAQELBQAEggIAIriE
# AYDXBcDsGyAgin3sdWTbt9pMkZaZ8L0MYFBaNXAqGXQ//MrHTv9qnf9Rykz4V6ZE
# kciPVVtl6q1+zdzEuQvTs/qJpT/l7+ZM/3OMTvIEC0pqviQ9ji/MUKfSFPnvUmBM
# dq/LzPRhduDQQhCc1CaeQgiNGZpTTQ7esSeQt1hwpcfjGNztCEUorVSE31ab30Ns
# Ut67YmoGOhyaH932NtU+dASoxE07dcQXH0foASDJZOeXIT6qBdXDky9Ho5wJcqXT
# 2f3hMelrbU2Zsv25qVe1OH4pRXIWjYlScJGNFfII+it2H1vcaIenkueSkCy/3THl
# VThPRgm40R88d3ZT//bLdO/ZP9Dois0Na+U6uPbO9HkDZeLPRwUGhkrS3BZv/Qyk
# 3t3rYxv/GRTonNwiezaRGSjFKkjcna0QTJeoaUPezXJnNT75MPevexe1vjkcI97j
# OxhpZI9tEX57uT9eRdB5eX787xQ/gml7jg9w/D9U0LWrEGi8cLnisEjjxe2BK7O8
# sicyu7a83Sak/+W4zO4rfMkq/nKdU/liAZcrV78x5VEZTqz3i+Upyo5oEoaOSe4+
# XrCoI9zqqmB47xZZIcbomqFoKwx6VwMDZBeDGWWkOkPoQaTyoCxlDZ0oAoV+I8/w
# V+JUtcWWYeZhJrdmPwZ9UhIB37Sj+A7WupQu7IM=
# SIG # End signature block
