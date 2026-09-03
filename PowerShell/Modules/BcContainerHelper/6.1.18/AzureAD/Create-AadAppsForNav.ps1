<# 
 .Synopsis
  Create Apps in Azure Active Directory to allow Single Signon when using AAD
 .Description
  This function will create an app in AAD, to allow Web and Windows Client to use AAD for authentication
  Optionally the function can also create apps for the Excel AddIn and/or PowerBI integration
 .Parameter AadAdminCredential
  Credentials for your AAD/Office 365 administrator user, who can create apps in the AAD
 .Parameter appIdUri
  Unique Uri to identify the AAD App (typically we use the URL for the Web Client)
 .Parameter publicWebBaseUrl
  URL for the Web Client (defaults to the value of appIdUri)
 .Parameter iconPath
  Path of the image you want to use for the SSO App
 .Parameter IncludeExcelAadApp
  Add this switch to request the function to also create an AAD app for the Excel AddIn
 .Parameter IncludePowerBiAadApp
  Add this switch to request the function to also create an AAD app for the PowerBI service
 .Parameter IncludeEMailAadApp
  Add this switch to request the function to also create an AAD app for the EMail service
 .Parameter IncludeApiAccess
  Add this switch to add application permissions for Web Services API and automation API
 .Parameter Singletenant
  Indicates whether this application is singletenant
 .Parameter PreAuthorizePowerShell
  Indicates whether the well known PowerShell AppID (1950a258-227b-4e31-a9cf-717495945fc2) should be pre-authorized for access
 .Parameter useCurrentAzureAdConnection
  Specify this switch to use the current Azure AD Connection instead of invoking Connect-AzureAD (which will pop up a UI)
 .Example
  Create-AadAppsForNAV -AadAdminCredential (Get-Credential) -appIdUri https://mycontainer.mydomain/bc/
#>
function Create-AadAppsForNav {
    Param (
        [Parameter(Mandatory=$false)]
        [PSCredential] $AadAdminCredential,
        [Parameter(Mandatory=$true)]
        [string] $appIdUri,
        [Parameter(Mandatory=$false)]
        [string] $publicWebBaseUrl = $appIdUri,
        [Parameter(Mandatory=$false)]
        [string] $iconPath,
        [switch] $IncludeExcelAadApp,
        [switch] $IncludePowerBiAadApp,
        [switch] $IncludeEmailAadApp,
        [switch] $IncludeApiAccess,
        [switch] $SingleTenant,
        [switch] $preAuthorizePowerShell,
        [switch] $useCurrentAzureAdConnection,
        [Hashtable] $bcAuthContext
    )

$telemetryScope = InitTelemetryScope -name $MyInvocation.InvocationName -parameterValues $PSBoundParameters -includeParameters @()
try {

    Write-Host -ForegroundColor Red 'Create-AadAppsForBC is deprecated, please use New-AadAppsForBc instead'
    Write-Host -ForegroundColor Red 'Create-AadAppsForBC is using AzureAD to create AAD Apps (which is deprecated)'
    Write-Host -ForegroundColor Red 'New-AadAppsForBC is using Microsoft.Graph to create AAD Apps'

    $publicWebBaseUrl = "$($publicWebBaseUrl.TrimEnd('/'))/"

    if (!(Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction Ignore)) {
        Write-Host "Installing NuGet Package Provider"
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -WarningAction Ignore | Out-Null
    }

    if (!(Get-Package -Name AzureAD -ErrorAction Ignore)) {
        Write-Host "Installing AzureAD PowerShell package"
        Install-Package AzureAD -Force -WarningAction Ignore | Out-Null
    }

    # Connect to AzureAD
    if ($useCurrentAzureAdConnection) {
        $account = Get-AzureADCurrentSessionInfo
    }
    elseif ($bcAuthContext) {
        $bcAuthContext = Renew-BcAuthContext -bcAuthContext $bcAuthContext
        $jwtToken = Parse-JWTtoken -token $bcAuthContext.accessToken
        if ($jwtToken.aud -ne 'https://graph.windows.net') {
            Write-Host -ForegroundColor Yellow "The accesstoken was provided for $($jwtToken.aud), should have been for https://graph.windows.net"
        }
        $account = Connect-AzureAD -AadAccessToken $bcAuthContext.accessToken -AccountId $jwtToken.upn
    }
    else {
        if ($AadAdminCredential) {
            $password = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($AadAdminCredential.Password))
            if ($password.Length -gt 100) {
                $account = Connect-AzureAD -AadAccessToken $password -AccountId $AadAdminCredential.UserName
            }
            else {
                $account = Connect-AzureAD -Credential $AadAdminCredential
            }
        }
        else {
            $account = Connect-AzureAD
        }
    }

    $AdProperties = @{}
    $adUserObjectId = 0

    $aadDomain = $account.TenantDomain
    $aadTenant = $account.TenantId
    $AdProperties["AadTenant"] = $AadTenant

    if ($account.Account.Type -eq 'ServicePrincipal') {
        $adUser = Get-AzureADServicePrincipal -Filter "AppId eq '$($account.Account.Id)'"
    } else {
        $adUser = Get-AzureADUser -ObjectId $account.Account.Id
    }
    if (!$adUser) {
        throw "Could not identify Aad Tenant"
    }

    $adUserObjectId = $adUser.ObjectId
    
    # Remove "old" AD Application
    Get-AzureADMSApplication -All $true | Where-Object { $_.IdentifierUris -contains $appIdUri } | ForEach-Object { Remove-AzureADMSApplication -ObjectId $_.Id }

    $signInReplyUrls = @("$($publicWebBaseUrl.ToLowerInvariant())SignIn",$publicWebBaseUrl.ToLowerInvariant().TrimEnd('/'))
    $oAuthReplyUrls = @("$($publicWebBaseUrl.ToLowerInvariant())OAuthLanding.htm")
    if ($publicWebBaseUrl.ToLowerInvariant() -cne $publicWebBaseUrl) {
        $signInReplyUrls += @("$($publicWebBaseUrl)SignIn",$publicWebBaseUrl.TrimEnd('/'))
        $oAuthReplyUrls += @("$($publicWebBaseUrl)OAuthLanding.htm")
    }


    Write-Host "Creating AAD App for WebClient"
    if ($SingleTenant.IsPresent) {
        $signInAudience = 'AzureADMyOrg'
    }
    else {
        $signInAudience = 'AzureADMultipleOrgs'
    }

    $informationalUrl = @{
    }
    if ($iconPath) {
        $informationalUrl += @{ 
            "LogoUrl" = $iconPath
        }
    }

    $ssoAdApp = New-AzureADMSApplication `
        -DisplayName "WebClient for $publicWebBaseUrl" `
        -IdentifierUris $appIdUri `
        -Web @{ "ImplicitGrantSettings" = @{ "EnableIdTokenIssuance" = $true }; "RedirectUris" = $signInReplyUrls } `
        -SignInAudience $signInAudience `
        -InformationalUrl @{ "LogoUrl" = $iconPath } `
        -RequiredResourceAccess @(
            @{ ResourceAppId = "00000003-0000-0000-c000-000000000000"; ResourceAccess = @(             # Microsoft Graph
                [PSCustomObject]@{ "Id" = "e1fe6dd8-ba31-4d61-89e7-88639da4683d"; "Type" = "Scope" }   # User.Read
                [PSCustomObject]@{ "Id" = "9769c687-087d-48ac-9cb3-c37dde652038"; "Type" = "Scope" }   # EWS.AccessAsUser.All
                [PSCustomObject]@{ "Id" = "5fa075e9-b951-4165-947b-c63396ff0a37"; "Type" = "Scope" }   # PrinterShare.ReadBasic.All
                [PSCustomObject]@{ "Id" = "21f0d9c0-9f13-48b3-94e0-b6b231c7d320"; "Type" = "Scope" }   # PrintJob.Create
                [PSCustomObject]@{ "Id" = "6a71a747-280f-4670-9ca0-a9cbf882b274"; "Type" = "Scope" }   # PrintJob.ReadBasic
            )}
            @{ ResourceAppId = "00000009-0000-0000-c000-000000000000"; ResourceAccess =                # Power BI Service
                [PSCustomObject]@{ "Id" = "4ae1bf56-f562-4747-b7bc-2fa0874ed46f"; "Type" = "Scope" }   # Report.Read.All
            }
            @{ ResourceAppId = "00000003-0000-0ff1-ce00-000000000000"; ResourceAccess = @(             # SharePoint
                [PSCustomObject]@{ "Id" = "640ddd16-e5b7-4d71-9690-3f4022699ee7"; "Type" = "Scope" }   # AllSites.Write
                [PSCustomObject]@{ "Id" = "2cfdc887-d7b4-4798-9b33-3d98d6b95dd2"; "Type" = "Scope" }   # MyFiles.Write
            )}
         )

    $admspwd = New-AzureADMSApplicationPassword -ObjectId $SsoAdApp.Id -PasswordCredential @{ "DisplayName" = "Password" }
    $AdProperties["SsoAdAppKeyValue"] = $admspwd.SecretText

    $SsoAdAppId = $ssoAdApp.AppId.ToString()
    $AdProperties["SsoAdAppId"] = $SsoAdAppId

    # Get oauth2 permission id for sso app
    $oauth2permissionid = [GUID]::NewGuid().ToString()
    $ssoAdApp.Api.Oauth2PermissionScopes.Add(@{
        "Id" = $oauth2permissionid
        "value" = "user_impersonation"
        "Type" = "User"
        "adminConsentDisplayName" = "Access WebClient for $publicWebBaseUrl"
        "adminConsentDescription" = "Allow the application to access WebClient for $publicWebBaseUrl on behalf of the signed-in user."
        "userConsentDisplayName" = "Access WebClient for $publicWebBaseUrl"
        "userConsentDescription" = "Allow the application to access WebClient for $publicWebBaseUrl on your behalf."
        "IsEnabled" = $true
    })
    Set-AzureADMSApplication -ObjectId $ssoAdApp.Id -Api $ssoAdApp.Api

    if ($IncludeApiAccess) {
        $appRoleId = [Guid]::NewGuid().ToString()
        Set-AzureADMSApplication `
            -ObjectId $ssoAdApp.id `
            -AppRoles @{
                 "Id" = $appRoleId
                 "DisplayName" = "API.ReadWrite.All"
                 "Description" = "Full access to web services API"
                 "Value" = "API.ReadWrite.All"
                 "IsEnabled" = $true
                 "AllowedMemberTypes" = @("Application","User")
             }
    }

    if ($preAuthorizePowerShell) {
        $ssoAdApp.Api.PreAuthorizedApplications.Add(@{ "AppId" = "1950a258-227b-4e31-a9cf-717495945fc2"; "DelegatedPermissionIds" = @($oauth2permissionid) })
        Set-AzureADMSApplication -ObjectId $ssoAdApp.Id -Api $ssoAdApp.Api
    }

    # API Access Aad App
    if ($IncludeApiAccess) {
        # Remove "old" Api AAD Application
        $ApiIdentifierUri = $appIdUri.Replace('://','://api.')
        Get-AzureADMSApplication -All $true | Where-Object { $_.IdentifierUris -contains $ApiIdentifierUri } | ForEach-Object { Remove-AzureADMSApplication -ObjectId $_.Id }
    
        # Create AD Application
        Write-Host "Creating AAD App for API Access"
        $apiAdApp = New-AzureADMSApplication `
            -DisplayName "API Access for $publicWebBaseUrl" `
            -IdentifierUris $ApiIdentifierUri `
            -Web @{ "RedirectUris" = $oAuthReplyUrls } `
            -SignInAudience $signInAudience `
            -RequiredResourceAccess @(
                @{ ResourceAppId = "$SsoAdAppId"; ResourceAccess = @(                                      # BC SSO App
                    [PSCustomObject]@{ "Id" = "$oauth2permissionid";                  "Type" = "Scope" }   # OAuth2
                    [PSCustomObject]@{ "Id" = "$appRoleId";                           "Type" = "Role" }    # API.ReadWrite.All
                )}
                @{ ResourceAppId = "00000003-0000-0000-c000-000000000000"; ResourceAccess =                # Microsoft Graph
                    [PSCustomObject]@{ "Id" = "e1fe6dd8-ba31-4d61-89e7-88639da4683d"; "Type" = "Scope" }   # User.Read
                }
             )
        
        $apiAdAppId = $apiAdApp.AppId.ToString()
        $AdProperties["ApiAdAppId"] = $apiAdAppId 
    
        $admspwd = New-AzureADMSApplicationPassword -ObjectId $apiAdApp.Id -PasswordCredential @{ "DisplayName" = "Password" }
        $AdProperties["ApiAdAppKeyValue"] = $admspwd.SecretText

        $sp = @( $null, $null )
        $idx = 0
        $ssoAdAppId,$apiAdAppId | % {
            $appId = $_
            $app = Get-AzureADApplication -All $true | Where-Object { $_.AppId -eq $appId }
            if (!$app) {
                Write-Host -NoNewline "Waiting for AD App synchronization."
                do {
                    Start-Sleep -Seconds 2
                    $app = Get-AzureADApplication -All $true | Where-Object { $_.AppId -eq $appId }
                } while (!$app)
            }
            $sp[$idx] = Get-AzureADServicePrincipal -All $true | Where-Object { $_.AppId -eq $appId }
            if (!$sp[$idx]) {
                $sp[$idx] = New-AzureADServicePrincipal -AppId $appId -Tags @("WindowsAzureActiveDirectoryIntegratedApp")
            }
            $idx++
        }
        New-AzureADServiceAppRoleAssignment -ObjectId $sp[1].ObjectId -PrincipalId $sp[1].ObjectId -ResourceId $sp[0].ObjectId -Id $appRoleId | Out-Null
    }

    # Excel Ad App
    if ($IncludeExcelAadApp) {
        # Remove "old" Excel AD Application
        $ExcelIdentifierUri = $appIdUri.Replace('://','://xls.')
        Get-AzureADMSApplication -All $true | Where-Object { $_.IdentifierUris -contains $ExcelIdentifierUri } | ForEach-Object { Remove-AzureADMSApplication -ObjectId $_.Id }

        # Create AD Application
        Write-Host "Creating AAD App for Excel Add-in"
        $excelAdApp = New-AzureADMSApplication `
            -DisplayName "Excel AddIn for $publicWebBaseUrl" `
            -IdentifierUris $ExcelIdentifierUri `
            -Web @{ "ImplicitGrantSettings" = @{ "EnableIdTokenIssuance" = $true; "EnableAccessTokenIssuance" = $true }; "RedirectUris" = ($oAuthReplyUrls+@("https://az689774.vo.msecnd.net/dynamicsofficeapp/v1.3.0.0/*")) } `
            -SignInAudience $signInAudience `
            -RequiredResourceAccess @(
                @{ ResourceAppId = "$SsoAdAppId"; ResourceAccess =                                         # BC SSO App
                    [PSCustomObject]@{ "Id" = "$oauth2permissionid";                  "Type" = "Scope" }   # Oauth2
                }
                @{ ResourceAppId = "00000003-0000-0000-c000-000000000000"; ResourceAccess =                # Microsoft Graph
                    [PSCustomObject]@{ "Id" = "e1fe6dd8-ba31-4d61-89e7-88639da4683d"; "Type" = "Scope" }   # User.Read
                }
             )

        $ExcelAdAppId = $excelAdApp.AppId.ToString()
        $AdProperties["ExcelAdAppId"] = $ExcelAdAppId

        $admspwd = New-AzureADMSApplicationPassword -ObjectId $excelAdApp.Id -PasswordCredential @{ "DisplayName" = "Password" }
        $AdProperties["ExcelAdAppKeyValue"] = $admspwd.SecretText
    }

    # PowerBI Ad App
    if ($IncludePowerBiAadApp) {
        # Remove "old" PowerBI AD Application
        $PowerBiIdentifierUri = $appIdUri.Replace('://','://pbi.')
        Get-AzureADMSApplication -All $true | Where-Object { $_.IdentifierUris -contains $PowerBiIdentifierUri } | ForEach-Object { Remove-AzureADMSApplication -ObjectId $_.Id }
    
        # Create AD Application
        Write-Host "Creating AAD App for PowerBI Service"
        $powerBiAdApp = New-AzureADMSApplication `
            -DisplayName "PowerBI Service for $publicWebBaseUrl" `
            -IdentifierUris $PowerBiIdentifierUri `
            -Web @{ "RedirectUris" = $oAuthReplyUrls } `
            -SignInAudience $signInAudience `
            -RequiredResourceAccess @(
                @{ ResourceAppId = "00000009-0000-0000-c000-000000000000"; ResourceAccess =                # Power BI Service
                    [PSCustomObject]@{ "Id" = "4ae1bf56-f562-4747-b7bc-2fa0874ed46f"; "Type" = "Scope" }   # Report.Read.All
                }
                @{ ResourceAppId = "00000003-0000-0000-c000-000000000000"; ResourceAccess =                # Microsoft Graph
                    [PSCustomObject]@{ "Id" = "e1fe6dd8-ba31-4d61-89e7-88639da4683d"; "Type" = "Scope" }   # User.Read
                }
             )
          
        $PowerBiAdAppId = $powerBiAdApp.AppId.ToString()
        $AdProperties["PowerBiAdAppId"] = $PowerBiAdAppId 
    
        $admspwd = New-AzureADMSApplicationPassword -ObjectId $PowerBiAdApp.Id -PasswordCredential @{ "DisplayName" = "Password" }
        $AdProperties["PowerBiAdAppKeyValue"] = $admspwd.SecretText
    }

    # EMail App
    if ($IncludeEmailAadApp) {
        # Remove "old" Email AD Application
        $EMailIdentifierUri = $appIdUri.Replace('://','://email.')
        Get-AzureADMSApplication -All $true | Where-Object { $_.IdentifierUris -contains $EMailIdentifierUri } | ForEach-Object { Remove-AzureADMSApplication -ObjectId $_.Id }
    
        # Create AD Application
        Write-Host "Creating AAD App for EMail Service"
        $EMailAdApp = New-AzureADMSApplication `
            -DisplayName "EMail Service for $publicWebBaseUrl" `
            -IdentifierUris $EMailIdentifierUri `
            -Web @{ "ImplicitGrantSettings" = @{ "EnableIdTokenIssuance" = $true; "EnableAccessTokenIssuance" = $true }; "RedirectUris" = $oAuthReplyUrls } `
            -SignInAudience $signInAudience `
            -RequiredResourceAccess `
                @{ ResourceAppId = "00000003-0000-0000-c000-000000000000"; ResourceAccess = @(             # Microsoft Graph
                    [PSCustomObject]@{ "Id" = "e1fe6dd8-ba31-4d61-89e7-88639da4683d"; "Type" = "Scope" }   # User.Read
                    [PSCustomObject]@{ "Id" = "64a6cdd6-aab1-4aaf-94b8-3cc8405e90d0"; "Type" = "Scope" }   # Email
                    [PSCustomObject]@{ "Id" = "e383f46e-2787-4529-855e-0e479a3ffac0"; "Type" = "Scope" }   # Mail.ReadWrite
                    [PSCustomObject]@{ "Id" = "024d486e-b451-40bb-833d-3e66d98c5c73"; "Type" = "Scope" }   # Mail.Send
                )}
        
        $EMailAdAppId = $EMailAdApp.AppId.ToString()
        $AdProperties["EMailAdAppId"] = $EMailAdAppId 
    
        $admspwd = New-AzureADMSApplicationPassword -ObjectId $EmailAdApp.Id -PasswordCredential @{ "DisplayName" = "Password" }
        $AdProperties["EMailAdAppKeyValue"] = $admspwd.SecretText
    }

    $AdProperties
}
catch {
    TrackException -telemetryScope $telemetryScope -errorRecord $_
    throw
}
finally {
    TrackTrace -telemetryScope $telemetryScope
}
}
Set-Alias -Name Create-AadAppsForBC -Value Create-AadAppsForNav
Export-ModuleMember -Function Create-AadAppsForNav -Alias Create-AadAppsForBC

# SIG # Begin signature block
# MIInSQYJKoZIhvcNAQcCoIInOjCCJzYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCBca0uXc3llOnX
# lFWH/Dz1iUZdwEwlvE2Q2M6c8MyzF6CCDLowggX1MIID3aADAgECAhMzAAACHU0Z
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
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEILkEwIwE
# vJR2XSkRBxPZNm288j7bowXIdMG44Rar5EVRMEIGCisGAQQBgjcCAQwxNDAyoBSA
# EgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20w
# DQYJKoZIhvcNAQEBBQAEggEARcIz6GLCVbkV5Hmo9xkGFCCjqi6sLIy/QEo9R6uT
# xHybRxNBzUYOb0uha14AqpyyT2kBdufH0P1dvghjkFMoE6hQYkJBdZMG+AmXVY+q
# RM4y0anIy0KlBRugg7GXIRxv5SD272yjH1ykzc1I0CeiicYqgjYasOh5pPB0LtCY
# 2Ws49xlAOmn6bPuoldTObgWAdTDovwcXQGZ16d1Rd9q/XuXh/iskgBUIHgrAwo1H
# u52h6JBFtKHArjiXM+WeITrphvBfisk8h4Mpk3X7R9yjKCeLD8ae73mF1HYdiaDH
# RexRKv6oBxfx8A7I49gkvOv0+83ulBKg8l/M5ot2XYWn+qGCF5cwgheTBgorBgEE
# AYI3AwMBMYIXgzCCF38GCSqGSIb3DQEHAqCCF3AwghdsAgEDMQ8wDQYJYIZIAWUD
# BAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGEWQoD
# ATAxMA0GCWCGSAFlAwQCAQUABCD/oVtv8FnLclHPFxoYQnvpk/tZDZGN53ok55al
# KmBaSwIGaoVY7GH1GBMyMDI2MDgyNzA2Mjk0MS45NjZaMASAAgH0oIHRpIHOMIHL
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxN
# aWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRT
# UyBFU046OTYwMC0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFNlcnZpY2WgghHtMIIHIDCCBQigAwIBAgITMwAAAiY1tD5nQ5P2HwABAAAC
# JjANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAe
# Fw0yNjAyMTkxOTQwMDJaFw0yNzA1MTcxOTQwMDJaMIHLMQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmlj
# YSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046OTYwMC0wNUUw
# LUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIi
# MA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC//w+ZZIL5RFFpVI8D3ZyuNu8I
# zcAEOD30OLYjh337rXjcrIlOSzpJc4ZeUxEyli6x6F6zm4NR8dbPb9diDp/hOUzH
# WGxiA1Z3RXKBb/4F/ojyvN43SEGWqSfVc3I3BlsYT35ecVAJ9kVf90YOv29tFjJB
# BZkYvrT/DwwyRLscOyP4p+9/lyJjD+ULs3YXBhVrfZ+MbQB+BYKLqRvBKbj/wR9a
# kNrMxQINoGaD5jZO/N/nSsmG2P1zv/cv4gSoMBnWeQIBkjd2I5w1DeXupp2vSiNm
# R5sA2ZkBK3yiQWaJvRxODlkfiyHk9Mkk/TrYTjmjPCbhe+uqhHNRy8UlbOvWsCq0
# tRtUykHv39DgqAfJNrE8OSt835rBzDprrcAhwmgfhoVi4AKeqwikY0nUa48K0Qy8
# 0XT4fiEA3ExEZNaRFo9Nq/GwbfgqKqGmc9xhKuRFcjtua4KHZvnAvpWgEFSOCkov
# Xs/BcLnkEHM9xZ8iUag5CyhNqXYYE/z0pcXdYaNIkQ68EWmuvLm7g9oofV2vOm5G
# VNoghnkWG6nGPo/JwEgmA9oSS0EfvFRMWPA/gpSvF3shArKHnaEpVSSi3DNbyiuY
# iEs9Ko0IkZc8xKFeQRaqGRxrB+2r/7B3X81Tps99KhFwg+wD87od22F2MUg1x7tw
# t3gaVnFk0IZIwUPCGwIDAQABo4IBSTCCAUUwHQYDVR0OBBYEFF3hn9fYJN2Y/Z9L
# VbBPIxAzXHsQMB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1Ud
# HwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3Js
# L01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggr
# BgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNv
# bS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIw
# MTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgw
# DgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUAA4ICAQA2Ux0tr9sYCjsq0FRy
# iVpx15OurNXv6Qk7iX+ArVPlz3w4tqjcTNm1dt3tTua2wJMpJhPH8n7UXhmT98d5
# Du44Ll4adnse4SQfVg3QL6aRkXHnJUn8y9iftB/Py22n9xnwPFfj3QlDOSgLuHle
# u97U0iH2ZaluYabWXJihdiYpK8cPHFlqZOAiot0+GD8dP+RMuvpxt/F2LmYelpoZ
# wriiFOUmlxEUV7xJHyZZlDquskeyuq01DTv91N4qM8cfPPhl/2pc4HeMf/nd2Hou
# ifJbDQFNd4WPhLzn0Sy3u1Zh3+S3tjQdqN+dyw60RaV+RXCoOLgFZ3MAg/GoDl+f
# vb5hy/1a71ctX8wEad1Pf6def2pqfl3wFc++hkF8DXXTZofJN4YVaN3InwbAGQDD
# kNK4lqecCixxmSKwidPynGeE5OtvNoK1pkLsm/i8F1RjGczZ/kSF2VDkqG866iQ+
# jVbGOQ6Du3eyyFcFKZoDJ4B5mEAS9aT2SKqllLeybOboH6r67siR5B/2Hnu7+KYu
# YZy0BEadtA6ngG4cnSR9JsrkhhsKmb11ujqwgJyNx92MsoGGwNgN1aI0QID8CsjC
# FwpfmMzlA44xHKYv3hmjxeqBS4uU5rQeiAnVgpJeaVGKm/lzPDtnppGV+7XhRp5b
# 1ZxT/Z7Xxc+I7H7/jCtQDZoaZTCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkA
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
# T3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjk2MDAtMDVFMC1E
# OTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEw
# BwYFKw4DAhoDFQCi/fMxFtkqr7XMXdsRyWU0lSKHZ6CBgzCBgKR+MHwxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29m
# dCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBCwUAAgUA7jm5ajAiGA8y
# MDI2MDgyNjE5MTM0NloYDzIwMjYwODI3MTkxMzQ2WjB3MD0GCisGAQQBhFkKBAEx
# LzAtMAoCBQDuOblqAgEAMAoCAQACAgVvAgH/MAcCAQACAhPyMAoCBQDuOwrqAgEA
# MDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAI
# AgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBAAX0FnCR88RCyazLOdZ+TTKQQmmE
# PwfeE/riH4Ie6ckR548QfN1iEqZ8M2baOA/tJcN5nFJnQA5QuVuKAFcdqDwB+E5g
# X3zQzV5EJCB2iKnpKTzhmL4eF8+wkUcWaKPnzfxiAYHJYiF+eRfj8wnTfsRwBG7h
# zxTXe/Wt5aijSji7H48XzIwvgrhVNq6sur2Q2iZwpqfjZWwbexV92jq+zEwXOXIY
# d5wIYDTcp0VwKyabxli8EjbtpgLxwONipKYJneG8ad+hgxdIp3GXKBQEE4PR9Aos
# Rb3d3fVWSRnv7sSAbTj2d04NG5SP+w5PwQXbUhbg1bPVDvIwYhZ5ExKKk+gxggQN
# MIIECQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQ
# MA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
# MSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAiY1
# tD5nQ5P2HwABAAACJjANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0G
# CyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCDK9h8K8m9jX+NErmoFQxqkqu2n
# sfLjCNKC9/+3ILRUajCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EIMwyXGFn
# TNsZRBrs6GN/BbV0okaNP3VBYqLFjUsFnbgqMIGYMIGApH4wfDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgUENBIDIwMTACEzMAAAImNbQ+Z0OT9h8AAQAAAiYwIgQg4RWuKsf4
# M+wbtxXql7QbH++jD59EOD9zWtx97APKemcwDQYJKoZIhvcNAQELBQAEggIAKlE6
# /Vf1KqTjS7dtPKycRoTnEuSwAxS96tg1ckuz/p87pNmbq5qs7Yd6l5Tnyjy8pTmj
# HgTjKTrCfbdREknaYzbeIRcddR8tawD/z+gyDb4xwEhT5pGe9q68jRITBswv5nE/
# mRN8g4zE2NSxL8mdwWlEDG5pc0JjERsT6klPGexN8GmGWMFiMsh4x1af4uELmBrM
# ev/PRPJhcVkAVdcYnVyS4cajTB0NBAMaUiGM0sdog36n49FfIq1eTF0GZwq1x5eF
# eCFlVvI3CaORRYthpjAZCvv7IbFIWKelRlpsDW1atDyBlL0/73o/qluZTXEaqmKi
# Mn6No+2myM/6E6H4rtYjRgNI17ht0SPNm3gTbw75rTjGWfPXnF8YWIScVaOrWiGP
# NM+pXaD9IDWh3dmRcZlJqEmqyl9wRV9LcT0ItyHpzb/VJhy4lqp18nZSp4vnUadi
# hOTfrm6EqqT0KFdQD6gp3ixECnD0+HcS+Q/Vw4a/FZr87d0yxhzu1ytexinUbJQ1
# WD09AroX58VMeIqNXB5wpJxr1kuq+txtWc4Ua4wAEULNqVjZ3k+zphOrYyM3C1fm
# jlhSpYWQ/46NRa85W0GwQPSCFJ+0jOow+c9w54VCOyPoCx2RWGcUOgaheXO3ozLt
# 52MO0oW26Wg8P6YT1gxSQGKtLdFe8Zhliv/02J0=
# SIG # End signature block
