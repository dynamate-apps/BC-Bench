<# 
 .Synopsis
  Create a VS Code AL Project Folder based on a Container
 .Description
  Export all objects from a container, convert them to AL and establish the necessary project files.
  The container needs to be started with -includeAL, which ensures that the .net used by the baseapp are available in a folder.
 .Parameter containerName
  Name of the container from which you want to create the AL Project folder
 .Parameter alProjectFolder
  The alProjectFolder will contain the AL project upon successful completion of this function.
  The content of the folder will be removed.
  This folder doesn't need to be shared with the container, but if you want to use Compile-AppInBcContainer, it might be a good idea to share it.
 .Parameter id
  This parameter specifies the ID of the AL app to be placed in app.json. Default is a new GUID.
 .Parameter name
  This parameter specifies the name of the AL app to be placed in app.json. Default is the container name.
 .Parameter publisher
  This parameter specifies the publisher of the AL app to be placed in app.json. Default is Default Publisher.
 .Parameter version
  This parameter specifies the version of the AL app to be placed in app.json. Default is 1.0.0.0.
 .Parameter addGIT
  Specify 
 .Parameter useBaseLine
  Specify this switch if you want to use the AL BaseLine, which was created when creating the container with -includeAL.
  The baseline AL objects are added to "C:\ProgramData\BcContainerHelper\Extensions\Original-<version>-<country>-al" and will contain AL files for the C/AL objects in the container at create time.
 .Parameter alFileStructure
  Specify a function, which will determine the location of the individual al source files
 .Parameter runTxt2AlInContainer
  Specify a foreign container in which you want to run the txt2al tool
 .Parameter useBaseAppProperties
  Specify to retrieve app properties from base app actually installed in container
 .Parameter credential
  Credentials are needed to download the app if you do not use the baseline
 .Example
  $alProjectFolder = "C:\ProgramData\BcContainerHelper\AL\BaseApp"
  Create-AlProjectFolderFromBcContainer -containerName alContainer `
                                         -alProjectFolder $alProjectFolder `
                                         -name "myapp" `
                                         -publisher "Freddy Kristiansen" `
                                         -version "1.0.0.0" `
                                         -AddGIT `
                                         -useBaseLine
#>
function Create-AlProjectFolderFromBcContainer {
    Param (
        [string] $containerName = $bcContainerHelperConfig.defaultContainerName,
        [Parameter(Mandatory=$true)]
        [string] $alProjectFolder,
        [string] $id = [GUID]::NewGuid().ToString(),
        [string] $name = $containerName,
        [string] $publisher = "Default Publisher",
        [string] $version = "1.0.0.0",
        [switch] $AddGIT,
        [switch] $useBaseLine,
        [ScriptBlock] $alFileStructure,
        [string] $runTxt2AlInContainer = $containerName,
        [switch] $useBaseAppProperties,
        [PSCredential] $credential = $null
    )

$telemetryScope = InitTelemetryScope -name $MyInvocation.InvocationName -parameterValues $PSBoundParameters -includeParameters @()
try {

    $navversion = Get-BcContainerNavversion -containerOrImageName $containerName
    $ver = [System.Version]($navversion.split('-')[0])
    $alFolder   = Join-Path $bcContainerHelperConfig.hostHelperFolder "Extensions\Original-$navversion-al"
    $dotnetAssembliesFolder = Join-Path $bcContainerHelperConfig.hostHelperFolder "Extensions\$containerName\.netPackages"

    if (($useBaseLine -and !(Test-Path $alFolder -PathType Container)) -or !(Test-Path $dotnetAssembliesFolder -PathType Container)) {
        throw "Container $containerName was not started with -includeAL (or -doNotExportObjectsAsText was specified)"
    }

    # Empty Al Project Folder
    if (Test-Path -Path $alProjectFolder -PathType Container) {
        if (Test-Path -Path (Join-Path $alProjectFolder "*")) {
            if (Test-Path -Path (Join-Path $alProjectFolder "app.json")) {
                Remove-Item -Path (Join-Path $alProjectFolder "*") -Recurse -Force
            }
            else {
                throw "The directory '$alProjectFolder' already exists, and it doesn't seem to be an AL project folder, please remove the folder manually."
            }
        }
    }
    else {
        New-Item -Path $AlProjectFolder -ItemType Directory | Out-Null
    }

    if ($useBaseLine) {
        Copy-AlSourceFiles -Path "$alFolder\*" -Destination $AlProjectFolder -Recurse -alFileStructure $alFileStructure
    }
    elseif ($ver.Major -ge 15) {
        $id = [Guid]::NewGuid().Guid
        $appFile = Join-Path $bcContainerHelperConfig.hostHelperFolder "Extensions\BaseApp-$id.app"
        $appFolder = Join-Path $bcContainerHelperConfig.hostHelperFolder "Extensions\BaseApp-$id"
        $myAlFolder = Join-Path $bcContainerHelperConfig.hostHelperFolder "Extensions\al-$id"
        try {
            $appName = "Base Application"
            if ($ver -lt [Version]("15.0.35659.0")) {
                $appName = "BaseApp"
            }
            $baseapp = Get-BcContainerAppInfo -containerName $containerName | Where-Object { $_.Name -eq $appName }
            Get-BcContainerApp -containerName $containerName `
                               -publisher $baseapp.Publisher `
                               -appName $baseapp.Name `
                               -appVersion $baseapp.Version `
                               -appFile $appFile `
                               -credential $credential
        
            Extract-AppFileToFolder -appFilename $appFile -appFolder $appFolder
            'layout','src','translations' | ForEach-Object {
                if (Test-Path (Join-Path $appFolder $_)) {
                    Copy-Item -Path (Join-Path $appFolder $_) -Destination $myAlFolder -Recurse -Force
                }
            }

            Copy-AlSourceFiles -Path "$myAlFolder\*" -Destination $AlProjectFolder -Recurse -alFileStructure $alFileStructure
        }
        finally {    
            Remove-Item -Path $myAlFolder -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $appFolder -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $appFile -Force -ErrorAction SilentlyContinue
        }
    }
    else {
        Convert-ModifiedObjectsToAl -containerName $containerName -doNotUseDeltas -alProjectFolder $AlProjectFolder -alFileStructure $alFileStructure -runTxt2AlInContainer $runTxt2AlInContainer
    }

    $appJsonFile = Join-Path $AlProjectFolder "app.json"
    if ($useBaseLine -and $ver -ge [Version]("15.0.35528.0")) {
        $appJson = [System.IO.File]::ReadAllLines("$alFolder\app.json") | ConvertFrom-Json

        if (-not $useBaseAppProperties) {
            $appJson.Id = $id
            $appJson.Name = $name
            $appJson.Publisher = $publisher
            $appJson.Version = $version
        }

        if ([bool]($appJson.PSObject.Properties.name -eq "Logo")) {
            try {
                Copy-Item -Path (Join-Path $alFolder $appJson.Logo) -Destination (Join-Path $alProjectFolder $appJson.Logo) -Force
            }
            catch {
                $appJson.Logo = ""
            }
        }

    } elseif ($ver.Major -ge  15) {
        
        if ($useBaseAppProperties) {
            $appName = "Base Application"
            if ($ver -lt [Version]("15.0.35659.0")) {
                $appName = "BaseApp"
            }
            $baseapp = Get-BcContainerAppInfo -containerName $containerName | Where-Object { $_.Name -eq $appName }
            if ($baseapp) {
                $id = $baseapp.AppId
                $name = $baseapp.Name
                $publisher = $baseapp.Publisher
                $version = $baseapp.Version
            }
            else {
                throw "BaseApp not found"
            }
        }
        if ($ver -ge [Version]("15.0.35528.0")) {
            $sysAppVer = "$($ver.Major).0.0.0"
        }
        else {
            $sysAppVer = "1.0.0.0"
        }
        $appJson = @{ 
            "id" = $id
            "name" = $name
            "publisher" = $publisher
            "version" = $version
            "brief" = ""
            "description" = ""
            "privacyStatement" = ""
            "EULA" = ""
            "help" = ""
            "url" = ""
            "logo" = ""
            "dependencies" = @(@{
                "appId" = "63ca2fa4-4f03-4f2b-a480-172fef340d3f"
                "publisher" = "Microsoft"
                "name" = "System Application"
                "version" = $sysAppVer
            })
            "screenshots" = @()
            "platform" = "$($ver.Major).0.0.0"
            "idRanges" = @()
            "showMyCode" = $true
            "target" = "OnPrem"
        }
    }
    else {
        $appJson = @{ 
            "id" = $id
            "name" = $name
            "publisher" = $publisher
            "version" = $version
            "brief" = ""
            "description" = ""
            "privacyStatement" = ""
            "EULA" = ""
            "help" = ""
            "url" = ""
            "logo" = ""
            "dependencies" = @()
            "screenshots" = @()
            "platform" = "14.0.0.0"
            "idRanges" = @()
            "showMyCode" = $true
            "target" = "Internal"
        }
    }
    Set-Content -Path $appJsonFile -Value ($appJson | ConvertTo-Json)

    $dotnetPackagesFolder = Join-Path $AlProjectFolder ".netpackages"
    New-Item -Path $dotnetPackagesFolder -ItemType Directory -Force | Out-Null

    $alPackagesFolder = Join-Path $AlProjectFolder ".alpackages"
    New-Item -Path $alPackagesFolder -ItemType Directory -Force | Out-Null

    $vscodeFolder = Join-Path $AlProjectFolder ".vscode"
    New-Item -Path $vscodeFolder -ItemType Directory -Force | Out-Null

    $settingsJsonFile = Join-Path $vscodeFolder "settings.json"
    $settingsJson = @{
        "al.enableCodeAnalysis" = $false
        "al.enableCodeActions" = $false
        "al.incrementalBuild" = $true
        "al.packageCachePath" = ".alpackages"
        "al.assemblyProbingPaths" = @(".netpackages", $dotnetAssembliesFolder)
        "editor.codeLens" = $false
    }
    Set-Content -Path $settingsJsonFile -Value ($settingsJson | ConvertTo-Json)
    
    $launchJsonFile = Join-Path $vscodeFolder "launch.json"
    $config = Get-BcContainerServerConfiguration -ContainerName $containerName
    if ($config.DeveloperServicesSSLEnabled -eq "true") {
        $devserverUrl = "https://$containerName"
    }
    else {
        $devserverUrl = "http://$containerName"
    }
    if ($config.ClientServicesCredentialType -eq "Windows") {
        $authentication = "Windows"
    }
    else {
        $authentication = "UserPassword"
    }
    $launchJson = @{
        "version" = "0.2.0"
        "configurations" = @( @{
            "type" = "al"
            "request" = "launch"
            "name" = "$containerName"
            "server" = $devserverUrl
            "port" = [int]($config.DeveloperServicesPort)
            "serverInstance" = $config.ServerInstance
            "authentication" = $authentication
            "breakOnError" = $true
            "launchBrowser" = $true
        } )
    }
    Set-Content -Path $launchJsonFile -Value ($launchJson | ConvertTo-Json)

    if ($addGit) {
        Add-GitToAlProjectFolder -alProjectFolder $alProjectFolder -commitMessage $containerName
    }
    
    Write-Host -ForegroundColor Green "Al Project Folder Created"
}
catch {
    TrackException -telemetryScope $telemetryScope -errorRecord $_
    throw
}
finally {
    TrackTrace -telemetryScope $telemetryScope
}
}
Set-Alias -Name Create-AlProjectFolderFromNavContainer -Value Create-AlProjectFolderFromBcContainer
Export-ModuleMember -Function Create-AlProjectFolderFromBcContainer -Alias Create-AlProjectFolderFromNavContainer


# SIG # Begin signature block
# MIInSQYJKoZIhvcNAQcCoIInOjCCJzYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCACJ00D9YZCRR/o
# 6lpi2auuJLwTbkOyuSgtpcD8PbK2XqCCDLowggX1MIID3aADAgECAhMzAAACHU0Z
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
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIC+a5/b4
# oUaBYa8DAblOrNvYx5hjcU/olzRt4TRwDti5MEIGCisGAQQBgjcCAQwxNDAyoBSA
# EgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20w
# DQYJKoZIhvcNAQEBBQAEggEAgoTVTf+CkWZyATcOenV7qU96l4viUwxqU66B+ppU
# RigpaeR+PZyI4S/sYPJzpssz6bhUDYc1heCZdoQzuFi97xJ6y9K1yNFYwkiP/ayH
# BaP4gVqP2SZX0JfRRPUf73SoaRJt74zhw41P9FM7ArXSqBZS/31O7grrlJZ8y1d2
# vmbgPfdFbppCRa5Si1LjnRz9JdwqoIYBV1ayntKAcv2bzjPjCgQTpQdbNLB1KN0k
# TABrPc6AyDi0bZquOJUBE1CZVFfN8T7TlQil+M0JusYLrDm8VoFMu5NGp0IptA6U
# afre3TE5yFW4h+RwD4hT64HhEQHpplIw70+xRlCx4VnVuqGCF5cwgheTBgorBgEE
# AYI3AwMBMYIXgzCCF38GCSqGSIb3DQEHAqCCF3AwghdsAgEDMQ8wDQYJYIZIAWUD
# BAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGEWQoD
# ATAxMA0GCWCGSAFlAwQCAQUABCDKzLGQ6uPwhAXcSg/8cRwHSZvwHu0fMppnXmhv
# MYBbjAIGaoVY7GvBGBMyMDI2MDgyNzA2MzAzOC4xNTZaMASAAgH0oIHRpIHOMIHL
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
# CyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCAse9P0VrN/LtQ3yZdHy/VgiLyV
# uMCIF3zi9JmWlKevfTCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EIMwyXGFn
# TNsZRBrs6GN/BbV0okaNP3VBYqLFjUsFnbgqMIGYMIGApH4wfDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgUENBIDIwMTACEzMAAAImNbQ+Z0OT9h8AAQAAAiYwIgQg4RWuKsf4
# M+wbtxXql7QbH++jD59EOD9zWtx97APKemcwDQYJKoZIhvcNAQELBQAEggIApNtW
# KQQ4WwLFLa2srwmsvTyv5cdwIYIW3eael1tBcC6N2ny8s10VLpWFoE/DyUEgNJJJ
# UUpvl4jnm2QCXKdIxdN1x5YCklvPc/n4km1eXYaQdjC0BmiZBDArl1ho9No4nb8h
# 0nqBZqUWwcjV6MoDdX+8H4i8fics5ovyrEdtvx3/Le3fd22Z2uSMlB5gf0ozR7R5
# Ceew8JpTpiO3JzVwP1KiELaC3Q/au6nJdqsQRmW47zpfXApwGf/SULNkg7fYhh3w
# RGRdNaHwX7DDj/VhUp8+EyGgCn86/8lFRxTs/kQxvQIqRMT8a7DMDubdAhvMumxA
# Qqgxt5YGE5X/bLC8QcwZWY7eyGTZZfETNwJdJ2vfeTIAnXjViLO3ufu5knTe0fub
# SaZ4S/21OljVAf3+vGl7RBE8zaxReF2XFwId/gCorlO+k6uibNYIglYuLKQIsUKv
# q6mZYdVUzuWWZEXHksM2TF9PDX9qqnfWtbg7LO5eBUvmrQDq2KAn8UJNhwgN9kBe
# nWcXZ+MaGykO2IDbHessESOtDgJHsBtHxhnx5KSUGdrYmOzN+kDZczJ+leuI7hhX
# Hx8hwO1+xa27sCoahAvAzIRmhVeBJ4ksulDNGlzkEZAsqxdzLA6drpTTI012qVYe
# mSiLj5GAOUiiSJQLYH0/0s5U4xEvFYLXnHEaNuc=
# SIG # End signature block
