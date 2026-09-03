<# 
 .Synopsis
  Run a BCPT test suite in a BC Container
 .Description
 .Parameter containerName
  Name of the container in which you want to run a BCPT test suite
 .Parameter tenant
  tenant to use if container is multitenant
 .Parameter companyName
  company to use
 .Parameter profile
  profile to use
 .Parameter credential
  Credentials of the SUPER user if using NavUserPassword authentication
 .Parameter TestPage
  Specifying a TestPage causes the performacne test tool to use this page for perf test execution
 .Parameter BCPTSuite
  PSCustomObject or HashTable containing your BCPT Suite for importing
 .Parameter SuiteCode
  The suite code ot the BCPT Test to run
 .Parameter doNotGetResults
  Include this switch to NOT query the BCPT Log Entry API for the results
 .Example
  Run-BCPTTestsInBcContainer -containerName test -credential $credential -suiteCode $suite.code
#>
function Run-BCPTTestsInBcContainer {
    Param (
        [string] $containerName = $bcContainerHelperConfig.defaultContainerName,
        [Parameter(Mandatory=$false)]
        [string] $tenant = "default",
        [Parameter(Mandatory=$false)]
        [string] $companyName = "",
        [Parameter(Mandatory=$false)]
        [PSCredential] $credential = $null,
        [string] $testPage = "149002",
        [switch] $doNotGetResults,
        [Parameter(Mandatory = $true,  ParameterSetName = 'Suite')]
        $BCPTSuite,
        [Parameter(Mandatory = $true,  ParameterSetName = 'SuiteCode')]
        [string] $suiteCode,
        [switch] $connectFromHost
    )

$telemetryScope = InitTelemetryScope -name $MyInvocation.InvocationName -parameterValues $PSBoundParameters -includeParameters @()
try {
    
    $navversion = Get-BcContainerNavversion -containerOrImageName $containerName
    $version = [System.Version]($navversion.split('-')[0])
    if ($version.Major -lt 18) {
        throw "Run-BCPTTestsInBcContainer is not supported for versions prior to 18.0"
    }
    $pre20 = ($version.Major -lt 20)

    if ($pre20) {
        $BCPTLogEntryAPIsrc = Join-Path $PSScriptRoot "BCPTLogEntryAPI"
        $appJson = [System.IO.File]::ReadAllLines((Join-Path $BCPTLogEntryAPIsrc "app.json")) | ConvertFrom-Json
        if (-not (Get-BcContainerAppInfo -containerName $containerName | Where-Object { $_.appId -eq $appJson.id })) {
            Write-Host "Adding BCPTLogEntryAPI.app to extend existing Performance Toolkit with BCPTLogEntry API page"
            Write-Host "Using Object Id $($bcContainerHelperConfig.ObjectIdForInternalUse) (set `$bcContainerHelperConfig.ObjectIdForInternalUse to change)"
            $appExtFolder = Join-Path $bcContainerHelperConfig.hostHelperFolder "Extensions\$containerName\$([GUID]::NewGuid().ToString())"
            New-Item $appExtFolder -ItemType Directory | Out-Null
            $appJson.idRanges[0].from = $bcContainerHelperConfig.ObjectIdForInternalUse
            $appJson.idRanges[0].to = $bcContainerHelperConfig.ObjectIdForInternalUse
            $appJson | ConvertTo-Json -Depth 99 | Set-Content (Join-Path $appExtFolder "app.json")
            $appExtSrc = Get-Content -Path (Join-Path $BCPTLogEntryAPIsrc "BCPTLogEntryAPI.Page.al")
            $appExtSrc[0] = "page $($bcContainerHelperConfig.ObjectIdForInternalUse) ""BCPT Log Entry API"""
            $appExtSrc | Set-Content (Join-Path $appExtFolder "BCPTLogEntryAPI.Page.al")
    
            $appExtFileName = Compile-AppInBcContainer `
                -containerName $containerName `
                -appProjectFolder $appExtFolder `
                -credential $credential `
                -UpdateSymbols
            
            Publish-BcContainerApp `
                -containerName $containerName `
                -tenant $tenant `
                -appFile $appExtFileName `
                -skipVerification `
                -sync `
                -install
        }
    }

    if ("$companyName" -eq "") {
        $myName = $credential.UserName.SubString($credential.UserName.IndexOf('\')+1)
        Get-BcContainerBcUser -containerName $containerName | Where-Object { $_.UserName -like "*\$MyName" -or $_.UserName -eq $myName } | % {
            $companyName = $_.Company
        }
        if ($companyName) { Write-Host "Using CompanyName $companyName" }
    }

    if ("$companyName" -eq "") {
        $companyName = Get-CompanyInBcContainer -containerName $containerName -tenant $tenant | Select-Object -First 1 | ForEach-Object { $_.CompanyName }
        if ($companyName) { Write-Host "Using CompanyName $companyName" }
    }
    
    if (($BCPTSuite) -or (!$doNotGetResults)) {
        $companyId = Get-BcContainerApiCompanyId `
            -containerName $containerName `
            -tenant $tenant `
            -credential $credential `
            -CompanyName $companyName
        Write-Host "Using Company ID $companyId"
    }

    $durationString = ""
    if ($BCPTSuite) {
        if ($BCPTSuite -is [PSCustomObject]) {
            $BCPTSuite = $BCPTSuite | ConvertTo-HashTable
        }
        if ($BCPTSuite -isnot [HashTable]) {
            throw "BCPTSuite must be PSCustomObject or HashTable"
        }

        Invoke-BcContainerApi `
            -containerName $containerName `
            -tenant $tenant `
            -credential $credential `
            -CompanyId $companyId `
            -APIPublisher 'Microsoft' `
            -APIGroup 'PerformancToolkit' `
            -APIVersion 'v1.0' `
            -Method 'POST' `
            -body $BCPTSuite `
            -Query 'bcptSuites' | Out-Null

        $suiteCode = $BCPTSuite.Code
        $durationString = " for $($BCPTSuite.durationInMinutes) minutes"
    }

    $config = Get-BcContainerServerConfiguration -containerName $containerName
    if ($connectFromHost) {
        Invoke-ScriptInBcContainer -containerName $containerName -scriptblock {
            Copy-Item -path "C:\Applications\testframework\TestRunner" -Destination "c:\run\my" -Recurse -Force
            # Copy System.Threading.Tasks.Extensions.dll to TestRunner\Internal to prevent LoaderException (issue #4062)
            $threadingDll = "C:\Test Assemblies\System.Threading.Tasks.Extensions.dll"
            if (Test-Path $threadingDll) {
                Write-Host "Copying System.Threading.Tasks.Extensions.dll to TestRunner\Internal"
                Copy-Item -Path $threadingDll -Destination "c:\run\my\TestRunner\Internal" -Force
            }
            else {
                Write-Host "System.Threading.Tasks.Extensions.dll not found at $threadingDll"
            }
        }
        $auth = $config.ClientServicesCredentialType
        if ($auth -eq "UserPassword") { $auth = "NavUserPassword" }
        $params = @{ "AuthorizationType" = $auth }
        if ($auth -ne "Windows") { $params += @{ "Credential" = $credential } }
        $serviceUrl = "$($config.PublicWebBaseUrl.TrimEnd('/'))/cs/?tenant=$tenant&company=$([Uri]::EscapeDataString($companyName))"
        Write-Host "Using testpage $testpage"
        Write-Host "Using Suitecode $suitecode"
        Write-Host "Service Url $serviceUrl"
        Write-Host "Running Performance Tests$($durationString)..."

        $Job = Start-Job -ScriptBlock { Param( $location, [HashTable] $params, $suitecode, $serviceUrl, $testPage)
            Set-Location $location

            # Pre-load AntiSSRF.dll with assembly resolver to prevent LoaderException (issue #4062)
            $antiSSRFPath = Join-Path $location "Internal\Microsoft.Internal.AntiSSRF.dll"
            if (Test-Path $antiSSRFPath) {
                $threadingDllPath = Join-Path $location "Internal\System.Threading.Tasks.Extensions.dll"
                if (Test-Path $threadingDllPath) {
                    $Threading = [Reflection.Assembly]::LoadFile($threadingDllPath)
                    $onAssemblyResolve = [System.ResolveEventHandler] {
                        param($sender, $e)
                        if ($e.Name -like "System.Threading.Tasks.Extensions, Version=*, Culture=neutral, PublicKeyToken=cc7b13ffcd2ddd51") {
                            return $Threading
                        }
                        return $null
                    }
                    [System.AppDomain]::CurrentDomain.add_AssemblyResolve($onAssemblyResolve)
                    try {
                        Add-Type -Path $antiSSRFPath
                    }
                    finally {
                        [System.AppDomain]::CurrentDomain.remove_AssemblyResolve($onAssemblyResolve)
                    }
                }
            }

            .\RunBCPTTests.ps1 @params `
                -BCPTTestRunnerInternalFolderPath Internal `
                -SuiteCode $suitecode `
                -ServiceUrl $serviceUrl `
                -Environment OnPrem `
                -TestRunnerPage ([int]$testPage) | Out-Null
        } -ArgumentList (Join-Path $bcContainerHelperConfig.hostHelperFolder "extensions\$containerName\my\TestRunner"), $params, $suiteCode, $serviceUrl, $testPage | Wait-Job

        if ($job.State -ne "Completed") {
            Write-Host "Running performance test failed"
            $job | Receive-Job
        }
        $job | Remove-Job | Out-Null
    }
    else {
        Invoke-ScriptInBcContainer -containerName $containerName -useSession:$false -scriptblock { Param($webBaseUrl, $tenant, $companyName, $testPage, $auth, $credential, $suitecode, $durationString)

            Set-Location C:\Applications\testframework\TestRunner
            if ($auth -eq "UserPassword") { $auth = "NavUserPassword" }
            $params = @{ "AuthorizationType" = $auth }
            if ($auth -ne "Windows") { $params += @{ "Credential" = $credential } }
            $serviceUrl = "http://localhost:80/$serverInstance/cs/?tenant=$tenant&company=$([Uri]::EscapeDataString($companyName))"
            Write-Host "Using testpage $testpage"
            Write-Host "Using Suitecode $suitecode"
            Write-Host "Service Url $serviceUrl"
            Write-Host "Running Performance Tests$($durationString)..."

            # Pre-load AntiSSRF.dll with assembly resolver to prevent LoaderException (issue #4062)
            $antiSSRFPath = Join-Path (Get-Location) "Internal\Microsoft.Internal.AntiSSRF.dll"
            if (Test-Path $antiSSRFPath) {
                $threadingDllPath = "C:\Test Assemblies\System.Threading.Tasks.Extensions.dll"
                if (Test-Path $threadingDllPath) {
                    Write-Host "Pre-loading AntiSSRF.dll with assembly resolver for System.Threading.Tasks.Extensions.dll"
                    $Threading = [Reflection.Assembly]::LoadFile($threadingDllPath)
                    $onAssemblyResolve = [System.ResolveEventHandler] {
                        param($sender, $e)
                        if ($e.Name -like "System.Threading.Tasks.Extensions, Version=*, Culture=neutral, PublicKeyToken=cc7b13ffcd2ddd51") {
                            return $Threading
                        }
                        return $null
                    }
                    [System.AppDomain]::CurrentDomain.add_AssemblyResolve($onAssemblyResolve)
                    try {
                        Add-Type -Path $antiSSRFPath
                    }
                    finally {
                        [System.AppDomain]::CurrentDomain.remove_AssemblyResolve($onAssemblyResolve)
                    }
                }
                else {
                    Write-Host "System.Threading.Tasks.Extensions.dll not found at $threadingDllPath"
                }
            }
    
            .\RunBCPTTests.ps1 @params `
                -BCPTTestRunnerInternalFolderPath Internal `
                -SuiteCode $suitecode `
                -ServiceUrl $serviceUrl `
                -Environment OnPrem `
                -TestRunnerPage ([int]$testPage) | Out-Null
    
        } -argumentList $config.PublicWebBaseUrl, $tenant, $companyName, $testPage, $config.ClientServicesCredentialType, $credential, $suitecode, $durationString
    }

    if (!$doNotGetResults) {
        $response = Invoke-BcContainerApi `
            -containerName $containerName `
            -tenant $tenant `
            -credential $credential `
            -CompanyId $companyId `
            -APIPublisher 'Microsoft' `
            -APIGroup 'PerformancToolkit' `
            -APIVersion 'v1.0' `
            -Method 'GET' `
            -Query 'bcptLogEntries'
        
        $response.value
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
Export-ModuleMember -Function Run-BCPTTestsInBcContainer

# SIG # Begin signature block
# MIInSQYJKoZIhvcNAQcCoIInOjCCJzYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBgqRw42ZEAIJ3l
# fhmBeoTIpLzaasgke/wR4os7ivCyjqCCDLowggX1MIID3aADAgECAhMzAAACHU0Z
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
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIM232Rfs
# mFD2PNa9Rh0HK6rTJZs1rLtZ2YpbLKwaxLChMEIGCisGAQQBgjcCAQwxNDAyoBSA
# EgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20w
# DQYJKoZIhvcNAQEBBQAEggEAZnBcW/5xUdBupobaxZgLboZnyRsGb4P7l6nhTZsW
# +gHEesqQfK08m/IR/am4T45lkp/10ho62rj7NybZjnA2qOG/+qB0CqOK4Iq3U7Ui
# AEGWyxJfRHxHTPn2uI9BqiyYA1vpOxIB2NJ825SD94eFmUnKFyjEKhf05HXS0Yxr
# 3qK7YaKCTfXUMPKzMymMSSN0yaKvyK1lv8y+94lITPGjavJ39Gzw8N8Y4IH5Azbq
# 43NHVQXjrzk+/Wq7kBtqoeVoUVHg7TF1q+okeqi7VcW3Ch/4RsCMU5hsE3lvEBJj
# rZhMjxuT8fesETOq2U931bOjcHlpzJ20fqfBRHCplLeUuKGCF5cwgheTBgorBgEE
# AYI3AwMBMYIXgzCCF38GCSqGSIb3DQEHAqCCF3AwghdsAgEDMQ8wDQYJYIZIAWUD
# BAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGEWQoD
# ATAxMA0GCWCGSAFlAwQCAQUABCB7b2QtwEL6F9kIdgYc/pifsh4usXg4iCUyN/O/
# plIQaQIGaoTD8ubiGBMyMDI2MDgyNzA2MzAzNy41NDJaMASAAgH0oIHRpIHOMIHL
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
# CyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCDJDaZo+O6vkO1xFp7Mupv0juSP
# 9g4+L/XW15WKOP8t9zCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EIFYN7oh6
# ON3y92CmAl/lF0CYwrjWWQP6dCUxajPSHKEQMIGYMIGApH4wfDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgUENBIDIwMTACEzMAAAIlgMc3xs2qd0kAAQAAAiUwIgQgfHKXflTw
# dNongw7X1PG5uz6GUXB/WltMkZJbqTo5AlowDQYJKoZIhvcNAQELBQAEggIAfNlr
# +zrz1cyJGBlAO2aLZn4dwdWqY98j3zyUDUnMZJkVzRMIHEWFiLVmiFonCtwUfSZO
# JuFWBwd7G7E+PjTKGun3Us2EM84bLWCOf6okfYpOvH4OGXjJXcdKvkZ+C3GYXkex
# gSpeNnaXzYEOu+of0wsoaoTLd7G79Kl6fhOB/0kEgZ34bMgLQagpxthvZfs5vqNO
# 7NQQEdJxF6OicddumkwexQ2AIJsc5aEkFgeDd9aGbx11qxND97CMeRzdJht3Wx7T
# QGVnav32ShilTii0V0o1b233GWoiJUvXqafEIxLQKGSgGdaQr2xRj9Q5sAOx1+5/
# 4CEvsDdH61+AsmosZ3j2ep8+UTrBCA0TENPV/dI2lFQiDQsPGNnxlCI/9FYcFm+q
# uJom603ft4NJUuPlPD+p/nOo4BPBvR9UxojvMahPSbcuXVRyvihz5IXb8YmVuwMB
# Rqk7h7NPKTXkwhq/PmFUjTjb5wN8LA9VDPFnu9R3G3stbWjRJqDs8Mn4oGUzrlBp
# LBzCw9n/59Cq2nThEJvgWkg2L1YfABLedxisJBzuEZwMTl/SEPat0PcBgHjKbV8Y
# ufSlZMnDs4v6EJO7zdso6IPIBt55oIuggZ/1DXwd7PI65S9Sx2ovciKnOMkdp1IT
# QhEHVT5uirA7fcJ8+vwf0zjGM1LrdYX/M+THeK4=
# SIG # End signature block
