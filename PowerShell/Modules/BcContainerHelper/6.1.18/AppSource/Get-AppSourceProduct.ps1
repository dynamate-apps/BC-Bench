<#
 .Synopsis
  Get information about AppSource products from the authenticated account
 .Description
  Returns one or more PSCustomObject with information about your AppSource products
 .Parameter authContext
  Authentication Context from New-BcAuthContext
 .Parameter productId
  Id of the product for which you want to get information 
 .Parameter productName
  Name of the product for which you want to get information (supports wildcards)
 .Parameter includeProperty
  Include this switch if you want do include the properties of the product
 .Parameter includeListing
  Include this switch if you want do include the listings of the product
 .Parameter includeSetup
  Include this switch if you want do include the setup of the product
 .Parameter includeProductAvailability
  Include this switch if you want do include the productavailability of the product
 .Parameter includeFeatureAvailability
  Include this switch if you want do include the featureavailability of the product (including markets)
 .Parameter includeListingAsset
  Include this switch if you want do include the assets of the listings of the product (including FileSasUri)
 .Parameter includeListingImage
  Include this switch if you want do include the images of the listings of the product (including FileSasUri)
 .Parameter includeListingVideo
  Include this switch if you want do include the videos of the listings of the product (including FileSasUri)
 .Parameter includePackage
  Include this switch if you want do include the packages of the product
 .Parameter includeAll
  Include this switch if you want to include all additional information about the product
 .Parameter silent
  Include this switch if you do not want the method to display URLs etc.
 .Example
  @(Get-AppSourceProduct -authContext $authcontext -silent)

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
 .Example
  Get-AppSourceProduct -authContext $authcontext -productId $productId -silent
  
  resourceType          : AzureDynamics365BusinessCentral
  name                  : BingMaps.AppSource
  externalIDs           : {@{type=AzureOfferId; value=bingmapsintegration}}
  isModularPublishing   : True
  id                    : 5fbe0803-a545-4504-b41a-d9d158112360

 .Example
  Get-AppSourceProduct -authContext $authcontext -productName 'BingMaps.*' -silent
  
  resourceType          : AzureDynamics365BusinessCentral
  name                  : BingMaps.AppSource
  externalIDs           : {@{type=AzureOfferId; value=bingmapsintegration}}
  isModularPublishing   : True
  id                    : 5fbe0803-a545-4504-b41a-d9d158112360

 .Example
  $product = Get-AppSourceProduct -authContext $authcontext -productId $productId -includeFeatureAvailability -silent
  $product.FeatureAvailability[0].marketStates | Where-Object { $_.state -eq "Enabled" }
  
  marketCode state  
  ---------- -----  
  DK         Enabled
  IT         Enabled
  US         Enabled

 .Example
  $product = Get-AppSourceProduct -authContext $authcontext -productId $productId -includepackage -silent
  $product
  $product.packageConfigurations
  
  resourceType          : AzureDynamics365BusinessCentral
  name                  : BingMaps.AppSource
  externalIDs           : {@{type=AzureOfferId; value=bingmapsintegration}}
  isModularPublishing   : True
  id                    : 5fbe0803-a545-4504-b41a-d9d158112360
  PackageConfigurations : {@{resourceType=Dynamics365BusinessCentralPackageConfiguration; packageType=AddOn; packageReferences=System.Object[]; 
                          @odata.etag="0000d552-0000-0800-0000-62eba1680000"; id=2c3eb741-7421-40b7-870b-1caea05f017e; Dynamics365BusinessCentralAddOnExtensionPackage=}}

  resourceType                                    : Dynamics365BusinessCentralPackageConfiguration
  packageType                                     : AddOn
  packageReferences                               : {@{type=Dynamics365BusinessCentralAddOnExtensionPackage; value=7cb9f83f-96a7-4e71-a782-6edcaf6a26e4}}
  @odata.etag                                     : "0000d552-0000-0800-0000-62eba1680000"
  id                                              : 2c3eb741-7421-40b7-870b-1caea05f017e
  Dynamics365BusinessCentralAddOnExtensionPackage : @{resourceType=; fileName=Freddy Kristiansen_BingMaps.AppSource_3.0.163.0.app; state=Processed; 
                                                    @odata.etag="40001820-0000-0800-0000-62eba15f0000"; id=7cb9f83f-96a7-4e71-a782-6edcaf6a26e4}
  
#>
function Get-AppSourceProduct {
     [CmdletBinding(DefaultParameterSetName = 'ProductId')]
     Param(
        [Parameter(Mandatory=$true)]
        [HashTable] $authContext,
        [Parameter(Mandatory=$false, ParameterSetName = 'ProductId')]
        [string] $productId = '',
        [Parameter(Mandatory=$false, ParameterSetName = 'ProductName')]
        [string] $productName = '',
        [switch] $includeSetup,
        [switch] $includeProperty,
        [switch] $includeListing,
        [switch] $includePackage,
        [switch] $includeProductAvailability,
        [switch] $includeFeatureAvailability,
        [switch] $includeListingAsset,
        [switch] $includeListingImage,
        [switch] $includeListingVideo,
        [switch] $includeAll,
        [switch] $silent
    )

$telemetryScope = InitTelemetryScope -name $MyInvocation.InvocationName -parameterValues $PSBoundParameters -includeParameters @()
try {
    $authContext = Renew-BcAuthContext -bcAuthContext $authContext
    if ($productId) {
        $product = Invoke-IngestionApiGet -authContext $authContext -path "/products/$productId" -silent:($silent.IsPresent)
        if (-not $product) {
            throw "Product with ID $productId cannot be found"
        }
        $products = @($product)
    }
    elseif ($productName) {
        $product = Invoke-IngestionApiGetCollection -authContext $authContext -path '/products' -silent:($silent.IsPresent) | Where-Object { $_.Name -like $productName }
        if (-not $product) {
            throw "Product with Name $productName cannot be found"
        }
        $products = @($product)
    }
    else {
        $products = @(Invoke-IngestionApiGetCollection -authContext $authContext -path '/products' -silent:($silent.IsPresent))
    }
    $products | ForEach-Object {
        $product = $_
        #$product | ConvertTo-Json -Depth 99 | Out-Host
        $variantID = ''
        if ($includeSetup -or $includeAll) {
            $product | Add-Member -MemberType NoteProperty -Name 'Setup' -Value (Invoke-IngestionApiGet -authContext $authContext -path "/products/$($product.Id)/setup" -silent:($silent.IsPresent))
        }
        if ($includeFeatureAvailability -or $includeProductAvailability -or $includeAll) {
            $branchesAvailability = @(Invoke-IngestionApiGetCollection -authContext $authContext -path "/products/$($product.Id)/branches/getByModule(module=Availability)" -silent:($silent.IsPresent) | Where-Object { 
                $thisVariantID = ''
                if ($_.PSObject.Properties.name -eq "variantID") { $thisVariantID = $_.variantID }
                $variantID -eq $thisVariantID
            })
            if ($branchesAvailability.Count -ne 1) {
                throw "Unable to find branchesAvailability for product $($product.Id)"
            }
            if ($includeProductAvailability -or $includeAll) {
                $product | Add-Member -MemberType NoteProperty -Name "ProductAvailability" -Value @(Invoke-IngestionApiGetCollection -authContext $authContext -path "/products/$($product.Id)/productavailabilities/getByInstanceID(instanceID=$($branchesAvailability[0].currentDraftInstanceID))" -silent:($silent.IsPresent))
            }
            if ($includeFeatureAvailability -or $includeAll) {
                $product | Add-Member -MemberType NoteProperty -Name "FeatureAvailability" -Value @(Invoke-IngestionApiGetCollection -authContext $authContext -path "/products/$($product.Id)/featureavailabilities/getByInstanceID(instanceID=$($branchesAvailability[0].currentDraftInstanceID))" -query '$expand=MarketStates' -silent:($silent.IsPresent))
            }
        }
        if ($includeProperty -or $includeAll) {
            $branchesProperty = @(Invoke-IngestionApiGetCollection -authContext $authContext -path "/products/$($product.Id)/branches/getByModule(module=Property)" -silent:($silent.IsPresent) | Where-Object { 
                $thisVariantID = ''
                if ($_.PSObject.Properties.name -eq "variantID") { $thisVariantID = $_.variantID }
                $variantID -eq $thisVariantID
            })
            if ($branchesProperty.Count -ne 1) {
                throw "Unable to find branchesProperty for product $($product.Id)"
            }
            $product | Add-Member -MemberType NoteProperty -Name "Property" -Value @(Invoke-IngestionApiGetCollection -authContext $authContext -path "/products/$($product.Id)/properties/getByInstanceID(instanceID=$($branchesProperty[0].currentDraftInstanceID))" -silent:($silent.IsPresent))
        }
        if ($includeListing -or $includeAll) {
            $branchesListing = @(Invoke-IngestionApiGetCollection -authContext $authContext -path "/products/$($product.Id)/branches/getByModule(module=Listing)" -silent:($silent.IsPresent) | Where-Object { 
                $thisVariantID = ''
                if ($_.PSObject.Properties.name -eq "variantID") { $thisVariantID = $_.variantID }
                $variantID -eq $thisVariantID
            })
            if ($branchesListing.Count -ne 1) {
                throw "Unable to find branchesListing for product $($product.Id)"
            }
            $product | Add-Member -MemberType NoteProperty -Name "Listing" -Value @(Invoke-IngestionApiGetCollection -authContext $authContext -path "/products/$($product.Id)/listings/getByInstanceID(instanceID=$($branchesListing[0].currentDraftInstanceID))" -silent:($silent.IsPresent))
            $product.Listing | ForEach-Object {
                $listing = $_
                if ($includeListingAsset -or $includeAll) {
                    $listing | Add-Member -MemberType NoteProperty -Name "Asset" -Value @(Invoke-IngestionApiGetCollection -authContext $authContext -path "/products/$($product.Id)/listings/$($listing.id)/assets" -query '$expand=FileSasUri' -silent:($silent.IsPresent))
                }
                if ($includeListingImage -or $includeAll) {
                    $listing | Add-Member -MemberType NoteProperty -Name "Image" -Value @(Invoke-IngestionApiGetCollection -authContext $authContext -path "/products/$($product.Id)/listings/$($listing.id)/images" -query '$expand=FileSasUri' -silent:($silent.IsPresent))
                }
                if ($includeListingVideo -or $includeAll) {
                    $listing | Add-Member -MemberType NoteProperty -Name "Video" -Value @(Invoke-IngestionApiGetCollection -authContext $authContext -path "/products/$($product.Id)/listings/$($listing.id)/videos" -query '$expand=FileSasUri' -silent:($silent.IsPresent))
                }
            }
        }
        if ($includePackage -or $includeAll) {
            $variantID = ''
            $branchesPackage = @(Invoke-IngestionApiGetCollection -authContext $authContext -path "/products/$($product.Id)/branches/getByModule(module=Package)" -silent:($silent.IsPresent) | Where-Object { 
                $thisVariantID = ''
                if ($_.PSObject.Properties.name -eq "variantID") { $thisVariantID = $_.variantID }
                $variantID -eq $thisVariantID
            })
            $branchesPackage | ForEach-Object {
                $packageConfigurations = @(Invoke-IngestionApiGetCollection -authContext $authContext -path "/products/$($product.Id)/packageconfigurations/getByInstanceID(instanceID=$($_.currentDraftInstanceID))" -silent:($silent.IsPresent))
                $packageConfigurations | ForEach-Object {
                    $addOnExtensionPackageId = $_.packageReferences | Where-Object { $_.type -eq 'Dynamics365BusinessCentralAddOnExtensionPackage' } | ForEach-Object { $_.Value }
                    if ($addOnExtensionPackageId) {
                        $_ | Add-Member -MemberType NoteProperty -Name 'Dynamics365BusinessCentralAddOnExtensionPackage' -value (Invoke-IngestionApiGet -authContext $authContext -path "/products/$($product.Id)/packages/$addOnExtensionPackageId" -silent:($silent.IsPresent))
                    }
                    $addOnLibraryExtensionPackageId = $_.packageReferences | Where-Object { $_.type -eq 'Dynamics365BusinessCentralAddOnLibraryExtensionPackage' } | ForEach-Object { $_.Value }
                    if ($addOnLibraryExtensionPackageId) {
                        $_ | Add-Member -MemberType NoteProperty -Name 'Dynamics365BusinessCentralAddOnLibraryExtensionPackage' -value (Invoke-IngestionApiGet -authContext $authContext -path "/products/$($product.Id)/packages/$addOnLibraryExtensionPackageId" -silent:($silent.IsPresent))
                    }
                }
                $product | Add-Member -MemberType NoteProperty -Name 'PackageConfigurations' -Value $packageConfigurations
            }
        }
        $product
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
Export-ModuleMember -Function Get-AppSourceProduct
# SIG # Begin signature block
# MIInbgYJKoZIhvcNAQcCoIInXzCCJ1sCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAqJi4iWqhcp3o/
# yXRMG4VCmZclornTWD3E6fdYN0FuMqCCDMkwggYEMIID7KADAgECAhMzAAACHPrN
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
# hvcNAQkEMSIEIAHhOS2oeFqXdNPc9zsIVqWrT/8sku6fv4yEyj9jDRfOMEIGCisG
# AQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEAJVJ1NKJP20h3hEaejU1z
# jkns1zLDSx+JN+OCwfiJY1VPPhY/BUoLW5ispvbc4VtlOXicdEJB6mgz3jeY06Qb
# w75PV0kWhLItQLp/XUALs2ip6wYKbeu8wgTDsw0o8UpWAeaqg6FhwziiD9fqJW7L
# wKb0+QptRkuVzUJrpe5AMzOp6/wUER4wKiz5lK2ghAC4rGVwK80TSAz5pyQkSqhz
# uxaH+2Y0lBvOA+ccG1cA8B2VIgLZ860dXUJRmtxFvl8oJ5TRSf5JmYhDjBsSxPVQ
# /Ekwp/97JVdNPhc5VW8GO26SpoBcDnCvdxsAiUt2BUtp8mgRyJ4dMZ+OvB5URLL5
# 3aGCF60wghepBgorBgEEAYI3AwMBMYIXmTCCF5UGCSqGSIb3DQEHAqCCF4YwgheC
# AgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFFMIIB
# QQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCDdHRmdCPiGRCTFU8gI
# Ks1EECEQdgMUmjtZnuOqrGf1cgIGaomzDM7zGBMyMDI2MDgyNzA2Mjk0My43OTRa
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
# BDAvBgkqhkiG9w0BCQQxIgQgRkD4gQcVig+rTjbHPnCKVqSh8aie/SNgwLxoF8X8
# y24wgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCAwJRSVuD2jmMcQCFXdLuJA
# wDpUVNZ6bc6dfJU83Q2LgDCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBD
# QSAyMDEwAhMzAAACG9CyuAJn93LPAAEAAAIbMCIEILpX2zOE3yRmSrEbYyB6Qah4
# staWGvdg0j8vh4PpXwO4MA0GCSqGSIb3DQEBCwUABIICABGKUwNcdotPu/8GU3kl
# iBtPp+W3/rY2IJSGg6AZouDl/Ly+p/VnK28XVCy4j09Vc8bLjHkUARJAVjuZpzII
# Gog9LlV15FsDQ45tgtKbKmnfQqhPW1IjPX5SOe5ZFo+D1Kv80s89xAxC63HX0+76
# pktEGHsSCIRyHdW+fW9T8S25cTDl8pWiMCOgHlRdhAyeRokE2JfLgw+W4TlN0ZTA
# MNypbvJ6f2yk4K5ogkufJ54uvaKrOheIPVZHPJQfwKesHhjtguZyf2OvnsndaEQH
# jNwSBngucU85UdoMqRP0pvqy73h9uAd2vKMiDmxmV+a1zal8vLu1pjjV593mPEdr
# oQkcDdokP0JDGxSBUp86akTX36UMHMkuvM8Grv/i/kAaNsVr77zy252RqQUPEfEW
# CiHuu6LuhHu56ScPiWi4rvfkMpgnqYNxtMZco1LqMSeUix4oZqyUoV+5Ds/GFbCb
# LH6zKG8mxvBjdfYPB2056vHhgVeGr7qxV62V4r0yeyD/ca0Lo+AXSPVX+T7CpS2T
# yIqDxnJhVwbiDHLOkfgcmbYEQkbBTqlE2R0tLPNNlFqPC6HCffTKWVFTtUF5qIKG
# MAqM6cv+RqaCQ026TwCzV/QmcdCVzj75dLp9B2saHRGNgmo7NsQA6bgC4Wg1n22A
# ubF6bqXCpJyM0QAWcP6zdpe8
# SIG # End signature block
