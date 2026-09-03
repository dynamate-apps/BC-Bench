<#
 .SYNOPSIS
  Create a new Compiler Folder
 .DESCRIPTION
  Create a folder containing all the necessary pieces from the artifacts to compile apps without the need of a container
  Returns a compilerFolder path, which can be used for functions like Compile-AppWithBcCompilerFolder or Remove-BcCompilerFolder
 .PARAMETER artifactUrl
  Artifacts URL to download the compiler and all .app files from
 .PARAMETER platformArtifactUrl
  Url for platform artifact to use. Use this when you want to use a different platform than the one related to artifactUrl.
 .PARAMETER containerName
  Name of the folder in which to create the compiler folder or empty to use a default name consisting of type-version-country
 .PARAMETER cacheFolder
  If present:
  - if the cacheFolder exists, the artifacts will be grabbed from here instead of downloaded.
  - if the cacheFolder doesn't exist, it is created and populated with the needed content from the ArtifactURL
 .PARAMETER packagesFolder
  If present, the symbols/apps will be copied from the compiler folder to this folder as well
 .PARAMETER vsixFile
  If present, use this vsixFile instead of the one included in the artifacts
 .PARAMETER includeAL
  Include this switch in order to populate folder with AL files (like New-BcContainer)
 .EXAMPLE
  $version = $artifactURL.Split('/')[4]
  $country = $artifactURL.Split('/')[5]
  $compilerFolder = New-BcCompilerFolder -artifactUrl $artifactURL -includeAL
  $baseAppSource = Join-Path $compilerFolder "BaseApp"
  Copy-Item -Path (Join-Path $bcContainerHelperConfig.hostHelperFolder "Extensions\Original-$version-$country-al") $baseAppSource -Container -Recurse
  Compile-AppWithBcCompilerFolder `
      -compilerFolder $compilerFolder `
      -appProjectFolder $baseAppSource `
      -appOutputFolder (Join-Path $compilerFolder '.output') `
      -appSymbolsFolder (Join-Path $compilerFolder 'symbols') `
      -CopyAppToSymbolsFolder
#>
function New-BcCompilerFolder {
    Param(
        [string] $artifactUrl,
        [string] $platformArtifactUrl = '',
        [string] $containerName = '',
        [string] $cacheFolder = '',
        [string] $packagesFolder = '',
        [string] $vsixFile = '',
        [switch] $includeAL
    )

$telemetryScope = InitTelemetryScope -name $MyInvocation.InvocationName -parameterValues $PSBoundParameters -includeParameters @()
try {
    if ($platformArtifactUrl -and -not $artifactUrl) {
        throw "You have to specify artifactUrl when using platformArtifactUrl."
    }
    $parts = $artifactUrl.Split('?')[0].Split('/')
    if ($parts.Count -lt 6) {
        throw "Invalid artifact URL"
    }
    $type = $parts[3]
    $version = [System.Version]($parts[4])
    $country = $parts[5]

    $vsixFile = DetermineVsixFile -vsixFile $vsixFile

    if ($version -lt "16.0.0.0") {
        throw "Containerless compiling is not supported with versions before 16.0"
    }

    if (!$containerName) {
        $containerName = [GUID]::NewGuid().ToString()
    }

    $compilerFolder = Join-Path $bcContainerHelperConfig.hostHelperFolder "compiler\$containerName"
    if (Test-Path $compilerFolder) {
        Remove-Item -Path $compilerFolder -Force -Recurse -ErrorAction Ignore
    }
    New-Item -Path $compilerFolder -ItemType Directory -ErrorAction Ignore | Out-Null

    # Populate artifacts cache
    if ($cacheFolder) {
        $symbolsPath = Join-Path $cacheFolder 'symbols'
        $compilerPath = Join-Path $cacheFolder 'compiler'
        $dllsPath = Join-Path $cacheFolder 'dlls'
    }
    else {
        $symbolsPath = Join-Path $compilerFolder 'symbols'
        $compilerPath = Join-Path $compilerFolder 'compiler'
        $dllsPath = Join-Path $compilerFolder 'dlls'
    }

    $newtonSoftDllPath = ''
    if ($includeAL -or !(Test-Path $symbolsPath)) {
        $artifactPaths = Download-Artifacts -artifactUrl $artifactUrl -platformArtifactUrl $platformArtifactUrl -includePlatform
        $appArtifactPath = $artifactPaths[0]
        $platformArtifactPath = $artifactPaths[1]
        $newtonSoftDllPath = Join-Path $platformArtifactPath "ServiceTier\*\Microsoft Dynamics NAV\*\Service\Newtonsoft.Json.dll" -Resolve
    }

    # IncludeAL will populate folder with AL files (like New-BcContainer)
    if ($includeAL) {
        $alFolder = Join-Path $bcContainerHelperConfig.hostHelperFolder "Extensions\Original-$version-$country-al"
        if (!(Test-Path $alFolder) -or (Get-ChildItem -Path $alFolder -Recurse | Measure-Object).Count -eq 0) {
            if (!(Test-Path $alFolder)) {
                New-Item $alFolder -ItemType Directory | Out-Null
            }
            $countryApplicationsFolder = Join-Path $appArtifactPath "Applications.$country"
            if (Test-Path $countryApplicationsFolder) {
                $baseAppSource = @(get-childitem -Path $countryApplicationsFolder -recurse -filter "Base Application.Source.zip")
            }
            else {
                $baseAppSource = @(get-childitem -Path (Join-Path $platformArtifactPath "?pplications") -recurse -filter "Base Application.Source.zip")
            }
            if ($baseAppSource.Count -ne 1) {
                throw "Unable to locate Base Application.Source.zip"
            }
            Write-Host "Extracting $($baseAppSource[0].FullName)"
            Expand-7zipArchive -Path $baseAppSource[0].FullName -DestinationPath $alFolder
        }
    }

    # Populate cache folder (or compiler folder)
    if (!(Test-Path $symbolsPath)) {
        New-Item $symbolsPath -ItemType Directory | Out-Null
        New-Item $compilerPath -ItemType Directory | Out-Null
        New-Item $dllsPath -ItemType Directory | Out-Null
        # Enumerate subfolders to ensure we support different casings in folder structure
        $modernDevFolder = Join-Path $platformArtifactPath "ModernDev\*\Microsoft Dynamics NAV\*\AL Development Environment"
        $modernDevFolder = Get-ChildItem -Recurse -Directory -Path $platformArtifactPath | Where-Object { $_.FullName -like $modernDevFolder } | ForEach-Object { $_.FullName }
        Copy-Item -Path (Join-Path $modernDevFolder 'System.app') -Destination $symbolsPath
        if ($cacheFolder -or !$vsixFile) {
            # Only unpack the artifact vsix file if we are populating a cache folder - or no vsixFile was specified
            Expand-7zipArchive -Path (Join-Path $modernDevFolder 'ALLanguage.vsix') -DestinationPath $compilerPath
        }
        $serviceTierFolder = Join-Path $platformArtifactPath "ServiceTier\*\Microsoft Dynamics NAV\*\Service" -Resolve
        Copy-Item -Path $serviceTierFolder -Filter '*.dll' -Destination $dllsPath -Recurse
        $newtonSoftDllPath = Join-Path $dllsPath "Newtonsoft.Json.dll"
        Remove-Item -Path (Join-Path $dllsPath 'Service\Management') -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path (Join-Path $dllsPath 'Service\WindowsServiceInstaller') -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path (Join-Path $dllsPath 'Service\SideServices') -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -Path (Join-Path $dllsPath 'OpenXML') -ItemType Directory | Out-Null
        Copy-Item -Path (Join-Path $dllsPath 'Service\DocumentFormat.OpenXml.dll') -Destination (Join-Path $dllsPath 'OpenXML') -Force -ErrorAction SilentlyContinue
        $testAssembliesFolder = Join-Path $platformArtifactPath "Test Assemblies" -Resolve
        $testAssembliesDestination = Join-Path $dllsPath "Test Assemblies"
        New-Item -Path $testAssembliesDestination -ItemType Directory | Out-Null
        Copy-Item -Path (Join-Path $testAssembliesFolder 'Newtonsoft.Json.dll') -Destination $testAssembliesDestination -Force -ErrorAction SilentlyContinue
        Copy-Item -Path (Join-Path $testAssembliesFolder 'Microsoft.Dynamics.Framework.UI.Client.dll') -Destination $testAssembliesDestination -Force
        $mockAssembliesFolder = Join-Path $testAssembliesFolder "Mock Assemblies" -Resolve
        Copy-Item -Path $mockAssembliesFolder -Filter '*.dll' -Destination $dllsPath -Recurse
        # Use questionmark as different versions of BC have different casing of the folder name (extensions/Extensions and applications/Applications)
        $extensionsFolder = Join-Path $appArtifactPath '?xtensions' -Resolve
        if ($extensionsFolder) {
            Write-Host "Copying app files from $extensionsFolder"
            Copy-Item -Path (Join-Path $extensionsFolder '*.app') -Destination $symbolsPath
            $platformAppsPath = Join-Path $platformArtifactPath '?pplications' -Resolve
            $appAppsPath = Join-Path $AppArtifactPath '?pplications.*' -Resolve

            $platformApps = @(Get-ChildItem -Path $platformAppsPath -Filter '*.app' -Recurse)
            Write-Host "PlatForm apps"
            $platformApps | ForEach-Object { Write-Host "- $($_.Name)" }
            $appApps = @()
            if ($appAppsPath) {
                $appApps = @(Get-ChildItem -Path $appAppsPath -Filter '*.app' -Recurse)
                Write-Host "App apps"
                $appApps | ForEach-Object { Write-Host "- $($_.Name)" }
            }
            'Microsoft_Tests-*.app','Microsoft_Performance Toolkit Samples*.app','Microsoft_Performance Toolkit Tests*.app','Microsoft_System Application Test Library*.app','Microsoft_TestRunner-Internal*.app','Microsoft_Business Foundation Test Libraries*.app','Microsoft_AI Test Toolkit*.app','Microsoft_Application Test Library*.app' | ForEach-Object {
                $appName = $_
                $apps = $appApps | Where-Object { $_.Name -like $appName }
                if (!$apps) {
                    $apps = $platformApps | Where-Object { $_.Name -like $appName }
                }
                $apps | ForEach-Object {
                    Copy-Item -Path $_.FullName -Destination $symbolsPath
                }
            }
        }
        else {
            $platformAppsPath = Join-Path $platformArtifactPath '?pplications' -Resolve
            $appAppsPath = Join-Path $AppArtifactPath '?pplications' -Resolve
            if ($appAppsPath) {
                Get-ChildItem -Path $appAppsPath -Filter '*.app' -Recurse | ForEach-Object { Copy-Item -Path $_.FullName -Destination $symbolsPath }
            }
            else {
                Get-ChildItem -Path $platformAppsPath -Filter '*.app' -Recurse | ForEach-Object { Copy-Item -Path $_.FullName -Destination $symbolsPath }
            }
        }
        # Copy manifest.json for .NET version resolution during compilation
        $manifestSource = Join-Path $appArtifactPath "manifest.json"
        if (Test-Path $manifestSource) {
            $manifestDest = if ($cacheFolder) { $cacheFolder } else { $compilerFolder }
            Copy-Item -Path $manifestSource -Destination (Join-Path $manifestDest "manifest.json") -Force
        }
    }

    $dotNetSharedFolder = Join-Path $dllsPath 'shared'
    if ($version -ge "22.0.0.0" -and (!(Test-Path $dotNetSharedFolder)) -and ($dotNetRuntimeVersionInstalled -lt [System.Version]$bcContainerHelperConfig.MinimumDotNetRuntimeVersionStr)) {
        if ("$dotNetRuntimeVersionInstalled" -eq "0.0.0") {
            Write-Host "dotnet runtime version is not installed/cannot be used"
        }
        else {
            Write-Host "dotnet runtime version $dotNetRuntimeVersionInstalled is installed, but minimum required version is $($bcContainerHelperConfig.MinimumDotNetRuntimeVersionStr)"
        }
        Write-Host "Downloading minimum required dotnet version from $($bcContainerHelperConfig.MinimumDotNetRuntimeVersionUrl)"
        $dotnetFolder = Join-Path $compilerFolder 'dotnet'
        $dotnetZipFile = "$($dotnetFolder).zip"
        Download-File -sourceUrl $bcContainerHelperConfig.MinimumDotNetRuntimeVersionUrl -destinationFile $dotnetZipFile
        Expand-7zipArchive -Path $dotnetZipFile -DestinationPath $dotnetFolder
        Move-Item -Path (Join-Path $dotnetFolder 'shared') -Destination $dllsPath
        Remove-Item -Path $dotnetZipFile -Force
        Remove-Item -Path $dotnetFolder -Recurse -Force
    }

    $containerCompilerPath = Join-Path $compilerFolder 'compiler'
    if ($vsixFile) {
        # If a vsix file was specified unpack directly to compilerfolder
        Write-Host "Using $vsixFile"

        if ($vsixFile -notlike 'https://*') {
            if (Test-Path -Path $vsixFile -PathType Leaf) {
                Expand-7zipArchive -Path $vsixFile -DestinationPath $containerCompilerPath
            }

            elseif (Test-Path -Path $vsixFile -PathType Container) {
                if (!(Test-Path -Path $containerCompilerPath)) {
                    New-Item $containerCompilerPath -ItemType Directory | Out-Null
                }

                Copy-Item -Path (Join-Path -Path $vsixFile -ChildPath '*') -Destination $containerCompilerPath -Recurse -Force
            }

            else {
                throw "An invalid vsix file was specified."
            }
        }
        else {
            $tempZip = Join-Path ([System.IO.Path]::GetTempPath()) "alc.$containerName.zip"

            Download-File -sourceUrl $vsixFile -destinationFile $tempZip
            Expand-7zipArchive -Path $tempZip -DestinationPath $containerCompilerPath

            Remove-Item -Path $tempZip -Force -ErrorAction SilentlyContinue
        }

        if ($isWindows -and $newtonSoftDllPath) {
            Copy-Item -Path $newtonSoftDllPath -Destination (Join-Path $containerCompilerPath 'extension\bin') -Force -ErrorAction SilentlyContinue
        }
    }

    # If a cacheFolder was specified, the cache folder has been populated
    if ($cacheFolder) {
        Write-Host "Copying DLLs from cache"
        Copy-Item -Path $dllsPath -Filter '*.dll' -Destination $compilerFolder -Recurse -Force
        Write-Host "Copying symbols from cache"
        Copy-Item -Path $symbolsPath -Filter '*.app' -Destination $compilerFolder -Recurse -Force
        # If a vsix file was specified, the compiler folder has been populated
        if (!$vsixFile) {
            Write-Host "Copying compiler from cache"
            Copy-Item -Path $compilerPath -Destination $compilerFolder -Recurse -Force
        }
        # Copy manifest.json from cache to compiler folder
        $cachedManifest = Join-Path $cacheFolder "manifest.json"
        if (Test-Path $cachedManifest) {
            Copy-Item -Path $cachedManifest -Destination (Join-Path $compilerFolder "manifest.json") -Force
        }
    }

    # If a packagesFolder was specified, copy symbols from CompilerFolder
    if ($packagesFolder) {
        Write-Host "Copying symbols to packagesFolder"
        New-Item -Path $packagesFolder -ItemType Directory -Force | Out-Null
        Copy-Item -Path $symbolsPath -Filter '*.app' -Destination $packagesFolder -Force -Recurse
    }

    if ($isLinux -or $isMacOS) {
        $compilerPlatform = 'linux'
        if ($isMacOS) {
            $compilerPlatform = 'darwin'
        }
        $alcExePath = Join-Path $containerCompilerPath "extension/bin/$($compilerPlatform)/alc"
        $alToolExePath = Join-Path $containerCompilerPath "extension/bin/$($compilerPlatform)/altool"

        if (Test-Path $alcExePath) {
            # Old VSIX layout with platform-specific subdirs
            if (Test-Path $alToolExePath) {
                # Set execute permissions on altool
                if ($isLinux) {
                    & /usr/bin/env sudo pwsh -command "& chmod +x $alToolExePath"
                } else {
                    & chmod +x $alToolExePath
                }
            }
            # Set execute permissions on alc
            if ($isLinux) {
                & /usr/bin/env sudo pwsh -command "& chmod +x $alcExePath"
            } else {
                & chmod +x $alcExePath
            }
        } else {
            # New VSIX layout (flat bin/) or old layout needing runtimeconfig patching
            $alcConfigPath = Join-Path $containerCompilerPath 'extension/bin/win32/alc.runtimeconfig.json'
            if (-not (Test-Path $alcConfigPath)) {
                $alcConfigPath = Join-Path $containerCompilerPath 'extension/bin/alc.runtimeconfig.json'
            }
            if (Test-Path $alcConfigPath) {
                $oldAlcConfig = Get-Content -Path $alcConfigPath -Encoding UTF8 | ConvertFrom-Json
                if ($oldAlcConfig.runtimeOptions.PSObject.Properties.Name -eq 'includedFrameworks') {
                    # Old self-contained VSIX: patch runtimeconfig for Linux/macOS
                    Write-Host "Patching alc.runtimeconfig.json for use with $($compilerPlatform)"
                    $newAlcConfig = @{
                        "runtimeOptions" = @{
                            "tfm" = "net6.0"
                            "framework" = @{
                                "name" = "Microsoft.NETCore.App"
                                "version" = $oldAlcConfig.runtimeOptions.includedFrameworks[0].version
                            }
                            "configProperties" = @{
                                "System.Reflection.Metadata.MetadataUpdater.IsSupported" = $false
                            }
                        }
                    }
                    $newAlcConfig | ConvertTo-Json | Set-Content -Path $alcConfigPath -Encoding utf8NoBOM
                }
                # else: new framework-dependent VSIX already has "framework" key, no patching needed
            }
        }
    }

    Write-Host "Enumerating Apps in $symbolsPath"
    $compilerFolderAppFiles = @(Get-ChildItem -Path (Join-Path $symbolsPath '*.app') | Select-Object -ExpandProperty FullName)
    GetAppInfo -AppFiles $compilerFolderAppFiles -compilerFolder $compilerFolder -cacheAppinfoPath (Join-Path $symbolsPath 'cache_AppInfo.json') | Out-Null
    if ($cacheFolder) {
        Write-Host "Copying symbols cache"
        Copy-Item -Path (Join-Path $symbolsPath 'cache_AppInfo.json') -Destination (Join-Path $compilerFolder 'symbols') -Force
        $templatesFolder = Join-Path $cacheFolder "compiler\extension\templates"
        if (Test-Path $templatesFolder) {
            Write-Host "Removing Templatest Folder"
            Remove-Item $templatesFolder -Recurse -Force
        }
    }
    $compilerFolder
}
catch {
    TrackException -telemetryScope $telemetryScope -errorRecord $_
    throw
}
finally {
    TrackTrace -telemetryScope $telemetryScope
}
}
Export-ModuleMember -Function New-BcCompilerFolder

# SIG # Begin signature block
# MIInSAYJKoZIhvcNAQcCoIInOTCCJzUCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDnMNP4DsJaN4mp
# ZFnAgkzmydYyET4PP2LVh0oB/7OrM6CCDLowggX1MIID3aADAgECAhMzAAACHU0Z
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
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIFieAqGb
# Qlp9O3rn/03tp0EEe0XnTJoNLl3QQ9htLvXMMEIGCisGAQQBgjcCAQwxNDAyoBSA
# EgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20w
# DQYJKoZIhvcNAQEBBQAEggEAS6poHIo9PYoWRyLKzY6lJ0DiM+BDk+ePAPYijCJt
# Y79EECxmRUSPTfbkxXaj2l7uBu0LFt9UgMKsvXBJQ9G19NF/eCp73mibrQjP5qfd
# /qd1B68KkejsVf4+HflvoyupskQ/ZNfcFAA94AkyU3Kjlx5dAKCs0ZzI60Ykmrci
# VFM7ZhSfVEfcdZ9z+TyucMdtcx9wSLgYwfjAtvoOmkln+WqIS76Qa+poHTpHtHO9
# C1Kiza65wt2qyOJmWzEKWVmoxrKY9nbA+uU0iNEJ8uAbUTOpmaMmGQ67smTRS+TS
# on3vOAr4iuWPsFkApGzwPdM9Rs02XtNQ2mgM0UKaGrRsbKGCF5YwgheSBgorBgEE
# AYI3AwMBMYIXgjCCF34GCSqGSIb3DQEHAqCCF28wghdrAgEDMQ8wDQYJYIZIAWUD
# BAIBBQAwggFRBgsqhkiG9w0BCRABBKCCAUAEggE8MIIBOAIBAQYKKwYBBAGEWQoD
# ATAxMA0GCWCGSAFlAwQCAQUABCAC2n6W5McZUZm5TsS0dJ/bqW4StL4faqb8wWS3
# K0fRjQIGaoULU16CGBIyMDI2MDgyNzA2MzAzNy45N1owBIACAfSggdGkgc4wgcsx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJTAjBgNVBAsTHE1p
# Y3Jvc29mdCBBbWVyaWNhIE9wZXJhdGlvbnMxJzAlBgNVBAsTHm5TaGllbGQgVFNT
# IEVTTjo3RjAwLTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3Rh
# bXAgU2VydmljZaCCEe0wggcgMIIFCKADAgECAhMzAAACHqOspG45b3xJAAEAAAIe
# MA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
# dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9y
# YXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMB4X
# DTI2MDIxOTE5Mzk0OVoXDTI3MDUxNzE5Mzk0OVowgcsxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xJTAjBgNVBAsTHE1pY3Jvc29mdCBBbWVyaWNh
# IE9wZXJhdGlvbnMxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjo3RjAwLTA1RTAt
# RDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZTCCAiIw
# DQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAKXROO1sPCxHsV7xpzqiXmzXOG1O
# p3YBalyFCEun0bmaZIzbc3l/JAYJDUPTqs4Dc+BcoX7vq9e84KzZWwu/WjCPiYcT
# ISqKrwYnnIL79A1hGlk8Dx7s6B6TMM7pL/i/L+NMxhuneuG4WIooLNNY5C10VwX4
# PSTfr0jumb8TTtLI0waS413mWPlIn3VSoW5l+MwHpxDbCHvua2JFRV2PnfKN02qP
# 4ZCX5hrPb0GOvOftTWWf4mkuWdvTF0aZmgg8plvAFVxa3Ivi7KEwvtJJOaI59ZdT
# 6D7I2XQJ2gsYvwu1YcSLwWy5M95J1KqZ4yu8toSaJtNVNLi9BBjw0+dvq4jnLqI1
# X28EVybwtT+UNOMZOo9rtQFPiB1/kmbfBit8IVng/+PkyipPQk41xrnSO3hMYj3R
# KKFdoMRiqTbdLQglndSRSm6QNFOMrvXcEjKR9/HIGox5Cp87TO9Z9THsGuZSm6BB
# zD334PEuXaB/65ASlGaeVutUn129b12zh+oQ83aMbRDAXU8FKCU1xXVKmpkqK1CA
# EZLC7/zYArO2gIfBhEdE3DPBNV7/Uo1O+aoB3hSB6zjLA4fTaFpqBPzBhjw51Z2M
# qfeTTnbD6SZzRQLQX6JVdMZkgzG+j2IFlChd6HNG1Yn9U60q8LJLdywrM3utK1Yn
# CNJbPp205/SX7K0tAgMBAAGjggFJMIIBRTAdBgNVHQ4EFgQU5goWmuoEHQlmYlwU
# Lhw8+Z4XgmQwHwYDVR0jBBgwFoAUn6cVXQBeYl2D9OXSZacbUzUZ6XIwXwYDVR0f
# BFgwVjBUoFKgUIZOaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwv
# TWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3JsMGwGCCsG
# AQUFBwEBBGAwXjBcBggrBgEFBQcwAoZQaHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAx
# MCgxKS5jcnQwDAYDVR0TAQH/BAIwADAWBgNVHSUBAf8EDDAKBggrBgEFBQcDCDAO
# BgNVHQ8BAf8EBAMCB4AwDQYJKoZIhvcNAQELBQADggIBAKShkHk2clUVvnAp6NGi
# eTnXxrZME1ikpwEy18voFLQBFoAE4wZguU826EjUfCZ6U/2FfeirdNoSb9wOSTM1
# ADMN50+ChEjZHv7ymg1Ja8dcQCztJk4Ob3HsqqUGQ1kz17HhdjXI2ZU4CZYONGvu
# MqNqJBue1/sQLgY2KTEYZpVY6N9i3dD1fSv8qzwoGVvMNH3OMD9MJy1HhyjValTV
# lEsWsH1uXx1HGxufJPapDjUTt1PXZHfR4gZTOISzkY37bpX+i9c6LbR0mIzXeFha
# /LU00kCGQo6UsHU426d3p9+E91Rwday7xX6VHRpqQxXrgeoNsu6ZmsI3BSh9XHfE
# yTwXi0Jgm1DEtPLBzfSxkAPVLawLX3n3HoqLED6njUUtSXyDrigfLdt9icfnF3gk
# 4GBChqqd0aNxy3Gv7wSSeOErKuADOtNwosltR7OCjJ7xusIsn7Lo8CgSOldGRJgB
# TzB9DdhZFyToAvChXtSKfz6ukZBJteEXpzV1MVqReYKEKW53ggANj+3olGQn7ToX
# Mv6MN3wotXxCPvsl+K5OI8gbkb/GWcahkVxf7LIG0O/NkTjx35j4dhR39y+EfUUq
# XsAf7kDKi2olIWa8z8G5hHHYHbRqxVeKVXaTYls07csYLPdD52kSXPCx8muRrU3+
# B62Zrt9amjCw2+ghoRC+Np3xMIIHcTCCBVmgAwIBAgITMwAAABXF52ueAptJmQAA
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
# cGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046N0YwMC0wNUUwLUQ5
# NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WiIwoBATAH
# BgUrDgMCGgMVAIP9A2QoMhbhUgXuPeiLaputHRr/oIGDMIGApH4wfDELMAkGA1UE
# BhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAc
# BgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0
# IFRpbWUtU3RhbXAgUENBIDIwMTAwDQYJKoZIhvcNAQELBQACBQDuOhR8MCIYDzIw
# MjYwODI3MDE0MjIwWhgPMjAyNjA4MjgwMTQyMjBaMHcwPQYKKwYBBAGEWQoEATEv
# MC0wCgIFAO46FHwCAQAwCgIBAAICG3cCAf8wBwIBAAICFB8wCgIFAO47ZfwCAQAw
# NgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYBBAGEWQoDAqAKMAgCAQACAwehIKEKMAgC
# AQACAwGGoDANBgkqhkiG9w0BAQsFAAOCAQEAj+Pdjg7zfIIpcKX5p2JA+WS286o0
# ThMZjky90eLPwKA8DfzlYuqEIwsccwkbXP7/iEGmneMzdCe/arEU0/0uS7HJPo8c
# ziM6tu4yqKMU+MXzpz0+xJJUkZnCm2J4r41B5qMbyPulQZ/J4S6IXDNAs6D6s0dZ
# eiCKHj86o3jhrPqvQxmNyn7blY94VK6jsvk39uHEIg/H5REhtvrsxHO578GddWvb
# M+Qa8GMbvO3qe6PU5UqOHXKe9wM3fO1qe5nnleh/7wlrhCaHcz40eGOTYpZgK6bZ
# OZ6qoFHTDpmm6EQVs0pUiQRKVv6Kh5phjOcz8MBQtQjTrIEO//YLnvhb6zGCBA0w
# ggQJAgEBMIGTMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAw
# DgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# JjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAACHqOs
# pG45b3xJAAEAAAIeMA0GCWCGSAFlAwQCAQUAoIIBSjAaBgkqhkiG9w0BCQMxDQYL
# KoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkEMSIEIDaCcSCUlUUHkDo9J2/VOU9kGLxu
# hNvvkBqoNLJkGMQSMIH6BgsqhkiG9w0BCRACLzGB6jCB5zCB5DCBvQQgL4FdavP2
# B4yAzwG+fxurEeOEdcnb0QGLMhMjDQH284IwgZgwgYCkfjB8MQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGlt
# ZS1TdGFtcCBQQ0EgMjAxMAITMwAAAh6jrKRuOW98SQABAAACHjAiBCB9dVIlZnXM
# 4y9aV6hnPkW025+kcn32ajdvCGfftl8gCTANBgkqhkiG9w0BAQsFAASCAgBNsynC
# X+HoX4qBmDIewX9PqjYLbYcK7VFvc4QAt/n5qh9IrzoGBw/2iW2VjXlVkdpkggB1
# MlcvZJhFxkpTrnrWvy5/QTdQ1UB+OTmE/j/ELMeBiPuJKyUFewMJao9Qxaahi+lm
# HEQQST2rBXUml9jxHp25N1uNC9Kboydmav4CHQCXeyxpjO2M0WpJfUQ5Nwuz00wx
# 86FJBZy+v0GShlFFcDFgb7GN4HqhB7v1ZpSMZdin8XpxrbYQ2kn42wLLbzNovMBb
# bb9yPpG+CMdNpIdTXdRaq4hkdZELmX7gyZ3qo2l5ekz/3w01z0jCI3n+pmKbLmQv
# JhyINjyCb/aHiKF2oObtpD4lQOOaGSZ/Ywm2Yqnx0/6X0/Cf4bIbklO2mWREpG/R
# 1HJxcMEvPIzhOIabl7+Nitr+rS68mYDwpsf+PeoxJKXNy7xT+cUIHTaOImDyZZa/
# RdTWMonmH+I1gy3NC29Coop1RHkeDC/5pArLPvhRkgsQyUL36MZFMAdAnOYEhLwY
# UdqaqIpKil2IOsJdN1NuVldMK4ucv98ONfD6w2npGFeZO0OpEGVbq0UvuzIR3/0k
# M+21gXpu6SHgpmG5xAdBIjZsmNh60JAgA7qwF7DgNko4LHxH0VmmFJ8mD4wBRUTb
# 06t1qk5t/gMYiRoa04woHYo7nEv8YQHHxC5pdQ==
# SIG # End signature block
