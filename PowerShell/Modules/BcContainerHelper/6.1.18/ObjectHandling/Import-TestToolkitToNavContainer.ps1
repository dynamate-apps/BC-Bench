<# 
 .Synopsis
  Import TestToolkit to BC Container
 .Description
  Import the objects from the TestToolkit to the BC Container.
  The TestToolkit objects are already in a folder on the NAV on Docker image from version 0.0.4.3
 .Parameter containerName
  Name of the container for which you want to enter a session
 .Parameter sqlCredential
  For 14.x containers and earlier. Credentials for the SQL admin user if using NavUserPassword authentication. User will be prompted if not provided
 .Parameter credential
  For 15.x containers and later. Credentials for the admin user if using NavUserPassword authentication. User will be prompted if not provided
 .Parameter includeTestLibrariesOnly
  Only import TestLibrary Apps (do not import Test Apps)
 .Parameter includeTestFrameworkOnly
  Only import TestFramework Apps (do not import Test Apps or Test Library apps)
 .Parameter includeTestRunnerOnly
  Only import Test Runner (do not import Test Apps, Test Framework Apps or Test Library apps)
 .Parameter testToolkitCountry
  Only import TestToolkit objects for a specific country.
  You must specify the country code that is used in the TestToolkit object name (e.g. CA, US, MX, etc.).
  This parameter only needs to be used in the event there are multiple country-specific sets of objects in the TestToolkit folder.
 .Parameter doNotUpdateSymbols
  Add this switch to avoid updating symbols when importing the test toolkit
 .Parameter ImportAction
  Specifies the import action. Default is Overwrite
 .Parameter scope
  Specify Global or Tenant based on how you want to publish the package. Default is Global
 .Parameter tenant
  Tenant in which you want to install the test framework (default is default)
 .Parameter useDevEndpoint
  Specify the useDevEndpoint switch if you want to publish using the Dev Endpoint (like VS Code). This allows VS Code to re-publish.
 .Parameter doNotUseRuntimePackages
  Include the doNotUseRuntimePackages switch if you do not want to cache and use the test apps as runtime packages (only 15.x containers)
 .Parameter replaceDependencies
  With this parameter, you can specify a hashtable, describring that the specified dependencies in the apps being published should be replaced
 .Parameter bcAuthContext
  Authorization Context created by New-BcAuthContext. By specifying BcAuthContext and environment, the function will import test toolkit to the online Business Central Environment specified
  Only Test Runner and Test Framework are/will be available in the online Business Central environment
 .Parameter environment
  Environment in which you want to import test toolkit.
 .Parameter appSymbolsFolder
  Folder where the app symbols should be stored when using compilerfolder
 .Example
  Import-TestToolkitToBcContainer -containerName test2
  .Example
  Import-TestToolkitToBcContainer -containerName test2 -testToolkitCountry US
  .Example
  Import-TestToolkitToBcContainer -containerName test2 -includeTestLibrariesOnly -replaceDependencies @{ "437dbf0e-84ff-417a-965d-ed2bb9650972" = @{ "id" = "88b7902e-1655-4e7b-812e-ee9f0667b01b"; "name" = "MyBaseApp"; "publisher" = "Freddy Kristiansen"; "minversion" = "1.0.0.0" }}
#>
function Import-TestToolkitToBcContainer {
    Param (
        [string] $containerName = $bcContainerHelperConfig.defaultContainerName,
        [string] $compilerFolder = '',
        [PSCredential] $sqlCredential = $null,
        [PSCredential] $credential = $null,
        [switch] $includeTestLibrariesOnly,
        [switch] $includeTestFrameworkOnly,
        [switch] $includeTestRunnerOnly,
        [switch] $includePerformanceToolkit,
        [string] $testToolkitCountry,
        [switch] $doNotUpdateSymbols,
        [ValidateSet("Overwrite","Skip")]
        [string] $ImportAction = "Overwrite",
        [switch] $doNotUseRuntimePackages = $true,
        [Parameter(Mandatory=$false)]
        [ValidateSet('Global','Tenant')]
        [string] $scope,
        [string] $tenant = "default",
        [switch] $useDevEndpoint,
        [hashtable] $replaceDependencies = $null,
        [Hashtable] $bcAuthContext,
        [string] $environment,
        [string] $appSymbolsFolder
    )

$telemetryScope = InitTelemetryScope `
                    -name $MyInvocation.InvocationName `
                    -parameterValues $PSBoundParameters `
                    -includeParameters @("containerName","includeTestLibrariesOnly","includeTestFrameworkOnly","includeTestRunnerOnly","includePerformanceToolkit","testToolkitCountry")
try {

    if ($replaceDependencies) {
        $doNotUseRuntimePackages = $true
    }
    if (!($scope)) {
        if ($useDevEndpoint) {
            $scope = "tenant"
        }
        else {
            $scope = "global"
        }
    }

    if ($bcAuthContext -and $environment) {
        $appFiles = GetTestToolkitApps -containerName $containerName -compilerFolder $compilerFolder -includeTestRunnerOnly:$includeTestRunnerOnly -includeTestFrameworkOnly:$includeTestFrameworkOnly -includeTestLibrariesOnly:$includeTestLibrariesOnly -includePerformanceToolkit:$includePerformanceToolkit
        $installedApps = Get-BcPublishedApps -bcAuthContext $bcauthcontext -environment $environment | Where-Object { $_.state -eq "installed" }
        $appFiles | ForEach-Object {
            if ($compilerFolder) {
                $appInfo = Get-AppJsonFromAppFile -appFile $_
                $appVersion = [Version]$appInfo.Version
                $appId = $appInfo.Id
            }
            else {
                $appInfo = Invoke-ScriptInBCContainer -containerName $containerName -scriptblock { Param($appFile)
                    Get-NAVAppInfo -Path $appFile
                } -argumentList $_ | Where-Object { $_ -isnot [System.String] }
                $appVersion = $appInfo.Version
                $appId = $appInfo.AppId
            }

            $targetVersion = ""
            if ($appVersion.Major -eq 18 -and $appVersion.Minor -eq 0) {
                $targetVersion = "18.0.23013.23913"
            }
            $installedApp = $installedApps | Where-Object { $_.id -eq $appId -and (($targetVersion -eq "") -or ([Version]($_.version) -ge [Version]$targetVersion)) }
            if ($installedApp) {
                Write-Host "Skipping app '$($installedApp.name)' as it is already installed"
            }
            else {
                Install-BcAppFromAppSource -bcAuthContext $bcauthcontext -environment $environment -appId $appId -appVersion $targetVersion -acceptIsvEula -installOrUpdateNeededDependencies
            }
        }
        Write-Host -ForegroundColor Green "TestToolkit successfully published"
    }
    elseif ($compilerFolder) {
        $appFiles = GetTestToolkitApps -compilerFolder $compilerFolder -includeTestRunnerOnly:$includeTestRunnerOnly -includeTestFrameworkOnly:$includeTestFrameworkOnly -includeTestLibrariesOnly:$includeTestLibrariesOnly -includePerformanceToolkit:$includePerformanceToolkit
        $appFiles | ForEach-Object {
            Copy-Item -Path $_ -Destination $appSymbolsFolder -Force
        }
    }
    else {
        $inspect = docker inspect $containerName | ConvertFrom-Json
        if ($inspect.Config.Labels.psobject.Properties.Match('maintainer').Count -eq 0 -or $inspect.Config.Labels.maintainer -ne "Dynamics SMB") {
            throw "Container $containerName is not a Business Central container"
        }
        [System.Version]$version = $inspect.Config.Labels.version
        $country = $inspect.Config.Labels.country
    
        $isBcSandbox = $inspect.Config.Env | Where-Object { $_ -eq "IsBcSandbox=Y" }
    
        $customConfig = Get-BcContainerServerConfiguration -ContainerName $containerName

        $doNotUpdateSymbols = $doNotUpdateSymbols -or (!(([bool]($customConfig.PSobject.Properties.name -eq "EnableSymbolLoadingAtServerStartup")) -and $customConfig.EnableSymbolLoadingAtServerStartup -eq "True"))
    
        $generateSymbols = $false
        if ($version.Major -eq 14 -and !$doNotUpdateSymbols -and $customConfig.ClientServicesCredentialType -ne "Windows") {
            $generateSymbols = $true
            $doNotUpdateSymbols = $true
        }

        if ($version.Major -ge 15) {
            if ($version -lt [Version]("15.0.35528.0")) {
                throw "Container $containerName (platform version $version) doesn't support the Test Toolkit yet, you need a laster version"
            }
    
            Invoke-ScriptInBcContainer -containerName $containerName -scriptblock {
                $mockAssembliesPath = "C:\Test Assemblies\Mock Assemblies"
                if (Test-Path $mockAssembliesPath) {
                    $serviceTierAddInsFolder = (Get-Item "C:\Program Files\Microsoft Dynamics NAV\*\Service\Add-ins").FullName
                    if (!(Test-Path (Join-Path $serviceTierAddInsFolder "Mock Assemblies"))) {
                        new-item -itemtype symboliclink -path $serviceTierAddInsFolder -name "Mock Assemblies" -value $mockAssembliesPath | Out-Null
                        Set-NavServerInstance $serverInstance -restart
                        while (Get-NavTenant $serverInstance | Where-Object { $_.State -eq "Mounting" }) {
                            Start-Sleep -Seconds 1
                        }
                    }
                }
            }
    
            $appFiles = GetTestToolkitApps -containerName $containerName -includeTestRunnerOnly:$includeTestRunnerOnly -includeTestFrameworkOnly:$includeTestFrameworkOnly -includeTestLibrariesOnly:$includeTestLibrariesOnly -includePerformanceToolkit:$includePerformanceToolkit

            $publishParams = @{}
            if ($version.Major -ge 18 -and $version.Major -lt 20 -and ($appFiles | Where-Object { $name = [System.IO.Path]::GetFileName($_); ($name -eq "Microsoft_Performance Toolkit.app" -or ($name -like "Microsoft_Performance Toolkit_*.*.*.*.app" -and $name -notlike "*.runtime.app")) })) {
                $BCPTLogEntryAPIsrc = Join-Path $PSScriptRoot "..\AppHandling\BCPTLogEntryAPI"
                $appJson = [System.IO.File]::ReadAllLines((Join-Path $BCPTLogEntryAPIsrc "app.json")) | ConvertFrom-Json
                $internalsVisibleTo = @{ "id" = $appJson.id; "name" = $appJson.name; "publisher" = $appjson.publisher }
                $publishParams += @{
                    "internalsVisibleTo" = $internalsVisibleTo
                    "replacePackageId" = $true
                }

                Get-BcContainerAppInfo -containerName $containerName | Where-Object { $_.Dependencies | Where-Object { $_ -like 'Performance Toolkit, Microsoft,*' } } | ForEach-Object {
                    UnPublish-BcContainerApp -containerName $containerName -publisher $_.Publisher -name $_.Name -version $_.Version -unInstall -force
                }
                
                UnPublish-BcContainerApp -containerName $containerName -publisher "microsoft" -name "Performance Toolkit" -unInstall -force
            }
    
            if (!$doNotUseRuntimePackages) {
                if ($isBcSandbox) {
                    $folderPrefix = "sandbox"
                }
                else {
                    $folderPrefix = "onprem"
                }
                $applicationsPath = Join-Path $bcContainerHelperConfig.hostHelperFolder "Extensions\$folderPrefix-Applications-$Version-$country"
                if (!(Test-Path $applicationsPath)) {
                    New-Item -Path $applicationsPath -ItemType Directory | Out-Null
                }
            }
    
            $appFiles | ForEach-Object {
                $appFile = $_
                if (!$doNotUseRuntimePackages) {
                    $name = [System.IO.Path]::GetFileName($appFile)
                    $runtimeAppFile = "$applicationsPath\$($name.Replace('.app','.runtime.app'))"
                    $useRuntimeApp = $false
                    if (Test-Path $runtimeAppFile) {
                        if ((Get-Item $runtimeAppFile).Length -eq 0) {
                            Remove-Item $runtimeAppFile -force
                        }
                        else {
                            $appFile = $runtimeAppFile
                            $useRuntimeApp = $true
                        }
                    }
                }
    
                $tenantAppInfo = Invoke-ScriptInBCContainer -containerName $containerName -scriptblock { Param($appFile, $tenant)
                    $navAppInfo = Get-NAVAppInfo -Path $appFile
                    (Get-NAVAppInfo -ServerInstance $serverInstance -Name $navAppInfo.Name -Publisher $navAppInfo.Publisher -Version $navAppInfo.Version -tenant $tenant -tenantSpecificProperties)
                } -argumentList $appFile, $tenant | Where-Object { $_ -isnot [System.String] }

                if ($tenantAppInfo) {
                    if ($tenantAppInfo.IsInstalled) {
                        Write-Host "Skipping app '$appFile' as it is already installed"
                    }
                    else {
                        Sync-BcContainerApp -containerName $containerName -tenant $tenant -appName $tenantAppInfo.Name -appPublisher $tenantAppInfo.Publisher -appVersion $tenantAppInfo.Version -Force
                        Install-BcContainerApp -containerName $containerName -tenant $tenant -appName $tenantAppInfo.Name -appPublisher $tenantAppInfo.Publisher -appVersion $tenantAppInfo.Version -Force
                    }
                }
                else {
                    $name = [System.IO.Path]::GetFileName($appFile)
                    if ( $name -eq "Microsoft_Performance Toolkit.app" -or ($name -like "Microsoft_Performance Toolkit_*.*.*.*.app" -and $name -notlike "*.runtime.app") ) {
                        Publish-BcContainerApp -containerName $containerName @publishParams -appFile ":$appFile" -skipVerification -sync -install -scope $scope -useDevEndpoint:$useDevEndpoint -replaceDependencies $replaceDependencies -credential $credential -tenant $tenant
                    }
                    else {
                        Publish-BcContainerApp -containerName $containerName -appFile ":$appFile" -skipVerification -sync -install -scope $scope -useDevEndpoint:$useDevEndpoint -replaceDependencies $replaceDependencies -credential $credential -tenant $tenant
                    }
        
                    if (!$doNotUseRuntimePackages -and !$useRuntimeApp) {
                        Invoke-ScriptInBCContainer -containerName $containerName -scriptblock { Param($appFile, $tenant, $runtimeAppFile)
                            
                            $navAppInfo = Get-NAVAppInfo -Path $appFile
                            $appPublisher = $navAppInfo.Publisher
                            $appName = $navAppInfo.Name
                            $appVersion = $navAppInfo.Version
        
                            Get-NavAppRuntimePackage -ServerInstance $serverInstance -Publisher $appPublisher -Name $appName -version $appVersion -Path $runtimeAppFile -Tenant $tenant
                        } -argumentList $appFile, $tenant, (Get-BcContainerPath -containerName $containerName -path $runtimeAppFile -throw)
                    }
                }
            }
            Write-Host -ForegroundColor Green "TestToolkit successfully imported"
        }
        else {
            $sqlCredential = Get-DefaultSqlCredential -containerName $containerName -sqlCredential $sqlCredential -doNotAskForCredential
            Invoke-ScriptInBcContainer -containerName $containerName -ScriptBlock { Param([PSCredential]$sqlCredential, $includeTestLibrariesOnly, $testToolkitCountry, $doNotUpdateSymbols, $ImportAction)
            
                $customConfigFile = Join-Path (Get-Item "C:\Program Files\Microsoft Dynamics NAV\*\Service").FullName "CustomSettings.config"
                [xml]$customConfig = [System.IO.File]::ReadAllText($customConfigFile)
                $databaseServer = $customConfig.SelectSingleNode("//appSettings/add[@key='DatabaseServer']").Value
                $databaseInstance = $customConfig.SelectSingleNode("//appSettings/add[@key='DatabaseInstance']").Value
                $databaseName = $customConfig.SelectSingleNode("//appSettings/add[@key='DatabaseName']").Value
                $managementServicesPort = $customConfig.SelectSingleNode("//appSettings/add[@key='ManagementServicesPort']").Value
                if ($databaseInstance) { $databaseServer += "\$databaseInstance" }
           
                $params = @{}
                if ($sqlCredential) {
                    $params = @{ 'Username' = $sqlCredential.UserName; 'Password' = ([System.Runtime.InteropServices.Marshal]::PtrToStringBSTR([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sqlCredential.Password))) }
                }
                if ($testToolkitCountry) {
                    $fileFilter = "*.$testToolkitCountry.fob"
                }
                else {
                    $fileFilter = "*.fob"
                }
                Get-ChildItem -Path "C:\TestToolKit" -Filter $fileFilter | ForEach-Object { 
                    if (!$includeTestLibrariesOnly -or $_.Name.StartsWith("CALTestLibraries")) {
                        $objectsFile = $_.FullName
                        Write-Host "Importing Objects from $objectsFile (container path)"
                        $databaseServerParameter = $databaseServer
        
                        if (!$doNotUpdateSymbols) {
                            Write-Host "Generating Symbols while importing"
                            # HACK: Parameter insertion...
                            # generatesymbolreference is not supported by Import-NAVApplicationObject yet
                            # insert an extra parameter for the finsql command by splitting the filter property
                            $databaseServerParameter = '",generatesymbolreference=1,ServerName="'+$databaseServer
                        }
            
                        Import-NAVApplicationObject @params -Path $objectsFile `
                                                    -DatabaseName $databaseName `
                                                    -DatabaseServer $databaseServerParameter `
                                                    -ImportAction $ImportAction `
                                                    -SynchronizeSchemaChanges No `
                                                    -NavServerName localhost `
                                                    -NavServerInstance $ServerInstance `
                                                    -NavServerManagementPort "$managementServicesPort" `
                                                    -Confirm:$false
            
                    }
                }
        
                # Sync after all objects hav been imported
                Get-NAVTenant -ServerInstance $ServerInstance | Sync-NavTenant -Mode ForceSync -Force
        
            } -ArgumentList $sqlCredential, ($includeTestLibrariesOnly -or $includeTestFrameworkOnly), $testToolkitCountry, $doNotUpdateSymbols, $ImportAction
        
            if ($generateSymbols) {
                Write-Host "Generating symbols"
                Generate-SymbolsInNavContainer -containerName $containerName -sqlCredential $sqlCredential
            }
            Write-Host -ForegroundColor Green "TestToolkit successfully imported"
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
Set-Alias -Name Import-TestToolkitToNavContainer -Value Import-TestToolkitToBcContainer
Export-ModuleMember -Function Import-TestToolkitToBcContainer -Alias Import-TestToolkitToNavContainer

# SIG # Begin signature block
# MIInbgYJKoZIhvcNAQcCoIInXzCCJ1sCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDiotD0lo/Yhn3T
# 1C7H6KQD2M6AVHVlsp+md04FTjdtmKCCDMkwggYEMIID7KADAgECAhMzAAACHPrN
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
# Ql0v4q8J/AUmQN5W4n101cY2L4A7GTQG1h32HHAvfQESWP0xghn7MIIZ9wIBATBu
# MFcxCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# KDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMjQCEzMAAAIc
# +s3Fm+gvfsQAAAAAAhwwDQYJYIZIAWUDBAIBBQCgga4wGQYJKoZIhvcNAQkDMQwG
# CisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZI
# hvcNAQkEMSIEIDkNLjUqDrAG+ZIwmcUQZewdjV5vepdQpHvRy9mlWj8AMEIGCisG
# AQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEAs8UaB+BS4Mt/4CzHLt7b
# I+toZVOVRr/rwFFW/63cwB+AfGbVqiwKVXNZya93YNChhkfQ7XK4WKajfPU2CYmn
# ESISjj5MoN+1ZEwS+BkCr9GT5tj9azUDv+q3u17ulBBGEXXxDh6VK3Nids+3Himu
# bSdDyaXB3SGWTqkSPyKSA+Wi93aGFmoC7nLBZeVmwg4oJo/H2OWWlSDjIZjgwwnU
# 0lvhLHEPRVulqic7B1Q2CFx1S7lj0DX0a8TCIyz/0E12ohFmabGu4GYnnHn10g1X
# OguoStsLxXCvsiPHv9HZBG2r2i+WVVv8sSsIdVmhk/cvfaoWVGyZnQqw91Nsg4zS
# i6GCF60wghepBgorBgEEAYI3AwMBMYIXmTCCF5UGCSqGSIb3DQEHAqCCF4YwgheC
# AgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFFMIIB
# QQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCDAumDv5iHOxZqSVMsR
# FgUc4MyBfvAl7VqGdtIANLc2HQIGaomzDM4qGBMyMDI2MDgyNzA2MjkzNi42MDJa
# MASAAgH0oIHZpIHWMIHTMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0
# ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjo1NTFBLTA1RTAtRDk0NzElMCMG
# A1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaCCEfswggcoMIIFEKAD
# AgECAhMzAAACG9CyuAJn93LPAAEAAAIbMA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29m
# dCBUaW1lLVN0YW1wIFBDQSAyMDEwMB4XDTI1MDgxNDE4NDgzMFoXDTI2MTExMzE4
# NDgzMFowgdMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTAr
# BgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUG
# A1UECxMeblNoaWVsZCBUU1MgRVNOOjU1MUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxN
# aWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOC
# Ag8AMIICCgKCAgEAjsWd52ZZkzB5Xe5g/l2GsOjAz30sg6jVxfFJV+w4xIDVyaI3
# LO8bIpmzYul3AZHg50UIQ8PrSRZGpQqFkRNu+o3YKJ4g2uGYBRksHnHYR0uVSCQg
# 58ThkYyeplGX3oAvGRVuPIpQtAiTsR76A/gdoU7HDwEbb73bJwTyrbKHhR+WaMy9
# DQHI4k5Qo4+bZDs0kj76bvhJvdGU+S8zxQBp7UAhjJnFqKxIusSITE7zCCR422EL
# hkhVVOFqK2w6h1MAvILe76hxRIcPj0SBL2r8O9tx5njU4+tg2rAdU153pmyhqazd
# pUccYBE9wDRFUd/e9CoWx7TdnUicB+Mai7RT6qse7e5aGqX1B7bnj/ZHvrrfF+BJ
# EIlS9iDXAUgekvXZ+FZmjvLwP+dN+0/crh++r4e8FknF7EX6IJfnmNeDN/68Z59k
# baJ1f+P5mnKYfydCeZmxrGpS0taWkDk36D3jPVZflvxrc+1rhCIlM5v9agLEFI12
# QiBTfpOBOBr3AGCPk+eH0+latjQajug+2/BD12qb82500LQytUWT2ota/HYnRgSv
# 1jvZ0/dml1FsxWYzOnCrjfdB/7N6pNySt4vn+PGN6dFLim7kxos+B9WfQPezJi3f
# uKyyDAB9zSHPj1Zu8nZfecZJ9um4zj7DFgvJXTDTnG5qlG4ZdbFRa/rrfzkCAwEA
# AaOCAUkwggFFMB0GA1UdDgQWBBS2vp93/lxLppNK8OkauJ2AvNmIUDAfBgNVHSME
# GDAWgBSfpxVdAF5iXYP05dJlpxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1l
# LVN0YW1wJTIwUENBJTIwMjAxMCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsG
# AQUFBzAChlBodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01p
# Y3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMB
# Af8EAjAAMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDAN
# BgkqhkiG9w0BAQsFAAOCAgEAZkU1XxQD4OTM3GTht32TXShIfPBoMfSsFsBQqFOZ
# qLJOxyJOllIBFpmpvOtGNPkC5Z8ldG8aCpvgFNo/jDWeT5FiW53dAj9KnZxpsQ3P
# f5fRzSGHRcxEMOdXIVzDJwcZUX0cjfxna7ydNv8eXB/Xk6G6SyrR2OH6S1LHMW11
# m3UvKF+eLjIPl45rximuDCoEd+ad0lOAXA5/vZOKN5n/ePYeP0LRchZX0Q6H8n/Z
# mSPMlbli3MO851Q09RmT/ZGHa+/Fdy+WLDrwcYykV9mUy/4TbwKw6FtdR6ZPHxMd
# Ii1pk8Y2mC/GzCq0LCsH0uTFeQ6Q7Nc3MRmER/3mLWUhbaWHgX1FbYchvR22b+Bu
# p+YPR5Q/0BhaaAN6AIBfcGs+u/nJoIByyZKA8cTyCmnUI/4vW6D4vywg3XBFf4f2
# DwFHy/evsC+58KMl+k2wa05X2kK0T/bCPLhaov9ZXyobawfNOLYGiauKT2FWvbwZ
# zHIFCTxjBww6Pt5uRvCE/jnUcf/xhlOGMn6iKO9Xt49vZTE2SfIBk/34iLTRBJ6H
# 7aGPTTQnza3OfWu1/dRycC6Wl5ons3PjnGXTSKSxXllJPmg6R/ulGonP/UCYoJ6m
# N+EXjfyDLPXLqsr91+VTG1rYzRCjPwBFAHv4EIwaE0ajCrf75eUGI3+oXU0UP6rl
# oZ8wggdxMIIFWaADAgECAhMzAAAAFcXna54Cm0mZAAAAAAAVMA0GCSqGSIb3DQEB
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
# RNGQ8cirOoo6CGJ/2XBjU02N7oJtpQUQwXEGahC0HVUzWLOhcGbyoYIDVjCCAj4C
# AQEwggEBoYHZpIHWMIHTMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0
# ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjo1NTFBLTA1RTAtRDk0NzElMCMG
# A1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIa
# AxUAhoV6r49M4GBd41K1RYB1Z0f4zuCggYMwgYCkfjB8MQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1T
# dGFtcCBQQ0EgMjAxMDANBgkqhkiG9w0BAQsFAAIFAO46H9UwIhgPMjAyNjA4Mjcw
# MjMwNDVaGA8yMDI2MDgyODAyMzA0NVowdDA6BgorBgEEAYRZCgQBMSwwKjAKAgUA
# 7jof1QIBADAHAgEAAgITszAHAgEAAgISuTAKAgUA7jtxVQIBADA2BgorBgEEAYRZ
# CgQCMSgwJjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0G
# CSqGSIb3DQEBCwUAA4IBAQBEU2jxUxxrZde6txcqjj2OfnCfGTfxgpIJBh7Xl3gT
# cHOkOJMAjkqDPvB0FrTPyTj3H+NH5fug21DCj9kGnsHJanhyW2PWg3m2WleCpv00
# NcS4w1vL7nzrJkNeuG0qlQFo3gGzSdRC2DOtZtAVADwpvDEWlEJ8r05AIB7jeEif
# AYTG3pTdv+6m1S9Qz3u9z45tf+xn4hBCWyr2mmT2+HoAZkeaLd488xl8W3TZTkcf
# /3Zm+zvsoHFDl3donmPPxhDnGtyd/uJ8ECTz1xzsFRyIuYxDdhrtXbNbhl0PEEIW
# QH9Sgg7+MeJIzW0CXJv35FleyEu9tkxf0d3gsSdqhLIDMYIEDTCCBAkCAQEwgZMw
# fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMd
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAIb0LK4Amf3cs8AAQAA
# AhswDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRAB
# BDAvBgkqhkiG9w0BCQQxIgQgUaRCDkS0SRSgwdqWE6DapNh0kQWNXmwXXvx/t9rx
# +agwgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCAwJRSVuD2jmMcQCFXdLuJA
# wDpUVNZ6bc6dfJU83Q2LgDCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBD
# QSAyMDEwAhMzAAACG9CyuAJn93LPAAEAAAIbMCIEILpX2zOE3yRmSrEbYyB6Qah4
# staWGvdg0j8vh4PpXwO4MA0GCSqGSIb3DQEBCwUABIICADJhuTp8bigNyTyWBLLQ
# j5YN5FGYKrAgOGMrKlhZSWpWtNWDzKwLMBVopHdIqC+6WyrGRlH9QHVk79GaguSX
# Ug8F1UGLN1rAPez1rgWJAm9QAhKryrhDPjMYJQucb8AmXm8aBEnXyFzDS+9bETSU
# vbphk1cnpnJ+e89GT+lVKZCRXd0tqlqZdMMU9Xy+lDySMCDYeg+F5V41QwYTCIO7
# rJM1qrl1h+NuYsnsAmx104YG1h3nzK/dawAXDmodd8KgzvGL3TFpY+Afs1dqef46
# Xu8ne6sYWPAkL/WzBujyNvcm+RlDQfLD5Y48oZvW8EUequv8CQwfBa+XiUtYpOmG
# vzMQJZ6aT4CYbgYizpknYeYels/MEp5mn5YEiL6d2OEXDjSiMhpQcnDw9FGqbhWg
# 52UuNu3xnKwiIak4IeXHWTZfyYd5IHCYst8aTCy+/lpD8vMcUZ/3AcXUzerTZK+d
# 65V907D5ErEyzijP/dLC8Q2ac2f2vTOfxTuxP/KTSdP7iFgnVm0l/2b9y3Qzl3QE
# gFiE8Dbe5ugCF2aij8weMAQYB5iYBTmzfyHk1QUWDtLtnrJZIIx0DaJPUpt4DNxG
# CfqxUegh4KDNlZmpsLx3CyFsa2x+vblBQ3ajqMI0+WOpB2cnPF6mslzRallrxJBV
# BXADuSMb586rSw/GzINkpaLx
# SIG # End signature block
