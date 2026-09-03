<# 
 .Synopsis
  Publish an AL Application (including Base App) to a NAV/BC Container
 .Description
  This function will replace the existing application (including base app) with a new application
  The application will be deployed using developer mode (same as used by VS Code)
 .Parameter containerName
  Name of the container to which you want to publish your AL Project
 .Parameter appFile
  Path of the appFile
 .Parameter appDotNetPackagesFolder
  Location of project specific dotnet reference assemblies. Default means that the app only uses standard DLLs.
  If your project is using custom DLLs, you will need to place them in this folder and the folder needs to be shared with the container.
 .Parameter credential
  Credentials of the container super user if using NavUserPassword authentication
 .Parameter useCleanDatabase
  Add this switch if you want to uninstall all extensions and remove all C/AL objects in the range 1..1999999999.
  This switch (or useNewDatabase) is needed when turning a C/AL container into an AL Container.
 .Parameter useNewDatabase
  Add this switch if you want to create a new and empty database in the container
  This switch (or useCleanDatabase) is needed when turning a C/AL container into an AL Container.
 .Parameter doNotCopyEntitlements
  Specify this parameter to avoid copying entitlements when using -useNewDatabase
 .Parameter copyTables
  Array of table names to copy from original database when using -useNewDatabase
 .Parameter companyName
  CompanyName when using -useNewDatabase. Default is My Company.
 .Parameter doNotUseDevEndpoint
  Specify this parameter to deploy the application to the global scope instead of the developer (tenant) scope
 .Parameter saveData
  Add this switch if you want to keep all extension data. Requires -useCleanDatabase
 .Parameter restoreApps
  Specify whether or not you want to restore previously installed apps in the container
 .Parameter replaceDependencies
  With this parameter, you can specify a hashtable, describing that the specified dependencies in the apps being published should be replaced
  If your application doesn't use the same appId, Publisher, Name and version as the original baseapp, you need to specify this if you want to restore apps
 .Example
  Publish-NewApplicationToBcContainer -containerName test `
                                      -appFile (Join-Path $alProjectFolder ".output\$($appPublisher)_$($appName)_$($appVersion).app") `
                                      -appDotNetPackagesFolder (Join-Path $alProjectFolder ".netPackages") `
                                      -credential $credential
 .Example
  Publish-NewApplicationToBcContainer -containerName test `
                                      -appFile (Join-Path $alProjectFolder ".output\$($appPublisher)_$($appName)_$($appVersion).app") `
                                      -appDotNetPackagesFolder (Join-Path $alProjectFolder ".netPackages") `
                                      -credential $credential `
                                      -replaceDependencies @{ "437dbf0e-84ff-417a-965d-ed2bb9650972" = @{ "id" = "88b7902e-1655-4e7b-812e-ee9f0667b01b"; "name" = "MyBaseApp"; "publisher" = "Freddy Kristiansen"; "minversion" = "1.0.0.0" }}
#>
function Publish-NewApplicationToBcContainer {
    Param (
        [string] $containerName = $bcContainerHelperConfig.defaultContainerName,
        [Parameter(Mandatory=$true)]
        [string] $appFile,
        [Parameter(Mandatory=$false)]
        [string] $appDotNetPackagesFolder,
        [Parameter(Mandatory=$false)]
        [pscredential] $credential,
        [switch] $useCleanDatabase,
        [switch] $useNewDatabase,
        [switch] $doNotCopyEntitlements,
        [string[]] $copyTables = @(),
        [string] $companyName = "My Company",
        [switch] $doNotUseDevEndpoint,
        [switch] $saveData,
        [ValidateSet('No','Yes','AsRuntimePackages')]
        [string] $restoreApps = "No",
        [hashtable] $replaceDependencies = $null
    )

$telemetryScope = InitTelemetryScope -name $MyInvocation.InvocationName -parameterValues $PSBoundParameters -includeParameters @()
try {

    $platform = Get-BcContainerPlatformversion -containerOrImageName $containerName
    if ("$platform" -eq "") {
        $platform = (Get-BcContainerNavVersion -containerOrImageName $containerName).Split('-')[0]
    }
    [System.Version]$platformversion = $platform

    if ($platformversion.Major -lt 14) {
        throw "Container $containerName does not support the function Publish-NewApplicationToBcContainer"
    }

    Add-Type -AssemblyName System.Net.Http

    $customconfig = Get-BcContainerServerConfiguration -ContainerName $containerName
    $containerAppDotNetPackagesFolder = ""
    if ($appDotNetPackagesFolder -and (Test-Path $appDotNetPackagesFolder)) {
        $containerAppDotNetPackagesFolder = Get-BcContainerPath -containerName $containerName -path $appDotNetPackagesFolder -throw
    }
    
    Invoke-ScriptInBcContainer -containerName $containerName -scriptblock { Param ( $appDotNetPackagesFolder )

        $serviceTierAddInsFolder = (Get-Item "C:\Program Files\Microsoft Dynamics NAV\*\Service\Add-ins").FullName
        $RTCFolder = "C:\Program Files (x86)\Microsoft Dynamics NAV\*\RoleTailored Client"
    
        if (!(Test-Path (Join-Path $serviceTierAddInsFolder "RTC"))) {
            if (Test-Path $RTCFolder -PathType Container) {
                new-item -itemtype symboliclink -path $ServiceTierAddInsFolder -name "RTC" -value (Get-Item $RTCFolder).FullName | Out-Null
            }
        }
        if (Test-Path (Join-Path $serviceTierAddInsFolder "ProjectDotNetPackages")) {
            (Get-Item (Join-Path $serviceTierAddInsFolder "ProjectDotNetPackages")).Delete()
        }
        if ($appDotNetPackagesFolder) {
            new-item -itemtype symboliclink -path $serviceTierAddInsFolder -name "ProjectDotNetPackages" -value $appDotNetPackagesFolder | Out-Null
            Set-NavServerInstance $serverInstance -restart
            while (Get-NavTenant $serverInstance | Where-Object { $_.State -eq "Mounting" }) {
                Start-Sleep -Seconds 1
            }
        }

    } -argumentList $containerAppDotNetPackagesFolder

    $containerFolder = Join-Path $bcContainerHelperConfig.hostHelperFolder "Extensions\$containerName"
    $appsFolder = Join-Path $containerFolder "Extensions"
    if (!(Test-Path $appsFolder)) {
        New-Item -Path $appsFolder -ItemType Directory | Out-Null
    }
    if ($restoreApps -ne "No") {
        $installedApps = Get-BcContainerAppInfo -containerName $containerName -tenantSpecificProperties -sort DependenciesFirst | Where-Object { $_.Name -ne "System Application" -and $_.Name -ne "BaseApp" -and $_.Name -ne "Base Application" }
        if ($restoreApps -eq "AsRuntimePackages" -and ($replaceDependencies)) {
            Write-Warning "ReplaceDependencies will not work with apps restored as runtime packages"
        }
    }
    else {
        $installedApps = Get-BcContainerAppInfo -containerName $containerName -tenantSpecificProperties | Where-Object { $_.Name -eq "Application" }
    }
    $applicationApp = $installedApps | Where-Object { $_.Name -eq "Application" }
    if ($applicationApp) {
        Write-Host "Application App Exists"
    }
    $warninggiven = $false
    $installedApps | ForEach-Object {
        if ($_.Scope -eq "Global" -and !$doNotUseDevEndpoint) {
            if (!$warninggiven) {
                Write-Warning "Restoring apps to global scope might not work when publishing base app to dev endpoint. You might need to specify -doNotUseDevEndpoint"
                $warninggiven = $true
            }
        }
    }
    $installedApps | ForEach-Object {
        $installedAppFile = Join-Path $appsFolder $("$($_.Publisher)_$($_.Name)_$($_.Version).app".Split([System.IO.Path]::GetInvalidFileNameChars()) -join '')
        if ($restoreApps -eq "AsRuntimePackages") {
            Write-Host "Downloading app $($_.Name) as runtime package"
            Get-BCContainerAppRuntimePackage -containerName $containerName -appName $_.Name -publisher $_.Publisher -appVersion $_.Version -appFile $installedAppFile -Tenant default | Out-Null
        }
        else {
            Get-BCContainerApp -containerName $containerName -appName $_.Name -publisher $_.Publisher -appVersion $_.Version -appFile $installedAppFile -Tenant default -credential $credential | Out-Null
        }
    }
    if ($useCleanDatabase -or $useNewDatabase) {
        Clean-BcContainerDatabase -containerName $containerName -saveData:$saveData -saveOnlyBaseAppData:($restoreApps -eq "No") -useNewDatabase:$useNewDatabase -doNotCopyEntitlements:$doNotCopyEntitlements -copyTables $copyTables -credential $credential -CompanyName $CompanyName
    }

    $scope = "tenant"
    if ($doNotUseDevEndpoint) {
        $scope = "global"
    }
    Publish-BCContainerApp -containerName $containerName -appFile $appFile -scope $scope -credential $credential -useDevEndpoint:(!$doNotUseDevEndpoint) -skipVerification -sync -install

    if ($restoreApps -ne "No") {
        $installedApps | ForEach-Object {
            $installedApp = $_
            $installedAppFile = Join-Path $appsFolder $("$($installedApp.Publisher)_$($installedApp.Name)_$($installedApp.Version).app".Split([System.IO.Path]::GetInvalidFileNameChars()) -join '')

            if ($applicationApp) {
                if ($installedApp -eq $applicationApp) {
                    $replaceDeps = $replaceDependencies
                }
                elseif ($installedApp.Name -like "* language (*)" -and $installedApp.Publisher -eq "Microsoft") {
                    $replaceDeps = $replaceDependencies
                }
                else {
                    $replaceDeps = $null
                }
            }
            else {
                $replaceDeps = $replaceDependencies
            }

            if ($_.IsPublished) {
                try {
                    Publish-BCContainerApp -containerName $containerName -appFile $installedAppFile -skipVerification -sync -install:($installedApp.IsInstalled) -scope $Scope -useDevEndpoint:(!$doNotUseDevEndpoint) -replaceDependencies $replaceDeps -credential $credential -ShowMyCode "Check"                }
                catch {
                    $appFile = Invoke-ScriptInBCContainer -containerName $containername -scriptblock { Param($installedApp)
                        $filename = ""
                        $localdir = Get-Item -Path "c:\Applications.*"
                        if ($localdir) {
                            $filename = Get-ChildItem -Path $localdir.FullName -Filter "*.app" -Recurse | % {
                                $appInfo = Get-NavAppInfo -Path $_.FullName
                                if ("$($appInfo.Publisher)_$($appInfo.Name)_$($appInfo.Version)_$($appInfo.AppId)" -eq "$($installedApp.Publisher)_$($installedApp.Name)_$($installedApp.Version)_$($installedApp.AppId)") {
                                    $_.FullName
                                }
                            }
                        }
                        if (!$filename) {
                            $filename = Get-ChildItem -Path "c:\Applications" -Filter "*.app" -Recurse | % {
                                $appInfo = Get-NavAppInfo -Path $_.FullName
                                if ("$($appInfo.Publisher)_$($appInfo.Name)_$($appInfo.Version)_$($appInfo.AppId)" -eq "$($installedApp.Publisher)_$($installedApp.Name)_$($installedApp.Version)_$($installedApp.AppId)") {
                                    $_.FullName
                                }
                            }
                        }
                        $filename
                    } -argumentlist $installedapp
                    if ($appfile) {
                        try {
                            Publish-BCContainerApp -containerName $containerName -appFile ":$appFile" -skipVerification -sync -install:($installedApp.IsInstalled) -scope $Scope -useDevEndpoint:(!$doNotUseDevEndpoint) -replaceDependencies $replaceDeps -credential $credential
                        }
                        catch {
                            Write-Warning "Could not publish :$([System.IO.Path]::GetFileName($appFile)) - $($_.Exception.Message)"
                        }
                    }
                    else {
                        Write-Warning "Could not publish $([System.IO.Path]::GetFileName($installedAppFile)) - $($_.Exception.Message)"
                    }
                }
            }
        }
    }
}
catch {
    TrackException -telemetryScope $telemetryScope -errorRecord $_
    throw
}
finally {
    TrackTrace -telemetryScope $telemetryScope
}
}
Set-Alias -Name Publish-NewApplicationToNavContainer -Value Publish-NewApplicationToBcContainer
Export-ModuleMember -Function Publish-NewApplicationToBcContainer -Alias Publish-NewApplicationToNavContainer

# SIG # Begin signature block
# MIIncQYJKoZIhvcNAQcCoIInYjCCJ14CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCYjHHfp85Ie4Ec
# bUjffoocvtB3/PBV59GFWP2vxYjg3aCCDMkwggYEMIID7KADAgECAhMzAAACHPrN
# xZvoL37EAAAAAAIcMA0GCSqGSIb3DQEBCwUAMFcxCzAJBgNVBAYTAlVTMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBD
# b2RlIFNpZ25pbmcgUENBIDIwMjQwHhcNMjYwNDE2MTg1OTQxWhcNMjcwNDE1MTg1
# OTQxWjB0MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYD
# VQQDExVNaWNyb3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IB
# DwAwggEKAoIBAQDVsZfgOKmM31HPfoWOoNEiw0SlCiIxUMC0I9NMWbucKOw/e9lP
# oAoehQVu6SG65V4EPzrYsnBnFPNoi4/HoOdjhz1qkrEt4I6tEcxXU6oOeY9zGveC
# /3iBeuhLYxM3M/PkcUoebF+Nednm8OkdSPoDu8imViHPQq/8CQUu0WRR4rE+dMRf
# rpVqfmNi2qWCX94T4MsepijGVkwE//tJg0ryAiYdHT34LSnlG/RSBZmQRGWZ5g8j
# qnKjRParSqMft1gvjuUTVgtWNZfgcLFSK5Wa0myrq8OPcgTGGsRgun+tnSS+IxDT
# xVsAPH1OzvPjwomguByhUe/OcvUN0D5Wmp7xAgMBAAGjggGqMIIBpjAOBgNVHQ8B
# Af8EBAMCB4AwHwYDVR0lBBgwFgYKKwYBBAGCN0wIAQYIKwYBBQUHAwMwHQYDVR0O
# BBYEFNoH7a2YDjOSwpkp6DHcmUS7J+0yMFQGA1UdEQRNMEukSTBHMS0wKwYDVQQL
# EyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxFjAUBgNVBAUT
# DTIzMDAxMis1MDc1NjkwHwYDVR0jBBgwFoAUf1k/VCHarU/vBeXmo9ctBpQSCDEw
# YAYDVR0fBFkwVzBVoFOgUYZPaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9w
# cy9jcmwvTWljcm9zb2Z0JTIwQ29kZSUyMFNpZ25pbmclMjBQQ0ElMjAyMDI0LmNy
# bDBtBggrBgEFBQcBAQRhMF8wXQYIKwYBBQUHMAKGUWh0dHA6Ly93d3cubWljcm9z
# b2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwQ29kZSUyMFNpZ25pbmcl
# MjBQQ0ElMjAyMDI0LmNydDAMBgNVHRMBAf8EAjAAMA0GCSqGSIb3DQEBCwUAA4IC
# AQAUnEqhaRXe0T3hIJjvdQErEkrA/7bByjn6t5IArODkkRjzkYwtKMc2yYj2quaN
# rLutWw2YZcngKPy1b71YyDJQTy4NDRwaSh9Tw5thrk3NmcPrAHia5vtcBJ1CgtKK
# 7mQbIcQ22d/N3813ayCDDFewu1+jsZmX+r/aTEqaOM4TVxVtRSkuCy8nAXKuChOK
# Li/zA4XuH8iEYqIsj2YoNaeSxVmeGiERXpKdo3dDmYi0kO5w2D8VS4c3+9h6gElY
# BaAAg/dYErBg27qT3vv0zRDJhJufvCNylA8S7/+8H5E/PV5cng6na9VV/w9OV3qu
# uND6zdGa2EX38Glp50F9AIQk3p2xXmcvorDeM4XJ7UlWYBi6g80J1SSOQnInCYFE
# msfUNn3+1AaTJKSJL83quKArTac2pKhu0Yzzzrzo6HrsRiQKzpnRBb1/dMa6P3hz
# 75XbMRBctNsFhZC07WCmjExdLg2eHW5uV0TY8D5+6wozJf7vF3+WHkYPO85Z+BC6
# U4FkNbYNycZ9cE4j1tXRdyDCfml6c0HWPHjNVDObrv9lKt3qUqFpX38VCqVCyNOO
# 1UcXfQiVjJw32U2WUKZjt/neJKHEBsm9kFsLuWzkQ53+qcaSaytmsCnk2gOglrlD
# 5d3kKyvvAw+rzm0lT8K38P6PLxfZQHhu4W8dV7Av8N2ZmDCCBr0wggSloAMCAQIC
# EzMAAAA5O7Y3Gb8GHWcAAAAAADkwDQYJKoZIhvcNAQEMBQAwgYgxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBS
# b290IENlcnRpZmljYXRlIEF1dGhvcml0eSAyMDExMB4XDTI0MDgwODIwNTQxOFoX
# DTM2MDMyMjIyMTMwNFowVzELMAkGA1UEBhMCVVMxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9zb2Z0IENvZGUgU2lnbmluZyBQ
# Q0EgMjAyNDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBANgBnB7jOMeq
# lRYHNa265v4IY9fH8TKhemHfPINe1gpLaV3dhg324WwH06LcHbpnsBukCDNitryo
# 0dtS/EW6I/yEL/bLSY8hKpbfQuWusBPr9qazYcDxCW/qnjb5JsI1s8bNOg3bVATv
# QVL4tcf03aTycsz8QeCdM0l/yHRObJ9QqazM1r6VPEOJ7LL+uEEb73w6QCuhs89a
# 1uv1zerOYMnsneRRwCbpyW11IcggU0cRKDDq1pjVJzIbIF6+oiXXbReOsgeI8zu1
# FyQfK0fVkaya8SmVHQ/tOf23mZ4W9k0Ri22QW9p3UgSC5OUDktKxxcCmGL6tXLfO
# GSWHIIV4YrTJTT6PNty5REojHJuZHArkF9VnHTERWoTjAzfI3kP+5b4alUdhgAZ7
# ttOu1bVnXfHaqPYl2rPs20ji03LOVWsh/radgE17es5hL+t6lV0eVHrVhsssROWJ
# uz2MXMCt7iw7lFPG9LXKGjsmonn2gotGdHIuEg5JnJMJVmixd5LRlkmgYRZKzhxS
# CwyoGIq0PhaA7Y+VPct5pCHkijcIIDm0nlkK+0KyepolcqGm0T/GYQRMhHJlGOOm
# VQop36wUVUYklUy++vDWeEgEo4s7hxN6mIbf2MSIQ/iIfMZgJxC69oukMUXCrOC3
# SkE/xIkgpfl22MM1itkZ35nNXkMolU1lAgMBAAGjggFOMIIBSjAOBgNVHQ8BAf8E
# BAMCAYYwEAYJKwYBBAGCNxUBBAMCAQAwHQYDVR0OBBYEFH9ZP1Qh2q1P7wXl5qPX
# LQaUEggxMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMA8GA1UdEwEB/wQFMAMB
# Af8wHwYDVR0jBBgwFoAUci06AjGQQ7kUBU7h6qfHMdEjiTQwWgYDVR0fBFMwUTBP
# oE2gS4ZJaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMv
# TWljUm9vQ2VyQXV0MjAxMV8yMDExXzAzXzIyLmNybDBeBggrBgEFBQcBAQRSMFAw
# TgYIKwYBBQUHMAKGQmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMv
# TWljUm9vQ2VyQXV0MjAxMV8yMDExXzAzXzIyLmNydDANBgkqhkiG9w0BAQwFAAOC
# AgEAFJQfOChP7onn6fLIMKrSlN1WYKwDFgAddymOUO3FrM8d7B/W/iQ6DxXsDn7D
# 5W4wMwYeLystcEqfkjz4NURRgazyMu5yRzQh4LqjA4tStTcJh1opExo7nn5PuPBY
# nbu0+THSuVHTe0VTTPVhily/piFrDo3axQ9P4C+Ol5yet+2gTfekICS5xS+cYfSI
# vgn0JksVBVMYVI5QFu/qhnLhsEFEUzG8fvv0hjgkO+lkpV9ty6GkN4vdnd7ya6Q6
# aR9y34aiM1qmxaxBi6OUnyNl6fkuun/diTFnYDLTppOkr/mg5WSfCiDVMNCxtj4w
# PKC5OmHm1DQIt/MNokbbH3UGsFP1QbzsLocuSqLCvH09Io3fDPTmscR9Y75G4qX7
# RTX8AdBPo0I6OEojf39zuFZt0qOHm65YWQE69cZM2ueE1MB05dNNgHK9gTE7zKvK
# /fg8B2qjW88MT/WF5V5uvZGtqa9FSL2RazArA+rDPuf6JGYz4HpgMZHB4S6szWSK
# YBv0VisCzfxgeU+dquXW9bd0auYlOB58DPcOYKdc3Se94g+xL4pcEhbB54JOgAkw
# YTu/9dLeH2pDqeJZAABVDWRQCaXfO5LgyKwKCLYXpigrZYCjUSBcr+Ve8PFWMhVT
# Ql0v4q8J/AUmQN5W4n101cY2L4A7GTQG1h32HHAvfQESWP0xghn+MIIZ+gIBATBu
# MFcxCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# KDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMjQCEzMAAAIc
# +s3Fm+gvfsQAAAAAAhwwDQYJYIZIAWUDBAIBBQCgga4wGQYJKoZIhvcNAQkDMQwG
# CisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZI
# hvcNAQkEMSIEIBv6xjBVS2pmKrlN4lCsJrXw7hOxgqicAoV1tsuIrkusMEIGCisG
# AQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEA1U4Chj+bSEXQ4dOs7IM4
# gW/umuf3nAblLgveg/VRmwtWfcjAyR9wAnZxmtnVEHCkjoIzptMbKqOkRKjaK6ry
# iw4yF/0yU9f45vCqIUKPv72aNhDjfvJA3j/17HnfrD56eLgKaO5A/7JscPz8OOij
# cX8jc+Yxr4p+sJ6RoAdsrMmzYrPmCVOWBHi2YczLvrcMV+PNY1t57nE7y1X2dZUE
# CU4gCUUKxoAySsJOO0WQ18MFCR3hDi39A+xXK5odzSoCPHCSU9I57mAFRRuwHL3t
# Ki3s/juGtfx5G+HMcKkyysNSOyuPhTimjrVVMMF4+P1lBy18beyGuQ/99WKUD+Xt
# XaGCF7AwghesBgorBgEEAYI3AwMBMYIXnDCCF5gGCSqGSIb3DQEHAqCCF4kwgheF
# AgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFFMIIB
# QQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCBwayNFN2pIAZJBxJG4
# VfqcxDJahHBufZilPARipWkLkgIGaog2IlUPGBMyMDI2MDgyNzA2MzAzNy44NTha
# MASAAgH0oIHZpIHWMIHTMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0
# ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjo2QjA1LTA1RTAtRDk0NzElMCMG
# A1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaCCEf4wggcoMIIFEKAD
# AgECAhMzAAACEUUYOZtDz/xsAAEAAAIRMA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29m
# dCBUaW1lLVN0YW1wIFBDQSAyMDEwMB4XDTI1MDgxNDE4NDgxM1oXDTI2MTExMzE4
# NDgxM1owgdMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTAr
# BgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUG
# A1UECxMeblNoaWVsZCBUU1MgRVNOOjZCMDUtMDVFMC1EOTQ3MSUwIwYDVQQDExxN
# aWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOC
# Ag8AMIICCgKCAgEAz7m7MxAdL5Vayrk7jsMo3GnhN85ktHCZEvEcj4BIccHKd/NK
# C7uPvpX5dhO63W6VM5iCxklG8qQeVVrPaKvj8dYYJC7DNt4NN3XlVdC/voveJuPP
# hTJ/u7X+pYmV2qehTVPOOB1/hpmt51SzgxZczMdnFl+X2e1PgutSA5CAh9/Xz5NW
# 0CxnYVz8g0Vpxg+Bq32amktRXr8m3BSEgUs8jgWRPVzPHEczpbhloGGEfHaROmHh
# VKIqN+JhMweEjU2NXM2W6hm32j/QH/I/KWqNNfYchHaG0xJljVTYoUKPpcQDuhH9
# dQKEgvGxj2U5/3Fq1em4dO6Ih04m6R+ttxr6Y8oRJH9ZhZ3sciFBIvZh7E2YFXOj
# P4MGybSylQTPDEFAtHHgpkskeEUhsPDR9VvWWhekhQx3qXaAKh+AkLmz/hpE3e0y
# +RIKO2AREjULJAKgf+R9QnNvqMeMkz9PGrjsijqWGzB2k2JNyaUYKlbmQweOabsC
# ioiY2fJbimjVyFAGk5AeYddUFxvJGgRVCH7BeBPKAq7MMOmSCTOMZ0Sw6zyNx4Uh
# h5Y0uJ0ZOoTKnB3KfdN/ba/eKHFeEhi3WqAfzTxiy0rMvhsfsXZK7zoclqaRvVl8
# Q48J174+eyriypY9HhU+ohgiYi4uQGDDVdTDeKDtoC/hD2Cn+ARzwE1rFfECAwEA
# AaOCAUkwggFFMB0GA1UdDgQWBBRifUUDwOnqIcvfb53+yV0EZn7OcDAfBgNVHSME
# GDAWgBSfpxVdAF5iXYP05dJlpxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1l
# LVN0YW1wJTIwUENBJTIwMjAxMCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsG
# AQUFBzAChlBodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01p
# Y3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMB
# Af8EAjAAMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDAN
# BgkqhkiG9w0BAQsFAAOCAgEApEKdnMeIIUiU6PatZ/qbrwiDzYUMKRczC4Bp/XY1
# S9NmHI+2c3dcpwH2SOmDfdvIIqt7mRrgvBPYOvJ9CtZS5eeIrsObC0b0ggKTv2wr
# TgWG+qktqNFEhQeipdURNLN68uHAm5edwBytd1kwy5r6B93klxDsldOmVWtw/ngj
# 7knN09muCmwr17JnsMFcoIN/H59s+1RYN7Vid4+7nj8FcvYy9rbZOMndBzsTiosF
# 1M+aMIJX2k3EVFVsuDL7/R5ppI9Tg7eWQOWKMZHPdsA3ZqWzDuhJqTzoFSQShnZe
# nC+xq/z9BhHPFFbUtfjAoG6EDPjSQJYXmogja8OEa19xwnh3wVufeP+ck+/0gxNi
# 7g+kO6WaOm052F4siD8xi6Uv75L7798lHvPThcxHHsgXqMY592d1wUof3tL/eDaQ
# 0UhnYCU8yGkU2XJnctONnBKAvURAvf2qiIWDj4Lpcm0zA7VuofuJR1Tpuyc5p1ja
# 52bNZBBVqAOwyDhAmqWsJXAjYXnssC/fJkee314Fh+GIyMgvAPRScgqRZqV16dTB
# Yvoe+w1n/wWs/ySTUsxDw4T/AITcu5PAsLnCVpArDrFLRTFyut+eHUoG6UYZfj8/
# RsuQ42INse1pb/cPm7G2lcLJtkIKT80xvB1LiaNvPTBVEcmNSvFUM0xrXZXcYcxV
# XiYwggdxMIIFWaADAgECAhMzAAAAFcXna54Cm0mZAAAAAAAVMA0GCSqGSIb3DQEB
# CwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMTIwMAYD
# VQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAxMDAe
# Fw0yMTA5MzAxODIyMjVaFw0zMDA5MzAxODMyMjVaMHwxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFBDQSAyMDEwMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA5OGm
# TOe0ciELeaLL1yR5vQ7VgtP97pwHB9KpbE51yMo1V/YBf2xK4OK9uT4XYDP/XE/H
# ZveVU3Fa4n5KWv64NmeFRiMMtY0Tz3cywBAY6GB9alKDRLemjkZrBxTzxXb1hlDc
# wUTIcVxRMTegCjhuje3XD9gmU3w5YQJ6xKr9cmmvHaus9ja+NSZk2pg7uhp7M62A
# W36MEBydUv626GIl3GoPz130/o5Tz9bshVZN7928jaTjkY+yOSxRnOlwaQ3KNi1w
# jjHINSi947SHJMPgyY9+tVSP3PoFVZhtaDuaRr3tpK56KTesy+uDRedGbsoy1cCG
# MFxPLOJiss254o2I5JasAUq7vnGpF1tnYN74kpEeHT39IM9zfUGaRnXNxF803RKJ
# 1v2lIH1+/NmeRd+2ci/bfV+AutuqfjbsNkz2K26oElHovwUDo9Fzpk03dJQcNIIP
# 8BDyt0cY7afomXw/TNuvXsLz1dhzPUNOwTM5TI4CvEJoLhDqhFFG4tG9ahhaYQFz
# ymeiXtcodgLiMxhy16cg8ML6EgrXY28MyTZki1ugpoMhXV8wdJGUlNi5UPkLiWHz
# NgY1GIRH29wb0f2y1BzFa/ZcUlFdEtsluq9QBXpsxREdcu+N+VLEhReTwDwV2xo3
# xwgVGD94q0W29R6HXtqPnhZyacaue7e3PmriLq0CAwEAAaOCAd0wggHZMBIGCSsG
# AQQBgjcVAQQFAgMBAAEwIwYJKwYBBAGCNxUCBBYEFCqnUv5kxJq+gpE8RjUpzxD/
# LwTuMB0GA1UdDgQWBBSfpxVdAF5iXYP05dJlpxtTNRnpcjBcBgNVHSAEVTBTMFEG
# DCsGAQQBgjdMg30BATBBMD8GCCsGAQUFBwIBFjNodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20vcGtpb3BzL0RvY3MvUmVwb3NpdG9yeS5odG0wEwYDVR0lBAwwCgYIKwYB
# BQUHAwgwGQYJKwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGGMA8G
# A1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAU1fZWy4/oolxiaNE9lJBb186aGMQw
# VgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9j
# cmwvcHJvZHVjdHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3JsMFoGCCsGAQUF
# BwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3Br
# aS9jZXJ0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcnQwDQYJKoZIhvcNAQEL
# BQADggIBAJ1VffwqreEsH2cBMSRb4Z5yS/ypb+pcFLY+TkdkeLEGk5c9MTO1OdfC
# cTY/2mRsfNB1OW27DzHkwo/7bNGhlBgi7ulmZzpTTd2YurYeeNg2LpypglYAA7AF
# vonoaeC6Ce5732pvvinLbtg/SHUB2RjebYIM9W0jVOR4U3UkV7ndn/OOPcbzaN9l
# 9qRWqveVtihVJ9AkvUCgvxm2EhIRXT0n4ECWOKz3+SmJw7wXsFSFQrP8DJ6LGYnn
# 8AtqgcKBGUIZUnWKNsIdw2FzLixre24/LAl4FOmRsqlb30mjdAy87JGA0j3mSj5m
# O0+7hvoyGtmW9I/2kQH2zsZ0/fZMcm8Qq3UwxTSwethQ/gpY3UA8x1RtnWN0SCyx
# TkctwRQEcb9k+SS+c23Kjgm9swFXSVRk2XPXfx5bRAGOWhmRaw2fpCjcZxkoJLo4
# S5pu+yFUa2pFEUep8beuyOiJXk+d0tBMdrVXVAmxaQFEfnyhYWxz/gq77EFmPWn9
# y8FBSX5+k77L+DvktxW/tM4+pTFRhLy/AsGConsXHRWJjXD+57XQKBqJC4822rpM
# +Zv/Cuk0+CQ1ZyvgDbjmjJnW4SLq8CdCPSWU5nR0W2rRnj7tfqAxM328y+l7vzhw
# RNGQ8cirOoo6CGJ/2XBjU02N7oJtpQUQwXEGahC0HVUzWLOhcGbyoYIDWTCCAkEC
# AQEwggEBoYHZpIHWMIHTMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0
# ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjo2QjA1LTA1RTAtRDk0NzElMCMG
# A1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIa
# AxUAKyp8q2VdgAq1VGkzd7PZwV6zNc2ggYMwgYCkfjB8MQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1T
# dGFtcCBQQ0EgMjAxMDANBgkqhkiG9w0BAQsFAAIFAO459EkwIhgPMjAyNjA4MjYy
# MzI0NTdaGA8yMDI2MDgyNzIzMjQ1N1owdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA
# 7jn0SQIBADAKAgEAAgIB3gIB/zAHAgEAAgITDTAKAgUA7jtFyQIBADA2BgorBgEE
# AYRZCgQCMSgwJjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYag
# MA0GCSqGSIb3DQEBCwUAA4IBAQBD9ujVkVB/5lrR38kDPuIEYMQxDhtUhabI9sZ/
# lBbRiXQHK41IgdjDcZ7ZPOD9IotoC5m+Yx0J3AkYqfYTRQ0cVD39oopuf0WaCNFV
# wtJx9EdVAGK7LR7gjXGlkrJYDjmWiWFkVpKBz22p8R3Dh+V8FgpY1Aj42zZ/3YVb
# FHaMvunWbhMHdwjwAhO0YXWInq0VRfnHRtiMI1egpn78N5X3OEp5xWU78KljZ904
# MrtWDYSNYrylmIUbzCvrcFTjVecfKMLK/yxtI2rFiqXPLAIQiXwMA6xshy/5ntNv
# lQQs22yCJj77+avw5VtSgrIVNR4lCPFrtMqNJda9mrHoti01MYIEDTCCBAkCAQEw
# gZMwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcT
# B1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UE
# AxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAIRRRg5m0PP/GwA
# AQAAAhEwDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0B
# CRABBDAvBgkqhkiG9w0BCQQxIgQgtD02P4v2zyOw4xzDTU52ya3fJDph9VAECczA
# kurexHswgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCAsrTOpmu+HTq1aXFwv
# lhjF8p2nUCNNCEX/OWLHNDMmtzCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1w
# IFBDQSAyMDEwAhMzAAACEUUYOZtDz/xsAAEAAAIRMCIEIPWpo5whL8rUqRexabJr
# bXHMQEE8LnZbxQLXMVaP6iqJMA0GCSqGSIb3DQEBCwUABIICAKZXevB3teqF8y6J
# 1XDY5VQ6v1xNOQQGwdSspwTCC+QBGgdEEZhQqbneJh1pkuvnzw7eaCA+K8wzUcfK
# QuAJxEZPeHZYfmF/8Gkw8gv0g7JYqC+xC3PKWsXCpLN4ATPq+JadUtUqTvzZJuod
# dXPsX5prOsGTqyo6hZY1gUwB9XTBKMYzGzn46iBtD1ASz1aWIxdb+1YlqA5RGGij
# ZlSdeceyrzopS3LZEq15HjaIiOK2Pcr73FAdiqeEIAAOEMQcdCyUnvmGybaLWo31
# LBH8MBz4J2ey37lovTK8DaRkjI8X3wN/USHC6JTLUqXmJyD8cJxFO2mCr55vJU5x
# TVJzdEksOYCubAtw/fNABuqWD1HGoOlaLrk2PQE2Iv1Zw5q9tGpq3hqGDdvqvVpi
# 6YDgFINVDeXZRyhLoJAlFKUXXVBlkCFdBVLY5xwvcqXd3Rmv+3wbOWxayX6hVoz7
# PNmdPVeNTqnRluQqiy1dVgUh4G2ap40Rn/314C2w2lZPRyp5kEeTdH+nJLI5KUg3
# Lwxhf2CfaGdh83oEdUnYrJRYz2hl/BwcfsRsYxA5sbpd2M3CBbwz8q55BNUeB0jB
# Bb3SowwWlaq3nn4zNFRbwt+a1PiE12F8pKVxww/i5D1QYl5jk/T5ChKSH4iyLYFx
# eRK3EKsUep6F/8YB6rdA+9v03fLC
# SIG # End signature block
