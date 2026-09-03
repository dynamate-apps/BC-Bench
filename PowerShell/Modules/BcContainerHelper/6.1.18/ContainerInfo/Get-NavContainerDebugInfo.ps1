<# 
 .Synopsis
  Extract metadata from a container to be able to give more specific information when reporting an issue on GitHub.
 .Description
  Returns the debugging info for a container when reporting an issue on GitHUb
 .Parameter containerName
  Name of the container for which you want to get the debugging info
 .Parameter ExcludeEnvVars
  Add this switch if you want to exclude environment variables in the debugging info
 .Parameter ExcludeDockerInfo
  Add this switch if you want to exclude docker info in the debugging info
 .Parameter ExcludeDockerLogs
  Add this switch if you want to exclude docker logs in the debugging info
 .Parameter ExcludePing
  Add this switch if you want to exclude ping information in the debugging info
 .Parameter includeSensitiveInformation
  Add this switch to include sensitive information in the debugging info (passwords and urls)
 .Parameter CopyToClipboard
  Add this switch if you want the debugging info to automatically be added to the clipboard
 .Example 
  Get-BcContainerDebugInfo -containerName bcserver -includeSensitiveInformation
  Get all debug information including sensitive information
  .Example
  Get-BcContainerDebugInfo -containerName bcserver -ExcludeDockerInfo
  Get debug information excluding sensitive information and excluding docker info
  .Example
  Get-BcContainerDebugInfo -containerName bcserver -ExcludeEnvVars -ExcludeDockerInfo -ExcludeDockerLogs -CopyToClipboard
  Get basic debug information and copy it into the clipboard.
#>
function Get-BcContainerDebugInfo {
    [CmdletBinding()]
    Param (
        [string] $containerName = $bcContainerHelperConfig.defaultContainerName,
        [Parameter()]
        [switch] $ExcludeEnvVars,
        [Parameter()]
        [switch] $ExcludeDockerInfo,
        [Parameter()]
        [switch] $ExcludeDockerLogs,
        [Parameter()]
        [switch] $ExcludePing,
        [Parameter()]
        [switch] $IncludeSensitiveInformation,
        [Parameter()]
        [switch] $CopyToClipboard
    )

    $debugInfo = @{}
    $inspect = docker inspect $containerName | ConvertFrom-Json

    if ($inspect.Config.Labels.psobject.Properties.Match('maintainer').Count -eq 0 -or $inspect.Config.Labels.maintainer -ne "Dynamics SMB") {
        throw "Container $containerName is not a NAV/BC container"
    }
    
    $debugInfo.Add('container.labels', $inspect.Config.Labels)
    
    if (!$ExcludeEnvVars) {
        $envs = $inspect.Config.Env.GetEnumerator() | ForEach-Object {
            if ($includeSensitiveInformation) {
                $_
            } elseif ($_.ToLowerInvariant().Contains("password=") -or 
                      $_.ToLowerInvariant().Startswith("navdvdurl=") -or 
                      $_.ToLowerInvariant().Startswith("countryurl=") -or 
                      $_.ToLowerInvariant().Startswith("licensefile=") -or 
                      $_.ToLowerInvariant().Startswith("bakfile=") -or 
                      $_.ToLowerInvariant().Startswith("folders=") -or 
                      $_.ToLowerInvariant().Startswith("vsixurl=")) {
                ($_.Split("=")[0] + "=<specified>")
            } else {
                $_
            }
        }
        if ($envs) {
            $debugInfo.Add('container.env', $envs)
        }
    }

    if (!$ExcludeDockerInfo) {
        $dockerInfo = docker info
        if ($dockerInfo) {
            $debugInfo.Add('docker.info', $dockerInfo)
        }
    }

    if (!$ExcludeDockerLogs) {
        $logs = docker logs $containerName
        if ($logs) {
            $debugInfo.Add('container.logs', $logs)
        }
    }

    if (!$ExcludePing) {
        $ping = ping $containerName
        if ($ping) {
            $debugInfo.Add('container.ping', $ping)
        }
    }

    $debugInfoJson = ConvertTo-Json $debugInfo

    if ($CopyToClipboard) {
        $debugInfoJson | Set-Clipboard
    }
    
    return $debugInfoJson
}
Set-Alias -Name Get-NavContainerDebugInfo -Value Get-BcContainerDebugInfo
Export-ModuleMember -Function Get-BcContainerDebugInfo -Alias Get-NavContainerDebugInfo

# SIG # Begin signature block
# MIInbgYJKoZIhvcNAQcCoIInXzCCJ1sCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAqm3NGvAxUKbJY
# LlGXy2D7AXah4hK8m6v1hVmr5IWx6KCCDMkwggYEMIID7KADAgECAhMzAAACHPrN
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
# hvcNAQkEMSIEIEldB1d06z/gjvT73MtIxUjXVWMZB71XuhGOiqN45do6MEIGCisG
# AQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEAa1fpDAOhfBxAFb5dWXXA
# ruM8naPC5VmhNl3BEhyjGAbkWitSWsZU6qbSWhvP1BR3jIBIgw2a/PThF7lYlOoT
# ty/kEFodkap7vAK6QAERXOyZKXOGc1b9bzOunw/C58nu5MWZ1UYvkdwUyAJOR31U
# FMRd9a/EEt9lXPGi+PLY3p86mzbTW8D8aKQfEp+GVFkAwZVfKjSbkALsOE0sptZt
# xsU8qQPXC2FBrtAOYhMMzKSY8Nhv4wz+Fcq8TUrgLdUZKUsDRrl6jdpB4F+NnTFT
# 6B6uzvzTYx+n6JIrp/QgXMlSfbt3cUPJOZoucPyULpEYVWsMZ0Vgj9VvOBVav5DZ
# 2KGCF60wghepBgorBgEEAYI3AwMBMYIXmTCCF5UGCSqGSIb3DQEHAqCCF4YwgheC
# AgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFFMIIB
# QQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCAadOnpAJnbImPN3fM3
# 0PjGi3q1S30pwB19tFQsXjfnwgIGaojzqfRoGBMyMDI2MDgyNzA2MzI1NC45ODVa
# MASAAgH0oIHZpIHWMIHTMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0
# ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjo0QzFBLTA1RTAtRDk0NzElMCMG
# A1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaCCEfswggcoMIIFEKAD
# AgECAhMzAAACGCXZkgXi5+XkAAEAAAIYMA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29m
# dCBUaW1lLVN0YW1wIFBDQSAyMDEwMB4XDTI1MDgxNDE4NDgyNVoXDTI2MTExMzE4
# NDgyNVowgdMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTAr
# BgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUG
# A1UECxMeblNoaWVsZCBUU1MgRVNOOjRDMUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxN
# aWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOC
# Ag8AMIICCgKCAgEAsdzo6uuQJqAfxLnvEBfIvj6knK+p6bnMXEFZ/QjPOFywlcjD
# fzI8Dg1nzDlxm7/pqbvjWhyvazKmFyO6qbPwClfRnI57h5OCixgpOOCGJJQIZSTi
# Mgui3B8DPiFtJPcfzRt3FsnxjLXwBIjGgnjGfmQl7zejA1WoYL/qBmQhw/FDFTWe
# bxfo4m0RCCOxf2qwj31aOjc2aYUePtLMXHsXKPFH0tp5SKIF/9tJxRSg0NYEvQqV
# ilje8aQkPd3qzAux2Mc5HMSK4NMTtVVCYAWDUZ4p+6iDI9t5BNCBIsf5ooFNUWtx
# CqnpFYiLYkHfFfxhVUBZ8LGGxYsA36snD65s2Hf4t86k0e8WelH/usfhYqOM3z2y
# aI8rg08631IkwqUzyQoEPqMsHgBem1xpmOGSIUnVvTsAv+lmECL2RqrcOZlZax8K
# 0aiij8h6UkWBN2IA/ikackTSGVRBQmWWZuLFWV/T4xuNzscC0X7xo4fetgpsqaEA
# 0jY/QevkTvLv4OlNN9eOL8LNh7Vm0R65P7oabOQDqtUFAwCgjgPJ0iV/jQCaMAcO
# 3SYpG5wSAYiJkk4XLjNSlNxU2Idjs1sORhl7s7LC6hOb7bVAHVwON74GxfFNiEIA
# 6BfudANjpQJ0nUc/ppEXpT4pgDBHsYtV8OyKSjKsIxOdFR7fIJIjDc8DvUkCAwEA
# AaOCAUkwggFFMB0GA1UdDgQWBBQkLqHEXDobY7dHuoQCBa4sX7aL0TAfBgNVHSME
# GDAWgBSfpxVdAF5iXYP05dJlpxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1l
# LVN0YW1wJTIwUENBJTIwMjAxMCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsG
# AQUFBzAChlBodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01p
# Y3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMB
# Af8EAjAAMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDAN
# BgkqhkiG9w0BAQsFAAOCAgEAnkjRhjwPgdoIpvt4YioT/j0LWuBxF3ARBKXDENgg
# raKvC0oRPwbjAmsXnPEmtuo5MD8uJ9Xw9eYrxqqkK4DF9snZMrHMfooxCa++1irL
# z8YoozC4tci+a4N37Sbke1pt1xs9qZtvkPgZGWn5BcwVfmAwSZLHi2CuZ06Y0/X+
# t6fNBnrbMVovNaDX4WPdyI9GEzxfIggDsck2Ipo4VXL/Arcz7p2F7bEZGRuyxjgM
# C+woCkDJaH/yk/wcZpAsixe4POdN0DW6Zb35O3Dg3+a6prANMc3WIdvfKDl75P0a
# qcQbQAR7b0f4gH4NMkUct0Wm4GN5KhsE1YK7V/wAqDKmK4jx3zLz3a8Hsxa9HB3G
# yitlmC5sDhOl4QTGN5kRi6oCoV4hK+kIFgnkWjHhSRNomz36QnbCSG/BHLEm2GRU
# 9u3/I4zUd9E1AC97IJEGfwb+0NWb3QEcrkypdGdWwl0LEObhrQR9B1V7+edcyNms
# X0p2BX0rFpd1PkXJSbxf8IcEiw/bkNgagZE+VlDtxXeruLdo5k3lGOv7rPYuOEao
# ZYxDvZtpHP9P36wmW4INjR6NInn2UM+krP/xeLnRbDBkm9RslnoDhVraliKDH62B
# xhcgL9tiRgOHlcI0wqvVWLdv8yW8rxkawOlhCRqT3EKECW8ktUAPwNbBULkT+oWc
# vBcwggdxMIIFWaADAgECAhMzAAAAFcXna54Cm0mZAAAAAAAVMA0GCSqGSIb3DQEB
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
# ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjo0QzFBLTA1RTAtRDk0NzElMCMG
# A1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIa
# AxUAnWtGrXWiuNE8QrKfm4CtGr57z+mggYMwgYCkfjB8MQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1T
# dGFtcCBQQ0EgMjAxMDANBgkqhkiG9w0BAQsFAAIFAO46CSgwIhgPMjAyNjA4Mjcw
# MDU0MDBaGA8yMDI2MDgyODAwNTQwMFowdDA6BgorBgEEAYRZCgQBMSwwKjAKAgUA
# 7joJKAIBADAHAgEAAgIV1zAHAgEAAgISrjAKAgUA7jtaqAIBADA2BgorBgEEAYRZ
# CgQCMSgwJjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0G
# CSqGSIb3DQEBCwUAA4IBAQBe9tx5LrZHwrgXj+mMnhnUeZyPpcVYfLaXUbGw+dnz
# sAsX6HqtiRHFc32JvScfNjcr1qWyrHK4pjotV3z2Rexip8uu9+QsJSAseFahQ3le
# FCubLJcXyTt92wNr+5Ko5hYaNlpkwvVk0jLuyGsI0t8lK0OjzqD4NHw6nEN8JlfI
# 8kvnC/UowD3DEOyBk1AE6co9/e912QzsCLEybO9RSjuugfNd9io6K0GmxnPMVUDX
# iDc7nDZcKCf0iiFB3U3iQ5piSBWt58KKbKW8tWacjpQb8UXPkkSdeysn2pj+5qZ7
# x0Vv7639sbX/ons/b5Cn1M+FzYRCswXIcc5vXAlrAwgJMYIEDTCCBAkCAQEwgZMw
# fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMd
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAIYJdmSBeLn5eQAAQAA
# AhgwDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRAB
# BDAvBgkqhkiG9w0BCQQxIgQgemiE48r9hj1ZDZIux/2Z1FBUTK3tuH9uE48TR5Hd
# eBAwgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCCZE9yJuOTItIwWaES6lzGK
# K1XcSoz1ynRzaOVzx9eFajCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBD
# QSAyMDEwAhMzAAACGCXZkgXi5+XkAAEAAAIYMCIEIEhqkwjM7SxCap2y9PHSkwvV
# i120OGxHXyrnyKwNL6A5MA0GCSqGSIb3DQEBCwUABIICACagedT6CiX3xDOLcG3F
# eOj5jrFY1NpXrP37Kaqp+oXw7YR+QnW2R0X+MiSVtTB2ZzV1h9SchVgzKEHXLaA0
# UW2NhK4kknX337QSvC38UxFfzwEaJ4cjqmChI57Bk4fxy5VAiy2zOPJH/pmJACG9
# UjKjhtxfQt3vCrj7dxLi9OTzY6ZC6oZxcBbDoRspT8/63TRL8ERm/F+Lh/f0OuQu
# 8iv0Z0rgrZ7DKHtqkkfL05mX8GqfO12dbDvHYb0GrUoYjdCArbCLCzG6NFMwXWIG
# wJUv6xTip1vaWpcaVIoVjHFkMAQt2B5oQJPNxuxMwszH0FGxWMjHlJggCiD2xKPy
# CZ+Y1S4KDGcMuKXEH/aRH/FfhBf3hKQzLvFb3pfpcVCMjLfFN8QPFPy4JZ0bKWz1
# bRsFOyPY/iWM2Ir/yKFZDqFPXaQ+5xboclIGkSeRWQcHDRl8W2I5K/Hp7fqYVUAZ
# m1SN/zDVyy4oe9A9+jb21oRMbcJYNEA8/7RLye/VAGVZGh2WpSulrLGICKgcsCaQ
# P1WW3KbjEdNOJDoW1pIsGVW/yv+DrLsC3gKRRC60b1AaaGpLl1EK0/B2WazhQ9/1
# FXYZuLY3lSi9Z2dMpkKGXxVDrMI8lH9RllqOO/ajOuEED/pfJcQm52mK/B3FbKBE
# WWK8meeV/Dz4axzciQW1u6HQ
# SIG # End signature block
