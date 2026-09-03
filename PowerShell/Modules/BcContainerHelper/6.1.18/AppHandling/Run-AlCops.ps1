<#
 .Synopsis
  Run AL Cops
 .Description
  Run AL Cops
 .Parameter containerName
  Name of the validation container. Default is bcserver.
 .Parameter credential
  These are the credentials used for the container. If not provided, the Run-AlValidation function will generate a random password and use that.
 .Parameter previousApps
  Array or comma separated list of previous version of apps to use for AppSourceCop validation and upgrade test
 .Parameter apps
  Array or comma separated list of apps to validate
 .Parameter affixes
  Array or comma separated list of affixes to use for AppSourceCop validation
 .Parameter supportedCountries
  Array or comma separated list of supportedCountries to use for AppSourceCop validation
 .Parameter obsoleteTagMinAllowedMajorMinor
  Objects that are pending obsoletion with an obsolete tag version lower than the minimum set in the AppSourceCop.json file are not allowed. (AS0105)
 .Parameter appPackagesFolder
  Folder in which symbols and apps will be cached. The folder must be shared with the container.
 .Parameter enableAppSourceCop
  Include this switch to enable AppSource Cop
 .Parameter enableCodeCop
  Include this switch to enable Code Cop
 .Parameter enableUICop
  Include this switch to enable UI Cop
 .Parameter enablePerTenantExtensionCop
  Include this switch to enable Per Tenant Extension Cop
 .Parameter failOnError
  Include this switch if you want to fail on the first error instead of returning all errors to the caller
 .Parameter ignoreWarnings
  Include this switch if you want to ignore Warnings
 .Parameter doNotIgnoreInfos
  Include this switch if you don't want to ignore Infos
 .Parameter rulesetFile
  Filename of the ruleset file for Compile-AppInBcContainer
 .Parameter skipVerification
  Include this parameter to skip verification of code signing certificate. Note that you cannot request Microsoft to set this parameter when validating for AppSource.
 .Parameter reportSuppressedDiagnostics
  Set reportSuppressedDiagnostics flag on ALC when compiling to ignore pragma warning disables
 .Parameter CompileAppInBcContainer
  Override function parameter for Compile-AppInBcContainer
#>
function Run-AlCops {
    Param(
        $containerName = $bcContainerHelperConfig.defaultContainerName,
        [PSCredential] $credential,
        $previousApps,
        $apps,
        $affixes,
        $supportedCountries,
        [string] $obsoleteTagMinAllowedMajorMinor = "",
        $appPackagesFolder = (Join-Path $bcContainerHelperConfig.hostHelperFolder ([Guid]::NewGuid().ToString())),
        [switch] $enableAppSourceCop,
        [switch] $enableCodeCop,
        [switch] $enableUICop,
        [switch] $enablePerTenantExtensionCop,
        [switch] $failOnError,
        [switch] $ignoreWarnings,
        [switch] $doNotIgnoreInfos,
        [switch] $reportsuppresseddiagnostics = $true,
        [switch] $skipVerification,
        [string] $rulesetFile = "",
        [scriptblock] $CompileAppInBcContainer
    )

    $telemetryScope = InitTelemetryScope -name $MyInvocation.InvocationName -parameterValues $PSBoundParameters -includeParameters @()
    try {

        if ($previousApps -is [String]) { $previousApps = @($previousApps.Split(',').Trim() | Where-Object { $_ }) }
        if ($apps -is [String]) { $apps = @($apps.Split(',').Trim()  | Where-Object { $_ }) }
        if ($affixes -is [String]) { $affixes = @($affixes.Split(',').Trim() | Where-Object { $_ }) }
        if ($supportedCountries -is [String]) { $supportedCountries = @($supportedCountries.Split(',').Trim() | Where-Object { $_ }) }
        $supportedCountries = $supportedCountries | Where-Object { $_ } | ForEach-Object { getCountryCode -countryCode $_ }

        if ($CompileAppInBcContainer) {
            Write-Host -ForegroundColor Yellow "CompileAppInBcContainer override"; Write-Host $CompileAppInBcContainer.ToString()
        }
        else {
            $CompileAppInBcContainer = { Param([Hashtable]$parameters) Compile-AppInBcContainer @parameters }
        }

        if ($enableAppSourceCop -and $enablePerTenantExtensionCop) {
            throw "You cannot run AppSourceCop and PerTenantExtensionCop at the same time"
        }

        $appsFolder = Join-Path $bcContainerHelperConfig.hostHelperFolder ([Guid]::NewGuid().ToString())
        New-Item -Path $appsFolder -ItemType Directory | Out-Null
        $apps = Sort-AppFilesByDependencies -containerName $containerName -appFiles @(CopyAppFilesToFolder -appFiles $apps -folder $appsFolder) -WarningAction SilentlyContinue

        $appPackFolderCreated = $false
        if (!(Test-Path $appPackagesFolder)) {
            New-Item -Path $appPackagesFolder -ItemType Directory | Out-Null
            $appPackFolderCreated = $true
        }

        $previousAppVersions = @{}
        if ($enableAppSourceCop -and $previousApps) {
            Write-Host "Copying previous apps to packages folder"
            $appList = CopyAppFilesToFolder -appFiles $previousApps -folder $appPackagesFolder
            $previousApps = Sort-AppFilesByDependencies -containerName $containerName -appFiles $appList -WarningAction SilentlyContinue
            $previousApps | ForEach-Object {
                $appFile = $_
                $tmpFolder = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
                try {
                    Extract-AppFileToFolder -appFilename $appFile -appFolder $tmpFolder -generateAppJson
                    $xappJsonFile = Join-Path $tmpFolder "app.json"
                    $xappJson = [System.IO.File]::ReadAllLines($xappJsonFile) | ConvertFrom-Json
                    Write-Host "$($xappJson.Publisher)_$($xappJson.Name) = $($xappJson.Version)"
                    $previousAppVersions += @{ "$($xappJson.Publisher)_$($xappJson.Name)" = $xappJson.Version }
                }
                catch {
                    throw "Cannot use previous app $([System.IO.Path]::GetFileName($appFile)), it might be a runtime package."
                }
                finally {
                    if (Test-Path $tmpFolder) {
                        Remove-Item $tmpFolder -Recurse -Force
                    }
                }
            }
        }

        $artifactUrl = Get-BcContainerArtifactUrl -containerName $containerName
        $artifactVersion = [System.Version]$artifactUrl.Split('/')[4]
        $latestSupportedRuntimeVersion = ''
        try {
            $latestSupportedRuntimeVersion = RunAlTool -usePrereleaseAlTool -arguments @('GetLatestSupportedRuntimeVersion',"$($artifactVersion.Major).$($artifactVersion.Minor)")
            Write-Host "Latest Supported Runtime Version: $latestSupportedRuntimeVersion"
        }
        catch {
            Write-Host -ForegroundColor Yellow "Cannot determine latest supported runtime version, will skip runtime version compatibility check"
        }

        $global:_validationResult = @()
        $apps | ForEach-Object {
            $appFile = $_
            $appFileName = [System.IO.Path]::GetFileName($appFile)

            $tmpFolder = Join-Path $bcContainerHelperConfig.hostHelperFolder ([Guid]::NewGuid().ToString())
            try {
                $length = $global:_validationResult.Length
                if (!$skipVerification) {
                    Copy-Item -path $appFile -Destination "$tmpFolder.app"
                    $signResult = Invoke-ScriptInBcContainer -containerName $containerName -scriptBlock { Param($appTmpFile)
                        if (!(Test-Path "C:\Windows\System32\vcruntime140_1.dll")) {
                            Write-Host "Downloading vcredist_x64 (version 140)"
                            (New-Object System.Net.WebClient).DownloadFile('https://aka.ms/vs/17/release/vc_redist.x64.exe', 'c:\run\install\vcredist_x64-140.exe')
                            Write-Host "Installing vcredist_x64 (version 140)"
                            start-process -Wait -FilePath c:\run\install\vcredist_x64-140.exe -ArgumentList /q, /norestart
                        }
                        Get-AuthenticodeSignature -FilePath $appTmpFile
                    } -argumentList (Get-BcContainerPath -containerName $containerName -path "$tmpFolder.app")
                    Remove-Item "$tmpFolder.app" -Force

                    if ($signResult.Status.Value -eq "valid") {
                        Write-Host -ForegroundColor Green "$appFileName is Signed with $($signResult.SignatureType.Value) certificate: $($signResult.SignerCertificate.Subject)"
                    }
                    else {
                        Write-Host -ForegroundColor Red "$appFileName is not signed, result is $($signResult.Status.Value)"
                        $global:_validationResult += @("$appFileName is not signed, result is $($signResult.Status.Value)")
                    }
                }

                Extract-AppFileToFolder -appFilename $appFile -appFolder $tmpFolder -generateAppJson -latestSupportedRuntimeVersion $latestSupportedRuntimeVersion
                $appJson = [System.IO.File]::ReadAllLines((Join-Path $tmpFolder "app.json")) | ConvertFrom-Json

                $ruleset = $null

                if ("$rulesetFile" -ne "" -or $enableAppSourceCop) {
                    $ruleset = [ordered]@{
                        "name"             = "Run-AlCops RuleSet"
                        "description"      = "Generated by Run-AlCops"
                        "includedRuleSets" = @()
                    }
                }

                if ($rulesetFile) {
                    $customRulesetFile = Join-Path $tmpFolder "custom.ruleset.json"
                    Copy-Item -Path $rulesetFile -Destination $customRulesetFile
                    $ruleset.includedRuleSets += @(@{
                            "action" = "Default"
                            "path"   = Get-BcContainerPath -containerName $containerName -path $customRulesetFile
                        })
                }

                if ($enableAppSourceCop) {
                    Write-Host "Analyzing: $appFileName"
                    Write-Host "Using affixes: $([string]::Join(',',$affixes))"
                    $appSourceCopJson = @{
                        "mandatoryAffixes" = @($affixes)
                    }
                    if ($obsoleteTagMinAllowedMajorMinor) {
                        $appSourceCopJson += @{
                            "ObsoleteTagMinAllowedMajorMinor" = $obsoleteTagMinAllowedMajorMinor
                        }
                    }
                    if ($supportedCountries) {
                        Write-Host "Using supportedCountries: $([string]::Join(',',$supportedCountries))"
                        $appSourceCopJson += @{
                            "supportedCountries" = @($supportedCountries)
                        }
                    }
                    if ($previousAppVersions.ContainsKey("$($appJson.Publisher)_$($appJson.Name)")) {
                        $previousVersion = $previousAppVersions."$($appJson.Publisher)_$($appJson.Name)"
                        if ($previousVersion -ne $appJson.Version) {
                            $appSourceCopJson += @{
                                "Publisher" = $appJson.Publisher
                                "Name"      = $appJson.Name
                                "Version"   = $previousVersion
                            }
                            Write-Host "Using previous app: $($appJson.Publisher)_$($appJson.Name)_$previousVersion.app"
                        }
                    }
                    $appSourceCopJson | ConvertTo-Json -Depth 99 | Set-Content (Join-Path $tmpFolder "appSourceCop.json") -Encoding UTF8

                    $appSourceRuleSetName = 'appsource.default.ruleset.json'
                    $appSourceRulesetFile = Join-Path $tmpFolder $appSourceRuleSetName
                    Copy-Item -Path (Join-Path $PSScriptRoot $appSourceRuleSetName) -Destination $appSourceRulesetFile -Force
                    $ruleset.includedRuleSets += @(@{
                            "action" = "Default"
                            "path"   = Get-BcContainerPath -containerName $containerName -path $appSourceRulesetFile
                        })

                    Write-Host "AppSourceCop.json content:"
                    [System.IO.File]::ReadAllLines((Join-Path $tmpFolder "appSourceCop.json")) | Out-Host
                }
                Remove-Item -Path (Join-Path $tmpFolder '*.xml') -Force

                $Parameters = @{
                    "containerName"               = $containerName
                    "credential"                  = $credential
                    "appProjectFolder"            = $tmpFolder
                    "appOutputFolder"             = $tmpFolder
                    "appSymbolsFolder"            = $appPackagesFolder
                    "CopySymbolsFromContainer"    = $true
                    "GenerateReportLayout"        = "No"
                    "EnableAppSourceCop"          = $enableAppSourceCop
                    "EnableUICop"                 = $enableUICop
                    "EnableCodeCop"               = $enableCodeCop
                    "EnablePerTenantExtensionCop" = $enablePerTenantExtensionCop
                    "Reportsuppresseddiagnostics" = $reportsuppresseddiagnostics
                    "outputTo"                    = { Param($line)
                        Write-Host $line
                        if ($line -like "error *" -or $line -like "warning *") {
                            $global:_validationResult += $line
                        }
                        elseif ($line -like "$($tmpFolder)*") {
                            $global:_validationResult += $line.SubString($tmpFolder.Length + 1)
                        }
                    }
                }
                if (!$failOnError) {
                    $Parameters += @{ "ErrorAction" = "SilentlyContinue" }
                }

                if ($ruleset) {
                    $myRulesetFile = Join-Path $tmpFolder "ruleset.json"
                    $ruleset | ConvertTo-Json -Depth 99 | Set-Content $myRulesetFile -Encoding UTF8
                    $Parameters += @{
                        "ruleset" = $myRulesetFile
                    }
                    Write-Host "Ruleset.json content:"
                    [System.IO.File]::ReadAllLines($myRulesetFile) | Out-Host
                }

                try {
                    Invoke-Command -ScriptBlock $CompileAppInBcContainer -ArgumentList ($Parameters) | Out-Null
                }
                catch {
                    Write-Host "ERROR $($_.Exception.Message)"
                    $global:_validationResult += $_.Exception.Message
                }

                if ($ignoreWarnings) {
                    Write-Host "Ignoring warnings"
                    $global:_validationResult = @($global:_validationResult | Where-Object { $_ -notlike "*: warning *" -and $_ -notlike "warning *" })
                }
                if (!$doNotIgnoreInfos) {
                    Write-Host "Ignoring infos"
                    $global:_validationResult = @($global:_validationResult | Where-Object { $_ -notlike "*: info *" -and $_ -notlike "info *" })
                }

                $lines = $global:_validationResult.Length - $length
                if ($lines -gt 0) {
                    $i = 0
                    $global:_validationResult = $global:_validationResult | ForEach-Object {
                        if ($i++ -eq $length) {
                            "$lines $(if ($ignoreWarnings) { "errors" } else { "errors/warnings"}) found in $([System.IO.Path]::GetFileName($appFile)) on $($artifactUrl.Split('?')[0]):"
                        }
                        $_
                    }
                    $global:_validationResult += ""
                }
                Invoke-ScriptInBcContainer -containerName $containerName -scriptblock { Param($appFile, $appPackagesFolder)
                    # Copy inside container to ensure files are ready
                    Write-Host "Copy $appFile to $appPackagesFolder"
                    Copy-Item -Path $appFile -Destination $appPackagesFolder -Force
                } -argumentList (Get-BcContainerPath -containerName $containerName -path $appFile), (Get-BcContainerPath -containerName $containerName -path $appPackagesFolder) | Out-Null
            }
            finally {
                if (Test-Path "$tmpFolder.app") {
                    Remove-Item -Path "$tmpFolder.app" -Force
                }
                if (Test-Path $tmpFolder) {
                    Remove-Item -Path $tmpFolder -Recurse -Force
                }
            }
        }
        if ($appPackFolderCreated) {
            Remove-Item $appPackagesFolder -Recurse -Force
        }
        Remove-Item $appsFolder -Recurse -Force

        $global:_validationResult
        Clear-Variable -Scope global -Name "_validationResult"
    }
    catch {
        TrackException -telemetryScope $telemetryScope -errorRecord $_
        throw
    }
    finally {
        TrackTrace -telemetryScope $telemetryScope
    }
}
Export-ModuleMember -Function Run-AlCops
# SIG # Begin signature block
# MIInSQYJKoZIhvcNAQcCoIInOjCCJzYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCATjyDOrvECXbw8
# aLbXYal48E8WungBV7/pEwHDNo279KCCDLowggX1MIID3aADAgECAhMzAAACHU0Z
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
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIHGpi2e/
# L7HLXhK2Lg4SJmqNhOXpkrA2fnvT6tcRKkk1MEIGCisGAQQBgjcCAQwxNDAyoBSA
# EgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20w
# DQYJKoZIhvcNAQEBBQAEggEAbEVMuvugsIVPz8Fl22ROxltIEG5OJi5Fq98lglH4
# RTwilhpMMgKBwOCRaqbjvYI2tcCnlZyTDdY//23Rv1f/AKgTh19Vo45UjnvoIeyW
# qybwMMkZXvz2scSPNeS5FHKwMPj0Y6MR4856bboUVb/xFebUVMqqsufOO5WQZGha
# EGDpN18C37J19n+sJsr4KbW7kKD4cLE9Mi1YI7DbZPdJCA+z7z5Wm2KivY7tAs3e
# zUy5FinL1XuHxcNz+eoH8kDeEGVTMzTogVYPxzk1LXR8mVMKxq7EknOob9vhtVx7
# c6BMoAhcYg0VsYuHc5/NhH6QhnLydaS65gmX9UQixIyvBaGCF5cwgheTBgorBgEE
# AYI3AwMBMYIXgzCCF38GCSqGSIb3DQEHAqCCF3AwghdsAgEDMQ8wDQYJYIZIAWUD
# BAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGEWQoD
# ATAxMA0GCWCGSAFlAwQCAQUABCBWYXadjy/HqF6Cf9/o4ZasXn6a2KLNo7wjNMq8
# N42k4wIGaoSBPZ40GBMyMDI2MDgyNzA2MzAzOC4yNDhaMASAAgH0oIHRpIHOMIHL
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxN
# aWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRT
# UyBFU046OTIwMC0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFNlcnZpY2WgghHtMIIHIDCCBQigAwIBAgITMwAAAiNP2WAkU8/+KwABAAAC
# IzANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAe
# Fw0yNjAyMTkxOTM5NTdaFw0yNzA1MTcxOTM5NTdaMIHLMQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmlj
# YSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046OTIwMC0wNUUw
# LUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIi
# MA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCK6Q2nk5WUdKzSCSafp+UjUARs
# WxHKS63rJhFC/zSabFumTBuaJ0QNrmqevub5Db7fSj5qtwwKnjIO92+HXF67192f
# ujL7DFot5WEj/AtEZ/XrzFHimKlN1h6gEQwP5I67wizaPW5ZzSBNpaLBg5oHvASP
# OZtwdNUoZ+DQKF3hJl1KZuoIlVK+qi7cLjgak6s5oOZcRCMrKnuC3aoVa6wRDbYv
# KUuj7rkFx9KO0PsHJ/k+LnZMggRheh4AVdawyh+oOzKPjlQGUNfSeWUgym2U9CLa
# 8tt0mQX4DxDz6+ram50gj1oAfyQ6TQ7r96PADFOKBgaU7+cpHnaZG89dTegQ6ydB
# RGIycOw1dRX2eKDRRzziK3cn0WaIm/7OeGsyQKjIzEQuUTDv0Jj/9zQ7truLOOpJ
# D98BJVOK7je84Sz2hb3HvUST7j1j2N8peD6olkpFHR/1Z8Jz4F+mkrUF7MmPAirY
# HRzunbIg3HrDMNwFYN7yBkDA4/VMo9CY0y9oGUoq2yjbCwTibz9VYl93nB3QQiTC
# T9nW3M+TOWB+PMrZpExq1BSHmKPzIqehKqrUDoM33PK+dEKwpYLET6uXq4HuQRMX
# WT//sPubUnQAaaUMfQhAZSy23HtxwtN3eK9+T4wCav2wQFt57eUOwUW5/DCzMF9t
# ua5He1hNvgcAXaiG1wIDAQABo4IBSTCCAUUwHQYDVR0OBBYEFNbAh89v29nPY9bw
# Qb1QYCzxVgeXMB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1Ud
# HwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3Js
# L01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggr
# BgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNv
# bS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIw
# MTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgw
# DgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUAA4ICAQCHQwe7z5tp4NZwAf1c
# B+4c9J4svw3P6WqGBMxtqznS6DdzUzStXHCaPZhM41g1iKHNnmcnLjwLujOEaNjh
# SnUDiAZqQjW5ZapOBxgc7Egghh9k+r78qWAe3rJ4QohBbhSGdZtKivTRaeRqmnhy
# 8+ThrKhzCeEwaarXJimZwSpdQQUDbheWHeyAxASqultd5KO0m/UFvO03tfepqGXA
# 4tCg/WGECwKqOjJzpRAfPIB6y1HyVrk+vmL5rpEbTwwLOtX7WxFGG8+cYLk9HjaD
# kxraA/HYlKQRx1sdza+w/gulLwgOnByRJKF2rr8M7FNIlwoi6ywFpaNc8A7HewaG
# jgw/tfcE260I1XekGluANI9HnONOYWlI7BKBQbWE2teo6vsQ1Vg8B8rTZSePVdmX
# L1PPqqs3KVdFKM5kYocPCDM+6VL32IV96sESf2T7DjxanpCg2D2UYj4Z1i7cy8U1
# LLDGg55KWs4af2RRBjH2MulHgAmW5obKxiZCDQjRaroJ2XElXUhigE9BzvhCFbT/
# HDY2vpVpl5HnSpcCSxmL5i5lIT/xbAQMI7Luh75Xrm+IslfFWOGOGMlCp+24qEJE
# glXEP7xwsolNdBNndXihhyIefVGlI1DR7xGELiJrk8ifVWYo9XEbEXv/lbvp6F2R
# 2UsnweWckvq0y1HWnLHDqH6dPjCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkA
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
# T3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjkyMDAtMDVFMC1E
# OTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEw
# BwYFKw4DAhoDFQA4RWFs+kTiZnoZiAj1BtYj8zCNaqCBgzCBgKR+MHwxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29m
# dCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBCwUAAgUA7jozHjAiGA8y
# MDI2MDgyNzAzNTMwMloYDzIwMjYwODI4MDM1MzAyWjB3MD0GCisGAQQBhFkKBAEx
# LzAtMAoCBQDuOjMeAgEAMAoCAQACAgqNAgH/MAcCAQACAhJMMAoCBQDuO4SeAgEA
# MDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAI
# AgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBAEwmvVg0hiKvDydXVxoI9oS1f6dS
# JOdCFlTCTEFmXy6G6e4ceUMGfXiTJjycapxg67u/tg4qnYGylbMlArwn4Ab2rBrM
# 8sGlyuuPhwl/YX/CY1ldL09MxvmwRrqVnj8op7LHU48qoNZfL2kQN3xUdN/ZLP3N
# WgeBGv23ibQWw2d07QyT0dRpX1Ah+MHOmljeo5V6TVvnq7PifoKPns1K6jgh5qYz
# PD5hIsqj7hC2tsNsNB7KILYvrFp/MLcHaHc8PVgPqfbc8uuOgJafnhwByZeXps2L
# sclMbDzSX+dTKUIHOPGfPmSZwOsCgw/a5xaudP76OYCWgxl4TmB8bUoJbOUxggQN
# MIIECQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQ
# MA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
# MSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAiNP
# 2WAkU8/+KwABAAACIzANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0G
# CyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCDWk0+dpgJCRev+C8HSYVQnUgM2
# rSauyxXdzTXmc8qWwjCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EIJbwMywR
# bvcGiynjnwjAqcaD47yYvebKZRAvtEAR5u6zMIGYMIGApH4wfDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgUENBIDIwMTACEzMAAAIjT9lgJFPP/isAAQAAAiMwIgQg79c37+vX
# 6VweJ8kpZo4KTEB2JWJLbeVyLqYHxq5AsoEwDQYJKoZIhvcNAQELBQAEggIAbxCf
# mo0HXsPlH0ubKCtMnCXUdhy5mzdUFb2IkfalqlHRFBK0fJeokW6TPCH61HH5JqgS
# cid3kCdRAhXcA7RQlHnOCDh9hTPjuzRKyX1R0N6uKhAlS3XNj4yYGv9EhKG6W/rS
# AiEaY0eSSvvmgVn/74nC/Q8wMvBqbv/6HZFh25c2/8kzfEP6Si2yVB/mXkQi0FSG
# 877nNKk3T3OCxflAp/8dV7mcedhKVZQ7DJSP9nv/KVF7zg2a24SaeZSrgHbNTi+H
# /9IeMpZO9uPUTToCTar+ebS3dGYLRsgtkD2bqsFAjF1wPMyTCHKP55hLLTS/goNU
# KZiv3/VMQaZSaXWlnOjENqiITGuIvNTUY4uiW8Tso4gPSk5PKFOu5ExxyB4cfv85
# iUEfDfteCeaM6khrGuFizdUBcAEa+q0tLStL/74uenpd9lcwCp5+zCtM+dcTwZIM
# Y+3Ah1I1o2Nc+YcO6EuJ1p70zku84s7STcncTO9aXrPSCIDdwZCzbIvmlZPKSN/A
# khdt996n0udtKUuUfc7US/m0WLnbnYucfkRmtQUiKZhCrUJgDdC+VpE1/4RbELe8
# q/HHnGBLHXQzuzvVzY8K0ThpEfwpzDvhqP+lkGieJCtLTijv7GP3Ttd7yVIsCps4
# bAvgiDsh43JdX/uXP/koPLW6GWWHmZ7A/VhZmIc=
# SIG # End signature block
