<# 
 .Synopsis
  Print out the ContainerHelper WelCome text
#>
function Write-BcContainerHelperWelcomeText {
    Clear-Host
    Write-Host -ForegroundColor Yellow "Welcome to the Business Central container Helper PowerShell Prompt"
    Write-Host
    Write-Host -ForegroundColor Yellow "Container info functions"
    Write-Host "Get-BcContainerNavVersion       Get Nav version from Business Central container or image"
    Write-Host "Get-BcContainerImageName        Get ImageName from Business Central container"
    Write-Host "Get-BcContainerGenericTag       Get Nav generic image tag from Business Central container or image"
    Write-Host "Get-BcContainerOsVersion        Get OS version from Business Central container or image"
    Write-Host "Get-BcContainerEula             Get Eula link from Business Central container or image"
    Write-Host "Get-BcContainerLegal            Get Legal link from Business Central container or image"
    Write-Host "Get-BcContainerCountry          Get country version from Business Central container or image"
    Write-Host "Get-BcContainerIpAddress        Get IP Address to a Business Central container"
    Write-Host "Get-BcContainerSharedFolders    Get Shared Folders from a Business Central container"
    Write-Host "Get-BcContainerPath             Get the path inside a Business Central container to a shared file"
    Write-Host "Get-BcContainerName             Get the name of a Business Central container"
    Write-Host "Get-BcContainerId               Get the Id of a Business Central container"
    Write-Host "Test-BcContainer                Test whether a Business Central container exists"
    Write-Host "Get-BcContainerDebugInfo        Get Troubleshooting info for Business Central container if you need help with an issue"
    Write-Host "Get-BcContainers                Get All Business Central containers"
    Write-Host "Get-BcContainerEventLog         Get EventLog from Business Central container"
    Write-Host "Get-BcContainerServerConfiguration Get Server Configuration from Business Central container"
    Write-Host
    Write-Host -ForegroundColor Yellow "Container handling functions"
    Write-Host "New-BcContainer                 Create new Business Central container"
    Write-Host "Remove-BcContainer              Remove Business Central container"
    Write-Host "Stop-BcContainer                Stop Business Central container"
    Write-Host "Start-BcContainer               Start Business Central container"
    Write-Host "Restart-BcContainer             Restart Business Central container"
    Write-Host "Restart-BcContainerServiceTier  Restarts a Business Central Server instance inside of an Business Central Container"
    Write-Host "Import-BcContainerLicense       Import License to a Business Central container"
    Write-Host "Get-BcContainerSession          Create new session to a Business Central container"
    Write-Host "Remove-BcContainerSession       Remove Business Central container session"
    Write-Host "Enter-BcContainer               Enter Business Central container session"
    Write-Host "Open-BcContainer                Open Business Central container in new window"
    Write-Host "Wait-BcContainerReady           Wait for Business Central container to become ready"
    Write-Host "Copy-FileFromBcContainer        Copy file from Business Central container"
    Write-Host "Copy-FileToBcContainer          Copy file to Business Central container"
    Write-Host "Export-BcContainerDatabasesAsBacpac Export database(s) in Business Central container as BacPac"
    Write-Host "Backup-BcContainerDatabases     Backup database(s) in Business Central container as bak"
    Write-Host "Extract-FilesFromBcContainerImage Extract files from Business Central container Image"
    Write-Host "Get-BestBcContainerImageName    Get best specific Business Central container Image for your host OS"
    Write-Host "Set-BcContainerServerConfiguration Configures settings for a Business Central Server instance"
    Write-Host
    Write-Host -ForegroundColor Yellow "Functions for running tests"
    Write-Host "Import-TestToolkitToBcContainer Import TestToolkit to Business Central container"
    Write-Host "Get-TestsFromBcContainer        Get a list of tests from a Business Central Container"
    Write-Host "Run-TestsInBcContainer          Run Tests inside a Business Central container"
    Write-Host
    Write-Host -ForegroundColor Yellow "Object handling functions (NAV)"
    Write-Host "Import-ObjectsToNavContainer    Import objects from .txt or .fob file to NAV container"
    Write-Host "Import-DeltasToNavContainer     Merge delta files and Import objects to NAV container"
    Write-Host "Compile-ObjectsInNavContainer   Compile objects"
    Write-Host "Export-NavContainerObjects      Export objects from NAV container"
    Write-Host "Create-MyOriginalFolder         Create folder with the original objects for modified objects"
    Write-Host "Create-MyDeltaFolder            Create folder with deltas for modified objects"
    Write-Host "Convert-Txt2Al                  Convert deltas folder to al folder"
    Write-Host "Export-ModifiedObjectsAsDeltas  Export objects, create baseline and create deltas"
    Write-Host "Convert-ModifiedObjectsToAl     Export objects, create baseline, create deltas and convert to .al files"
    Write-Host "Invoke-NavContainerCodeunit     Invoke Codeunit in NAV container"
    Write-Host
    Write-Host -ForegroundColor Yellow "App handling functions"
    Write-Host "Compile-AppInBcContainer        Use Container to compile App"
    Write-Host "Publish-BcContainerApp          Publish App to Business Central container"
    Write-Host "Sync-BcContainerApp             Sync App in Business Central container"
    Write-Host "Install-BcContainerApp          Install App in Business Central container"
    Write-Host "Uninstall-BcContainerApp        Uninstall App from Business Central container"
    Write-Host "Unpublish-BcContainerApp        Unpublish App from Business Central container"
    Write-Host "Get-BcContainerAppInfo          Get info about installed apps from Business Central container"
    Write-Host "Start-BcContainerAppDataUpgrade Start Data Upgrade for an App in a Business Central container"
    Write-Host "Install-NAVSipCryptoProviderFromBcContainer Install Nav Sip Crypto Provider locally from container to sign extensions"
    Write-Host "Sign-BcContainerApp             Uses a Business Central container to sign an App"
    Write-Host
    Write-Host -ForegroundColor Yellow "Tenant handling functions"
    Write-Host "Get-BcContainerTenants          Get all tenants in Business Central container"
    Write-Host "New-BcContainerTenant           Create tenant in multitenant Business Central container"
    Write-Host "Remove-BcContainerTenant        Remove tenant from multitenant Business Central container"
    Write-Host 
    Write-Host -ForegroundColor Yellow "User handling functions"
    Write-Host "Get-BcContainerBcUser           Get all users in Business Central container"
    Write-Host "New-BcContainerBcUser           Create new Nav User in Business Central container"
    Write-Host "New-BcContainerWindowsUser      Create new Windows User in Business Central container"
    Write-Host "Setup-BcContainerTestUsers      Create a set of users for test purposes"
    Write-Host 
    Write-Host -ForegroundColor Yellow "Company handling functions"
    Write-Host "Get-CompanyInBcContainer        Get a list of Companies in Business Central container"
    Write-Host "New-CompanyInBcContainer        Create new Company in Business Central container"
    Write-Host "Remove-CompanyInBcContainer     Remove Company from Business Central container"
    Write-Host 
    Write-Host -ForegroundColor Yellow "Configuration package handling functions"
    Write-Host "Import-ConfigPackageInBcContainer Import Configuration package in Business Central container"
    Write-Host "Remove-ConfigPackageInBcContainer Remove Configuratioin package from Business Central container"
    Write-Host 
    Write-Host -ForegroundColor Yellow "Azure AD specific functions"
    Write-Host "Create-AadAppsForNav             Create Apps in Aad for AAD authentication support"
    Write-Host "Create-AadUsersInBcContainer    Create all active users in the Aad in the Business Central container"
    Write-Host
    Write-Host -ForegroundColor Yellow "Azure VM specific functions"
    Write-Host "Replace-BcServerContainer        Replace or recreate bcserver (primary) container"
    Write-Host "New-LetsEncryptCertificate       Create Lets Encrypt Certificate for secure communication"
    Write-Host "Renew-LetsEncryptCertificate     Renew Lets Encrypt Certificate for secure communication"
    Write-Host
    Write-Host -ForegroundColor White "Note: The BcContainerHelper is an open source project from http://www.github.com/microsoft/NavContainerhelper."
    Write-Host -ForegroundColor White "The project is released as-is, no warranty! Contributions are welcome, study the github repository for usage."
    Write-Host -ForegroundColor White "Report issues on http://www.github.com/microsoft/NavContainerhelper/issues."
    Write-Host
}
Export-ModuleMember -Function Write-BcContainerHelperWelcomeText

# SIG # Begin signature block
# MIInagYJKoZIhvcNAQcCoIInWzCCJ1cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDHvIqthC6ocYIt
# KJf2Xot0k7tvG2kYtcf+Zf291DywyKCCDMkwggYEMIID7KADAgECAhMzAAACHPrN
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
# Ql0v4q8J/AUmQN5W4n101cY2L4A7GTQG1h32HHAvfQESWP0xghn3MIIZ8wIBATBu
# MFcxCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# KDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMjQCEzMAAAIc
# +s3Fm+gvfsQAAAAAAhwwDQYJYIZIAWUDBAIBBQCgga4wGQYJKoZIhvcNAQkDMQwG
# CisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZI
# hvcNAQkEMSIEIMk13c98+Tyttt4GXxwKrGm+313p/vvHzToBDzoe79mSMEIGCisG
# AQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEAWwBNGsrzBxvAJR/kAzOA
# vRNpialbcYvq2EkwpKDOqATbeBBsmF9cNuMp089Vqez82WlKAe9APAoUDwg1AwmW
# nB8eUUZBZOjQt5ZMh6WexW3RgA9McmoELr1mpjU3RtnAAclvUzNROm0tZ7bPugrJ
# v/QNN4EdpC4GlEq2G7wI6g/VL88bnFOGXe5xZOrH4ZS0vxcDU0FN0YPtjANyaBQt
# if8V++4PuDtIecGQCXjualnDbHtzRN9FkCmbhWdFfn7PmwtVJpJ3mnmCwExm2l2e
# 7JuE7p7ib8NdrNYSDzkgZPPHCfuGI3ywoTV2rxfxrFx2eJZFWxep+ZOfqqJ0qCgT
# kaGCF6kwghelBgorBgEEAYI3AwMBMYIXlTCCF5EGCSqGSIb3DQEHAqCCF4Iwghd+
# AgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFWBgsqhkiG9w0BCRABBKCCAUUEggFBMIIB
# PQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCCvyKlfaL/25ToqKAWY
# AcmN5wYKP58z2A6qLrAVQ259zwIGaomzDNRaGA8yMDI2MDgyNzA2MzAzOVowBIAC
# AfSggdmkgdYwgdMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAw
# DgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# LTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEn
# MCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjU1MUEtMDVFMC1EOTQ3MSUwIwYDVQQD
# ExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloIIR+zCCBygwggUQoAMCAQIC
# EzMAAAIb0LK4Amf3cs8AAQAAAhswDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgUENBIDIwMTAwHhcNMjUwODE0MTg0ODMwWhcNMjYxMTEzMTg0ODMw
# WjCB0zELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcT
# B1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEtMCsGA1UE
# CxMkTWljcm9zb2Z0IElyZWxhbmQgT3BlcmF0aW9ucyBMaW1pdGVkMScwJQYDVQQL
# Ex5uU2hpZWxkIFRTUyBFU046NTUxQS0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jv
# c29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAw
# ggIKAoICAQCOxZ3nZlmTMHld7mD+XYaw6MDPfSyDqNXF8UlX7DjEgNXJojcs7xsi
# mbNi6XcBkeDnRQhDw+tJFkalCoWRE276jdgoniDa4ZgFGSwecdhHS5VIJCDnxOGR
# jJ6mUZfegC8ZFW48ilC0CJOxHvoD+B2hTscPARtvvdsnBPKtsoeFH5ZozL0NAcji
# TlCjj5tkOzSSPvpu+Em90ZT5LzPFAGntQCGMmcWorEi6xIhMTvMIJHjbYQuGSFVU
# 4WorbDqHUwC8gt7vqHFEhw+PRIEvavw723HmeNTj62DasB1TXnembKGprN2lRxxg
# ET3ANEVR3970KhbHtN2dSJwH4xqLtFPqqx7t7loapfUHtueP9ke+ut8X4EkQiVL2
# INcBSB6S9dn4VmaO8vA/5037T9yuH76vh7wWScXsRfogl+eY14M3/rxnn2RtonV/
# 4/macph/J0J5mbGsalLS1paQOTfoPeM9Vl+W/Gtz7WuEIiUzm/1qAsQUjXZCIFN+
# k4E4GvcAYI+T54fT6Vq2NBqO6D7b8EPXapvzbnTQtDK1RZPai1r8didGBK/WO9nT
# 92aXUWzFZjM6cKuN90H/s3qk3JK3i+f48Y3p0UuKbuTGiz4H1Z9A97MmLd+4rLIM
# AH3NIc+PVm7ydl95xkn26bjOPsMWC8ldMNOcbmqUbhl1sVFr+ut/OQIDAQABo4IB
# STCCAUUwHQYDVR0OBBYEFLa+n3f+XEumk0rw6Rq4nYC82YhQMB8GA1UdIwQYMBaA
# FJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6Ly93
# d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMFRpbWUtU3Rh
# bXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRgMF4wXAYIKwYBBQUH
# MAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9z
# b2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwGA1UdEwEB/wQC
# MAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwDgYDVR0PAQH/BAQDAgeAMA0GCSqG
# SIb3DQEBCwUAA4ICAQBmRTVfFAPg5MzcZOG3fZNdKEh88Ggx9KwWwFCoU5mosk7H
# Ik6WUgEWmam860Y0+QLlnyV0bxoKm+AU2j+MNZ5PkWJbnd0CP0qdnGmxDc9/l9HN
# IYdFzEQw51chXMMnBxlRfRyN/GdrvJ02/x5cH9eTobpLKtHY4fpLUscxbXWbdS8o
# X54uMg+XjmvGKa4MKgR35p3SU4BcDn+9k4o3mf949h4/QtFyFlfRDofyf9mZI8yV
# uWLcw7znVDT1GZP9kYdr78V3L5YsOvBxjKRX2ZTL/hNvArDoW11Hpk8fEx0iLWmT
# xjaYL8bMKrQsKwfS5MV5DpDs1zcxGYRH/eYtZSFtpYeBfUVthyG9HbZv4G6n5g9H
# lD/QGFpoA3oAgF9waz67+cmggHLJkoDxxPIKadQj/i9boPi/LCDdcEV/h/YPAUfL
# 96+wL7nwoyX6TbBrTlfaQrRP9sI8uFqi/1lfKhtrB804tgaJq4pPYVa9vBnMcgUJ
# PGMHDDo+3m5G8IT+OdRx//GGU4YyfqIo71e3j29lMTZJ8gGT/fiItNEEnoftoY9N
# NCfNrc59a7X91HJwLpaXmiezc+OcZdNIpLFeWUk+aDpH+6Uaic/9QJignqY34ReN
# /IMs9cuqyv3X5VMbWtjNEKM/AEUAe/gQjBoTRqMKt/vl5QYjf6hdTRQ/quWhnzCC
# B3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkAAAAAABUwDQYJKoZIhvcNAQELBQAw
# gYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMT
# KU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRlIEF1dGhvcml0eSAyMDEwMB4XDTIx
# MDkzMDE4MjIyNVoXDTMwMDkzMDE4MzIyNVowfDELMAkGA1UEBhMCVVMxEzARBgNV
# BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jv
# c29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAg
# UENBIDIwMTAwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDk4aZM57Ry
# IQt5osvXJHm9DtWC0/3unAcH0qlsTnXIyjVX9gF/bErg4r25PhdgM/9cT8dm95VT
# cVrifkpa/rg2Z4VGIwy1jRPPdzLAEBjoYH1qUoNEt6aORmsHFPPFdvWGUNzBRMhx
# XFExN6AKOG6N7dcP2CZTfDlhAnrEqv1yaa8dq6z2Nr41JmTamDu6GnszrYBbfowQ
# HJ1S/rboYiXcag/PXfT+jlPP1uyFVk3v3byNpOORj7I5LFGc6XBpDco2LXCOMcg1
# KL3jtIckw+DJj361VI/c+gVVmG1oO5pGve2krnopN6zL64NF50ZuyjLVwIYwXE8s
# 4mKyzbnijYjklqwBSru+cakXW2dg3viSkR4dPf0gz3N9QZpGdc3EXzTdEonW/aUg
# fX782Z5F37ZyL9t9X4C626p+Nuw2TPYrbqgSUei/BQOj0XOmTTd0lBw0gg/wEPK3
# Rxjtp+iZfD9M269ewvPV2HM9Q07BMzlMjgK8QmguEOqEUUbi0b1qGFphAXPKZ6Je
# 1yh2AuIzGHLXpyDwwvoSCtdjbwzJNmSLW6CmgyFdXzB0kZSU2LlQ+QuJYfM2BjUY
# hEfb3BvR/bLUHMVr9lxSUV0S2yW6r1AFemzFER1y7435UsSFF5PAPBXbGjfHCBUY
# P3irRbb1Hode2o+eFnJpxq57t7c+auIurQIDAQABo4IB3TCCAdkwEgYJKwYBBAGC
# NxUBBAUCAwEAATAjBgkrBgEEAYI3FQIEFgQUKqdS/mTEmr6CkTxGNSnPEP8vBO4w
# HQYDVR0OBBYEFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMFwGA1UdIARVMFMwUQYMKwYB
# BAGCN0yDfQEBMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0LmNv
# bS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTATBgNVHSUEDDAKBggrBgEFBQcD
# CDAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYDVR0T
# AQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTV9lbLj+iiXGJo0T2UkFvXzpoYxDBWBgNV
# HR8ETzBNMEugSaBHhkVodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2NybC9w
# cm9kdWN0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcmwwWgYIKwYBBQUHAQEE
# TjBMMEoGCCsGAQUFBzAChj5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2Nl
# cnRzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNydDANBgkqhkiG9w0BAQsFAAOC
# AgEAnVV9/Cqt4SwfZwExJFvhnnJL/Klv6lwUtj5OR2R4sQaTlz0xM7U518JxNj/a
# ZGx80HU5bbsPMeTCj/ts0aGUGCLu6WZnOlNN3Zi6th542DYunKmCVgADsAW+iehp
# 4LoJ7nvfam++Kctu2D9IdQHZGN5tggz1bSNU5HhTdSRXud2f8449xvNo32X2pFaq
# 95W2KFUn0CS9QKC/GbYSEhFdPSfgQJY4rPf5KYnDvBewVIVCs/wMnosZiefwC2qB
# woEZQhlSdYo2wh3DYXMuLGt7bj8sCXgU6ZGyqVvfSaN0DLzskYDSPeZKPmY7T7uG
# +jIa2Zb0j/aRAfbOxnT99kxybxCrdTDFNLB62FD+CljdQDzHVG2dY3RILLFORy3B
# FARxv2T5JL5zbcqOCb2zAVdJVGTZc9d/HltEAY5aGZFrDZ+kKNxnGSgkujhLmm77
# IVRrakURR6nxt67I6IleT53S0Ex2tVdUCbFpAUR+fKFhbHP+CrvsQWY9af3LwUFJ
# fn6Tvsv4O+S3Fb+0zj6lMVGEvL8CwYKiexcdFYmNcP7ntdAoGokLjzbaukz5m/8K
# 6TT4JDVnK+ANuOaMmdbhIurwJ0I9JZTmdHRbatGePu1+oDEzfbzL6Xu/OHBE0ZDx
# yKs6ijoIYn/ZcGNTTY3ugm2lBRDBcQZqELQdVTNYs6FwZvKhggNWMIICPgIBATCC
# AQGhgdmkgdYwgdMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAw
# DgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# LTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEn
# MCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjU1MUEtMDVFMC1EOTQ3MSUwIwYDVQQD
# ExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQCG
# hXqvj0zgYF3jUrVFgHVnR/jO4KCBgzCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1w
# IFBDQSAyMDEwMA0GCSqGSIb3DQEBCwUAAgUA7jof1TAiGA8yMDI2MDgyNzAyMzA0
# NVoYDzIwMjYwODI4MDIzMDQ1WjB0MDoGCisGAQQBhFkKBAExLDAqMAoCBQDuOh/V
# AgEAMAcCAQACAhOzMAcCAQACAhK5MAoCBQDuO3FVAgEAMDYGCisGAQQBhFkKBAIx
# KDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJKoZI
# hvcNAQELBQADggEBAERTaPFTHGtl17q3FyqOPY5+cJ8ZN/GCkgkGHteXeBNwc6Q4
# kwCOSoM+8HQWtM/JOPcf40fl+6DbUMKP2QaewclqeHJbY9aDebZaV4Km/TQ1xLjD
# W8vufOsmQ164bSqVAWjeAbNJ1ELYM61m0BUAPCm8MRaUQnyvTkAgHuN4SJ8BhMbe
# lN2/7qbVL1DPe73Pjm1/7GfiEEJbKvaaZPb4egBmR5ot3jzzGXxbdNlORx//dmb7
# O+ygcUOXd2ieY8/GEOca3J3+4nwQJPPXHOwVHIi5jEN2Gu1ds1uGXQ8QQhZAf1KC
# Dv4x4kjNbQJcm/fkWV7IS722TF/R3eCxJ2qEsgMxggQNMIIECQIBATCBkzB8MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNy
# b3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAhvQsrgCZ/dyzwABAAACGzAN
# BglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8G
# CSqGSIb3DQEJBDEiBCB/7OyS9atd50C0FtFE0k9PI+DLufpZFfdG34FqNs9LpjCB
# +gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EIDAlFJW4PaOYxxAIVd0u4kDAOlRU
# 1nptzp18lTzdDYuAMIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
# c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIw
# MTACEzMAAAIb0LK4Amf3cs8AAQAAAhswIgQgulfbM4TfJGZKsRtjIHpBqHiy1pYa
# 92DSPy+Hg+lfA7gwDQYJKoZIhvcNAQELBQAEggIAJdxK3niRin2dGgkA6sQG6CgL
# AQkJCZ504WCZRVInR/XhTIbghbdT2f/SikDtHxIboeMsMW5qtGeJRLXdSFpeVjzJ
# wrcX55HqpyURfhePI1aZI+2xkSjeUh48uF18ApBUyLc1B3tPeUUjkbjiMgcF4LxY
# 7J+xkhQMwIvpwjMh2FJw+XVwdeuAojBSiBcKpz5O6FS8F+iGqW+ExhtCETae84I5
# 59a4eDzxrMIVyzfQK67aMyPHVAVF+AzYFoSVdTffZhxjMfiqpiJktFBnkXOertFu
# jXe3AcBnS8m1ujt0CznflKL8J+krTTuMNtkYp+s3W7jfxtdwdVjGjudgAoL/T+TV
# e3xD22sQ2rcS4qWwpTuTRPR0AAFbxGrK/idwihXCnfOatMe1DV1+6Q6c470RcVxE
# HLFTPi22WJldrpM8IahB89mRS1HQ0iOkzqB9llIQFfyuDwdW4TvDJFu7rdlvONnq
# vhhR6y5IHL5D6o1TVnGzD7EnMGcy8M/UUEoCh8zWml8GMvc/j2CWFFMdBUM1flDy
# B+ysd+axM4pKZOEwQO8bIsuZUSRhsdLNQdLdWM1zuuU7NQrzvZsFaKvn0NKmg8RS
# Vdz0tVjcDlDdRRMkcGLB3jgy3164rK52c9Rfvx8VASkIUIA3MZQCzUOqY4j9/5Ez
# f61+SOOdrQIri6gMOdc=
# SIG # End signature block
