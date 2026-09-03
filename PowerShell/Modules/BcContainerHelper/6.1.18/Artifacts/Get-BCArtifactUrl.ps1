<# 
 .Synopsis
  Get a list of available artifact URLs
 .Description
  Get a list of available artifact URLs.  It can be used to create a new instance of a Container.
 .Parameter type
  OnPrem or Sandbox (default is Sandbox)
 .Parameter country
  the requested localization of Business Central
 .Parameter version
  The version of Business Central (will search for entries where the version starts with this value of the parameter)
 .Parameter select
  All or only the latest (Default Latest):
    - All: will return all possible urls in the selection.
    - Latest: will sort on version, and return latest version.
    - Daily: will return the latest build from yesterday (ignoring builds from today). Daily only works with Sandbox artifacts.
    - Weekly: will return the latest build from last week (ignoring builds from this week). Weekly only works with Sandbox artifacts.
    - Closest: will return the closest version to the version specified in version (must be a full version number).
    - SecondToLastMajor: will return the latest version where Major version number is second to Last (used to get Next Minor version from insider).
    - Current: will return the currently active sandbox release.
    - NextMajor: will return the next major sandbox release (will return empty if no Next Major is available).
    - NextMinor: will return the next minor sandbox release (will return NextMajor when the next release is a major release).
 .Parameter storageAccount
  The storageAccount that is being used where artifacts are stored (default is bcartifacts, usually should not be changed).
 .Parameter sasToken
  OBSOLETE - sasToken is no longer supported
 .Parameter accept_insiderEula
  Accept the EULA for Business Central Insider artifacts. This is required for using Business Central Insider artifacts without providing a SAS token after October 1st 2023.
 .Example
  Get the latest URL for Belgium: 
  Get-BCArtifactUrl -Type OnPrem -Select Latest -country be
  
  Get all available Artifact URLs for BC SaaS:
  Get-BCArtifactUrl -Type Sandbox -Select All
#>
function Get-BCArtifactUrl {
    [CmdletBinding()]
    param (
        [ValidateSet('OnPrem', 'Sandbox')]
        [String] $type = 'Sandbox',
        [String] $country = '',
        [String] $version = '',
        [ValidateSet('Latest', 'First', 'All', 'Closest', 'SecondToLastMajor', 'Current', 'NextMinor', 'NextMajor', 'Daily', 'Weekly')]
        [String] $select = 'Latest',
        [DateTime] $after,
        [DateTime] $before,
        [String] $storageAccount = '',
        [Obsolete("sasToken is no longer supported")]
        [String] $sasToken = '',
        [switch] $accept_insiderEula,
        [switch] $doNotCheckPlatform
    )

$telemetryScope = InitTelemetryScope -name $MyInvocation.InvocationName -parameterValues $PSBoundParameters -includeParameters @("type","country","version","select","after","before","StorageAccount")
try {

    if ($type -eq "OnPrem") {
        if ($version -like '18.9*') {
            Write-Host -ForegroundColor Yellow 'On-premises build for 18.9 was replaced by 18.10.35134.0, using this version number instead'
            $version = '18.10.35134.0'
        }
        elseif ($version -like '17.14*') {
            Write-Host -ForegroundColor Yellow 'On-premises build for 17.14 was replaced by 17.15.35135.0, using this version number instead'
            $version = '17.15.35135.0'
        }
        elseif ($version -like '16.18*') {
            Write-Host -ForegroundColor Yellow 'On-premises build for 16.18 was replaced by 16.19.35126.0, using this version number instead'
            $version = '16.19.35126.0'
        }
        if ($select -eq "Weekly" -or $select -eq "Daily") {
            $select = 'Latest'
        }
    }

    if ($select -eq "Weekly" -or $select -eq "Daily") {
        if ($select -eq "Daily") {
            $ignoreBuildsAfter = [DateTime]::Today
        }
        else {
            $ignoreBuildsAfter = [DateTime]::Today.AddDays(-[datetime]::Today.DayOfWeek)
        }
        if ($version -ne '' -or ($after) -or ($before)) {
            throw 'You cannot specify version, before or after when selecting Daily or Weekly build'
        }
        $current = Get-BCArtifactUrl -country $country -select Latest -doNotCheckPlatform:$doNotCheckPlatform
        Write-Verbose "Current build is $current"
        if ($current) {
            $currentversion = [System.Version]($current.Split('/')[4])
            $periodic = Get-BCArtifactUrl -country $country -select Latest -doNotCheckPlatform:$doNotCheckPlatform -before ($ignoreBuildsAfter.ToUniversalTime()) -version "$($currentversion.Major).$($currentversion.Minor)"
            if (-not $periodic) {
                $periodic = Get-BCArtifactUrl -country $country -select First -doNotCheckPlatform:$doNotCheckPlatform -after ($ignoreBuildsAfter.ToUniversalTime()) -version "$($currentversion.Major).$($currentversion.Minor)"
            }
            Write-Verbose "Periodic build is $periodic"
            if ($periodic) { $current = $periodic }
        }
        $current
    }
    elseif ($select -eq "Current") {
        if ($storageAccount -ne '' -or $type -eq 'OnPrem' -or $version -ne '') {
            throw 'You cannot specify storageAccount, type=OnPrem or version when selecting Current release'
        }
        Get-BCArtifactUrl -country $country -select Latest -doNotCheckPlatform:$doNotCheckPlatform
    }
    elseif ($select -eq "NextMinor" -or $select -eq "NextMajor") {
        if ($storageAccount -ne '' -or $type -eq 'OnPrem' -or $version -ne '') {
            throw "You cannot specify storageAccount, type=OnPrem or version when selecting $select release"
        }

        $current = Get-BCArtifactUrl -country 'base' -select Latest -doNotCheckPlatform:$doNotCheckPlatform
        $currentversion = [System.Version]($current.Split('/')[4])

        $nextminorversion = "$($currentversion.Major).$($currentversion.Minor+1)."
        $nextmajorversion = "$($currentversion.Major+1).0."
        if ($currentVersion.Minor -ge 5) {
            $nextminorversion = $nextmajorversion
        }

        if (-not $country) { $country = 'w1' }
        $insiderParams = @{
            country            = $country
            storageAccount     = 'bcinsider'
            select             = 'All'
            doNotCheckPlatform = $doNotCheckPlatform
            accept_insiderEula = $accept_insiderEula
        }
        if ($before) {
            $insiderParams['before'] = $before
        }
        if ($after) {
            $insiderParams['after'] = $after
        }
        $insiders = Get-BcArtifactUrl @insiderParams
        $nextmajor = $insiders | Where-Object { $_.Split('/')[4].StartsWith($nextmajorversion) } | Select-Object -Last 1
        $nextminor = $insiders | Where-Object { $_.Split('/')[4].StartsWith($nextminorversion) } | Select-Object -Last 1

        if ($select -eq 'NextMinor') {
            $nextminor
        }
        else {
            $nextmajor
        }
    }
    else {
        if ($storageAccount -eq '') {
            $storageAccount = 'bcartifacts'
        }

        if (-not $storageAccount.Contains('.')) {
            $storageAccount += ".blob.core.windows.net"
        }
        $BaseUrl = ReplaceCDN -sourceUrl "https://$storageAccount/$($Type.ToLowerInvariant())/"
        $storageAccount = ReplaceCDN -sourceUrl $storageAccount -useBlobUrl

        if ($storageAccount -eq 'bcinsider.blob.core.windows.net' -and !$accept_insiderEULA) {
            throw "You need to accept the insider EULA (https://go.microsoft.com/fwlink/?linkid=2245051) by specifying -accept_insiderEula or by providing a SAS token to get access to insider builds"
        }

        if ($type -eq 'sandbox' -and $storageAccount -eq 'bcartifacts.blob.core.windows.net' -and $select -eq 'latest' -and $version -eq '' -and $bcContainerHelperConfig.useApproximateVersion) {
            # Temp fix / hack for Get-BcArtifact performance
            # If Microsoft changes versioning schema, this needs to change (or useApproximateVersion should be set to false)
            $now = ([DateTime]::Now).AddDays(15)
            $approximateMajor = 23+2*($now.Year-2024)+($now.Month -ge 4)+($now.Month -ge 10)
            $approximateMinor = ($now.Month + 2)%6
            $artifactUrl = Get-BCArtifactUrl -country $country -version "$approximateMajor.$approximateMinor" -select Latest -doNotCheckPlatform:$doNotCheckPlatform
            if ($artifactUrl) {
                # We found an artifact - check if it is the latest
                while ($artifactUrl) {
                    $lastGoodArtifact = $artifactUrl
                    if ($approximateMinor -eq 5) {
                        $approximateMajor += 1
                        $approximateMinor = 0
                    }
                    else {
                        $approximateMinor += 1
                    }
                    $artifactUrl = Get-BCArtifactUrl -country $country -version "$approximateMajor.$approximateMinor" -select Latest -doNotCheckPlatform:$doNotCheckPlatform
                }
                $artifactUrl = $lastGoodArtifact
            }
            else {
                # No artifact found - try previous 3 versions (else give up - maybe country is unavailable)
                $tryVersions = 3
                while (-not $artifactUrl -and $tryVersions-- -gt 0) {
                    if ($approximateMinor -eq 0) {
                        $approximateMajor -= 1
                        $approximateMinor = 5
                    }
                    else {
                        $approximateMinor -= 1
                    }
                    $artifactUrl = Get-BCArtifactUrl -country $country -version "$approximateMajor.$approximateMinor" -select Latest -doNotCheckPlatform:$doNotCheckPlatform
                }
            }
            $artifactUrl
        }
        else {
            $versionPrefix = ''
            if ($select -eq 'SecondToLastMajor') {
                if ($version) {
                    throw "You cannot specify a version when asking for the Second To Last Major version"
                }
            }
            elseif ($select -eq 'Closest') {
                if (!($version)) {
                    throw "You must specify a version number when you want to get the closest artifact Url"
                }
                $dots = ($version.ToCharArray() -eq '.').Count
                $closestToVersion = [Version]"0.0.0.0"
                if ($dots -ne 3 -or !([Version]::TryParse($version, [ref] $closestToVersion))) {
                    throw "Version number must be in the format 1.2.3.4 when you want to get the closest artifact Url"
                }
                $versionPrefix = "$($closestToVersion.Major).$($closestToVersion.Minor)."
            }
            elseif (!([string]::IsNullOrEmpty($version))) {
                $dots = ($version.ToCharArray() -eq '.').Count
                if ($dots -lt 3) {
                    # avoid 14.1 returning 14.10, 14.11 etc.
                    $version = "$($version.TrimEnd('.'))."
                }
                $versionPrefix = $Version
            }

            $parameters = @{
                "storageAccount" = $storageAccount.ToLowerInvariant()
                "Type" = $Type.ToLowerInvariant()
                "VersionPrefix" = $versionPrefix
                "Country" = $country.ToLowerInvariant()
                "doNotCheckPlatform" = $doNotCheckPlatform
            }
            if ($after) {
                $parameters["after"] = $after
            }
            if ($before) {
                $parameters["before"] = $before
            }

            $artifacts = QueryArtifactsFromIndex @parameters

            foreach($excludebuilds in $bccontainerHelperConfig.ExcludeBuilds) {
                . (Join-Path $PSScriptRoot "../NuGet/NuGetFeedClass.ps1")
                $artifacts = $artifacts | Where-Object { if ([nugetFeed]::IsVersionIncludedInRange($_.Split('/')[0], $excludebuilds)) { Write-Host "Excluding $_"; return $false } else { return $true } }
            }

            switch ($Select) {
                'All' {  
                    # Artifacts are sorted
                }
                'Latest' { 
                    $Artifacts = $Artifacts | Select-Object -Last 1
                }
                'First' { 
                    $Artifacts = $Artifacts | Select-Object -First 1
                }
                'SecondToLastMajor' { 
                    $latest = $Artifacts | Select-Object -Last 1
                    if ($latest) {
                        $latestversion = [Version]($latest.Split('/')[0])
                        $Artifacts = $Artifacts |
                            Where-Object { ([Version]($_.Split('/')[0])).Major -ne $latestversion.Major } |
                            Select-Object -Last 1
                    }
                    else {
                        $Artifacts = @()
                    }
                }
                'Closest' {
                    $closest = $Artifacts |
                        Where-Object { [Version]($_.Split('/')[0]) -ge $closestToVersion } |
                        Select-Object -First 1
                    if (-not $closest) {
                        $closest = $Artifacts | Select-Object -Last 1
                    }
                    $Artifacts = $closest           
                }
            }
    
           foreach ($Artifact in $Artifacts) {
                "$BaseUrl$($Artifact)$sasToken"
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
Export-ModuleMember -Function Get-BCArtifactUrl

# SIG # Begin signature block
# MIInSQYJKoZIhvcNAQcCoIInOjCCJzYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDgMQakcV4XIA1p
# KYpaQxmNnG1G73uJYjldlSDBzHkszaCCDLowggX1MIID3aADAgECAhMzAAACHU0Z
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
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIBhUnQXm
# vvsLTZJeisfDllrWIteWao065N9UmStgP8z+MEIGCisGAQQBgjcCAQwxNDAyoBSA
# EgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20w
# DQYJKoZIhvcNAQEBBQAEggEAGQSCCIQSGkjWvUwEmSq52Kqxg+eoW0RxjpQqtfgF
# FLkI3soDnMKBajKwYoO1b5DDedxFger5IyejcYKDqGMrG9o5htYJL+xX3/NAC6Bs
# qya+/WT0i8yZcanYrhnIydu81Nv979yKV4ds2sKGVLqZudolpEhp7M6vFKHGVdFr
# +kLPzftv3NwGfQdK5noBVRp8yoUyFYnCmqWjjglFGkA27Y5/JJzOOy5gM+ts2DGq
# 5bwc5jTd0GbxGzRyU0lqm4GXeuq4lJ8IT6m3G12gw+njeS884RKt+hgC0fUPAxLY
# zcENI4ikNhMBN0mjfYNQIg8ET2yllK4INeRUyFj7MagAHqGCF5cwgheTBgorBgEE
# AYI3AwMBMYIXgzCCF38GCSqGSIb3DQEHAqCCF3AwghdsAgEDMQ8wDQYJYIZIAWUD
# BAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGEWQoD
# ATAxMA0GCWCGSAFlAwQCAQUABCBk4TPuKwr7G8SacLp/1B9jQTgyTS4JsFmyIqqe
# IEOdWQIGaoTD8t1UGBMyMDI2MDgyNzA2MjkzNy4xNjFaMASAAgH0oIHRpIHOMIHL
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxN
# aWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRT
# UyBFU046ODYwMy0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFNlcnZpY2WgghHtMIIHIDCCBQigAwIBAgITMwAAAiWAxzfGzap3SQABAAAC
# JTANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAe
# Fw0yNjAyMTkxOTQwMDFaFw0yNzA1MTcxOTQwMDFaMIHLMQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmlj
# YSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046ODYwMy0wNUUw
# LUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIi
# MA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCm8RIP0eLA46VcCPovvmqsIlN6
# qkmz5IsHWmUU0neUqp8uGxadeo+SwWBCwQ5alZI/DNdpXfyiZLZR6XYgpRPFzepI
# l7OCDb4NtEskJCIZDkQMNwrH9YwUyu71GGigsLIxeleHtA3utoVTeHjS1b8UnwOR
# RtknKkyrUArT6ZpB2rodIcmcLcv3x3wwgYlOs0FEg5EsVrZb7LNc/nd0bXDp+HTO
# WWui8eoTVwJeLxcVP869oF8li5SU81aa2tGJ6/Jsejiz9JMW8SJXKBT2DCXMOUkC
# sGjonPZRqfvoMSIQZgtaOTyAJlrvsy0TZ78XrGqoygtQimQnbOAL4KNLSCuW5TZE
# QGTHLOQJGgggb3j5gKC778+RIPJA+n/hmHJ/x4qT/HTTPoVeMCcuBKWrQXR1+/pY
# au3Fwe0tWIyG+LWzkRr/ZNPPupcA2Yci3qn8HR9RwvQopqSNJwn2Ri6am8AQyfVV
# y/BBw0t6jpoRPjwKvuUjfCzpae6duOxQtQ1XDN9PA2yl9sDko/+AXV/SOe8ea8Qo
# Qcv3s3ErkG+Lp6hnvw6OMPian4ggNkRtgtB7ro1OiopOUXJn9Y5EO3JUAXNcuM9m
# +5My1VEuvGytgAH3uxmslTnW3YbrfazaySCSSnWkhaOZ33hgbuUQfH7n2NFEAUc/
# cFzfmCQUikWisnJYywIDAQABo4IBSTCCAUUwHQYDVR0OBBYEFLE40qoXTuMHX3Af
# ZUu1n8nx2h93MB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1Ud
# HwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3Js
# L01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggr
# BgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNv
# bS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIw
# MTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgw
# DgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUAA4ICAQAHnfc2yUyoHZbvvyVK
# FuXh5HxxHIvIaR9JWpIfITJlc/Ki03juR+vckzq3tp5fFH5LL7eIFXRIuoewMsvW
# eFrWufrrW4HhmhCwkqArfA1C0xk+HaYs2O48YSxMX9lgS1kTTIb3YsfoFdFpKurP
# f2nc2Yd4wLg+FgwmkxkeyE3MUKVna8SZeVpEjnS5ucFck4srPwK2ORAf70I23GGy
# PhqgIKZphNXhSscTAQsyIqB5GwDMdRV5LK37NfU4YmxvCYh3TFYE/Gh01Q6yJvf9
# HxiEZpwW+oUk0gruHobg3sgIR5rfgUo8l30vUnaDYMcPAClaFMC/QbHZSaUhWXZG
# 1OOcMp0g9vYQNLDEqFX2jlquvzVSSwtHtm1KTldCjRED+kdCybcPxbPalwJigXc1
# BsI9CitnTf0ljwb9NkZ/JVI8/D62rXXzhz4F3u0iVGzwncGaxRxHG/Xv4nTrpkOe
# epoYbNBbMWS2G1qP3Xj7pVf0+4qRyAqJ0stjQjoVOJImVPWRjz5PR3Dn6adQVMBJ
# DM6gDrj1rZTFVgCtTijqGZSGzvXpGkF3vYsyE6ZDma/kGdiUe5saeI6lH66PiWWX
# gqxt7sy2Ezv0yIjSVv+eMOT2QMUiZ6WCc7gVtAmXpfeIus+NmgFvM+Ic1X58e4I9
# EL4ZSAidSpWW0GZTLNC02mryLjCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkA
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
# T3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjg2MDMtMDVFMC1E
# OTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEw
# BwYFKw4DAhoDFQBTb+bKOPAjCBflhzw5EXBuSWxeDqCBgzCBgKR+MHwxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29m
# dCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBCwUAAgUA7jnNFzAiGA8y
# MDI2MDgyNjIwMzc0M1oYDzIwMjYwODI3MjAzNzQzWjB3MD0GCisGAQQBhFkKBAEx
# LzAtMAoCBQDuOc0XAgEAMAoCAQACAgQlAgH/MAcCAQACAhOlMAoCBQDuOx6XAgEA
# MDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAI
# AgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBAIp7bW8O5OfonPWUFnACfgi3xLdH
# LbIuIaWH4MXitCQwaDCAdllZF5+7e5d1B2oacIcYBPPlzJHVvgbKoPpgyzE/cq+r
# xXfcQBuOxAOowK7LPofcutgin9FSs2BjhpyNLHg8IiScE0t2OItaBwoi9gA2NDCj
# jOVF6DnsGWHQn8W0f+ibILOsUnojaj6+DgcdTPSM7gXCJ8B7ly5rUONEZMC5GIyt
# 1NB3PNiZ8IKNLYTqqIdDie/wmpE3qxCqTzuRyeSmN4CnhPpuNEhIjp+C1gPJEr1V
# I2wRCc67/FfPxIG7vFyEv7KU9NnJOSInyOlak+UAIytbUV8pwtIZ1NlLYDAxggQN
# MIIECQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQ
# MA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
# MSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAiWA
# xzfGzap3SQABAAACJTANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0G
# CyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCBBvknJeU6lJrepnHoCZZ4smOlL
# M9X0NO9WOhyVejiJqzCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EIFYN7oh6
# ON3y92CmAl/lF0CYwrjWWQP6dCUxajPSHKEQMIGYMIGApH4wfDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgUENBIDIwMTACEzMAAAIlgMc3xs2qd0kAAQAAAiUwIgQgfHKXflTw
# dNongw7X1PG5uz6GUXB/WltMkZJbqTo5AlowDQYJKoZIhvcNAQELBQAEggIAV3Zf
# /jYiR/H9Q0DrGNusi8D5YqoQ9D3rhVa9c/0dHM74K2a+QLLAWsPCRQR/zn2cF1S9
# xhzpqwaqnmB88EtSuGNSOy0LPh6OS+6EMstH2WPfYr2QIlD3jYWdbrlVR5Js3Uco
# lWaLIq2/jh+pL34mA37AoL34lX0squXep3oGk2xOkSUCncHxpvMBD8w36O3Ayw47
# J+NAazDxghYkiakTuduQww9+cAG73DjY0u5gUcLbSxe0/Ow3bva9HlnsCSdsdiV3
# co4bs2TrhrSH8sh/7rImo8+/q5WuKywiyOtM97y4szRfwf/+muDGkII73y/YCD5Q
# FTTmhvIvvNx73gX2Exjiqz1Ua5Vtuo3meJWPibUKSYmTRVyTTCTAHkeX/4xR3shS
# B0MA9GAhG3XwtbYJt2cu2GIT3tBN4vxhZZ1nwzP5tLA33ovooq0/eT8raHCd7B+B
# a6F7mwclV6pKQfTMCYxqF3qTyn/XeLLB1XnExjn69ZTSsc3TUwqc/0MagHaBNaaQ
# gSwiJJj2MdZmVbnQmxBdbxmQywq7AcKgXN3LXrHgl69vTmwOgm2UgCHzAU/ulUlI
# MD63wVrSOATiPy/gY8QAOo91xzqlczPpO5zg0xDuSFXCWxUPJ8QPzp4bWThyyJlI
# uBMRadegG91WD91PKrB5yBBP/xBxaCkWyYTPBkY=
# SIG # End signature block
