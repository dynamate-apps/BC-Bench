if ($isWindows) {
    $programDataFolder = 'C:\ProgramData\BcContainerHelper'
    $artifactsCacheFolder = "c:\bcartifacts.cache"
    $nugetCacheFolder = "c:\bcnuget.cache"
}
elseif ($isMacOS) {
    $programDataFolder = "/Users/$myUsername/.bccontainerhelper"
    $artifactsCacheFolder = "/Users/$myUsername/.bcartifacts.cache"
    $nugetCacheFolder = "/Users/$myUsername/.bcnuget.cache"
}
else {
    $programDataFolder = "/home/$myUsername/.bccontainerhelper"
    $artifactsCacheFolder = "/home/$myUsername/.bcartifacts.cache"
    $nugetCacheFolder = "/home/$myUsername/.bcnuget.cache"
}

function Get-ContainerHelperConfig {
    if (!((Get-Variable -scope Script bcContainerHelperConfig -ErrorAction SilentlyContinue) -and $bcContainerHelperConfig)) {
        Set-Variable -scope Script -Name bcContainerHelperConfig -Value @{
            "bcartifactsCacheFolder" = ""
            "genericImageName" = 'mcr.microsoft.com/businesscentral:{1}'
            "genericImageNameFilesOnly" = 'mcr.microsoft.com/businesscentral:{1}-filesonly'
            "usePsSession" = $true
            "usePwshForBc24" = $true
            "usePsSessionForBc28" = $false
            "useSslForWinRmSession" = $true
            "useWinRmSession" = "allow"   # allow, always, never
            "addTryCatchToScriptBlock" = $true
            "killPsSessionProcess" = $false
            "usePrereleaseAlTool" = $false
            "useVolumes" = $false
            "useVolumeForMyFolder" = $false
            "use7zipIfAvailable" = $true
            "defaultNewContainerParameters" = [PSCustomObject]@{
            }
            "hostHelperFolder" = ""
            "containerHelperFolder" = $programDataFolder
            "defaultContainerName" = "bcserver"
            "useCompilerFolder" = $false
            "digestAlgorithm" = "SHA256"
            "timeStampServer" = "http://timestamp.digicert.com"
            "sandboxContainersAreMultitenantByDefault" = $true
            "useSharedEncryptionKeys" = $true
            "DOCKER_SCAN_SUGGEST" = $false
            "psSessionTimeout" = 0
            "artifactDownloadTimeout" = 600
            "defaultDownloadTimeout" = 120
            "baseUrl" = "https://businesscentral.dynamics.com"
            "apiBaseUrl" = "https://api.businesscentral.dynamics.com"
            "mapCountryCode" = [PSCustomObject]@{
                "ae" = "w1"
                "ar" = "w1"
                "bd" = "w1"
                "dz" = "w1"
                "cl" = "w1"
                "pr" = "w1"
                "eg" = "w1"
                "fo" = "dk"
                "gl" = "dk"
                "id" = "w1"
                "ke" = "w1"
                "lb" = "w1"
                "lk" = "w1"
                "lu" = "w1"
                "ma" = "w1"
                "mm" = "w1"
                "mt" = "w1"
                "my" = "w1"
                "ng" = "w1"
                "qa" = "w1"
                "sa" = "w1"
                "sg" = "w1"
                "tn" = "w1"
                "ua" = "w1"
                "za" = "w1"
                "ao" = "w1"
                "bh" = "w1"
                "ba" = "w1"
                "bw" = "w1"
                "cr" = "br"
                "cy" = "w1"
                "do" = "br"
                "ec" = "br"
                "sv" = "br"
                "gt" = "br"
                "hn" = "br"
                "jm" = "w1"
                "mv" = "w1"
                "mu" = "w1"
                "ni" = "br"
                "pa" = "br"
                "py" = "br"
                "tt" = "br"
                "uy" = "br"
                "zw" = "w1"
                "im" = "gb"
                "gg" = "gb"
            }
            "mapNetworkSettings" = [PSCustomObject]@{
            }
            "AddHostDnsServersToNatContainers" = $false
            "TraefikUseDnsNameAsHostName" = $false
            "TreatWarningsAsErrors" = @()
            "PartnerTelemetryConnectionString" = ""
            "MicrosoftTelemetryConnectionString" = "InstrumentationKey=5b44407e-9750-4a07-abe9-30c3b853821b;IngestionEndpoint=https://southcentralus-0.in.applicationinsights.azure.com/"
            "SendExtendedTelemetryToMicrosoft" = $false
            "TraefikImage" = "tobiasfenster/traefik-for-windows:v1.7.34"
            "ObjectIdForInternalUse" = 88123
            "WinRmCredentials" = $null
            "WarningPreference" = "SilentlyContinue"
            "UseNewFormatForGetBcContainerAppInfo" = $false
            "NoOfSecondsToSleepAfterPublishBcContainerApp" = 1
            "RenewClientContextBetweenTests" = $false
            "DebugMode" = $false
            "ExcludeBuilds" = @()
            "MinimumDotNetRuntimeVersionStr" = "6.0.16"
            "MinimumDotNetRuntimeVersionUrl" = 'https://download.visualstudio.microsoft.com/download/pr/ca13c6f1-3107-4cf8-991c-f70edc1c1139/a9f90579d827514af05c3463bed63c22/dotnet-sdk-6.0.408-win-x64.zip'
            "MSSymbolsNuGetFeedUrl" = 'https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/MSSymbols/nuget/v3/index.json'
            "MSAppsNuGetFeedUrl" = 'https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/MSApps/nuget/v3/index.json'
            "TrustedNuGetFeeds" = @(
            )
            "IsGitHubActions" = ($env:GITHUB_ACTIONS -eq "true")
            "IsAzureDevOps" = ($env:TF_BUILD -eq "true")
            "IsGitLab" = ($env:GITLAB_CI -eq "true")
            "useApproximateVersion" = $false
            "useSqlServerModule" = $false
            "NuGetSearchResultsCacheRetentionPeriod" = 600 # 10 minutes
            "BcNuGetCacheFolder" = ""
            "doNotRemovePackagesFolderIfExists" = $false
        }

        if ($isInsider) {
            $bcContainerHelperConfig.genericImageName = 'mcr.microsoft.com/businesscentral:{1}-dev'
            $bcContainerHelperConfig.genericImageNameFilesOnly = 'mcr.microsoft.com/businesscentral:{1}-filesonly-dev'
        }

        if ($bcContainerHelperConfigFile -notcontains (Join-Path $programDataFolder "BcContainerHelper.config.json")) {
            $bcContainerHelperConfigFile = @((Join-Path $programDataFolder "BcContainerHelper.config.json"))+$bcContainerHelperConfigFile
        }
        $bcContainerHelperConfigFile | ForEach-Object {
            $configFile = $_
            if (Test-Path $configFile) {
                try {
                    $savedConfig = Get-Content $configFile | ConvertFrom-Json
                    if ("$savedConfig") {
                        $keys = $bcContainerHelperConfig.Keys | ForEach-Object { $_ }
                        $keys | ForEach-Object {
                            if ($savedConfig.PSObject.Properties.Name -eq "$_") {
                                $savedConfigValue = $savedConfig."$_"
                                if ($isPsCore -and ($savedConfigValue -is [Int64])) {
                                    $savedConfigValue = [Int32]$savedConfigValue
                                }
                                if ($bcContainerHelperConfig."$_" -and $savedConfigValue -and $bcContainerHelperConfig."$_".GetType() -ne $savedConfigValue.GetType()) {
                                    Write-Host -ForegroundColor Red "Ignoring config setting $_ as the type in the config file is different than in the default configuration"
                                }
                                else {
                                    if ((ConvertTo-Json -InputObject $bcContainerHelperConfig."$_" -Compress) -eq (ConvertTo-Json -InputObject $savedConfigValue -Compress)) {
                                        if (!$silent) {
                                            Write-Host "Ignoring unchanged config setting $_"
                                        }
                                    }
                                    else {
                                        if (!$silent) {
                                            Write-Host "Setting $_ = $savedConfigValue"
                                        }
                                        $bcContainerHelperConfig."$_" = $savedConfigValue
                                    }
                                }
                            }
                        }
                    }
                }
                catch {
                    throw "Error reading configuration file $configFile, cannot import module."
                }
            }
        }

        if ($isInsideContainer) {
            $bcContainerHelperConfig.usePsSession = $true
            try {
                $myinspect = docker inspect $(hostname) | ConvertFrom-Json
                $bcContainerHelperConfig.WinRmCredentials = New-Object PSCredential -ArgumentList 'WinRmUser', (ConvertTo-SecureString -string "P@ss$($myinspect.Id.SubString(48))" -AsPlainText -Force)
            }
            catch {}
        }

        if ($bcContainerHelperConfig.UseVolumes) {
            if ($bcContainerHelperConfig.bcartifactsCacheFolder -eq "") {
                $bcContainerHelperConfig.bcartifactsCacheFolder = "bcartifacts.cache"
            }
            if ($bcContainerHelperConfig.bcNuGetCacheFolder -eq "") {
                $bcContainerHelperConfig.bcNuGetCacheFolder = "bcnuget.cache"
            }
            if ($bcContainerHelperConfig.hostHelperFolder -eq "") {
                $bcContainerHelperConfig.hostHelperFolder = "hostHelperFolder"
            }
            $bcContainerHelperConfig.useVolumeForMyFolder = $false
        }
        else {
            if ($bcContainerHelperConfig.bcartifactsCacheFolder -eq "") {
                $bcContainerHelperConfig.bcartifactsCacheFolder = $artifactsCacheFolder
            }
            if ($bcContainerHelperConfig.bcNuGetCacheFolder -eq "") {
                $bcContainerHelperConfig.bcNuGetCacheFolder = $nuGetCacheFolder
            }
            if ($bcContainerHelperConfig.hostHelperFolder -eq "") {
                $bcContainerHelperConfig.hostHelperFolder = $programDataFolder
            }
        }

        if ($isWindows -and ($bcContainerHelperConfig.useWinRmSession -ne 'never')) {
            # useWinRmSession should be never if the service isn't running
            $service = get-service WinRm -erroraction SilentlyContinue
            if ($service -and $service.Status -ne "Running") {
                if (!$Silent) {
                    Write-Host "WinRM service is not running, will not try to use WinRM sessions"
                }
                $bcContainerHelperConfig.useWinRmSession = 'never'
            }
        }

        Export-ModuleMember -Variable bcContainerHelperConfig
    }
    return $bcContainerHelperConfig
}

$configHelperFolder = $programDataFolder
if (!(Test-Path $configHelperFolder)) {
    New-Item -Path $configHelperFolder -ItemType Container -Force | Out-Null
    if ($isWindows -and !$isAdministrator) {
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($myUsername,'FullControl', 3, 'InheritOnly', 'Allow')
        $acl = Get-Acl -Path $configHelperFolder
        $acl.AddAccessRule($rule)
        Set-Acl -Path $configHelperFolder -AclObject $acl | Out-Null
    }
}

Get-ContainerHelperConfig | Out-Null

$telemetry = @{
    "Assembly" = $null
    "PartnerClient" = $null
    "MicrosoftClient" = $null
    "CorrelationId" = ""
    "TopId" = ""
    "Debug" = $false
}
try {
    if (($bcContainerHelperConfig.MicrosoftTelemetryConnectionString) -and !$Silent) {
        Write-Host -ForegroundColor Green "BC.HelperFunctions emits usage statistics telemetry to Microsoft"
    }
    $dllPath = Join-Path $configHelperFolder 'Microsoft.ApplicationInsights.2.32.0.429.dll'
    if (-not (Test-Path $dllPath)) {
        Copy-Item (Join-Path $PSScriptRoot "Microsoft.ApplicationInsights.dll") -Destination $dllPath
    }
    $telemetry.Assembly = [System.Reflection.Assembly]::LoadFrom($dllPath)
} catch {
    if (!$Silent) {
        Write-Host -ForegroundColor Yellow "Unable to load ApplicationInsights.dll"
    }
}

. (Join-Path $PSScriptRoot "TelemetryHelper.ps1")

# Telemetry functions
Export-ModuleMember -Function RegisterTelemetryScope
Export-ModuleMember -Function InitTelemetryScope
Export-ModuleMember -Function AddTelemetryProperty
Export-ModuleMember -Function TrackTrace
Export-ModuleMember -Function TrackException

# Common functions
. (Join-Path $PSScriptRoot "Common\Download-File.ps1")
. (Join-Path $PSScriptRoot "Common\New-DesktopShortcut.ps1")
. (Join-Path $PSScriptRoot "Common\Remove-DesktopShortcut.ps1")
. (Join-Path $PSScriptRoot "Common\ConvertTo-HashTable.ps1")
. (Join-Path $PSScriptRoot "Common\Get-PlainText.ps1")
. (Join-Path $PSScriptRoot "Common\Invoke-gh.ps1")
. (Join-Path $PSScriptRoot "Common\Invoke-git.ps1")
. (Join-Path $PSScriptRoot "Common\ConvertTo-OrderedDictionary.ps1")

# BC Authentication helper functions
. (Join-Path $PSScriptRoot "Auth\New-BcAuthContext.ps1")
. (Join-Path $PSScriptRoot "Auth\Renew-BcAuthContext.ps1")

# SIG # Begin signature block
# MIIncQYJKoZIhvcNAQcCoIInYjCCJ14CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDv5Gjfn2Jx8y1p
# CJY6YRpRndYlrx3vosKQelCpLVXLGaCCDMkwggYEMIID7KADAgECAhMzAAACHPrN
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
# hvcNAQkEMSIEIGZGDr8gzGQWelg9fNO+xFO6oLJdklNcTsA1uMjRjsYIMEIGCisG
# AQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEAK2YKk9pB430jfi0IoQxo
# mi+5kJNM5xEIdcTR76hduNipZLnQR6JyD8Dzj33kwbDIQOxHuGyGscDrxhg85Ttw
# zHfen0vR5TnVW7hJVsiYmn+3dRq0bMO8e34x/vbyPSrmxVp1mjGpwoJPVe2QMXTa
# HIAOLKc6SKNOr8hgISOlbMclNYkqJZinqDMmFXtHHpaxQziHY0nz3FrOIsl7zUVt
# 5Wsz2BiTK5Ks8aGSoXVjA48D7gDnVMmacjYffIJaxADFZZZhGZsEJQJnQsYPg0Zs
# 7p+XuiMgkMuwmQjMlqmh72DztswVbHx9Xb4u7TjPHqPyOKQDERIrGMELgD+ii9FP
# +aGCF7AwghesBgorBgEEAYI3AwMBMYIXnDCCF5gGCSqGSIb3DQEHAqCCF4kwgheF
# AgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFFMIIB
# QQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCCwWBETwCtJhpvIB2a0
# hkWnUoN0xPbF/r6mD1q36V7ARQIGaojahmVZGBMyMDI2MDgyNzA2MzAzNy40NzJa
# MASAAgH0oIHZpIHWMIHTMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0
# ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjo0MDFBLTA1RTAtRDk0NzElMCMG
# A1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaCCEf4wggcoMIIFEKAD
# AgECAhMzAAACGV6y2FR19LGNAAEAAAIZMA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29m
# dCBUaW1lLVN0YW1wIFBDQSAyMDEwMB4XDTI1MDgxNDE4NDgyNloXDTI2MTExMzE4
# NDgyNlowgdMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTAr
# BgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUG
# A1UECxMeblNoaWVsZCBUU1MgRVNOOjQwMUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxN
# aWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOC
# Ag8AMIICCgKCAgEApqFIyUkzIyxpL3Q03WmLuy4G9YIUScznhKr+cHOT+/u7Parx
# I96gxxb1WrWuAxB8qjGLfsbImx8V3ouK1nUcf+R/nsnXas5/iTgV/Tl3QTRGT0De
# uXBNbpHqc+wC1NiTyA76gLnirvSBEoBzlrpNQFEnuwdbPLCLpTS3KWSCu5J02b+R
# FWR/kcFzVxnhoE3gIaeURtrGKGBZGKLBXvqggkDENtKkvtvRT32xLvAvL/RpReu5
# z18ZojCs72ZSoa74Dy8YbaWsDm3OZOpJRZxZsPKCHZ6xNqgFKf0xNHj0t9v0Q3W+
# 2z5gAVaasJJCvR52Sl0XJ2AOf3l0LSetXgUA5gD5IQ1RvEslTmNnSouTrGID3D1n
# jY7mBu0puiIdPK2jK/1Weef2+YR4cQpWQkeBZmXidh9AuWdlwxKQL15LJ6K2dw8y
# /t/PBhmLyt6QAf0CepWRdgZnMytVAUuWHwlZRV9JLY7aX8D55eL9+cOLpX3bGNOm
# N24UpIW8qtZaqXaesFvIOW23JNLhaaQVvObr1eu7GE/5Mn43e+/DbtdYl/bLP2IQ
# 1xYEJdSbcUkDFfW3KlZEh+nBKDtaRnNRkbgIgxIbKdT38OKQwZ/aA4uSsiAg6nEP
# iWBHGuytIo5wU75M5VdjhEqqTHfXYu8BJi6GTzvWT+9ekfMXezqCkksxaG8CAwEA
# AaOCAUkwggFFMB0GA1UdDgQWBBSAaOo5HWatNzqZn1IF1fcD6nr3ITAfBgNVHSME
# GDAWgBSfpxVdAF5iXYP05dJlpxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1l
# LVN0YW1wJTIwUENBJTIwMjAxMCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsG
# AQUFBzAChlBodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01p
# Y3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMB
# Af8EAjAAMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDAN
# BgkqhkiG9w0BAQsFAAOCAgEAXxzVZLLXBFfoCCCTiY7MHXdb7civJSTfrHYJC5Ok
# 2NN75NpzTMT9V2TcIQjfQ3AFUbh1NBAYtMUuwxC6D4ceEXG5lXAnbvkC9YjeLVDR
# yImXYYmft7z+Qpl9t3C/8a0tiqnOz8Ue8/DYLtMTgvWMnsqLNjILDaImOfnHI36T
# LCjGFe8RYLXGdCUdOLlfAdMGePxSTA3TAAOc+GQbmPWjrguLWbxvnl3NVjRvrBZV
# kxFMoVZH0f7qGwDOShjpnv5nYnQ48ufL0uBz52RbPGdX4Fv9+UGOrBprmcHzmIut
# FtJec2Y4kujNtTK2wBGgWscEOVhFiaVdje8VLJ7MVNKE5TmsuGM3jTLr1nuR5AFG
# s3UKkP7g3cQD4cHK7XdLiTm7e606QJ+WqeQsADYE9dvU9wIUbI9Dl4UcIErFw+FH
# aWSTrkfJ4SvLmhKnl5khhpJ1sF3z6e1BxepUliXHqzRLiHWihWIWESF8IHElF3PO
# xbP4VJqHBiYvaXMV0SyRgwoD6zXddbUnX9WR6JL2BlqAjjHxINwelsp/VhxAWThz
# uMA58LxvE/VAzjfFF4Wm7a1ZALmJVw3oL/s/uxo1Op4tcT+hfZ9uN1htC1JN4DuR
# qFfLttjuoAmUQobO5zUFRzvCn8Ck/hiO+bzR15sqkjlxLMyMjpkc/ef4SUUikD46
# 8vUwggdxMIIFWaADAgECAhMzAAAAFcXna54Cm0mZAAAAAAAVMA0GCSqGSIb3DQEB
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
# ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjo0MDFBLTA1RTAtRDk0NzElMCMG
# A1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIa
# AxUAMXYp/Wqqdyb0enigrLfxl0InAz6ggYMwgYCkfjB8MQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1T
# dGFtcCBQQ0EgMjAxMDANBgkqhkiG9w0BAQsFAAIFAO458AIwIhgPMjAyNjA4MjYy
# MzA2NDJaGA8yMDI2MDgyNzIzMDY0MlowdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA
# 7jnwAgIBADAKAgEAAgIb9wIB/zAHAgEAAgIS+jAKAgUA7jtBggIBADA2BgorBgEE
# AYRZCgQCMSgwJjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYag
# MA0GCSqGSIb3DQEBCwUAA4IBAQC4B5wWvFe5Oy7FHWas9gU606npG+e/ULoi9fOV
# vezxBSIdOR0sbK80pZJojkt/71d5VMzvDvm4s+Z7fEaut8SgsQvcm+OtSqqsIhbZ
# QXYrEuS+XOmXEe3+gpDoFkMqlSnsHv9pqfQwUSGs17hYtz+HZSlRZ0bI823sccSV
# yyCXQFQh37mCMaETf4mrzbF7RejgcPVjprlrsFSwRsjXkM7ObJyXG+L8LTWYjZXp
# 8l/GGpGv4bumWEpbQF7Fg2/Esfxd5RRc/UkCwQjvsjixpQver9ZsfOqJXXWNobQS
# 1nbxBvfEIAPmdHrPElNRcrX8NOhJqToW9XGu/VOqawich6+nMYIEDTCCBAkCAQEw
# gZMwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcT
# B1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UE
# AxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAIZXrLYVHX0sY0A
# AQAAAhkwDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0B
# CRABBDAvBgkqhkiG9w0BCQQxIgQgzdigJM3hTiHOIpeB3mtfxz0ntxU1sJamr8Cl
# kaO4aK0wgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCDckX633E1y1EF32V18
# zQcrsgjzI9+3Le7mlvk2OebthjCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1w
# IFBDQSAyMDEwAhMzAAACGV6y2FR19LGNAAEAAAIZMCIEIAtOcsPk5vguHBXbI50i
# krOBEuK3R9Rf07Q1wMtdkE12MA0GCSqGSIb3DQEBCwUABIICAAPoW9q56h8urqUr
# jGwV16xulh8UVdLlt6Ebd8sP4hLZ5kIf7UHtgD6Y5T48p5Vcxp5KFbWbyqoz5Jgv
# qUVnzKdoW6PEPSMI4Mb7qrWtItPdLGj8IkAc8/n1hFqvyz2LJsSk5dJLmZV754lb
# WYbZI2OphPEwcBLWsO/221NjevtLJih9eYLj+Xun5PPCAmDq346NiFQanG8fJEoj
# ROlaPufuLSj7Qqaf8/tFoFOGm5+BuGHksQlcJBbuJwDvdbPgfwS4/AfrAYE0iKHn
# 4rYLdL+YgGitX1yEd8CCbHU3vqvT8su5qvTgVKHAcKwmmBl5CfQN3MYg0n/ZpPVn
# x0lOsx4srAuYIkbU0weoUPXKYRAZJqoi/p+nySmkx03uAJ65qL8SMauEhNlIsODj
# aXd+pjXQChUOAp2MgZQpNA9/hndkUKwC2/SUcuGhtzdRFcOZccszHBNpFtiCZB3T
# ClNP68Jz1NK4EVYRP20mmL54+AoxF3iuIEn8NtZ7ycxDEONXNwvWY8as8YqE+rfg
# d5r5nqN1rbA6zgLNebUOaH0nkufG/JZ4SDIgY7ckSFv8tDklBCSouf4nz55+OLQi
# dtUe9VHy0SVYg3Rr/FlFpqDCuYGZrOcwtnkH7Lh1o2RzAfQVte9ifl/b9prRVYB2
# U41ppum1e7TearHFIRWkKPvzRZuW
# SIG # End signature block
