<#
 .Synopsis
  Create a new AppSource submission (submit a new version of your app for validation)
 .Description
  Returns a PSCustomObject with submission details
 .Parameter authContext
  Authentication Context from New-BcAuthContext
 .Parameter productId
  Id of the product for which you want to create a new submission
 .Parameter appFile
  Path of the main app File
 .Parameter libraryAppFiles
  An array of app files to be included as library app files. If this array consists of a single file, it will be uploaded as-is - if multiple files are provided, they will be zipped together and uploaded
 .Parameter autoPromote
  Include this switch if you want to automatically promote the submission to production / Go Live after validation/preview
 .Parameter doNotWait
  Include this switch if you do not want to wait for the submission to pass or fail (note that if you include autoPromote, the function will wait for first part of validation)
 .Parameter force
  If another submission is in progress, it will be cancelled if you include the force switch
 .Parameter silent
  Include this switch if you do not want the method to display URLs etc.
 .Parameter doNotCheckVersionNumber
  Include this switch avoid checking whether the new version number is greater than the existing version number in Partner Center
 .Parameter doNotUpdateVersionNumber
  Include this switch when you do not want to change the version number of the product in Partner Center (can be used for hotfixes) 
 .Example
  New-AppSourceSubmission -authContext $authContext -productId $product.Id -appFile $appFile
 .Example
  New-AppSourceSubmission -authContext $authContext -productId $product.Id -appFile $appFile -libraryAppFiles @($libraryApp1,$libraryApp2) -autoPromote -doNotWait -silent
#>
function New-AppSourceSubmission {
    Param(
        [Parameter(Mandatory=$true)]
        [HashTable] $authContext,
        [Parameter(Mandatory=$true)]
        [string] $productId,
        [Parameter(Mandatory=$false)]
        [string] $appFile = "",
        [Parameter(Mandatory=$false)]
        [string[]] $libraryAppFiles = @(),
        [switch] $autoPromote,
        [switch] $doNotWait,
        [switch] $force,
        [switch] $silent,
        [Obsolete("doNotCheckVersionNumber is obsolete, please use doNotUpdateVersionNumber instead")]
        [switch] $doNotCheckVersionNumber,
        [switch] $doNotUpdateVersionNumber
    )

$telemetryScope = InitTelemetryScope -name $MyInvocation.InvocationName -parameterValues $PSBoundParameters -includeParameters @()
try {
    $authContext = Renew-BcAuthContext -bcAuthContext $authContext
    if ($telemetryScope) {
        if ($authContext.ClientID) {
            AddTelemetryProperty -telemetryScope $telemetryScope -key "client" -value (GetHash -str $authContext.ClientID)
        }
        AddTelemetryProperty -telemetryScope $telemetryScope -key "product" -value (GetHash -str $productId)
        AddTelemetryProperty -telemetryScope $telemetryScope -key "autoPromote" -value "$autoPromote"
    }
    
    $product = Get-AppSourceProduct -authContext $authContext -productId $productId -silent:($silent.IsPresent) -includeSetup
    if ($product) {
        if ($product.Setup.packageType -eq "Connect") {
            throw "Product $($product.Name) is a Connect App, you cannot submit an app to a Connect app"
        }
    }
    else {
        throw "No product found with ProductID=$productID with this account"
    }

    $submission = Get-AppSourceSubmission -authContext $authContext -productId $productId -silent:($silent.IsPresent)
    if ($submission) {
        if ($submission.state -eq "InProgress") {
            if ($submission.substate -eq "Failed") {
                # ignore
            }
            elseif ($force) {
                Cancel-AppSourceSubmission -authContext $authContext -productId $productId -submissionId $submission.id -silent:($silent.IsPresent)
            }
            else {
                throw "An AppSource submission is in progress. If you want to cancel an in progress submission, you need to add -force"
            }
        }
        elseif (!($submission.state -eq "Published" -and ($submission.substate -eq "ReadyToPublish" -or $submission.substate -eq "InStore"))) {
            throw "An AppSource submission already running. You cannot create a new submission, when an existing submission is in substate=$($submission.substate)"
        }
    }

    $variantID = ''
    $branchesPackage = @(Invoke-IngestionApiGetCollection -authContext $authContext -path "/products/$productId/branches/getByModule(module=Package)" -silent:($silent.IsPresent) | Where-Object { 
        $thisVariantID = ''
        if ($_.PSObject.Properties.name -eq "variantID") { $thisVariantID = $_.variantID }
        $variantID -eq $thisVariantID
    })
    if ($branchesPackage.Count -ne 1) {
        throw "Unable to locate package from Ingestion API"
    }
    $packageCurrentDraftInstanceID = $branchesPackage[0].currentDraftInstanceID
    
    $appVersionNumber = ""
    if ($appFile) {
        $appJson = Get-AppJsonFromAppFile -appFile $appFile
        $appVersionNumber = [System.Version]$appJson.version
    }

    $tempFolder = ""
    $libraryAppFile = ""
    if ($libraryAppFiles -and ($libraryAppFiles.Count -gt 0)) {
        if ($libraryAppFiles.Count -eq 1) {
            $libraryAppFile = $libraryAppFiles[0]
        }
        else {
            $tempFolder = Join-Path ([System.IO.Path]::GetTempPath()) ([GUID]::NewGuid().ToString())
            New-Item -Path $tempFolder -ItemType Directory | Out-Null
            $libraryAppFile = Join-Path $tempFolder "$([System.IO.Path]::GetFileNameWithoutExtension($appFile)).libraries.zip"
            Compress-Archive -Path $libraryAppFiles -DestinationPath $libraryAppFile -CompressionLevel Fastest
        }
    }
    
    $packageConfigurations = @(Invoke-IngestionApiGetCollection -authContext $authContext -path "/products/$productId/packageConfigurations/getByInstanceID(instanceID=$($packageCurrentDraftInstanceID))" -silent:($silent.IsPresent))
    if ($packageConfigurations.Count -ne 1) {
        $packageConfigurations | fl | Out-Host
        throw "unable to locate package configuration"
    }
    $packageConfiguration = $packageConfigurations[0]

    0..1 | ForEach-Object {
        if ($_ -eq 0) {
            $parameterName = 'AppFile'
            $file = $appFile
            $resourceType = "Dynamics365BusinessCentralAddOnExtensionPackage"
        }
        else {
            $parameterName = 'LibraryAppFiles'
            $file = $libraryAppFile
            $resourceType = "Dynamics365BusinessCentralAddOnLibraryExtensionPackage"
        }
        if ($PSBoundParameters.ContainsKey($parameterName)) {
            $packageConfiguration.packageReferences = @($packageConfiguration.packageReferences | Where-Object { $_.type -ne $resourceType })
        }
        if ($file) {
            $body = @{
                "resourceType" = $resourceType
                "fileName" = [System.IO.Path]::GetFileName($file)
            }
            $packageUpload = Invoke-IngestionApiPost -authContext $authContext -path "/products/$productId/packages" -Body $body -silent:($silent.IsPresent)
        
            # Upload directly to the SAS URI as-issued (works for any host, e.g. Azure Front Door - see issue #4191).
            # Fall back to the legacy Az.Storage upload (only valid for <account>.blob.core.windows.net hosts) if that fails.
            try {
                Invoke-RestMethod -Method Put -Uri $packageUpload.fileSasUri -InFile $file -Headers @{ 'x-ms-blob-type' = 'BlockBlob' } -ContentType 'application/octet-stream' | Out-Null
            }
            catch {
                if (!$silent) {
                    Write-Host -ForegroundColor Yellow "WARNING: Direct upload to the SAS URI failed ($($_.Exception.Message.Trim())). Falling back to the Az.Storage upload."
                }
                $uri = [System.Uri] $packageUpload.fileSasUri
                $storageAccountName = $uri.DnsSafeHost.Split(".")[0]
                $container = $uri.LocalPath.Substring(1).split('/')[0]
                $blobname = $uri.LocalPath.Substring(1).split('/')[1]
                $sasToken = $uri.Query

                if (!(get-command New-AzureStorageContext -ErrorAction SilentlyContinue)) {
                    Set-Alias -Name New-AzureStorageContext -Value New-AzStorageContext
                    Set-Alias -Name Set-AzureStorageBlobContent -Value Set-AzStorageBlobContent
                }

                $storageContext = New-AzureStorageContext -StorageAccountName $storageAccountName -SasToken $sasToken
                Set-AzureStorageBlobContent -File $file -Container $container -Blob $blobname -Context $storageContext -Force | Out-Null
            }
        
            $packageUpload.state = "Uploaded"
            $packageUploaded = Invoke-IngestionApiPut -authContext $authContext -path "/products/$productId/packages/$($packageUpload.id)" -Body ($packageUpload | ConvertTo-HashTable) -silent:($silent.IsPresent)
            if ($packageUploaded.state -ne "Processed") {
                throw "Could not process package"
            }

            $packageConfiguration.packageReferences += @([PSCustomObject]@{
                "type" = $resourceType
                "value" = $packageUploaded.id
            })
        }
    }
    if ($tempFolder -and (Test-Path $tempFolder -PathType Container)) {
        Remove-Item $tempFolder -Recurse -Force
    }

    $result = Invoke-IngestionApiPut -authContext $authContext -path "/products/$productId/packageConfigurations/$($packageConfiguration.id)" -Body ($packageConfiguration | ConvertTo-HashTable -recurse) -silent:($silent.IsPresent)
    
    $body = [ordered]@{
        "resourceType" = "SubmissionCreationRequest"
        "targets" = @(
            [ordered]@{
                "type" = "Scope"
                "value" = "preview"
            }
        )
        "resources" = @(
            [ordered]@{
                "type" = "Package"
                "value" = $packageCurrentDraftInstanceID
            }
        )
    }
    if ($appVersionNumber -and !$doNotUpdateVersionNumber) {
        $branchesProperty = @(Invoke-IngestionApiGetCollection -authContext $authContext -path "/products/$productId/branches/getByModule(module=Property)" -silent:($silent.IsPresent) | Where-Object { 
            $thisVariantID = ''
            if ($_.PSObject.Properties.name -eq "variantID") { $thisVariantID = $_.variantID }
            $variantID -eq $thisVariantID
        })
        if ($branchesProperty.Count -ne 1) {
            throw "Unable to locate properties from Ingestion API"
        }
        $propertyCurrentDraftInstanceID = $branchesProperty[0].currentDraftInstanceID

        $properties = @(Invoke-IngestionApiGetCollection -authContext $authContext -path "/products/$productId/properties/getByInstanceID(instanceID=$propertyCurrentDraftInstanceID)" -silent:($silent.IsPresent))
        if ($properties.Count -ne 1) {
            $properties | fl | Out-Host
            throw "unable to locate properties"
        }
        $property = $properties[0]
        if (!$doNotCheckVersionNumber) {
            $prevVersion = [System.Version]"0.0.0.0"
            if ([System.Version]::TryParse($property.appVersion, [ref] $prevVersion)) {
                if ($prevVersion -gt $appVersionNumber) {
                    # This error message is used in the Federated credentials test in AL-Go for GitHub to determine the next version number for a submission
                    throw "The new version number ($appVersionNumber) is lower than the existing version number ($prevVersion) in Partner Center"
                }
            }
        }
        $property.appVersion = $appVersionNumber.ToString()
        $result = Invoke-IngestionApiPut -authContext $authContext -path "/products/$productId/properties/$($property.id)" -Body ($property | ConvertTo-HashTable -recurse) -silent:($silent.IsPresent)
        $body.resources += @(
            [ordered]@{
                "type" = "Property"
                "value" = $propertyCurrentDraftInstanceID
            }
        )
    }
    
    $submission = Invoke-IngestionApiPost -authContext $authContext -path "/products/$productId/submissions" -Body $body -silent:($silent.IsPresent)
    
    if ($doNotWait.IsPresent -and !$autoPromote.IsPresent) {
        Write-Host -ForegroundColor Green "New AppSource submission created"
        $submission
    }
    else {
        $jobs = @{
            "Automated validation" = "NotStarted"
            "Preview Creation" = "NotStarted"
            "Publisher Signoff" = "NotStarted"
            "Certification" = "NotStarted"
            "Publish" = "NotStarted"
        }
        $promoted = $false
        $lastName = ""
        do {
            Start-Sleep -Seconds 30
            $authContext = Renew-BcAuthContext -bcAuthContext $authContext -silent

            $complete = $false
            $failed = $false
            $status = @(Invoke-IngestionApiGetCollection -authContext $authContext -path "/products/$productId/submissions/$($submission.id)/workflowdetails" -silent)
            if ($status.Count -ne 2) {
                $status | fl | Out-Host
                throw "Unexpected error when trying to get status for submission. Please consult Partner Center UI."
            }
            0..1 | ForEach-Object {
                $st = $status[$_]
                $st.workflowSteps | ForEach-Object {
                    if ($jobs."$($_.Name)" -eq $_.State) {
                        if ($_.state -eq "InProgress") {
                            Write-Host -NoNewline '.'
                        }
                        elseif ($_.state -eq "NotStarted") {
                        }
                    }
                    else {
                        if ($jobs."$($_.Name)" -eq "NotStarted") {
                            Write-Host -NoNewline $_.Name
                        }
                        if ($_.State -eq "Success") {
                            Write-Host -ForegroundColor Green ' Success'
                        }
                        elseif ($_.state -eq "InProgress") {
                            Write-Host -NoNewline '.'
                        }
                        else {
                            Write-Host -ForegroundColor Red ' Failure'
                            $failed = $true
                        }
                        $jobs."$($_.Name)" = $_.State
                    }
                }
            }
            $sm = Invoke-IngestionApiGet -authContext $authContext -path "/products/$productId/submissions/$($submission.id)" -silent
            if ($sm.state -eq "Published" -and $sm.substate -eq "ReadyToPublish") {
                if ($autoPromote.IsPresent) {
                    if (!$promoted) {
                        Promote-AppSourceSubmission -authContext $authContext -productId $productId -submissionId $submission.id -silent:($silent.IsPresent) | Out-Null
                        $promoted = $true
                        if ($doNotWait.IsPresent) {
                            $complete = $true
                        }
                    }
                }
                else {
                    $complete = $true
                }
            }
            elseif ($sm.state -eq "Published" -and $sm.substate -eq "InStore") {
                $complete = $true
            }
        } while (!$complete -and !$failed)
        
        if ($failed) {
            Write-Host -ForegroundColor Red "New AppSource submission failed"
        }
        else {
            Write-Host -ForegroundColor Green "New AppSource submission succeeded"
        }
        $sm
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
Export-ModuleMember -Function New-AppSourceSubmission
# SIG # Begin signature block
# MIInSAYJKoZIhvcNAQcCoIInOTCCJzUCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCb/F8f3SnQ5TQJ
# niQwoa5GF6aFjgV8DgDKwZUdJyaa7aCCDLowggX1MIID3aADAgECAhMzAAACHU0Z
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
# 1cY2L4A7GTQG1h32HHAvfQESWP0xghnkMIIZ4AIBATBuMFcxCzAJBgNVBAYTAlVT
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
# c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMjQCEzMAAAIdTRnITtcPV0gAAAAAAh0w
# DQYJYIZIAWUDBAIBBQCgga4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYK
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIHZJ8Xpu
# usaRht17mMbxutQb6fnE7k4t7hi4fcTIl+gIMEIGCisGAQQBgjcCAQwxNDAyoBSA
# EgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20w
# DQYJKoZIhvcNAQEBBQAEggEAEsM5FJA0WNz3NThQe7qgGUdNyvWaqQBztzffOGcj
# YF0LNkLZat7JqgBwNsThAwpN/1aPhgb+zUPvEm84siaUeNlS1Cbn1G8k2ZKSLWcs
# DcQIY/JB7qgUur+nRFi8FAscVnvW5H35RLItcj2HQwC76xeLxR5MpidLkYQ9/Owz
# VKLWKWvGZ2OwGPGCL0k/h1BEB9OX6vpSlpMmeLyHVV5KpwykjUo5oHjckhU86IHz
# Ok5Cv6VCMjdInHZHSktsGGswu4DWNIFk8H/Hy4XhSy500+++FxdJdmYzS8ZFnkY+
# /M9zwDrfj02UDganH90jTjccj7KtOUY/2pAgPMQ3CpHD5qGCF5YwgheSBgorBgEE
# AYI3AwMBMYIXgjCCF34GCSqGSIb3DQEHAqCCF28wghdrAgEDMQ8wDQYJYIZIAWUD
# BAIBBQAwggFRBgsqhkiG9w0BCRABBKCCAUAEggE8MIIBOAIBAQYKKwYBBAGEWQoD
# ATAxMA0GCWCGSAFlAwQCAQUABCBwkUnfHGUWHeZTyAX8uHq7jR/tr4WgxdqI/OYO
# x4mD/AIGaoWNtXnRGBIyMDI2MDgzMTA5NDQxOS45MVowBIACAfSggdGkgc4wgcsx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJTAjBgNVBAsTHE1p
# Y3Jvc29mdCBBbWVyaWNhIE9wZXJhdGlvbnMxJzAlBgNVBAsTHm5TaGllbGQgVFNT
# IEVTTjpFMDAyLTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3Rh
# bXAgU2VydmljZaCCEe0wggcgMIIFCKADAgECAhMzAAACKQ7VZCq0l/IaAAEAAAIp
# MA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
# dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9y
# YXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMB4X
# DTI2MDIxOTE5NDAwN1oXDTI3MDUxNzE5NDAwN1owgcsxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xJTAjBgNVBAsTHE1pY3Jvc29mdCBBbWVyaWNh
# IE9wZXJhdGlvbnMxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjpFMDAyLTA1RTAt
# RDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZTCCAiIw
# DQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAJ4i0WrjPWgJhKZRmalgOxslYS77
# 7Vttz8zPs9rcjRlfkQ435aKsHQW+caXIVFTKXM7lMldl9TxAU85T3k/VjU5nwn6q
# 4Dkb4BZIE6v/jyxyXSz1EGmqBMyr+VvKoHPgIya9VHZB68CBWnhrWFuY6b0bthZ7
# Lrw3kXmtINhXTAyWDgjLxhG4WBE3Z4GlVe30i8VoWYGdAtl+jbYpncvw9YQdSFdT
# l0s5JmhN+qpD8H515bnoAIyeceM/Fm76zMeFkwtSsxZOCz0nsKfwO16VwqP1oz7R
# mru2RIMcKvCjp4JJ/DdyWS1dFGt2axxxqXxEIOI0UWBmzKnAXZoYAXqSDjX5CX62
# Femc4xQfiY8IAllanTMNajCwr9ijmMcvWlP8CBsvcWgDLhxuE4jg9vV5AUb6NPuy
# RLYX9v5kAJQDUQNnzfQr4G7TLD4WlIbLy2l3WzOTdxRiMinMgbjPegU2aJIk3xh0
# 13hIewRHkOSzlvGIpum+Z+s4Df2NNvsRbZNPvJJaAkhJ+9N7O4uZCxNVLM2y9qlW
# UeETbMGoPDjT2e862K0IVueGFc19q3Nvb4Z/a1fazpgFrXnUIL/z56Ym+96BdtY2
# 53Ni3xwVGibQ9n58lGGEF91KoKqvxB44YnxViWbEVerHVJ0NKRMJKCmyyQapnCH/
# q6YDWDgvvN4YE2eBAgMBAAGjggFJMIIBRTAdBgNVHQ4EFgQUJ01FpIv0BbxC9pDb
# VaNEBco3gzswHwYDVR0jBBgwFoAUn6cVXQBeYl2D9OXSZacbUzUZ6XIwXwYDVR0f
# BFgwVjBUoFKgUIZOaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwv
# TWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3JsMGwGCCsG
# AQUFBwEBBGAwXjBcBggrBgEFBQcwAoZQaHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAx
# MCgxKS5jcnQwDAYDVR0TAQH/BAIwADAWBgNVHSUBAf8EDDAKBggrBgEFBQcDCDAO
# BgNVHQ8BAf8EBAMCB4AwDQYJKoZIhvcNAQELBQADggIBAD3BzvaV/9zMOGnT1Pc8
# YAw5CHGX/HTiOkTu3f0V6pBKfZSnoNXOGDCfMKpjc0iEu1Rpat3s3G+uFkNxr4nj
# HO+tFA08d5FCmclV4ezJO7neBMGVQHVNEjo6dm38BWZH2gwn80E6oH535I5vw/Hr
# NGBHCTrawWQ6QHmWKD8MydgR5H9qZb0d2jy9dwqZpr8NtI4AdJ19kW36Koxl82WQ
# Q6fvX9EApM2/hCmr/YWFyMwyZKQiGyEF0FUHRWOaTAV+FVR/lNO4sn2wNHgTIK85
# kncHqDsjDpaNDHJyPCR/OxUxOl+6wnlLB04cvzIY9Zk54+PBrwhJdazqSJUr/pLT
# 8lVvUunGnJgpERCOdT/k55wq3Y5eUd3AVZmvACL3xE9lroQTFxv8sYt/XS00eO7V
# 5OWiFjSPM1lDQEOBK4xmAxT7wQSO0xAwgOeU8YRQ43ssdccfQovQUDTU8RZVkquv
# 8tQ664NM0XPDnjcU8yniCQIgWUp1G5yJHUhc6T5ex7quP20kViBWf7jgEei7ZdB7
# lFffR5/cBBZrSbHIYOonMaxXdfn5s1B4xXzyJa6Uk+rmyCcYb078fX8cfgew71ko
# Zf9asmlCYW5CtM5Hj1eO95oLTFoWYaw2D5GFu0PmpOSf4hIO/DQgn8T9Vc13P/Ja
# CiXqvnTuFPywAy6meGQXa7DUMIIHcTCCBVmgAwIBAgITMwAAABXF52ueAptJmQAA
# AAAAFTANBgkqhkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
# c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUg
# QXV0aG9yaXR5IDIwMTAwHhcNMjEwOTMwMTgyMjI1WhcNMzAwOTMwMTgzMjI1WjB8
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1N
# aWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDCCAiIwDQYJKoZIhvcNAQEBBQAD
# ggIPADCCAgoCggIBAOThpkzntHIhC3miy9ckeb0O1YLT/e6cBwfSqWxOdcjKNVf2
# AX9sSuDivbk+F2Az/1xPx2b3lVNxWuJ+Slr+uDZnhUYjDLWNE893MsAQGOhgfWpS
# g0S3po5GawcU88V29YZQ3MFEyHFcUTE3oAo4bo3t1w/YJlN8OWECesSq/XJprx2r
# rPY2vjUmZNqYO7oaezOtgFt+jBAcnVL+tuhiJdxqD89d9P6OU8/W7IVWTe/dvI2k
# 45GPsjksUZzpcGkNyjYtcI4xyDUoveO0hyTD4MmPfrVUj9z6BVWYbWg7mka97aSu
# eik3rMvrg0XnRm7KMtXAhjBcTyziYrLNueKNiOSWrAFKu75xqRdbZ2De+JKRHh09
# /SDPc31BmkZ1zcRfNN0Sidb9pSB9fvzZnkXftnIv231fgLrbqn427DZM9ituqBJR
# 6L8FA6PRc6ZNN3SUHDSCD/AQ8rdHGO2n6Jl8P0zbr17C89XYcz1DTsEzOUyOArxC
# aC4Q6oRRRuLRvWoYWmEBc8pnol7XKHYC4jMYctenIPDC+hIK12NvDMk2ZItboKaD
# IV1fMHSRlJTYuVD5C4lh8zYGNRiER9vcG9H9stQcxWv2XFJRXRLbJbqvUAV6bMUR
# HXLvjflSxIUXk8A8FdsaN8cIFRg/eKtFtvUeh17aj54WcmnGrnu3tz5q4i6tAgMB
# AAGjggHdMIIB2TASBgkrBgEEAYI3FQEEBQIDAQABMCMGCSsGAQQBgjcVAgQWBBQq
# p1L+ZMSavoKRPEY1Kc8Q/y8E7jAdBgNVHQ4EFgQUn6cVXQBeYl2D9OXSZacbUzUZ
# 6XIwXAYDVR0gBFUwUzBRBgwrBgEEAYI3TIN9AQEwQTA/BggrBgEFBQcCARYzaHR0
# cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9Eb2NzL1JlcG9zaXRvcnkuaHRt
# MBMGA1UdJQQMMAoGCCsGAQUFBwMIMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBB
# MAsGA1UdDwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFNX2VsuP
# 6KJcYmjRPZSQW9fOmhjEMFYGA1UdHwRPME0wS6BJoEeGRWh0dHA6Ly9jcmwubWlj
# cm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1Jvb0NlckF1dF8yMDEwLTA2
# LTIzLmNybDBaBggrBgEFBQcBAQROMEwwSgYIKwYBBQUHMAKGPmh0dHA6Ly93d3cu
# bWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMu
# Y3J0MA0GCSqGSIb3DQEBCwUAA4ICAQCdVX38Kq3hLB9nATEkW+Geckv8qW/qXBS2
# Pk5HZHixBpOXPTEztTnXwnE2P9pkbHzQdTltuw8x5MKP+2zRoZQYIu7pZmc6U03d
# mLq2HnjYNi6cqYJWAAOwBb6J6Gngugnue99qb74py27YP0h1AdkY3m2CDPVtI1Tk
# eFN1JFe53Z/zjj3G82jfZfakVqr3lbYoVSfQJL1AoL8ZthISEV09J+BAljis9/kp
# icO8F7BUhUKz/AyeixmJ5/ALaoHCgRlCGVJ1ijbCHcNhcy4sa3tuPywJeBTpkbKp
# W99Jo3QMvOyRgNI95ko+ZjtPu4b6MhrZlvSP9pEB9s7GdP32THJvEKt1MMU0sHrY
# UP4KWN1APMdUbZ1jdEgssU5HLcEUBHG/ZPkkvnNtyo4JvbMBV0lUZNlz138eW0QB
# jloZkWsNn6Qo3GcZKCS6OEuabvshVGtqRRFHqfG3rsjoiV5PndLQTHa1V1QJsWkB
# RH58oWFsc/4Ku+xBZj1p/cvBQUl+fpO+y/g75LcVv7TOPqUxUYS8vwLBgqJ7Fx0V
# iY1w/ue10CgaiQuPNtq6TPmb/wrpNPgkNWcr4A245oyZ1uEi6vAnQj0llOZ0dFtq
# 0Z4+7X6gMTN9vMvpe784cETRkPHIqzqKOghif9lwY1NNje6CbaUFEMFxBmoQtB1V
# M1izoXBm8qGCA1AwggI4AgEBMIH5oYHRpIHOMIHLMQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBP
# cGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046RTAwMi0wNUUwLUQ5
# NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WiIwoBATAH
# BgUrDgMCGgMVALe/2JI7bbGhvtnE3l1cISr70i//oIGDMIGApH4wfDELMAkGA1UE
# BhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAc
# BgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0
# IFRpbWUtU3RhbXAgUENBIDIwMTAwDQYJKoZIhvcNAQELBQACBQDuPzOYMCIYDzIw
# MjYwODMwMjI1NjI0WhgPMjAyNjA4MzEyMjU2MjRaMHcwPQYKKwYBBAGEWQoEATEv
# MC0wCgIFAO4/M5gCAQAwCgIBAAICGxACAf8wBwIBAAICElAwCgIFAO5AhRgCAQAw
# NgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYBBAGEWQoDAqAKMAgCAQACAwehIKEKMAgC
# AQACAwGGoDANBgkqhkiG9w0BAQsFAAOCAQEAwCjULk3KPAR4BrcMslSjtQbLeNgA
# pcOg5xIXDv0KTat8ru4GzKNlBLEz2tzT9mSCLGZQMWG06OQOuHFMFjzQLOuyQwPi
# n0vA3m6NmS8d6jz00oZrV4c40d+KKM39Fsa1RGWMYURvCpsGV1bdo4IQd2OKSuau
# ujrzp+eFkgMHfkqZzwPWe4fywc2AfSn28SQjvJpC0wYPXdApGop20mECOxOVB2Ry
# LXGA4SkSoKbMf/j5b3Sp6EYK4zIEaC6GBkhgdNAE5hElwJuFqhNwE9nEsl2rWii+
# BBpnfXzcno4Jfigro+2C6+Wz2MVLIrThaFvgRdtUxcCYx22JQ02/IotBZTGCBA0w
# ggQJAgEBMIGTMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAw
# DgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# JjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAACKQ7V
# ZCq0l/IaAAEAAAIpMA0GCWCGSAFlAwQCAQUAoIIBSjAaBgkqhkiG9w0BCQMxDQYL
# KoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkEMSIEIG0no6ghVUTy4+CqgiIQ7ksIZ038
# 0imLcY2ce2Df80DRMIH6BgsqhkiG9w0BCRACLzGB6jCB5zCB5DCBvQQgt8o98SK2
# 8P+VK8S6bGo+SR44S2CSYoURUy56X2g6upIwgZgwgYCkfjB8MQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGlt
# ZS1TdGFtcCBQQ0EgMjAxMAITMwAAAikO1WQqtJfyGgABAAACKTAiBCCp8aA7nq/6
# Fz3Po+cMG4SFpwgwLBGIrILuQZoO1De0mTANBgkqhkiG9w0BAQsFAASCAgA6LhVr
# 01Kl4Vj+VKIX4ve0xUzPacOs6vDNQ48Vzp6OVLw0+JJUvT66uW2AvjBhf0iL1sBR
# E+6jyEsrgSn1+39JBzr5DgpuHqmA+Z6Z7yuzj/8zMMBxyPHtsm2JiPqRqfWEhHbA
# 7KB4yVtSyUYEYyV3vbdZAqZ2WA4aI4jge3U7uFXVQAs2mX36ao3pcjf4lg9EweIb
# Q1bKxbPig6kKz/zH83/HVufUuuy27ILIk0IwIhMxwRDdb7dwvb+ous0z1q0aaNpC
# wNI2zJPl6uEYKYE31z8KDx5jJCnVAjGzmPAzc+3niHZxT0M64NHqRQUhpLkJlXx8
# ydlg6JSeiSv09ASTgmy+1ekrs7LiOUWnNQXFw06QvinBt1Ew9x4lS8DSUkKbiFdG
# XmS/fm7/WFmTxw/3hxGBS1wwRPNgQZvv2DFMMAr7HoyrCPy9UOv54aPPwDStVNqk
# s/Fz+RdYDzgMVH3yZtpPyL5yAByjlyZXS44RIC8VHSVaakn/+lUfaG2027whDtjI
# K9KZq8MPd+++hy5Qn4TIpySRLu3PguTLGrrxDyeK9lrXHxz1DqY79F4D7yoSu7fT
# kH/GAAlV/p0a0/RTdA3P36gRo/TGP2Zkksdw3arjvzzG9gtAFIklWe6Ar1rMi+Ig
# U1UYID65PcpS6Nmf8gDhXX4qcqcYlf/HmqUVkA==
# SIG # End signature block
