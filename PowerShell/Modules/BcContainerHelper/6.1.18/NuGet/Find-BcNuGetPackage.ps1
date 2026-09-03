<#
 .Synopsis
  PROOF OF CONCEPT PREVIEW: Get Business Central NuGet Package from NuGet Server
 .Description
  Find Business Central NuGet Package from NuGet Server
 .OUTPUTS
  NuGetFeed class, packageId and package Version
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
 .PARAMETER silent
  Suppress output
 .PARAMETER select
  Select the package to download if more than one package is found matching the name and version
  - Earliest: Select the earliest version
  - Latest: Select the latest version (default)
  - Exact: Select the exact version
  - Any: Select the first version found
  - AllAscending: Select all matching versions in ascending order
  - AllDescending: Select all matching versions in descending order
 .PARAMETER allowPrerelease
  Include prerelease versions in the search
 .EXAMPLE
  $feed, $packageId, $packageVersion = Find-BcNuGetPackage -packageName 'FreddyKristiansen.BingMapsPTE.165d73c1-39a4-4fb6-85a5-925edc1684fb'
 .EXAMPLE
  $feed, $packageId, $packageVersion = Find-BcNuGetPackage -nuGetServerUrl $nugetServerUrl -nuGetToken $nuGetToken -packageName '437dbf0e-84ff-417a-965d-ed2bb9650972' -allowPrerelease
#>
Function Find-BcNuGetPackage {
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
        [string[]] $excludeVersions = @(),
        [Parameter(Mandatory=$false)]
        [ValidateSet('Earliest','Latest','Exact','Any','AllAscending','AllDescending')]
        [string] $select = 'Latest',
        [switch] $allowPrerelease
    )

    $returnValue = @()
    $bestmatch = $null
    $matchingPackagesCount = 0
    # Search all trusted feeds for the package
    foreach($feed in (@([PSCustomObject]@{ "Url" = $nuGetServerUrl; "Token" = $nuGetToken; "Patterns" = @('*'); "Fingerprints" = @() })+$bcContainerHelperConfig.TrustedNuGetFeeds)) {
        if ($feed -and $feed.Url) {
            Write-Host "Search NuGetFeed $($feed.Url)"
            if (!($feed.PSObject.Properties.Name -eq 'Token')) { $feed | Add-Member -MemberType NoteProperty -Name 'Token' -Value '' }
            if (!($feed.PSObject.Properties.Name -eq 'Patterns')) { $feed | Add-Member -MemberType NoteProperty -Name 'Patterns' -Value @('*') }
            if (!($feed.PSObject.Properties.Name -eq 'Fingerprints')) { $feed | Add-Member -MemberType NoteProperty -Name 'Fingerprints' -Value @() }
            $nuGetFeed = [NuGetFeed]::Create($feed.Url, $feed.Token, $feed.Patterns, $feed.Fingerprints, $bcContainerHelperConfig.NuGetSearchResultsCacheRetentionPeriod, $bcContainerHelperConfig.BcNuGetCacheFolder)

            $packages = $nuGetFeed.Search($packageName)
            if ($packages) {
                foreach($package in $packages) {
                    $packageId = $package.Id
                    Write-Host "PackageId: $packageId"
                    $packageVersionsStr = $nuGetFeed.FindPackageVersion($package, $version, $excludeVersions, $select, $allowPrerelease.IsPresent)
                    if (!$packageVersionsStr) {
                        Write-Host "No package found matching version '$version' for package id $($packageId)"
                        continue
                    }
                    $matchingPackagesCount++
                    $packageVersions = $packageVersionsStr.Split(',')
                    foreach($packageVersion in $packageVersions.Split(',')) {
                        if ($bestmatch) {
                            # We already have a match, check if this is a better match
                            if (($select -eq 'Earliest' -and ([NuGetFeed]::CompareVersions($packageVersion, $bestmatch.PackageVersion) -eq -1)) -or
                                ($select -eq 'Latest' -and ([NuGetFeed]::CompareVersions($packageVersion, $bestmatch.PackageVersion) -eq 1))) {
                                $bestmatch = [PSCustomObject]@{
                                    "Feed" = $nuGetFeed
                                    "PackageId" = $packageId
                                    "PackageVersion" = $packageVersion
                                }
                            }
                        }
                        elseif ($select -eq 'Exact') {
                            # We only have a match if the version is exact
                            if ([NuGetFeed]::NormalizeVersionStr($packageVersion) -eq [NuGetFeed]::NormalizeVersionStr($version)) {
                                $bestmatch = [PSCustomObject]@{
                                    "Feed" = $nuGetFeed
                                    "PackageId" = $packageId
                                    "PackageVersion" = $packageVersion
                                }
                                break
                            }
                        }
                        else {
                            $thismatch = [PSCustomObject]@{
                                "Feed" = $nuGetFeed
                                "PackageId" = $packageId
                                "PackageVersion" = $packageVersion
                            }
                            if ($select -eq 'AllAscending' -or $select -eq 'AllDescending') {
                                $returnValue += @($thismatch)
                            }
                            else {
                                $bestmatch = $thismatch
                                # If we are looking for any match, we can stop here
                                if ($select -eq 'Any') {
                                    break
                                }
                            }
                        }
                    }
                    if ($bestmatch -and ($select -eq 'Any' -or $select -eq 'Exact')) {
                        # If we have an exact match or any match, we can stop here
                        break
                    }
                }
            }
        }
        if ($bestmatch -and ($select -eq 'Any' -or $select -eq 'Exact')) {
            # If we have an exact match or any match, we can stop here
            break
        }
    }
    if ($bestmatch) {
        return $bestmatch.Feed, $bestmatch.PackageId, $bestmatch.PackageVersion
    }
    else {
        if ($matchingPackagesCount -gt 1) {
            Write-Host "Found $matchingPackagesCount matching packages across all feeds"

            # Deduplicate by PackageId and PackageVersion across all feeds
            Write-Host "Deduplicating by PackageId and PackageVersion across all feeds"
            $returnValue = @($returnValue | Sort-Object { "$($_.PackageId)|$($_.PackageVersion)" } -Unique)

            if ($select -eq 'AllAscending' -or $select -eq 'AllDescending') {
                # Sort all versions across all feeds and packages
                Write-Host "Sorting all versions across all feeds and packages"
                $returnValue = @($returnValue | Sort-Object { ($_.PackageVersion -replace '-.+$') -as [System.Version]  }, { "$($_.PackageVersion)z" } -Descending:($select -eq 'AllDescending'))
            }
        }
        return $returnValue
    }
}
Export-ModuleMember -Function Find-BcNuGetPackage

# SIG # Begin signature block
# MIIncAYJKoZIhvcNAQcCoIInYTCCJ10CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCqeDcxAEfPEcl5
# rJOct3Cm/90WjlpiJX9ddrmObbHL46CCDMkwggYEMIID7KADAgECAhMzAAACHPrN
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
# Ql0v4q8J/AUmQN5W4n101cY2L4A7GTQG1h32HHAvfQESWP0xghn9MIIZ+QIBATBu
# MFcxCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# KDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMjQCEzMAAAIc
# +s3Fm+gvfsQAAAAAAhwwDQYJYIZIAWUDBAIBBQCgga4wGQYJKoZIhvcNAQkDMQwG
# CisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZI
# hvcNAQkEMSIEIL8+C9m1UKQFwFBMlTW7Y0qwFIb1da8xTHqL7FDUTTX1MEIGCisG
# AQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEAeWNjMC7RcFATasKJ4gsD
# VuOW+bQaTlz9WeL6+GFZRUk2DeyvepDd5G2Oit/+5be6e7P/Xn+g4zZOodUMg92r
# Bl8U1V1Az8PTNxYTIMOzPePDzdHqyZRfhcAi6b6boZt4GcwkgtLJ49cgHpYIbpvj
# tlb4nDxFXmX2KvaMssTssCAEfHwS29U7ZalIblN4zOXgKyW+6RxGeB5ZiEFr+MWi
# 88kdtJNK8U20lFrLwPAisf9i26NacbaEkjbFalks8R/fFpWNGKqkNykHCyTtYVrG
# iMlzg2qJ2GvPqMzxeUiSjTh9fjarPBKavJ8Bs53knGAE6I+UyTfWWZIMrppPWVdd
# D6GCF68wgherBgorBgEEAYI3AwMBMYIXmzCCF5cGCSqGSIb3DQEHAqCCF4gwgheE
# AgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFZBgsqhkiG9w0BCRABBKCCAUgEggFEMIIB
# QAIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCDKuFjhNLjjZeJNZSh5
# xohnG2AVkEnsgxKCgy/i467IVgIGaojahmWrGBIyMDI2MDgyNzA2MzA0MC43OVow
# BIACAfSggdmkgdYwgdMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRl
# ZDEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjQwMUEtMDVFMC1EOTQ3MSUwIwYD
# VQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloIIR/jCCBygwggUQoAMC
# AQICEzMAAAIZXrLYVHX0sY0AAQAAAhkwDQYJKoZIhvcNAQELBQAwfDELMAkGA1UE
# BhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAc
# BgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0
# IFRpbWUtU3RhbXAgUENBIDIwMTAwHhcNMjUwODE0MTg0ODI2WhcNMjYxMTEzMTg0
# ODI2WjCB0zELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
# BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEtMCsG
# A1UECxMkTWljcm9zb2Z0IElyZWxhbmQgT3BlcmF0aW9ucyBMaW1pdGVkMScwJQYD
# VQQLEx5uU2hpZWxkIFRTUyBFU046NDAxQS0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3DQEBAQUAA4IC
# DwAwggIKAoICAQCmoUjJSTMjLGkvdDTdaYu7Lgb1ghRJzOeEqv5wc5P7+7s9qvEj
# 3qDHFvVata4DEHyqMYt+xsibHxXei4rWdRx/5H+eyddqzn+JOBX9OXdBNEZPQN65
# cE1ukepz7ALU2JPIDvqAueKu9IESgHOWuk1AUSe7B1s8sIulNLcpZIK7knTZv5EV
# ZH+RwXNXGeGgTeAhp5RG2sYoYFkYosFe+qCCQMQ20qS+29FPfbEu8C8v9GlF67nP
# XxmiMKzvZlKhrvgPLxhtpawObc5k6klFnFmw8oIdnrE2qAUp/TE0ePS32/RDdb7b
# PmABVpqwkkK9HnZKXRcnYA5/eXQtJ61eBQDmAPkhDVG8SyVOY2dKi5OsYgPcPWeN
# juYG7Sm6Ih08raMr/VZ55/b5hHhxClZCR4FmZeJ2H0C5Z2XDEpAvXksnorZ3DzL+
# 388GGYvK3pAB/QJ6lZF2BmczK1UBS5YfCVlFX0ktjtpfwPnl4v35w4ulfdsY06Y3
# bhSkhbyq1lqpdp6wW8g5bbck0uFppBW85uvV67sYT/kyfjd778Nu11iX9ss/YhDX
# FgQl1JtxSQMV9bcqVkSH6cEoO1pGc1GRuAiDEhsp1Pfw4pDBn9oDi5KyICDqcQ+J
# YEca7K0ijnBTvkzlV2OESqpMd9di7wEmLoZPO9ZP716R8xd7OoKSSzFobwIDAQAB
# o4IBSTCCAUUwHQYDVR0OBBYEFIBo6jkdZq03OpmfUgXV9wPqevchMB8GA1UdIwQY
# MBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6
# Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMFRpbWUt
# U3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRgMF4wXAYIKwYB
# BQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWlj
# cm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwGA1UdEwEB
# /wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwDgYDVR0PAQH/BAQDAgeAMA0G
# CSqGSIb3DQEBCwUAA4ICAQBfHNVkstcEV+gIIJOJjswdd1vtyK8lJN+sdgkLk6TY
# 03vk2nNMxP1XZNwhCN9DcAVRuHU0EBi0xS7DELoPhx4RcbmVcCdu+QL1iN4tUNHI
# iZdhiZ+3vP5CmX23cL/xrS2Kqc7PxR7z8Ngu0xOC9Yyeyos2MgsNoiY5+ccjfpMs
# KMYV7xFgtcZ0JR04uV8B0wZ4/FJMDdMAA5z4ZBuY9aOuC4tZvG+eXc1WNG+sFlWT
# EUyhVkfR/uobAM5KGOme/mdidDjy58vS4HPnZFs8Z1fgW/35QY6sGmuZwfOYi60W
# 0l5zZjiS6M21MrbAEaBaxwQ5WEWJpV2N7xUsnsxU0oTlOay4YzeNMuvWe5HkAUaz
# dQqQ/uDdxAPhwcrtd0uJObt7rTpAn5ap5CwANgT129T3AhRsj0OXhRwgSsXD4Udp
# ZJOuR8nhK8uaEqeXmSGGknWwXfPp7UHF6lSWJcerNEuIdaKFYhYRIXwgcSUXc87F
# s/hUmocGJi9pcxXRLJGDCgPrNd11tSdf1ZHokvYGWoCOMfEg3B6Wyn9WHEBZOHO4
# wDnwvG8T9UDON8UXhabtrVkAuYlXDegv+z+7GjU6ni1xP6F9n243WG0LUk3gO5Go
# V8u22O6gCZRChs7nNQVHO8KfwKT+GI75vNHXmyqSOXEszIyOmRz95/hJRSKQPjry
# 9TCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkAAAAAABUwDQYJKoZIhvcNAQEL
# BQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNV
# BAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRlIEF1dGhvcml0eSAyMDEwMB4X
# DTIxMDkzMDE4MjIyNVoXDTMwMDkzMDE4MzIyNVowfDELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
# bXAgUENBIDIwMTAwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDk4aZM
# 57RyIQt5osvXJHm9DtWC0/3unAcH0qlsTnXIyjVX9gF/bErg4r25PhdgM/9cT8dm
# 95VTcVrifkpa/rg2Z4VGIwy1jRPPdzLAEBjoYH1qUoNEt6aORmsHFPPFdvWGUNzB
# RMhxXFExN6AKOG6N7dcP2CZTfDlhAnrEqv1yaa8dq6z2Nr41JmTamDu6GnszrYBb
# fowQHJ1S/rboYiXcag/PXfT+jlPP1uyFVk3v3byNpOORj7I5LFGc6XBpDco2LXCO
# Mcg1KL3jtIckw+DJj361VI/c+gVVmG1oO5pGve2krnopN6zL64NF50ZuyjLVwIYw
# XE8s4mKyzbnijYjklqwBSru+cakXW2dg3viSkR4dPf0gz3N9QZpGdc3EXzTdEonW
# /aUgfX782Z5F37ZyL9t9X4C626p+Nuw2TPYrbqgSUei/BQOj0XOmTTd0lBw0gg/w
# EPK3Rxjtp+iZfD9M269ewvPV2HM9Q07BMzlMjgK8QmguEOqEUUbi0b1qGFphAXPK
# Z6Je1yh2AuIzGHLXpyDwwvoSCtdjbwzJNmSLW6CmgyFdXzB0kZSU2LlQ+QuJYfM2
# BjUYhEfb3BvR/bLUHMVr9lxSUV0S2yW6r1AFemzFER1y7435UsSFF5PAPBXbGjfH
# CBUYP3irRbb1Hode2o+eFnJpxq57t7c+auIurQIDAQABo4IB3TCCAdkwEgYJKwYB
# BAGCNxUBBAUCAwEAATAjBgkrBgEEAYI3FQIEFgQUKqdS/mTEmr6CkTxGNSnPEP8v
# BO4wHQYDVR0OBBYEFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMFwGA1UdIARVMFMwUQYM
# KwYBBAGCN0yDfQEBMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0
# LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTATBgNVHSUEDDAKBggrBgEF
# BQcDCDAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYD
# VR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTV9lbLj+iiXGJo0T2UkFvXzpoYxDBW
# BgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2Ny
# bC9wcm9kdWN0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcmwwWgYIKwYBBQUH
# AQEETjBMMEoGCCsGAQUFBzAChj5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtp
# L2NlcnRzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNydDANBgkqhkiG9w0BAQsF
# AAOCAgEAnVV9/Cqt4SwfZwExJFvhnnJL/Klv6lwUtj5OR2R4sQaTlz0xM7U518Jx
# Nj/aZGx80HU5bbsPMeTCj/ts0aGUGCLu6WZnOlNN3Zi6th542DYunKmCVgADsAW+
# iehp4LoJ7nvfam++Kctu2D9IdQHZGN5tggz1bSNU5HhTdSRXud2f8449xvNo32X2
# pFaq95W2KFUn0CS9QKC/GbYSEhFdPSfgQJY4rPf5KYnDvBewVIVCs/wMnosZiefw
# C2qBwoEZQhlSdYo2wh3DYXMuLGt7bj8sCXgU6ZGyqVvfSaN0DLzskYDSPeZKPmY7
# T7uG+jIa2Zb0j/aRAfbOxnT99kxybxCrdTDFNLB62FD+CljdQDzHVG2dY3RILLFO
# Ry3BFARxv2T5JL5zbcqOCb2zAVdJVGTZc9d/HltEAY5aGZFrDZ+kKNxnGSgkujhL
# mm77IVRrakURR6nxt67I6IleT53S0Ex2tVdUCbFpAUR+fKFhbHP+CrvsQWY9af3L
# wUFJfn6Tvsv4O+S3Fb+0zj6lMVGEvL8CwYKiexcdFYmNcP7ntdAoGokLjzbaukz5
# m/8K6TT4JDVnK+ANuOaMmdbhIurwJ0I9JZTmdHRbatGePu1+oDEzfbzL6Xu/OHBE
# 0ZDxyKs6ijoIYn/ZcGNTTY3ugm2lBRDBcQZqELQdVTNYs6FwZvKhggNZMIICQQIB
# ATCCAQGhgdmkgdYwgdMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRl
# ZDEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjQwMUEtMDVFMC1EOTQ3MSUwIwYD
# VQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4DAhoD
# FQAxdin9aqp3JvR6eKCst/GXQicDPqCBgzCBgKR+MHwxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBCwUAAgUA7jnwAjAiGA8yMDI2MDgyNjIz
# MDY0MloYDzIwMjYwODI3MjMwNjQyWjB3MD0GCisGAQQBhFkKBAExLzAtMAoCBQDu
# OfACAgEAMAoCAQACAhv3AgH/MAcCAQACAhL6MAoCBQDuO0GCAgEAMDYGCisGAQQB
# hFkKBAIxKDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAIAgEAAgMBhqAw
# DQYJKoZIhvcNAQELBQADggEBALgHnBa8V7k7LsUdZqz2BTrTqekb579QuiL185W9
# 7PEFIh05HSxsrzSlkmiOS3/vV3lUzO8O+biz5nt8Rq63xKCxC9yb461KqqwiFtlB
# disS5L5c6ZcR7f6CkOgWQyqVKewe/2mp9DBRIazXuFi3P4dlKVFnRsjzbexxxJXL
# IJdAVCHfuYIxoRN/iavNsXtF6OBw9WOmuWuwVLBGyNeQzs5snJcb4vwtNZiNleny
# X8Yaka/hu6ZYSltAXsWDb8Sx/F3lFFz9SQLBCO+yOLGlC96v1mx86olddY2htBLW
# dvEG98QgA+Z0es8SU1Fytfw06EmpOhb1ca79U6prCJyHr6cxggQNMIIECQIBATCB
# kzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMH
# UmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQD
# Ex1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAhlesthUdfSxjQAB
# AAACGTANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJ
# EAEEMC8GCSqGSIb3DQEJBDEiBCC+OU3KAGdgqzPrtQMv93gnsOy/zaiLojRG4ea0
# NUFUdjCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EINyRfrfcTXLUQXfZXXzN
# ByuyCPMj37ct7uaW+TY55u2GMIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNV
# BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jv
# c29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAg
# UENBIDIwMTACEzMAAAIZXrLYVHX0sY0AAQAAAhkwIgQgC05yw+Tm+C4cFdsjnSKS
# s4ES4rdH1F/TtDXAy12QTXYwDQYJKoZIhvcNAQELBQAEggIAowTgLJcAF7oBnl4G
# F2Z/IkuW+iSpgsND+Glmb/GPX/dH09W9fPOdVTv98Dnzo5cJpQb8BRUlCVPuXAPj
# 0NRBg9QQMtvs6YuFUDjHR6M2Gmtznn4St5OIiaFeSNgAJVAKrxNxcINwS3vUAMNR
# dckgGkSzC5c+QmYwb5CCzi9bRspO0kLT0plDs2x3KwZlsHWOt6heaV4nfyEfZrWY
# NBlui5+AUIdOmHfdQl6dgNDj1W1i8sw1FuKvvkWS6UsRyu1+LtMOURa6C5LAomBw
# WKrLgDjFcOGyeeIZgrRSYZqoatb8ndUNerBBl6wyVA+UkvI0Tue4RqnUC3onVnlh
# afIjfNgMJq3geHZxoru4YwOYAXPJEa6/PkW7Ct8ZnWEtJ78tq+f6GJpM2aagJVp+
# 7+OlhwFK0vQ6Y9EXUAyiCfeKb6Qpf2ur/37iAoGW039+zC1JEmIUpvQ200rlvkns
# PNfkzhiE0GyY5lt3NVyrP18rXZKc80WlwzpIILXgSyDL4mUuk+QU1TQEu2AuPKpI
# Nk19LbBRMu3F9BYLPBQtEC45C2qCnfFpbmFDZOTggs0jzxwffMegzxtm2ffsvin2
# FKX8BMNGFgBxlbv5sDAUR5vVsqV3T050yUefaI2HHDyRQX0dGS0xC6Bxwq1lK9MY
# SCjdQUUW8BSO1PoR/9asU2LA8+U=
# SIG # End signature block
