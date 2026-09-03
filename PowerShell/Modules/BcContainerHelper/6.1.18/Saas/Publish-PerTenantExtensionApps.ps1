<# 
 .Synopsis
  Function for publishing PTE apps to an online tenant
 .Description
  Function for publishing PTE apps to an online tenant
  Please consult the CI/CD Workshop document at http://aka.ms/cicdhol to learn more about this function
 .Parameter clientId
  ClientID of Azure AD App for authenticating to Business Central (SecureString or String)
 .Parameter clientSecret
  ClientSecret of Azure AD App for authenticating to Business Central (SecureString or String)
 .Parameter tenantId
  TenantId of tenant in which you want to publish the Per Tenant Extension Apps
 .Parameter environment
  Name of the environment inside the tenant in which you want to publish the Per Tenant Extension Apps
 .Parameter companyName
  Company Name in which the Azure AD App is registered
 .Parameter appFiles
  Array or comma separated string of apps or .zip files containing apps, which needs to be published
  The apps will be sorted by dependencies and published+installed
 .Parameter useNewLine
  Add this switch to add a newline to progress indicating periods during wait.
  Azure DevOps doesn't update logs until a newline is added.
 .Parameter hideInstalledExtensionsOutput
  Add this parameter to hide the output that lists installed extensions on the specified environment before and after installation of new and updated PTE extensions.
 .Parameter unpublishPreviousVersions
  Add this switch to unpublish previous versions of apps after upgrading to a new version.
#>
function Publish-PerTenantExtensionApps {
    [CmdletBinding(DefaultParameterSetName="AC")]
    Param(
        [Parameter(Mandatory=$true, ParameterSetName="CC")]
        $clientId,
        [Parameter(Mandatory=$true, ParameterSetName="CC")]
        $clientSecret,
        [Parameter(Mandatory=$true, ParameterSetName="CC")]
        [string] $tenantId,
        [Parameter(Mandatory=$true, ParameterSetName="AC")]
        [Hashtable] $bcAuthContext,
        [Parameter(Mandatory=$true)]
        [string] $environment,
        [Parameter(Mandatory=$false)]
        [string] $companyName,
        [Parameter(Mandatory=$true)]
        $appFiles,
        [ValidateSet('Add','Force')]
        [string] $schemaSyncMode = 'Add',
        [ValidateSet('','Current version','Next minor version','Next major version')]
        [string] $schedule = '',
        [switch] $useNewLine,
        [switch] $hideInstalledExtensionsOutput,
        [switch] $unpublishPreviousVersions
    )

$telemetryScope = InitTelemetryScope -name $MyInvocation.InvocationName -parameterValues $PSBoundParameters -includeParameters @()
try {
	
    function GetAuthHeaders {
        $script:authContext = Renew-BcAuthContext -bcAuthContext $script:authContext
        return @{ "Authorization" = "Bearer $($script:authContext.AccessToken)" }
    }

    $newLine = @{}
    if (!$useNewLine) {
        $newLine = @{ "NoNewLine" = $true }
    }

    if ($PsCmdlet.ParameterSetName -eq "CC") {
        if ($clientId -is [SecureString]) { $clientID = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($clientID)) }
        if ($clientId -isnot [String]) { throw "ClientID needs to be a SecureString or a String" }
        if ($clientSecret -is [String]) { $clientSecret = ConvertTo-SecureString -String $clientSecret -AsPlainText -Force }
        if ($clientSecret -isnot [SecureString]) { throw "ClientSecret needs to be a SecureString or a String" }

        $script:authContext = New-BcAuthContext `
            -clientID $clientID `
            -clientSecret $clientSecret `
            -tenantID $tenantId `
            -scopes "https://api.businesscentral.dynamics.com/.default"

        if (-not ($script:AuthContext)) {
            throw "Authentication failed"
        }
    }
    else {
        $script:authContext = Renew-BcAuthContext -bcAuthContext $bcAuthContext
    }

    $appFolder = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
    try {
        $appFiles = CopyAppFilesToFolder -appFiles $appFiles -folder $appFolder
        $automationApiUrl = "$($bcContainerHelperConfig.apiBaseUrl.TrimEnd('/'))/v2.0/$environment/api/microsoft/automation/v2.0"
        
        Write-Host "$automationApiUrl/companies"
        $companies = Invoke-RestMethod -Headers (GetAuthHeaders) -Method Get -Uri "$automationApiUrl/companies" -UseBasicParsing
        $company = $companies.value | Where-Object { ($companyName -eq "") -or ($_.name -eq $companyName) } | Select-Object -First 1
        if (!($company)) {
            throw "No company $companyName"
        }
        $companyId = $company.id
        if ($companyName -eq "") {
            $companyName = $company.name
        }
        Write-Host "Company '$companyName' has id $companyId"
        
        Write-Host "$automationApiUrl/companies($companyId)/extensions"
        $getExtensions = Invoke-WebRequest -Headers (GetAuthHeaders) -Method Get -Uri "$automationApiUrl/companies($companyId)/extensions" -UseBasicParsing
        $extensions = (ConvertFrom-Json $getExtensions.Content).value | Sort-Object -Property DisplayName
        
        if(!$hideInstalledExtensionsOutput) {
            Write-Host "Extensions before:"
            $extensions | ForEach-Object { Write-Host " - $($_.DisplayName), Version $($_.versionMajor).$($_.versionMinor).$($_.versionBuild).$($_.versionRevision), Installed=$($_.isInstalled)" }
            Write-Host
        }

        $body = @{"schedule" = "Current Version"}
        $appDep = $extensions | Where-Object { $_.DisplayName -eq 'Application' }
        $appDepVer = [System.Version]"$($appDep.versionMajor).$($appDep.versionMinor).$($appDep.versionBuild).$($appDep.versionRevision)"
        if ($appDepVer -ge [System.Version]"21.2.0.0") {
            if ($schemaSyncMode -eq 'Force') {
                $body."SchemaSyncMode" = "Force Sync"
            }
            else {
                $body."SchemaSyncMode" = "Add"
            }
        }
        else {
            if ($schemaSyncMode -eq 'Force') {
                throw 'SchemaSyncMode Force is not supported before version 21.2'
            }
        }

        if($schedule) {
            $body."schedule" = $schedule
        }

        $ifMatchHeader = @{ "If-Match" = '*'}
        $jsonHeader = @{ "Content-Type" = 'application/json'}
        $streamHeader = @{ "Content-Type" = 'application/octet-stream'}
        try {
            Sort-AppFilesByDependencies -appFiles $appFiles -excludeRuntimePackages | ForEach-Object {
                $appFile = $_
                Write-Host @newline "$([System.IO.Path]::GetFileName($appFile)) - "
                $appJson = Get-AppJsonFromAppFile -appFile $appFile
                $previousApp = $null
                $existingApp = $extensions | Where-Object { $_.id -eq $appJson.id -and $_.isInstalled }
                if ($existingApp) {
                    if ($existingApp.isInstalled) {
                        $existingVersion = [System.Version]"$($existingApp.versionMajor).$($existingApp.versionMinor).$($existingApp.versionBuild).$($existingApp.versionRevision)"
                        if ($existingVersion -ge $appJson.version) {
                            Write-Host "already installed"
                        }
                        else {
                            Write-Host @newLine "upgrading"
                            $previousApp = $existingApp
                            $existingApp = $null
                        }
                    }
                    else {
                        Write-Host @newLine "installing"
                        $existingApp = $null
                    }
                }
                else {
                    Write-Host @newLine "publishing and installing"
                }
                if (!$existingApp) {
                    $extensionUpload = (Invoke-RestMethod -Method Get -Uri "$automationApiUrl/companies($companyId)/extensionUpload" -Headers (GetAuthHeaders)).value
                    Write-Host @newLine "."
                    if ($extensionUpload -and $extensionUpload.systemId) {
                        $extensionUpload = Invoke-RestMethod `
                            -Method Patch `
                            -Uri "$automationApiUrl/companies($companyId)/extensionUpload($($extensionUpload.systemId))" `
                            -Headers ((GetAuthHeaders) + $ifMatchHeader + $jsonHeader) `
                            -Body ($body | ConvertTo-Json -Compress)
                    }
                    else {
                        $ExtensionUpload = Invoke-RestMethod `
                            -Method Post `
                            -Uri "$automationApiUrl/companies($companyId)/extensionUpload" `
                            -Headers ((GetAuthHeaders) + $jsonHeader) `
                            -Body ($body | ConvertTo-Json -Compress)
                    }
                    Write-Host @newLine "."
                    if ($null -eq $extensionUpload.systemId) {
                        throw "Unable to upload extension"
                    }
                    # Use stream instead of reading the entire file into memory
                    $fileStream = [System.IO.File]::OpenRead($appFile)
                    Invoke-RestMethod `
                        -Method Patch `
                        -Uri $extensionUpload.'extensionContent@odata.mediaEditLink' `
                        -Headers ((GetAuthHeaders) + $ifMatchHeader + $streamHeader) `
                        -Body $fileStream | Out-Null
                    $fileStream.Close()
                    Write-Host @newLine "."
                    Invoke-RestMethod `
                        -Method Post `
                        -Uri "$automationApiUrl/companies($companyId)/extensionUpload($($extensionUpload.systemId))/Microsoft.NAV.upload" `
                        -Headers ((GetAuthHeaders) + $ifMatchHeader) `
                        -ErrorAction SilentlyContinue | Out-Null
                    Write-Host @newLine "."    
                    $completed = $false
                    $errCount = 0
                    $sleepSeconds = 30
                    $lastStatus = ''
                    while (!$completed)
                    {
                        Start-Sleep -Seconds $sleepSeconds
                        try {
                            $extensionDeploymentStatusResponse = Invoke-WebRequest -Headers (GetAuthHeaders) -Method Get -Uri "$automationApiUrl/companies($companyId)/extensionDeploymentStatus" -UseBasicParsing
                            $extensionDeploymentStatuses = (ConvertFrom-Json $extensionDeploymentStatusResponse.Content).value

                            $thisExtension = $extensionDeploymentStatuses | Where-Object { $_.publisher -eq $appJson.publisher -and $_.name -eq $appJson.name -and $_.appVersion -eq $appJson.version }
                            if ($null -eq $thisExtension) {
                                throw "Unable to find extension deployment status"
                            } 
                            $thisExtension | ForEach-Object {
                                if ($_.status -ne $lastStatus) {
                                    if (!$useNewLine) { Write-Host }
                                    Write-Host @newLine $_.status
                                    $lastStatus = $_.status
                                }
                                if ($_.status -eq "InProgress") {
                                    $errCount = 0
                                    $sleepSeconds = 5
                                    Write-Host @newLine "."
                                }
                                elseif ($_.Status -eq "Unknown") {
                                    throw "Unknown Error"
                                }
                                elseif ($_.Status -eq "Completed") {
                                    if (!$useNewLine) { Write-Host }
                                    $completed = $true
                                }
                                else {
                                    $errCount = 5
                                    throw $_.status
                                }
                            }
                        }
                        catch {
                            if (!$useNewLine) { Write-Host }
                            if ($errCount++ -gt 4) {
                                Write-Host $_.Exception.Message
                                throw "Unable to publish app. Please open the Extension Deployment Status Details page in Business Central to see the detailed error message."
                            }
                            $sleepSeconds += $sleepSeconds
                            Write-Host "Error: $($_.Exception.Message). Retrying in $sleepSeconds seconds"
                        }
                    }
                    if ($unpublishPreviousVersions -and $previousApp -and ($appDepVer -ge [System.Version]"25.4.0.0")) { # New unpublish API available from 25.4
                        Write-Host @newLine "Unpublishing previous version"
                        Invoke-RestMethod `
                            -Method Post `
                            -Uri "$automationApiUrl/companies($companyId)/extensions($($previousApp.packageId))/Microsoft.NAV.unpublish" `
                            -Headers (GetAuthHeaders) | Out-Null
                    }
                }
            }
        }
        catch [System.Net.WebException],[System.Net.Http.HttpRequestException] {
            if (!$useNewLine) { Write-Host }
            Write-Host "ERROR $($_.Exception.Message)"
            Write-Host $_.ScriptStackTrace
            throw (GetExtendedErrorMessage $_)
        }
        catch {
            if (!$useNewLine) { Write-Host }
            Write-Host "ERROR: $($_.Exception.Message) [$($_.Exception.GetType().FullName)]"
            throw
        }
        finally {
            $getExtensions = Invoke-WebRequest -Headers (GetAuthHeaders) -Method Get -Uri "$automationApiUrl/companies($companyId)/extensions" -UseBasicParsing
            $extensions = (ConvertFrom-Json $getExtensions.Content).value | Sort-Object -Property DisplayName
            
            if (!$hideInstalledExtensionsOutput) {
                Write-Host
                Write-Host "Extensions after:"
                $extensions | ForEach-Object { Write-Host " - $($_.DisplayName), Version $($_.versionMajor).$($_.versionMinor).$($_.versionBuild).$($_.versionRevision), Installed=$($_.isInstalled)" }
            }
        }
    }
    catch [System.Net.WebException],[System.Net.Http.HttpRequestException] {
        Write-Host "ERROR $($_.Exception.Message)"
        throw (GetExtendedErrorMessage $_)
    }
    finally {
        if (Test-Path $appFolder) {
            Remove-Item $appFolder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
catch {
    TrackException -telemetryScope $telemetryScope -errorRecord $_
    throw
}
finally {
    $script:authContext = $null
    TrackTrace -telemetryScope $telemetryScope
}
}
Export-ModuleMember -Function Publish-PerTenantExtensionApps

# SIG # Begin signature block
# MIInbgYJKoZIhvcNAQcCoIInXzCCJ1sCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBWCWINe1jT9ccY
# kzwzQ4QQ9o29ZgLDb1zQSw9D7Xym/KCCDMkwggYEMIID7KADAgECAhMzAAACHPrN
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
# hvcNAQkEMSIEIKGLS97DxXlqnllIizEG8KwVVjw22qCB947a33fWbGngMEIGCisG
# AQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEAP2xJfQ/JklcSJjhCz7aV
# CDJ89qehk+ICRMxW7ZKWZa6FyWQb+A9mEjyHek3uUOKG8+C9/jgzW6oH8ooeL0ZX
# 7tvdbZr/uVcE9bWh8DOTfkFzXSTTIfBh7dISOB/iMuBXHOa35ZTgwudTfLJuTPoE
# xYBoGG+3nEhig76mfxOZQ0JX0jUCDva7h1umQYPgF2YPh4LPx02ehfvGTyXpsU9U
# iHMWmQs/1h5qsBiQ87DQdmBL2iqa23SgQJgwHVilaAxOGEdvZ/HGRvl6z9gnJsVj
# V3Ko6mggkihq20fkq3xlEhhZ5jzJew9M8IBreiG9/fAVSIiY1ZD0mfS1m8IJ4NXs
# aKGCF60wghepBgorBgEEAYI3AwMBMYIXmTCCF5UGCSqGSIb3DQEHAqCCF4YwgheC
# AgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFFMIIB
# QQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCC2qRzMABFsWVa7A8G5
# cWewUOxBlcAKBeeZmvezc4LfkgIGaomzDM5FGBMyMDI2MDgyNzA2MjkzNy42MzRa
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
# BDAvBgkqhkiG9w0BCQQxIgQgpWQhvmktcfGtq5MmG55KzpUQYEv6ZoCdHy0J4oLO
# MwwwgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCAwJRSVuD2jmMcQCFXdLuJA
# wDpUVNZ6bc6dfJU83Q2LgDCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBD
# QSAyMDEwAhMzAAACG9CyuAJn93LPAAEAAAIbMCIEILpX2zOE3yRmSrEbYyB6Qah4
# staWGvdg0j8vh4PpXwO4MA0GCSqGSIb3DQEBCwUABIICABbu80+jVKLJp91x4ru/
# eizSqoTFuu4ivNAtvMG7GUMGX95lmskWMHF/zEedA0lO8NBvqZgUHYKJD7ie1Oed
# 24eAC9v77/AuKD4mDzP+b5GMbUkmHwUxgVetiUJRt6zBm/ndjs1TgjjfYdAnXxKi
# 3Em4a6XJtgeLSlcZCSy/JBUluwrXtdhWODCiDC8Dj9RCDKq4Z0uVflWvOMe4b+zU
# KbYTkE7Oq+zd0mlmQamgY25h4fVO6I9I4Sg29kuRUBLEbnciL2kCTU4LWW8oT2Zf
# RZYG816rAhjDHhxQmGR6uziJCGEVHdkLCIiN6LWBFgc9hJSDljhyI1jPBr+VSqmp
# FLMxtP/KgToGocbWu6k+qRGFt6dH1kBXq82UFzHEVdevsAxA3WVYloHUIJQ9BFJC
# wT/L8dzAsxQ5LVRsDdJ+K3EZMLAtye9BaN2wDbeLSOO40LKnNE6YS+lbtYp5EOwn
# K/gnCC/ZazNRb/6oebrCJq5R0E2CyM9T5+mj8Qv8crNlXMFQD5ESbZOz0NFphs+O
# PBP1pD1jW7fmW2s0kNzMecLqFHMr4wl1RYlh9Bk8DpZW/oLjZuziPc/szqSXpu4G
# 1tDl2ocbUCfomuIkvBS+PsJdfihuifmLjLo/VUTht0MP70bRiXtmZw9B1e0+X/uA
# 1vkBSZ3BlQh2QdWTWla7TXbd
# SIG # End signature block
