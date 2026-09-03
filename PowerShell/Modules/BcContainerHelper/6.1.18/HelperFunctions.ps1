if (-not ([System.Management.Automation.PSTypeName]"SslVerification").Type) {
    if ($isPsCore) {
        $sslCallbackCode = @"
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;

public static class SslVerification
{
    public static bool DisabledServerCertificateValidationCallback(object sender, X509Certificate certificate, X509Chain chain, SslPolicyErrors sslPolicyErrors) { return true; }
    public static void DisableSsl(System.Net.Http.HttpClientHandler handler) { handler.ServerCertificateCustomValidationCallback = DisabledServerCertificateValidationCallback; }
}
"@
        Add-Type -TypeDefinition $sslCallbackCode -Language CSharp -WarningAction SilentlyContinue | Out-Null
    }
    else {
        $sslCallbackCode = @"
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;

public static class SslVerification
{
    public static bool DisabledServerCertificateValidationCallback(object sender, X509Certificate certificate, X509Chain chain, SslPolicyErrors sslPolicyErrors) { return true; }
    public static void Disable() { System.Net.ServicePointManager.ServerCertificateValidationCallback = DisabledServerCertificateValidationCallback; }
    public static void Enable()  { System.Net.ServicePointManager.ServerCertificateValidationCallback = null; }
    public static void DisableSsl(System.Net.Http.HttpClientHandler handler) { handler.ServerCertificateCustomValidationCallback = DisabledServerCertificateValidationCallback; }
}
"@
        Add-Type -TypeDefinition $sslCallbackCode -Language CSharp -ReferencedAssemblies @('System.Net.Http') -WarningAction SilentlyContinue | Out-Null
    }
}

function Get-DefaultCredential {
    Param(
        [string]$Message,
        [string]$DefaultUserName,
        [switch]$doNotAskForCredential
    )

    if (Test-Path "$($bcContainerHelperConfig.hostHelperFolder)\settings.ps1") {
        . "$($bcContainerHelperConfig.hostHelperFolder)\settings.ps1"
        if (Test-Path "$($bcContainerHelperConfig.hostHelperFolder)\aes.key") {
            $key = Get-Content -Path "$($bcContainerHelperConfig.hostHelperFolder)\aes.key"
            New-Object System.Management.Automation.PSCredential ($DefaultUserName, (ConvertTo-SecureString -String $adminPassword -Key $key))
        }
        else {
            New-Object System.Management.Automation.PSCredential ($DefaultUserName, (ConvertTo-SecureString -String $adminPassword))
        }
    }
    else {
        if (!$doNotAskForCredential) {
            Get-Credential -username $DefaultUserName -Message $Message
        }
    }
}

function Get-DefaultSqlCredential {
    Param(
        [Parameter(Mandatory = $true)]
        [string]$containerName,
        [System.Management.Automation.PSCredential]$sqlCredential = $null,
        [switch]$doNotAskForCredential
    )

    if ($sqlCredential -eq $null) {
        $containerAuth = Get-NavContainerAuth -containerName $containerName
        if ($containerAuth -ne "Windows") {
            $sqlCredential = Get-DefaultCredential -DefaultUserName "" -Message "Please enter the SQL Server System Admin credentials for container $containerName" -doNotAskForCredential:$doNotAskForCredential
        }
    }
    $sqlCredential
}

function CmdDo {
    Param(
        [string] $command = "",
        [string] $arguments = "",
        [switch] $silent,
        [switch] $returnValue,
        [string] $inputStr = "",
        [string] $messageIfCmdNotFound = ""
    )

    $oldNoColor = "$env:NO_COLOR"
    $env:NO_COLOR = "Y"
    $oldEncoding = [Console]::OutputEncoding
    try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
    try {
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = $command
        $pinfo.RedirectStandardError = $true
        $pinfo.RedirectStandardOutput = $true
        if ($inputStr) {
            $pinfo.RedirectStandardInput = $true
        }
        $pinfo.WorkingDirectory = Get-Location
        $pinfo.UseShellExecute = $false
        $pinfo.Arguments = $arguments
        $pinfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Minimized

        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $pinfo
        $p.Start() | Out-Null
        if ($inputStr) {
            $p.StandardInput.WriteLine($inputStr)
            $p.StandardInput.Close()
        }
        $outtask = $p.StandardOutput.ReadToEndAsync()
        $errtask = $p.StandardError.ReadToEndAsync()
        $p.WaitForExit();

        $message = $outtask.Result
        $err = $errtask.Result

        if ("$err" -ne "") {
            $message += "$err"
        }

        $message = $message.Trim()

        if ($p.ExitCode -eq 0) {
            if (!$silent) {
                Write-Host $message
            }
            if ($returnValue) {
                $message.Replace("`r", "").Split("`n")
            }
        }
        else {
            $message += "`n`nExitCode: " + $p.ExitCode + "`nCommandline: $command $arguments"
            throw $message
        }
    }
    catch [System.ComponentModel.Win32Exception] {
        if ($_.Exception.NativeErrorCode -eq 2) {
            if ($messageIfCmdNotFound) {
                throw $messageIfCmdNotFound
            }
            else {
                throw "Command $command not found, you might need to install that command."
            }
        }
        else {
            throw
        }
    }
    finally {
        try { [Console]::OutputEncoding = $oldEncoding } catch {}
        $env:NO_COLOR = $oldNoColor
    }
}

function DockerDo {
    Param(
        [Parameter(Mandatory = $true)]
        [string]$imageName,
        [ValidateSet('run', 'start', 'pull', 'restart', 'stop', 'rmi','build')]
        [string]$command = "run",
        [switch]$accept_eula,
        [switch]$accept_outdated,
        [switch]$detach,
        [switch]$silent,
        [string[]]$parameters = @()
    )

    if ($accept_eula) {
        $parameters += "--env accept_eula=Y"
    }
    if ($accept_outdated) {
        $parameters += "--env accept_outdated=Y"
    }
    if ($detach) {
        $parameters += "--detach"
    }

    $result = $true
    $arguments = ("$command " + [string]::Join(" ", $parameters) + " $imageName")

    # Retry logic for docker pull to handle transient CDN/WAF errors.
    # Azure Front Door occasionally blocks MCR requests, returning an HTML error page
    # ("The request is blocked") instead of a proper registry response. This causes docker
    # to report "pull access denied" even though the image exists. Observed WAF block
    # windows can last well over a minute, so the backoff schedule (5s, 15s, 30s, 60s,
    # 120s; total ~3.8 min) is deliberately patient rather than aggressive early.
    $retryDelays = @(5, 15, 30, 60, 120)
    $maxRetries = 0
    if ($command -eq "pull") {
        $maxRetries = $retryDelays.Count
    }
    $attempt = 0

    while ($true) {
        $attempt++

        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = "docker.exe"
        $pinfo.RedirectStandardError = $true
        $pinfo.RedirectStandardOutput = $true
        $pinfo.UseShellExecute = $false
        $pinfo.Arguments = $arguments
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $pinfo
        $p.Start() | Out-Null

        $outtask = $null
        $errtask = $p.StandardError.ReadToEndAsync()
        $out = ""
        $err = ""

        do {
            if ($outtask -eq $null) {
                $outtask = $p.StandardOutput.ReadLineAsync()
            }
            $outtask.Wait(100) | Out-Null
            if ($outtask.IsCompleted) {
                $outStr = $outtask.Result
                if ($outStr -eq $null) {
                    break
                }
                if (!$silent) {
                    Write-Host $outStr
                }
                $out += $outStr
                $outtask = $null
                if ($outStr.StartsWith("Please login")) {
                    $registry = $imageName.Split("/")[0]
                    if ($registry -eq "bcinsider.azurecr.io" -or $registry -eq "bcprivate.azurecr.io") {
                        throw "You need to login to $registry prior to pulling images. Get credentials through the ReadyToGo program on Microsoft Collaborate."
                    }
                    else {
                        throw "You need to login to $registry prior to pulling images."
                    }
                }
            }
            elseif ($outtask.IsCanceled) {
                break
            }
            elseif ($outtask.IsFaulted) {
                break
            }
        } while (!($p.HasExited))

        $err = $errtask.Result
        $p.WaitForExit();
        $exitCode = $p.ExitCode
        $p.Dispose();

        if ($exitCode -ne 0) {
            # Detect transient Azure Front Door CDN/WAF blocks on MCR.
            # When this happens, docker reports "pull access denied ... denied: <!DOCTYPE html..."
            # containing an HTML page with "The request is blocked" from Azure Front Door.
            # Only retry for pull commands when the HTML WAF/CDN block signature is present;
            # genuine auth failures and missing-image errors do not contain HTML and fail immediately.
            if ($attempt -le $maxRetries -and $err -match 'pull access denied' -and ($err -match '<html' -or $err -match 'The request is blocked')) {
                $waitTime = $retryDelays[$attempt - 1]
                if (!$silent) {
                    Write-Host "Docker pull failed due to a CDN/WAF block (attempt $attempt of $($maxRetries + 1)), retrying in $waitTime seconds..."
                }
                Start-Sleep -Seconds $waitTime
                continue
            }

            $result = $false
            if (!$silent) {
                $out = $out.Trim()
                $err = $err.Trim()
                if ($command -eq "run" -and "$out" -ne "") {
                    Docker rm $out -f
                }
                $errorMessage = ""
                if ("$err" -ne "") {
                    $errorMessage += "$err`r`n"
                    if ($err.Contains("authentication required")) {
                        $registry = $imageName.Split("/")[0]
                        if ($registry -eq "bcinsider.azurecr.io" -or $registry -eq "bcprivate.azurecr.io") {
                            $errorMessage += "You need to login to $registry prior to pulling images. Get credentials through the ReadyToGo program on Microsoft Collaborate.`r`n"
                        }
                        else {
                            $errorMessage += "You need to login to $registry prior to pulling images.`r`n"
                        }
                    }
                }
                $errorMessage += "ExitCode: " + $exitCode + "`r`nCommandline: docker $arguments"
                Write-Error -Message $errorMessage
            }
        }
        break
    }
    $result
}

function Get-NavContainerAuth {
    Param
    (
        [string]$containerName
    )

    Invoke-ScriptInNavContainer -containerName $containerName -ScriptBlock {
        $customConfigFile = Join-Path (Get-Item "C:\Program Files\Microsoft Dynamics NAV\*\Service").FullName "CustomSettings.config"
        [xml]$customConfig = [System.IO.File]::ReadAllText($customConfigFile)
        $customConfig.SelectSingleNode("//appSettings/add[@key='ClientServicesCredentialType']").Value
    }
}

function Check-BcContainerName {
    Param
    (
        [string]$containerName = ""
    )

    if ($containerName -eq "") {
        throw "Container name cannot be empty"
    }

    if ($containerName.Length -gt 15) {
        Write-Host "WARNING: Container name should not exceed 15 characters"
    }

    $first = $containerName.ToLowerInvariant()[0]
    if ($first -lt "a" -or $first -gt "z") {
        throw "Container name should start with a letter (a-z)"
    }

    $containerName.ToLowerInvariant().ToCharArray() | ForEach-Object {
        if (($_ -lt "a" -or $_ -gt "z") -and ($_ -lt "0" -or $_ -gt "9") -and ($_ -ne "-")) {
            throw "Container name contains invalid characters. Allowed characters are letters (a-z), numbers (0-9) and dashes (-)"
        }
    }
}

function AssumeNavContainer {
    Param
    (
        [string]$containerOrImageName = "",
        [string]$functionName = ""
    )

    $inspect = docker inspect $containerOrImageName | ConvertFrom-Json
    if ($inspect.Config.Labels.psobject.Properties.Match('maintainer').Count -eq 0 -or $inspect.Config.Labels.maintainer -ne "Dynamics SMB") {
        throw "Container $containerOrImageName is not a Business Central container"
    }
    [System.Version]$version = $inspect.Config.Labels.version

    if ("$functionName" -eq "") {
        $functionName = (Get-Variable MyInvocation -Scope 1).Value.MyCommand.Name
    }
    if ($version.Major -ge 15) {
        throw "Container $containerOrImageName does not support the function $functionName"
    }
}

function Expand-7zipArchive {
    Param (
        [Parameter(Mandatory = $true)]
        [string] $Path,
        [string] $DestinationPath,
        [switch] $use7zipIfAvailable = $bcContainerHelperConfig.use7zipIfAvailable,
        [switch] $silent
    )

    $7zipPath = "$env:ProgramFiles\7-Zip\7z.exe"
    $use7zip = $false
    if ($use7zipIfAvailable -and (Test-Path -Path $7zipPath -PathType Leaf)) {
        try {
            $use7zip = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($7zipPath).FileMajorPart -ge 19
        }
        catch {
            $use7zip = $false
        }
    }

    if ($use7zip) {
        if (!$silent) { Write-Host "using 7zip" }
        Set-Alias -Name 7z -Value $7zipPath
        $command = '7z x "{0}" -o"{1}" -aoa -r' -f $Path, $DestinationPath
        $global:LASTEXITCODE = 0
        Invoke-Expression -Command $command | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Error $LASTEXITCODE extracting $path"
        }
    }
    else {
        if (!$silent) { Write-Host "using Expand-Archive" }
        if ([System.IO.Path]::GetExtension($path) -eq '.zip') {
            Expand-Archive -Path $Path -DestinationPath "$DestinationPath" -Force
        }
        else {
            $tempZip = Join-Path ([System.IO.Path]::GetTempPath()) "$([guid]::NewGuid().ToString()).zip"
            Copy-Item -Path $Path -Destination $tempZip -Force
            try {
                Expand-Archive -Path $tempZip -DestinationPath "$DestinationPath" -Force
            }
            finally {
                Remove-Item -Path $tempZip -Force
            }
        }
    }
}

function GetSymbolFiles {
    param (
        [string] $path,
        [string] $baseName
    )

    $filterName = @("$($baseName)_*.*.*.*.app", "$($baseName).app")
    $appFiles = @(Get-ChildItem -Path $path -Filter $filterName[0])

    if (!$appFiles) {
        $appFiles = @(Get-ChildItem -Path $path -Filter $filterName[1])
    }

    return $appFiles
}

function GetTestToolkitApps {
    Param(
        [string] $containerName,
        [string] $compilerFolder,
        [switch] $includeTestLibrariesOnly,
        [switch] $includeTestFrameworkOnly,
        [switch] $includeTestRunnerOnly,
        [switch] $includePerformanceToolkit
    )

    if ($compilerFolder) {
        $symbolsFolder = Join-Path $compilerFolder "symbols"
        # Add Test Framework
        $apps = @()
        $baseAppFile = GetSymbolFiles -path $symbolsFolder -baseName 'Microsoft_Base Application' | Select-Object -First 1
        $baseAppInfo = Get-AppJsonFromAppFile -appFile $baseAppFile.FullName

        $version = [Version]$baseAppInfo.version
        if ($version -ge [Version]"19.0.0.0") {
            $apps += @('Microsoft_Permissions Mock')
        }
        $apps += @('Microsoft_Test Runner')
        if (!$includeTestRunnerOnly) {
            $apps += @('Microsoft_Any', 'Microsoft_Library Assert', 'Microsoft_Library Variable Storage')
            if (!$includeTestFrameworkOnly) {
                # Add Test Libraries
                $apps += @('Microsoft_System Application Test Library', 'Microsoft_Business Foundation Test Libraries', 'Microsoft_Application Test Library', 'Microsoft_Tests-TestLibraries','Microsoft_AI Test Toolkit')
                if (!$includeTestLibrariesOnly) {
                    # Add Tests
                    if ($version -ge [Version]"18.0.0.0") {
                        $apps += @('Microsoft_System Application Test', 'Microsoft_Business Foundation Tests', 'Microsoft_Tests-*')
                    }
                }
            }
        }
        if ($includePerformanceToolkit) {
            $apps += @('Microsoft_Performance Toolkit')
            if (!$includeTestFrameworkOnly) {
                $apps += @('Microsoft_Performance Toolkit *')
            }
        }

        $appFiles = @()

        $apps | ForEach-Object {
            $tempAppFiles = GetSymbolFiles -path $symbolsFolder -baseName $_
            $appFiles += @($tempAppFiles | Where-Object {($version.Major -ge 17 -or ($_.Name -notlike 'Microsoft_Tests-Marketing*.app')) -and $_.Name -notlike "Microsoft_Tests-SINGLESERVER*.app"} | ForEach-Object { $_.FullName })
        }

        $appFiles | Select-Object -Unique
    }
    else {
        Invoke-ScriptInBCContainer -containerName $containerName -scriptblock { Param($includeTestLibrariesOnly, $includeTestFrameworkOnly, $includeTestRunnerOnly, $includePerformanceToolkit)

            $version = [Version](Get-Item "C:\Program Files\Microsoft Dynamics NAV\*\Service\Microsoft.Dynamics.Nav.Server.exe").VersionInfo.FileVersion

            # Add Test Framework
            $apps = @()
            if (($version -ge [Version]"19.0.0.0") -and (Test-Path 'C:\Applications\TestFramework\TestLibraries\permissions mock')) {
                $apps += @(get-childitem -Path "C:\Applications\TestFramework\TestLibraries\permissions mock\*.*" -recurse -filter "*.app")
            }
            $apps += @(get-childitem -Path "C:\Applications\TestFramework\TestRunner\*.*" -recurse -filter "*.app")

            if (!$includeTestRunnerOnly) {
                $apps += @(get-childitem -Path "C:\Applications\TestFramework\TestLibraries\*.*" -recurse -filter "*.app")

                if (!$includeTestFrameworkOnly) {
                    # Add Test Libraries
                    $apps += "Microsoft_System Application Test Library.app", "Microsoft_Business Foundation Test Libraries.app", 'Microsoft_Application Test Library.app', "Microsoft_Tests-TestLibraries.app", 'Microsoft_AI Test Toolkit.app' | ForEach-Object {
                        @(get-childitem -Path "C:\Applications\*.*" -recurse -filter $_)
                    }

                    if (!$includeTestLibrariesOnly) {
                        # Add Tests
                        if ($version -ge [Version]"18.0.0.0") {
                            $apps += "Microsoft_System Application Test.app", "Microsoft_Business Foundation Tests.app" | ForEach-Object {
                                @(get-childitem -Path "C:\Applications\*.*" -recurse -filter $_)
                            }
                        }
                        $apps += @(get-childitem -Path "C:\Applications\*.*" -recurse -filter "Microsoft_Tests-*.app") | Where-Object { $_ -notlike "*\Microsoft_Tests-TestLibraries.app" -and ($version.Major -ge 17 -or ($_ -notlike "*\Microsoft_Tests-Marketing.app")) -and $_ -notlike "*\Microsoft_Tests-SINGLESERVER.app" }
                    }
                }
            }

            if ($includePerformanceToolkit) {
                $apps += @(get-childitem -Path "C:\Applications\TestFramework\PerformanceToolkit\*.*" -recurse -filter "*Toolkit.app")
                if (!$includeTestFrameworkOnly) {
                    $apps += @(get-childitem -Path "C:\Applications\TestFramework\PerformanceToolkit\*.*" -recurse -filter "*.app" -exclude "*Toolkit.app")
                }
            }

            $apps | ForEach-Object {
                $appFile = Get-ChildItem -path "c:\applications.*\*.*" -recurse -filter ($_.Name).Replace(".app", "_*.app")
                if (!($appFile)) {
                    $appFile = $_
                }
                $appFile.FullName
            }
        } -argumentList $includeTestLibrariesOnly, $includeTestFrameworkOnly, $includeTestRunnerOnly, $includePerformanceToolkit
    }
}

function GetExtendedErrorMessage {
    Param(
        $errorRecord
    )

    $exception = $errorRecord.Exception
    $message = $exception.Message

    try {
        if ($errorRecord.ErrorDetails) {
            $errorDetails = $errorRecord.ErrorDetails | ConvertFrom-Json
            $message += " $($errorDetails.error)`r`n$($errorDetails.error_description)"
        }
    }
    catch {}
    try {
        if ($exception -is [System.Management.Automation.MethodInvocationException]) {
            $exception = $exception.InnerException
        }
        if ($exception -is [System.Net.Http.HttpRequestException]) {
            $message += "`r`n$($exception.Message)"
            if ($exception.InnerException) {
                if ($exception.InnerException -and $exception.InnerException.Message) {
                    $message += "`r`n$($exception.InnerException.Message)"
                }
            }

        }
        else {
            $webException = [System.Net.WebException]$exception
            $webResponse = $webException.Response
            try {
                if ($webResponse.StatusDescription) {
                    $message += "`r`n$($webResponse.StatusDescription)"
                }
            }
            catch {}
            $reqstream = $webResponse.GetResponseStream()
            $sr = new-object System.IO.StreamReader $reqstream
            $result = $sr.ReadToEnd()
        }
        try {
            $json = $result | ConvertFrom-Json
            $message += "`r`n$($json.Message)"
        }
        catch {
            $message += "`r`n$result"
        }
        try {
            $correlationX = $webResponse.GetResponseHeader('ms-correlation-x')
            if ($correlationX) {
                $message += " (ms-correlation-x = $correlationX)"
            }
        }
        catch {}
    }
    catch {}
    $message
}

function CopyAppFilesToFolder {
    Param(
        $appFiles,
        [string] $folder
    )

    if ($appFiles -is [String]) {
        if (!(Test-Path $appFiles)) {
            $appFiles = @($appFiles.Split(',').Trim() | Where-Object { $_ })
        }
    }
    if (!(Test-Path $folder)) {
        New-Item -Path $folder -ItemType Directory | Out-Null
    }
    $appFiles | Where-Object { $_ } | ForEach-Object {
        $appFile = "$_"
        if ($appFile -like "http://*" -or $appFile -like "https://*") {
            $appUrl = $appFile
            $appFileFolder = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
            $appFile = Join-Path $appFileFolder ([Uri]::UnescapeDataString([System.IO.Path]::GetFileName($appUrl.Split('?')[0].TrimEnd('/'))))
            Download-File -sourceUrl $appUrl -destinationFile $appFile
            CopyAppFilesToFolder -appFile $appFile -folder $folder
            if (Test-Path $appFileFolder) {
                Remove-Item -Path $appFileFolder -Force -Recurse
            }
        }
        elseif (Test-Path $appFile -PathType Container) {
            Get-ChildItem $appFile -Recurse -File | ForEach-Object {
                CopyAppFilesToFolder -appFile $_.FullName -folder $folder
            }
        }
        elseif (Test-Path $appFile -PathType Leaf) {
            Get-ChildItem $appFile | ForEach-Object {
                $appFile = $_.FullName
                if ($appFile -like "*.app") {
                    $destFileName = [System.IO.Path]::GetFileName($appFile)
                    $destFile = Join-Path $folder $destFileName
                    if ((Test-Path $destFile) -and ((Get-FileHash -Path $appFile).Hash -ne (Get-FileHash -Path $destFile).Hash)) {
                        Write-DevOpsWarning -Message "$destFileName already exists, it looks like you have multiple app files with the same name. App filenames must be unique."
                    }
                    Copy-Item -Path $appFile -Destination $destFile -Force
                    $destFile
                }
                elseif ([string]::new([char[]](Get-Content $appFile @byteEncodingParam -TotalCount 2)) -eq "PK") {
                    $tmpFolder = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
                    $copied = $false
                    try {
                        if ($appFile -notlike "*.zip") {
                            $orgAppFile = $appFile
                            $appFile = Join-Path ([System.IO.Path]::GetTempPath()) "$([System.IO.Path]::GetFileName($orgAppFile)).zip"
                            Copy-Item $orgAppFile $appFile
                            $copied = $true
                        }
                        Expand-Archive $appfile -DestinationPath $tmpFolder -Force
                        CopyAppFilesToFolder -appFiles $tmpFolder -folder $folder
                    }
                    finally {
                        Remove-Item -Path $tmpFolder -Recurse -Force
                        if ($copied) { Remove-Item -Path $appFile -Force }
                    }
                }
            }
        }
        else {
            Write-DevOpsWarning -Message "File not found: $appFile"
        }
    }
}

function getCountryCode {
    Param(
        [string] $countryCode
    )

    $countryCodes = @{
        "Afghanistan"                                  = "AF"
        "Åland Islands"                                = "AX"
        "Albania"                                      = "AL"
        "Algeria"                                      = "DZ"
        "American Samoa"                               = "AS"
        "AndorrA"                                      = "AD"
        "Angola"                                       = "AO"
        "Anguilla"                                     = "AI"
        "Antarctica"                                   = "AQ"
        "Antigua and Barbuda"                          = "AG"
        "Argentina"                                    = "AR"
        "Armenia"                                      = "AM"
        "Aruba"                                        = "AW"
        "Australia"                                    = "AU"
        "Austria"                                      = "AT"
        "Azerbaijan"                                   = "AZ"
        "Bahamas"                                      = "BS"
        "Bahrain"                                      = "BH"
        "Bangladesh"                                   = "BD"
        "Barbados"                                     = "BB"
        "Belarus"                                      = "BY"
        "Belgium"                                      = "BE"
        "Belize"                                       = "BZ"
        "Benin"                                        = "BJ"
        "Bermuda"                                      = "BM"
        "Bhutan"                                       = "BT"
        "Bolivia"                                      = "BO"
        "Bosnia and Herzegovina"                       = "BA"
        "Botswana"                                     = "BW"
        "Bouvet Island"                                = "BV"
        "Brazil"                                       = "BR"
        "British Indian Ocean Territory"               = "IO"
        "Brunei Darussalam"                            = "BN"
        "Bulgaria"                                     = "BG"
        "Burkina Faso"                                 = "BF"
        "Burundi"                                      = "BI"
        "Cambodia"                                     = "KH"
        "Cameroon"                                     = "CM"
        "Canada"                                       = "CA"
        "Cape Verde"                                   = "CV"
        "Cayman Islands"                               = "KY"
        "Central African Republic"                     = "CF"
        "Chad"                                         = "TD"
        "Chile"                                        = "CL"
        "China"                                        = "CN"
        "Christmas Island"                             = "CX"
        "Cocos (Keeling) Islands"                      = "CC"
        "Colombia"                                     = "CO"
        "Comoros"                                      = "KM"
        "Congo"                                        = "CG"
        "Congo, The Democratic Republic of the"        = "CD"
        "Cook Islands"                                 = "CK"
        "Costa Rica"                                   = "CR"
        "Cote D'Ivoire"                                = "CI"
        "Croatia"                                      = "HR"
        "Cuba"                                         = "CU"
        "Cyprus"                                       = "CY"
        "Czech Republic"                               = "CZ"
        "Denmark"                                      = "DK"
        "Djibouti"                                     = "DJ"
        "Dominica"                                     = "DM"
        "Dominican Republic"                           = "DO"
        "Ecuador"                                      = "EC"
        "Egypt"                                        = "EG"
        "El Salvador"                                  = "SV"
        "Equatorial Guinea"                            = "GQ"
        "Eritrea"                                      = "ER"
        "Estonia"                                      = "EE"
        "Ethiopia"                                     = "ET"
        "Falkland Islands (Malvinas)"                  = "FK"
        "Faroe Islands"                                = "FO"
        "Fiji"                                         = "FJ"
        "Finland"                                      = "FI"
        "France"                                       = "FR"
        "French Guiana"                                = "GF"
        "French Polynesia"                             = "PF"
        "French Southern Territories"                  = "TF"
        "Gabon"                                        = "GA"
        "Gambia"                                       = "GM"
        "Georgia"                                      = "GE"
        "Germany"                                      = "DE"
        "Ghana"                                        = "GH"
        "Gibraltar"                                    = "GI"
        "Greece"                                       = "GR"
        "Greenland"                                    = "GL"
        "Grenada"                                      = "GD"
        "Guadeloupe"                                   = "GP"
        "Guam"                                         = "GU"
        "Guatemala"                                    = "GT"
        "Guernsey"                                     = "GG"
        "Guinea"                                       = "GN"
        "Guinea-Bissau"                                = "GW"
        "Guyana"                                       = "GY"
        "Haiti"                                        = "HT"
        "Heard Island and Mcdonald Islands"            = "HM"
        "Holy See (Vatican City State)"                = "VA"
        "Honduras"                                     = "HN"
        "Hong Kong"                                    = "HK"
        "Hungary"                                      = "HU"
        "Iceland"                                      = "IS"
        "India"                                        = "IN"
        "Indonesia"                                    = "ID"
        "Iran, Islamic Republic Of"                    = "IR"
        "Iraq"                                         = "IQ"
        "Ireland"                                      = "IE"
        "Isle of Man"                                  = "IM"
        "Israel"                                       = "IL"
        "Italy"                                        = "IT"
        "Jamaica"                                      = "JM"
        "Japan"                                        = "JP"
        "Jersey"                                       = "JE"
        "Jordan"                                       = "JO"
        "Kazakhstan"                                   = "KZ"
        "Kenya"                                        = "KE"
        "Kiribati"                                     = "KI"
        "Korea, Democratic People's Republic of"       = "KP"
        "Korea, Republic of"                           = "KR"
        "Kuwait"                                       = "KW"
        "Kyrgyzstan"                                   = "KG"
        "Lao People's Democratic Republic"             = "LA"
        "Latvia"                                       = "LV"
        "Lebanon"                                      = "LB"
        "Lesotho"                                      = "LS"
        "Liberia"                                      = "LR"
        "Libyan Arab Jamahiriya"                       = "LY"
        "Liechtenstein"                                = "LI"
        "Lithuania"                                    = "LT"
        "Luxembourg"                                   = "LU"
        "Macao"                                        = "MO"
        "Macedonia, The Former Yugoslav Republic of"   = "MK"
        "Madagascar"                                   = "MG"
        "Malawi"                                       = "MW"
        "Malaysia"                                     = "MY"
        "Maldives"                                     = "MV"
        "Mali"                                         = "ML"
        "Malta"                                        = "MT"
        "Marshall Islands"                             = "MH"
        "Martinique"                                   = "MQ"
        "Mauritania"                                   = "MR"
        "Mauritius"                                    = "MU"
        "Mayotte"                                      = "YT"
        "Mexico"                                       = "MX"
        "Micronesia, Federated States of"              = "FM"
        "Moldova, Republic of"                         = "MD"
        "Monaco"                                       = "MC"
        "Mongolia"                                     = "MN"
        "Montserrat"                                   = "MS"
        "Morocco"                                      = "MA"
        "Mozambique"                                   = "MZ"
        "Myanmar"                                      = "MM"
        "Namibia"                                      = "NA"
        "Nauru"                                        = "NR"
        "Nepal"                                        = "NP"
        "Netherlands"                                  = "NL"
        "Netherlands Antilles"                         = "AN"
        "New Caledonia"                                = "NC"
        "New Zealand"                                  = "NZ"
        "Nicaragua"                                    = "NI"
        "Niger"                                        = "NE"
        "Nigeria"                                      = "NG"
        "Niue"                                         = "NU"
        "Norfolk Island"                               = "NF"
        "Northern Mariana Islands"                     = "MP"
        "Norway"                                       = "NO"
        "Oman"                                         = "OM"
        "Pakistan"                                     = "PK"
        "Palau"                                        = "PW"
        "Palestinian Territory, Occupied"              = "PS"
        "Panama"                                       = "PA"
        "Papua New Guinea"                             = "PG"
        "Paraguay"                                     = "PY"
        "Peru"                                         = "PE"
        "Philippines"                                  = "PH"
        "Pitcairn"                                     = "PN"
        "Poland"                                       = "PL"
        "Portugal"                                     = "PT"
        "Puerto Rico"                                  = "PR"
        "Qatar"                                        = "QA"
        "Reunion"                                      = "RE"
        "Romania"                                      = "RO"
        "Russian Federation"                           = "RU"
        "RWANDA"                                       = "RW"
        "Saint Helena"                                 = "SH"
        "Saint Kitts and Nevis"                        = "KN"
        "Saint Lucia"                                  = "LC"
        "Saint Pierre and Miquelon"                    = "PM"
        "Saint Vincent and the Grenadines"             = "VC"
        "Samoa"                                        = "WS"
        "San Marino"                                   = "SM"
        "Sao Tome and Principe"                        = "ST"
        "Saudi Arabia"                                 = "SA"
        "Senegal"                                      = "SN"
        "Serbia and Montenegro"                        = "CS"
        "Seychelles"                                   = "SC"
        "Sierra Leone"                                 = "SL"
        "Singapore"                                    = "SG"
        "Slovakia"                                     = "SK"
        "Slovenia"                                     = "SI"
        "Solomon Islands"                              = "SB"
        "Somalia"                                      = "SO"
        "South Africa"                                 = "ZA"
        "South Georgia and the South Sandwich Islands" = "GS"
        "Spain"                                        = "ES"
        "Sri Lanka"                                    = "LK"
        "Sudan"                                        = "SD"
        "Suriname"                                     = "SR"
        "Svalbard and Jan Mayen"                       = "SJ"
        "Swaziland"                                    = "SZ"
        "Sweden"                                       = "SE"
        "Switzerland"                                  = "CH"
        "Syrian Arab Republic"                         = "SY"
        "Taiwan, Province of China"                    = "TW"
        "Tajikistan"                                   = "TJ"
        "Tanzania, United Republic of"                 = "TZ"
        "Thailand"                                     = "TH"
        "Timor-Leste"                                  = "TL"
        "Togo"                                         = "TG"
        "Tokelau"                                      = "TK"
        "Tonga"                                        = "TO"
        "Trinidad and Tobago"                          = "TT"
        "Tunisia"                                      = "TN"
        "Turkey"                                       = "TR"
        "Turkmenistan"                                 = "TM"
        "Turks and Caicos Islands"                     = "TC"
        "Tuvalu"                                       = "TV"
        "Uganda"                                       = "UG"
        "Ukraine"                                      = "UA"
        "United Arab Emirates"                         = "AE"
        "United Kingdom"                               = "GB"
        "United States"                                = "US"
        "United States Minor Outlying Islands"         = "UM"
        "Uruguay"                                      = "UY"
        "Uzbekistan"                                   = "UZ"
        "Vanuatu"                                      = "VU"
        "Venezuela"                                    = "VE"
        "Viet Nam"                                     = "VN"
        "Virgin Islands, British"                      = "VG"
        "Virgin Islands, U.S."                         = "VI"
        "Wallis and Futuna"                            = "WF"
        "Western Sahara"                               = "EH"
        "Yemen"                                        = "YE"
        "Zambia"                                       = "ZM"
        "Zimbabwe"                                     = "ZW"
        "Hong Kong SAR"                                = "HK"
        "Serbia"                                       = "RS"
        "Korea"                                        = "KR"
        "Taiwan"                                       = "TW"
        "Vietnam"                                      = "VN"
    }

    $countryCode = $countryCode.Trim()
    if ($countryCodes.ContainsValue($countryCode.ToUpperInvariant())) {
        return $countryCode.ToLowerInvariant()
    }
    elseif ($countryCodes.ContainsKey($countryCode)) {
        return ($countryCodes[$countryCode]).ToLowerInvariant()
    }
    else {
        throw "Country code $countryCode is illegal"
    }
}

function Get-WWWRootPath {
    $inetstp = Get-Item "HKLM:\SOFTWARE\Microsoft\InetStp" -ErrorAction SilentlyContinue
    if ($inetstp) {
        [System.Environment]::ExpandEnvironmentVariables($inetstp.GetValue("PathWWWRoot"))
    }
    else {
        ""
    }
}

function Parse-JWTtoken([string]$token) {
    if ($token.Contains(".") -and $token.StartsWith("eyJ")) {
        $tokenPayload = $token.Split(".")[1].Replace('-', '+').Replace('_', '/')
        while ($tokenPayload.Length % 4) { $tokenPayload += "=" }
        return [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($tokenPayload)) | ConvertFrom-Json
    }
    throw "Invalid token"
}

function Test-BcAuthContext {
    Param(
        $bcAuthContext
    )

    if (!(($bcAuthContext -is [Hashtable]) -and
          ($bcAuthContext.ContainsKey('ClientID')) -and
          ($bcAuthContext.ContainsKey('Credential')) -and
          ($bcAuthContext.ContainsKey('authority')) -and
          ($bcAuthContext.ContainsKey('RefreshToken')) -and
          ($bcAuthContext.ContainsKey('UtcExpiresOn')) -and
          ($bcAuthContext.ContainsKey('tenantID')) -and
          ($bcAuthContext.ContainsKey('AccessToken')) -and
          ($bcAuthContext.ContainsKey('includeDeviceLogin')) -and
          ($bcAuthContext.ContainsKey('deviceLoginTimeout')))) {
        throw 'BcAuthContext should be a HashTable created by New-BcAuthContext.'
    }
}

Function CreatePsTestToolFolder {
    Param(
        [string] $containerName,
        [string] $PsTestToolFolder
    )

    $PsTestFunctionsPath = Join-Path $PsTestToolFolder "PsTestFunctions.ps1"
    $ClientContextPath = Join-Path $PsTestToolFolder "ClientContext.ps1"
    $newtonSoftDllPath = Join-Path $PsTestToolFolder "Newtonsoft.Json.dll"
    $clientDllPath = Join-Path $PsTestToolFolder "Microsoft.Dynamics.Framework.UI.Client.dll"

    if (!(Test-Path -Path $PsTestToolFolder -PathType Container)) {
        New-Item -Path $PsTestToolFolder -ItemType Directory | Out-Null
        Copy-Item -Path (Join-Path $PSScriptRoot "AppHandling\PsTestFunctions.ps1") -Destination $PsTestFunctionsPath -Force
        Copy-Item -Path (Join-Path $PSScriptRoot "AppHandling\ClientContext.ps1") -Destination $ClientContextPath -Force
    }

    Invoke-ScriptInBcContainer -containerName $containerName { Param([string] $myNewtonSoftDllPath, [string] $myClientDllPath)
        if (!(Test-Path $myNewtonSoftDllPath)) {
            $newtonSoftDllPath = "C:\Program Files\Microsoft Dynamics NAV\*\Service\Management\Newtonsoft.Json.dll"
            if (!(Test-Path $newtonSoftDllPath)) {
                $newtonSoftDllPath = "C:\Program Files\Microsoft Dynamics NAV\*\Service\Newtonsoft.Json.dll"
            }
            $newtonSoftDllPath = (Get-Item $newtonSoftDllPath).FullName
            Copy-Item -Path $newtonSoftDllPath -Destination $myNewtonSoftDllPath
        }
        if (!(Test-Path $myClientDllPath)) {
            $clientDllPath = "C:\Test Assemblies\Microsoft.Dynamics.Framework.UI.Client.dll"
            Copy-Item -Path $clientDllPath -Destination $myClientDllPath
            $antiSSRFdll = Join-Path ([System.IO.Path]::GetDirectoryName($clientDllPath)) 'Microsoft.Internal.AntiSSRF.dll'
            if (Test-Path $antiSSRFdll) {
                Copy-Item -Path $antiSSRFdll -Destination ([System.IO.Path]::GetDirectoryName($myClientDllPath))
            }
        }
    } -argumentList (Get-BcContainerPath -containerName $containerName -Path $newtonSoftDllPath), (Get-BcContainerPath -containerName $containerName -Path $clientDllPath)
}

function RandomChar([string]$str) {
    $rnd = Get-Random -Maximum $str.length
    [string]$str[$rnd]
}

function GetRandomPassword {
    $cons = 'bcdfghjklmnpqrstvwxz'
    $voc = 'aeiouy'
    $numbers = '0123456789'

    ((RandomChar $cons).ToUpper() + `
    (RandomChar $voc) + `
    (RandomChar $cons) + `
    (RandomChar $voc) + `
    (RandomChar $numbers) + `
    (RandomChar $numbers) + `
    (RandomChar $numbers) + `
    (RandomChar $numbers))
}

function getVolumeMountParameter($volumes, $hostPath, $containerPath) {
    $volume = $volumes | Where-Object { $_ -like "*|$hostPath" -or $_ -like "$hostPath|*" }
    if ($volume) {
        $volumeName = $volume.Split('|')[1]
        "--mount source=$($volumeName),target=$containerPath"
    }
    else {
        "--volume ""$($hostPath):$($containerPath)"""
    }
}

function testPfxCertificate([string] $pfxFile, [SecureString] $pfxPassword, [string] $certkind) {
    if (!(Test-Path $pfxFile)) {
        throw "$certkind certificate file does not exist"
    }
    try {
        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($pfxFile, $pfxPassword)
    }
    catch {
        throw "Unable to read $certkind certificate. Error was $($_.Exception.Message)"
    }
    if ([DateTime]::Now -gt $cert.NotAfter) {
        throw "$certkind certificate expired on $($cert.GetExpirationDateString())"
    }
    if ([DateTime]::Now -gt $cert.NotAfter.AddDays(-14)) {
        Write-Host -ForegroundColor Yellow "$certkind certificate will expire on $($cert.GetExpirationDateString())"
    }
}

function GetHash {
    param(
        [string] $str
    )

    $stream = [IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($str))
    (Get-FileHash -InputStream $stream -Algorithm SHA256).Hash
}

function DownloadFileLow {
    Param(
        [string] $sourceUrl,
        [string] $destinationFile,
        [switch] $dontOverwrite,
        [switch] $useDefaultCredentials,
        [switch] $skipCertificateCheck,
        [hashtable] $headers = @{"UserAgent" = "BcContainerHelper $bcContainerHelperVersion" },
        [int] $timeout = 100
    )

    $handler = New-Object System.Net.Http.HttpClientHandler
    if ($skipCertificateCheck) {
        Write-Host "Disabling SSL Verification on HttpClient"
        [SslVerification]::DisableSsl($handler)
    }
    if ($useDefaultCredentials) {
        $handler.UseDefaultCredentials = $true
    }
    $httpClient = New-Object System.Net.Http.HttpClient -ArgumentList $handler
    $httpClient.Timeout = [Timespan]::FromSeconds($timeout)
    $headers.Keys | ForEach-Object {
        $httpClient.DefaultRequestHeaders.Add($_, $headers."$_")
    }
    $stream = $null
    $fileStream = $null
    if ($dontOverwrite) {
        $fileMode = [System.IO.FileMode]::CreateNew
    }
    else {
        $fileMode = [System.IO.FileMode]::Create
    }
    try {
        $stream = $httpClient.GetStreamAsync($sourceUrl).GetAwaiter().GetResult()
        $fileStream = New-Object System.IO.Filestream($destinationFile, $fileMode)
        if (-not $stream.CopyToAsync($fileStream).Wait($timeout * 1000)) {
            throw "Timeout downloading file"
        }
    }
    finally {
        if ($fileStream) {
            $fileStream.Close()
            $fileStream.Dispose()
        }
        if ($stream) {
            $stream.Dispose()
        }
    }
}

function LoadDLL {
    Param(
        [string] $path
    )
    $bytes = [System.IO.File]::ReadAllBytes($path)
    [System.Reflection.Assembly]::Load($bytes) | Out-Null
}

function GetAppInfo {
    Param(
        [string[]] $appFiles,
        [string] $compilerFolder,
        [string] $cacheAppInfoPath = ''
    )

    Push-Location
    $appInfoCache = $null
    $cacheUpdated = $false
    if ($cacheAppInfoPath) {
        if (Test-Path $cacheAppInfoPath) {
            $appInfoCache = Get-Content -Path $cacheAppInfoPath -Encoding utf8 | ConvertFrom-Json
        }
        else {
            $appInfoCache = @{}
        }
        Set-Location (Split-Path $cacheAppInfoPath -parent)
    }
    Write-Host "Getting .app info $cacheAppInfoPath"
    $binPath = Join-Path $compilerFolder 'compiler/extension/bin'
    $alToolDll = ''
    if ($isLinux) {
        $alcPath = Join-Path $binPath 'linux'
        if (-not (Test-Path $alcPath)) { $alcPath = $binPath }
        $command = Join-Path $alcPath 'altool'
        if (Test-Path $command) {
            Write-Host "Use $command as altool executable."
            & /usr/bin/env sudo pwsh -command "& chmod +x $command"
            $alToolExists = $true
        }
        else {
            Write-Host "No altool executable found. Using dotnet to run altool.dll."
            $command = 'dotnet'
            $alToolDll = Join-Path $alcPath 'altool.dll'
            $alToolExists = Test-Path -Path $alToolDll -PathType Leaf
        }
    }
    elseif ($isMacOS) {
        $alcPath = Join-Path $binPath 'darwin'
        if (-not (Test-Path $alcPath)) { $alcPath = $binPath }
        $command = Join-Path $alcPath 'altool'
        if (Test-Path $command) {
            Write-Host "Use $command as altool executable."
            & chmod +x $command
            $alToolExists = $true
        }
        else {
            Write-Host "No altool executable found. Using dotnet to run altool.dll."
            $command = 'dotnet'
            $alToolDll = Join-Path $alcPath 'altool.dll'
            $alToolExists = Test-Path -Path $alToolDll -PathType Leaf
        }
    }
    else {
        $alcPath = Join-Path $binPath 'win32'
        if (-not (Test-Path $alcPath)) { $alcPath = $binPath }
        $command = Join-Path $alcPath 'altool.exe'
        $alToolExists = Test-Path -Path $command -PathType Leaf
        Write-Host "Use $command as altool executable (Exists = $alToolExists)."
    }
    $alcDllPath = $alcPath
    if (!($isLinux -or $isMacOS) -and !$isPsCore) {
        $alcDllPath = $binPath
    }

    $ErrorActionPreference = "STOP"
    $assembliesAdded = $false
    $packageStream = $null
    $package = $null
    try {
        foreach($path in $appFiles) {
            $relativePath = Resolve-Path -Path $path -Relative
            if ($appInfoCache -and $appInfoCache.PSObject.Properties.Name -eq $relativePath) {
                $appInfo = $appInfoCache."$relativePath"
            }
            else {
                Write-Host -nonewline "- $relativePath"
                if ($alToolExists) {
                    $arguments = @('GetPackageManifest', """$path""")
                    if ($alToolDll) {
                        $arguments = @($alToolDll) + $arguments
                    }
                    $manifest = CmdDo -Command $command -arguments $arguments -returnValue -silent | ConvertFrom-Json
                    $appInfo = @{
                        "appId"                 = $manifest.id
                        "publisher"             = $manifest.publisher
                        "name"                  = $manifest.name
                        "version"               = $manifest.version
                        "application"           = "$(if($manifest.PSObject.Properties.Name -eq 'application'){$manifest.application})"
                        "platform"              = "$(if($manifest.PSObject.Properties.Name -eq 'platform'){$manifest.Platform})"
                        "propagateDependencies" = ($manifest.PSObject.Properties.Name -eq 'PropagateDependencies') -and $manifest.PropagateDependencies
                        "dependencies"          = @(if($manifest.PSObject.Properties.Name -eq 'dependencies'){$manifest.dependencies | ForEach-Object { if ($_.PSObject.Properties.Name -eq 'id') { $id = $_.id } else { $id = $_.AppId }; @{ "id" = $id; "name" = $_.name; "publisher" = $_.publisher; "version" = $_.version }}})
                    }
                    Write-Host " (using altool)"
                }
                else {
                    if (!$assembliesAdded) {
                        Add-Type -AssemblyName System.IO.Compression.FileSystem
                        Add-Type -AssemblyName System.Text.Encoding
                        LoadDLL -Path (Join-Path $alcDllPath Newtonsoft.Json.dll)
                        LoadDLL -Path (Join-Path $alcDllPath System.Collections.Immutable.dll)
                        if (Test-Path (Join-Path $alcDllPath System.IO.Packaging.dll)) {
                            LoadDLL -Path (Join-Path $alcDllPath System.IO.Packaging.dll)
                        }
                        LoadDLL -Path (Join-Path $alcDllPath Microsoft.Dynamics.Nav.CodeAnalysis.dll)
                        $assembliesAdded = $true
                    }
                    $packageStream = [System.IO.File]::OpenRead($path)
                    $package = [Microsoft.Dynamics.Nav.CodeAnalysis.Packaging.NavAppPackageReader]::Create($PackageStream, $true)
                    $manifest = $package.ReadNavAppManifest()
                    $appInfo = @{
                        "appId"                 = $manifest.AppId
                        "publisher"             = $manifest.AppPublisher
                        "name"                  = $manifest.AppName
                        "version"               = "$($manifest.AppVersion)"
                        "dependencies"          = @($manifest.Dependencies | ForEach-Object { @{ "id" = $_.AppId; "name" = $_.Name; "publisher" = $_.Publisher; "version" = "$($_.Version)" } })
                        "application"           = "$($manifest.Application)"
                        "platform"              = "$($manifest.Platform)"
                        "propagateDependencies" = $manifest.PropagateDependencies
                    }
                    $packageStream.Close()
                    Write-Host " (using DLLs)"
                }
                if ($cacheAppInfoPath) {
                    $appInfoCache | Add-Member -MemberType NoteProperty -Name $relativePath -Value $appInfo
                    $cacheUpdated = $true
                }
            }
            @{
                "Id"                    = $appInfo.appId
                "AppId"                 = $appInfo.appId
                "Publisher"             = $appInfo.publisher
                "Name"                  = $appInfo.name
                "Version"               = [System.Version]$appInfo.version
                "Dependencies"          = @($appInfo.dependencies)
                "Path"                  = $path
                "Application"           = $appInfo.application
                "Platform"              = $appInfo.platform
                "PropagateDependencies" = $appInfo.propagateDependencies
            }
        }
        if ($cacheUpdated) {
            $appInfoCache | ConvertTo-Json -Depth 99 | Set-Content -Path $cacheAppInfoPath -Encoding UTF8 -Force
        }
    }
    catch [System.Reflection.ReflectionTypeLoadException] {
        if ($_.Exception.LoaderExceptions) {
            $_.Exception.LoaderExceptions | Select-Object -Property Message | Select-Object -Unique | ForEach-Object {
                Write-Host "LoaderException: $($_.Message)"
            }
        }
        throw
    }
    finally {
        if ($package) {
            $package.Dispose()
        }
        if ($packageStream) {
            $packageStream.Dispose()
        }
        Pop-Location
    }
}

function GetLatestAlLanguageExtensionVersionAndUrl {
    Param(
        [switch] $allowPrerelease
    )

    $listing = Invoke-WebRequest -Method POST -UseBasicParsing `
                      -Uri https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery?api-version=3.0-preview.1 `
                      -Body '{"filters":[{"criteria":[{"filterType":8,"value":"Microsoft.VisualStudio.Code"},{"filterType":12,"value":"4096"},{"filterType":7,"value":"ms-dynamics-smb.al"}],"pageNumber":1,"pageSize":50,"sortBy":0,"sortOrder":0}],"assetTypes":[],"flags":0x192}' `
                      -ContentType application/json | ConvertFrom-Json

    $result =  $listing.results | Select-Object -First 1 -ExpandProperty extensions `
                         | Select-Object -ExpandProperty versions `
                         | Where-Object { ($allowPrerelease.IsPresent -or !(($_.properties.Key -eq 'Microsoft.VisualStudio.Code.PreRelease') -and ($_.properties | where-object { $_.Key -eq 'Microsoft.VisualStudio.Code.PreRelease' }).value -eq "true")) } `
                         | Select-Object -First 1

    if ($result) {
        $vsixUrl = $result.files | Where-Object { $_.assetType -eq "Microsoft.VisualStudio.Services.VSIXPackage"} | Select-Object -ExpandProperty source
        if ($vsixUrl) {
            return $result.version, $vsixUrl
        }
    }
    throw "Unable to locate latest AL Language Extension from the VS Code Marketplace"
}

function DetermineVsixFile {
    Param(
        [string] $vsixFile
    )

    if ($vsixFile -eq 'default') {
        return ''
    }
    elseif ($vsixFile -eq 'latest' -or $vsixFile -eq 'preview') {
        $version, $url = GetLatestAlLanguageExtensionVersionAndUrl -allowPrerelease:($vsixFile -eq 'preview')
        return $url
    }
    else {
        return $vsixFile
    }
}

# Cached Path for latest and preview versions of AL Language Extension
$AlLanguageExtenssionPath = @('','')

function DownloadLatestAlLanguageExtension {
    Param(
        [switch] $allowPrerelease
    )

    # Check if we already have the latest version downloaded and located in this session
    if ($script:AlLanguageExtenssionPath[$allowPrerelease.IsPresent]) {
        $path = $script:AlLanguageExtenssionPath[$allowPrerelease.IsPresent]
        if (Test-Path $path -PathType Container) {
            return $path
        }
        else {
            $script:AlLanguageExtenssionPath[$allowPrerelease.IsPresent] = ''
        }
    }

    $mutexName = "DownloadAlLanguageExtension"
    $mutex = New-Object System.Threading.Mutex($false, $mutexName)
    try {
        try {
            if (!$mutex.WaitOne(1000)) {
                Write-Host "Waiting for other process downloading AL Language Extension"
                $mutex.WaitOne() | Out-Null
                Write-Host "Other process completed downloading"
            }
        }
        catch [System.Threading.AbandonedMutexException] {
           Write-Host "Other process terminated abnormally"
        }

        $version, $url = GetLatestAlLanguageExtensionVersionAndUrl -allowPrerelease:$allowPrerelease
        $path = Join-Path $bcContainerHelperConfig.hostHelperFolder "alLanguageExtension/$version"
        if (!(Test-Path $path -PathType Container)) {
            $AlLanguageExtensionsFolder = Join-Path $bcContainerHelperConfig.hostHelperFolder "alLanguageExtension"
            if (!(Test-Path $AlLanguageExtensionsFolder -PathType Container)) {
                New-Item -Path $AlLanguageExtensionsFolder -ItemType Directory | Out-Null
            }
            $description = "AL Language Extension"
            if ($allowPrerelease) {
                $description += " (Prerelease)"
            }
            $zipFile = "$path.zip"
            Download-File -sourceUrl $url -destinationFile $zipFile -Description $description
            Expand-7zipArchive -Path $zipFile -DestinationPath $path
            Remove-Item -Path $zipFile -Force
        }
        $script:AlLanguageExtenssionPath[$allowPrerelease.IsPresent] = $path
        return $path
    }
    finally {
        $mutex.ReleaseMutex()
    }
}

function RunAlTool {
    Param(
        [string[]] $arguments,
        [switch] $usePrereleaseAlTool = ($bccontainerHelperConfig.usePrereleaseAlTool)
    )
    $path = DownloadLatestAlLanguageExtension -allowPrerelease:$usePrereleaseAlTool
    if ($isLinux) {
        $command = Join-Path $path 'extension/bin/linux/altool'
        if (-not (Test-Path $command)) {
            $command = Join-Path $path 'extension/bin/altool'
        }
        if (Test-Path $command) {
            & /usr/bin/env sudo pwsh -command "& chmod +x $command"
        }
        else {
            Write-Host "No altool executable found. Using dotnet to run altool.dll."
            $command = 'dotnet'
            $altoolDll = Join-Path $path 'extension/bin/linux/altool.dll'
            if (-not (Test-Path $altoolDll)) {
                $altoolDll = Join-Path $path 'extension/bin/altool.dll'
            }
            $arguments = @($altoolDll) + $arguments
        }
    }
    elseif ($isMacOS) {
        $command = Join-Path $path 'extension/bin/darwin/altool'
        if (-not (Test-Path $command)) {
            $command = Join-Path $path 'extension/bin/altool'
        }
        if (Test-Path $command) {
            & chmod +x $command
        }
        else {
            Write-Host "No altool executable found. Using dotnet to run altool.dll."
            $command = 'dotnet'
            $altoolDll = Join-Path $path 'extension/bin/darwin/altool.dll'
            if (-not (Test-Path $altoolDll)) {
                $altoolDll = Join-Path $path 'extension/bin/altool.dll'
            }
            $arguments = @($altoolDll) + $arguments
        }
    }
    else {
        $command = Join-Path $path 'extension/bin/win32/altool.exe'
        if (-not (Test-Path $command)) {
            $command = Join-Path $path 'extension/bin/altool.exe'
        }
    }
    CmdDo -Command $command -arguments $arguments -returnValue -silent
}

function GetApplicationDependency( [string] $appFile, [string] $minVersion = "0.0" ) {
    try {
        $appJson = Get-AppJsonFromAppFile -appFile $appFile
    }
    catch {
        Write-Host -ForegroundColor Red "Unable to read app $([System.IO.Path]::GetFileName($appFile)), ignoring application dependency check"
        return $minVersion
    }
    $version = $minVersion
    if ($appJson.PSObject.Properties.Name -eq "Application") {
        $version = $appJson.application
    }
    elseif ($appJson.PSObject.Properties.Name -eq "dependencies") {
        $baseAppDependency = $appJson.dependencies | Where-Object { $_.Name -eq "Base Application" -and $_.Publisher -eq "Microsoft" }
        if ($baseAppDependency) {
            $version = $baseAppDependency.Version
        }
    }
    if ([System.Version]$version -lt [System.Version]$minVersion) {
        $version = $minVersion
    }
    return $version
}

function ReplaceCDN {
    Param(
        [string] $sourceUrl,
        [switch] $useBlobUrl
    )

    $bcCDNs = @(
        @{ "oldCDN" = "bcartifacts.azureedge.net";         "newCDN" = "bcartifacts-exdbf9fwegejdqak.b02.azurefd.net";         "blobUrl" = "bcartifacts.blob.core.windows.net" },
        @{ "oldCDN" = "bcinsider.azureedge.net";           "newCDN" = "bcinsider-fvh2ekdjecfjd6gk.b02.azurefd.net";           "blobUrl" = "bcinsider.blob.core.windows.net" },
        @{ "oldCDN" = "bcpublicpreview.azureedge.net";     "newCDN" = "bcpublicpreview-f2ajahg0e2cudpgh.b02.azurefd.net";     "blobUrl" = "bcpublicpreview.blob.core.windows.net" },
        @{ "oldCDN" = "businesscentralapps.azureedge.net"; "newCDN" = "businesscentralapps-hkdrdkaeangzfydv.b02.azurefd.net"; "blobUrl" = "businesscentralapps.blob.core.windows.net" },
        @{ "oldCDN" = "bcprivate.azureedge.net";           "newCDN" = "bcprivate-fmdwbsb3ekbkc0bt.b02.azurefd.net";           "blobUrl" = "bcprivate.blob.core.windows.net" }
    )

    foreach($cdn in $bcCDNs) {
        $found = $false
        $cdn.blobUrl, $cdn.newCDN, $cdn.oldCDN | ForEach-Object {
            if ($sourceUrl.ToLowerInvariant().StartsWith("https://$_/")) {
                $sourceUrl = "https://$(if($useBlobUrl){$cdn.blobUrl}else{$cdn.newCDN})/$($sourceUrl.Substring($_.Length+9))"
                $found = $true
            }
            if ($sourceUrl -eq $_) {
                $sourceUrl = "$(if($useBlobUrl){$cdn.blobUrl}else{$cdn.newCDN})"
                $found = $true
            }
        }
        if ($found) {
            break
        }
    }
    $sourceUrl
}

function Write-GroupStart([string] $Message) {
    switch ($true) {
        $bcContainerHelperConfig.IsGitHubActions { Write-Host "::group::$Message"; break }
        $bcContainerHelperConfig.IsAzureDevOps { Write-Host "##[group]$Message"; break }
        Default { Write-Host $Message}
    }
}

function Write-GroupEnd {
     switch ($true) {
        $bcContainerHelperConfig.IsGitHubActions { Write-Host "::endgroup::"; break }
        $bcContainerHelperConfig.IsAzureDevOps { Write-Host "##[endgroup]"; break }
    }
}

function Write-DevOpsWarning {
    Param(
        [string] $Message
    )
    switch ($true) {
        $bcContainerHelperConfig.IsGitHubActions { Write-Host "::warning::$Message"; break }
        $bcContainerHelperConfig.IsAzureDevOps { Write-Host "##vso[task.logissue type=warning]$Message"; break }
        Default { Write-Host -ForegroundColor Yellow $Message }
    }
}

function Write-DevOpsError {
    Param(
        [string] $Message
    )
    switch ($true) {
        $bcContainerHelperConfig.IsGitHubActions { Write-Host "::error::$Message"; break }
        $bcContainerHelperConfig.IsAzureDevOps { Write-Host "##vso[task.logissue type=error]$Message"; break }
        Default { Write-Host -ForegroundColor Red $Message }
    }
}

function CopySymbolsFromContainer {
    Param(
        [string] $containerName,
        [string] $containerSymbolsFolder
    )

    Invoke-ScriptInBcContainer -containerName $containerName -scriptblock { Param($appSymbolsFolder)
        if (Test-Path "C:\Extensions\*.app") {
            $paths = @(
                "C:\Program Files\Microsoft Dynamics NAV\*\AL Development Environment\System.app"
                "C:\Extensions\*.app"
            )
        }
        else {
            $paths = @(
                "C:\Program Files\Microsoft Dynamics NAV\*\AL Development Environment\System.app"
                "C:\Applications.*\Microsoft_Application_*.app,C:\Applications\Application\Source\Microsoft_Application.app"
                "C:\Applications.*\Microsoft_Base Application_*.app,C:\Applications\BaseApp\Source\Microsoft_Base Application.app"
                "C:\Applications.*\Microsoft_System Application_*.app,C:\Applications\System Application\source\Microsoft_System Application.app"
                "C:\Applications.*\Microsoft_Business Foundation_*.app,C:\Applications\BusinessFoundation\source\Microsoft_Business Foundation.app"
                "C:\Applications.*\Microsoft_AI Test Toolkit_*.app,C:\Applications\BusinessFoundation\source\Microsoft_AI Test Toolkit.app"
            )
        }
        # Include Apps only available offline
        "Microsoft_System Application Test Library", "Microsoft_Business Foundation Test Libraries", "Microsoft_Tests-TestLibraries" | ForEach-Object {
            $paths += @(
                "C:\Applications.*\$($_)_*.app,C:\Applications\BusinessFoundation\source\$($_).app"
            )
        }
        $paths | ForEach-Object {
            $appFiles = $_.Split(',')
            $appFile = ""
            if (Test-Path -Path $appFiles[0]) {
                $appFile = $appFiles[0]
            }
            elseif (Test-Path -path $appFiles[1]) {
                $appFile = $appFiles[1]
            }
            if ($appFile) {
                Get-Item -Path $appFile | ForEach-Object {
                    Write-Host "Copying $([System.IO.Path]::GetFileName($_.FullName)) from Container"
                    Copy-Item -Path $_.FullName -Destination $appSymbolsFolder -Force
                }
            }
        }
    } -argumentList $containerSymbolsFolder
}

function GetIsolationMode {
    Param(
        [Parameter(Mandatory=$true)]
        [System.Version] $hostOsVersion,
        [Parameter(Mandatory=$true)]
        [System.Version] $containerOsVersion,
        [Parameter(Mandatory=$true)]
        [bool] $useSSL,
        [string] $isolation = ''
    )
    if ($hostOsVersion -eq $containerOsVersion) {
        $recommendation = "Host and container OS match, recommended isolation mode is process."
        $recommendedIsolation = "process"
    }
    elseif ($hostOsVersion.Build -ge 26100) {
        $recommendation = "Host OS is 26100 (24H2) or above, recommended isolation mode is hyperv."
        $recommendedIsolation = "hyperv"
    }
    elseif ($hostOsVersion.Build -ge 22621 -and $useSSL) {
        $recommendation = "Host OS is 22621 (22H2) or above and you are using SSL, recommended isolation mode is hyperv."
        $recommendedIsolation = "hyperv"
    }
    elseif ($hostOsVersion.Build -ge 20348 -and $containerOsVersion.Build -ge 20348) {
        $recommendation = "Container and host OS are 20348 or above, not using SSL, recommended isolation mode is process."
        $recommendedIsolation = "process"
    }
    elseif (("$hostOsVersion".StartsWith('10.0.19043.') -or "$hostOsVersion".StartsWith('10.0.19044.') -or "$hostOsVersion".StartsWith('10.0.19045.')) -and "$containerOsVersion".StartsWith("10.0.19041.")) {
        $recommendation = "Host OS is Windows 10 21H1 or newer and Container OS is 2004, recommended isolation mode is process."
        $recommendedIsolation = "process"
    }
    else {
        $recommendation = "Host OS and Base Image Container OS doesn't match, recommended isolation mode is hyperv."
        $recommendedIsolation = "hyperv"
    }

    $hypervState = GetHypervState
    if ($recommendedIsolation -eq "hyperv") {
        if ($hypervState -eq "Disabled") {
            $recommendation += ' HyperV is not installed, recommending process isolation instead.'
            $recommendedIsolation = "process"
        }
        elseif ($hypervState -eq 'Unknown') {
            $recommendation += ' HyperV state is unknown, if you encounter problems you might need to install HyperV.'
        }
    }

    if ($isolation -eq '') {
        $isolation = $recommendedIsolation
        Write-Host $recommendation
    }
    elseif ($isolation -ne $recommendedIsolation) {
        Write-Host -ForegroundColor Yellow "WARNING: You have specified isolation mode $isolation. $recommendation If you encounter issues you could try to specify -isolation $recommendedIsolation (or remove the -isolation parameter)."
    }

    return $isolation
}

function GetContainerOs {
    Param(
        [Parameter(Mandatory=$true)]
        [Version] $containerOsVersion
    )
    if ("$containerOsVersion".StartsWith('10.0.14393.')) {
        $containerOs = "ltsc2016"
    }
    elseif ("$containerOsVersion".StartsWith('10.0.15063.')) {
        $containerOs = "1703"
    }
    elseif ("$containerOsVersion".StartsWith('10.0.16299.')) {
        $containerOs = "1709"
    }
    elseif ("$containerOsVersion".StartsWith('10.0.17134.')) {
        $containerOs = "1803"
    }
    elseif ("$containerOsVersion".StartsWith('10.0.17763.')) {
        $containerOs = "ltsc2019"
    }
    elseif ("$containerOsVersion".StartsWith('10.0.18362.')) {
        $containerOs = "1903"
    }
    elseif ("$containerOsVersion".StartsWith('10.0.18363.')) {
        $containerOs = "1909"
    }
    elseif ("$containerOsVersion".StartsWith('10.0.19041.')) {
        $containerOs = "2004"
    }
    elseif ("$containerOsVersion".StartsWith('10.0.19042.')) {
        $containerOs = "20H2"
    }
    elseif ("$containerOsVersion".StartsWith('10.0.19043.')) {
        $containerOs = "21H1"
    }
    elseif ("$containerOsVersion".StartsWith('10.0.19044.')) {
        $containerOs = "21H2"
    }
    elseif ("$containerOsVersion".StartsWith('10.0.19045.')) {
        $containerOs = "22H2"
    }
    elseif ("$containerOsVersion".StartsWith('10.0.20348.')) {
        $containerOs = "ltsc2022"
    }
    elseif ("$containerOsVersion".StartsWith('10.0.26100.')) {
        $containerOs = "ltsc2025"
    }
    else {
        $containerOs = "unknown"
    }
    return $containerOs
}

function GetHostOs {
    Param(
        [Parameter(Mandatory=$true)]
        [Version] $hostOsVersion,
        [Parameter(Mandatory=$true)]
        [bool] $isServerHost
    )

    $hostOs = "Unknown/Insider build"
    if ($os.BuildNumber -eq 26100) {
        if ($isServerHost) {
            $hostOs = "ltsc2025"
        }
        else {
            $hostOs = "24H2"
        }
    }
    elseif ($os.BuildNumber -eq 22631) {
        $hostOs = "23H2"
    }
    elseif ($os.BuildNumber -eq 22621) {
        $hostOs = "22H2"
    }
    elseif ($os.BuildNumber -eq 22000) {
        $hostOs = "21H2"
    }
    elseif ($os.BuildNumber -eq 20348) {
        $hostOs = "ltsc2022"
    }
    elseif ($os.BuildNumber -eq 19045) {
        $hostOs = "22H2"
    }
    elseif ($os.BuildNumber -eq 19044) {
        $hostOs = "21H2"
    }
    elseif ($os.BuildNumber -eq 19043) {
        $hostOs = "21H1"
    }
    elseif ($os.BuildNumber -eq 19042) {
        $hostOs = "20H2"
    }
    elseif ($os.BuildNumber -eq 19041) {
        $hostOs = "2004"
    }
    elseif ($os.BuildNumber -eq 18363) {
        $hostOs = "1909"
    }
    elseif ($os.BuildNumber -eq 18362) {
        $hostOs = "1903"
    }
    elseif ($os.BuildNumber -eq 17763) {
        if ($isServerHost) {
            $hostOs = "ltsc2019"
        }
        else {
            $hostOs = "1809"
        }
    }
    elseif ($os.BuildNumber -eq 17134) {
        $hostOs = "1803"
    }
    elseif ($os.BuildNumber -eq 16299) {
        $hostOs = "1709"
    }
    elseif ($os.BuildNumber -eq 15063) {
        $hostOs = "1703"
    }
    elseif ($os.BuildNumber -eq 14393) {
        if ($isServerHost) {
            $hostOs = "ltsc2016"
        }
        else {
            $hostOs = "1607"
        }
    }
    return $hostOs
}

function Write-PSCallStack {
    Param(
        [string] $message
    )
    Write-Host "PS CallStack $message :"
    Get-PSCallStack | ForEach-Object { Write-Host "- $($_.FunctionName) ($([System.IO.Path]::GetFileName($_.ScriptName)) Line $($_.ScriptLineNumber))" }
}

function GetTempRunnerPath {
    if ($ENV:RUNNER_TEMP) {
        # GitHub Actions temp directory
        return $ENV:RUNNER_TEMP
    }
    elseif ($ENV:AGENT_TEMPDIRECTORY) {
        # Azure DevOps temp directory
        return $ENV:AGENT_TEMPDIRECTORY
    }
    else {
        # Machine temp directory
        return ([System.IO.Path]::GetTempPath())
    }
}

function QueryArtifactsFromIndex {
    Param(
        [string] $storageAccount,
        [string] $Type,
        [string] $versionPrefix = '',
        [string] $country = '',
        [DateTime] $after,
        [DateTime] $before,
        [bool] $doNotCheckPlatform = $false
    )

    $indexesContainerUrl = "https://$storageAccount/$($Type.ToLowerInvariant())/indexes"
    $artifacts = @()
    $sortIt = $false
    if ($country -eq '') {
        # countries unsettled, get all countries
        $countriesUrl = "$indexesContainerUrl/countries.json"
        $countriesFile = Join-Path (GetTempRunnerPath) "bcContainerHelper.countries.json"
        Download-File -sourceUrl $countriesUrl -destinationFile $countriesFile -Description "Countries index"
        $countries = [System.IO.File]::ReadAllText($countriesFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        $countries = $countries | Where-Object { $_ -ne "platform" }
        $sortIt = $true
    }
    else {
        if (($type -eq "sandbox") -and ($bcContainerHelperConfig.mapCountryCode.PSObject.Properties.Name -eq $country)) {
            $country = $bcContainerHelperConfig.mapCountryCode."$country"
        }
        $countries = @($country)
    }
    if (-not $doNotCheckPlatform) {
        # Checking whether platform exists in the index for the country
        $platformUrl = "$indexesContainerUrl/platform.json"
        $platformFile = Join-Path (GetTempRunnerPath) "bcContainerHelper.platform.json"
        Write-Host "Platformurl: $platformUrl"
        Download-File -sourceUrl $platformUrl -destinationFile $platformFile -Description "Platform index"
        $platformArtifacts = @([System.IO.File]::ReadAllText($platformFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json | ForEach-Object { $_.Version })
    }
    $countries | ForEach-Object {
        $country = $_
        $countryUrl = "$indexesContainerUrl/$country.json"
        $countryFile = Join-Path (GetTempRunnerPath) "bcContainerHelper.$($country).json"
        Download-File -sourceUrl $countryUrl -destinationFile $countryFile -Description "$country index"
        $countryArtifacts = [System.IO.File]::ReadAllText($countryFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        $countryArtifacts = $countryArtifacts | Where-Object { $_.Version -like "$($versionPrefix)*" }
        if ($doNotCheckPlatform -and (!$after) -and (!$before)) {
            $artifacts += $countryArtifacts | ForEach-Object { "$($_.Version)/$country" }
        }
        else {
            $artifacts += $countryArtifacts | ForEach-Object {
                $platformOK = $doNotCheckPlatform
                if (-not $doNotCheckPlatform) {
                    $platformOK = $platformArtifacts.Contains($_.Version)
                }
                if ($platformOK) {
                    if ($after -or $before) {
                        if ($_."CreationTime" -is [datetime]) {
                            $blobModifiedDate = $_."CreationTime"
                        }
                        else {
                            $blobModifiedDate = [DateTime]::Parse($_."CreationTime")
                        }
                        if ($after) {
                            if ($before) {
                                if ($blobModifiedDate -lt $before -and $blobModifiedDate -gt $after) {
                                    "$($_.Version)/$country"
                                }
                            }
                            elseif ($blobModifiedDate -gt $after) {
                                "$($_.Version)/$country"
                            }
                        }
                        else {
                            if ($blobModifiedDate -lt $before) {
                                "$($_.Version)/$country"
                            }
                        }
                    }
                    else {
                        "$($_.Version)/$country"
                    }
                }
            }
        }
    }
    if ($sortIt) {
        return $Artifacts | Sort-Object { [Version]($_.Split('/')[0]) }
    }
    else {
        return $Artifacts
    }
}

# SIG # Begin signature block
# MIInSQYJKoZIhvcNAQcCoIInOjCCJzYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCnr1sfgYCuntAu
# k6hpiaIPHl98TbfcGjidpfCFOMFFE6CCDLowggX1MIID3aADAgECAhMzAAACHU0Z
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
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIDzqKpEX
# n7qfh0LPYRqDpNVg2Vl5XuU019EI/GzEN3bFMEIGCisGAQQBgjcCAQwxNDAyoBSA
# EgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20w
# DQYJKoZIhvcNAQEBBQAEggEAoH9xVcGEKZNb3wEEF5rmc1xpMu6flSuXlO9vkM4I
# t0uy8LBfG+o+MQ/9hfmx1sy0ZYB1YztXYEzo8isviNLMiSd97Fj8bhvz0VcMvsiu
# wIReAN1EFgCh8+uIGDXNJsLm1tj7vAXM3P5JevwHOLOFlhpQxTGCARPboiTKC4DX
# GT6ojK9juWJuFA7kZZWbMMo2f68fSVBRR0EQk6jeDdxC6rBInjmwXNokGnX7xtJA
# LsJNMjnV9xsXJrnTaelUTOwfOUdc4QVQYNQsPPEJrvMXb2T7Xch6+M8wcTSIbuOi
# UBZ1n3PaTQ6gaXffsYfYS2zUe/Ydzu+mOcC7BRYtRGgYlaGCF5cwgheTBgorBgEE
# AYI3AwMBMYIXgzCCF38GCSqGSIb3DQEHAqCCF3AwghdsAgEDMQ8wDQYJYIZIAWUD
# BAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGEWQoD
# ATAxMA0GCWCGSAFlAwQCAQUABCAAZHGBE0Z3nbT/IWBaGe/5o1KWqEyk74PADKNu
# srQRUAIGaoV0MGIPGBMyMDI2MDgyNzA2MjkzNS4wODdaMASAAgH0oIHRpIHOMIHL
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
# CyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCApqSS1SkxcqzxP6C/Mi/X/RC7g
# 9xqeLfrisQg/xbdC0jCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EION7vyOl
# PA1VqlEp0QIVGlNd8S5YWBnKj97LuTWHSO2vMIGYMIGApH4wfDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgUENBIDIwMTACEzMAAAIgJOHm4Be5tI4AAQAAAiAwIgQgjiu1gfdt
# K/nOE0cUc+Y8+y8Y+ptu1I0ru0zk1hD/Vy8wDQYJKoZIhvcNAQELBQAEggIAvfWX
# FzqczCg/6zIcPlZ59JoGyRkEEmexz98x7W0R9gnfobgW0L/O5rYr0PLqIVMwD1iA
# NDiaBjclLOQnU2ULpUnEbodgerMWBOZ83GHhNSxnNM2GUFCUdwQPKWY8j3apG8Gh
# 2qLNRlF30RPv2E+RdniphhLaQp+reIJY4EgCtiXulNeo5C+MeVlivggHexdFpxGR
# PjrKvERAXzRfx8sNdGmNLwhdwsOvKCfWHxr+EwskonJ1lZGNAIzsIDN2+m4eDgKi
# dJR32hdVE8OwF65byWBB4ECeq2SPL7bA6RybyzdpCwo7OVUjm+kog3GQJm2OJ6xv
# VzsN9wONhRnJzDUKJ6xmjUn6rG84lIluuKakwvdMAmVvTNC6JVun2bOv+Em4U/W0
# gHlrkH+k8hoJxyNE6saUjOGvO7TYi+YJ8U+1x0kYHjP0jFkvlaF5e9QisLZImb6Y
# uWkvHP6u7X2uhbPNiiAI5SXR+cy+QSX+pHI9bbtSEtCVYkTRPgCb3HbTvT4HNpWn
# mD5JQyu4Hx2dCl7GssRRTjoZ9pwaalrluw+fXh9eSbKyqzryca4shJHVqsdHf7Md
# QTk9P2dW96iNgsU1oeu8GQW4nTyYmjtzFj6zmFk3sNUhRfDduIDH6KlUX0rJRekI
# DbDlT51sRngGIqeYZWvLdx15DvxJwUzYf6HqQeg=
# SIG # End signature block
