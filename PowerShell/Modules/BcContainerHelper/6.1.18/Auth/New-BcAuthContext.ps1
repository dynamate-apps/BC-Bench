<# 
 .Synopsis
  Function for creating a new Business Central Authorization Context
 .Description
  Function for creating a new Business Central Authorization Context
  The Authorization Context can be used to authenticate to a Business Central online tenant/environment in various function from ContainerHelper.
  The Authorization Context contains an AccessToken and you can renew the accesstoken (if necessary) by calling Renew-BcAuthContext
  Order of priority of OAuth2 flows: client_credentials, password, refresh_token, devicecode
 .Parameter clientID
  ClientID of AAD app to use for authentication. Default is a well known PowerShell AAD App ID (1950a258-227b-4e31-a9cf-717495945fc2)
 .Parameter Resource
  Resource used for OAuth2 flow. This parameter is obsolete, use scopes instead.
 .Parameter tenantID
  TenantID to use for OAuth2 flow. Default is Common
 .Parameter authority
  Authority to use for OAuth2 login. Default is https://login.microsoftonline.com/$TenantID
 .Parameter scopes
  Scopes to use for OAuth2 flow. Default is https://api.businesscentral.dynamics.com/.default
 .Parameter refreshToken
  If Refresh token is specified, the refresh_token flow will be included in the list of OAuth2 flows to try
 .Parameter clientSecret
  If ClientSecret is specified, the client_credentials flow will be included in the list of OAuth2 flows to try
 .Parameter clientAssertion
  If ClientAssertion is specified, the client_credentials flow (with ClientAssertion instead of ClientSecret) will be included in the list of OAuth2 flows to try
 .Parameter credential
  If Credential is specified, the password flow will be included in the list of OAuth2 flows to try
 .Parameter includeDeviceLogin
  Include this switch if you want to include a device login prompt if no other way to authenticate succeeds
 .Parameter deviceLoginTimeout
  Timespan indicating the timeout while waiting for user to perform devicelogin. Default is 5 minutes.
 .Parameter deviceCode
  When deviceLogin expires, the deviceCode will be returned. You can use this to re-authenticate using the deviceCode and wait for the user to authenticate.
 .Parameter silent
  Include silent to avoid unnecessary output from the function
 .Example
  $authContext = New-BcAuthContext -refreshToken $refreshTokenSecret.SecretValueText
 .Example
  $authContext = New-BcAuthContext -clientID $clientID -clientSecret $clientSecret
 .Example
  $authContext = New-BcAuthContext -includeDeviceLogin -deviceLoginTimeout ([TimeSpan]::FromHours(1))
#>
function New-BcAuthContext {
    Param(
        [string] $clientID = "1950a258-227b-4e31-a9cf-717495945fc2",
        [string] $Resource = "",
        [string] $tenantID = "Common",
        [string] $authority = "https://login.microsoftonline.com/$TenantID",
        [string] $refreshToken,
        [string] $scopes = "$($bcContainerHelperConfig.apiBaseUrl.TrimEnd('/'))/",
        $clientSecret,
        $clientAssertion,
        [PSCredential] $credential,
        [switch] $includeDeviceLogin,
        [Timespan] $deviceLoginTimeout = [TimeSpan]::FromMinutes(15),
        [string] $deviceCode = "",
        [switch] $silent
    )

$telemetryScope = InitTelemetryScope -name $MyInvocation.InvocationName -parameterValues $PSBoundParameters -includeParameters @()
try {

    if ($clientSecret -and ($clientSecret -isnot [SecureString])) {
        $clientSecret = ConvertTo-SecureString -String "$clientSecret" -AsPlainText -Force
    }
    if ($clientAssertion -and ($clientAssertion -isnot [SecureString])) {
        $clientAssertion = ConvertTo-SecureString -String "$clientAssertion" -AsPlainText -Force
    }

    if ($deviceCode) {
        $includeDeviceLogin = $true
    }

    if ($resource) {
        Write-Host -ForegroundColor Yellow "Resource parameter on New-BcAuthContext is obsolete, please use scopes parameter instead"
        $scopes = "$($resource.TrimEnd('/'))/"
    }

    $authContext = @{
        "clientID"           = $clientID
        "scopes"             = $scopes
        "tenantID"           = $tenantID
        "authority"          = $authority
        "includeDeviceLogin" = $includeDeviceLogin
        "deviceLoginTimeout" = $deviceLoginTimeout
        "deviceCode"         = $deviceCode
    }
    $accessToken = $null
    if ($clientSecret -or $clientAssertion) {
        if ($scopes.EndsWith('/')) {
            $scopes += ".default"
        }

        $TokenRequestParams = @{
            Method = 'POST'
            Uri    = "$($authority.TrimEnd('/'))/oauth2/v2.0/token"
            Body   = @{
                "grant_type"    = "client_credentials"
                "scope"         = $scopes
                "client_id"     = $clientId
            }
            Headers = @{ "Content-Type" = "application/x-www-form-urlencoded" }
        }
        if ($clientSecret) {
            $TokenRequestParams.Body += @{
                "client_secret" = ($clientSecret | Get-PlainText)
            }
        }
        else {
            $TokenRequestParams.Body += @{
                "client_assertion_type" = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
                "client_assertion" = ($clientAssertion | Get-PlainText)
            }
        }
        try {
            if (!$silent) { Write-Host "Attempting authentication to $scopes using clientCredentials..." }
            $TokenRequest = Invoke-RestMethod @TokenRequestParams -UseBasicParsing
            $accessToken = $TokenRequest.access_token
            $jwtToken = Parse-JWTtoken -token $accessToken
            if (!$silent) { Write-Host -ForegroundColor Green "Authenticated as app $($jwtToken.appid)" }

            try {
                $expiresOn = [Datetime]::new(1970,1,1).AddSeconds($jwtToken.exp)
            }
            catch {
                $expiresOn = [DateTime]::now.AddSeconds($TokenRequest)
            }

            $authContext += @{
                "AccessToken"     = $accessToken
                "UtcExpiresOn"    = $expiresOn
                "RefreshToken"    = $null
                "Credential"      = $null
                "ClientSecret"    = $clientSecret
                "ClientAssertion" = $clientAssertion
                "appid"           = $jwtToken.appid
                "name"            = ""
                "upn"             = ""
        }
            if ($tenantID -eq "Common") {
                if (!$silent) { Write-Host "Authenticated to common, using tenant id $($jwtToken.tid)" }
                $authContext.TenantId = $jwtToken.tid
            }

        }
        catch {
            Write-Host -ForegroundColor Red (GetExtendedErrorMessage $_)
            $accessToken = $null
        }
    }
    else {
        if ($scopes.EndsWith('/')) {
            $scopes += ".default offline_access"
        }

        if ($credential) {
            $TokenRequestParams = @{
                Method = 'POST'
                Uri    = "$($authority.TrimEnd('/'))/oauth2/v2.0/token"
                Body   = @{
                    "grant_type" = "password"
                    "client_id"  = $ClientId
                    "username"   = $credential.UserName
                    "password"   = ($credential.Password | Get-PlainText)
                    "scope"      = $scopes
                }
                Headers = @{ "Content-Type" = "application/x-www-form-urlencoded" }
            }
            try {
                if (!$silent) { Write-Host "Attempting authentication to $Scopes using username/password..." }
                $TokenRequest = Invoke-RestMethod @TokenRequestParams -UseBasicParsing
                $accessToken = $TokenRequest.access_token
                $jwtToken = Parse-JWTtoken -token $accessToken
                if (!$silent) { Write-Host -ForegroundColor Green "Authenticated from $($jwtToken.ipaddr) as user $($jwtToken.name) ($($jwtToken.unique_name))" }
                $authContext += @{
                    "AccessToken"     = $accessToken
                    "UtcExpiresOn"    = [Datetime]::UtcNow.AddSeconds($TokenRequest.expires_in)
                    "RefreshToken"    = $null
                    "Credential"      = $credential
                    "ClientSecret"    = $null
                    "ClientAssertion" = $null
                    "appid"           = ""
                    "name"            = $jwtToken.name
                    "upn"             = $jwtToken.unique_name
                }
                if ($TokenRequest.PSObject.Properties.Name -eq 'refresh_token') {
                    $authContext.RefreshToken = $TokenRequest.refresh_token
                }
                if ($tenantID -eq "Common") {
                    if (!$silent) { Write-Host "Authenticated to common, using tenant id $($jwtToken.tid)" }
                    $authContext.TenantId = $jwtToken.tid
                }
            }
            catch {
                Write-Host -ForegroundColor Yellow (GetExtendedErrorMessage $_).Replace('{EmailHidden}',$credential.UserName)
                $accessToken = $null
            }
        }
        if (!$accessToken -and $refreshToken) {
            $TokenRequestParams = @{
                Method = 'POST'
                Uri    = "$($authority.TrimEnd('/'))/oauth2/v2.0/token"
                Body   = @{
                    "grant_type"    = "refresh_token"
                    "client_id"     = $ClientId
                    "refresh_token" = $refreshToken
                    "scope"         = $scopes
                }
                Headers = @{ "Content-Type" = "application/x-www-form-urlencoded" }
            }
            try
            {
                if (!$silent) { Write-Host "Attempting authentication to $Scopes using refresh token..." }
                $TokenRequest = Invoke-RestMethod @TokenRequestParams -UseBasicParsing
                $accessToken = $TokenRequest.access_token
                try {
                    $jwtToken = Parse-JWTtoken -token $accessToken
                    if (!$silent) { Write-Host -ForegroundColor Green "Authenticated using refresh token as user $($jwtToken.name) ($($jwtToken.unique_name))" }
                }
                catch {
                    $accessToken = $null
                    throw "Invalid Access token"
                }
                $authContext += @{
                    "AccessToken"     = $accessToken
                    "UtcExpiresOn"    = [Datetime]::UtcNow.AddSeconds($TokenRequest.expires_in)
                    "RefreshToken"    = $TokenRequest.refresh_token
                    "Credential"      = $null
                    "ClientSecret"    = $null
                    "ClientAssertion" = $null
                    "appid"           = ""
                    "name"            = $jwtToken.name
                    "upn"             = $jwtToken.unique_name
                    }
                if ($tenantID -eq "Common") {
                    if (!$silent) { Write-Host "Authenticated to common, using tenant id $($jwtToken.tid)" }
                    $authContext.TenantId = $jwtToken.tid
                }
            }
            catch {
                Write-Host -ForegroundColor Yellow "Refresh token not valid"
            }
        }
        if (!$accessToken -and $includeDeviceLogin) {
            
            $deviceLoginStart = [DateTime]::Now
            $accessToken = ""
            $userCode = ""
            $message = ""
            $interval = 5
    
            if ($deviceCode -eq "") {
                $DeviceCodeRequestParams = @{
                    Method = 'POST'
                    Uri    = "$($authority.TrimEnd('/'))/oauth2/v2.0/devicecode"
                    Body   = @{
                        "client_id" = $ClientId
                        "scope"     = $Scopes
                    }
                    Headers = @{ "Content-Type" = "application/x-www-form-urlencoded" }
                }
                
                Write-Host "Attempting authentication to $Scopes using device login..."
                $DeviceCodeRequest = Invoke-RestMethod @DeviceCodeRequestParams -UseBasicParsing
                Write-Host $DeviceCodeRequest.message -ForegroundColor Yellow
                $deviceCode = $DeviceCodeRequest.device_code
                $userCode = $DeviceCodeRequest.user_code
                $interval = $DeviceCodeRequest.interval
                $message = $DeviceCodeRequest.message
                Write-Host -NoNewline "Waiting for authentication (interval=$interval)"
            }

            $TokenRequestParams = @{
                Method = 'POST'
                Uri    = "$($authority.TrimEnd('/'))/oauth2/v2.0/token"
                Body   = @{
                    "grant_type"  = "urn:ietf:params:oauth:grant-type:device_code"
                    "device_code" = $deviceCode
                    "client_id"   = $ClientId
                }
                Headers = @{ "Content-Type" = "application/x-www-form-urlencoded" }
            }

            while ($accessToken -eq "" -and ([DateTime]::Now.Subtract($deviceLoginStart) -lt $deviceLoginTimeout)) {
                Start-Sleep -Seconds $interval
                try {
                    $TokenRequest = Invoke-RestMethod @TokenRequestParams -UseBasicParsing
                    $accessToken = $TokenRequest.access_token
                }
                catch {
                    $tokenRequest = $null
                    $errorRecord = $_
                    try {
                        $err = ($errorRecord.ErrorDetails.Message | ConvertFrom-Json).error
                        if ($err -eq "code_expired") {
                            Write-Host
                            Write-Host -ForegroundColor Red "Authentication request expired."
                            $deviceCode = ""
                        }
                        elseif ($err -eq "expired_token") {
                            Write-Host
                            Write-Host -ForegroundColor Red "Authentication token expired!"
                            $errorRecord = "Authentication token expired!"
                            throw $errorRecord
                        }
                        elseif ($err -eq "authorization_declined") {
                            Write-Host
                            Write-Host -ForegroundColor Red "Authentication request declined!"
                            $errorRecord = "Authentication request declined!"
                            throw $errorRecord
                        }
                        elseif ($err -eq "authorization_pending") {
                            Write-Host -NoNewline "."
                        }
                        else {
                            Write-Host
                            throw $errorRecord
                        }
                    }
                    catch {
                        Write-Host 
                        throw $errorRecord
                    }
                }
            }
            if ($accessToken) {
                try {
                    $jwtToken = Parse-JWTtoken -token $accessToken
                    Write-Host
                    Write-Host -ForegroundColor Green "Authenticated from $($jwtToken.ipaddr) as user $($jwtToken.name) ($($jwtToken.unique_name))"
                }
                catch {
                    $accessToken = $null
                    throw "Invalid Access token"
                }
                $authContext += @{
                    "AccessToken"     = $accessToken
                    "UtcExpiresOn"    = [Datetime]::UtcNow.AddSeconds($TokenRequest.expires_in)
                    "RefreshToken"    = $null
                    "Credential"      = $null
                    "ClientSecret"    = $null
                    "ClientAssertion" = $null
                    "appid"           = ""
                    "name"            = $jwtToken.name
                    "upn"             = $jwtToken.unique_name
                }
                if ($TokenRequest.PSObject.Properties.Name -eq 'refresh_token') {
                    $authContext.RefreshToken = $TokenRequest.refresh_token
                }
                if ($tenantID -eq "Common") {
                    Write-Host "Authenticated to common, using tenant id $($jwtToken.tid)"
                    $authContext.TenantId = $jwtToken.tid
                }
            }
            else {
                Write-Host
                $accessToken = "N/A"
                $authContext.deviceCode = $deviceCode
                $authContext += @{
                    "AccessToken"     = $accessToken
                    "UtcExpiresOn"    = [Datetime]::Now
                    "RefreshToken"    = ""
                    "Credential"      = $null
                    "ClientSecret"    = $null
                    "ClientAssertion" = $null
                    "appid"           = ""
                    "name"            = ""
                    "upn"             = ""
                    "userCode"        = $userCode
                    "message"         = $message
                }
            }
        }
    }
    if (!$accessToken) {
        Write-Host
        Write-Host -ForegroundColor Yellow "Authentication failed"
        return $null
    }
    return $authContext
}
catch {
    TrackException -telemetryScope $telemetryScope -errorRecord $_
    throw
}
finally {
    TrackTrace -telemetryScope $telemetryScope
}
}
Export-ModuleMember -Function New-BcAuthContext

# SIG # Begin signature block
# MIInRQYJKoZIhvcNAQcCoIInNjCCJzICAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCALpCDBD96fZlaL
# nuTFtRwRPUVR0YnIDBxfOeck6H2yA6CCDLowggX1MIID3aADAgECAhMzAAACHU0Z
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
# 1cY2L4A7GTQG1h32HHAvfQESWP0xghnhMIIZ3QIBATBuMFcxCzAJBgNVBAYTAlVT
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
# c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMjQCEzMAAAIdTRnITtcPV0gAAAAAAh0w
# DQYJYIZIAWUDBAIBBQCgga4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYK
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIOxR2M15
# pqvl+22TDq+pZcI2K24D2XAGDm6kfWV3AbtAMEIGCisGAQQBgjcCAQwxNDAyoBSA
# EgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20w
# DQYJKoZIhvcNAQEBBQAEggEAkoIR7awBg19XlsluP1ctEkTXPk8LPBSkKxBVmANY
# cv3HzbZppAdiivUUYFvmlZYEzkaC88eNXg8e1mfGzu0gpyX5x1WFJZls1Gs5KFQW
# mjOYuJHvnGpH9kCRRB2X2iZD7GGvGiz5+eGmCmkPnc2u0SavilhmcdKZ2YRJKixh
# kZy4Wxc6dmPHdQxsKiu+vPlNJUNicRLZA/eYwAHLIck2OYuSM/IsC7N7RXfCgAIC
# GOglzflHmSuUE/kFL71UW2FRXulvglqdr/QsBnSNatFlKMvSAh4VwaasZyOYIDWt
# 72LSQcEHGJR/uOZFY96AtdELPR5zZC0gZdWkKJ06SL8g8KGCF5MwghePBgorBgEE
# AYI3AwMBMYIXfzCCF3sGCSqGSIb3DQEHAqCCF2wwghdoAgEDMQ8wDQYJYIZIAWUD
# BAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGEWQoD
# ATAxMA0GCWCGSAFlAwQCAQUABCChkFwTKQwYGndc+GeqfXTiTEsukf/Aktt6EpdZ
# igkTBQIGaoTCpMntGBMyMDI2MDgxOTA2Mzg0MC4yNjJaMASAAgH0oIHRpIHOMIHL
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxN
# aWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRT
# UyBFU046ODYwMy0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFNlcnZpY2WgghHpMIIHIDCCBQigAwIBAgITMwAAAiWAxzfGzap3SQABAAAC
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
# VTNYs6FwZvKhggNMMIICNAIBATCB+aGB0aSBzjCByzELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFtZXJpY2Eg
# T3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjg2MDMtMDVFMC1E
# OTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEw
# BwYFKw4DAhoDFQBTb+bKOPAjCBflhzw5EXBuSWxeDqCBgzCBgKR+MHwxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29m
# dCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBCwUAAgUA7i9BFTAiGA8y
# MDI2MDgxODIwMzc0MVoYDzIwMjYwODE5MjAzNzQxWjBzMDkGCisGAQQBhFkKBAEx
# KzApMAoCBQDuL0EVAgEAMAYCAQACASowBwIBAAICElAwCgIFAO4wkpUCAQAwNgYK
# KwYBBAGEWQoEAjEoMCYwDAYKKwYBBAGEWQoDAqAKMAgCAQACAwehIKEKMAgCAQAC
# AwGGoDANBgkqhkiG9w0BAQsFAAOCAQEAAIbtdaZdFMMQgzFZjCN0lQaPp68hUBqx
# TxuVPU1H9bDLcHbIAxZ2LDpDLvmNZSY1olrtlmOcueyvtzyyZ/ipXPwiYupb5RPq
# 9D2YC5gRyrVCskljijMug1LgOAp+/216sPWUkFm32UF1sMCkWjyJXdsko/7Iw3VJ
# M5qwiayERqDsqnZB+GTBD60V/2YNbPAwoZQx6i8m8jxDiIBsG72nzzkDIFRWr/bs
# OFVjz8VteSx9eqfy7U9a0PlHe4k9sAOfX3zHBgP+WrkOM92fsAkWdyCiaIrO/h00
# wsoeZbAc/xSF0Yrunzd/4kmZ5pHFxNVr1pOgY2Tt8+y66luHqMi/WDGCBA0wggQJ
# AgEBMIGTMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAk
# BgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAACJYDHN8bN
# qndJAAEAAAIlMA0GCWCGSAFlAwQCAQUAoIIBSjAaBgkqhkiG9w0BCQMxDQYLKoZI
# hvcNAQkQAQQwLwYJKoZIhvcNAQkEMSIEIMm7OiP1PEl8roHfS3RVGRUXYFoRprK8
# 6y1QmPtUt/YWMIH6BgsqhkiG9w0BCRACLzGB6jCB5zCB5DCBvQQgVg3uiHo43fL3
# YKYCX+UXQJjCuNZZA/p0JTFqM9IcoRAwgZgwgYCkfjB8MQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1T
# dGFtcCBQQ0EgMjAxMAITMwAAAiWAxzfGzap3SQABAAACJTAiBCBC4jcGavBTzAHe
# 4nDuAUggtHzFahgUo/3Q8gCPr1+3FDANBgkqhkiG9w0BAQsFAASCAgBQ8WJ2aAwp
# q7gwOq08TXKf7dv6THStVV75S/Qudyb2Z97SKEccTSwwWYogTcXmr6vhHrUd0chC
# ZhKdl8p46upzihPSh1nYxxJjxHDXYR6271jjrskbBuDiHweFUvfgyHOmXd19ExGR
# yaH+etcSP4kK8jGyi7uNF+9dp32YERfnXgxpb3qGqF1ireeGw3iUJkmPvY9L3EIO
# NLk5PQQPtFVfSu/E11+z5qQBeKLRFVtjG/LO983pynbYaY7DpPDTgQDpkVdsPuz4
# oZYi1WB435NNcs9S+q6nGHpHzD9poCwIrQXbz07ZiyHORN7WiQp+PA6FlSb4UY+q
# +H7WJp6jCc7Hpptsb2/saN/YNGV5mFjRc63v9+l1azNzps1qAMM+UulkdlEqTnPO
# Hg9Byq97DequsKoWvM4JErd8PISUXndKcpCdjQUda1Cc58wbkD0UEBeAAVTMVb5U
# SFBXKIkrpf6ZGxJDfl6lcEqEB6zJszUEYLKkd5qjhFbqxXzS1n1na6FQX/bSW+3P
# y4QxjSJMRi34wwMoEXMIrFrvsjQto852XF6zS3+DhIJXXbEGJS9wJ4mh1cRBvGk6
# G9x/VR5xtDZPdWMhFvhDeQmJuAw+LF795SrDEoqEWRha12kjpAowjht5heUaLXHj
# aMNrKQ6hYtN3nM8BmpmVo1zru6QyObGhGA==
# SIG # End signature block
