<# 
 .Synopsis
  Invoke a PowerShell scriptblock in a NAV/BC Container
 .Description
  If you are running as administrator, this function will create a session to a Container and invoke a scriptblock in this session.
  If you are not an administrator, this function will create a PowerShell script in the container and use docker exec to launch the PowerShell script in the container.
 .Parameter containerName
  Name of the container in which you want to invoke a PowerShell scriptblock
 .Parameter scriptblock
  A pre-compiled PowerShell scriptblock to invoke
 .Parameter argumentList
  Arguments to transfer to the scriptblock in form of an object[]
 .Parameter useSession
  If true, the scriptblock will be invoked in a PowerShell session in the container. If false, the scriptblock will be invoked using docker exec
 .Parameter usePwsh
  If true, the scriptblock will be invoked using pwsh instead of powershell (when BC version is 24 or later)
 .Example
  Invoke-ScriptInBcContainer -containerName dev -scriptblock { $env:UserName }
 .Example
  [xml](Invoke-ScriptInBcContainer -containerName dev -scriptblock { Get-Content -Path (Get-item 'c:\Program Files\Microsoft Dynamics NAV\*\Service\CustomSettings.config').FullName })
#>
function Invoke-ScriptInBcContainer {
    Param (
        [string] $containerName = $bcContainerHelperConfig.defaultContainerName, 
        [Parameter(Mandatory=$true)]
        [ScriptBlock] $scriptblock,
        [Parameter(Mandatory=$false)]
        [Object[]] $argumentList,
        [bool] $useSession = $bcContainerHelperConfig.usePsSession,
        [bool] $usePwsh = $bccontainerHelperConfig.usePwshForBc24
    )

    $file = ''
    [System.Version]$platformVersion = Get-BcContainerPlatformVersion -containerOrImageName $containerName
    if ($useSession -and $usePwsh) {
        # Check if we should disable PS sessions for BC v28+ due to known PS7 remote session issues
        # https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/upgrade/known-issues#business-central-admin-shell-modules-fail-in-powershell7-remote-sessions
        if ($platformVersion.Major -eq 28 -and -not $bcContainerHelperConfig.usePsSessionForBc28) {
            $useSession = $false
        }
    }
    if (!$useSession) {
        $file = Join-Path $bcContainerHelperConfig.hostHelperFolder ([GUID]::NewGuid().Tostring()+'.ps1')
        $containerFile = Get-BcContainerPath -containerName $containerName -path $file
        if ($isInsideContainer -or "$containerFile" -eq "") {
            $useSession = $true
        }
    }

    if ($useSession) {
        try {
            $session = Get-BcContainerSession -containerName $containerName -silent -usePwsh:$usePwsh
        }
        catch {
            if ($isInsideContainer) {
                Write-Host "Error trying to establish session, retrying in 5 seconds"
                Start-Sleep -Seconds 5
                $session = Get-BcContainerSession -containerName $containerName -silent -usePwsh:$usePwsh
            }
            else {
                $useSession = $false
            }
        }
    }
    if ($useSession) {
        if ($bcContainerHelperConfig.debugMode) {
            Write-Host "Invoke script using remote session"
        }
        $startTime = [DateTime]::Now
        try {
            Invoke-Command -Session $session -ScriptBlock { param($a) $WarningPreference = $a } -ArgumentList $bcContainerHelperConfig.WarningPreference
            Invoke-Command -Session $session -ScriptBlock $scriptblock -ArgumentList $argumentList
        }
        catch {
            $errorMessage = $_.Exception.Message
            Write-Host -ForegroundColor Red $errorMessage
            Write-Host
            Write-Host "Exception Script Stack Trace:"
            Write-Host -ForegroundColor Red $_.scriptStackTrace
            Write-Host
            Write-Host "PowerShell Call Stack:"
            Get-PSCallStack | Write-Host -ForegroundColor Red
            try {
               $isOutOfMemory = Invoke-Command -Session $session -ScriptBlock { Param($containerName, $startTime)
                    $cimInstance = Get-CIMInstance Win32_OperatingSystem
                    Write-Host "`nContainer Free Physical Memory: $(($cimInstance.FreePhysicalMemory/1024/1024).ToString('F1',[CultureInfo]::InvariantCulture))Gb"
                    Get-PSDrive C | ForEach-Object { Write-Host "Disk C: Free $([Math]::Round($_.Free / 1GB))Gb from $([Math]::Round(($_.Free+$_.Used) / 1GB))Gb" }
                    $any = $false
                    Write-Host "`nServices in container $($containerName):"
                    Get-Service |
                        Where-Object { $_.Name -like "MicrosoftDynamics*" -or $_.Name -like "MSSQL`$*" } |
                        Select-Object -Property name, Status |
                        ForEach-Object {
                            if ($_.Status -eq "Running") {
                                Write-Host "- $($_.Name) is $($_.Status)"
                            }
                            else {
                                Write-Host -ForegroundColor Red "- $($_.Name) is $($_.Status)"
                            }
                            $any = $true
                        }
                    if (!$any) { Write-Host -ForegroundColor Red "- No services found" }
                    Write-Host
                    $any = $false
                    $isOutOfMemory = $false
                    Get-EventLog -LogName Application | 
                        Where-Object { $_.EntryType -eq "Error" -and $_.TimeGenerated -gt $startTime -and ($_.Source -like "MicrosoftDynamics*" -or $_.Source -like "MSSQL`$*") } | 
                        Select-Object -Property TimeGenerated, Source, Message |
                        ForEach-Object {
                            if (!$any) {
                                Write-Host "`nRelevant event log from container $($containerName):"
                            }
                            Write-Host -ForegroundColor Red "- $($_.TimeGenerated.ToString('yyyyMMdd hh:mm:ss')) - $($_.Source)"
                            Write-Host -ForegroundColor Gray "`n  $($_.Message.Replace("`n","`n  "))`n"
                            if ($_.Message.Contains('OutOfMemoryException')) { $isOutOfMemory = $true }
                            $any = $true
                        }
                    $isOutOfMemory
                } -ArgumentList $containerName, $startTime
                if ($isOutOfMemory) {
                    $errorMessage = "Out Of Memory Exception thrown inside container $containerName"
                }
            } catch {}
            throw $errorMessage
        }
    } else {
        if ($bcContainerHelperConfig.debugMode) {
            Write-Host "Invoke script using docker exec"
        }
        if ($file -eq '') {
            $file = Join-Path $bcContainerHelperConfig.hostHelperFolder ([GUID]::NewGuid().Tostring()+'.ps1')
            $containerFile = Get-BcContainerPath -containerName $containerName -path $file
        }
        if ("$containerFile" -eq "") {
            throw "$($bcContainerHelperConfig.hostHelperFolder) is not shared with the container, cannot invoke scripts in container without using a session"
        }
        $shell = 'powershell'
        if ($usePwsh) {
            if ($platformVersion -ge [System.Version]"24.0.0.0") {
                $shell = 'pwsh'
            }
        }
        $hostOutputFile = "$file.output"
        $containerOutputFile = "$containerFile.output"
        try {
            $oldEncoding = [Console]::OutputEncoding
            try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
            if ($isPsCore) { $encoding = 'UTF8BOM' } else { $encoding = 'UTF8' }
            if ($argumentList) {
                $encryptionKey = $null
                $xml = [xml]([System.Management.Automation.PSSerializer]::Serialize($argumentList))
                $nsmgr = New-Object System.Xml.XmlNamespaceManager -ArgumentList $xml.NameTable
                $nsmgr.AddNamespace("ns", "http://schemas.microsoft.com/powershell/2004/04");  
                $nodes = $xml.SelectNodes("//ns:SS", $nsmgr)
                if ($nodes.Count -gt 0) {
                    $encryptionKey = New-Object Byte[] 16
                    [Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($encryptionKey)
                    '$encryptionkey = [System.Management.Automation.PSSerializer]::Deserialize('''+([xml]([System.Management.Automation.PSSerializer]::Serialize($encryptionKey))).OuterXml+''')' | Add-Content -Encoding $encoding -Path $file
                }
                foreach($node in $nodes) {
                    $node.InnerText = ConvertFrom-SecureString -SecureString ($node.InnerText | ConvertTo-SecureString) -Key $encryptionkey
                }
                
                $xmlbytes =[System.Text.Encoding]::UTF8.GetBytes($xml.OuterXml)
                '$xmlbytes = [Convert]::FromBase64String('''+[Convert]::ToBase64String($xmlbytes)+''')' | Add-Content -Encoding $encoding -Path $file
                '$xml = [xml]([System.Text.Encoding]::UTF8.GetString($xmlbytes))' | Add-Content -Encoding $encoding -Path $file

                if ($encryptionKey) {
                    '$nsmgr = New-Object System.Xml.XmlNamespaceManager -ArgumentList $xml.NameTable' | Add-Content -Encoding $encoding -Path $file
                    '$nsmgr.AddNamespace("ns", "http://schemas.microsoft.com/powershell/2004/04")' | Add-Content -Encoding $encoding -Path $file
                    '$nodes = $xml.SelectNodes("//ns:SS", $nsmgr)' | Add-Content -Encoding $encoding -Path $file
                    'foreach($node in $nodes) { $node.InnerText = ConvertFrom-SecureString -SecureString ($node.InnerText | ConvertTo-SecureString -Key $encryptionKey) }' | Add-Content -Encoding $encoding -Path $file
                }
                '$argumentList = [System.Management.Automation.PSSerializer]::Deserialize($xml.OuterXml)' | Add-Content -Encoding $encoding -Path $file
            }

'$runPath = "c:\Run"
$myPath = Join-Path $runPath "my"

function Get-MyFilePath([string]$FileName)
{
    if ((Test-Path $myPath -PathType Container) -and (Test-Path (Join-Path $myPath $FileName) -PathType Leaf)) {
        (Join-Path $myPath $FileName)
    } else {
        (Join-Path $runPath $FileName)
    }
}

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

. (Get-MyFilePath "prompt.ps1") -silent | Out-Null
. (Get-MyFilePath "ServiceSettings.ps1") | Out-Null
. (Get-MyFilePath "HelperFunctions.ps1") | Out-Null

$txt2al = ""
if ($roleTailoredClientFolder) {
    $txt2al = Join-Path $roleTailoredClientFolder "txt2al.exe"
    if (!(Test-Path $txt2al)) {
        $txt2al = ""
    }
}

Set-Location $runPath
$ErrorActionPreference = "Stop"
$startTime = [DateTime]::Now
' | Add-Content -Encoding $encoding -Path $file

"`$WarningPreference = '$($bcContainerHelperConfig.WarningPreference)'
" | Add-Content -Encoding $encoding -Path $file

"`$containerName = '$containerName'
" | Add-Content -Encoding $encoding -Path $file

            if ($bcContainerHelperConfig.addTryCatchToScriptBlock) {
                $ast = $scriptblock.Ast
                if ($ast -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
                    $ast = $ast.Body
                }
                if ($ast -is [System.Management.Automation.Language.ScriptBlockAst]) {
                    if ($ast.ParamBlock) {
                        $script = $ast.Extent.text.Replace($ast.ParamBlock.Extent.Text,'').Trim()
                        if ($script.StartsWith('{')) {
                            "`$result = Invoke-Command -ScriptBlock { $($ast.ParamBlock.Extent.Text) try $script catch { ""::EXCEPTION::`$(`$_.Exception.Message)"" } } -ArgumentList `$argumentList" | Add-Content -Encoding $encoding -Path $file
                        }
                        else {
                            "`$result = Invoke-Command -ScriptBlock { $($ast.ParamBlock.Extent.Text) try { $script } catch { ""::EXCEPTION::`$(`$_.Exception.Message)"" } } -ArgumentList `$argumentList" | Add-Content -Encoding $encoding -Path $file
                        }
                    }
                    else {
                        $script = $ast.Extent.text.Trim()
                        if ($script.StartsWith('{')) {
                            "`$result = Invoke-Command -ScriptBlock { try $($ast.Extent.text) catch { ""::EXCEPTION::`$(`$_.Exception.Message)"" } }" | Add-Content -Encoding $encoding -Path $file
                        }
                        else {
                            "`$result = Invoke-Command -ScriptBlock { try { $($ast.Extent.text) } catch { ""::EXCEPTION::`$(`$_.Exception.Message)"" } }" | Add-Content -Encoding $encoding -Path $file
                        }
                    }
                }
                else {
                    throw "Unsupported Scriptblock type $($ast.GetType())"
                }
@'
$exception = $result | Where-Object { $_ -like "::EXCEPTION::*" }
if ($exception) {
    $errorMessage = $exception.SubString(13)
    Write-Host -ForegroundColor Red "$errorMessage"
    Write-Host
    try {
       $isOutOfMemory = Invoke-Command -ScriptBlock { Param($containerName, $startTime)
            $cimInstance = Get-CIMInstance Win32_OperatingSystem
            Write-Host "Container Free Physical Memory: $(($cimInstance.FreePhysicalMemory/1024/1024).ToString('F1',[CultureInfo]::InvariantCulture))Gb"
            Get-PSDrive C | ForEach-Object { Write-Host "Disk C: Free $([Math]::Round($_.Free / 1GB))Gb from $([Math]::Round(($_.Free+$_.Used) / 1GB))Gb" }
            $any = $false
            Write-Host "`nServices in container $($containerName):"
            Get-Service |
                Where-Object { $_.Name -like "MicrosoftDynamics*" -or $_.Name -like "MSSQL`$*" } |
                Select-Object -Property name, Status |
                ForEach-Object {
                    if ($_.Status -eq "Running") {
                        Write-Host "- $($_.Name) is $($_.Status)"
                    }
                    else {
                        Write-Host -ForegroundColor Red "- $($_.Name) is $($_.Status)"
                    }
                    $any = $true
                }
            if (!$any) { Write-Host -ForegroundColor Red "- No services found" }
            Write-Host
            $any = $false
            $isOutOfMemory = $false
            Get-EventLog -LogName Application | 
                Where-Object { $_.EntryType -eq "Error" -and $_.TimeGenerated -gt $startTime -and ($_.Source -like "MicrosoftDynamics*" -or $_.Source -like "MSSQL`$*") } | 
                Select-Object -Property TimeGenerated, Source, Message |
                ForEach-Object {
                    if (!$any) {
                        Write-Host "`nRelevant event log from container $($containerName):"
                    }
                    Write-Host -ForegroundColor Red "- $($_.TimeGenerated.ToString('yyyyMMdd hh:mm:ss')) - $($_.Source)"
                    $message = @($_.Message.Split("`n") | Select-Object -First 15) -join "`n  "
                    Write-Host -ForegroundColor Gray "`n  $($message)`n"
                    if ($_.Message.Contains('OutOfMemoryException')) { $isOutOfMemory = $true }
                    $any = $true
                }
            $isOutOfMemory
        } -ArgumentList $containerName, $startTime
        if ($isOutOfMemory) {
            $errorMessage = "Out Of Memory Exception thrown inside container $containerName"
        }
    } catch {}

    $result = @("::EXCEPTION::$errorMessage") + @($result | Where-Object { $_ -notlike "::EXCEPTION::*" })
}
'@ | Add-Content -Encoding $encoding -Path $file

'if ($result -ne $null) { [System.Management.Automation.PSSerializer]::Serialize($result) | Set-Content -Encoding utf8 "'+$containerOutputFile+'" }' | Add-Content -Encoding $encoding -Path $file

#Write-Host -ForegroundColor cyan (Get-Content $file -Raw -Encoding UTF8)

                $ErrorActionPreference = "Stop"
                #$file | Out-Host
                #Get-Content -encoding utf8 -path $file | Out-Host
                docker exec $containerName $shell $containerFile | Out-Host
                if($LASTEXITCODE -ne 0) {
                    Remove-Item $file -Force -ErrorAction SilentlyContinue
                    Remove-Item $hostOutputFile -Force -ErrorAction SilentlyContinue
                    throw "Error executing script in Container"
                }
                if (Test-Path -Path $hostOutputFile -PathType Leaf) {
#                   Write-Host -ForegroundColor Cyan "'$(Get-content $hostOutputFile -Raw -Encoding UTF8)'"
                    $result = [System.Management.Automation.PSSerializer]::Deserialize((Get-content -encoding utf8 $hostOutputFile))
                    $exception = $result | Where-Object { $_ -like "::EXCEPTION::*" }
                    if ($exception) {
                        $errorMessage = $exception.SubString(13)
                        throw $errorMessage
                    }
                    $result
                }
            }
            else {
                '$result = Invoke-Command -ScriptBlock {' + $scriptblock.ToString() + '} -ArgumentList $argumentList' | Add-Content -Encoding $encoding -Path $file
                'if ($result) { [System.Management.Automation.PSSerializer]::Serialize($result) | Set-Content -Encoding utf8 "'+$containerOutputFile+'" }' | Add-Content -Encoding $encoding -Path $file
                $ErrorActionPreference = "Stop"
                docker exec $containerName $shell $containerFile | Out-Host
                if($LASTEXITCODE -ne 0) {
                    Remove-Item $file -Force -ErrorAction SilentlyContinue
                    Remove-Item $hostOutputFile -Force -ErrorAction SilentlyContinue
                    throw "Error executing script in Container"
                }
                if (Test-Path -Path $hostOutputFile -PathType Leaf) {
                    [System.Management.Automation.PSSerializer]::Deserialize((Get-content -encoding utf8 $hostOutputFile))
                }
            }
        } finally {
            try { [Console]::OutputEncoding = $oldEncoding } catch {}
            Remove-Item $file -Force -ErrorAction SilentlyContinue
            Remove-Item $hostOutputFile -Force -ErrorAction SilentlyContinue
        }
    }
}
Set-Alias -Name Invoke-ScriptInNavContainer -Value Invoke-ScriptInBcContainer
Export-ModuleMember -Function Invoke-ScriptInBcContainer -Alias Invoke-ScriptInNavContainer

# SIG # Begin signature block
# MIInbgYJKoZIhvcNAQcCoIInXzCCJ1sCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCARW9068zkQXNE6
# meOQO/QWOvxSBBBhrZG9vj4QbTDDJaCCDMkwggYEMIID7KADAgECAhMzAAACHPrN
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
# hvcNAQkEMSIEINMF8HHyjMiAMYFJfA+ZW9QIAmqkML9IjMCvLTx/uVSBMEIGCisG
# AQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEAjcZt1gDN79GnbTFU87Kc
# KjxjzoJL8ibY0tLPeOPrF//sRZt2q+6aFkG5wzJlOG6Q5isax89WiOAuxvT+bnsL
# QazrB/x6jMuY4hglJY0jsQfPsVmQVPO1RGo2j4XoAIkda6MyrFSQyzYFgMRcxOUj
# U84P4jww8McCvYma3me8uwYqOoFur0hMD2lKPET3vUGE1+kldT9YBPi7TGtJF9se
# pgntg7q68cZKGHq+uw2IFK3TFS5nowK1hprETmakr5c3kTlY9OZ3NInNGvphJD26
# v5+kNlrJuQdHfJFaTArHzhLTX3mX5AP/NEXsaI/evUBfF3GNK4+A6MdSx24u/MED
# tKGCF60wghepBgorBgEEAYI3AwMBMYIXmTCCF5UGCSqGSIb3DQEHAqCCF4YwgheC
# AgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFFMIIB
# QQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCCGhxCStZoTstwwbrep
# FfjpSe2Dtf6+0wIYJkp6GoQvkAIGamQNqX2ZGBMyMDI2MDgxODA5MTA0NC4zNDJa
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
# dGFtcCBQQ0EgMjAxMDANBgkqhkiG9w0BAQsFAAIFAO4uLc4wIhgPMjAyNjA4MTgw
# MTAzMTBaGA8yMDI2MDgxOTAxMDMxMFowdDA6BgorBgEEAYRZCgQBMSwwKjAKAgUA
# 7i4tzgIBADAHAgEAAgIDNTAHAgEAAgISsTAKAgUA7i9/TgIBADA2BgorBgEEAYRZ
# CgQCMSgwJjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0G
# CSqGSIb3DQEBCwUAA4IBAQAaWiAioOD9BiX09Y+D6yK6HN4Vjfb+h7IoAcbpaIiy
# /7VOZpixQa0XodlHn0T1MS7VIbQnBPl3+3MJsEmKoqh0QmPukJuGa2dvFMa2pcuL
# 2L6bNtYtoGjU9TDablUVkG6w6miGHlvMDZ8Y7saHeIM369piTNgnydzoS1N++22B
# RKEIYy3MxZZSZB/4mkNcdhO0zglQ1FXhYx0Prb/e7sl6ZyQrt9CQwCaSu3sDOunW
# TfMudY8dF7NcUOZ6EDskX2OikufjH2+BM5Ltz0PMjnFDpMLEDCUqJYJrlwI1Z2X9
# 0aZ/SAwYoTfM7+5wai/HZsGIjBLK0brrseWYB7JNUHjaMYIEDTCCBAkCAQEwgZMw
# fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMd
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAIb0LK4Amf3cs8AAQAA
# AhswDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRAB
# BDAvBgkqhkiG9w0BCQQxIgQglAlnrFU35wFub/WQoZT2k0AbnHuVwBLb39qXLFLS
# LiUwgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCAwJRSVuD2jmMcQCFXdLuJA
# wDpUVNZ6bc6dfJU83Q2LgDCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBD
# QSAyMDEwAhMzAAACG9CyuAJn93LPAAEAAAIbMCIEIPKl/JU9x9RwWBl7m+PbDOgx
# ePvVdHbu793O8+33FQWiMA0GCSqGSIb3DQEBCwUABIICAIeRgLBYyY6SBzC+Y1Ii
# MNa4WTrwzCz0vlnMEkXOLK5WQDZGRBZsSQvgKo6tEDKVlVbNkqcxwyu7RHG70zp9
# TtXnPud7QboWtsNQF9AyQlv3eB26kaXJPLnrZbj7VHVcTZvYF8bMPsdbLtNRAWYm
# JMNAzh6iFCsPNnCed+Ix734FXwiFcQgnjdJ4ExxRBxNKBG3lG2AttK+OJUxY+WQK
# qH/AMUYFMIWXgOGV42E/nuMMTsyU7gp9EQNmgwA9AmYbjfc2aBIQNK3vn28HjHVE
# vC03dFiRcfK0XNAQg8ILLzdGOBOTMBOJgDAnWlPtLz2Zqac8L0qLzvZb7Ry8o5TT
# a/87zA02t/is+tgCE2fTIatxzW4FR4NPYaH6muIr19QCQFO1awEMu5WM5DL/k+hE
# KXll2gAj7Shl4S82uL1gSVUQCmtpqTc/zL9CkTBgwTwJ2wkhkzKCbGt9FuNXqZz+
# kPMdvfOdOTu/zQIfAEV4yNKh43PM/yeqLqaT4q6gCj0T9E9ceMIizQrSz8rgFs6Q
# s4hXInFepD54eEF8MMh9BGLHCVdlB5FLVb6BpKSBZJUjmsP9rWtrKo/y3yEaQKiL
# verSrU8LS6xnCwSa5xTWSkI6o1RSkyMClGk6uAPTrckYM66mG+TwXpz9g+es2QAL
# erO71dlK/55hH3ttHL1+TEyi
# SIG # End signature block
