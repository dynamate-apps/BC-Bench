<# 
 .Synopsis
  PROOF OF CONCEPT PREVIEW: Create a new Business Central NuGet Package
 .Description
  Create a new NuGet package containing a Business Central apps
 .Parameter appfile
  App file to include in the NuGet package
 .Parameter countrySpecificAppFiles
  Hashtable with country specific app files (runtime packages) to include in the NuGet package
 .Parameter packageId
  Template to generate the id, replacing {id}, {name} and {publisher} with the values from the app.json file
  The default is '{publisher}.{name}.{id}'
 .Parameter packageVersion
  Version of the NuGet package
  The default is the version number from the app.json file
 .Parameter prereleaseTag
  If this is a prerelease, then you can specify a prerelease tag, which will be appended to the version number of the NuGet package (together with a dash)
 .Parameter packageTitle
  Title of the NuGet package
  The default is the name from the app.json file
 .Parameter packageDescription
  Description of the NuGet package
  The default is the description from the app.json file
  If no description exists in the app.json file, the default is the package title
 .Parameter packageAuthors
  Authors of the NuGet package
  The default is the publisher from the app.json file
 .Parameter githubRepository
  URL to the GitHub repository for the NuGet package
 .Parameter dependencyIdTemplate
  Template to calculate the id of the dependencies
  The template can contain {id}, {name} and {publisher} which will be replaced with the values from the corresponding dependency from app.json
  The default is '{publisher}.{name}.{id}'
 .Parameter dependencyVersionTemplate
  Template to calculate the version field of the dependencies, default is {version}
  The template can contain {version} which will be replaced with the version from the corresponding dependency from app.json
  The template can also contain {major},{minor},{build} and {revision} which will be replaced with the fields from the version
  The template can also contain {major+1},{minor+1},{build+1} and {revision+1} which will be replaced with the fields from the version incremented by 1 
 .Parameter applicationDependencyId
  Id of the application dependency
  The default is 'Microsoft.Application'
 .Parameter applicationDependency
  Version/Template of the application dependency, default is the Application version from the app.json file
  The template can contain {version} which will be replaced with the version from the corresponding dependency from app.json
  The template can also contain {major},{minor},{build} and {revision} which will be replaced with the fields from the version
  The template can also contain {major+1},{minor+1},{build+1} and {revision+1} which will be replaced with the fields from the version incremented by 1 
 .Parameter platformDependencyId
  Id of the platform dependency
  The default is 'Microsoft.Platform'
 .Parameter platformDependency
  Version/Template of the platform dependency, default is the Platform version from the app.json file
  The template can contain {version} which will be replaced with the version from the corresponding dependency from app.json
  The template can also contain {major},{minor},{build} and {revision} which will be replaced with the fields from the version
  The template can also contain {major+1},{minor+1},{build+1} and {revision+1} which will be replaced with the fields from the version incremented by 1 
 .Parameter destinationFolder
  Folder to create the NuGet package in. Default it to create a temporary folder and delete it after the NuGet package has been created
 .Example
  $package = New-BcNuGetPackage -appfile "C:\Users\freddyk\Downloads\MyBingMaps-main-Apps-1.0.3.0\Freddy Kristiansen_BingMaps.PTE_4.4.3.0.app"
 .Example
  $package = New-BcNuGetPackage -appfile $appfile -packageId "AL-Go-{id}" -dependencyIdTemplate "AL-Go-{id}"
#>
Function New-BcNuGetPackage {
    Param(
        [Parameter(Mandatory=$true)]
        [alias('appFiles')]
        [string] $appfile,
        [Parameter(Mandatory=$false)]
        [hashtable] $countrySpecificAppFiles = @{},
        [Parameter(Mandatory=$false)]
        [string] $packageId = "{publisher}.{name}.{id}",
        [Parameter(Mandatory=$false)]
        [System.Version] $packageVersion = $null,
        [Parameter(Mandatory=$false)]
        [string] $prereleaseTag = '',
        [Parameter(Mandatory=$false)]
        [string] $packageTitle = "",
        [Parameter(Mandatory=$false)]
        [string] $packageDescription = "",
        [Parameter(Mandatory=$false)]
        [string] $packageAuthors = "",
        [Parameter(Mandatory=$false)]
        [string] $githubRepository = "",
        [Parameter(Mandatory=$false)]
        [string] $dependencyIdTemplate = '{publisher}.{name}.{id}',
        [Parameter(Mandatory=$false)]
        [string] $dependencyVersionTemplate = '{version}',
        [Parameter(Mandatory=$false)]
        [string] $applicationDependencyId = 'Microsoft.Application',
        [Parameter(Mandatory=$false)]
        [string] $applicationDependency = '',
        [Parameter(Mandatory=$false)]
        [string] $platformDependencyId = 'Microsoft.Platform',
        [Parameter(Mandatory=$false)]
        [string] $platformDependency = '',
        [Parameter(Mandatory=$false)]
        [string] $runtimeDependencyId = '{publisher}.{name}.runtime-{version}',
        [switch] $isIndirectPackage,
        [Parameter(Mandatory=$false)]
        [string] $destinationFolder = '',
        [obsolete('NuGet Dependencies are always included.')]
        [switch] $includeNuGetDependencies
    )

    function CopyFileToStream([string] $filename, [System.IO.Stream] $stream) {
        $bytes = [System.IO.File]::ReadAllBytes($filename)
        $stream.Write($bytes,0,$bytes.Length)
    }

    function GetDependencyVersionStr([string] $template, [System.Version] $version) {
        return $template.Replace('{version}',"$version").Replace('{major}',$version.Major).Replace('{minor}',$version.Minor).Replace('{build}',$version.Build).Replace('{revision}',$version.Revision).Replace('{major+1}',($version.Major+1)).Replace('{minor+1}',($version.Minor+1)).Replace('{build+1}',($version.Build+1)).Replace('{revision+1}',($version.Revision+1))
    }

    Write-Host "Create NuGet package"
    Write-Host "AppFile:"
    Write-Host $appFile
    if (!(Test-Path $appFile)) {
        throw "Unable to locate file: $_"
    }
    $appFile = (Get-Item $appfile).FullName
    if ($destinationFolder) {
        $rootFolder = $destinationFolder
    }
    else {
        $rootFolder = Join-Path ([System.IO.Path]::GetTempPath()) ([GUID]::NewGuid().ToString())
    }
    if (Test-Path $rootFolder) {
        if (Get-ChildItem -Path $rootFolder) {
            throw "Destination folder is not empty"
        }
    }
    else {
        New-Item -Path $rootFolder -ItemType Directory | Out-Null
    }
    try {
        if (!$isIndirectPackage.IsPresent) {
            Copy-Item -Path $appFile -Destination $rootFolder -Force
            if ($countrySpecificAppFiles) {
                foreach($country in $countrySpecificAppFiles.Keys) {
                    $countrySpecificAppFile = $countrySpecificAppFiles[$country]
                    if (!(Test-Path $countrySpecificAppFile)) {
                        throw "Unable to locate file: $_"
                    }
                    $countryFolder = Join-Path $rootFolder $country 
                    New-Item -Path $countryFolder -ItemType Directory | Out-Null
                    Copy-Item -Path $countrySpecificAppFile -Destination $countryFolder -Force
                }
            }
        }
        $appJson = Get-AppJsonFromAppFile -appFile $appFile
        $packageId = Get-BcNuGetPackageId -packageIdTemplate $packageId -publisher $appJson.publisher -name $appJson.name -id $appJson.id -version $appJson.version.replace('.','-')
        if ($null -eq $packageVersion) {
            $packageVersion = [System.Version]$appJson.version
        }
        if (-not $packageTitle) {
            $packageTitle = $appJson.name
        }
        if (-not $packageDescription) {
            $packageDescription = $appJson.description
            if (-not $packageDescription) {
                $packageDescription = $packageTitle
            }
        }
        if (-not $packageAuthors) {
            $packageAuthors = $appJson.publisher
        }
        if ($appJson.PSObject.Properties.Name -eq 'Application' -and $appJson.Application) {
            if (-not $applicationDependency) {
                $applicationDependency = $appJson.Application
            }
            else {
                $applicationDependency = GetDependencyVersionStr -template $applicationDependency -version ([System.Version]::Parse($appJson.Application))
            }
        }
        elseif ($applicationDependency.Contains('{')) {
            $applicationDependency = ''
        }
        if ($appJson.PSObject.Properties.Name -eq 'Platform' -and $appJson.Platform) {
            if (-not $platformDependency) {
                $platformDependency = $appJson.Platform
            }
            else {
                $platformDependency = GetDependencyVersionStr -template $platformDependency -version ([System.Version]::Parse($appJson.Platform))
            }
        }
        elseif ($platformDependency.Contains('{')) {
            $platformDependency = ''
        }

        if ($prereleaseTag) {
            $packageVersionStr = "$($packageVersion)-$prereleaseTag"
        }
        else {
            $packageVersionStr = "$packageVersion"
        }
        $nuPkgFileName = "$($packageId)-$($packageVersionStr).nupkg"
        $nupkgFile = Join-Path ([System.IO.Path]::GetTempPath()) $nuPkgFileName
        if (Test-Path $nuPkgFile -PathType Leaf) {
            Remove-Item $nupkgFile -Force
        }
        $nuspecFileName = Join-Path $rootFolder "manifest.nuspec"
        $xmlObjectsettings = New-Object System.Xml.XmlWriterSettings
        $xmlObjectsettings.Indent = $true
        $xmlObjectsettings.IndentChars = "    "
        $xmlObjectsettings.Encoding = [System.Text.Encoding]::UTF8
        $XmlObjectWriter = [System.XML.XmlWriter]::Create($nuspecFileName, $xmlObjectsettings)
        $XmlObjectWriter.WriteStartDocument()
        $XmlObjectWriter.WriteStartElement("package", "http://schemas.microsoft.com/packaging/2010/07/nuspec.xsd")
        $XmlObjectWriter.WriteStartElement("metadata")
        $XmlObjectWriter.WriteElementString("id", $packageId)
        $XmlObjectWriter.WriteElementString("version", $packageVersionStr)
        $XmlObjectWriter.WriteElementString("title", $packageTitle)
        $XmlObjectWriter.WriteElementString("description", $packageDescription)
        $XmlObjectWriter.WriteElementString("authors", $packageAuthors)
        if ($githubRepository) {
            $XmlObjectWriter.WriteStartElement("repository")
            $XmlObjectWriter.WriteAttributeString("type", "git");
            $XmlObjectWriter.WriteAttributeString("url", $githubRepository)
            $XmlObjectWriter.WriteEndElement()
        }
        if ($dependencyIdTemplate) {
            $XmlObjectWriter.WriteStartElement("dependencies")
            if ($appJson.PSObject.Properties.Name -eq 'dependencies') {
                $appJson.dependencies | ForEach-Object {
                    if ($_.PSObject.Properties.name -eq 'id') {
                        $dependencyId = $_.id
                    } else {
                        $dependencyId = $_.appId
                    }
                    $id = Get-BcNuGetPackageId -packageIdTemplate $dependencyIdTemplate -publisher $_.publisher -name $_.name -id $dependencyId -version $_.version.replace('.','-')
                    $XmlObjectWriter.WriteStartElement("dependency")
                    $XmlObjectWriter.WriteAttributeString("id", $id)
                    $XmlObjectWriter.WriteAttributeString("version", (GetDependencyVersionStr -template $dependencyVersionTemplate -version ([System.Version]::Parse($_.version))))
                    $XmlObjectWriter.WriteEndElement()
                }
            }
            if ($applicationDependency) {
                $XmlObjectWriter.WriteStartElement("dependency")
                $XmlObjectWriter.WriteAttributeString("id", $applicationDependencyId)
                $XmlObjectWriter.WriteAttributeString("version", $applicationDependency)
                $XmlObjectWriter.WriteEndElement()
            }
            if ($platformDependency) {
                $XmlObjectWriter.WriteStartElement("dependency")
                $XmlObjectWriter.WriteAttributeString("id", $platformDependencyId)
                $XmlObjectWriter.WriteAttributeString("version", $platformDependency)
                $XmlObjectWriter.WriteEndElement()
            }
            if ($isIndirectPackage.IsPresent) {
                $XmlObjectWriter.WriteStartElement("dependency")
                $id = Get-BcNuGetPackageId -packageIdTemplate $runtimeDependencyId -publisher $appJson.publisher -name $appJson.name -id $appJson.id -version $appJson.version.replace('.','-')
                $XmlObjectWriter.WriteAttributeString("id", $id)
                $XmlObjectWriter.WriteAttributeString("version", '1.0.0.0')
                $XmlObjectWriter.WriteEndElement()
            }
            $XmlObjectWriter.WriteEndElement()
        }
        $XmlObjectWriter.WriteEndElement()
        if (!$isIndirectPackage.IsPresent) {
            $XmlObjectWriter.WriteStartElement("files")
            $XmlObjectWriter.WriteStartElement("file")
            $appFileName = [System.IO.Path]::GetFileName($appfile)
            $XmlObjectWriter.WriteAttributeString("src", $appFileName );
            $XmlObjectWriter.WriteAttributeString("target", $appFileName);
            $XmlObjectWriter.WriteEndElement()
            if ($countrySpecificAppFiles) {
                foreach($country in $countrySpecificAppFiles.Keys) {
                    $countrySpecificAppFile = $countrySpecificAppFiles[$country]
                    $XmlObjectWriter.WriteStartElement("file")
                    $appFileName = Join-Path $country ([System.IO.Path]::GetFileName($countrySpecificAppFiles[$country]))
                    $XmlObjectWriter.WriteAttributeString("src", $appFileName );
                    $XmlObjectWriter.WriteAttributeString("target", $appFileName);
                    $XmlObjectWriter.WriteEndElement()
                }
            }
            $XmlObjectWriter.WriteEndElement()
        }
        $XmlObjectWriter.WriteEndElement()
        $XmlObjectWriter.WriteEndDocument()
        $XmlObjectWriter.Flush()
        $XmlObjectWriter.Close()
        
        Write-Host "NUSPEC file:"
        Get-Content -path $nuspecFileName -Encoding UTF8 | Out-Host
        $nuPkgFileName = "$($packageId)-$($packageVersion).nupkg"
        $nupkgFile = Join-Path ([System.IO.Path]::GetTempPath()) $nuPkgFileName
        if (Test-Path $nuPkgFile -PathType Leaf) {
            Remove-Item $nupkgFile -Force
        }
        if (Test-Path "$nupkgFile.zip" -PathType Leaf) {
            Remove-Item "$nupkgFile.zip" -Force
        }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory("$rootFolder", "$nupkgFile.zip", [System.IO.Compression.CompressionLevel]::Optimal, $false)
        Rename-Item -Path "$nupkgFile.zip" -NewName $nuPkgFileName
        
        $size = (Get-Item $nupkgFile).Length
        if ($size -gt 1MB) {
            $sizeStr = "$([int]($size/1MB))Mb"
        }
        elseif ($size -gt 1KB) {
            $sizeStr = "$([int]($size/1KB))Kb"
        }
        else {
            $sizeStr = "$size bytes"
        }
        Write-Host -ForegroundColor Green "Successfully created NuGet package (Size: $sizeStr)"
        $nupkgFile
    }
    finally {
        if ($destinationFolder -ne $rootFolder) {
            Remove-Item -Path $rootFolder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
Export-ModuleMember -Function New-BcNuGetPackage

# SIG # Begin signature block
# MIInSQYJKoZIhvcNAQcCoIInOjCCJzYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDo3y62xLUay5EZ
# KTlXVrDgOrpwvIJhYomuCy919UWYEaCCDLowggX1MIID3aADAgECAhMzAAACHU0Z
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
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIFjK2Zup
# s3bBqcaxSIfO1lB4yL5dxuBZM7sJyPi120n+MEIGCisGAQQBgjcCAQwxNDAyoBSA
# EgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20w
# DQYJKoZIhvcNAQEBBQAEggEAJtnOKo087EAG8BvqVKsEXHFvhxuemk0hfhy4blbA
# FjlmPEx68G68GKNXqI4Ngqb+VUbsH/an5CbJQ89bMIDGJMv7MVsM09+j0n9Pw1/+
# 01sPAsMYOHEB9Ds+I6LbbpEEBsPPMCouIj+eDAmAOuybtvAQnUtLNxcewtyz9KJ0
# KaDMEeDdIE2HFdIqqEFzv/3FV9xxtFDM1Vu53YXI+G9yLRE6hY2PM53AzwU3nY0r
# b1UjMe3QJviAvAmy/ONBuoStzptA/KDXUmh1JR6XsTP9RSQXP32PXRuIY9MlZomI
# 75CVh5vEwANP9RZSMAZn+lan7HwQf2SHOpg9PyQ8HtDbLKGCF5cwgheTBgorBgEE
# AYI3AwMBMYIXgzCCF38GCSqGSIb3DQEHAqCCF3AwghdsAgEDMQ8wDQYJYIZIAWUD
# BAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGEWQoD
# ATAxMA0GCWCGSAFlAwQCAQUABCDyrzwjo72LRICruuIGOGI2o5i3fYPTwSHe34AI
# ojrG8QIGaoTyJFEPGBMyMDI2MDgyNzA2MzAzOC43OTRaMASAAgH0oIHRpIHOMIHL
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxN
# aWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRT
# UyBFU046REMwMC0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFNlcnZpY2WgghHtMIIHIDCCBQigAwIBAgITMwAAAiQ7hCGwLKxkIgABAAAC
# JDANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAe
# Fw0yNjAyMTkxOTM5NTlaFw0yNzA1MTcxOTM5NTlaMIHLMQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmlj
# YSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046REMwMC0wNUUw
# LUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIi
# MA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCj6W3UaQ2Zr4hNvSy7j7UMPFVy
# s7aExGB+JFwykzzXg3jayYm9gOLXJ7tNhU2emhrLQCOZcgLvz6FkqmghzQxzmkgK
# tLYiKaEzhogO/ce0lThdLNdVtMwQOYgo+XtXAZcViBX4LcHk38RusZiF7wxSa5t/
# Lxic04+Z/hly1gJQpIeFDqp4a9PuLt8rsfH05vW9pU9uriGdDxfJXn/lc49CxbXq
# A3EX17L24bc6t+mFuPDAJKKpai3XXqF2nJlpTPfdrA29sWTSNKig9CtBC5tzQj0f
# lbsa/4wqO9u+RkuwpZb3b7qnW5FdFrDR1vQmXfjlyUP9ZO38839NwSuiHtvsFCNk
# TNIX8OL5XVq1nsKyu//GeIZ9YuxsfLBedqG024PDERyrAs0pvfUWOLapVQajHPoC
# nuNSKvbEh7s5IQ0YgupGji+H7rIDx2/mIEI+6Q8WwBtk3Yxyhjj0GXw909i0EkTk
# Vyy+1yADjwSC8bw2qM4+Mc4hyytlZzSc0IPUBq1YGnYwCjIwa5/lMW0pFn/HpJdB
# 6XeMuTtYTOpaPoo64FjQryLXWjd4ovpw5lOw7X+v3E9kwN9VBC+wJESBECC1gZMC
# S5TaVwfE1w4pnXXb1qT9bjgRsPg4dklruUTdon/3SNt0a0Q5Nc2Ul+rMlQxXoP9i
# sXwMNnKO5JJkqRDRVQIDAQABo4IBSTCCAUUwHQYDVR0OBBYEFHMfkX1u/zJLCMe0
# gqYitx1tAHeoMB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1Ud
# HwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3Js
# L01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggr
# BgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNv
# bS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIw
# MTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgw
# DgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUAA4ICAQA+wHSbmhIpM8CRVZ4t
# k624hQ+LdZXE4qoeQui77CeNa3jq1FOzi7MRKkko6diEDHXPNWvAagxastCewPzm
# 5TCNh1s4qCHh4R2G/r48wU/Mpc68/WDmJy5CIQn/Fwps1sbNUEu7Bzg004qULIVJ
# 963jo/am4xwKgwh+vSVL7/dhsfT7dvhpRddbYLQTHZgwuNB6QhcEEsgogLVwNRj3
# 7VEWZDiwoMdxyC7YYrQu6MCVtizHnOtkSX7FqIoi6jlcfqfo619uDH9r8k2qAOHC
# eEAqKXKymIXDMcGGlEdDFbYiDZgPCBM0IHgAeilUSon07wjHu0e0ssBmtBafPb4G
# d+5FuRnWG3XGe91NCpLKqmFa/4GkVz9OMzZUg8oczxC/4JT3Hf45JEtszToXwNsk
# V3JNCcu2IItr6SJHmi3EDVADDRSNhdzFRpYmplGElPl5GRoPtJiDEvRIbv5MFKIw
# 2x9gnehf5IvBjC4ZkBg+4GTpqGE3mmnzF3nIekOkX4ug0/0mN2CSarhuSi9NmHIO
# pUN2eQHUtgTb/+Gmq7gktCMwIq/JOCYIiTYqpv1objAGKdWMPCrlSyNAs0jZYzkh
# a535158NMx+wBGvsfFoVsCMG5Ocp6vW6CXyuWRbUVqMU1OrQbHfdyzJpbhJC1PbA
# ZIyJCbN+VBgDTAzTKY8w4ISSwTCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkA
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
# T3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOkRDMDAtMDVFMC1E
# OTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEw
# BwYFKw4DAhoDFQCmCPHbmseASfe//bGtX9eQG+0+46CBgzCBgKR+MHwxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29m
# dCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBCwUAAgUA7jn7TTAiGA8y
# MDI2MDgyNjIzNTQ1M1oYDzIwMjYwODI3MjM1NDUzWjB3MD0GCisGAQQBhFkKBAEx
# LzAtMAoCBQDuOftNAgEAMAoCAQACAgNXAgH/MAcCAQACAhNjMAoCBQDuO0zNAgEA
# MDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAI
# AgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBADYf9r4rRYdNkQCMgTffgv/zMMez
# gC+udgVjvTc4fRPmo/vFo0//JN3WUhHJoOc8xrH/AVz/ojC8ewtndfZY2wTA4QNZ
# oVIWtI7ax0pJNdg86vbelmkpcbG9ccodUgZlC4rx4MBpGiIdLoa8LvbjQe3xTqlk
# je155Kf5ELczpCXM4bg8QLTp9qoliiMc7iY2bReAmxF01UqawYKej8pUPZVESCdU
# 3K+5+T4NWnR9eRXqZtsMw9zr8ca0E7gLF0pid9vl59nXpqgmA3OHI9rC4SmCaXTl
# oPBPHnrz1jWEjcjBGkyE7O3MU7J7IETAh7xFlxv2hx1aTYLLFw38Q/WwrdsxggQN
# MIIECQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQ
# MA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
# MSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAiQ7
# hCGwLKxkIgABAAACJDANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0G
# CyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCCJltOBFxaBza/htq2jclVPeJTJ
# 36kCLKn/dLv5eTSW3jCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EIEghPTdq
# m/dRyZ0BczXcdloVEqICdcmpVNbH9CEVzWSOMIGYMIGApH4wfDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgUENBIDIwMTACEzMAAAIkO4QhsCysZCIAAQAAAiQwIgQgdM6yKxDm
# Mlo8IWk8ftXTEH/Rd0mP598nQt1o4w7Jx5cwDQYJKoZIhvcNAQELBQAEggIAVFxy
# CoRmP/9AH8QLyhi2OMCcOXutCqtMHZimIEAWuWA1V+fmv5Gs6RaLHYXZeiBkHTA4
# lee9ZkPmdWeV3CrWmT3WhosM4FZGLQyh+t02xBC6mrxyp8rF406Q5d3IDWApmx5c
# /4CzR/XmlmK47RNP9RwIXJbypjMA69oKU7tjiNYQVQjC+hX20xiTNgtnLNbJpH4k
# LO1ShyL4O7MNDnQSPWTY61mXiYRjyDDKBrXgIaMvvN5PKFUx0iYdGfAIQGCtUON7
# W7LlOvMeKUXTIXZuMbAt/UmOFaebHilgZgRFNoOFIWi8OgfgHy1uEqGdo22jdlx2
# LsFIl1hMOdAGWIxcDkKiF+p7gp7C+5tvIX2SPOU98IoPsPAsWoe5NHs0DbjTnA5f
# zJcxmwXlwNVf2l/0Z9+OWWv9wVkKbwWG9WpwpwX7QON717av6dYqwfffVCdxoeW4
# hEiuIhDIvdN9GPpwFcqoUY0BPeZaN1ktuajrS7qnuH2sRMwxx3uGqCXtdXpssFgl
# sWCflx9xKFrdYOYk87IJ205MqF6Xzpz4h9cIRdmv8N5uT1yIyYUejYPOl3CHbWa/
# BV07Kf2aIEdkt8TPwWc+KUIlGthHHRsaY8BGBPPeXpSz/8UznBmhXI8cAkT+c6bz
# 2/g9acc1gFksfLTmO+sGFQbxvgkF3QmuV4iAPp0=
# SIG # End signature block
