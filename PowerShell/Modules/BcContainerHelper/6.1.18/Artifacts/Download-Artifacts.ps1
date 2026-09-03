<#
 .Synopsis
  Download Artifacts
 .Description
  Download artifacts from artifacts storage
 .Parameter artifactUrl
  Url for artifact to use.
 .Parameter platformArtifactUrl
  Url for platform artifact to use instead of the platform related to artifactUrl.
 .Parameter includePlatform
  Add this switch to include the platform artifact in the download
 .Parameter force
  Add this switch to force download artifacts even though they already exists
 .Parameter forceRedirection
  Add this switch to force download redirection artifacts even though they already exists
 .Parameter basePath
  Load the artifacts into a file structure below this path. (default is c:\bcartifacts.cache)
 .Parameter timeout
  Timeout in seconds for each file download.
 .Example
  $artifactPaths = Download-Artifacts -artifactUrl $artifactUrl -includePlatform
  $appArtifactPath = $artifactPaths[0]
  $platformArtifactPath = $artifactPaths[1]
 .Example
  $appArtifactPath = Download-Artifacts -artifactUrl $artifactUrl
#>
function Download-Artifacts {
    Param (
        [Parameter(Mandatory=$true)]
        [string] $artifactUrl,
        [string] $platformArtifactUrl = "",
        [switch] $includePlatform,
        [switch] $force,
        [switch] $forceRedirection,
        [string] $basePath = "",
        [int]    $timeout = $bccontainerHelperConfig.artifactDownloadTimeout
    )

    function DownloadPackage {
        Param(
            [string] $artifactUrl,
            [string] $destinationPath,
            [int]    $timeout = 300
        )

        $tmpFolder = Join-Path ([System.IO.Path]::GetDirectoryName($destinationPath)) ([System.IO.Path]::GetRandomFileName())
        $zipFile = Join-Path ([System.IO.Path]::GetTempPath()) "$([Guid]::NewGuid().ToString()).zip"
        $retry = $false
        do {
            Download-File -sourceUrl $artifactUrl -destinationFile $zipFile -timeout $timeout
            Write-Host "Unpacking artifact to tmp folder " -NoNewline
            try {
                Expand-7zipArchive -Path $zipFile -DestinationPath $tmpFolder -use7zipIfAvailable:(!$retry)
                $retry = $false
            }
            catch {
                Remove-Item -path $zipFile -force
                if (Test-Path $tmpFolder) {
                    Remove-Item $tmpFolder -Recurse -Force
                }
                if ($retry) {
                    throw "Error trying to unpack artifact, downloaded package is corrupt"
                }
                else {
                    if ($artifactUrl -match '^https:\/\/(.+)\.azureedge\.net\/(.*)$') {
                        Write-Host "Error unpacking platform artifact downloaded from CDN, retrying download from direct download URL"
                        $artifactUrl = "https://$($Matches[1]).blob.core.windows.net/$($Matches[2])"
                        $retry = $true
                    }
                }
            }
        } while ($retry)
        $result = $false
        try {
            $attempts = 0
            while (!(Test-Path $destinationPath)) {
                try {
                    Rename-Item -Path $tmpFolder -NewName ([System.IO.Path]::GetFileName($destinationPath)) -Force
                    $result = $true
                }
                catch {
                    if ($attempts++ -eq 5) {
                        throw
                    }
                    $waittime = 5*$attempts
                    Write-Host "Could not rename '$tmpFolder' retrying in $waittime seconds."
                    Start-Sleep -Seconds $waittime
                    Write-Host "Retrying..."
                }
            }
        }
        finally {
            if (Test-Path $zipFile) {
                Remove-Item -path $zipFile -force
            }
            if (Test-Path $tmpFolder) {
                Remove-Item $tmpFolder -Recurse -Force
            }
        }
        return $result
    }


$telemetryScope = InitTelemetryScope -name $MyInvocation.InvocationName -parameterValues $PSBoundParameters -includeParameters @("artifactUrl","platformArtifactUrl","includePlatform")
try {

    if ($basePath -eq "") {
        $basePath = $bcContainerHelperConfig.bcartifactsCacheFolder
    }

    if (-not (Test-Path $basePath)) {
        New-Item $basePath -ItemType Directory | Out-Null
    }

    $appMutexName = "dl-$($artifactUrl.Split('?')[0].Substring(8).Replace('/','_'))"
    $appMutex = New-Object System.Threading.Mutex($false, $appMutexName)
    try {
        try {
            if (!$appMutex.WaitOne(1000)) {
                Write-Host "Waiting for other process downloading artifact '$($artifactUrl.Split('?')[0])'"
                $appMutex.WaitOne() | Out-Null
                Write-Host "Other process completed download"
            }
        }
        catch [System.Threading.AbandonedMutexException] {
           Write-Host "Other process terminated abnormally"
        }
        do {
            $redir = $false
            $appUri = [Uri]::new($artifactUrl)
    
            $appArtifactPath = Join-Path $basePath $appUri.AbsolutePath
            $appManifestPath = Join-Path $appArtifactPath "manifest.json"
            $exists = Test-Path $appArtifactPath

            # if the force switch is set, we remove the existing artifact and redownload it
            if ($exists -and $force) {
                Remove-Item $appArtifactPath -Recurse -Force
                $exists = $false
            }

            # If the artifact exists and includePlatform or forceRedirection is set, we also need the manifest file
            if ($exists -and ($includePlatform -or $forceRedirection) -and (-not (Test-Path $appManifestPath))) {
                Remove-Item $appArtifactPath -Recurse -Force
                $exists = $false
            }

            # Test if the manifest file exists and is not corrupt
            if ($exists -and (Test-Path $appManifestPath)) {
                try {
                    Get-Content $appManifestPath | ConvertFrom-Json | Out-Null
                }
                catch {
                    Write-Host "ERROR: Manifest file is corrupt, removing $appArtifactPath and redownloading"
                    Remove-Item $appArtifactPath -Recurse -Force
                    $exists = $false
                }
            }

            if ($exists -and $forceRedirection) {
                $appManifest = Get-Content $appManifestPath | ConvertFrom-Json
                if ($appManifest.PSObject.Properties.name -eq "applicationUrl") {
                    # redirect artifacts are always downloaded
                    Remove-Item $appArtifactPath -Recurse -Force
                    $exists = $false
                }
            }

            if (-not $exists) {
                Write-Host "Downloading artifact $($appUri.AbsolutePath)"
                DownloadPackage -artifactUrl $artifactUrl -destinationPath $appArtifactPath -timeout $timeout | Out-Null
            }
            try { [System.IO.File]::WriteAllText((Join-Path $appArtifactPath 'lastused'), "$([datetime]::UtcNow.Ticks)") } catch {}

            if (Test-Path $appManifestPath) {
                $appManifest = Get-Content $appManifestPath | ConvertFrom-Json

                # Patch wrong license file in ONPREM AU version 20.5.45456.45889
                if ($artifactUrl -like '*/onprem/20.5.45456.45889/au') {
                    Write-Host "INFO: Patching wrong license file in ONPREM AU version 20.5.45456.45889"
                    Download-File -sourceUrl 'https://bcartifacts-exdbf9fwegejdqak.b02.azurefd.net/prerequisites/21demolicense/au/3048953.flf' -destinationFile (Join-Path $appArtifactPath 'database/Cronus.flf')
                }
                
                $cuFixMapping = @{
                    '11.0.48794.0' = 'cu53';
                    '11.0.48962.0' = 'cu54';
                    '11.0.49061.0' = 'cu55';
                    '11.0.49175.0' = 'cu56';
                    '11.0.49240.0' = 'cu57';
                    '11.0.49345.0' = 'cu58';
                    '11.0.49497.0' = 'cu59';
                    '11.0.49618.0' = 'cu60';
                }
                if ($appManifest.version -in $cuFixMapping.Keys) {
                    $appManifest.cu = $cuFixMapping[$appManifest.version]
                    $appManifest | ConvertTo-Json | Set-Content -Path $appManifestPath
                }
        
                if ($appManifest.PSObject.Properties.name -eq "applicationUrl") {
                    $redir = $true
                    $artifactUrl = $appManifest.ApplicationUrl
                    if ($artifactUrl -notlike 'https://*') {
                        $artifactUrl = "https://$($appUri.Host)/$artifactUrl$($appUri.Query)"
                    }
                }
            }
    
        } while ($redir)
    
        $appArtifactPath
    
        if ($includePlatform) {
            if ($platformArtifactUrl) {
                Write-Host "Using separate platformArtifactUrl $($platformArtifactUrl.split('?')[0])"
                $platformUrl = $platformArtifactUrl
            }
            elseif ($appManifest.PSObject.Properties.name -eq "platformUrl") {
                $platformUrl = $appManifest.platformUrl
            }
            else {
                $platformUrl = "$( $appUri.AbsolutePath.Substring(0,$appUri.AbsolutePath.LastIndexOf('/')) )/platform".TrimStart('/')
            }
        
            if ($platformUrl -notlike 'https://*') {
                $platformUrl = "https://$($appUri.Host.TrimEnd('/'))/$platformUrl$($appUri.Query)"
            }
            $platformUri = [Uri]::new($platformUrl)
    
            $PlatformMutexName = "dl-$($platformUrl.Split('?')[0].Substring(8).Replace('/','_'))"
            $PlatformMutex = New-Object System.Threading.Mutex($false, $PlatformMutexName)
            try {
                try {
                    if (!$PlatformMutex.WaitOne(1000)) {
                        Write-Host "Waiting for other process downloading platform artifact '$($platformUrl.Split('?')[0])'"
                        $PlatformMutex.WaitOne() | Out-Null
                        Write-Host "Other process completed download"
                    }
                }
                catch [System.Threading.AbandonedMutexException] {
                   Write-Host "Other process terminated abnormally"
                }
    
                $platformArtifactPath = Join-Path $basePath $platformUri.AbsolutePath
                $exists = Test-Path $platformArtifactPath
                if ($exists -and $force) {
                    Remove-Item $platformArtifactPath -Recurse -Force
                    $exists = $false
                }
                if (-not $exists) {
                    Write-Host "Downloading platform artifact $($platformUri.AbsolutePath)"
                    $downloadprereqs = DownLoadPackage -ArtifactUrl $platformUrl -DestinationPath $platformArtifactPath -timeout $timeout
                    if ($downloadprereqs) {
                        $prerequisiteComponentsFile = Join-Path $platformArtifactPath "Prerequisite Components.json"
                        if (Test-Path $prerequisiteComponentsFile) {
                            $prerequisiteComponents = Get-Content $prerequisiteComponentsFile | ConvertFrom-Json
                            Write-Host "Downloading Prerequisite Components"
                            $prerequisiteComponents.PSObject.Properties | % {
                                $skip = ($_.Name -eq "Prerequisite Components\Open XML SDK 2.5 for Microsoft Office\OpenXMLSDKv25.msi") -and (([System.Version]$appManifest.Version).Major -ge 21)
                                $path = Join-Path $platformArtifactPath $_.Name
                                if ((-not $skip) -and (-not (Test-Path $path))) {
                                    $dirName = [System.IO.Path]::GetDirectoryName($path)
                                    if (-not (Test-Path $dirName)) {
                                        New-Item -Path $dirName -ItemType Directory | Out-Null
                                    }
                                    $url = $_.Value
                                    Download-File -sourceUrl $url -destinationFile $path -timeout $timeout
                                }
                            }
                            $dotnetCoreFolder = Join-Path $platformArtifactPath "Prerequisite Components\DotNetCore"
                            if (!(Test-Path $dotnetCoreFolder)) {
                                New-Item $dotnetCoreFolder -ItemType Directory | Out-Null
                                Download-File -sourceUrl "https://go.microsoft.com/fwlink/?LinkID=844461" -destinationFile (Join-Path $dotnetCoreFolder "DotNetCore.1.0.4_1.1.1-WindowsHosting.exe") -timeout $timeout
                            }
                        }
                        # Patch potential wrong version of Newtonsoft.Json.dll
                        $newtonSoftDllPath = Join-Path $platformArtifactPath 'ServiceTier\program files\Microsoft Dynamics NAV\210\Service\Newtonsoft.Json.dll'
                        if (Test-Path $newtonSoftDllPath) {
                            'Applications\testframework\TestRunner\Internal\Newtonsoft.Json.dll','Test Assemblies\Newtonsoft.Json.dll' | ForEach-Object {
                                $dstFile = Join-Path $platformArtifactPath $_
                                $file = Get-item -Path $dstFile -ErrorAction SilentlyContinue
                                if ($file -and $file.Length -eq 686000) {
                                    Write-Host "INFO: Patching wrong version of Newtonsoft.Json.dll in $dstFile"
                                    Copy-Item -Path $newtonSoftDllPath -Destination $dstFile -Force 
                                }
                            }
                        }
                        $ad1DLL = Join-Path $platformArtifactPath 'Applications\testframework\TestRunner\Internal\Microsoft.IdentityModel.Clients.ActiveDirectory.dll'
                        $ad2DLL = Join-Path $platformArtifactPath 'ServiceTier\*\Microsoft Dynamics NAV\*\Service\Management\Microsoft.IdentityModel.Clients.ActiveDirectory.dll'
                        if ((Test-Path $ad1DLL) -and (Test-Path $ad2DLL)) {
                            if ((Get-Item $ad1DLL).Length -ne (Get-Item $ad2DLL).Length) {
                                Write-Host "INFO: Patching wrong version of Microsoft.IdentityModel.Clients.ActiveDirectory.dll in $ad1DLL"
                            }
                            Copy-Item -Path $ad2DLL -Destination $ad1DLL -Force
                        } 
                    }
                }
                try { [System.IO.File]::WriteAllText((Join-Path $platformArtifactPath 'lastused'), "$([datetime]::UtcNow.Ticks)") } catch {}
                $platformArtifactPath
            }
            finally {
                $platformMutex.ReleaseMutex()
            }
        }
    }
    finally {
        $appMutex.ReleaseMutex()
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
Export-ModuleMember -Function Download-Artifacts
# SIG # Begin signature block
# MIIncQYJKoZIhvcNAQcCoIInYjCCJ14CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCA7eAgtcjZDDhGk
# 0QE895S0dWeChXSE4ie3i0zYW6jWz6CCDMkwggYEMIID7KADAgECAhMzAAACHPrN
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
# Ql0v4q8J/AUmQN5W4n101cY2L4A7GTQG1h32HHAvfQESWP0xghn+MIIZ+gIBATBu
# MFcxCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# KDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMjQCEzMAAAIc
# +s3Fm+gvfsQAAAAAAhwwDQYJYIZIAWUDBAIBBQCgga4wGQYJKoZIhvcNAQkDMQwG
# CisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZI
# hvcNAQkEMSIEIHe/U9yFLiJ/NOuSeRnsyyxoLRDofOazFPoXRT90/CzpMEIGCisG
# AQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEAZDYUg0QRvbcUCMIuif+N
# oGBvVg5lGz29XyhMvSVDmiqdAyCOBhvfMM7ORR2p3dDross1dDePAp6NzQLF8dmA
# SnTbgBUC6TVJqai6C2oFCGg1cXhcv8mkr4ivkYuW1uYyYFLfTPgW+daWV9yRTjOY
# hu5XLY2Ny71Gis+ptioJ6ckBT9jm/IM/+8QeNYd4eY9o/xRE2e+PrulSSfzFb1Qe
# vRO/sECHx9ib3hKCgvskbnuEbaxq6tMqQ9DLWUgAyd0YcTr6G9XOyL8q0hCNlx7U
# 4S5Or6hg0sMEV5qCgktnJBXR7tDjSYgYcJA0fCR1JabRC/obpAovWRssx35oUVkK
# XqGCF7AwghesBgorBgEEAYI3AwMBMYIXnDCCF5gGCSqGSIb3DQEHAqCCF4kwgheF
# AgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFFMIIB
# QQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCAF4FezafVygm07tOT1
# IjPJ5G04nbDemtCF7bZujT1MDwIGaohqFTfxGBMyMDI2MDgyNzA2MjkzNi4xMTNa
# MASAAgH0oIHZpIHWMIHTMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0
# ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjozMjFBLTA1RTAtRDk0NzElMCMG
# A1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaCCEf4wggcoMIIFEKAD
# AgECAhMzAAACGqmgHQagD0OqAAEAAAIaMA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29m
# dCBUaW1lLVN0YW1wIFBDQSAyMDEwMB4XDTI1MDgxNDE4NDgyOFoXDTI2MTExMzE4
# NDgyOFowgdMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTAr
# BgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUG
# A1UECxMeblNoaWVsZCBUU1MgRVNOOjMyMUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxN
# aWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOC
# Ag8AMIICCgKCAgEAmYEAwSTz79q2V3ZWzQ5Ev7RKgadQtMBy7+V3XQ8R0NL8R9mu
# pxcqJQ/KPeZGJTER+9Qq/t7HOQfBbDy6e0TepvBFV/RY3w+LOPMKn0Uoh2/8IvdS
# bJ8qAWRVoz2S9VrJzZpB8/f5rQcRETgX/t8N66D2JlEXv4fZQB7XzcJMXr1puhuX
# bOt9RYEyN1Q3Z7YjRkhfBsRc+SD/C9F4iwZqfQgo82GG4wguIhjJU7+XMfrv4vxA
# FNVg3mn1PoMWGZWio+e14+PGYPVLKlad+0IhdHK5AgPyXKkqAhEZpYhYYVEItHOO
# vqrwukxVAJXMvWA3GatWkRZn33WDJVtghCW6XPLi1cDKiGE5UcXZSV4OjQIUB8vp
# 2LUMRXud5I49FIBcE9nT00z8A+EekrPM+OAk07aDfwZbdmZ56j7ub5fNDLf8yIb8
# QxZ8Mr4RwWy/czBuV5rkWQQ+msjJ5AKtYZxJdnaZehUgUNArU/u36SH1eXKMQGRX
# r/xeKFGI8vvv5Jl1knZ8UqEQr9PxDbis7OXp2WSMK5lLGdYVH8VownYF3sbOiRkx
# 5Q5GaEyTehOQp2SfdbsJZlg0SXmHphGnoW1/gQ/5P6BgSq4PAWIZaDJj6AvLLCdb
# URgR5apNQQed2zYUgUbjACA/TomA8Ll7Arrv2oZGiUO5Vdi4xxtA3BRTQTUCAwEA
# AaOCAUkwggFFMB0GA1UdDgQWBBTwqyIJ3QMoPasDcGdGovbaY8IlNjAfBgNVHSME
# GDAWgBSfpxVdAF5iXYP05dJlpxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1l
# LVN0YW1wJTIwUENBJTIwMjAxMCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsG
# AQUFBzAChlBodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01p
# Y3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMB
# Af8EAjAAMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDAN
# BgkqhkiG9w0BAQsFAAOCAgEA1a72WFq7B6bJT3VOJ21nnToPJ9O/q51bw1bhPfQy
# 67uy+f8x8akipzNL2k5b6mtxuPbZGpBqpBKguDwQmxVpX8cGmafeo3wGr4a8Yk6S
# y09tEh/Nwwlsyq7BRrJNn6bGOB8iG4OTy+pmMUh7FejNPRgvgeo/OPytm4NNrMMg
# 98UVlrZxGNOYsifpRJFg5jE/Yu6lqFa1lTm9cHuPYxWa2oEwC0sEAsTFb69iKpN0
# sO19xBZCr0h5ClU9Pgo6ekiJb7QJoDzrDoPQHwbNA87Cto7TLuphj0m9l/I70gLj
# Eq53SHjuURzwpmNxdm18Qg+rlkaMC6Y2KukOfJ7oCSu9vcNGQM+inl9gsNgirZ6y
# Jk9VsXEsoTtoR7fMNU6Py6ufJQGMTmq6ZCq2eIGOXWMBb79ZF6tiKTa4qami3US0
# mTY41J129XmAglVy+ujSZkHu2lHJDRHs7FjnIXZVUE5pl6yUIl23jG50fRTLQcSt
# dwY/LvJUgEHCIzjvlLTqLt6JVR5bcs5aN4Dh0YPG95B9iDMZrq4rli5SnGNWev5L
# LsDY1fbrK6uVpD+psvSLsNpht27QcHRsYdAMALXM+HNsz2LZ8xiOfwt6rOsVWXoi
# HV86/TeMy5TZFUl7qB59INoMSJgDRladVXeT9fwOuirFIoqgjKGk3vO2bELrYMN0
# QVwwggdxMIIFWaADAgECAhMzAAAAFcXna54Cm0mZAAAAAAAVMA0GCSqGSIb3DQEB
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
# RNGQ8cirOoo6CGJ/2XBjU02N7oJtpQUQwXEGahC0HVUzWLOhcGbyoYIDWTCCAkEC
# AQEwggEBoYHZpIHWMIHTMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0
# ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjozMjFBLTA1RTAtRDk0NzElMCMG
# A1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIa
# AxUA8YrutmKpSrubCaAYsU4pt1Ft8DaggYMwgYCkfjB8MQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1T
# dGFtcCBQQ0EgMjAxMDANBgkqhkiG9w0BAQsFAAIFAO46KEMwIhgPMjAyNjA4Mjcw
# MzA2NDNaGA8yMDI2MDgyODAzMDY0M1owdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA
# 7jooQwIBADAKAgEAAgIK0gIB/zAHAgEAAgISdzAKAgUA7jt5wwIBADA2BgorBgEE
# AYRZCgQCMSgwJjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYag
# MA0GCSqGSIb3DQEBCwUAA4IBAQCYeZUjoB06Gwk5tRRPeIB7nJhW7cAmPddyL9Oa
# lnjkzzpMg515wIOAhFEpo3UJH/4mvcN2FpJ6uEgL0FqsTgnpW8orGSWF1UPql+BN
# 1hERheAi7MVZgJ95zkhe6Q3sSS4kl8k2AOerbm9dlTtBiP37zVHxzIl//0e9Y/ms
# 0Xe+aLWVdSQ0f6pEOUyMl96tQ2hR0EIuCM0opcVC9Uw8tGPYKVVg7cpM+no7T8vu
# 7XJo8MSnxjyj3FxUCjy5FL0tPTtbUTYgVGttng60GGSqQFYFeGwex9jJG17MaYMd
# SKlRrO9ddQk4VdAAOUohSqoE/DC+5yilJNrSg2QomWhCK+M+MYIEDTCCBAkCAQEw
# gZMwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcT
# B1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UE
# AxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAIaqaAdBqAPQ6oA
# AQAAAhowDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0B
# CRABBDAvBgkqhkiG9w0BCQQxIgQg4WT1VYeRKEHeEnRCC7jHTc8uPhpTq8SUG4BD
# xOEIm9EwgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCCdeiHHrbtpKcwB20do
# VU89WHIOH8S7w37uaHcDmemK+zCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1w
# IFBDQSAyMDEwAhMzAAACGqmgHQagD0OqAAEAAAIaMCIEIJvNkMndWUHCC6HXn8+a
# lwCRDhrVLdHuYEv9sLfePL+cMA0GCSqGSIb3DQEBCwUABIICACUTyoc1+KfmB5aa
# cnKNdnzkVbCMM2sv+qAcUM06ED1w/4VoS1hEqYs56IOFjrG0W8+YIdEWHGKiLXD6
# dLwy35xjqA8uDW2rrdeUC5hCbsYXgzjswUhmWh8+TY9xkJ6WZpFVNtKyTQxIXkHN
# tKwOc5sTbAumTQ5JVc0ePRq5zGYqSLLILCBTq2DW56xgRJMYs+MVByQRpC/MA981
# swCS5htYIWzwf5AHgf5biLeKwsd3cUTobNT8Bfm0afr9zfArR62CXAiOl87EYeBu
# a9lGKcHWpjjbsThWTDZu0cTrKC4/F4jmJ/h6PYzUQqHjiFLpMBVO2LKAlmpBLJps
# 6JdxU7U+oT4W1MHeS3h8u7C6Tc9bTqd1+bB2o9D2Oee00LgJzDdZEYJeRr13rvWT
# feCzwcJskRWRRDrA5cLQTkdu3HxjCHcus476ywbjQ02yl+QruereJrF3X/9k+1Un
# 8jI8kkyIlhHaX/8oEQUlbKZUnZI4xme+uirfUoHfUIUr0DdKsWt6XqM49UhODt+y
# CAQ3ASYSMR/UK+Jmlplj6SOCI/1SWNEEzjoKHWT60TX1GEdTiInwGKR3H3jQclh8
# u5bz4j1VbQFCYmbQB6H5l7UpBiVeaUZnIzQ7dPETArnSaBHqPkUmr6cw7/apgAea
# 8jVwcDclLFLXILvDoUXD3mJuSkB9
# SIG # End signature block
