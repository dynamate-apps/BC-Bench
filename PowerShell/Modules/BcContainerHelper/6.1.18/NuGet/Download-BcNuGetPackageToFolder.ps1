<# 
 .Synopsis
  PROOF OF CONCEPT PREVIEW: Download Apps from Business Central NuGet Package to folder
 .Description
  Download Apps from Business Central NuGet Package to folder
 .PARAMETER nuGetServerUrl
  NuGet Server URL
  Default: https://api.nuget.org/v3/index.json
 .PARAMETER nuGetToken
  NuGet Token for authenticated access to the NuGet Server
  If not specified, the NuGet Server is accessed anonymously (and needs to support this)
 .PARAMETER packageName
  Package Name to search for.
  This can be the full name or a partial name with wildcards.
  If more than one package is found, matching the name, an error is thrown.
 .PARAMETER version
  Package Version, following the nuget versioning rules
  https://learn.microsoft.com/en-us/nuget/concepts/package-versioning#version-ranges
 .PARAMETER select
  Select the package to download if more than one package is found matching the name and version
  - Earliest: Select the earliest version
  - EarliestMatching: Select the earliest version matching the already installed dependencies
  - Latest: Select the latest version (default)
  - LatestMatching: Select the latest version matching the already installed dependencies
  - Exact: Select the exact version
  - Any: Select the first version found
 .PARAMETER folder
  Folder where the apps are copied to
 .PARAMETER copyInstalledAppsToFolder
  If specified, apps are also copied to this folder
 .PARAMETER installedPlatform
  Version of the installed platform
 .PARAMETER installedCountry
  Country of the installed application. installedCountry is used to determine if the NuGet package is compatible with the installed application localization
 .PARAMETER installedApps
  List of installed apps
  Format is an array of PSCustomObjects with properties Name, Publisher, id and Version
 .PARAMETER downloadDependencies
  Specifies which dependencies to download
  Allowed values are:
    - all: Download all dependencies
    - own: Download only dependencies that has the same publisher as the package
    - allButMicrosoft: Download all dependencies except packages with publisher Microsoft
    - allButApplication: Download all dependencies except the Application and Platform packages (Microsoft.Application and Microsoft.Platform)
    - allButPlatform: Download all dependencies except the Platform package (Microsoft.Platform)
    - none: Do not download any dependencies
 .PARAMETER allowPrerelease
  Include prerelease versions in the search
#>
Function Download-BcNuGetPackageToFolder {
    Param(
        [Parameter(Mandatory=$false)]
        [string] $nuGetServerUrl = "",
        [Parameter(Mandatory=$false)]
        [string] $nuGetToken = "",
        [Parameter(Mandatory=$true)]
        [string] $packageName,
        [Parameter(Mandatory=$false)]
        [string] $version = '0.0.0.0',
        [Parameter(Mandatory=$false)]
        [ValidateSet('Earliest','EarliestMatching','Latest','LatestMatching','Exact','Any')]
        [string] $select = 'Latest',
        [Parameter(Mandatory=$true)]
        [alias('appSymbolsFolder')]
        [string] $folder,
        [Parameter(Mandatory=$false)]
        [string] $copyInstalledAppsToFolder = "",
        [Parameter(Mandatory=$false)]
        [System.Version] $installedPlatform,
        [Parameter(Mandatory=$false)]
        [string] $installedCountry = '',
        [Parameter(Mandatory=$false)]
        [PSCustomObject[]] $installedApps = @(),
        [ValidateSet('all','own','allButMicrosoft','allButApplication','allButPlatform','none')]
        [string] $downloadDependencies = 'allButApplication',
        [switch] $allowPrerelease,
        [switch] $checkLocalVersion
    )

try {
    $returnValue = @()
    $findSelect = $select
    if ($select -eq 'LatestMatching') {
        $findSelect = 'AllDescending'
    }
    if ($select -eq 'EarliestMatching') {
        $findSelect = 'AllAscending'
    }
    if ($checkLocalVersion) {
        # Format Publisher.Name[.Country][.symbols][.AppId]
        if ($packageName -match '^(Microsoft)\.([^\.]+)(\.[^\.][^\.])?(\.symbols)?(\.[0-9A-Fa-f]{8}\-[0-9A-Fa-f]{4}\-[0-9A-Fa-f]{4}\-[0-9A-Fa-f]{4}\-[0-9A-Fa-f]{12})?$') {
            $publisher = $matches[1]
            $name = $matches[2]
            $countryPart = "$($matches[3])"
            $symbolsPart = "$($matches[4])"
            $appIdPart = "$($matches[5])"
            $checkPackageName = ''
            if ($name -ne 'Platform' -and $countryPart -eq '' -and $installedCountry -ne '') {
                $countryPart = ".$installedCountry"
                $checkPackageName = "$publisher.$name$countryPart$symbolsPart$appIdPart"
            }
            if ($checkPackageName -and $checkPackageName -ne $packageName) {
                $downloadedPackages = Download-BcNuGetPackageToFolder -nuGetServerUrl $nuGetServerUrl -nuGetToken $nuGetToken -packageName $checkPackageName -version $version -folder $folder -copyInstalledAppsToFolder $copyInstalledAppsToFolder -installedPlatform $installedPlatform -installedCountry $installedCountry -installedApps $installedApps -downloadDependencies $downloadDependencies -verbose:($VerbosePreference -eq 'Continue') -select $select -allowPrerelease:$allowPrerelease
                if ($downloadedPackages) {
                    return $downloadedPackages
                }
            }
            return Download-BcNuGetPackageToFolder -nuGetServerUrl $nuGetServerUrl -nuGetToken $nuGetToken -packageName $packageName -version $version -folder $folder -copyInstalledAppsToFolder $copyInstalledAppsToFolder -installedPlatform $installedPlatform -installedCountry $installedCountry -installedApps $installedApps -downloadDependencies $downloadDependencies -verbose:($VerbosePreference -eq 'Continue') -select $select -allowPrerelease:$allowPrerelease
        }
    }
    Write-Host "Looking for NuGet package $packageName version $version ($select match)"
    if ($packageName -match '^Microsoft\.Platform(\.symbols)?$') {
        if ($installedPlatform) {
            $existingPlatform = $installedPlatform
        }
        else {
            $existingPlatform = $installedApps | Where-Object { $_ -and $_.Name -eq 'Platform' } | Select-Object -ExpandProperty Version
        }
        if ($existingPlatform -and ([NuGetFeed]::IsVersionIncludedInRange($existingPlatform, $version))) {
            Write-Host "Microsoft.Platform version $existingPlatform is already available"
            return @()
        }
    }
    elseif ($packageName -match '^([^\.]+\.)?Application(\.[^\.]+)?(\.symbols)?$') {
        $installedApp = $installedApps | Where-Object { $_ -and $_.Name -eq 'Application' }
        if ($installedApp -and ([NuGetFeed]::IsVersionIncludedInRange($installedApp.Version, $version))) {
            Write-Host "Application version $($installedApp.Version) is already available"
            return @()
        }
    }
    elseif ($packageName -match '^([^\.]+)\.([^\.]+)(\.[^\.][^\.])?(\.symbols)?(\.[0-9A-Fa-f]{8}\-[0-9A-Fa-f]{4}\-[0-9A-Fa-f]{4}\-[0-9A-Fa-f]{4}\-[0-9A-Fa-f]{12})?$') {
        $installedApp = $installedApps | Where-Object { $_ -and $_.id -and $packageName -like "*$($_.id)*" }
        if ($installedApp -and ([NuGetFeed]::IsVersionIncludedInRange($installedApp.Version, $version))) {
            Write-Host "$($installedApp.Name) from $($installedApp.publisher) version $($installedApp.Version) is already available (AppId=$($installedApp.id))"
            return @()
        }
    }
    if ($findselect -eq 'AllAscending' -or $findselect -eq 'AllDescending') {
        $nuGetVersions = Find-BcNugetPackage -nuGetServerUrl $nuGetServerUrl -nuGetToken $nuGetToken -packageName $packageName -version $version -verbose:($VerbosePreference -eq 'Continue') -select $findselect -allowPrerelease:($allowPrerelease.IsPresent)
    }
    else {
        $feed, $packageId, $packageVersion = Find-BcNugetPackage -nuGetServerUrl $nuGetServerUrl -nuGetToken $nuGetToken -packageName $packageName -version $version -verbose:($VerbosePreference -eq 'Continue') -select $findselect -allowPrerelease:($allowPrerelease.IsPresent)
        $nuGetVersions = @(@{"feed" = $feed; "packageId" = $packageId; "packageVersion" = $packageVersion })
    }
    foreach($nuGetVersion in $nuGetVersions) {
        $feed = $nuGetVersion.feed
        $packageId = $nuGetVersion.packageId
        $packageVersion = $nuGetVersion.packageVersion
        $returnValue = @()
        if (-not $feed) {
            Write-Host "No package found matching package name $($packageName) Version $($version)"
            break
        }
        else {
            Write-Host "Best match for package name $($packageName) Version $($version): $packageId Version $packageVersion from $($feed.Url)"
            $package = ''
            $packageSpec = $feed.DownloadPackageSpec($packageId, $packageVersion)
            
            if ($VerbosePreference -ne 'SilentlyContinue') {
                Write-Verbose "Package spec:"
                $packageSpec | ConvertTo-Json -Depth 10 | Write-Verbose
            }

            $appId = ''
            $appName = $packageSpec.name
            if ($packageSpec.id -match '^.*([0-9A-Fa-f]{8}\-[0-9A-Fa-f]{4}\-[0-9A-Fa-f]{4}\-[0-9A-Fa-f]{4}\-[0-9A-Fa-f]{12})$') {
                # If packageId ends in a GUID (AppID) then use the AppId for the packageId
                $appId = "$($matches[1])"
            }
            elseif ($packageSpec.id -like 'Microsoft.Platform*') {
                # If packageId starts with Microsoft.Platform then use the packageId for the packageId
                $appName = 'Platform'
            }
            $returnValue = @([PSCustomObject]@{
                "Publisher" = $packageSpec.authors
                "Name" = $appName
                "id" = $appId
                "Version" = $packageSpec.version
            })
            $dependenciesErr = ''
            $dependenciesToDownload = @()
            foreach($dependency in $packageSpec.dependencies) {
                if (-not $installedPlatform) {
                    $installedPlatform = $installedApps+$returnValue | Where-Object { $_ -and $_.Name -eq 'Platform' } | Select-Object -ExpandProperty Version
                }
                $dependencyVersion = $dependency.Version
                $dependencyId = $dependency.Id
                $dependencyCountry = ''
                $downloadIt = $false
                if ($dependencyId -match '^Microsoft\.Platform(\.symbols)?$') {
                    $dependencyPublisher = 'Microsoft'
                    # Dependency is to the platform
                    if ($installedPlatform) {
                        if (!([NuGetFeed]::IsVersionIncludedInRange($installedPlatform, $dependencyVersion))) {
                            # The NuGet package found isn't compatible with the installed platform
                            $dependenciesErr = "NuGet package $packageId (version $packageVersion) requires platform $dependencyVersion. You cannot install it on version $installedPlatform"
                        }
                        $downloadIt = $false
                    }
                    else {
                        $downloadIt = ($downloadDependencies -eq 'all')
                    }
                }
                elseif ($dependencyId -match '^([^\.]+\.)?Application(\.[^\.]+)?(\.symbols)?$') {
                    # Dependency is to the application
                    $dependencyPublisher = $matches[1].TrimEnd('.')
                    $dependencyCountry = "$($matches[2])".TrimStart('.')
                    $installedApp = $installedApps | Where-Object { $_ -and $_.Name -eq 'Application' }
                    if ($installedApp) {
                        if (!([NuGetFeed]::IsVersionIncludedInRange($installedApp.Version, $dependencyVersion))) {
                            $dependenciesErr = "NuGet package $packageId (version $packageVersion) requires application $dependencyVersion. You cannot install it on version $($installedApp.Version)"
                        }
                        $downloadIt = $false
                    }
                    else {
                        $downloadIt = ($downloadDependencies -eq 'all' -or $downloadDependencies -eq 'allButPlatform')
                    }
                }
                else {
                    $dependencyPublisher = ''
                    if ($dependencyId -match '^([^\.]+)\.([^\.]+)(\.[^\.][^\.])?(\.symbols)?\.?([0-9A-Fa-f]{8}\-[0-9A-Fa-f]{4}\-[0-9A-Fa-f]{4}\-[0-9A-Fa-f]{4}\-[0-9A-Fa-f]{12})?$') {
                        # Matches publisher.name[.country][.symbols][.appId] format (country section is only for microsoft apps)
                        $dependencyPublisher = $matches[1]
                        if ($dependencyPublisher -eq 'microsoft') {
                            $dependencyCountry = "$($matches[3])".TrimStart('.')
                        }
                        if ($Matches[5]) {
                            # If the dependencyId ends in a GUID (AppID) then use the AppId for the dependencyId
                            $dependencyId = "$($matches[5])"
                        }
                    }
                    $installedApp = $installedApps | Where-Object { $_ -and $_.id -and $dependencyId -like "*$($_.id)*" }  | Sort-Object -Property @{ "Expression" = "[System.Version]Version" } -Descending | Select-Object -First 1
                    if ($installedApp) {
                        # Dependency is already installed, check version number
                        if (!([NuGetFeed]::IsVersionIncludedInRange($installedApp.Version, $dependencyVersion))) {
                            # The version installed isn't compatible with the NuGet package found
                            $dependenciesErr = "Dependency $dependencyId is already installed with version $($installedApp.Version), which is not compatible with the version $dependencyVersion required by the NuGet package $packageId (version $packageVersion))"
                        }
                    }
                    elseif ($downloadDependencies -eq 'own') {
                        $downloadIt = ($dependencyPublisher -eq [NugetFeed]::Normalize($packageSpec.authors))
                    }
                    elseif ($downloadDependencies -eq 'allButMicrosoft') {
                        # Download if publisher isn't Microsoft (including if publisher is empty)
                        $downloadIt = ($dependencyPublisher -ne 'Microsoft')
                    }
                    elseif ($dependencyId -match '^([^\.]+)\.([^\.]+)\.runtime\-[0-9]+\-[0-9]+\-[0-9]+\-[0-9]+$') {
                        $downloadIt = $true
                    }
                    else {
                        $downloadIt = ($downloadDependencies -ne 'none')
                    }
                }
                # When downloading symbols, country will be symbols if no specific country is specified
                if ($dependencyCountry -eq 'symbols') {
                    $dependencyCountry = ''
                }
                if ($installedCountry -and $dependencyCountry -and ($installedCountry -ne $dependencyCountry)) {
                    # The NuGet package found isn't compatible with the installed application
                    Write-Host "NuGet package $packageId (version $packageVersion) requires $dependencyCountry application. You have $installedCountry application installed"
                }                   
                if ($dependenciesErr) {
                    if (@('LatestMatching', 'EarliestMatching') -notcontains $select) {
                        throw $dependenciesErr
                    }
                    else {
                        # If we are looking for the earliest/latest matching version, then we can try to find another version
                        Write-Host $dependenciesErr
                        $returnValue = @()
                        break
                    }
                }
                if ($downloadIt) {
                    $dependenciesToDownload += @( @{ "id" = $dependencyId; "version" = $dependencyVersion } )
                }
            }
            if ($dependenciesErr) {
                # If we are looking for the earliest/latest matching version, then we can try to find another version
                continue
            }
            
            # Download the package
            $package = $feed.DownloadPackage($packageId, $packageVersion)

            foreach ($dependency in $dependenciesToDownload) {
                # Download the dependencies of the package
                $dependencyVersion = $dependency.Version
                $dependencyId = $dependency.Id
                if ($dependencyVersion.StartsWith('[') -and $select -eq 'Exact') {
                    # Downloading Microsoft packages for a specific version
                    $dependencyVersion = $version
                }
                Write-Host -foregroundcolor Yellow "Downloading dependency $dependencyId version $dependencyVersion"
                $dependencyApps = Download-BcNuGetPackageToFolder -nuGetServerUrl $nuGetServerUrl -nuGetToken $nuGetToken -packageName $dependencyId -version $dependencyVersion -folder $package -copyInstalledAppsToFolder $copyInstalledAppsToFolder -installedPlatform $installedPlatform -installedCountry $installedCountry -installedApps @($installedApps + $returnValue) -downloadDependencies $downloadDependencies -verbose:($VerbosePreference -eq 'Continue') -select $select -allowPrerelease:$allowPrerelease -checkLocalVersion
                if ($dependencyApps) {
                    $returnValue += $dependencyApps
                }
                else {
                    Write-Host "WARNING: Dependency $dependencyId version $dependencyVersion cannot be found"
                }
            }

            if ($installedCountry -and (Test-Path (Join-Path $package $installedCountry) -PathType Container)) {
                # NuGet packages of Runtime packages might exist in different versions for different countries
                # The runtime package might contain C# invoke calls with different methodis for different countries
                # if the installedCountry doesn't have a special version, then the w1 version is used (= empty string)
                # If the package contains a country specific folder, then use that
                Write-Host "Using country specific folder $installedCountry"
                $appFiles = Get-Item -Path (Join-Path $package "$installedCountry/*.app")
            }
            else {
                $appFiles = Get-Item -Path (Join-Path $package "*.app")
            }

            foreach($appFile in $appFiles) {
                $targetFolders = @($folder)
                if ($copyInstalledAppsToFolder) {
                    $targetFolders += @($copyInstalledAppsToFolder)
                }
                $manifest = Get-AppJsonFromAppFile -appFile $appFile.FullName
                Write-Host "Found app file for package $($manifest.Name)"
                foreach ($currTargetFolder in $targetFolders) {
                    if (-not (Test-Path -Path $currTargetFolder -PathType Container)) {
                        New-Item -Path $currTargetFolder -ItemType Directory | Out-Null
                    }
                    $appFileName = "$($manifest.Publisher)_$($manifest.Name)_$($manifest.Version)".Split([System.IO.Path]::GetInvalidFileNameChars()) -join ''
                    $targetFilePath = Join-Path -Path $currTargetFolder -ChildPath "$($appFileName).app"
                    Write-Host "Copying $($appFileName) to $currTargetFolder"
                    Copy-Item $appFile.FullName -Destination $targetFilePath -Force
                }
            }
            Remove-Item -Path $package -Recurse -Force
            break
        }
    }
    return $returnValue
}
catch {
    Write-Host -ForegroundColor Red "Error Message: $($_.Exception.Message.Replace("`r",'').Replace("`n",' '))`r`nStackTrace: $($_.ScriptStackTrace)"
    throw
}
}
Set-Alias -Name Copy-BcNuGetPackageToFolder -Value Download-BcNuGetPackageToFolder
Export-ModuleMember -Function Download-BcNuGetPackageToFolder -Alias Copy-BcNuGetPackageToFolder


# SIG # Begin signature block
# MIInSQYJKoZIhvcNAQcCoIInOjCCJzYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBGD0bIugZ0G8Ef
# vfTbFFrZYoMmpiopUOoON8amYIxPpKCCDLowggX1MIID3aADAgECAhMzAAACHU0Z
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
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIBJdD8kv
# R1t3YGRBc2Oe56Ym/Cl/ArCbMsOqiyENDiA5MEIGCisGAQQBgjcCAQwxNDAyoBSA
# EgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20w
# DQYJKoZIhvcNAQEBBQAEggEAV3w1H3E7K3Q/qzfWOdLyTIL3PjSSGxqEL1VFvpGd
# zIBOJXItnt0ncxGxCALfGUYrVrTf052J/URWeDuhYySVrB6COmpMW7HyE82r5zmo
# gz5Qz1SsRDpvHqMIL62TU9h558LwE2CwpalxOfMGRN7vqovmv4vFfnUWKbH3y+Iq
# t0Kk0wpj64W0TsEnchzGf1wGGI9JtZBbA6PigbRWKaUuYoRH/h/BKW7h0FAH4ulZ
# C+ozS8i0ev4wFsxj5eiy4tjacWOSPD1Od/MLg/KyXXWNojUPiTGrh4jVFaOF2UNj
# csGtvTAI7OD4LR5qPn0NzyEBId6Uqkeb4UgLBxaGnZopwqGCF5cwgheTBgorBgEE
# AYI3AwMBMYIXgzCCF38GCSqGSIb3DQEHAqCCF3AwghdsAgEDMQ8wDQYJYIZIAWUD
# BAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGEWQoD
# ATAxMA0GCWCGSAFlAwQCAQUABCDvSD0mTT8IPUC6SizsuuYVnaq4jwdGPaG22iyp
# MaUgtwIGaoWNF3gOGBMyMDI2MDgyNzA2MjkzNC44MDRaMASAAgH0oIHRpIHOMIHL
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxN
# aWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRT
# UyBFU046RTAwMi0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFNlcnZpY2WgghHtMIIHIDCCBQigAwIBAgITMwAAAikO1WQqtJfyGgABAAAC
# KTANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAe
# Fw0yNjAyMTkxOTQwMDdaFw0yNzA1MTcxOTQwMDdaMIHLMQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmlj
# YSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046RTAwMi0wNUUw
# LUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIi
# MA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCeItFq4z1oCYSmUZmpYDsbJWEu
# ++1bbc/Mz7Pa3I0ZX5EON+WirB0FvnGlyFRUylzO5TJXZfU8QFPOU95P1Y1OZ8J+
# quA5G+AWSBOr/48scl0s9RBpqgTMq/lbyqBz4CMmvVR2QevAgVp4a1hbmOm9G7YW
# ey68N5F5rSDYV0wMlg4Iy8YRuFgRN2eBpVXt9IvFaFmBnQLZfo22KZ3L8PWEHUhX
# U5dLOSZoTfqqQ/B+deW56ACMnnHjPxZu+szHhZMLUrMWTgs9J7Cn8DtelcKj9aM+
# 0Zq7tkSDHCrwo6eCSfw3clktXRRrdmsccal8RCDiNFFgZsypwF2aGAF6kg41+Ql+
# thXpnOMUH4mPCAJZWp0zDWowsK/Yo5jHL1pT/AgbL3FoAy4cbhOI4Pb1eQFG+jT7
# skS2F/b+ZACUA1EDZ830K+Bu0yw+FpSGy8tpd1szk3cUYjIpzIG4z3oFNmiSJN8Y
# dNd4SHsER5Dks5bxiKbpvmfrOA39jTb7EW2TT7ySWgJISfvTezuLmQsTVSzNsvap
# VlHhE2zBqDw409nvOtitCFbnhhXNfatzb2+Gf2tX2s6YBa151CC/8+emJvvegXbW
# NudzYt8cFRom0PZ+fJRhhBfdSqCqr8QeOGJ8VYlmxFXqx1SdDSkTCSgpsskGqZwh
# /6umA1g4L7zeGBNngQIDAQABo4IBSTCCAUUwHQYDVR0OBBYEFCdNRaSL9AW8QvaQ
# 21WjRAXKN4M7MB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1Ud
# HwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3Js
# L01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggr
# BgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNv
# bS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIw
# MTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgw
# DgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUAA4ICAQA9wc72lf/czDhp09T3
# PGAMOQhxl/x04jpE7t39FeqQSn2Up6DVzhgwnzCqY3NIhLtUaWrd7NxvrhZDca+J
# 4xzvrRQNPHeRQpnJVeHsyTu53gTBlUB1TRI6OnZt/AVmR9oMJ/NBOqB+d+SOb8Px
# 6zRgRwk62sFkOkB5lig/DMnYEeR/amW9Hdo8vXcKmaa/DbSOAHSdfZFt+iqMZfNl
# kEOn71/RAKTNv4Qpq/2FhcjMMmSkIhshBdBVB0VjmkwFfhVUf5TTuLJ9sDR4EyCv
# OZJ3B6g7Iw6WjQxycjwkfzsVMTpfusJ5SwdOHL8yGPWZOePjwa8ISXWs6kiVK/6S
# 0/JVb1LpxpyYKREQjnU/5OecKt2OXlHdwFWZrwAi98RPZa6EExcb/LGLf10tNHju
# 1eTlohY0jzNZQ0BDgSuMZgMU+8EEjtMQMIDnlPGEUON7LHXHH0KL0FA01PEWVZKr
# r/LUOuuDTNFzw543FPMp4gkCIFlKdRuciR1IXOk+Xse6rj9tJFYgVn+44BHou2XQ
# e5RX30ef3AQWa0mxyGDqJzGsV3X5+bNQeMV88iWulJPq5sgnGG9O/H1/HH4HsO9Z
# KGX/WrJpQmFuQrTOR49XjveaC0xaFmGsNg+RhbtD5qTkn+ISDvw0IJ/E/VXNdz/y
# Wgol6r507hT8sAMupnhkF2uw1DCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkA
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
# T3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOkUwMDItMDVFMC1E
# OTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEw
# BwYFKw4DAhoDFQC3v9iSO22xob7ZxN5dXCEq+9Iv/6CBgzCBgKR+MHwxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29m
# dCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBCwUAAgUA7jntmDAiGA8y
# MDI2MDgyNjIyNTYyNFoYDzIwMjYwODI3MjI1NjI0WjB3MD0GCisGAQQBhFkKBAEx
# LzAtMAoCBQDuOe2YAgEAMAoCAQACAhVEAgH/MAcCAQACAhI7MAoCBQDuOz8YAgEA
# MDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAI
# AgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBAE37w8gnup/iUyTB61NHJg3jt8I5
# 91NCcjyr/X49uDpqMPIoVuVq/yYlcL9AjQxM48KRtYYPm2QXoBhhPB5EvC6rqhDu
# Kso1stCsHt3qEDSdnY1fQZhyM7vNmNOaBlPae2wR6PF1WOSbHNU+q+ECALDEMRO9
# +wLNVtAhak5XJUK2Vk5cYk9DtNoC3ylwwBMGcA2iBgyftWiNgw+Zh8ElP1YdESyk
# DjrZgLJ/XY0gic89NoviKJtNC9rBibehJoNpNPpwrcjoXCP+4KbXu3AXmR9w25Y1
# KKLI0nresbT/J6wVc4yuxUxNh9FYJmyfIsI9j4mE5GIV4Z00RSYNRcQLaR4xggQN
# MIIECQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQ
# MA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
# MSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAikO
# 1WQqtJfyGgABAAACKTANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0G
# CyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCCR7mMk0RDn5bnZ1WNT2FLL3hg4
# 0I0JAslqaYrZf3bRPTCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EILfKPfEi
# tvD/lSvEumxqPkkeOEtgkmKFEVMuel9oOrqSMIGYMIGApH4wfDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgUENBIDIwMTACEzMAAAIpDtVkKrSX8hoAAQAAAikwIgQgLetGcOD4
# k68sAgAitb2kO0u9U/IvhXEKvJHbDaj8L1EwDQYJKoZIhvcNAQELBQAEggIAeC7A
# wdQaEW9mLfx2uuRdnThFy3pBTYjV+8EovS5dDM0cSVBow5AM+3lGuoJFft46A0hp
# RtruV0uvXjyxnainR3+LoL9xYKAK02eYLWqafeErWD6A3F1Xg8OZjlJhk+wbmT7L
# saVaGHEPHen+vx7RFx1WBJfWkiYUHvMeYh2Lm3R7I2y0ofs3QLFuwdz9hyxLp7JI
# IidpgaM9L/25M8cpo3KKFEPBbmKE7zQQgjJ4Hob5ttEFtndRI2mlDJKXSl+lg+D8
# D5k4xzX/SqfynBiqPIuYWALTde15aeIN3pY0hjMas+5ELQYvsZHifoJH7ZyaIB/r
# cOuXX6/YKbVFJgaiOKTnfnXFOm+459bz3WSMy8pPdGJFH4qM3VOnLx+aaLXIFl6O
# zUlx91j7q9sXnAi/PKPQHgOaeMAMxIinanbpJiIn+3Qdw8+4oW2CsaA9QCmle4TX
# irh1bEfZBZ0FDsH18n8TM77VFEn29hsi4m6isdGRCH1KMPFTM5wdxTukgWdXbVKX
# ykmKN7f44My3zGBma/xNKnJvjO/FYJx0kFXlwLlG7WDVN/Wut2zKN1TygwKYoQFJ
# 2OGtVCf0Pmt+0y7guKDgERRK1cq5N3lTG0rAvhxC8gjJDY7Xwq2FIKGBcIwoaDZl
# loEfMtJZCxjm5rpfSVGRg6NSjHSDKnaHhQ7HhJs=
# SIG # End signature block
