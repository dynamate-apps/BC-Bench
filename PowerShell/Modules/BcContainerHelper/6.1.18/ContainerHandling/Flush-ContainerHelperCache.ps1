<# 
 .Synopsis
  Flush Caches used in ContainerHelper
 .Description
  Extract all files from a Container Image necessary to start a generic container with these files
 .Parameter cache
  Specify which cache you want to flush (default is all)
  - calSourceCache is the C/AL Source Cache
  - alSourceCache is the AL Source Cache
  - filesCache is the files extracted from other images
  - applicationCache are the test applications runtime cache (15.x containers)
  - bakFolderCache are version specific backup sets
  - bcartifacts are artifacts downloaded for spinning up containers
  - bcnuget are nuget packages downloaded to nuget cache
  - sandboxartifacts are artifacts downloaded for spinning up containers
  - images are images built on artifacts using New-BcImage or New-BcContainer
  - compilerFolders are folders used for Dockerless builds
  - exitedContainers are containers which have been stopped
  - all is all of the above (except for exited Containers)
 .Parameter keepDays
  When specifying a value in keepDays, the function will try to keep cached information, which has been used during the last keepDays days. Default is 0 - to flush all cache.
 .Example
  Flush-ContainerHelperCache -cache calSourceCache
#>
function Flush-ContainerHelperCache {
    [CmdletBinding()]
    Param (
        [string] $cache = 'all',
        [int] $keepDays = 0
    )

$telemetryScope = InitTelemetryScope -name $MyInvocation.InvocationName -parameterValues $PSBoundParameters -includeParameters @()
try {

    $flushMutexName = "FlushContainerHelperCache"
    $flushMutex = New-Object System.Threading.Mutex($false, $flushMutexName)
    try {
        try {
            if (!$flushMutex.WaitOne(1000)) {
                Write-Host "Waiting for other process flushing cache"
                $flushMutex.WaitOne() | Out-Null
                Write-Host "Other process completed flushing"
            }
        }
        catch [System.Threading.AbandonedMutexException] {
           Write-Host "Other process terminated abnormally"
        }

        $artifactsCacheFolder = $bcContainerHelperConfig.bcartifactsCacheFolder
        $caches = $cache.ToLowerInvariant().Split(',')
    
        if ($caches.Contains('exitedcontainers')) {
            docker container ls --format "{{.ID}}:{{.Names}}" --no-trunc -a --filter "status=exited" | ForEach-Object {
                $containerID = $_.Split(':')[0]
                $containerName = $_.Split(':')[1]
                $inspect = docker inspect $containerID | ConvertFrom-Json
                try {
                    if ($inspect.state.FinishedAt -is [datetime]) {
                        $finishedAt = $inspect.state.FinishedAt
                    }
                    else {
                        $finishedAt = [DateTime]::Parse($inspect.state.FinishedAt)
                    }
                    $exitedDaysAgo = [DateTime]::Now.Subtract($finishedAt).Days
                    if ($exitedDaysAgo -ge $keepDays) {
                        if (($inspect.Config.Labels.psobject.Properties.Match('maintainer').Count -ne 0 -and $inspect.Config.Labels.maintainer -eq "Dynamics SMB")) {
                            if ($caches.Contains('algocontainersonly')) {
                                if ($inspect.Config.Labels.psobject.Properties.Match('creator').Count -ne 0 -and $inspect.Config.Labels.creator -eq "AL-Go") {
                                    Write-Host "Removing AL-Go container $containerName"
                                    docker rm $containerID -f
                                } 
                                else {
                                    Write-Host "Container $containerName (exited $exitedDaysAgo day$(if($exitedDaysAgo -ne 1){'s'}) ago) is recognized as a Business Central Container, but was not created by AL-Go - not removing"
                                }
                            } 
                            else {
                                Write-Host "Removing container $containerName"
                                docker rm $containerID -f
                            }   
                        }
                        else {
                            Write-Host "Container $containerName (exited $exitedDaysAgo day$(if($exitedDaysAgo -ne 1){'s'}) ago) is not recognized as a Business Central Container - not removing"
                        }
                    }
                    else {
                        Write-Host "Keeping container $containerName (exited $exitedDaysAgo day$(if($exitedDaysAgo -ne 1){'s'}) ago) - removing after $keepDays day$(if($keepDays -ne 1){'s'})"
                    }
                }
                catch {
                    # ignore any errors
                }
            }
        }

        $folders = @()
        if ($caches.Contains('all') -or $caches.Contains('calSourceCache')) {
            $folders += @("extensions\original-*-??","extensions\original-*-??-newsyntax")
        }
    
        if ($caches.Contains('all') -or $caches.Contains('filesCache')) {
            $folders += @("*-??-files")
        }
    
        if ($caches.Contains('all') -or $caches.Contains('bcartifacts') -or $caches.Contains('sandboxartifacts')) {
            $subfolder = "*"
            if (!($caches.Contains('all') -or $caches.Contains('bcartifacts'))) {
                $subfolder = "sandbox"
            }
            if (Test-Path $artifactsCacheFolder) {
                if ($keepDays) {
                    $removeBefore = [DateTime]::Now.Subtract([timespan]::FromDays($keepDays))
                    Get-ChildItem -Path $artifactsCacheFolder | Where-Object { $_.PSIsContainer -and $_.Name -like $subfolder } | ForEach-Object {
                        $level1 = $_.FullName
                        Get-ChildItem -Path $level1 | ?{ $_.PSIsContainer } | ForEach-Object {
                            $level2 = $_.FullName
                            Get-ChildItem -Path $level2 | ?{ $_.PSIsContainer } | ForEach-Object {
                                $level3 = $_.FullName
                                $lastUsedFileName = Join-Path $level3 "LastUsed"
                                if (Test-Path $lastUsedFileName) {
                                    $lastUsedFile = Get-Item $lastUsedFileName
                                    if ($lastUsedFile.LastWriteTime -lt $removeBefore) {
                                        Write-Host "Removing $level3"
                                        Remove-Item $level3 -Recurse -Force
                                    }
                                }
                            }
                            if (-not (Get-ChildItem -Path $level2)) {
                                Remove-Item $level2 -Force
                            }
                        }
                        if (-not (Get-ChildItem -Path $level1)) {
                            Remove-Item $level1 -Force
                        }
                    }
                }
                else {
                    Get-ChildItem -Path $artifactsCacheFolder | ?{ $_.PSIsContainer -and $_.Name -like $subfolder } | ForEach-Object {
                        Write-Host "Removing Cache $($_.FullName)"
                        [System.IO.Directory]::Delete($_.FullName, $true)
                    }
                }
            }
        }
    
        if ($caches.Contains('all') -or $caches.Contains('alSourceCache')) {
            $folders += @("extensions\original-*-??-al")
        }
    
        if ($caches.Contains('all') -or $caches.Contains('applicationCache')) {
            $folders += @("extensions\applications-*-??","extensions\sandbox-applications-*-??","extensions\onprem-applications-*-??")
        }

        if ($caches.Contains('all') -or $caches.Contains('compilerFolders')) {
            # Remove CompilerFolders created 24h ago or earlier
            Push-Location -path $bcContainerHelperConfig.hostHelperFolder
            $compilerPath = Join-Path $bcContainerHelperConfig.hostHelperFolder 'compiler'
            if (Test-Path $compilerPath) {
                $removeBefore = [DateTime]::UtcNow.AddDays(-$keepDays)
                $folders += @(Get-ChildItem -Path $compilerPath | Where-Object { $_.PSIsContainer } | Where-Object { $_.CreationTimeUtc -lt $removeBefore } | ForEach-Object { Resolve-Path $_.FullName -Relative })
            }
            Pop-Location
        }

        if ($caches.Contains('all') -or $caches.Contains('bakFolderCache')) {
            $folders += @("sandbox-*-bakfolders","onprem-*-bakfolders")
        }
    
        $folders | ForEach-Object {
            $folder = Join-Path $bcContainerHelperConfig.hostHelperFolder $_
            Get-Item $folder -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer } | ForEach-Object {
                Write-Host "Removing Cache $($_.FullName)"
                [System.IO.Directory]::Delete($_.FullName, $true)
            }
        }
    
        if (($caches.Contains('all') -or $caches.Contains('bcnuget')) -and ($bcContainerHelperConfig.BcNuGetCacheFolder) -and (Test-Path $bcContainerHelperConfig.BcNuGetCacheFolder)) {
            Get-ChildItem -Path $bcContainerHelperConfig.BcNuGetCacheFolder | Where-Object { $_.PSIsContainer } | ForEach-Object {
                Get-ChildItem -Path $_.FullName | ForEach-Object {
                    $lastWrite = $_.LastWriteTime
                    if ($keepDays -eq 0 -or $lastWrite -lt (Get-Date).AddDays(-$keepDays)) {
                        Write-Host "Remove $($_.FullName.SubString($bcContainerHelperConfig.BcNuGetCacheFolder.Length+1))"
                        Remove-Item -Path $_.FullName -Recurse -Force
                    }
                }
            }
        }

        if ($caches.Contains('all') -or $caches.Contains('images')) {
            $bestGenericImageName = Get-BestGenericImageName
            $allImages = @(docker images --no-trunc --format "{{.Repository}}:{{.Tag}}|{{.ID}}")
            $bestGenericImage = $allImages | Where-Object { $_.Split('|')[0] -eq $bestGenericImageName }
            if ($bestGenericImage) {
                $bestGenericImageId = $bestGenericImage.Split('|')[1]
                $bestGenericImageInspect = docker inspect $bestGenericImageID | ConvertFrom-Json
            }
            $usedImages = docker ps -a --no-trunc --format '{{.Image}}'
            $allImages | ForEach-Object {
                $imageName = $_.Split('|')[0]
                if ($usedImages -notcontains $imageName) {
                    $imageID = $_.Split('|')[1]
                    $inspect = docker inspect $imageID | ConvertFrom-Json
                    $artifactUrl = $inspect.config.Env | Where-Object { $_ -like "artifactUrl=*" }
                    if ($artifactUrl) {
                        $artifactUrl = $artifactUrl.Split('?')[0]
                        "artifactUrl=https://bcartifacts*.net/",
                        "artifactUrl=https://bcinsider*.net/",
                        "artifactUrl=https://bcprivate*.net/",
                        "artifactUrl=https://bcpublicpreview*.net/" | ForEach-Object {
                            if ($artifactUrl -like "$($_)*") {
                                $cacheFolder = Join-Path $artifactsCacheFolder $artifactUrl.Substring($artifactUrl.IndexOf('/',$_.Length)+1)
                                if (-not (Test-Path $cacheFolder)) {
                                    Write-Host "$imageName was built on artifacts which was removed from the cache, removing image"
                                    if (-not (DockerDo -command rmi -parameters @("--force") -imageName $imageID -ErrorAction SilentlyContinue)) {
                                        Write-Host "WARNING: Unable to remove image"
                                    }
                                }
                            }
                        }
                    }
                    elseif ($bestGenericImage) {
                        try {
                            if ($inspect.config.Labels.maintainer -eq "Dynamics SMB" -and 
                                $inspect.Config.Labels.tag -ne "" -and 
                                $inspect.Config.Labels.osversion -ne $bestGenericImageInspect.Config.Labels.osversion) {
                                Write-Host "$imageName is a generic image for an old version of your OS, removing image"
                                if (-not (DockerDo -command rmi -parameters @("--force") -imageName $imageID -ErrorAction SilentlyContinue)) {
                                    Write-Host "WARNING: Unable to remove image"
                                }
                            }
                        } catch {}
                    }
                }
            }
            if ($keepDays -eq 0) {
                Write-Host "Running Docker image prune"
                docker image prune -f > $null
            }
            else {
                $h = 24*$keepDays
                Write-Host "Running Docker image prune --filter ""until=$($h)h"""
                docker image prune -f --filter "until=$($h)h" > $null
            }
            Write-Host "Completed"
        }
    }
    finally {
        $flushMutex.ReleaseMutex()
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
Export-ModuleMember -Function Flush-ContainerHelperCache

# SIG # Begin signature block
# MIInSQYJKoZIhvcNAQcCoIInOjCCJzYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCA8X8+Atxe/2Cdg
# 5Ny6jpgG6otgkN6bGkx6iBHMpKSSzqCCDLowggX1MIID3aADAgECAhMzAAACHU0Z
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
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIOVVTsNc
# iaA+AB2tCE8veSQFclzN6zGCKoCVWx2hTpIYMEIGCisGAQQBgjcCAQwxNDAyoBSA
# EgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20w
# DQYJKoZIhvcNAQEBBQAEggEAXQEJm0Cz6PNrfDjYNTbnvfuBal0LIiESlpKS17aV
# MgIJm5/wMz/WyV+qFti92seTQBG2nkgIKCxgaEBT7o8gOe5T2X1cFD+eqMHREL9S
# UEaVRx2CM5/ub5K0VLnxakzX1bD8ZSnjdU4Ly4QGGdfbNjQm99ymUeSWROZC53fq
# iDpUwnowYRdFbNgjtaddp1y0fC2tIj7XTOEql8MctOWS/ICv57Ek0aqVKYd3U33B
# v8JlCU3BoSDIxwR5mx4VT7OrjhCPyL+ZBK5rZTCj5PllppOW8i42EXTvxPEesYFu
# opfX9tHOtozsLAYEuqnHGr9LwtzEhLWkHiLnHobTJapm7qGCF5cwgheTBgorBgEE
# AYI3AwMBMYIXgzCCF38GCSqGSIb3DQEHAqCCF3AwghdsAgEDMQ8wDQYJYIZIAWUD
# BAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGEWQoD
# ATAxMA0GCWCGSAFlAwQCAQUABCA6Tm5tmK+1KjPCy1X2k9duqA6kQ50GuIKy5qDn
# PfV+9gIGaoV0MGJJGBMyMDI2MDgyNzA2MjkzNi41NDRaMASAAgH0oIHRpIHOMIHL
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
# CyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCAKOuccfnhie3yzJqLFaYtpdf5E
# d7KrmBblhAiWC7xX7TCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EION7vyOl
# PA1VqlEp0QIVGlNd8S5YWBnKj97LuTWHSO2vMIGYMIGApH4wfDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgUENBIDIwMTACEzMAAAIgJOHm4Be5tI4AAQAAAiAwIgQgjiu1gfdt
# K/nOE0cUc+Y8+y8Y+ptu1I0ru0zk1hD/Vy8wDQYJKoZIhvcNAQELBQAEggIAxN4W
# MiDOWMxBCWR070pwTQYQUQe2uVh0D5Ky6PDrYRcIZSvwQIz+c6RCCxo+Mqri6hIi
# odpu8cmby/hblUu8U32uWOJFLp57Dyot1LvFGFQqnG68lvJX57hHujibcDcZu1aS
# 1rQBvTEnbld5NO1ohmdLmSfKyZ0JfbaB4nxne27VKxCFRgSZL0eUEptvhcBNAaHV
# n4W9tzdVx3rUAUH+TYuHOrzxroHtZXAbKkaz7jtfqcZ0FRdCWD5v5pQEds6oI7q5
# pgaMSVQCwshFAd6sTux9uURyRqCpQ5DR1GV1rIZOxKzR4oVR0RnxxapDvGBqPtP7
# 8KWgKtBNS906ViRxKXX+pH4pS7RHeqjUTZJsi3BpDBo/+2kbTYnOFsUdZzxmgrRG
# TA6SFNPONYBbS4Un4PrUTTX/zZucc2Zhe7knVAvhLETUDj4XoIle93pBaxHdXvfs
# jRa+tlHu5FM2jZDIYIak9UvTUkXUQSinp9FeWxFilvYxZGH3jjQucE4Ins+cDp3y
# 3pHca3HbbcOzsxJ0yGj5s/F3FAXiI7gezASFUBtmiD7yoxc0OeaiTjN2eev4yw8x
# oGBl7pRrlL0CBYr66njc4yLoNmQxx33MMNIVIBsni4lflcJkegBJqdhTKg55AGzr
# GM9dlQdL84mWldlQGYhf0LKFtFGZ8XH/eN1KMfQ=
# SIG # End signature block
