<# 
 .Synopsis
  Create Apps in Azure Active Directory to allow Single Signon when using AAD
 .Description
  This function will create an app in AAD, to allow Web and Windows Client to use AAD for authentication
  Optionally the function can also create apps for the Excel AddIn and/or Other services integration
 .Parameter accessToken
  Accesstoken for Microsoft Graph with permissions to create apps in the AAD
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
 .Parameter IncludeOtherServicesAadApp
  Add this switch to request the function to also create an AAD app for other services (including PowerBI, SharePoint, Universal Print, etc.)
  https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/administration/register-app-azure
 .Parameter IncludeApiAccess
  Add this switch to add application permissions for Web Services API and automation API
 .Parameter Singletenant
  Indicates whether this application is singletenant
 .Parameter PreAuthorizePowerShell
  Indicates whether the well known PowerShell AppID (1950a258-227b-4e31-a9cf-717495945fc2) should be pre-authorized for access
 .Parameter useCurrentMicrosoftGraphConnection
  Specify this switch to use the current Microsoft Graph Connection instead of invoking Connect-MgGraph (which will pop up a UI)
 .Parameter autoConsent
  Specify that this will automatically grant Admin permissions to the created application registration. (Cloud Application Administrator role required)
 .Example
  New-AadAppsForBC -accessToken $accessToken -appIdUri https://mycontainer.mydomain/bc/
 .Example
  $bcAuthContext = New-BcAuthContext -tenantID $azureTenantId -clientID $azureApplicationId -clientSecret $clientSecret -scopes "https://graph.microsoft.com/.default"
  $AdProperties = New-AadAppsForBc -appIdUri https://mycontainer.mydomain/bc/ -bcAuthContext $bcAuthContext 
#>
function New-AadAppsForBc {
    Param (
        [Parameter(Mandatory=$false)]
        [string] $accessToken,
        [Parameter(Mandatory=$true)]
        [string] $appIdUri,
        [Parameter(Mandatory=$false)]
        [string] $publicWebBaseUrl = $appIdUri,
        [Parameter(Mandatory=$false)]
        [string] $iconPath,
        [switch] $IncludeExcelAadApp,
        [switch] $IncludePowerBiAadApp,
        [switch] $IncludeEmailAadApp,
        [switch] $IncludeOtherServicesAadApp,
        [switch] $IncludeApiAccess,
        [switch] $SingleTenant,
        [switch] $preAuthorizePowerShell,
        [switch] $useCurrentMicrosoftGraphConnection,
        [Hashtable] $bcAuthContext,
        [switch] $autoConsent
    )

$telemetryScope = InitTelemetryScope -name $MyInvocation.InvocationName -parameterValues $PSBoundParameters -includeParameters @()
try {

    $publicWebBaseUrl = "$($publicWebBaseUrl.TrimEnd('/'))/"

    if (!(Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction Ignore)) {
        Write-Host "Installing NuGet Package Provider"
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -WarningAction Ignore | Out-Null
    }

    if (!(Get-Package -Name Microsoft.Graph -ErrorAction Ignore)) {
        Write-Host "Installing Microsoft.Graph PowerShell package"
        Install-Package Microsoft.Graph -Force -WarningAction Ignore | Out-Null
    }

    # Connect to Microsoft.Graph
    if (!$useCurrentMicrosoftGraphConnection) {
        if ($bcAuthContext) {
            $bcAuthContext = Renew-BcAuthContext -bcAuthContext $bcAuthContext
            $jwtToken = Parse-JWTtoken -token $bcAuthContext.accessToken
            if ($jwtToken.aud -ne 'https://graph.microsoft.com') {
                Write-Host -ForegroundColor Yellow "The accesstoken was provided for $($jwtToken.aud), should have been for https://graph.microsoft.com"
            }
            $accessToken = $bcAuthContext.accessToken
        }
        if ($accessToken) {
            # Check the AccessToken since Microsoft Graph V2 requires a SecureString
            $graphAccessTokenParameter = (Get-Command Connect-MgGraph).Parameters['AccessToken']
            if ($graphAccessTokenParameter.ParameterType -eq [securestring]) {
                Connect-MgGraph -AccessToken (ConvertTo-SecureString -String $accessToken -AsPlainText -Force) | Out-Null
            }
            else {
                Connect-MgGraph -AccessToken $accessToken | Out-Null
            }
        }
        else {
            Connect-MgGraph -Scopes 'Application.ReadWrite.All' | Out-Null
        }
    }
    $account = Get-MgContext

    $AdProperties = @{}

    $aadTenant = $account.TenantId
    $AdProperties["AadTenant"] = $AadTenant

    if ($null -eq $account.Account) {
        $adUser = Get-MgServicePrincipal -Filter "AppId eq '$($account.ClientId)'"
    } else {
        $adUser = Get-MgUser -UserId $account.Account
    }
    if (!$adUser) {
        throw "Could not identify Aad Tenant"
    }
    
    # Remove "old" AD Application
    Get-MgApplication -All | Where-Object { $_.IdentifierUris -contains $appIdUri } | ForEach-Object { Remove-MgApplication -ApplicationId $_.Id }

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
    $graphRRA = New-Object -TypeName Microsoft.Graph.PowerShell.Models.MicrosoftGraphRequiredResourceAccess
    $graphRRA.ResourceAppId = "00000003-0000-0000-c000-000000000000" # Well-known ID, the same across all tenants 
    $graphRRA.ResourceAccess = @(
        @{ Id = "e1fe6dd8-ba31-4d61-89e7-88639da4683d"; Type = "Scope" }   # User.Read
        @{ Id = "9769c687-087d-48ac-9cb3-c37dde652038"; Type = "Scope" }   # EWS.AccessAsUser.All
        @{ Id = "5fa075e9-b951-4165-947b-c63396ff0a37"; Type = "Scope" }   # PrinterShare.ReadBasic.All
        @{ Id = "21f0d9c0-9f13-48b3-94e0-b6b231c7d320"; Type = "Scope" }   # PrintJob.Create
        @{ Id = "6a71a747-280f-4670-9ca0-a9cbf882b274"; Type = "Scope" }   # PrintJob.ReadBasic
    )
    $powerBIRRA = New-Object -TypeName Microsoft.Graph.PowerShell.Models.MicrosoftGraphRequiredResourceAccess
    $powerBIRRA.ResourceAppId = "00000009-0000-0000-c000-000000000000" # Power BI Service
    $powerBIRRA.ResourceAccess = @(
        @{ "Id" = "4ae1bf56-f562-4747-b7bc-2fa0874ed46f"; "Type" = "Scope" }   # Report.Read.All
    )
    $sharepointRRA = New-Object -TypeName Microsoft.Graph.PowerShell.Models.MicrosoftGraphRequiredResourceAccess
    $sharepointRRA.ResourceAppId = "00000003-0000-0ff1-ce00-000000000000" # SharePoint
    $sharepointRRA.ResourceAccess = @(
        @{ "Id" = "640ddd16-e5b7-4d71-9690-3f4022699ee7"; "Type" = "Scope" }   # AllSites.Write
        @{ "Id" = "2cfdc887-d7b4-4798-9b33-3d98d6b95dd2"; "Type" = "Scope" }   # MyFiles.Write
    )
    $resourceAccessList = @($graphRRA, $powerBIRRA, $sharepointRRA)

    $ssoAdApp = New-MgApplication `
        -DisplayName "WebClient for $publicWebBaseUrl" `
        -IdentifierUris $appIdUri `
        -Web @{ ImplicitGrantSettings = @{ EnableIdTokenIssuance = $true }; RedirectUris = $signInReplyUrls } `
        -SignInAudience $signInAudience `
        -Info @{ "LogoUrl" = $iconPath } `
        -RequiredResourceAccess $resourceAccessList

    $admspwd = Add-MgApplicationPassword -ApplicationId $ssoAdApp.Id -PasswordCredential @{ "DisplayName" = "Password" }
    $AdProperties["SsoAdAppKeyValue"] = $admspwd.SecretText

    $ssoAdAppId = $ssoAdApp.AppId.ToString()
    $AdProperties["SsoAdAppId"] = $ssoAdAppId

    # Get oauth2 permission id for sso app
    $oauth2permissionid = [GUID]::NewGuid().ToString()
    $oauth2PermissionScopes = $ssoAdApp.Api.Oauth2PermissionScopes
    $oauth2PermissionScopes +=  @{
        "Id" = $oauth2permissionid
        "value" = "user_impersonation"
        "Type" = "User"
        "adminConsentDisplayName" = "Access WebClient for $publicWebBaseUrl"
        "adminConsentDescription" = "Allow the application to access WebClient for $publicWebBaseUrl on behalf of the signed-in user."
        "userConsentDisplayName" = "Access WebClient for $publicWebBaseUrl"
        "userConsentDescription" = "Allow the application to access WebClient for $publicWebBaseUrl on your behalf."
        "IsEnabled" = $true
    }
    Update-MgApplication -ApplicationId $ssoAdApp.Id -Api @{Oauth2PermissionScopes = $oauth2PermissionScopes}

    if ($autoConsent.IsPresent) {
        try {
            $SsoAdAppId = $AdProperties["SsoAdAppId"]
            $sp = @( $null, $null )
            $idx = 0
            $ssoAdAppId | ForEach-Object {
                $appId = $_
                $app = Get-MgApplication -All | Where-Object { $_.AppId -eq $appId }
                if (!$app) {
                    Write-Host -NoNewline "Waiting for AD App synchronization."
                    do {
                        Start-Sleep -Seconds 2
                        $app = Get-MgApplication -All | Where-Object { $_.AppId -eq $appId }
                    } while (!$app)
                }
                $sp[$idx] = Get-MgServicePrincipal -All | Where-Object { $_.AppId -eq $appId }
                if (!$sp[$idx]) {
                    $sp[$idx] = New-MgServicePrincipal -AppId $appId -Tags @("WindowsAzureActiveDirectoryIntegratedApp")
                }
                $idx++
            }
            $client = Get-MgServicePrincipal -Filter "appId eq '$appId'"
            $resource = Get-MgServicePrincipal -Filter "servicePrincipalNames / any(n: n eq 'https://graph.microsoft.com/')"
            New-MgOAuth2PermissionGrant -ClientId $client.Id -ConsentType "AllPrincipals" -ResourceId $resource.Id
            Write-Host "Installing Microsoft.Graph PowerShell package"
        }
        catch {
            Write-Error "An error occurred while attempting to automatically consent to the created application: $_"
            Write-Warning "Note: Cloud Application Administrator role required."
        }
    }

    if ($IncludeApiAccess) {
        $appRoleId = [Guid]::NewGuid().ToString()
        Update-MgApplication `
            -ApplicationId $ssoAdApp.Id `
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
        $PreAuthorizedApplications = $ssoAdApp.Api.PreAuthorizedApplications
        $PreAuthorizedApplications += @{ "AppId" = "1950a258-227b-4e31-a9cf-717495945fc2"; "DelegatedPermissionIds" = @($oauth2permissionid) }
        Update-MgApplication -ApplicationId $ssoAdApp.Id -Api @{PreAuthorizedApplications = $PreAuthorizedApplications}
    }

    # API Access Aad App
    if ($IncludeApiAccess) {
        # Remove "old" Api AAD Application
        $ApiIdentifierUri = $appIdUri.Replace('://','://api.')
        Get-MgApplication -All | Where-Object { $_.IdentifierUris -contains $ApiIdentifierUri } | ForEach-Object { Remove-MgApplication -ApplicationId $_.Id }
    
        # Create AD Application
        Write-Host "Creating AAD App for API Access"
        $bcSSOAppRRA = New-Object -TypeName Microsoft.Graph.PowerShell.Models.MicrosoftGraphRequiredResourceAccess
        $bcSSOAppRRA.ResourceAppId = "$ssoAdAppId"                                 # BC SSO App
        $bcSSOAppRRA.ResourceAccess = @(
            @{ "Id" = "$oauth2permissionid";                  "Type" = "Scope" }   # OAuth2
            @{ "Id" = "$appRoleId";                           "Type" = "Role" }    # API.ReadWrite.All
        )
        $graphRRA = New-Object -TypeName Microsoft.Graph.PowerShell.Models.MicrosoftGraphRequiredResourceAccess
        $graphRRA.ResourceAppId = "00000003-0000-0000-c000-000000000000"           # Microsoft Graph
        $graphRRA.ResourceAccess = @(
            @{ "Id" = "e1fe6dd8-ba31-4d61-89e7-88639da4683d"; "Type" = "Scope" }   # User.Read
        )
        $apiAppResourceAccessList = @($graphRRA, $bcSSOAppRRA)
        $apiAdApp = New-MgApplication `
            -DisplayName "API Access for $publicWebBaseUrl" `
            -IdentifierUris $ApiIdentifierUri `
            -Web @{ "RedirectUris" = $oAuthReplyUrls } `
            -SignInAudience $signInAudience `
            -RequiredResourceAccess $apiAppResourceAccessList
        
        $apiAdAppId = $apiAdApp.AppId.ToString()
        $AdProperties["ApiAdAppId"] = $apiAdAppId 
    
        $admspwd = Add-MgApplicationPassword -ApplicationId $apiAdApp.Id -PasswordCredential @{ "DisplayName" = "Password" }
        $AdProperties["ApiAdAppKeyValue"] = $admspwd.SecretText

        $sp = @( $null, $null )
        $idx = 0
        $ssoAdAppId,$apiAdAppId | ForEach-Object {
            $appId = $_
            $app = Get-MgApplication -All | Where-Object { $_.AppId -eq $appId }
            if (!$app) {
                Write-Host -NoNewline "Waiting for AD App synchronization."
                do {
                    Start-Sleep -Seconds 2
                    $app = Get-MgApplication -All | Where-Object { $_.AppId -eq $appId }
                } while (!$app)
            }
            $sp[$idx] = Get-MgServicePrincipal -All | Where-Object { $_.AppId -eq $appId }
            if (!$sp[$idx]) {
                $sp[$idx] = New-MgServicePrincipal -AppId $appId -Tags @("WindowsAzureActiveDirectoryIntegratedApp")
            }
            $idx++
        }
        New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp[1].Id -PrincipalId $sp[1].Id -ResourceId $sp[0].Id -AppRoleId $appRoleId | Out-Null
    }

    # Excel Ad App
    if ($IncludeExcelAadApp) {
        # Remove "old" Excel AD Application
        $ExcelIdentifierUri = $appIdUri.Replace('://','://xls.')
        Get-MgApplication -All | Where-Object { $_.IdentifierUris -contains $ExcelIdentifierUri } | ForEach-Object { Remove-MgApplication -ApplicationId $_.Id }

        # Create AD Application
        Write-Host "Creating AAD App for Excel Add-in"
        $bcSSOAppRRA = New-Object -TypeName Microsoft.Graph.PowerShell.Models.MicrosoftGraphRequiredResourceAccess
        $bcSSOAppRRA.ResourceAppId = "$ssoAdAppId"                            # BC SSO App
        $bcSSOAppRRA.ResourceAccess = @(
            @{ "Id" = "$oauth2permissionid";                  "Type" = "Scope" }   # OAuth2
        )
        $graphRRA = New-Object -TypeName Microsoft.Graph.PowerShell.Models.MicrosoftGraphRequiredResourceAccess
        $graphRRA.ResourceAppId = "00000003-0000-0000-c000-000000000000"           # Microsoft Graph
        $graphRRA.ResourceAccess = @(
            @{ "Id" = "e1fe6dd8-ba31-4d61-89e7-88639da4683d"; "Type" = "Scope" }   # User.Read
        )
        $excelAppResourceAccessList = @($graphRRA, $bcSSOAppRRA)
        $excelAdApp = New-MgApplication `
            -DisplayName "Excel AddIn for $publicWebBaseUrl" `
            -IdentifierUris $ExcelIdentifierUri `
            -Spa @{ "RedirectUris" = ($oAuthReplyUrls+@("https://az689774.vo.msecnd.net/dynamicsofficeapp/v1.3.0.0/*")) } `
            -Web @{ "ImplicitGrantSettings" = @{ "EnableIdTokenIssuance" = $true; "EnableAccessTokenIssuance" = $true } } `
            -SignInAudience $signInAudience `
            -RequiredResourceAccess $excelAppResourceAccessList

        $ExcelAdAppId = $excelAdApp.AppId.ToString()
        $AdProperties["ExcelAdAppId"] = $ExcelAdAppId

        $admspwd = Add-MgApplicationPassword -ApplicationId $excelAdApp.Id -PasswordCredential @{ "DisplayName" = "Password" }
        $AdProperties["ExcelAdAppKeyValue"] = $admspwd.SecretText
    }

    # Other Services Ad App
    if ($IncludeOtherServicesAadApp) {
        # Remove "old" Other Services AD Application
        $OtherServicesIdentifierUri = $appIdUri.Replace('://','://other.')
        Get-MgApplication -All | Where-Object { $_.IdentifierUris -contains $OtherServicesIdentifierUri } | ForEach-Object { Remove-MgApplication -ApplicationId $_.Id }

        # Create AD Application
        Write-Host "Creating AAD App for Other Services"

        # Microsoft Graph
        $graphRRA = New-Object -TypeName Microsoft.Graph.PowerShell.Models.MicrosoftGraphRequiredResourceAccess
        $graphRRA.ResourceAppId = "00000003-0000-0000-c000-000000000000"           # Microsoft Graph
        $graphRRA.ResourceAccess = @(
            @{ "Id" = "e1fe6dd8-ba31-4d61-89e7-88639da4683d"; "Type" = "Scope" }   # User.Read
            @{ "Id" = "5fa075e9-b951-4165-947b-c63396ff0a37"; "Type" = "Scope" }   # PrinterShare.ReadBasic.All
            @{ "Id" = "21f0d9c0-9f13-48b3-94e0-b6b231c7d320"; "Type" = "Scope" }   # PrintJob.Create
            @{ "Id" = "6a71a747-280f-4670-9ca0-a9cbf882b274"; "Type" = "Scope" }   # PrintJob.ReadBasic
            @{ "Id" = "9769c687-087d-48ac-9cb3-c37dde652038"; "Type" = "Scope" }   # EWS.AccessAsUser.All
            @{ "Id" = "d56682ec-c09e-4743-aaf4-1a3aac4caa21"; "Type" = "Scope" }   # Contacts.ReadWrite
        )

        $powerBIRRA = New-Object -TypeName Microsoft.Graph.PowerShell.Models.MicrosoftGraphRequiredResourceAccess
        $powerBIRRA.ResourceAppId = "00000009-0000-0000-c000-000000000000"         # Power BI Service
        $powerBIRRA.ResourceAccess = @(
            @{ "Id" = "4ae1bf56-f562-4747-b7bc-2fa0874ed46f"; "Type" = "Scope" }   # Report.Read.All
            @{ "Id" = "b2f1b2fa-f35c-407c-979c-a858a808ba85"; "Type" = "Scope" }   # Workspace.Read.All
        )

        $sharePointRRA = New-Object -TypeName Microsoft.Graph.PowerShell.Models.MicrosoftGraphRequiredResourceAccess
        $sharepointRRA.ResourceAppId = "00000003-0000-0ff1-ce00-000000000000"      # Sharepoint Service
        $sharepointRRA.ResourceAccess = @(
            @{ "Id" = "56680e0d-d2a3-4ae1-80d8-3c4f2100e3d0"; "Type" = "Scope" }   # AllSites.FullControl
            @{ "Id" = "82866913-39a9-4be7-8091-f4fa781088ae"; "Type" = "Scope" }   # User.ReadWrite.All
        )

        $otherServicesAppResourceAccessList = @($graphRRA, $powerBIRRA, $sharepointRRA)
        $otherServicesAdApp = New-MgApplication `
            -DisplayName "Other Services for $publicWebBaseUrl" `
            -IdentifierUris $OtherServicesIdentifierUri `
            -Web @{ "RedirectUris" = $oAuthReplyUrls } `
            -SignInAudience $signInAudience `
            -RequiredResourceAccess $otherServicesAppResourceAccessList
          
        $OtherServicesAdAppId = $otherServicesAdApp.AppId.ToString()
        $AdProperties["OtherServicesAdAppId"] = $OtherServicesAdAppId
    
        $admspwd = Add-MgApplicationPassword -ApplicationId $otherServicesAdApp.Id -PasswordCredential @{ "DisplayName" = "Password" }
        $AdProperties["OtherServicesAdAppKeyValue"] = $admspwd.SecretText
    }

    # PowerBI Ad App
    if ($IncludePowerBiAadApp) {
        Write-Host -ForegroundColor Yellow "-includePowerBiAadApp is deprecated. Use -includeOtherServicesAadApp instead."
        # Remove "old" PowerBI AD Application
        $PowerBiIdentifierUri = $appIdUri.Replace('://','://pbi.')
        Get-MgApplication -All | Where-Object { $_.IdentifierUris -contains $PowerBiIdentifierUri } | ForEach-Object { Remove-MgApplication -ApplicationId $_.Id }
    
        # Create AD Application
        Write-Host "Creating AAD App for PowerBI Service"
        $powerBIRRA = New-Object -TypeName Microsoft.Graph.PowerShell.Models.MicrosoftGraphRequiredResourceAccess
        $powerBIRRA.ResourceAppId = "00000009-0000-0000-c000-000000000000"         # Power BI Service
        $powerBIRRA.ResourceAccess = @(
            @{ "Id" = "4ae1bf56-f562-4747-b7bc-2fa0874ed46f"; "Type" = "Scope" }   # Report.Read.All
            @{ "Id" = "b2f1b2fa-f35c-407c-979c-a858a808ba85"; "Type" = "Scope" }   # Workspace.Read.All
        )
        $graphRRA = New-Object -TypeName Microsoft.Graph.PowerShell.Models.MicrosoftGraphRequiredResourceAccess
        $graphRRA.ResourceAppId = "00000003-0000-0000-c000-000000000000"           # Microsoft Graph
        $graphRRA.ResourceAccess = @(
            @{ "Id" = "e1fe6dd8-ba31-4d61-89e7-88639da4683d"; "Type" = "Scope" }   # User.Read
        )
        $powerBIAppResourceAccessList = @($powerBIRRA, $graphRRA)
        $powerBiAdApp = New-MgApplication `
            -DisplayName "PowerBI Service for $publicWebBaseUrl" `
            -IdentifierUris $PowerBiIdentifierUri `
            -Web @{ "RedirectUris" = $oAuthReplyUrls } `
            -SignInAudience $signInAudience `
            -RequiredResourceAccess $powerBIAppResourceAccessList
          
        $PowerBiAdAppId = $powerBiAdApp.AppId.ToString()
        $AdProperties["PowerBiAdAppId"] = $PowerBiAdAppId 
    
        $admspwd = Add-MgApplicationPassword -ApplicationId $PowerBiAdApp.Id -PasswordCredential @{ "DisplayName" = "Password" }
        $AdProperties["PowerBiAdAppKeyValue"] = $admspwd.SecretText
    }

    # EMail App
    if ($IncludeEmailAadApp) {
        # Remove "old" Email AD Application
        $EMailIdentifierUri = $appIdUri.Replace('://','://email.')
        Get-MgApplication -All | Where-Object { $_.IdentifierUris -contains $EMailIdentifierUri } | ForEach-Object { Remove-MgApplication -ApplicationId $_.Id }
    
        # Create AD Application
        Write-Host "Creating AAD App for EMail Service"
        $graphRRA = New-Object -TypeName Microsoft.Graph.PowerShell.Models.MicrosoftGraphRequiredResourceAccess
        $graphRRA.ResourceAppId = "00000003-0000-0000-c000-000000000000"           # Microsoft Graph
        $graphRRA.ResourceAccess = @(
            @{ "Id" = "e1fe6dd8-ba31-4d61-89e7-88639da4683d"; "Type" = "Scope" }   # User.Read
            @{ "Id" = "64a6cdd6-aab1-4aaf-94b8-3cc8405e90d0"; "Type" = "Scope" }   # Email
            @{ "Id" = "e383f46e-2787-4529-855e-0e479a3ffac0"; "Type" = "Scope" }   # Mail.ReadWrite
            @{ "Id" = "024d486e-b451-40bb-833d-3e66d98c5c73"; "Type" = "Scope" }   # Mail.Send
            @{ "Id" = "9769c687-087d-48ac-9cb3-c37dde652038"; "Type" = "Scope" }   # EWS.AccessAsUser.All
            @{ "Id" = "d56682ec-c09e-4743-aaf4-1a3aac4caa21"; "Type" = "Scope" }   # Contacts.ReadWrite
        )
        $eMailAppResourceAccessList = @($graphRRA)
        $EMailAdApp = New-MgApplication `
            -DisplayName "EMail Service for $publicWebBaseUrl" `
            -IdentifierUris $EMailIdentifierUri `
            -Web @{ "ImplicitGrantSettings" = @{ "EnableIdTokenIssuance" = $true; "EnableAccessTokenIssuance" = $true }; "RedirectUris" = $oAuthReplyUrls } `
            -SignInAudience $signInAudience `
            -RequiredResourceAccess $eMailAppResourceAccessList
        
        $EMailAdAppId = $EMailAdApp.AppId.ToString()
        $AdProperties["EMailAdAppId"] = $EMailAdAppId 
    
        $admspwd = Add-MgApplicationPassword -ApplicationId $EmailAdApp.Id -PasswordCredential @{ "DisplayName" = "Password" }
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
Export-ModuleMember -Function New-AadAppsForBc

# SIG # Begin signature block
# MIIncQYJKoZIhvcNAQcCoIInYjCCJ14CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBRB5e0gbypllZN
# jMiCYqw9S9EqOWy78OK/9q8yr9miuqCCDMkwggYEMIID7KADAgECAhMzAAACHPrN
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
# hvcNAQkEMSIEIMWGEdKibW/3l3TcNTMlgsXXnkPzbyP4Vbd7YR2GRC6VMEIGCisG
# AQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEAPLswxIlgxlLMo5DND2rq
# pkzcyw83qOWy7ynb+MeJN0jFefiQ6bEQ+fi833/6KvfyH0jp6ZhacbtDjwaPChAH
# stuH5P6feojtUc5V/inZB4peOIWRQrW9eC3djFEiyz/lOUWrdZsyu85erD05YPYn
# Gql86x3VsAnWheVCL0h671FipZrfykG42atEk84Nk2SpEu5CH1Nl/fHXy5Wdz62N
# i10iow5eenPx4BRaFZRQqnigAdSQ+m39LwakuYTj4nGkOBAvtdwNBRQdaIbnfrsp
# W95XqCk466tx6m1NZl2Qp//9G9sMhvMzLtCX2qab9OmGVYK6vi8HlUK3i8OgF/TK
# waGCF7AwghesBgorBgEEAYI3AwMBMYIXnDCCF5gGCSqGSIb3DQEHAqCCF4kwgheF
# AgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFFMIIB
# QQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCA7z053Cvp+BbcT3VE5
# 51mKPNTxWlChSDN3CF1UpEPvhAIGaohqFTgCGBMyMDI2MDgyNzA2MjkzNi44MzFa
# MASAAgH0oIHZpIHWMIHTMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0
# ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjozMjFBLTA1RTAtRDk0NzElMCMG
# A1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaCCEf4wggcoMIIFEKAD
# AgECAhMzAAACGqmgHQagD0OqAAEAAAIaMA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29m
# dCBUaW1lLVN0YW1wIFBDQSAyMDEwMB4XDTI1MDgxNDE4NDgyOFoXDTI2MTExMzE4
# NDgyOFowgdMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTAr
# BgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUG
# A1UECxMeblNoaWVsZCBUU1MgRVNOOjMyMUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxN
# aWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOC
# Ag8AMIICCgKCAgEAmYEAwSTz79q2V3ZWzQ5Ev7RKgadQtMBy7+V3XQ8R0NL8R9mu
# pxcqJQ/KPeZGJTER+9Qq/t7HOQfBbDy6e0TepvBFV/RY3w+LOPMKn0Uoh2/8IvdS
# bJ8qAWRVoz2S9VrJzZpB8/f5rQcRETgX/t8N66D2JlEXv4fZQB7XzcJMXr1puhuX
# bOt9RYEyN1Q3Z7YjRkhfBsRc+SD/C9F4iwZqfQgo82GG4wguIhjJU7+XMfrv4vxA
# FNVg3mn1PoMWGZWio+e14+PGYPVLKlad+0IhdHK5AgPyXKkqAhEZpYhYYVEItHOO
# vqrwukxVAJXMvWA3GatWkRZn33WDJVtghCW6XPLi1cDKiGE5UcXZSV4OjQIUB8vp
# 2LUMRXud5I49FIBcE9nT00z8A+EekrPM+OAk07aDfwZbdmZ56j7ub5fNDLf8yIb8
# QxZ8Mr4RwWy/czBuV5rkWQQ+msjJ5AKtYZxJdnaZehUgUNArU/u36SH1eXKMQGRX
# r/xeKFGI8vvv5Jl1knZ8UqEQr9PxDbis7OXp2WSMK5lLGdYVH8VownYF3sbOiRkx
# 5Q5GaEyTehOQp2SfdbsJZlg0SXmHphGnoW1/gQ/5P6BgSq4PAWIZaDJj6AvLLCdb
# URgR5apNQQed2zYUgUbjACA/TomA8Ll7Arrv2oZGiUO5Vdi4xxtA3BRTQTUCAwEA
# AaOCAUkwggFFMB0GA1UdDgQWBBTwqyIJ3QMoPasDcGdGovbaY8IlNjAfBgNVHSME
# GDAWgBSfpxVdAF5iXYP05dJlpxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1l
# LVN0YW1wJTIwUENBJTIwMjAxMCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsG
# AQUFBzAChlBodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01p
# Y3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMB
# Af8EAjAAMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDAN
# BgkqhkiG9w0BAQsFAAOCAgEA1a72WFq7B6bJT3VOJ21nnToPJ9O/q51bw1bhPfQy
# 67uy+f8x8akipzNL2k5b6mtxuPbZGpBqpBKguDwQmxVpX8cGmafeo3wGr4a8Yk6S
# y09tEh/Nwwlsyq7BRrJNn6bGOB8iG4OTy+pmMUh7FejNPRgvgeo/OPytm4NNrMMg
# 98UVlrZxGNOYsifpRJFg5jE/Yu6lqFa1lTm9cHuPYxWa2oEwC0sEAsTFb69iKpN0
# sO19xBZCr0h5ClU9Pgo6ekiJb7QJoDzrDoPQHwbNA87Cto7TLuphj0m9l/I70gLj
# Eq53SHjuURzwpmNxdm18Qg+rlkaMC6Y2KukOfJ7oCSu9vcNGQM+inl9gsNgirZ6y
# Jk9VsXEsoTtoR7fMNU6Py6ufJQGMTmq6ZCq2eIGOXWMBb79ZF6tiKTa4qami3US0
# mTY41J129XmAglVy+ujSZkHu2lHJDRHs7FjnIXZVUE5pl6yUIl23jG50fRTLQcSt
# dwY/LvJUgEHCIzjvlLTqLt6JVR5bcs5aN4Dh0YPG95B9iDMZrq4rli5SnGNWev5L
# LsDY1fbrK6uVpD+psvSLsNpht27QcHRsYdAMALXM+HNsz2LZ8xiOfwt6rOsVWXoi
# HV86/TeMy5TZFUl7qB59INoMSJgDRladVXeT9fwOuirFIoqgjKGk3vO2bELrYMN0
# QVwwggdxMIIFWaADAgECAhMzAAAAFcXna54Cm0mZAAAAAAAVMA0GCSqGSIb3DQEB
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
# ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjozMjFBLTA1RTAtRDk0NzElMCMG
# A1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIa
# AxUA8YrutmKpSrubCaAYsU4pt1Ft8DaggYMwgYCkfjB8MQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1T
# dGFtcCBQQ0EgMjAxMDANBgkqhkiG9w0BAQsFAAIFAO46KEMwIhgPMjAyNjA4Mjcw
# MzA2NDNaGA8yMDI2MDgyODAzMDY0M1owdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA
# 7jooQwIBADAKAgEAAgIK0gIB/zAHAgEAAgISdzAKAgUA7jt5wwIBADA2BgorBgEE
# AYRZCgQCMSgwJjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYag
# MA0GCSqGSIb3DQEBCwUAA4IBAQCYeZUjoB06Gwk5tRRPeIB7nJhW7cAmPddyL9Oa
# lnjkzzpMg515wIOAhFEpo3UJH/4mvcN2FpJ6uEgL0FqsTgnpW8orGSWF1UPql+BN
# 1hERheAi7MVZgJ95zkhe6Q3sSS4kl8k2AOerbm9dlTtBiP37zVHxzIl//0e9Y/ms
# 0Xe+aLWVdSQ0f6pEOUyMl96tQ2hR0EIuCM0opcVC9Uw8tGPYKVVg7cpM+no7T8vu
# 7XJo8MSnxjyj3FxUCjy5FL0tPTtbUTYgVGttng60GGSqQFYFeGwex9jJG17MaYMd
# SKlRrO9ddQk4VdAAOUohSqoE/DC+5yilJNrSg2QomWhCK+M+MYIEDTCCBAkCAQEw
# gZMwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcT
# B1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UE
# AxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAIaqaAdBqAPQ6oA
# AQAAAhowDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0B
# CRABBDAvBgkqhkiG9w0BCQQxIgQg46TR6aC74WWjqasq/ftBsULyS0ekB1cYEWA/
# IalpoXMwgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCCdeiHHrbtpKcwB20do
# VU89WHIOH8S7w37uaHcDmemK+zCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1w
# IFBDQSAyMDEwAhMzAAACGqmgHQagD0OqAAEAAAIaMCIEIJvNkMndWUHCC6HXn8+a
# lwCRDhrVLdHuYEv9sLfePL+cMA0GCSqGSIb3DQEBCwUABIICAF18uJvUaT+C0gjF
# ERuSLPlKMEkv9pTZmySJFGQu1GsIIBykPAYBj6lwEsfcGYEtqWx6r+KiADJu3l4/
# BwxFnBvgBlc7q1plD4BpL2lYkYYQW9ZgumAJu7aoGkqCjeAg7gl5sH7lFaZmONei
# 2ESv5MQPmna0StHrQjC7psjPF31YeOHgu1YR0//Fc5XeLWrK7UNIwaQUnS87x/sL
# BrSzyo+Z7IGBurE66FeKPnqOMDs/q3coNYG1jwfmoM4Ie0DPfu+l4tm1woqzBIEV
# t9y9zQ6itBGmaYvObMh0lhZXejqrr15XV4reBggalOnVMg+AJUQYM5uh4KPEwcbG
# /+7bdqY+7+Z16+Uub9PyQmRjklAi8LBdAq3XwlvzeKTMZflqyaRHrXAd87JRvw5j
# OXYAvphThnCXWV25L4NQ4xYdXqW/nJKhaY92X2QWJxmaCWu/pTBJ19eZI4TnQnod
# LCdgwdkHz70l2MuaDnMIN0YkfwJJwHQGKkODxY6ZSHsLwbD43ln67EJqli+zFA+Q
# 73QOEdeQeJi2js7PKS/aJsPBHuPqVcA7bfrYrcmEJDF5HV+XQefC9Ui9I9XboQCO
# 1udAtvZ8TCummlMGcMa71D7f+aAGiu0g33oiKsx8B/lpip2lJ6TRjdNiuIoflU+b
# c8hQ1DTrmZSpzTeQju1xXQpjjx+N
# SIG # End signature block
