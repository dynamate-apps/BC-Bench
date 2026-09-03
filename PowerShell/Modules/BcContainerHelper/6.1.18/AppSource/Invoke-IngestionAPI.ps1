function Invoke-IngestionApiRestMethod {
    Param(
        [Parameter(Mandatory=$true)]
        [HashTable] $authContext,
        [Parameter(Mandatory=$false)]
        [HashTable] $headers = @{},
        [string] $method = "GET",
        [Parameter(Mandatory=$true)]
        [string] $path,
        [Parameter(Mandatory=$false)]
        [string] $query = '',
        [Parameter(Mandatory=$false)]
        [string] $body = '',
        [switch] $silent,
        [switch] $ignore404
    )

    $authContext = Renew-BcAuthContext -bcAuthContext $authContext
    if ($authContext.scopes -ne "https://api.partner.microsoft.com/.default" -and $authContext.scopes -ne "https://api.partner.microsoft.com/" -and $authContext.scopes -ne "https://api.partner.microsoft.com/user_impersonation offline_access") {
        Write-Host -ForegroundColor Red "WARNING: AuthContext.Scopes is '$($authContext.Scopes)', should have been 'https://api.partner.microsoft.com/.default' or 'https://api.partner.microsoft.com/user_impersonation offline_access'"
    }
    $headers += @{
        "Authorization" = "Bearer $($authcontext.AccessToken)"
        "Content-Type" = "application/json; charset=utf-8"
    }
    $uriBuilder = [UriBuilder]::new("https://api.partner.microsoft.com/v1.0/ingestion$path")
    if (!$silent) {
        Write-Host "$method $($UriBuilder.Uri.ToString())"
    }
    if ($query) {
        $uriBuilder.Query = $query
    }
    $parameters = @{
        "useBasicParsing" = $true
        "method" = $method
        "uri" = $UriBuilder.Uri.ToString()
        "headers" = $headers
    }
    if ($PSBoundParameters.ContainsKey('body')) {
        if (!$silent) {
            # Strip URL query strings before logging the body so that SAS tokens
            # (e.g. in package fileSasUri values) are never written to logs.
            [regex]::Replace($body, '(?i)(https?://[^\s"''?]+)\?[^\s"'']*', '$1?<redacted>') | Out-Host
        }
        $parameters += @{
            "body" = [System.Text.Encoding]::UTF8.GetBytes($body)
        }
    }
    $waitTime = 1
    $retries = 5
    $success = $false
    do {
        try {
            Invoke-RestMethod @parameters
            $success = $true
        }
        catch {
            $statusCode = 0
            if ($_.Exception -is [System.Net.WebException]) {
                $webException = [System.Net.WebException]$_.Exception
                $webResponse = $webException.Response
                if ($webResponse) {
                    $statusCode = [int]$webResponse.StatusCode
                }
            }
            if ($statusCode -eq 404 -and $ignore404) {
                # fix for bug https://github.com/microsoft/navcontainerhelper/issues/3151
                Write-Host -ForegroundColor Yellow "WARNING: Ingestion API returned an invalid nextlink, ignoring..."
                $success = $true
            }
            else {
                try {
                    $errorDetails = $_.ErrorDetails | ConvertFrom-Json
                    $statusCode = $errorDetails.statusCode
                }
                catch {}

                # 500 Internal Server Error
                # 503 Service Unavailable
                # 504 Gateway Timeout
                if ($retries -gt 0 -and $statusCode -in @(500, 503, 504)) {
                    $retries--
                    Write-Host "$(GetExtendedErrorMessage $_)".TrimEnd()
                    Write-Host "...retrying in $waittime minute(s)"
                    Start-Sleep -Seconds ($waitTime*60)
                    $waitTime = $waitTime * 2
                }
                else {
                    throw (GetExtendedErrorMessage $_)
                }
            }
        }
    } while (!$success)
}

<#
 .Synopsis
  Invoke a HTTP GET to receive a collection of objects from the Ingestion API
  This function handles paging and always returns the full array
 .Description
  Returns an array of PSCustomObjects with properties from the Objects received
 .Parameter authContext
  Authentication Context from New-BcAuthContext
 .Parameter path
  Ingestion API path as described on Swagger doc (https://ingestionapi-swagger.azureedge.net/)
 .Parameter headers
  Optional. Hashtable with additional headers for the request
 .Parameter query
  Optional. Query parameters for the invoke
 .Parameter silent
  Include this switch if you do not want the method to display URLs etc.
 .Example
  @(Invoke-IngestionApiGetCollection -authContext $authContext -path "/products")
  GET https://api.partner.microsoft.com/v1.0/ingestion/products
  
  resourceType        : AzureDynamics365BusinessCentral
  name                : C5 2012 Data Migration
  externalIDs         : {@{type=AzureOfferId; value=c5-2012-data-migration}}
  isModularPublishing : True
  id                  : bc09759f-4d41-4d56-a57a-2f7e4cfad4a2
  
  resourceType        : AzureDynamics365BusinessCentral
  name                : ELSTER VAT Localization for Germany
  externalIDs         : {@{type=AzureOfferId; value=elster-vat-file-de}}
  isModularPublishing : True
  id                  : 29cb661d-ea77-4415-ac43-b0f7a90cd9b5
  
  resourceType        : AzureDynamics365BusinessCentral
  name                : PayPal Payments Standard
  externalIDs         : {@{type=AzureOfferId; value=fb310c16-0b22-4569-a5f0-8f9a01571cee}}
  isModularPublishing : True
  id                  : 193aec22-a99f-4024-8aba-c01ec540c0b7

  ...
#>
function Invoke-IngestionApiGetCollection {
    Param(
        [Parameter(Mandatory=$true)]
        [HashTable] $authContext,
        [Parameter(Mandatory=$true)]
        [string] $path,
        [Parameter(Mandatory=$false)]
        [HashTable] $headers = @{},
        [Parameter(Mandatory=$false)]
        [string] $query = '',
        [switch] $silent
    )

$telemetryScope = InitTelemetryScope -name $MyInvocation.InvocationName -parameterValues $PSBoundParameters -includeParameters @()
try {
    $nextlink = $path
    $ignore404 = $false
    while ($nextlink) {

        $ps = Invoke-IngestionApiRestMethod -authContext $authContext -method GET -headers $headers -path $nextlink -query $query -silent:$silent -ignore404:$ignore404

        $nextlink = ""
        if ($ps) {
            if ($ps.PSObject.Properties.Name -eq 'nextlink') {
                $nextlink = $ps.nextlink.SubString("v1.0/ingestion".Length)
                $ignore404 = $true
            }
            if ($ps.value) {
                $ps.value
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

<#
 .Synopsis
  Invoke a HTTP GET to receive a single object from the Ingestion API
 .Description
  Returns a PSCustomObject with properties from the Object received
 .Parameter authContext
  Authentication Context from New-BcAuthContext
 .Parameter path
  Ingestion API path as described on Swagger doc (https://ingestionapi-swagger.azureedge.net/)
 .Parameter headers
  Optional. Hashtable with additional headers for the request
 .Parameter query
  Optional. Query parameters for the invoke
 .Parameter silent
  Include this switch if you do not want the method to display URLs etc.
 .Example
  Invoke-IngestionApiGet -authContext $authContext -path "/products/5fbe0803-a545-4504-b41a-d9d158112360"
  GET https://api.partner.microsoft.com/v1.0/ingestion/products/5fbe0803-a545-4504-b41a-d9d158112360

  resourceType        : AzureDynamics365BusinessCentral
  name                : BingMaps.AppSource
  externalIDs         : {@{type=AzureOfferId; value=bingmapsintegration}}
  isModularPublishing : True
  id                  : 5fbe0803-a545-4504-b41a-d9d158112360
#>
function Invoke-IngestionApiGet {
    Param(
        [Parameter(Mandatory=$true)]
        [HashTable] $authContext,
        [Parameter(Mandatory=$true)]
        [string] $path,
        [Parameter(Mandatory=$false)]
        [HashTable] $headers = @{},
        [Parameter(Mandatory=$false)]
        [string] $query = '',
        [switch] $silent
    )

$telemetryScope = InitTelemetryScope -name $MyInvocation.InvocationName -parameterValues $PSBoundParameters -includeParameters @()
try {
    Invoke-IngestionApiRestMethod -authContext $authContext -method GET -headers $headers -path $path -query $query -silent:$silent
}
catch {
    TrackException -telemetryScope $telemetryScope -errorRecord $_
    throw
}
finally {
    TrackTrace -telemetryScope $telemetryScope
}
}

<#
 .Synopsis
  Invoke a HTTP POST to create a new object or run an action in the Ingestion API
 .Description
  Returns a PSCustomObject with properties from the newly created Object received
 .Parameter authContext
  Authentication Context from New-BcAuthContext
 .Parameter path
  Ingestion API path as described on Swagger doc (https://ingestionapi-swagger.azureedge.net/)
 .Parameter body
  Optional. HashTable with properties for the request
 .Parameter headers
  Optional. Hashtable with additional headers for the request
 .Parameter query
  Optional. Query parameters for the invoke
 .Parameter silent
  Include this switch if you do not want the method to display URLs etc.
 .Example
  Invoke-IngestionApiPost -authContext $authContext -path "/products/5fbe0803-a545-4504-b41a-d9d158112360/submissions/123456789/promote"
 .Example
  $packageUpload = Invoke-IngestionApiPost -authContext $authContext -path "/products/$productId/packages" -Body $body
#>
function Invoke-IngestionApiPost {
    Param(
        [Parameter(Mandatory=$true)]
        [HashTable] $authContext,
        [Parameter(Mandatory=$true)]
        [string] $path,
        [Parameter(Mandatory=$false)]
        [HashTable] $body = @{},
        [Parameter(Mandatory=$false)]
        [HashTable] $headers = @{},
        [Parameter(Mandatory=$false)]
        [string] $query = '',
        [switch] $silent
    )

$telemetryScope = InitTelemetryScope -name $MyInvocation.InvocationName -parameterValues $PSBoundParameters -includeParameters @()
try {
    Invoke-IngestionApiRestMethod -authContext $authContext -method POST -headers $headers -path $path -query $query -body ($body | ConvertTo-Json) -silent:$silent
}
catch {
    TrackException -telemetryScope $telemetryScope -errorRecord $_
    throw
}
finally {
    TrackTrace -telemetryScope $telemetryScope
}
}

<#
 .Synopsis
  Invoke a HTTP PUT to modify a single object through the Ingestion API
 .Description
  Returns a PSCustomObject with properties from the modified Object
 .Parameter authContext
  Authentication Context from New-BcAuthContext
 .Parameter path
  Ingestion API path as described on Swagger doc (https://ingestionapi-swagger.azureedge.net/)
 .Parameter body
  Optional. HashTable with properties for the request (incl. an '@odata.etag' property)
 .Parameter headers
  Optional. Hashtable with additional headers for the request
 .Parameter query
  Optional. Query parameters for the invoke
 .Parameter silent
  Include this switch if you do not want the method to display URLs etc.
 .Example
  $packageUpload.state = "Uploaded"
  $packageUploaded = Invoke-IngestionApiPut -authContext $authContext -path "/products/$productId/packages/$($packageUpload.id)" -Body ($packageUpload | ConvertTo-HashTable)
#>
function Invoke-IngestionApiPut {
    Param(
        [Parameter(Mandatory=$true)]
        [HashTable] $authContext,
        [Parameter(Mandatory=$true)]
        [string] $path,
        [Parameter(Mandatory=$true)]
        [HashTable] $body,
        [Parameter(Mandatory=$false)]
        [HashTable] $headers = @{},
        [Parameter(Mandatory=$false)]
        [string] $query,
        [switch] $silent
    )

$telemetryScope = InitTelemetryScope -name $MyInvocation.InvocationName -parameterValues $PSBoundParameters -includeParameters @()
try {
    $headers += @{
        "If-Match" = $body.'@odata.etag'
    }
    Invoke-IngestionApiRestMethod -authContext $authContext -method PUT -headers $headers -path $path -query $query -body ($body | ConvertTo-Json) -silent:$silent
}
catch {
    TrackException -telemetryScope $telemetryScope -errorRecord $_
    throw
}
finally {
    TrackTrace -telemetryScope $telemetryScope
}
}

<#
 .Synopsis
  Invoke a HTTP DELETE to delete a single object through the Ingestion API
  Primary used to cancel an in progress validation
 .Description
  Returns a PSCustomObject with properties from the removed Object
 .Parameter authContext
  Authentication Context from New-BcAuthContext
 .Parameter path
  Ingestion API path as described on Swagger doc (https://ingestionapi-swagger.azureedge.net/)
 .Parameter headers
  Optional. Hashtable with additional headers for the request
 .Parameter query
  Optional. Query parameters for the invoke
 .Parameter silent
  Include this switch if you do not want the method to display URLs etc.
 .Example
  Invoke-IngestionApiDelete -authContext $authContext -path "/products/$productId/submissions/$($submission.id)"
#>
function Invoke-IngestionApiDelete {
    Param(
        [Parameter(Mandatory=$true)]
        [HashTable] $authContext,
        [Parameter(Mandatory=$true)]
        [string] $path,
        [Parameter(Mandatory=$false)]
        [HashTable] $headers = @{},
        [Parameter(Mandatory=$false)]
        [string] $query = '',
        [switch] $silent
    )

$telemetryScope = InitTelemetryScope -name $MyInvocation.InvocationName -parameterValues $PSBoundParameters -includeParameters @()
try {
    Invoke-IngestionApiRestMethod -authContext $authContext -method DELETE -headers $headers -path $path -query $query -silent:$silent
}
catch {
    TrackException -telemetryScope $telemetryScope -errorRecord $_
    throw
}
finally {
    TrackTrace -telemetryScope $telemetryScope
}
}
Export-ModuleMember -Function Invoke-IngestionApiGet, Invoke-IngestionApiGetCollection, Invoke-IngestionApiPost, Invoke-IngestionApiPut, Invoke-IngestionApiDelete

# SIG # Begin signature block
# MIInRgYJKoZIhvcNAQcCoIInNzCCJzMCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAtQrUvg3r3DQCu
# CKXS60oIMeFzwCTkpMBaPmgSS0J4GaCCDLowggX1MIID3aADAgECAhMzAAACHU0Z
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
# 1cY2L4A7GTQG1h32HHAvfQESWP0xghniMIIZ3gIBATBuMFcxCzAJBgNVBAYTAlVT
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
# c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMjQCEzMAAAIdTRnITtcPV0gAAAAAAh0w
# DQYJYIZIAWUDBAIBBQCgga4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYK
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEILeUCq4l
# m2r2ekRYg73gjbzk/HOiWevISb2vj+bXplX9MEIGCisGAQQBgjcCAQwxNDAyoBSA
# EgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20w
# DQYJKoZIhvcNAQEBBQAEggEAVeqvD9efVaeS4d7ng+mEeA+pCam0VjOKoPxXA28o
# QjQYgvZfb+UbSNR58r4Kt8Y4KAgh2yO3Ye835AiOSR2z4cIIDi0dQXPzZjjBDwYq
# 0MDkdakTaQfKwwvZgYvZesokIgcTEqdtNjoBg/kVL3+Zk6wC5OlHEy+IdSpAuP/L
# MSUnnDwk7Frvon3XWKrwZcADPNTOVKQdfb8lmX/c7gKFAVlAXNmSnzwDepI8ZeS2
# ZdcIR3puVuPfiCbsXrFUukDyuIzc73bIBAMtyeFO5VVQrTa8F3qmyDiE3Hh4mxeb
# 08/C367gxp+8vAgMhPR5Lu9rJ17iNRuSqQ33PXRVclU036GCF5QwgheQBgorBgEE
# AYI3AwMBMYIXgDCCF3wGCSqGSIb3DQEHAqCCF20wghdpAgEDMQ8wDQYJYIZIAWUD
# BAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGEWQoD
# ATAxMA0GCWCGSAFlAwQCAQUABCDix9YGEkKGLK4j5AcVb0q9kFy5FCKqcU+Ehhew
# 4c2UQwIGaoV0z4mlGBMyMDI2MDgzMTA5NDQyMC40MzhaMASAAgH0oIHRpIHOMIHL
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxN
# aWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRT
# UyBFU046RjAwMi0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFNlcnZpY2WgghHqMIIHIDCCBQigAwIBAgITMwAAAiAk4ebgF7m0jgABAAAC
# IDANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAe
# Fw0yNjAyMTkxOTM5NTJaFw0yNzA1MTcxOTM5NTJaMIHLMQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmlj
# YSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046RjAwMi0wNUUw
# LUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIi
# MA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDRYY7yr7ijW6CR178uKveIMufu
# tWOicxgJwKOce/2GOQceus6ZWfX14i3jNg3JOP7MGJMkOAucwWBwiA8URp+ZYkGj
# pVoVkGZsV27WjqLwpf2AwqBsJ/TzqwE7JFFaxup3Ldxj8GjdJymDFRrdVN/pYHoB
# FrjD1IkIDu8b1CWn8tgomiKRSY+STvJq99mVkdphMBIUGOegQny8qRd24VME0xi8
# Oomks9Zq9EjDeKHGpvAbXUEQ6m3cROoEPhTE/miweQH9TqJt3IOsqPv3L8urojB7
# 47XBC2y0CDIHlKLcLl3ZG8D7JXKnWTFen3msMPJpcvrQ3zUBVJrH/mI3RxHmCh9p
# pDP0uG1+PJwk6H/x+sfoG9hW64xoXkpx6DEfNZNfcXdKbXF28XEXdLNnzo3SLNVy
# meQJhNqOSKhnU84QnKmrjEk541JiurlDCkCWO9lUBUMb9x0nyfXUbNRPVLgP+PTM
# RdXOowJdYCzCQfN2ZqL0s4YI28F1Dbn7Bgw2E4P1E9unsvMzJHtzhS2Th3TpCfBb
# OGalIlF9x/DJZ/ssm/yyzT9YtIFeqmfNxBPTE3aOuh6HxmTICzfYAATvWNhBbo19
# QwsjPeA9JvhqTLC2KUNgrXroGy4eDZo0n7jFYjZkUih1Ty+8E6qEvV2Na6Z5gUyD
# 5a+tHGDmq69CmUiHfwIDAQABo4IBSTCCAUUwHQYDVR0OBBYEFNvInOCIhxGA8mY7
# l1g07UHvyNgzMB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1Ud
# HwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3Js
# L01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggr
# BgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNv
# bS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIw
# MTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgw
# DgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUAA4ICAQCtKGBto1BSvm4WFI+J
# 0NSyVhU1LHL7F3fbjZ2d7F5Kn/FCTBZXpzrDVl63FLRNcIFpnJy4/nlg43r7T5sJ
# Pdo4Ms8ADSHQEJnHSu3x9UpjCzREBPi9+nHhvDgRx/1WmBD6gQUZJLOhcN2TxW4K
# JyhinMtiBFtkNRZ2vmZ1MAdNXTm5d0Lwk3wzj+/f7VCCTWCXJSoqNa3VU/6sACHI
# 97Evbnzg8bd3hxrfz6CcCVuf77egvRHinthJuwSRePP7aVmcevb1nWUIAICdBebH
# QOrzNIeWBIQwvcFaS3SFc+49rqrwQOMFDR4FYBzS7b0QeBVxFuLL2iVu4KAHMNUh
# LLSD4iKLDFBNTOtTzTlhGvMgG77A1cjeQrDMHa6oReMDeUDqHUrxv8g7IRdIh+h0
# gDLkzN0xIuzli0Bv7JtybGJbV6JxaDF4CzSCIMRpK59nI6iKo4LgnbQBZJW7+6ak
# YsKG/pXPlfxNv2InpD10tSCkCvw9kr6W1+NRN+EuZczRgAwWlcK9XJZ3uu/v/oxH
# tO7/kmVIs51F9qV6Y2QNXd6tU46YPrK98m2QDys+lvLNimK0e1xZ7Z1GawKohKGv
# lLALWDlZQqgHfJ31CB0LlIDI7iLyYTpd2iyKjqskbQiyMtICH+RmH/oCg7JOK0ZA
# 3XIMba9aSWgBF3QZ6pG3EGeQqjCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkA
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
# VTNYs6FwZvKhggNNMIICNQIBATCB+aGB0aSBzjCByzELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFtZXJpY2Eg
# T3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOkYwMDItMDVFMC1E
# OTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEw
# BwYFKw4DAhoDFQCTGA9vpsJ6glqCLmI0rggGx4YEEqCBgzCBgKR+MHwxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29m
# dCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBCwUAAgUA7j/DZzAiGA8y
# MDI2MDgzMTA5MDk1OVoYDzIwMjYwOTAxMDkwOTU5WjB0MDoGCisGAQQBhFkKBAEx
# LDAqMAoCBQDuP8NnAgEAMAcCAQACAjdFMAcCAQACAhH9MAoCBQDuQRTnAgEAMDYG
# CisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAIAgEA
# AgMBhqAwDQYJKoZIhvcNAQELBQADggEBAE6pD7yVpMqMvfltxZNNANYUju8qTHMB
# z/saLEZbLvt/l/JUIPW+tkDrg9KN866gOhRllQV/SrKo720krAG+Sg4w4uLJY+O7
# fclh8y63x8NHWNESX4UKjDEDsPjETkWnSXIpHBaE+y9aWL/jRZpQIwkRIidrQAxf
# IGyQPyHUyJmCDuuGBThp0gBvJKaIs6RW5ZoBWp3hR9qtwks6YAFYOmSIR/Y3FKGN
# PXg5rRUe9i6DGVOL+wEeykVqfNWQfw/z8exyGCcvgZyo4b4V8FFKsl5S8WWHfKiz
# 77tR0JftuWXqrAcwyute3mvGAlp7phZNN2nuC/Z76C6LP7JtjHNaoDcxggQNMIIE
# CQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYw
# JAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAiAk4ebg
# F7m0jgABAAACIDANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0GCyqG
# SIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCChKr+eMKj33Bisq6rdDN3KarADBjcq
# tuN3sCoWsmzrfDCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EION7vyOlPA1V
# qlEp0QIVGlNd8S5YWBnKj97LuTWHSO2vMIGYMIGApH4wfDELMAkGA1UEBhMCVVMx
# EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoT
# FU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUt
# U3RhbXAgUENBIDIwMTACEzMAAAIgJOHm4Be5tI4AAQAAAiAwIgQgAUCPS728UIEc
# QDh2riTXnMsZ6zryAvF7cHudAF+2/aEwDQYJKoZIhvcNAQELBQAEggIAGelR7dBe
# jU1W8EQHJI9bveg3i0YQ+FfUv8q+PwvszNGU1n9nFgiUyrMCYqzwfyjBEl+APdPI
# uhmAQAgArhscvC0B/7mcHwM9aBHIc9GZlcWebN3rTYP0VP3qwZWKg3KzSAKK/Ghf
# bkBwoMBunB0lOb0gVM8cYi/BKBqEtzEaWMv2FXW7iCLNT0yJibIrfGt9O6lnjlgv
# 8KtDIOyuayjFQ+Q1wbWtrqUUh+XsEd/I2k96zCqkZiDgkhYhg3TYHV0BimEOPNF+
# cwFSGkEuZCK3eySfrlp7SmVGyImpl4nBPh/blG30B2SsBn49mf9W2OwjqmpQf6M6
# XG0+HGhZ1XkxSTu9tWgbBO9GH8BCqaKtaJ0cNLzXDwL+AHqISiVujGNOkpVgBBhP
# dFwocn4yw3MFTtYyanoA0I5vKvYKK/EIDoOxNktLYPPYDuAPQZ0DQPdPIYY56u9Q
# 8QMaI7KtJiU/2qbPh7YnrvMz34+Sa9F5agi/ERMc6lgT50YuKr2nIZtFmkCiYKMx
# 7J+ZrTZ2yTc6qwjC/kbDddebbBnEjXrWXQtE9KwepLTxf4Ir439KOnmZPdkn3r2M
# BviKbbJwPl5VN86gsYoVP91cJ5hDoKl902Cfhxx8Tuud2LiADI6mMG66MjK4CWnF
# hVprFLhLZbH7huzL4RS3aJVIOh8kq+8XZRQ=
# SIG # End signature block
