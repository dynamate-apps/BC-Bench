<#
 .Synopsis
  Function for creating a starting a new Database Export from an online Business Central environment
 .Description
  Function for creating a starting a new Database Export from an online Business Central environment
  Wrapper for https://docs.microsoft.com/en-us/dynamics365/business-central/dev-itpro/administration/administration-center-api#start-environment-database-export
 .Parameter bcAuthContext
  Authorization Context created by New-BcAuthContext.
 .Parameter applicationFamily
  Application Family in which the environment is located. Default is BusinessCentral.
 .Parameter environment
  Environment from which you want to return the published Apps.
 .Parameter apiVersion
  API version. Default is v2.3.
 .Parameter storageAccountSasUri
  An Azure SAS uri pointing at the Azure storage account where the database will be exported to. The uri must have (Read | Write | Create | Delete) permissions
 .Parameter blobContainerName
  The name of the container that will be created by the process to store the exported database.
 .Parameter blobName
  The name of the blob within the container that the database will be exported to. Databases are exported in the .bacpac format so a filename ending with the '.bacpac' suffix is typical.
 .Parameter doNotWait
  Include this flag if you do not want to wait for the backup to complete
 .Example
  $authContext = New-BcAuthContext -includeDeviceLogin
  New-BcEnvironmentDatabaseExport -bcAuthContext $authContext -environment "Production" -storageAccountSasUri $storageAccountSasUri -blobContainerName $blobContainerName -blobName $blobName -doNotWait
#>
function New-BcEnvironmentDatabaseExport {
    Param(
        [Parameter(Mandatory = $true)]
        [Hashtable] $bcAuthContext,
        [string] $applicationFamily = "BusinessCentral",
        [Parameter(Mandatory = $true)]
        [string] $environment,
        [string] $apiVersion = "v2.3",
        [Parameter(Mandatory = $true)]
        [string] $storageAccountSasUri,
        [Parameter(Mandatory = $true)]
        [string] $blobContainerName,
        [Parameter(Mandatory = $true)]
        [string] $blobName,
        [switch] $doNotWait
    )

    $telemetryScope = InitTelemetryScope -name $MyInvocation.InvocationName -parameterValues $PSBoundParameters -includeParameters @()
    try {

        $bcAuthContext = Renew-BcAuthContext -bcAuthContext $bcAuthContext
        $bearerAuthValue = "Bearer $($bcAuthContext.AccessToken)"
        $headers = @{ "Authorization" = $bearerAuthValue }
        $body = @{
            "storageAccountSasUri" = $storageAccountSasUri
            "container"            = $blobContainerName
            "blob"                 = $blobName
        } | ConvertTo-Json
        try {
            Invoke-RestMethod -Method POST -Uri "$($bcContainerHelperConfig.apiBaseUrl.TrimEnd('/'))/admin/$apiVersion/exports/applications/$applicationFamily/environments/$environment" -Headers $headers -Body $Body -ContentType 'application/json' -UseBasicParsing
        }
        catch {
            throw (GetExtendedErrorMessage $_)
        }
        if (!$doNotWait) {
            $uri = [Uri]::new($storageAccountSasUri)
            $blobUrl = "$($uri.Scheme)://$($uri.Host)/$blobContainerName/$blobName$($uri.Query)"
            $done = $false
            Write-Host -NoNewline "Waiting for backup to complete."
            while (!$done) {
                Start-Sleep -Seconds 30
                Write-Host -NoNewline "."
                try {
                    $result = Invoke-WebRequest -UseBasicParsing -Method Head -Uri $blobUrl -ErrorAction SilentlyContinue
                    if ($result.StatusCode -eq 200) {
                        Write-Host -ForegroundColor Green " Success"
                        $done = $true
                    }
                    else {
                        Write-Host -ForegroundColor red " Failure"
                        throw $result.StatusDescription
                    }
                }
                catch {
                    if ($_.exception.response.StatusCode -ne "NotFound") {
                        Write-Host -ForegroundColor red " Failure"
                        throw
                    }
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
Set-Alias -Name New-BcDatabaseExport -Value New-BcEnvironmentDatabaseExport
Export-ModuleMember -Function New-BcEnvironmentDatabaseExport -Alias New-BcDatabaseExport


# SIG # Begin signature block
# MIInbQYJKoZIhvcNAQcCoIInXjCCJ1oCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBt2aAB1HjsBe5c
# lcCAGHqbtJlx91OYmnv3HCy3dYgEZKCCDMkwggYEMIID7KADAgECAhMzAAACHPrN
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
# Ql0v4q8J/AUmQN5W4n101cY2L4A7GTQG1h32HHAvfQESWP0xghn6MIIZ9gIBATBu
# MFcxCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# KDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMjQCEzMAAAIc
# +s3Fm+gvfsQAAAAAAhwwDQYJYIZIAWUDBAIBBQCgga4wGQYJKoZIhvcNAQkDMQwG
# CisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZI
# hvcNAQkEMSIEIL4Y8rvOFzAVK41q0U2S+kge7dHQ2JmHeBnshwBRyoV/MEIGCisG
# AQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEAgYtN/+6fakxl5Ww1cFtO
# cLA0RENxJBsvHgfnv2/4YKwv/GxPG2MI42uhPYsAju7h7k89I9CU7WNMMly0fZaH
# L/gaJsbnAjoztf0c9wObKEk7AGRZPrEuWhENXdmQGaxWIlzfYNUJw7uq5NMU5VXj
# wCuVzfgJILMrASxJs1pFYtkhxOdRGBBcZuuNryonTulXc3wPvwuwN3ckPh51KDgq
# c4Ll3fWe4q/GSTAmOFdsgE5FhNnjhn/BCy5TK6aPdYRLeM85bCSr0+ma3FmCiDEL
# Feh1M0XcQzwTczfrvw0QKreiwaA2+BZx+qh9OwjeADTsOpPQtPcGI6TtdNlgQcn1
# 6KGCF6wwgheoBgorBgEEAYI3AwMBMYIXmDCCF5QGCSqGSIb3DQEHAqCCF4UwgheB
# AgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFZBgsqhkiG9w0BCRABBKCCAUgEggFEMIIB
# QAIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCBJ+HnkbX1OBSpm6cDI
# bP+w6dti9fXT852Ej5H7nBmO6wIGaokHZUNoGBIyMDI2MDgyNzA2MzIzMy44M1ow
# BIACAfSggdmkgdYwgdMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRl
# ZDEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjQzMUEtMDVFMC1EOTQ3MSUwIwYD
# VQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloIIR+zCCBygwggUQoAMC
# AQICEzMAAAIdS8CShziFfjkAAQAAAh0wDQYJKoZIhvcNAQELBQAwfDELMAkGA1UE
# BhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAc
# BgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0
# IFRpbWUtU3RhbXAgUENBIDIwMTAwHhcNMjUwODE0MTg0ODMzWhcNMjYxMTEzMTg0
# ODMzWjCB0zELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
# BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEtMCsG
# A1UECxMkTWljcm9zb2Z0IElyZWxhbmQgT3BlcmF0aW9ucyBMaW1pdGVkMScwJQYD
# VQQLEx5uU2hpZWxkIFRTUyBFU046NDMxQS0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3DQEBAQUAA4IC
# DwAwggIKAoICAQCitKBoADyg6XimHnvjPDb16BQ3wMN6lEctfwUzXMc0mZcboqtK
# pQrDNwpp+im5h09MRNMK9v1ol8RK4BTSIY1QUj8PpHSS91+l7ag9f4TextNC8aLg
# k8fmp0hhRonjlX/hup7x429tbOkL5kqMfX3cN6IjVcAj3XwmhCYGGURej9OifXvb
# WW5kmCKdyx/kuMxjeNfzhbJdRJfd2xLuH/vFUj7DXKODulr7TLej+Z7ZOy/pQlR1
# JNBqnk5EZJ8KdyWc/XPciKJYhavdWjtog9ayAnOrebkbGnFQcJCTyrNSGTnTL+4H
# 4sYTdYgrYLvuLL2IWxJ9ItSfIwTMZENb2ZcdPg8fs7PPoIepASI2/BweqW+UKHWk
# dCHU1dBICo6hUGzmaLp5qx/rLFZN97kOtHv3nTevylTpWoLZj1cxFTjAf1Bthdiw
# hRnfcmad3LbZbUsEMBvEE9AcIGWdwYNTcGB2FVRUt7zSaCAU73wV2RaGjrvDiQ90
# JNGS92+Rjw+tBgT+dCMdcJrSDstwy21lvp6Mwd9D61RZe/r6dnhieSvY6RrFyUUL
# DhEhg0xYPboBZtCP9YR3OBrXx8q3DrovmDNc/NrqMUF88l4oTcfxAC7CmKuYfiaz
# 7mdSM01A6Y2ComfRTX7difsKWzAPv1g3Svd91tgEwMCkFkmk2UrursddGwIDAQAB
# o4IBSTCCAUUwHQYDVR0OBBYEFIRZ8HE0RqZm1ebyCX3ZirzSN/FdMB8GA1UdIwQY
# MBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6
# Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMFRpbWUt
# U3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRgMF4wXAYIKwYB
# BQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWlj
# cm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwGA1UdEwEB
# /wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwDgYDVR0PAQH/BAQDAgeAMA0G
# CSqGSIb3DQEBCwUAA4ICAQCR3B4HjLG8uyksqrQP6aLIPhDQRzFUWk1m4nGJHniB
# ZGR5MMO7KY14HTcmGWwGlvBJgnm5lKAMEK/AcQPZUvyUmkWU6msnPGxdYLY1N8D4
# 7487kWTmPDoseHqN4EAMMR1ADHceqLtmbQnC9D3fPl/p23GSbb1ao5wdhdFd8BDD
# LWFKstfJ95uWpHrqOk//2fR8KRZTiCCxSNClDY2CPUNXT0nhjfLun013zX5ezqpi
# j77tEqbyqIH/k0N6KA4uOUB4WCIRchFQlb6YnKqlDD445GVqpwWNHwe7Qb7/tsx1
# 6Trxhf6Q+kMGTtR74j/GCJgnXFwNEGf+9zMu03vb5EiUPhSBdgu4FIKT/+kMQ9fn
# Pf0Kv6uRzoThjbwU+TgGGWgDK+nrbw/jF8SVBjxNzGtpRtlKHKmhwTqfL3kPUrUG
# SW1masdUoLGaCWe46UzXk0oitcWVcLN2qkK0jBDjXvA0BUX9AM+/PNu6Y91OLp9v
# S0ttJxihtXrO9sGwywoQwThOPVv2ghcLx3JsmridtugRdilHCLVABulI2uf4/EZb
# 25/WrrcWcwm7iCbc6HreeNb+JV/vbeq7PIetKKNYyBjQeJGIdCLQnK7SHwx2FFSn
# ubFuYtByQ+I4XACUhpQ3+TvbnL9otamRFTp+qYuUQ7IflanIt3bcBjL2vy/5Chtr
# qzCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkAAAAAABUwDQYJKoZIhvcNAQEL
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
# 0ZDxyKs6ijoIYn/ZcGNTTY3ugm2lBRDBcQZqELQdVTNYs6FwZvKhggNWMIICPgIB
# ATCCAQGhgdmkgdYwgdMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRl
# ZDEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjQzMUEtMDVFMC1EOTQ3MSUwIwYD
# VQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4DAhoD
# FQC6g74Ept9fOrJ+L0YsR1YeQIt5P6CBgzCBgKR+MHwxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBCwUAAgUA7joc5TAiGA8yMDI2MDgyNzAy
# MTgxM1oYDzIwMjYwODI4MDIxODEzWjB0MDoGCisGAQQBhFkKBAExLDAqMAoCBQDu
# OhzlAgEAMAcCAQACAgbEMAcCAQACAhKVMAoCBQDuO25lAgEAMDYGCisGAQQBhFkK
# BAIxKDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJ
# KoZIhvcNAQELBQADggEBAI14ZLCM5T3ATou01AsTiFvBM4Nnzi5JfTrYBC+TBZtN
# hvbOgi1GLhgN1D6Hibr2PubpPLZggNvmt3synaqykSaRbtVMqlQO9oAHnWxuD2eH
# LkOdnvXdPv7n6Y8wrFotzg4f5bBOlstweCJpUMl+BNarbU8+qgWwuZ5ZjdAcijLQ
# CXF8zrYNHecGNDQc9oyXWzsdlxac57LQj0ok1NySDKPuRHQXnfWvelg+hE1ko4pj
# /LK+if8yLkg4QTV6+ZNqfcZ2esJlbAV86rLRXVt+PAbn4O8pM4S9YfjxBmFluUtM
# gHW7k5uW0stpfvTnY9kyoooEzDXv2EDcx5sQvH7KRu8xggQNMIIECQIBATCBkzB8
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1N
# aWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAh1LwJKHOIV+OQABAAAC
# HTANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEE
# MC8GCSqGSIb3DQEJBDEiBCDIEgzt0q4qw9sGrjLMrG+jlyUtUVfpeQg30BT0vBIe
# zzCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EILG2lcxcSIsnOuozvt6nitM3
# Csw6PqClY32Fm+mPlAVRMIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgT
# Cldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENB
# IDIwMTACEzMAAAIdS8CShziFfjkAAQAAAh0wIgQgHNUuZZfjza+1URYORdYqzXGc
# rSOAWjrfiofILtQ1LKEwDQYJKoZIhvcNAQELBQAEggIAVBR++dmO9FHxWEXvVxbF
# UeaWufmk9T9A402XfcHSHrlHCsfe6d2ZF29HWLhlTNkfvZ/Jnwt3F6L5RuFsLaK6
# UATibmV2/OLv07KtruclOdSC7jVEq4XRy0Ys43itIWBlAzW+7bETc6X3Jr+EqIUU
# a/mTG0W9Ido+CskUeCKaOukZcAkisatHqb/+PEV3k+eTccmvaHyYEhyu/15k3G5z
# 5RLhdAb8qmwA3UbMmDypwq2Uoq6nyKAkHp5uzYqW/Kcva//1qCsH6JX1q7cd7qt2
# JE0KbO9CSUZvM7bxm4jmSzkAr9sffd9iN2Hf2IOljO1UwLfkpzA59N1K3OhgBv59
# yqVyuQ5uCfOlIpsTU3VkeFg4PXKdqphka81iMDMCSNOlaKlpIenY7oodv63iXhcA
# cHWRZjEYc7C28TNQN0TLy4EvlFrH89h+YJXQXQz18ErkKaagiSkoHtBpGM3soOj2
# LukaAMMUP15FKTj5mEQmQnxuTeBlkBCMAwHZAiPtjjyw5lma5kRVOt8aowTL5+sx
# izIJEhlOoS4j4jUTIl3Z7TIWIIpGk4694AvVHzufoD4bTYRQcnJJsehiKMAC6oqJ
# kIuckkrPtQ8EFsmFmt1dhtAzguKIIefxXZJBMJMp8z9oS/gj4Hr2y0UXhbKkk/Vo
# aSMBna7Fz45WajOj/8XDMdM=
# SIG # End signature block
