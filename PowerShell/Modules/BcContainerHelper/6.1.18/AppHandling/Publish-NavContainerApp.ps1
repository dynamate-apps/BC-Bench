<# 
 .Synopsis
  Publish App to a NAV/BC Container
 .Description
  Copies the appFile to the container if necessary
  Creates a session to the container and runs the CmdLet Publish-NavApp in the container
 .Parameter containerName
  Name of the container in which you want to publish an app
 .Parameter appFile
  Path of the app you want to publish  
 .Parameter skipVerification
  Include this parameter if the app you want to publish is not signed
 .Parameter ignoreIfAppExists
  Include this parameter if you want to ignore the error if the app already is published/installed
 .Parameter sync
  Include this parameter if you want to synchronize the app after publishing
 .Parameter syncMode
  Specify Add, Clean or Development based on how you want to synchronize the database schema. Default is Add
 .Parameter install
  Include this parameter if you want to install the app after publishing
 .Parameter upgrade
  Include this parameter if you want to upgrade the app after publishing. if no upgrade is necessary then its just installed instead.
 .Parameter tenant
  If you specify the install switch, then you can specify the tenant in which you want to install the app
 .Parameter packageType
  Specify Extension or SymbolsOnly based on which package you want to publish
 .Parameter scope
  Specify Global or Tenant based on how you want to publish the package. Default is Global
 .Parameter useDevEndpoint
  Specify the useDevEndpoint switch if you want to publish using the Dev Endpoint (like VS Code). This allows VS Code to re-publish.
 .Parameter credential
  Specify the credentials for the admin user if you use DevEndpoint and authentication is set to UserPassword
 .Parameter language
  Specify language version that is used for installing the app. The value must be a valid culture name for a language in Business Central, such as en-US or da-DK. If the specified language does not exist on the Business Central Server instance, then en-US is used.
 .Parameter includeOnlyAppIds
  Array of AppIds. If specified, then include Only Apps in the specified AppFile array or archive which is contained in this Array and their dependencies
 .Parameter excludeRuntimePackages
  If specified, then runtime packages will be excluded
 .Parameter copyInstalledAppsToFolder
  If specified, the installed apps will be copied to this folder in addition to being installed in the container
 .Parameter replaceDependencies
  With this parameter, you can specify a hashtable, describring that the specified dependencies in the apps being published should be replaced
 .Parameter internalsVisibleTo
  An Array of hashtable, containing id, name and publisher of an app, which should be added to internals Visible to
 .Parameter showMyCode
  With this parameter you can change or check ShowMyCode in the app file. Check will throw an error if ShowMyCode is False.
 .Parameter PublisherAzureActiveDirectoryTenantId
  AAD Tenant of the publisher to ensure access to keyvault (unless publisher check is disables in server config)
 .Parameter bcAuthContext
  Authorization Context created by New-BcAuthContext. By specifying BcAuthContext and environment, the function will publish the app to the online Business Central Environment specified
 .Parameter environment
  Environment to use for publishing
 .Example
  Publish-BcContainerApp -appFile c:\temp\myapp.app
 .Example
  Publish-BcContainerApp -containerName test2 -appFile c:\temp\myapp.app -skipVerification
 .Example
  Publish-BcContainerApp -containerName test2 -appFile c:\temp\myapp.app -install -sync
 .Example
  Publish-BcContainerApp -containerName test2 -appFile c:\temp\myapp.app -skipVerification -install -sync -tenant mytenant
 .Example
  Publish-BcContainerApp -containerName test2 -appFile c:\temp\myapp.app -install -sync -replaceDependencies @{ "437dbf0e-84ff-417a-965d-ed2bb9650972" = @{ "id" = "88b7902e-1655-4e7b-812e-ee9f0667b01b"; "name" = "MyBaseApp"; "publisher" = "Freddy Kristiansen"; "minversion" = "1.0.0.0" }}
#>
function Publish-BcContainerApp {
    Param (
        [string] $containerName = "",
        [Parameter(Mandatory=$true)]
        $appFile,
        [switch] $skipVerification,
        [switch] $ignoreIfAppExists,
        [switch] $sync,
        [Parameter(Mandatory=$false)]
        [ValidateSet('Add','Clean','Development','ForceSync')]
        [string] $syncMode,
        [switch] $install,
        [switch] $upgrade,
        [Parameter(Mandatory=$false)]
        [string] $tenant = "default",
        [ValidateSet('Extension','SymbolsOnly')]
        [string] $packageType = 'Extension',
        [Parameter(Mandatory=$false)]
        [ValidateSet('Global','Tenant')]
        [string] $scope,
        [switch] $useDevEndpoint,
        [pscredential] $credential,
        [string] $language = "",
        [string[]] $includeOnlyAppIds = @(),
        [string] $copyInstalledAppsToFolder = "",
        [hashtable] $replaceDependencies = $null,
        [hashtable[]] $internalsVisibleTo = $null,
        [ValidateSet('Ignore','True','False','Check')]
        [string] $ShowMyCode = "Ignore",
        [switch] $replacePackageId,
        [string] $PublisherAzureActiveDirectoryTenantId,
        [Hashtable] $bcAuthContext,
        [string] $environment,
        [switch] $checkAlreadyInstalled,
        [ValidateSet('default','ignore','strict')]
        [string] $dependencyPublishingOption = "default",
        [switch] $excludeRuntimePackages
    )

$telemetryScope = InitTelemetryScope -name $MyInvocation.InvocationName -parameterValues $PSBoundParameters -includeParameters @()
try {

    Add-Type -AssemblyName System.Net.Http

    if ($containerName -eq "" -and (!($bcAuthContext -and $environment))) {
        $containerName = $bcContainerHelperConfig.defaultContainerName
    }
    $installedApps = @()
    if ($containerName) {
        $customconfig = Get-BcContainerServerConfiguration -ContainerName $containerName
        $appFolder = Join-Path $bcContainerHelperConfig.hostHelperFolder "Extensions\$containerName\$([guid]::NewGuid().ToString())"
        if ($appFile -is [string] -and $appFile.Startswith(':')) {
            New-Item $appFolder -ItemType Directory | Out-Null
            $destFile = Join-Path $appFolder ([System.IO.Path]::GetFileName($appFile.SubString(1)).Replace('*','').Replace('?',''))
            Invoke-ScriptInBcContainer -containerName $containerName -scriptblock { Param($appFile, $destFile)
                Copy-Item -Path $appFile -Destination $destFile -Force
            } -argumentList (Get-BcContainerPath -containerName $containerName -path $appFile), (Get-BcContainerPath -containerName $containerName -path $destFile) | Out-Null
            $appFiles = @($destFile)
        }
        else {
            $appFiles = CopyAppFilesToFolder -appFiles $appFile -folder $appFolder
        }
        $navversion = Get-BcContainerNavversion -containerOrImageName $containerName
        $version = [System.Version]($navversion.split('-')[0])
        $force = ($version.Major -ge 14)
        if ($checkAlreadyInstalled) {
            # Get Installed apps (if UseDevEndpoint is specified, only get global apps)
            $installedApps = Get-BcContainerAppInfo -containerName $containerName -installedOnly | Where-Object { (-not $useDevEndpoint.IsPresent) -or ($_.Scope -eq 'Global') } | ForEach-Object {
                @{ "id" = "$($_.appId)"; "publisher" = $_.publisher; "name" = $_.name; "version" = $_.Version }
            }
        }
    }
    else {
        $appFolder = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
        $appFiles = CopyAppFilesToFolder -appFiles $appFile -folder $appFolder
        $force = $true
        if ($checkAlreadyInstalled) {
            # Get Installed apps (if UseDevEndpoint is specified, only get global apps or PTEs)
            # PublishedAs is either "Global", " PTE" or " Dev" (with leading space)
            $installedApps = Get-BcInstalledExtensions -bcAuthContext $bcAuthContext -environment $environment
            Write-Host "InstalledApps:"
            $installedApps | ForEach-Object { Write-Host "- $($_.id) $($_.displayName) $($_.VersionMajor).$($_.VersionMinor).$($_.VersionBuild).$($_.VersionRevision) '$($_.PublishedAs)' $($_.IsInstalled) $($_.publisher)" }
            $installedApps = $installedApps | Where-Object { $_.IsInstalled -and ((-not $useDevEndpoint.IsPresent) -or ($_.PublishedAs -ne ' Dev')) } | ForEach-Object {
                @{ "id" = $_.id; "publisher" = $_.publisher; "name" = $_.displayName; "version" = [System.Version]::new($_.VersionMajor,$_.VersionMinor,$_.VersionBuild,$_.VersionRevision) }
            }
        }
    }

    try {
        $appFiles = @(Sort-AppFilesByDependencies -containerName $containerName -appFiles $appFiles -includeOnlyAppIds $includeOnlyAppIds -excludeInstalledApps $installedApps -excludeRuntimePackages:$excludeRuntimePackages -WarningAction SilentlyContinue)
        $appFiles | Where-Object { $_ } | ForEach-Object {
            $appFile = $_

            if ($ShowMyCode -ne "Ignore" -or $replaceDependencies -or $replacePackageId -or $internalsVisibleTo) {
                Write-Host "Checking dependencies in $appFile"
                Replace-DependenciesInAppFile -Path $appFile -replaceDependencies $replaceDependencies -internalsVisibleTo $internalsVisibleTo -ShowMyCode $ShowMyCode -replacePackageId:$replacePackageId
            }

            if ($copyInstalledAppsToFolder) {
                if (!(Test-Path -Path $copyInstalledAppsToFolder)) {
                    New-Item -Path $copyInstalledAppsToFolder -ItemType Directory | Out-Null
                }
                Write-Host "Copy $appFile to $copyInstalledAppsToFolder"
                Copy-Item -Path $appFile -Destination $copyInstalledAppsToFolder -force
            }
        
            if ($bcAuthContext -and $environment) {
                $useDevEndpoint = $true
            }
            elseif ($customconfig.ServerInstance -eq "") {
                throw "You cannot publish an app to a filesOnly container. Specify bcAuthContext and environemnt to publish to an online tenant"
            }

            if ($useDevEndpoint) {
        
                if ($scope -eq "Global") {
                    throw "You cannot publish to global scope using the dev. endpoint"
                }
        
                $sslVerificationDisabled = $false
                if ($bcAuthContext -and $environment) {
                    $bcAuthContext = Renew-BcAuthContext -bcAuthContext $bcAuthContext
                    $devServerUrl = "$($bcContainerHelperConfig.apiBaseUrl.TrimEnd('/'))/v2.0/$environment"
                    $tenant = ""
                    $handler = New-Object System.Net.Http.HttpClientHandler
                    $HttpClient = [System.Net.Http.HttpClient]::new($handler)
                    $HttpClient.DefaultRequestHeaders.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", $bcAuthContext.AccessToken)
                    $HttpClient.Timeout = [System.Threading.Timeout]::InfiniteTimeSpan
                    $HttpClient.DefaultRequestHeaders.ExpectContinue = $false
                }
                else {
                    $handler = New-Object System.Net.Http.HttpClientHandler
                    if ($customConfig.DeveloperServicesSSLEnabled -eq "true") {
                        $protocol = "https://"
                    }
                    else {
                        $protocol = "http://"
                    }
                    $sslVerificationDisabled = ($protocol -eq "https://")
                    if ($sslVerificationDisabled) {
                        Write-Host "Disabling SSL Verification on HttpClient"
                        [SslVerification]::DisableSsl($handler)
                    }
                    if ($customConfig.ClientServicesCredentialType -eq "Windows") {
                        $handler.UseDefaultCredentials = $true
                    }
                    $HttpClient = [System.Net.Http.HttpClient]::new($handler)
                    if ($customConfig.ClientServicesCredentialType -eq "NavUserPassword") {
                        if (!($credential)) {
                            throw "You need to specify credentials when you are not using Windows Authentication"
                        }
                        $pair = ("$($Credential.UserName):"+[System.Runtime.InteropServices.Marshal]::PtrToStringBSTR([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($credential.Password)))
                        $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
                        $base64 = [System.Convert]::ToBase64String($bytes)
                        $HttpClient.DefaultRequestHeaders.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue("Basic", $base64);
                    }
                    $HttpClient.Timeout = [System.Threading.Timeout]::InfiniteTimeSpan
                    $HttpClient.DefaultRequestHeaders.ExpectContinue = $false
                
                    $ip = Get-BcContainerIpAddress -containerName $containerName
                    if ($ip) {
                        $devServerUrl = "$($protocol)$($ip):$($customConfig.DeveloperServicesPort)/$($customConfig.ServerInstance)"
                    }
                    else {
                        $devServerUrl = "$($protocol)$($containerName):$($customConfig.DeveloperServicesPort)/$($customConfig.ServerInstance)"
                    }
                }
                
                $schemaUpdateMode = "synchronize"
                if ($syncMode -eq "Clean") {
                    $schemaUpdateMode = "recreate";
                }
                elseif ($syncMode -eq "ForceSync") {
                    $schemaUpdateMode = "forcesync"
                }
                $url = "$devServerUrl/dev/apps?SchemaUpdateMode=$schemaUpdateMode"
                if ($PSBoundParameters.ContainsKey('dependencyPublishingOption')) {
                    $url += "&DependencyPublishingOption=$dependencyPublishingOption"
                }
                if ($tenant) {
                    $url += "&tenant=$tenant"
                }
                
                $appName = [System.IO.Path]::GetFileName($appFile)
                
                $multipartContent = [System.Net.Http.MultipartFormDataContent]::new()
                $FileStream = [System.IO.FileStream]::new($appFile, [System.IO.FileMode]::Open)
                try {
                    $fileHeader = [System.Net.Http.Headers.ContentDispositionHeaderValue]::new("form-data")
                    $fileHeader.Name = "$AppName"
                    $fileHeader.FileName = "$appName"
                    $fileHeader.FileNameStar = "$appName"
                    $fileContent = [System.Net.Http.StreamContent]::new($FileStream)
                    $fileContent.Headers.ContentDisposition = $fileHeader
                    $multipartContent.Add($fileContent)
                    Write-Host "Publishing $appName to $url"
                    $result = $HttpClient.PostAsync($url, $multipartContent).GetAwaiter().GetResult()
                    if (!$result.IsSuccessStatusCode) {
                        $message = "Status Code $($result.StatusCode) : $($result.ReasonPhrase)"
                        try {
                            $resultMsg = $result.Content.ReadAsStringAsync().Result
                            try {
                                $json = $resultMsg | ConvertFrom-Json
                                $message += "`n$($json.Message)"
                            }
                            catch {
                                $message += "`n$resultMsg"
                            }
                        }
                        catch {}
                        throw $message
                    }
                }
                catch {
                    GetExtendedErrorMessage -errorRecord $_ | Out-Host
                    throw
                }
                finally {
                    $FileStream.Close()
                }
            
                if ($bcContainerHelperConfig.NoOfSecondsToSleepAfterPublishBcContainerApp -gt 0) {
                    # Avoid race condition
                    Start-Sleep -Seconds $bcContainerHelperConfig.NoOfSecondsToSleepAfterPublishBcContainerApp
                }
            }
            else {
                [ScriptBlock] $scriptblock = { Param($appFile, $skipVerification, $sync, $install, $upgrade, $tenant, $syncMode, $packageType, $scope, $language, $PublisherAzureActiveDirectoryTenantId, $force, $ignoreIfAppExists, $version)
                    $prevPreference = $ProgressPreference; $ProgressPreference = "SilentlyContinue"
                    $publishArgs = @{ "packageType" = $packageType }
                    if ($scope) {
                        $publishArgs += @{ "Scope" = $scope }
                        if ($scope -eq "Tenant") {
                            $publishArgs += @{ "Tenant" = $tenant }
                        }
                    }
                    if ($PublisherAzureActiveDirectoryTenantId) {
                        $publishArgs += @{ "PublisherAzureActiveDirectoryTenantId" = $PublisherAzureActiveDirectoryTenantId }
                    }
                    if ($force) {
                        $publishArgs += @{ "Force" = $true }
                    }
                    
                    $publishIt = $true
                    if ($ignoreIfAppExists) {
                        $navAppInfo = Get-NAVAppInfo -Path $appFile
                        $addArg = @{
                            "tenantSpecificProperties" = $true
                            "tenant" = $tenant
                        }
                        if ($packageType -eq "SymbolsOnly") {
                            $addArg = @{ "SymbolsOnly" = $true }
                        }
                        $appInfo = (Get-NAVAppInfo -ServerInstance $serverInstance -Name $navAppInfo.Name -Publisher $navAppInfo.Publisher @addArg) | Where-Object { $_.Version -ge $navAppInfo.Version } | Sort-Object { $_.Version } | Select-Object -Last 1
                        if ($appInfo) {
                            $publishIt = $false
                            Write-Host "$($navAppInfo.Name) version $($appInfo.Version) is already published"
                            if ($appInfo.IsInstalled) {
                                $sync = ($appinfo.SyncState -ne "Synced")
                                $install = $false
                                $upgrade = $false
                                Write-Host "$($navAppInfo.Name) version $($appInfo.Version) is already installed"
                            }
                        }
                    }
            
                    if ($publishIt) {
                        Write-Host "Publishing $appFile"
                        $publishArgs += @{"serverInstance" = $serverInstance; "Path" = $appFile; "SkipVerification" = $skipVerification.IsPresent}
                        if ($PSVersionTable.PSVersion.Major -lt 7 -and $version.Major -ge 24) {
                            # GIANT HACK AHEAD...
                            # To cope with this issue https://github.com/microsoft/navcontainerhelper/issues/3591 where the PS5 bridge to PS7 hangs when calling Publish-NavApp directly
                            # and due to https://github.com/microsoft/navcontainerhelper/issues/3575 and https://github.com/PowerShell/PowerShell/issues/23982 we cannot use -usepwsh:$true
                            $command = '$serviceTierFolder = (Get-Item ''C:\Program Files\Microsoft Dynamics NAV\*\Service'').FullName;Import-Module (Join-Path $serviceTierFolder ''Admin\Microsoft.Dynamics.Nav.Management.psm1'');Import-Module (Join-Path $serviceTierFolder ''Admin\Microsoft.BusinessCentral.Management.psd1'');Import-Module (Join-Path $serviceTierFolder ''Admin\Microsoft.BusinessCentral.Apps.Management.dll'');'
                            $command += "Publish-NavApp $(($publishArgs.Keys | ForEach-Object { $v=$publishArgs."$_"; if($v -is [boolean]){"-$($_):`$$($publishArgs."$_")"}elseif($v -is [string]){"-$($_):'$($publishArgs."$_")'"}else{"-$($_):$($publishArgs."$_")"} }) -join ' ')"
                            pwsh -command "$($command.Replace('"','""'))" | Out-Host
                            if ($LASTEXITCODE -ne 0) {
                                throw "Publish-NavApp failed"
                            }
                        }
                        else {
                            Publish-NavApp @publishArgs
                        }
                    }
        
                    if ($sync -or $install -or $upgrade) {
        
                        $navAppInfo = Get-NAVAppInfo -Path $appFile
                        $appPublisher = $navAppInfo.Publisher
                        $appName = $navAppInfo.Name
                        $appVersion = $navAppInfo.Version
        
                        $syncArgs = @{}
                        if ($syncMode) {
                            $syncArgs += @{ "Mode" = $syncMode }
                        }
            
                        if ($sync) {
                            Write-Host "Synchronizing $appName on tenant $tenant"
                            Sync-NavTenant -ServerInstance $ServerInstance -Tenant $tenant -Force
                            Sync-NavApp -ServerInstance $ServerInstance -Publisher $appPublisher -Name $appName -Version $appVersion -Tenant $tenant @syncArgs -force -WarningAction Ignore
                        }

                        if($upgrade -and $install){
                            $navAppInfoFromDb = Get-NAVAppInfo -ServerInstance $ServerInstance -Publisher $appPublisher -Name $appName -Version $appVersion -Tenant $tenant -TenantSpecificProperties
                            if($null -eq $navAppInfoFromDb.ExtensionDataVersion -or $navAppInfoFromDb.ExtensionDataVersion -eq  $navAppInfoFromDb.Version){
                                $upgrade = $false
                            } else {
                                $install = $false
                            }
                        }

                        $installArgs = @{}
                        if ($language) {
                            $installArgs += @{ "Language" = $language }
                        }
                        if ($force) {
                            $installArgs += @{ "Force" = $true }
                        }
                        if ($install) {
                            Write-Host "Installing $appName on tenant $tenant"
                            Install-NavApp -ServerInstance $ServerInstance -Publisher $appPublisher -Name $appName -Version $appVersion -Tenant $tenant @installArgs
                        }
                        if ($upgrade) {
                            Write-Host "Upgrading $appName on tenant $tenant"
                            Start-NavAppDataUpgrade -ServerInstance $ServerInstance -Publisher $appPublisher -Name $appName -Version $appVersion -Tenant $tenant @installArgs
                        }
                    }
                    $ProgressPreference = $prevPreference
                }
                Invoke-ScriptInBcContainer `
                    -containerName $containerName `
                    -ScriptBlock $scriptblock `
                    -ArgumentList (Get-BcContainerPath -containerName $containerName -path $appFile), $skipVerification, $sync, $install, $upgrade, $tenant, $syncMode, $packageType, $scope, $language, $PublisherAzureActiveDirectoryTenantId, $force, $ignoreIfAppExists, $version
            }
            Write-Host -ForegroundColor Green "App $([System.IO.Path]::GetFileName($appFile)) successfully published"
        }
    }
    finally {
        Remove-Item $appFolder -Recurse -Force -ErrorAction SilentlyContinue
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
Set-Alias -Name Publish-NavContainerApp -Value Publish-BcContainerApp
Export-ModuleMember -Function Publish-BcContainerApp -Alias Publish-NavContainerApp

# SIG # Begin signature block
# MIInSQYJKoZIhvcNAQcCoIInOjCCJzYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCxSw5vRjNGJKBH
# nM5L8BTn0lNK44PzcRVAesU2oHAcFKCCDLowggX1MIID3aADAgECAhMzAAACHU0Z
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
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIJEMcZA3
# l8FnXwKj94B7jZFkoh01c4s73r+ujo7cCI4rMEIGCisGAQQBgjcCAQwxNDAyoBSA
# EgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20w
# DQYJKoZIhvcNAQEBBQAEggEAICEkVV01wsd5yrGO179RDJ6u8TeXnGMxUagNEjuO
# EQu/kEDzj1ZYXMJiFqf1P6OM8CV5PIv0T2CIcwcSj8WwQhdG4T/xjj771sVVBnTJ
# bBQ38xFJkU+yTSZQxLq/nhvYs2fyF5Lm09ZVu43GkBsNbY8vtV83oJGs51t8V4R1
# wLMP/EkFw9NY1qcTle7Rl5w0gcQlsaD8yw/CGt1msP60/2Q28oL25X7Su/ap2tr2
# ffilcW3+jYzCoAdXuq4ETyLL2b5ce2cnuHMdIklEgtoGUBRJ56C6io/Uimw34tZg
# ZxwJaV6CxuEeaQ7nHYleqK1hT/Zi+VO5KFXZHfvz8QIcNaGCF5cwgheTBgorBgEE
# AYI3AwMBMYIXgzCCF38GCSqGSIb3DQEHAqCCF3AwghdsAgEDMQ8wDQYJYIZIAWUD
# BAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGEWQoD
# ATAxMA0GCWCGSAFlAwQCAQUABCB6+ZQSPwnfW0J1x7ewCN+abovfcDWaLmSiY3kk
# 6HiArgIGaoSBPZOOGBMyMDI2MDgyNzA2MjkzNS43NjJaMASAAgH0oIHRpIHOMIHL
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxN
# aWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRT
# UyBFU046OTIwMC0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFNlcnZpY2WgghHtMIIHIDCCBQigAwIBAgITMwAAAiNP2WAkU8/+KwABAAAC
# IzANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAe
# Fw0yNjAyMTkxOTM5NTdaFw0yNzA1MTcxOTM5NTdaMIHLMQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmlj
# YSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046OTIwMC0wNUUw
# LUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIi
# MA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCK6Q2nk5WUdKzSCSafp+UjUARs
# WxHKS63rJhFC/zSabFumTBuaJ0QNrmqevub5Db7fSj5qtwwKnjIO92+HXF67192f
# ujL7DFot5WEj/AtEZ/XrzFHimKlN1h6gEQwP5I67wizaPW5ZzSBNpaLBg5oHvASP
# OZtwdNUoZ+DQKF3hJl1KZuoIlVK+qi7cLjgak6s5oOZcRCMrKnuC3aoVa6wRDbYv
# KUuj7rkFx9KO0PsHJ/k+LnZMggRheh4AVdawyh+oOzKPjlQGUNfSeWUgym2U9CLa
# 8tt0mQX4DxDz6+ram50gj1oAfyQ6TQ7r96PADFOKBgaU7+cpHnaZG89dTegQ6ydB
# RGIycOw1dRX2eKDRRzziK3cn0WaIm/7OeGsyQKjIzEQuUTDv0Jj/9zQ7truLOOpJ
# D98BJVOK7je84Sz2hb3HvUST7j1j2N8peD6olkpFHR/1Z8Jz4F+mkrUF7MmPAirY
# HRzunbIg3HrDMNwFYN7yBkDA4/VMo9CY0y9oGUoq2yjbCwTibz9VYl93nB3QQiTC
# T9nW3M+TOWB+PMrZpExq1BSHmKPzIqehKqrUDoM33PK+dEKwpYLET6uXq4HuQRMX
# WT//sPubUnQAaaUMfQhAZSy23HtxwtN3eK9+T4wCav2wQFt57eUOwUW5/DCzMF9t
# ua5He1hNvgcAXaiG1wIDAQABo4IBSTCCAUUwHQYDVR0OBBYEFNbAh89v29nPY9bw
# Qb1QYCzxVgeXMB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1Ud
# HwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3Js
# L01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggr
# BgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNv
# bS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIw
# MTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgw
# DgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUAA4ICAQCHQwe7z5tp4NZwAf1c
# B+4c9J4svw3P6WqGBMxtqznS6DdzUzStXHCaPZhM41g1iKHNnmcnLjwLujOEaNjh
# SnUDiAZqQjW5ZapOBxgc7Egghh9k+r78qWAe3rJ4QohBbhSGdZtKivTRaeRqmnhy
# 8+ThrKhzCeEwaarXJimZwSpdQQUDbheWHeyAxASqultd5KO0m/UFvO03tfepqGXA
# 4tCg/WGECwKqOjJzpRAfPIB6y1HyVrk+vmL5rpEbTwwLOtX7WxFGG8+cYLk9HjaD
# kxraA/HYlKQRx1sdza+w/gulLwgOnByRJKF2rr8M7FNIlwoi6ywFpaNc8A7HewaG
# jgw/tfcE260I1XekGluANI9HnONOYWlI7BKBQbWE2teo6vsQ1Vg8B8rTZSePVdmX
# L1PPqqs3KVdFKM5kYocPCDM+6VL32IV96sESf2T7DjxanpCg2D2UYj4Z1i7cy8U1
# LLDGg55KWs4af2RRBjH2MulHgAmW5obKxiZCDQjRaroJ2XElXUhigE9BzvhCFbT/
# HDY2vpVpl5HnSpcCSxmL5i5lIT/xbAQMI7Luh75Xrm+IslfFWOGOGMlCp+24qEJE
# glXEP7xwsolNdBNndXihhyIefVGlI1DR7xGELiJrk8ifVWYo9XEbEXv/lbvp6F2R
# 2UsnweWckvq0y1HWnLHDqH6dPjCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkA
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
# T3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjkyMDAtMDVFMC1E
# OTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEw
# BwYFKw4DAhoDFQA4RWFs+kTiZnoZiAj1BtYj8zCNaqCBgzCBgKR+MHwxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29m
# dCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBCwUAAgUA7jozHjAiGA8y
# MDI2MDgyNzAzNTMwMloYDzIwMjYwODI4MDM1MzAyWjB3MD0GCisGAQQBhFkKBAEx
# LzAtMAoCBQDuOjMeAgEAMAoCAQACAgqNAgH/MAcCAQACAhJMMAoCBQDuO4SeAgEA
# MDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAI
# AgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBAEwmvVg0hiKvDydXVxoI9oS1f6dS
# JOdCFlTCTEFmXy6G6e4ceUMGfXiTJjycapxg67u/tg4qnYGylbMlArwn4Ab2rBrM
# 8sGlyuuPhwl/YX/CY1ldL09MxvmwRrqVnj8op7LHU48qoNZfL2kQN3xUdN/ZLP3N
# WgeBGv23ibQWw2d07QyT0dRpX1Ah+MHOmljeo5V6TVvnq7PifoKPns1K6jgh5qYz
# PD5hIsqj7hC2tsNsNB7KILYvrFp/MLcHaHc8PVgPqfbc8uuOgJafnhwByZeXps2L
# sclMbDzSX+dTKUIHOPGfPmSZwOsCgw/a5xaudP76OYCWgxl4TmB8bUoJbOUxggQN
# MIIECQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQ
# MA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
# MSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAiNP
# 2WAkU8/+KwABAAACIzANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0G
# CyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCBZF+zae4d47bWxb8zG83gqPyxF
# MTAXfKKFxlDHRKIWIjCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EIJbwMywR
# bvcGiynjnwjAqcaD47yYvebKZRAvtEAR5u6zMIGYMIGApH4wfDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgUENBIDIwMTACEzMAAAIjT9lgJFPP/isAAQAAAiMwIgQg79c37+vX
# 6VweJ8kpZo4KTEB2JWJLbeVyLqYHxq5AsoEwDQYJKoZIhvcNAQELBQAEggIAM1dZ
# 503In6H5HLozjR7PmA5q41ki6HijuQzQ4D2JAntowSuMzIwV9zdy325poixAH7Aa
# Cu9ISmlMWUUR1opb4+4/aixLALiH51Y8GPaWQOjNXFdd7gEon0M8WKIPqaGqJ4Mb
# +BBKZXzPLzOIFs53SmNPQAeQbBWiSe16m0CB1zS0EJKhBm/Cgw3PV42tbK0YgHlf
# UVzMiwZj9N1yFZ/F72Se9JwX2OjCyz0EIesayEtk+H0O6zG1DaLGe58Tm1+kd9G8
# 9MFjLgLfia3YRNvyWbMzRkXWej+b2pebkN2PpGX44qdEM/VBEsViRGd4Ougr5Rme
# jJJAgnyaEaNXvcfyAfzbQaug5slBAFZXyZoegRaA+udjFJteIZY77I9ZCBSNCIyD
# rl7FFnTbqxaFqNz8AxkBk3ueQO4eyxRZnrVqaTMLkNGGTwhn1VQawrmwsCvGh7V2
# Hq0G25+/KmYCNKsqAJVs1yv5NszEteBsL2/YzpVnI8I7Y9MjA07809TabVj6aMmf
# qoLlpTRyl4QNpE4YM1wrsMDT2N8/O+sL8YbaxM3lPMc2yL0vCblNrlkwvP1B7abK
# OVb6jK1MPVSRfANyf9kuOvDlu++qCAvte60ML60bgG9bHM1unPS7YYCslEyncXN9
# 0C3vj4nwJ+gCIYh+IhJ3JN9jyK5N+vHh8JVNFzo=
# SIG # End signature block
