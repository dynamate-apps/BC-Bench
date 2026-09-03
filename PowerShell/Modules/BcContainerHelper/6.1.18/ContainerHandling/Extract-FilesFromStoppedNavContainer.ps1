<# 
 .Synopsis
  Extract Files From stopped NAV/BC Container
 .Description
  Extract all files from a Container Image necessary to start a generic container with these files
 .Parameter containerName
  Name of the Container from which you want to extract the files
 .Parameter path
  Location where you want the files to be placed
 .Parameter extract
  Determine what you need to extract (default is all)
 .Parameter force
  Specify -force if you want to automatically stop the container if running and remove the destination folder if it exists
 .Example
  Extract-FilesFromStoppedBcContainer -ContainerName temp -Path "c:\programdata\bccontainerhelper\extensions\acontainer\afolder"
#>
function Extract-FilesFromStoppedBcContainer {
    [CmdletBinding()]
    Param (
        [string] $containerName = $bcContainerHelperConfig.defaultContainerName,
        [string] $path,
        [ValidateSet('all','vsix','database')]
        [string] $extract = "all",
        [switch] $force
    )

$telemetryScope = InitTelemetryScope -name $MyInvocation.InvocationName -parameterValues $PSBoundParameters -includeParameters @()
try {

    $artifactUrl = Get-BcContainerArtifactUrl -containerName $containerName
    if ($artifactUrl) {
        throw "Extract-FilesFromStoppedBcContainer doesn't support containers based on artifacts."
        return
    }

    $startContainer = $false
    if ((docker inspect -f '{{.State.Running}}' $containerName) -eq "true") {
        if (!$force) {
            throw "Container is running. Cannot extract files from a running container"
        }
        $startContainer = $true
        Stop-BcContainer $containerName | Out-Null
    }

    if (Test-Path -Path $path) {
        if (!$force) { 
            throw "Destination folder '$path' already exists"
        }
        Remove-Item -Path "$path\*" -Recurse -Force
    }
    else {
        New-Item -Path $path -ItemType Directory -Force | Out-Null
    }

    $ErrorActionPreference = 'Continue'

    if ($extract -eq "all") {

        $inspect = docker inspect $containerName | ConvertFrom-Json
        if ($inspect.Config.Labels.psobject.Properties.Match('platform').Count -ne 0) {
            Set-Content -Path "$path\platform.txt" -value "$($inspect.Config.Labels.platform)"
        }
        $country = $inspect.Config.Labels.Country
        Set-Content -Path "$path\country.txt" -value "$country"
        Set-Content -Path "$path\version.txt" -value "$($inspect.Config.Labels.Version)"

        New-Item "$path\ServiceTier\System64Folder" -ItemType Directory | Out-Null
        New-Item "$path\ServiceTier\Program Files" -ItemType Directory | Out-Null
        New-Item "$path\WebClient\Microsoft Dynamics NAV" -ItemType Directory | Out-Null
        New-Item "$path\RoleTailoredClient\systemFolder" -ItemType Directory | Out-Null
        New-Item "$path\RoleTailoredClient\Program Files" -ItemType Directory | Out-Null
        New-Item "$path\ClickOnceInstallerTools\Program Files\Microsoft Dynamics NAV" -ItemType Directory | Out-Null
        New-Item "$path\WindowsPowerShellScripts\Cloud" -ItemType Directory | Out-Null
        New-Item "$path\RoleTailoredClient\CommonAppData\Microsoft\Microsoft Dynamics NAV\VER" -ItemType Directory | Out-Null
        
        Write-Host "Extracting Service Tier and WebClient Files"
        docker cp "$($containerName):\Windows\System32\NavSip.dll" "$path\ServiceTier\System64Folder"
        docker cp "$($containerName):\Program Files\Microsoft Dynamics NAV" "$path\ServiceTier\program files\Microsoft Dynamics NAV"
        Write-Host "Extracting Windows Client Files"
        docker cp "$($containerName):\Windows\SysWow64\NavSip.dll" "$path\RoleTailoredClient\systemFolder" 2>$null
        docker cp "$($containerName):\Program Files (x86)\Microsoft Dynamics NAV" "$path\RoleTailoredClient\Program Files"
        Write-Host "Extracting Configuration packages"
        docker cp "$($containerName):\ConfigurationPackages" "$path" 2>$null
        Write-Host "Extracting Test Assemblies"
        docker cp "$($containerName):\Test Assemblies" "$path" 2>$null
        Write-Host "Extracting Test Toolkit"
        docker cp "$($containerName):\TestToolKit" "$path" 2>$null
        Write-Host "Extracting Upgrade Toolkit"
        docker cp "$($containerName):\UpgradeToolKit" "$path" 2>$null
        Write-Host "Extracting Extensions"
        docker cp "$($containerName):\Extensions" "$path" 2>$null
        Write-Host "Extracting Applications"
        docker cp "$($containerName):\Applications" "$path" 2>$null
        Write-Host "Extracting Applications.$country"
        docker cp "$($containerName):\Applications.$country" "$path" 2>$null

        $customConfigFile = (Get-Item "$path\ServiceTier\program files\Microsoft Dynamics NAV\*\Service\CustomSettings.config").FullName
        [xml]$customConfig = [System.IO.File]::ReadAllText($customConfigFile)
        if ($customConfig.SelectSingleNode("//appSettings/add[@key='Multitenant']").Value -eq "true") {
            Remove-Item -Path $path -Recurse -Force
            throw "Extract-Files cannot be performed on multitenant containers/images, use artifacts"
        }

        $sourceFolder = (Get-Item "$path\ServiceTier\Program Files\Microsoft Dynamics NAV\*\Web Client").FullName
        $destFolder = $sourceFolder.Replace('\Web Client','').Replace('ServiceTier\Program Files','WebClient')
        New-Item -Path $destFolder -ItemType Directory | Out-Null
        Move-Item -Path $sourceFolder -Destination $destFolder

        $sourceItem = Get-Item "$path\ServiceTier\Program Files\Microsoft Dynamics NAV\*\AL Development Environment"
        if ($sourceItem) {
            $sourceFolder = $SourceItem.FullName
            $destFolder = $sourceFolder.Replace('\AL Development Environment','').Replace('ServiceTier\','ModernDev\')
            New-Item -Path $destFolder -ItemType Directory | Out-Null
            Move-Item -Path $sourceFolder -Destination $destFolder
        }
        
        $sourceItem = Get-Item "$path\RoleTailoredClient\Program Files\Microsoft Dynamics NAV\*\ClickOnce Installer Tools"
        if ($sourceItem) {
            $sourceFolder = $SourceItem.FullName
            $destFolder = $sourceFolder.Replace('\ClickOnce Installer Tools','').Replace('\RoleTailoredClient\','\ClickOnceInstallerTools\')
            New-Item -Path $destFolder -ItemType Directory | Out-Null
            Move-Item -Path $sourceFolder -Destination $destFolder
        }
    }
    if ($extract -eq "all" -or $extract -eq "vsix") {
        Write-Host "Extracting Files from Run folder"
        docker cp "$($containerName):\Run" "$path"
    }
    if ($extract -eq "all" -or $extract -eq "database") {
        Write-Host "Extracting Database Files"
        docker cp "$($containerName):\databases" "$path" 2>$null
    }

    if ($extract -eq "all") {
        Write-Host "Downloading prerequisites"
        $ver = [int]((get-childitem "$path\ServiceTier\Program Files\Microsoft Dynamics NAV").Name)
        Download-File -dontOverwrite -sourceUrl "https://download.microsoft.com/download/C/9/E/C9E8180D-4E51-40A6-A9BF-776990D8BCA9/rewrite_amd64.msi" -destinationFile "$path\Prerequisite Components\IIS URL Rewrite Module\rewrite_2.0_rtw_x64.msi"
        Download-File -dontOverwrite -sourceUrl "https://download.microsoft.com/download/5/5/3/553C731E-9333-40FB-ADE3-E02DC9643B31/OpenXMLSDKV25.msi" -destinationFile "$path\Prerequisite Components\Open XML SDK 2.5 for Microsoft Office\OpenXMLSDKv25.msi" 
        if ($ver -eq 90) {
            Download-File -dontOverwrite -sourceUrl "https://download.microsoft.com/download/1/3/0/13089488-91FC-4E22-AD68-5BE58BD5C014/ENU/x86/SQLSysClrTypes.msi" -destinationFile "$path\Prerequisite Components\Microsoft Report Viewer 2015\SQLSysClrTypes.msi"
            Download-File -dontOverwrite -sourceUrl "https://download.microsoft.com/download/A/1/2/A129F694-233C-4C7C-860F-F73139CF2E01/ENU/x86/ReportViewer.msi" -destinationFile "$path\Prerequisite Components\Microsoft Report Viewer 2015\ReportViewer.msi"
        } elseif ($ver -eq 100) {
            Download-File -dontOverwrite -sourceUrl "https://download.microsoft.com/download/1/3/0/13089488-91FC-4E22-AD68-5BE58BD5C014/ENU/x86/SQLSysClrTypes.msi" -destinationFile "$path\Prerequisite Components\Microsoft Report Viewer\SQLSysClrTypes.msi"
            Download-File -dontOverwrite -sourceUrl "https://download.microsoft.com/download/A/1/2/A129F694-233C-4C7C-860F-F73139CF2E01/ENU/x86/ReportViewer.msi" -destinationFile "$path\Prerequisite Components\Microsoft Report Viewer\ReportViewer.msi" 
        } elseif ($ver -ge 110) {
            Download-File -dontOverwrite -sourceUrl "https://go.microsoft.com/fwlink/?LinkID=844461" -destinationFile "$path\Prerequisite Components\DotNetCore\DotNetCore.1.0.4_1.1.1-WindowsHosting.exe"
        }
    }

    Write-Host "Performing cleanup"
    if ($extract -eq "all" -or $extract -eq "database") {
        if (Test-Path "$path\databases\*.mdf") {
            
            Move-Item -Path (Get-Item "$path\databases\*.mdf").FullName -Destination "$path\databases\CRONUS.mdf"
            Move-Item -Path (Get-Item "$path\databases\*.ldf").FullName -Destination "$path\databases\CRONUS.ldf"
        } else {
            $folder = Get-ChildItem -Path "$path\databases" | Where-Object { $_.PSIsContainer }
            if ($folder) {
                $name = $folder.Name
                Move-Item -Path (Get-Item "$path\databases\$Name\*.mdf").FullName -Destination "$path\databases\$name.mdf"
                Move-Item -Path (Get-Item "$path\databases\$Name\*.ldf").FullName -Destination "$path\databases\$name.ldf"
                Remove-Item $folder.FullName -Recurse -Force
            } else {
                docker cp "$($containerName):\Program Files\Microsoft SQL Server\MSSQL13.SQLEXPRESS\MSSQL\DATA" "$path" 2>$null
                docker cp "$($containerName):\Program Files\Microsoft SQL Server\MSSQL14.SQLEXPRESS\MSSQL\DATA" "$path" 2>$null
                docker cp "$($containerName):\Program Files\Microsoft SQL Server\MSSQL15.SQLEXPRESS\MSSQL\DATA" "$path" 2>$null
                $mdffile = Get-Item "$path\DATA\Financials*.mdf"
                if ($mdffile) {
                    $name = $mdffile.Name.SubString(0,$mdffile.Name.IndexOf('_'))
                    Move-Item -Path (Get-Item "$path\DATA\Financials*.mdf").FullName -Destination "$path\databases\$name.mdf"
                    Move-Item -Path (Get-Item "$path\DATA\Financials*.ldf").FullName -Destination "$path\databases\$name.ldf"
                    Remove-Item -path "$path\DATA" -Recurse -Force
                } else {
                    throw "Cannot locate database"
                }
            }
        }
        if (Test-Path "$path\Run\Collation.txt") {
            Move-Item -Path "$path\Run\Collation.txt" -Destination "$path\databases\Collation.txt"
        }
    }
    
    if ($extract -eq "all") {
        Copy-Item -Path "$path\Run\NAVAdministration" -Destination "$path\WindowsPowerShellScripts\Cloud" -Force -Recurse
        if (Test-Path "$path\Run\WebSearch") {
            Copy-Item -Path "$path\Run\WebSearch" -Destination "$path\WindowsPowerShellScripts\Cloud" -Force -Recurse
        }

        if ($ver -lt 150) {
            Copy-Item -Path "$path\Run\ClientUserSettings.config" -Destination "$path\RoleTailoredClient\CommonAppData\Microsoft\Microsoft Dynamics NAV\VER" -Force
        }
        If (Test-Path "$path\Run\inetpub") {
            Copy-Item -Path "$path\Run\inetpub" -Destination "$path\WebClient" -Force -Recurse
        }
    }
    if ($extract -eq "all" -or $extract -eq "vsix") {
        Copy-Item -Path "$path\Run\*.vsix" -Destination "$path" -Force
        Remove-Item -Path "$path\Run" -Recurse -Force
    }
    
    if ($extract -eq "all") {
        New-Item -Path "$path\allextracted" -ItemType File | Out-Null
    }

    $ErrorActionPreference = 'Stop'

    if ($startContainer) {
        Start-BcContainer -containerName $containerName
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
Set-Alias -Name Extract-FilesFromStoppedNavContainer -Value Extract-FilesFromStoppedBcContainer
Export-ModuleMember -Function Extract-FilesFromStoppedBcContainer -Alias Extract-FilesFromStoppedNavContainer

# SIG # Begin signature block
# MIInSQYJKoZIhvcNAQcCoIInOjCCJzYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCABr75jJWhJ7oTF
# /RgTc+/8RbmgtQtR8aYeVua0QXClX6CCDLowggX1MIID3aADAgECAhMzAAACHU0Z
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
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIGkE/+/j
# lIR90MzACW4Aje/aiUsk5e1ir1xvNG3wNFxFMEIGCisGAQQBgjcCAQwxNDAyoBSA
# EgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20w
# DQYJKoZIhvcNAQEBBQAEggEALuKty/MVPx1UbDGyadtb0I30x/gl+u29ulRimtNC
# Tt5O2QQF9g0qsignJdBQmMZ/tXhMmlez/XPz9iHWQTfjK8xZaIDLucvpdlSTDUFn
# ygpS/EF15+CSMvB2WWx4vmPRj2eL/YWzPZpkthwer47txvPDVF/SucfiTHgHd01S
# NsZAMq9e0i9FbDWjV4vPcEfYMOmSerrfZMDT6sN4fe9T4guG+Ogc1JYDQJwpShA3
# aLa8DGBF84bGolmmUQjijpL1Z094DbzelASXmjuXR7Xj1VsYPZztd6Vglgeh6xu/
# bHmI/8PxljRzJVepCUSVuNtV9iMZKJwp15IsWMEkbjDC9aGCF5cwgheTBgorBgEE
# AYI3AwMBMYIXgzCCF38GCSqGSIb3DQEHAqCCF3AwghdsAgEDMQ8wDQYJYIZIAWUD
# BAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGEWQoD
# ATAxMA0GCWCGSAFlAwQCAQUABCAioyT8ms0/933Og6VINWsJ0ZARR1S0Xn+vL0on
# sV5npQIGaoV0MG2mGBMyMDI2MDgyNzA2MzAzOC4zOTFaMASAAgH0oIHRpIHOMIHL
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxN
# aWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRT
# UyBFU046RjAwMi0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFNlcnZpY2WgghHtMIIHIDCCBQigAwIBAgITMwAAAiAk4ebgF7m0jgABAAAC
# IDANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAe
# Fw0yNjAyMTkxOTM5NTJaFw0yNzA1MTcxOTM5NTJaMIHLMQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmlj
# YSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046RjAwMi0wNUUw
# LUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIi
# MA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDRYY7yr7ijW6CR178uKveIMufu
# tWOicxgJwKOce/2GOQceus6ZWfX14i3jNg3JOP7MGJMkOAucwWBwiA8URp+ZYkGj
# pVoVkGZsV27WjqLwpf2AwqBsJ/TzqwE7JFFaxup3Ldxj8GjdJymDFRrdVN/pYHoB
# FrjD1IkIDu8b1CWn8tgomiKRSY+STvJq99mVkdphMBIUGOegQny8qRd24VME0xi8
# Oomks9Zq9EjDeKHGpvAbXUEQ6m3cROoEPhTE/miweQH9TqJt3IOsqPv3L8urojB7
# 47XBC2y0CDIHlKLcLl3ZG8D7JXKnWTFen3msMPJpcvrQ3zUBVJrH/mI3RxHmCh9p
# pDP0uG1+PJwk6H/x+sfoG9hW64xoXkpx6DEfNZNfcXdKbXF28XEXdLNnzo3SLNVy
# meQJhNqOSKhnU84QnKmrjEk541JiurlDCkCWO9lUBUMb9x0nyfXUbNRPVLgP+PTM
# RdXOowJdYCzCQfN2ZqL0s4YI28F1Dbn7Bgw2E4P1E9unsvMzJHtzhS2Th3TpCfBb
# OGalIlF9x/DJZ/ssm/yyzT9YtIFeqmfNxBPTE3aOuh6HxmTICzfYAATvWNhBbo19
# QwsjPeA9JvhqTLC2KUNgrXroGy4eDZo0n7jFYjZkUih1Ty+8E6qEvV2Na6Z5gUyD
# 5a+tHGDmq69CmUiHfwIDAQABo4IBSTCCAUUwHQYDVR0OBBYEFNvInOCIhxGA8mY7
# l1g07UHvyNgzMB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1Ud
# HwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3Js
# L01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggr
# BgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNv
# bS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIw
# MTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgw
# DgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUAA4ICAQCtKGBto1BSvm4WFI+J
# 0NSyVhU1LHL7F3fbjZ2d7F5Kn/FCTBZXpzrDVl63FLRNcIFpnJy4/nlg43r7T5sJ
# Pdo4Ms8ADSHQEJnHSu3x9UpjCzREBPi9+nHhvDgRx/1WmBD6gQUZJLOhcN2TxW4K
# JyhinMtiBFtkNRZ2vmZ1MAdNXTm5d0Lwk3wzj+/f7VCCTWCXJSoqNa3VU/6sACHI
# 97Evbnzg8bd3hxrfz6CcCVuf77egvRHinthJuwSRePP7aVmcevb1nWUIAICdBebH
# QOrzNIeWBIQwvcFaS3SFc+49rqrwQOMFDR4FYBzS7b0QeBVxFuLL2iVu4KAHMNUh
# LLSD4iKLDFBNTOtTzTlhGvMgG77A1cjeQrDMHa6oReMDeUDqHUrxv8g7IRdIh+h0
# gDLkzN0xIuzli0Bv7JtybGJbV6JxaDF4CzSCIMRpK59nI6iKo4LgnbQBZJW7+6ak
# YsKG/pXPlfxNv2InpD10tSCkCvw9kr6W1+NRN+EuZczRgAwWlcK9XJZ3uu/v/oxH
# tO7/kmVIs51F9qV6Y2QNXd6tU46YPrK98m2QDys+lvLNimK0e1xZ7Z1GawKohKGv
# lLALWDlZQqgHfJ31CB0LlIDI7iLyYTpd2iyKjqskbQiyMtICH+RmH/oCg7JOK0ZA
# 3XIMba9aSWgBF3QZ6pG3EGeQqjCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkA
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
# T3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOkYwMDItMDVFMC1E
# OTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEw
# BwYFKw4DAhoDFQCTGA9vpsJ6glqCLmI0rggGx4YEEqCBgzCBgKR+MHwxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29m
# dCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBCwUAAgUA7jnUpzAiGA8y
# MDI2MDgyNjIxMDk1OVoYDzIwMjYwODI3MjEwOTU5WjB3MD0GCisGAQQBhFkKBAEx
# LzAtMAoCBQDuOdSnAgEAMAoCAQACAgVGAgH/MAcCAQACAhISMAoCBQDuOyYnAgEA
# MDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAI
# AgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBAGEKJF7U7jLYB+LK6Qavhn1a4mYS
# K+/lRxcKvC8d2RL5/DUf3ym0prWrMzogTv6ijqKhkmHHU6NFNdCvh9OwoqBI2zVC
# op//YrOSKVQ0cRvfzHUSKs5o4aize4wBsfrzyc6Rahu6APoKGbGOWWZ+AQe8XL/P
# ZMdsfRKdMvHtA90asFuX9FCP4hPDd8iKnOAqOGZWJV2bxXAI9lZksKYdFlFtm3B/
# jxUhLRUT7BR7jXs+A9dSMtt8/L7E8jKy9uteU3k/IybVshCBuZ1SHgYlGeIMA34V
# cLgi93bk4Lwtj8VAISjIEG30qK8fYgN8qne2Ye29lVpTH21nOUULWYdjCMIxggQN
# MIIECQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQ
# MA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
# MSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAiAk
# 4ebgF7m0jgABAAACIDANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0G
# CyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCCWB/vln3IVhH0SqWzWX2ZR61Lx
# f+iYiMwp2idx0SkXBDCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EION7vyOl
# PA1VqlEp0QIVGlNd8S5YWBnKj97LuTWHSO2vMIGYMIGApH4wfDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgUENBIDIwMTACEzMAAAIgJOHm4Be5tI4AAQAAAiAwIgQgjiu1gfdt
# K/nOE0cUc+Y8+y8Y+ptu1I0ru0zk1hD/Vy8wDQYJKoZIhvcNAQELBQAEggIAdXOz
# 6mJVyWmWjhq02qGppdK2GqfempWnR31tu5VNJ3Tbr99xAR/9NKbRshEFX8FwXb1B
# 1FTQs5AwbigEYuE0letI/NoBdhp2AQFGDwmKS2mZLbDIpHQ97m9//PZ+AYaxm/vn
# pxlQLnz57oppUT/hZKsdtOpSYqyE7sxgFk2FwbdGv1Z7JWMMAbBMQsdMmtHjcfS/
# SZ8g3b6iSz74Oz4LVZdXRwjEDv72uRckBreihyzPCR8PcHWqHftrJeecl4a5scwG
# vatv3YT/WgLMxzgu8u2KkDBFlZiVCnc8bmj3HmPgU6x3Q8BhKrQBdHRSmgEEt3gm
# M9SPpu87Vv33oIuzmtTeDcohubAGBDPFsPp7dvlVgD4vKn+X38u+nFJAia+TVrFM
# Qkhzorg9uVNpxENi+T16LhHFSH7dsFNYhTxmgC7t2pFYMp9hPiuOr0T1atHMCU2p
# onYr8TCEsLm3xQNUP0g1S8bHIkQTC46z/HBHL/WNXgyaE/FB7VlY/uHq6+yeywxJ
# F/3IQm0GHlrOWppop8XSru+Hb41epzXFN9jvLCc/YCEx8oQv/rwAr7kqpprrNHnY
# tRa6zSjABYrJ0b2YMAJyBOwKji4X1HgTnclalENFmzxu3zRXOI8lpbRRxyfiaFWk
# Yy4YJajL2BJVih1/xhJDrTjEtgdEz+Z9cD318VM=
# SIG # End signature block
