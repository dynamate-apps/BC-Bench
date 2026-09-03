$eventIds = @{
    "New-BcContainer"                                 = "DO0001"
    "New-BcImage"                                     = "DO0002"
    "Compile-AppInBcContainer"                        = "DO0003"
    "Publish-BcContainerApp"                          = "DO0004"
    "Run-AlCops"                                      = "DO0005"
    "Run-AlValidation"                                = "DO0006"
    "Run-AlPipeline"                                  = "DO0007"
    "Run-TestsInBcContainer"                          = "DO0008"
    "Sign-BcContainerApp"                             = "DO0009"
    "Publish-PerTenantExtensionApps"                  = "DO0010"
    "Install-BcAppFromAppSource"                      = "DO0011"
    "New-BcEnvironment"                               = "DO0012"
    "New-BcDatabaseExport"                            = "DO0013"
    "Remove-BcEnvironment"                            = "DO0014"
    "Download-Artifacts"                              = "DO0015"
    "New-CompanyInNavContainer"                       = "DO0016"
    "Import-TestToolkitToBcContainer"                 = "DO0017"
    "UploadImportAndApply-ConfigPackageInBcContainer" = "DO0018"
    "New-AppSourceSubmission"                         = "DO0019"
    "Promote-AppSourceSubmission"                     = "DO0020"
}

function FormatValue {
    Param(
        $value
    )

    if ($value -eq $null) {
        "[null]"
    }
    elseif ($value -is [switch]) {
        $value.IsPresent
    }
    elseif ($value -is [boolean]) {
        $value
    }
    elseif ($value -is [SecureString]) {
        "[SecureString]"
    }
    elseif ($value -is [PSCredential]) {
        "[PSCredential]"
    }
    elseif ($value -is [string]) {
        if (($value -like "https:*" -or $value -like "http:*") -and ($value.Contains('?'))) {
            "$($value.Split('?')[0])?[parameters]"
        }
        else {
            "$value"
        }
    }
    elseif ($value -is [System.Collections.IDictionary]) {
        $arr = @($value.GetEnumerator() | ForEach-Object { $_ })
        $str = "{"
        $arr | ForEach-Object {
            if ($_.Key -eq "RefreshToken" -or $_.Key -eq "AccessToken") {
                if ($_.Value) {
                    $str += "`n  $($_.Key): [token]"
                }
                else {
                    $str += "`n  $($_.Key): [null]"
                }
            }
            else {
                $str += "`n  $($_.Key): $(FormatValue -value $_.Value)"
            }
        }
        "$str`n}"
    }
    elseif ($value -is [System.Collections.IEnumerable]) {
        $arr = @($value.GetEnumerator() | ForEach-Object { $_ })
        if ($arr.Count -gt 1) { $str = "[" } else { $str = "" }
        $arr | ForEach-Object {
            if ($arr.Count -gt 1) { $str += "`n  " }
            $str += "$(FormatValue -value $_)"
        }
        if ($arr.Count -gt 1) { "$str`n]" } else { $str }
    }
    else {
        $value
    }
}

function AddTelemetryProperty {
    Param(
        $telemetryScope,
        $key,
        $value
    )

    if ($telemetryScope) {
        $value = FormatValue -value $value
        if ($telemetry.Debug) {
            Write-Host -ForegroundColor Yellow "Telemetry scope $($telemetryScope.Name), add property $key = '$value', type = $($value.GetType())"
        }
        if ($telemetryScope.properties.ContainsKey($Key)) {
            $telemetryScope.properties."$key" += "`n$value"
        }
        else {
            $telemetryScope.properties.Add($key, $value)
        }
    }
}

function InitTelemetryClients {
    Param()

    "Microsoft","Partner" | ForEach-Object {
        $clientName = "$($_)Client"
        $telemetryConnectionString = $bcContainerHelperConfig."$($_)TelemetryConnectionString"
        if ($telemetryConnectionString -and $telemetry.Assembly -ne $null) {
            if ($telemetry."$clientName" -eq $null -or $telemetry."$ClientName".TelemetryConfiguration.ConnectionString -ne $telemetryConnectionString) {
                try {
                    $telemetryConfiguration = $telemetry.Assembly.CreateInstance('Microsoft.ApplicationInsights.Extensibility.TelemetryConfiguration')
                    $telemetryConfiguration.Connectionstring = $telemetryConnectionString
                    $telemetry."$clientName" = $telemetry.Assembly.CreateInstance('Microsoft.ApplicationInsights.TelemetryClient', $false, 0, $null, $telemetryConfiguration, $null, $null)
                }
                catch {
                    $telemetry."$clientName" = $null
                }
            }
        }
        else {
            $telemetry."$clientName" = $null
        }
    }
}

function RegisterTelemetryScope {
    Param(
        [string] $telemetryScopeJson
    )

    InitTelemetryClients

    $telemetryScope = $telemetryScopeJson | ConvertFrom-Json
    if ($telemetry.TopId -eq "") { 
        $telemetry.TopId = $telemetryScope.CorrelationId
    }

    $scope = @{
        "Name" = $telemetryScope.Name
        "EventId" = $telemetryScope.eventId
        "StartTime" = $telemetryScope.StartTime
        "Properties" = [Collections.Generic.Dictionary[string, string]]::new()
        "Parameters" = [Collections.Generic.Dictionary[string, string]]::new()
        "AllParameters" = [Collections.Generic.Dictionary[string, string]]::new()
        "CorrelationId" = $telemetryScope.CorrelationId
        "ParentId" = $telemetryScope.CorrelationId
        "TopId" = $telemetry.TopId
        "Emitted" = $telemetryScope.Emitted
    }

    "Properties","Parameters","AllParameters" | ForEach-Object {
        $prop = $_
        $telemetryScope."$prop".PSObject.Properties.GetEnumerator() | ForEach-Object { $scope."$prop".Add($_.Name, $_.Value) }
    }

    $telemetry.CorrelationId = $telemetryScope.CorrelationId
    $scope
}

function InitTelemetryScope {
    Param(
        [string] $name,
        [string[]] $includeParameters = @(),
        $parameterValues = $null,
        [string] $eventId = ""
    )
    
    InitTelemetryClients

    if ($telemetry.MicrosoftClient -ne $null -or $telemetry.PartnerClient -ne $null) {
        if ($eventId -eq "" -and ($eventIds.ContainsKey($name))) {
            $eventId = $eventIds[$name]
        }
        if (($eventId -ne "") -or ($telemetry.CorrelationId -eq "")) {
            $CorrelationId = [GUID]::NewGuid().ToString()
            Start-Transcript -Path (Join-Path ([System.IO.Path]::GetTempPath()) $CorrelationId) | Out-Null
            if ($telemetry.Debug) {
                Write-Host -ForegroundColor Yellow "Init telemetry scope $name"
            }
            if ($telemetry.TopId -eq "") { 
                $telemetry.TopId = $CorrelationId
            }
            $scope = @{
                "Name" = $name
                "EventId" = $eventId
                "StartTime" = [DateTime]::Now
                "Properties" = [Collections.Generic.Dictionary[string, string]]::new()
                "Parameters" = [Collections.Generic.Dictionary[string, string]]::new()
                "AllParameters" = [Collections.Generic.Dictionary[string, string]]::new()
                "CorrelationId" = $CorrelationId
                "ParentId" = $telemetry.CorrelationId
                "TopId" = $telemetry.TopId
                "Emitted" = $false
            }
            $telemetry.CorrelationId = $CorrelationId
            if ($includeParameters) {
                $parameterValues.GetEnumerator() | ForEach-Object {
                    $includeParameter = $false
                    $key = $_.key
                    $value = FormatValue -value $_.value
                    $scope.allParameters.Add($key, $value)
                    $includeParameters | ForEach-Object { if ($key -like $_) { $includeParameter = $true } }
                    if ($includeParameter) {
                        $scope.parameters.Add($key, $value)
                    }
                }
            }
            AddTelemetryProperty -telemetryScope $scope -key "eventId" -value $eventId
            AddTelemetryProperty -telemetryScope $scope -key "bcContainerHelperVersion" -value $BcContainerHelperVersion
            AddTelemetryProperty -telemetryScope $scope -key "isAdministrator" -value $isAdministrator
            AddTelemetryProperty -telemetryScope $scope -key "stackTrace" -value (Get-PSCallStack | % { "$($_.Command) at $($_.Location)" }) -join "`n"
            $scope
        }
    }
}

function TrackTrace {
    Param(
        $telemetryScope
    )

    if ($telemetryScope -and !$telemetryScope.Emitted) {
        if ($telemetryScope.CorrelationId -eq $telemetry.CorrelationId) {
            if ($telemetry.Debug) {
                Write-Host -ForegroundColor Yellow "Emit telemetry trace, scope $($telemetryScope.Name)"
            }
            $telemetry.CorrelationId = $telemetryScope.ParentId
            if ($telemetry.CorrelationId -eq "") {
                $telemetry.TopId = ""
            }
            $telemetryScope.Emitted = $true
            try {
                Stop-Transcript | Out-Null
                $transcript = (@(Get-Content -Path (Join-Path ([System.IO.Path]::GetTempPath()) $telemetryScope.CorrelationId)) | select -skip 18 | select -skiplast 4 | Where-Object { -not "$_".StartsWith("::add-mask::") }) -join "`n"
                if ($transcript.Length -gt 32000) {
                    $transcript = "$($transcript.SubString(0,16000))`n`n...`n`n$($transcript.SubString($transcript.Length-16000))"
                }
                Remove-Item -Path (Join-Path ([System.IO.Path]::GetTempPath()) $telemetryScope.CorrelationId)
            }
            catch {
                $transcript = ""
            }
            $telemetryScope.Properties.Add("duration", [DateTime]::Now.Subtract($telemetryScope.StartTime).TotalSeconds)

            if ($telemetry.Assembly -ne $null) {
                try {
                    $printCorrelationId = $telemetry.Debug
                    "Microsoft","Partner" | ForEach-Object {
                        $clientName = "$($_)Client"
                        $extendedTelemetry = $bcContainerHelperConfig.SendExtendedTelemetryToMicrosoft -or $_ -eq "Partner"
                        if ($telemetry."$clientName") {
                            $traceTelemetry = $telemetry.Assembly.CreateInstance('Microsoft.ApplicationInsights.DataContracts.TraceTelemetry')
                            if ($extendedTelemetry) {
                                $traceTelemetry.Message = "$($telemetryScope.Name)`n$transcript"
                                $traceTelemetry.SeverityLevel = 0
                                $telemetryScope.allParameters.GetEnumerator() | ForEach-Object { 
                                    [void]$traceTelemetry.Properties.TryAdd("parameter[$($_.Key)]", $_.Value)
                                }
                            }
                            else {
                                $traceTelemetry.Message = "$($telemetryScope.Name)"
                                $traceTelemetry.SeverityLevel = 1
                                $telemetryScope.Parameters.GetEnumerator() | ForEach-Object { 
                                    [void]$traceTelemetry.Properties.TryAdd("parameter[$($_.Key)]", $_.Value)
                                }
                            }
                            $telemetryScope.Properties.GetEnumerator() | ForEach-Object { 
                                [void]$traceTelemetry.Properties.TryAdd($_.Key, $_.Value)
                            }
                            $traceTelemetry.Context.Operation.Name = $telemetryScope.Name
                            $traceTelemetry.Context.Operation.Id = $telemetryScope.CorrelationId
                            $traceTelemetry.Context.Operation.ParentId = $telemetryScope.ParentId
                            $telemetry."$clientName".TrackTrace($traceTelemetry)
                            $telemetry."$clientName".Flush()
                            if ($extendedTelemetry) { $printCorrelationId = $true }
                            if ($telemetry.Debug) { 
                                Write-Host "$_ telemetry emitted"
                            }
                        }
                    }
                    if ($printCorrelationId) {
                        Write-Host "$($telemetryScope.Name) Telemetry Correlation Id: $($telemetryScope.CorrelationId)"
                    }
                }
                catch {
                    Write-Host -ForegroundColor Red "Error emitting telemetry."
                    Write-Host -ForegroundColor Red "This might be caused by and old version of dotnet, you need at least dotnet 6.0."
                    Write-Host -ForegroundColor Red "Please upgrade dotnet here: https://dotnet.microsoft.com/en-us/download/dotnet/6.0"
                }
            }
        }
    }
}

function TrackException {
    Param(
        $telemetryScope,
        $errorRecord
    )

    TrackException -telemetryScope $telemetryScope -exception $errorRecord.Exception -scriptStackTrace $errorRecord.scriptStackTrace
}

function TrackException {
    Param(
        $telemetryScope,
        $exception,
        $scriptStackTrace = $null
    )

    if ($telemetryScope -and !$telemetryScope.Emitted) {
        if ($telemetryScope.CorrelationId -eq $telemetry.CorrelationId) {
            if ($telemetry.Debug) {
                Write-Host -ForegroundColor Yellow "Emit telemetry exception, scope $($telemetryScope.Name)"
            }
            $telemetry.CorrelationId = $telemetryScope.ParentId
            if ($telemetry.CorrelationId -eq "") {
                $telemetry.TopId = ""
            }
            $telemetryScope.Emitted = $true

            try {
                Stop-Transcript | Out-Null
                $transcript = (@(Get-Content -Path (Join-Path ([System.IO.Path]::GetTempPath()) $telemetryScope.CorrelationId)) | select -skip 18 | select -skiplast 4 | Where-Object { -not "$_".StartsWith("::add-mask::") }) -join "`n"
                if ($transcript.Length -gt 32000) {
                    $transcript = "$($transcript.SubString(0,16000))`n`n...`n`n$($transcript.SubString($transcript.Length-16000))"
                }
                Remove-Item -Path (Join-Path ([System.IO.Path]::GetTempPath()) $telemetryScope.CorrelationId)
            }
            catch {
                $transcript = ""
            }
            $telemetryScope.Properties.Add("duration", [DateTime]::Now.Subtract($telemetryScope.StartTime).TotalSeconds)
            if ($scriptStackTrace) {
                $telemetryScope.Properties.Add("errorStackTrace", $scriptStackTrace)
            }
            if ($exception) {
                $telemetryScope.Properties.Add("errorMessage", $exception.Message)
            }

            if ($telemetry.Assembly -ne $null) {
                try {
                    "Microsoft","Partner" | ForEach-Object {
                        $clientName = "$($_)Client"
                        $extendedTelemetry = $bcContainerHelperConfig.SendExtendedTelemetryToMicrosoft -or $_ -eq "Partner"
                        if ($telemetry."$clientName") {
                            $traceTelemetry = $telemetry.Assembly.CreateInstance('Microsoft.ApplicationInsights.DataContracts.TraceTelemetry')
                            if ($extendedTelemetry) {
                                $traceTelemetry.Message = "$($telemetryScope.Name)`n$transcript"
                                $traceTelemetry.SeverityLevel = 0
                                $telemetryScope.allParameters.GetEnumerator() | ForEach-Object { 
                                    [void]$traceTelemetry.Properties.TryAdd("parameter[$($_.Key)]", $_.Value)
                                }
                            }
                            else {
                                $traceTelemetry.Message = "$($telemetryScope.Name)"
                                $traceTelemetry.SeverityLevel = 1
                                $telemetryScope.Parameters.GetEnumerator() | ForEach-Object { 
                                    [void]$traceTelemetry.Properties.TryAdd("parameter[$($_.Key)]", $_.Value)
                                }
                            }
                            $telemetryScope.Properties.GetEnumerator() | ForEach-Object { 
                                [void]$traceTelemetry.Properties.TryAdd($_.Key, $_.Value)
                            }
                            $traceTelemetry.Context.Operation.Name = $telemetryScope.Name
                            $traceTelemetry.Context.Operation.Id = $telemetryScope.CorrelationId
                            $traceTelemetry.Context.Operation.ParentId = $telemetryScope.ParentId
                            $telemetry."$clientName".TrackTrace($traceTelemetry)
                        
                            # emit exception telemetry
                            $exceptionTelemetry = $telemetry.Assembly.CreateInstance('Microsoft.ApplicationInsights.DataContracts.ExceptionTelemetry')
                            if ($extendedTelemetry) {
                                $exceptionTelemetry.Message = "$($telemetryScope.Name)`n$transcript"
                                $exceptionTelemetry.SeverityLevel = 3
                                $telemetryScope.allParameters.GetEnumerator() | ForEach-Object { 
                                    [void]$exceptionTelemetry.Properties.TryAdd("parameter[$($_.Key)]", $_.Value)
                                }
                            }
                            else {
                                $exceptionTelemetry.Message = "$($telemetryScope.Name)"
                                $exceptionTelemetry.SeverityLevel = 1
                                $telemetryScope.Parameters.GetEnumerator() | ForEach-Object { 
                                    [void]$exceptionTelemetry.Properties.TryAdd("parameter[$($_.Key)]", $_.Value)
                                }
                            }
                            $telemetryScope.Properties.GetEnumerator() | ForEach-Object { 
                                [void]$exceptionTelemetry.Properties.TryAdd($_.Key, $_.Value)
                            }
                            $exceptionTelemetry.Context.Operation.Name = $telemetryScope.Name
                            $exceptionTelemetry.Context.Operation.Id = $telemetryScope.CorrelationId
                            $exceptionTelemetry.Context.Operation.ParentId = $telemetryScope.ParentId
                            $telemetry."$clientName".TrackException($exceptionTelemetry)
                            $telemetry."$clientName".Flush()
                        }
                    }
                    Write-Host "$($telemetryScope.Name) Telemetry Correlation Id: $($telemetryScope.CorrelationId)"
                }
                catch {
                    Write-Host -ForegroundColor Red "Error emitting telemetry."
                    Write-Host -ForegroundColor Red "This might be caused by and old version of dotnet, you need at least dotnet 6.0."
                    Write-Host -ForegroundColor Red "Please upgrade dotnet here: https://dotnet.microsoft.com/en-us/download/dotnet/6.0"
                }
            }
        }
    }
}

# SIG # Begin signature block
# MIInSQYJKoZIhvcNAQcCoIInOjCCJzYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDqmeRfJdU8tpX7
# fAV4/qtHO7dCG2MF/n85/yEPWX8jLaCCDLowggX1MIID3aADAgECAhMzAAACHU0Z
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
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIN80Bq3b
# n2LvR1GWduHeY3aCKmPmjB2XK/Yh6GSPte9oMEIGCisGAQQBgjcCAQwxNDAyoBSA
# EgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20w
# DQYJKoZIhvcNAQEBBQAEggEAhPIYh55YVvgpYmNpyvdfW7uB/yf477KrWwGyrefy
# DAYTCgXjNUAU1wqWmSTNFVU2vg24IMKcc2z0XE+sn9N3RD1bjQIdsP+kfPYkjVvN
# n4xoIzfQnqAnxPAZry6ebuhjE3oTvf45I4fsjNXNjKx4Tfy51kNCMKCPUlfaYD7F
# ZyHitgGJmHgeXZ5IKpN3mT7WfoVOhqcq8bhrYhxa5HEen6MKFurbEserBVMbmpmd
# 02+m9p7FPchPuGap4IiHCj8pLj3CF2syk16ppa8auasz0jgQPkhcf32dKwVvS7ZQ
# WPaKoHuagSq2F9am+x+mIEk2CJC4FrAtY7xOM6XVEopxZ6GCF5cwgheTBgorBgEE
# AYI3AwMBMYIXgzCCF38GCSqGSIb3DQEHAqCCF3AwghdsAgEDMQ8wDQYJYIZIAWUD
# BAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGEWQoD
# ATAxMA0GCWCGSAFlAwQCAQUABCDaNC9YEfPpd7mZLQYs2HQr5sGHQ5v8QdtbozVD
# 0QCsaQIGaoWvWCjgGBMyMDI2MDgyNzA2MzAzNy43MDNaMASAAgH0oIHRpIHOMIHL
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxN
# aWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRT
# UyBFU046MzMwMy0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFNlcnZpY2WgghHtMIIHIDCCBQigAwIBAgITMwAAAiEzwDX70g8hpAABAAAC
# ITANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAe
# Fw0yNjAyMTkxOTM5NTRaFw0yNzA1MTcxOTM5NTRaMIHLMQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmlj
# YSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046MzMwMy0wNUUw
# LUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIi
# MA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDbcTACqU1YvRocyWL2PL9fyf/+
# ULs2qK7U1aZsRnDZSnlCr7K7jgA3eFCEJL5BZ7dUTC0DeZepf+ZC+7HEbB4IdzmJ
# fQAUDFFerqY5VTHmQvP2XA3lWSFj740idcGUHglP5H/PbCJU7GAHWP2HdcCjdx1l
# YAo0A+zLI7xwnTQeMyOXX212Eg4UmDPPJgxdTMw6WFVWsBPWRBi5gDixy2s+7R8A
# Dk5lbBBFDB5h0CjrNWIN7uCAzF5g7trrL8nXIKp10mj9RxhcGQ+tlht6VIvdygRV
# TUGdzFB2/nBvJqQ9kxxFltQST70fEdx4TyaKow/f5+BSh4z4/9f7NXIVVTLn/8kc
# JAfRqFmRrrFt3IKby7VrzmYuoQWD0lmNFtGQ57BrJkPrPFAPek1ALtcbb7FH3nQp
# vi8ngz/MFX/+cnmNFWFU29VVLmzB9XvLZxbYvkeett0mh5lfteeN2rEwUyrdrKuf
# z9h2S6pbate+C2h02CrXwSka0x6ezpTmGkIJLFt25ub/UYXNLdHdsxGD6EfckOIo
# JYsm4MS9F/vSqLNHK89I0vTLBngQEp6LIFkINanRT3PtNx3pNKRKJRALc6L6mhW4
# hL4aHL749qPfQ72t5qAMm5xiKYMgJ2WanidRLNuI251JIN7raaeA/2vb0XFkZcIb
# TR1pfQGsco4U0g5tjwIDAQABo4IBSTCCAUUwHQYDVR0OBBYEFOYjIs5qa6pfuquP
# yyK1FTr5QDCnMB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1Ud
# HwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3Js
# L01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggr
# BgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNv
# bS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIw
# MTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgw
# DgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUAA4ICAQA4I/3bkdnTxD2rFum3
# MF8xVKdEkohAObbePrQ+0fr5bRimjz9sVkKT/7gcj4OMcClSYG+IdX6Mp3EYsLHW
# fjvwfzFoeZE+yTbdBj/1VHZQRuCmw6QqeVCTbw2nnS7nBxnWd9oZXbPUpqEawH5D
# qXQaWFgR9A4KWVK/IvXVDMj1PlPCES1P3JonNbdhkkkz49rJuKOm5b7e/BH8loqA
# mXOXRc22yxWVTMWrEp4pslmv8eT7VoY8X/jdKYTPVEXsfmLbVFcqzMuB8vFGfUyW
# sWROS8wgq7lQYfWcYqh7NymoATX+wWYK3zWG7aRciPGUAzznXdf+aHtIWnQLNa5H
# FmSXkiak3fSuprWYZiHhuYjE16hroApcBHpm+8S/kNqhm9WjQX+2BxnYv+Jejy6l
# qTi8fLBLS069WXVw/ptf5IV+FtYl34GvVoeg31UoUmVVZe1SDUJkm9dDXc8l/qBD
# YiAIT2CCsPTyt9XA9JVuHxdP63n7ChvWAO/47QRuCDsUlFJoWwyBwl7jeYpaRVMt
# Qt0iuJMGGjgEaJX1Q/2j8sXURvTceLHDD9ipWt092ZDWMQciDRmhHNFOX1dnjBvk
# /k1UMcg997j5oYznAnSpJvlg/4BP3aVE0h/YH2KgsKbU4NXZHAjJXj2Slqo1C115
# CG6qBZaFkM8W6vPZCm5qnSezOjCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkA
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
# T3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjMzMDMtMDVFMC1E
# OTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEw
# BwYFKw4DAhoDFQALbEgZZnyYHXJ1DGb5fGjplXptuaCBgzCBgKR+MHwxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29m
# dCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBCwUAAgUA7joP5TAiGA8y
# MDI2MDgyNzAxMjI0NVoYDzIwMjYwODI4MDEyMjQ1WjB3MD0GCisGAQQBhFkKBAEx
# LzAtMAoCBQDuOg/lAgEAMAoCAQACAh2jAgH/MAcCAQACAhMoMAoCBQDuO2FlAgEA
# MDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAI
# AgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBAE4gU+/k2bmPh0bglHshDI5com2z
# CZNCQq/AQpj/SVSt6bjKRzQ1gIplHncHzX+tMrDsPRo9gxDcRtYu8cCvBggqyT8e
# MIZlJ+ctqmNnEHsWle5NZ4wUMSFDBaQONUPAbhzWXb5G2X4UjhgYOWBwBJzRFJZI
# cJoKUFQuBt9AIkpLDRdeKdnBQfNzhHF9FQV6xtmBfcWd1oPc3tcOl5JCPcIYJzx1
# VtOpc9PQTUz5aNj2JvjIz8R9ZdzMVos1T/iA+y7ClTbXgENNgoHdPJh5TXqWm0m8
# UuTGiBksC16QbemHyqDkfj6EXqub03vLSZbsD1yl+k//ZHy/0YFeAO7cfQAxggQN
# MIIECQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQ
# MA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
# MSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAiEz
# wDX70g8hpAABAAACITANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0G
# CyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCAEt9ESutN2LJscCq208YbgdK8r
# f1mawbYwLjlpUSEEUjCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EIADvIQef
# FVUa4BJy8IZywMAvmGSKdUVqEmy9A++PCj1EMIGYMIGApH4wfDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgUENBIDIwMTACEzMAAAIhM8A1+9IPIaQAAQAAAiEwIgQgm8nw9j3q
# XjYmLOPid7coFoyn0arM9jVcaXkS4q5zrXAwDQYJKoZIhvcNAQELBQAEggIADDTP
# 5mWb5QSZyClu5mvlvyWAoqC4FMLH+3rvD53BmlvnzDmffpAHu6lPvMHRkRmurcn3
# UvfLSEUX6tpe6sBB+4sqTcwYoQ1HtllxTPIo485I82gmFB+hpn51DVLgT2QEwYbB
# DhkOEHkIVYJdTOkPRWoFHlE0FAswj6m1sH1zeKNZ7uSQ6JnqTdV3MLokEdkpbSCI
# HXgBOL3HGkM41kO360PxFhrbtw5xn1ZG+M0UxyYLFw75uVCwj2GsN18i8BHidrqv
# OOVSEiTKKayXLUbl2rPomNm2bfofJqfaAK3RL78Nn+wuuXPSgxcqWeDzNcMGAcWl
# ermKKYgpybK79RJtjkGEqX9CBUlR301qGF7yjqF4lk8vrOfvU1e0LcH7XPO+wqua
# oq/onzhrRlrZmtaPB5O8h5ZlR1wgTQxLP9YQdkpm6oNgMq4wIZuGmNDWg98ynoqc
# rAUZRPIwzVcqWoNKo83yWmMlDIiIW91GYdB8ohVnrxQ2vyDq2vvX9LR7rDun39HO
# Yxj5X73q44Y95MN3qaNeBkxDbPSKQXycDnZtOd4qCZxgaxjbcnHo2wYIMO9DxHfJ
# /ZQZlIigORW1qv1wvU4hnx+zJQKw97I4phpYPXNBM0wgra0++r9sqHZV/WzqRT90
# aFaHH/+2D4w7RH3WSTEI7VeJdHXH+v6pYdYFzKs=
# SIG # End signature block
