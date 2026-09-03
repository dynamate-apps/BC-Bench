<#
 .Synopsis
  Use NAV/BC Container to Compile App
 .Description
 .Parameter containerName
  Name of the container in which you want to use to compile the app
 .Parameter tenant
  tenant to use if container is multitenant
 .Parameter credential
  Credentials of the SUPER user if using NavUserPassword authentication
 .Parameter appProjectFolder
  Location of the project. This folder (or any of its parents) needs to be shared with the container.
 .Parameter appOutputFolder
  Folder in which the output will be placed. This folder (or any of its parents) needs to be shared with the container. Default is $appProjectFolder\output.
 .Parameter appSymbolsFolder
  Folder in which the symbols of dependent apps will be placed. This folder (or any of its parents) needs to be shared with the container. Default is $appProjectFolder\symbols.
 .Parameter appName
  File name of the app. Default is to compose the file name from publisher_appname_version from app.json.
 .Parameter basePath
  Base Path of the files in the ALC output, to convert file paths to relative paths. This folder (or any of its parents) needs to be shared with the container.
 .Parameter UpdateSymbols
  Add this switch to indicate that you want to force the download of symbols for all dependent apps.
 .Parameter UpdateDependencies
  Update the dependency version numbers to the actual version number used during compilation
 .Parameter CopySymbolsFromContainer
  Add this switch to copy system and base application symbols from container to speed up symbol download.
 .Parameter CopyAppToSymbolsFolder
  Add this switch to copy the compiled app to the appSymbolsFolder.
 .Parameter GenerateReportLayout
  Add this switch to invoke report layout generation during compile. Default is default alc.exe behavior, which is to generate report layout
 .Parameter AzureDevOps
  Add this switch to convert the output to Azure DevOps Build Pipeline compatible output
 .Parameter gitHubActions
  Include this switch to convert the output to GitHub Actions compatible output
 .Parameter EnableCodeCop
  Add this switch to Enable CodeCop to run
 .Parameter EnableAppSourceCop
  Add this switch to Enable AppSourceCop to run
 .Parameter EnablePerTenantExtensionCop
  Add this switch to Enable PerTenantExtensionCop to run
 .Parameter EnableUICop
  Add this switch to Enable UICop to run
 .Parameter RulesetFile
  Specify a ruleset file for the compiler
 .Parameter enableExternalRulesets
  Add this switch to Enable External Rulesets
 .Parameter CustomCodeCops
  Add custom AL code Cops when compiling apps.
 .Parameter Failon
  Specify if you want Compilation to fail on Error or Warning
 .Parameter nowarn
  Specify a nowarn parameter for the compiler
 .Parameter generateErrorLog
  Switch parameter on whether to generate an alerts log file. Default is false.
  The file will be placed in the same folder as the app file, and will have the same name as the app file, but with the extension .errorLog.json.
 .Parameter preProcessorSymbols
  PreProcessorSymbols to set when compiling the app.
 .Parameter generatecrossreferences
  Include this flag to generate cross references when compiling
 .Parameter reportSuppressedDiagnostics
  Set reportSuppressedDiagnostics flag on ALC when compiling to ignore pragma warning disables
 .Parameter bcAuthContext
  Authorization Context created by New-BcAuthContext. By specifying BcAuthContext and environment, the compile function will use the online Business Central Environment as target for the compilation
 .Parameter environment
  Environment to use for the compilation.
 .Parameter assemblyProbingPaths
  Specify a comma separated list of paths to include in the search for dotnet assemblies for the compiler
 .Parameter SourceRepositoryUrl
  Repository holding the source code for the app. Will be stamped into the app manifest.
 .Parameter SourceCommit
  The commit identifier for the source code for the app. Will be stamped into the app manifest.
 .Parameter BuildBy
  Information about which product built the app. Will be stamped into the app manifest.
 .Parameter BuildUrl
  The URL for the build job, which built the app. Will be stamped into the app manifest.
 .Parameter OutputTo
  Compiler output is sent to this scriptblock for output. Default value for the scriptblock is: { Param($line) Write-Host $line }
 .Example
  Compile-AppInBcContainer -containerName test -credential $credential -appProjectFolder "C:\Users\freddyk\Documents\AL\Test"
 .Example
  Compile-AppInBcContainer -containerName test -appProjectFolder "C:\Users\freddyk\Documents\AL\Test"
 .Example
  Compile-AppInBcContainer -containerName test -appProjectFolder "C:\Users\freddyk\Documents\AL\Test" -outputTo { Param($line) if ($line -notlike "*sourcepath=C:\Users\freddyk\Documents\AL\Test\Org\*") { Write-Host $line } }
#>
function Compile-AppInBcContainer {
    Param (
        [string] $containerName = $bcContainerHelperConfig.defaultContainerName,
        [Parameter(Mandatory=$false)]
        [string] $tenant = "default",
        [Parameter(Mandatory=$false)]
        [PSCredential] $credential = $null,
        [Parameter(Mandatory=$true)]
        [string] $appProjectFolder,
        [Parameter(Mandatory=$false)]
        [string] $appOutputFolder = (Join-Path $appProjectFolder "output"),
        [Parameter(Mandatory=$false)]
        [string] $appSymbolsFolder = (Join-Path $appProjectFolder ".alpackages"),
        [Parameter(Mandatory=$false)]
        [string] $appName = "",
        [string] $basePath = "",
        [switch] $UpdateSymbols,
        [switch] $UpdateDependencies,
        [switch] $CopySymbolsFromContainer,
        [switch] $CopyAppToSymbolsFolder,
        [ValidateSet('Yes','No','NotSpecified')]
        [string] $GenerateReportLayout = 'NotSpecified',
        [switch] $AzureDevOps = $bcContainerHelperConfig.IsAzureDevOps,
        [switch] $gitHubActions = $bcContainerHelperConfig.IsGitHubActions,
        [switch] $EnableCodeCop,
        [switch] $EnableAppSourceCop,
        [switch] $EnablePerTenantExtensionCop,
        [switch] $EnableUICop,
        [ValidateSet('none','error','warning','newWarning')]
        [string] $FailOn = 'none',
        [Parameter(Mandatory=$false)]
        [string] $rulesetFile,
        [switch] $enableExternalRulesets,
        [string[]] $CustomCodeCops = @(),
        [Parameter(Mandatory=$false)]
        [string] $nowarn,
        [switch] $generateErrorLog,
        [string[]] $preProcessorSymbols = @(),
        [switch] $GenerateCrossReferences,
        [switch] $ReportSuppressedDiagnostics,
        [Parameter(Mandatory=$false)]
        [string] $assemblyProbingPaths,
        [Parameter(Mandatory=$false)]
        [ValidateSet('ExcludeGeneratedTranslations','GenerateCaptions','GenerateLockedTranslations','NoImplicitWith','TranslationFile','LcgTranslationFile')]
        [string[]] $features = @(),
        [Hashtable] $bcAuthContext,
        [string] $environment,
        [string[]] $treatWarningsAsErrors = $bcContainerHelperConfig.TreatWarningsAsErrors,
        [string] $sourceRepositoryUrl = '',
        [string] $sourceCommit = '',
        [string] $buildBy = "BcContainerHelper,$BcContainerHelperVersion",
        [string] $buildUrl = '',
        [scriptblock] $outputTo = { Param($line) Write-Host $line }
    )

$telemetryScope = InitTelemetryScope -name $MyInvocation.InvocationName -parameterValues $PSBoundParameters -includeParameters @()
try {

    $startTime = [DateTime]::Now

    $platform = Get-BcContainerPlatformversion -containerOrImageName $containerName
    if ("$platform" -eq "") {
        $platform = (Get-BcContainerNavVersion -containerOrImageName $containerName).Split('-')[0]
    }
    [System.Version]$platformversion = $platform

    $containerProjectFolder = Get-BcContainerPath -containerName $containerName -path $appProjectFolder
    if ("$containerProjectFolder" -eq "") {
        throw "The appProjectFolder ($appProjectFolder) is not shared with the container."
    }

    $containerFolder = Get-BcContainerPath -containerName $containerName -path (Join-Path $bcContainerHelperConfig.hostHelperFolder "Extensions\$containerName")
    # Read the required .NET version from the manifest (stored during New-BcContainer)
    $requiredDotNetMajor = 0
    $manifestFile = Join-Path $bcContainerHelperConfig.hostHelperFolder "Extensions\$containerName\manifest.json"
    if (Test-Path $manifestFile) {
        try {
            $manifest = Get-Content $manifestFile -Encoding UTF8 | ConvertFrom-Json
            if ($manifest.dotNetVersion) {
                $requiredDotNetMajor = ([System.Version]$manifest.dotNetVersion).Major
            }
        }
        catch {}
    }
    if (!$PSBoundParameters.ContainsKey("assemblyProbingPaths")) {
        if ($platformversion.Major -ge 13) {
            $assemblyProbingPaths = Invoke-ScriptInBcContainer -containerName $containerName -ScriptBlock { Param($containerFolder, $appProjectFolder, $platformVersion, $requiredDotNetMajor)
                $assemblyProbingPaths = ""
                $netpackagesPath = Join-Path $appProjectFolder ".netpackages"
                if (Test-Path $netpackagesPath) {
                    $assemblyProbingPaths += """$netpackagesPath"","
                }

                $roleTailoredClientFolder = "C:\Program Files (x86)\Microsoft Dynamics NAV\*\RoleTailored Client"
                if (Test-Path $roleTailoredClientFolder) {
                    $assemblyProbingPaths += """$((Get-Item $roleTailoredClientFolder).FullName)"","
                }

                $serviceTierFolder = (Get-Item "C:\Program Files\Microsoft Dynamics NAV\*\Service").FullName
                if ($platformversion.Major -ge 22) {
                    $dotnetAssembliesFolder = Join-Path $containerFolder ".netPackages\Service"
                    if (!(Test-Path $dotnetAssembliesFolder)) {
                        New-Item $dotnetAssembliesFolder -ItemType Directory -Force | Out-Null

                        Write-Host "Copying DLLs from $serviceTierFolder to assemblyProbingPath"
                        Copy-Item -Path $serviceTierFolder -filter '*.dll' -Destination $dotnetAssembliesFolder -Recurse -Force -ErrorAction SilentlyContinue

                        $mockAssembliesPath = "C:\Test Assemblies\Mock Assemblies"
                        Copy-Item -Path $mockAssembliesPath -filter '*.dll' -Destination $dotnetAssembliesFolder -Recurse -Force -ErrorAction SilentlyContinue

                        Write-Host "Removing dotnet Framework Assemblies"
                        $dotnetServiceFolder = Join-Path $dotnetAssembliesFolder "Service"
                        Remove-Item -Path (Join-Path $dotnetserviceFolder 'Management') -Recurse -Force -ErrorAction SilentlyContinue
                        Remove-Item -Path (Join-Path $dotnetserviceFolder 'SideServices') -Recurse -Force -ErrorAction SilentlyContinue
                        Remove-Item -Path (Join-Path $dotnetserviceFolder 'WindowsServiceInstaller') -Recurse -Force -ErrorAction SilentlyContinue
                    }

                    $assemblyProbingPaths += """$dotnetAssembliesFolder"""
                    # Use specific .NET version paths if the required version is known from the artifact manifest
                    $dotNetSharedPath = ""
                    if ($requiredDotNetMajor -gt 0) {
                        $dotNetCorePath = 'C:\Program Files\dotnet\shared\Microsoft.NETCore.App'
                        if (Test-Path $dotNetCorePath) {
                            $matchingVersion = Get-ChildItem $dotNetCorePath | ForEach-Object {
                                try { [System.Version]$_.Name } catch {}
                            } | Where-Object { $_.Major -eq $requiredDotNetMajor } | Sort-Object -Descending | Select-Object -First 1
                            if ($matchingVersion) {
                                Write-Host "Using .NET $matchingVersion for assembly probing (artifact requires .NET $requiredDotNetMajor)"
                                $dotNetSharedPath = """C:\Program Files\dotnet\shared\Microsoft.NETCore.App\$matchingVersion"",""C:\Program Files\dotnet\shared\Microsoft.AspNetCore.App\$matchingVersion"""
                            }
                        }
                    }
                    if (-not $dotNetSharedPath) {
                        $dotNetSharedPath = """C:\Program Files\dotnet\shared"""
                    }
                    $assemblyProbingPaths = "$dotNetSharedPath,$assemblyProbingPaths"
                }
                else {
                    $assemblyProbingPaths += """$serviceTierFolder"",""C:\Program Files (x86)\Open XML SDK\V2.5\lib"""
                    $assemblyProbingPaths += ',"c:\Windows\Microsoft.NET\Assembly"'
                    $mockAssembliesPath = "C:\Test Assemblies\Mock Assemblies"
                    if (Test-Path $mockAssembliesPath -PathType Container) {
                        $assemblyProbingPaths += ",""$mockAssembliesPath"""
                    }
                }
                $assemblyProbingPaths
            } -ArgumentList $containerFolder, $containerProjectFolder, $platformversion, $requiredDotNetMajor
        }
    }

    $containerOutputFolder = Get-BcContainerPath -containerName $containerName -path $appOutputFolder
    if ("$containerOutputFolder" -eq "") {
        throw "The appOutputFolder ($appOutputFolder) is not shared with the container."
    }

    $containerSymbolsFolder = Get-BcContainerPath -containerName $containerName -path $appSymbolsFolder
    if ("$containerSymbolsFolder" -eq "") {
        throw "The appSymbolsFolder ($appSymbolsFolder) is not shared with the container."
    }

    $containerRulesetFile = ""
    if ($rulesetFile) {
        $containerRulesetFile = Get-BcContainerPath -containerName $containerName -path $rulesetFile
        if ("$containerRulesetFile" -eq "") {
            throw "The rulesetFile ($rulesetFile) is not shared with the container."
        }
    }

    $CustomCodeCopFiles = @()
    if ($CustomCodeCops.Count -gt 0) {
        $CustomCodeCops | ForEach-Object {
            if ($_ -like 'https://*') {
                $customCopPath = $_
            }
            else {
                $customCopPath = Get-BcContainerPath -containerName $containerName -path $_
                if ("$customCopPath" -eq "") {
                    throw "The custom code cop ($_) is not shared with the container."
                }
            }
            $CustomCodeCopFiles += $customCopPath
        }
    }

    if (!(Test-Path $appOutputFolder -PathType Container)) {
        New-Item $appOutputFolder -ItemType Directory | Out-Null
    }

    $appJsonFile = Join-Path $appProjectFolder 'app.json'
    $appJsonObject = [System.IO.File]::ReadAllLines($appJsonFile) | ConvertFrom-Json
    if ("$appName" -eq "") {
        $appName = "$($appJsonObject.Publisher)_$($appJsonObject.Name)_$($appJsonObject.Version).app".Split([System.IO.Path]::GetInvalidFileNameChars()) -join ''
    }
    if ([bool]($appJsonObject.PSobject.Properties.name -eq "id")) {
        AddTelemetryProperty -telemetryScope $telemetryScope -key "id" -value $appJsonObject.id
    }
    elseif ([bool]($appJsonObject.PSobject.Properties.name -eq "appid")) {
        AddTelemetryProperty -telemetryScope $telemetryScope -key "id" -value $appJsonObject.appid
    }
    AddTelemetryProperty -telemetryScope $telemetryScope -key "publisher" -value $appJsonObject.Publisher
    AddTelemetryProperty -telemetryScope $telemetryScope -key "name" -value $appJsonObject.Name
    AddTelemetryProperty -telemetryScope $telemetryScope -key "version" -value $appJsonObject.Version
    AddTelemetryProperty -telemetryScope $telemetryScope -key "appname" -value $appName

    Write-Host "Using Symbols Folder: $appSymbolsFolder"
    if (!(Test-Path -Path $appSymbolsFolder -PathType Container)) {
        New-Item -Path $appSymbolsFolder -ItemType Directory | Out-Null
    }

    if ($CopySymbolsFromContainer) {
        CopySymbolsFromContainer -containerName $containerName -containerSymbolsFolder $containerSymbolsFolder
    }

    $GenerateReportLayoutParam = ""
    if (($GenerateReportLayout -ne "NotSpecified") -and ($platformversion.Major -ge 14)) {
        if ($GenerateReportLayout -eq "Yes") {
            $GenerateReportLayoutParam = "/GenerateReportLayout+"
        }
        else {
            $GenerateReportLayoutParam = "/GenerateReportLayout-"
        }
    }

    # unpack compiler
    Invoke-ScriptInBcContainer -containerName $containerName -ScriptBlock {
        if (!(Test-Path "c:\build" -PathType Container)) {
            $tempZip = Join-Path ([System.IO.Path]::GetTempPath()) "alc.zip"
            Copy-item -Path (Get-Item -Path "c:\run\*.vsix").FullName -Destination $tempZip
            Expand-Archive -Path $tempZip -DestinationPath "c:\build\vsix"
        }
    }

    $customConfig = Get-BcContainerServerConfiguration -ContainerName $containerName

    $dependencies = @()

    if (([bool]($appJsonObject.PSobject.Properties.name -eq "application")) -and $appJsonObject.application) {
        AddTelemetryProperty -telemetryScope $telemetryScope -key "application" -value $appJsonObject.application
        $dependencies += @{"publisher" = "Microsoft"; "name" = "Application"; "appId" = 'c1335042-3002-4257-bf8a-75c898ccb1b8'; "version" = $appJsonObject.application }
    }

    if (([bool]($appJsonObject.PSobject.Properties.name -eq "platform")) -and $appJsonObject.platform) {
        AddTelemetryProperty -telemetryScope $telemetryScope -key "platform" -value $appJsonObject.platform
        $dependencies += @{"publisher" = "Microsoft"; "name" = "System"; "appId" = '8874ed3a-0643-4247-9ced-7a7002f7135d'; "version" = $appJsonObject.platform }
    }

    if (([bool]($appJsonObject.PSobject.Properties.name -eq "test")) -and $appJsonObject.test) {
        $dependencies +=  @{"publisher" = "Microsoft"; "name" = "Test"; "appId" = ''; "version" = $appJsonObject.test }
        if (([bool]($customConfig.PSobject.Properties.name -eq "EnableSymbolLoadingAtServerStartup")) -and ($customConfig.EnableSymbolLoadingAtServerStartup -eq "true")) {
            throw "app.json should NOT have a test dependency when running hybrid development (EnableSymbolLoading)"
        }
    }

    if (([bool]($appJsonObject.PSobject.Properties.name -eq "dependencies")) -and $appJsonObject.dependencies) {
        $appJsonObject.dependencies | ForEach-Object {
            $dep = $_
            try { $appId = $dep.id } catch { $appId = $dep.appId }
            $dependencies += @{ "publisher" = $dep.publisher; "name" = $dep.name; "appId" = $appId; "version" = $dep.version }
        }
    }

    $existingApps = @()
    if (!$updateSymbols) {
        $existingApps = Invoke-ScriptInBcContainer -containerName $containerName -ScriptBlock { Param($appSymbolsFolder)
            Get-ChildItem -Path (Join-Path $appSymbolsFolder '*.app') | ForEach-Object {
                $alcPath = 'C:\build\vsix\extension\bin'
                $alToolExe = Join-Path $alcPath 'win32\altool.exe'
                if (-not (Test-Path $alToolExe)) {
                    $alToolExe = Join-Path $alcPath 'altool.exe'
                }
                $alToolExists = Test-Path -Path $alToolExe -PathType Leaf
                if ($alToolExists) {
                    $manifest = & "$alToolExe" GetPackageManifest "$($_.FullName)" | ConvertFrom-Json
                    $dependencies = @()
                    $propagateDependencies = $false
                    if ($manifest.PSObject.Properties.Name -eq 'dependencies') {
                        $dependencies = @($manifest.dependencies | ForEach-Object { @{ "Publisher" = $_.publisher; "Name" = $_.name; "Version" = $_.version; "AppId" = $_.id } })
                    }
                    if ($manifest.PSObject.Properties.Name -eq 'propagateDependencies') {
                        $propagateDependencies = $manifest.propagateDependencies
                    }
                    return @{ "AppId" = $manifest.id; "Publisher" = $manifest.publisher; "Name" = $manifest.name; "Version" = $manifest.version; "PropagateDependencies" = $propagateDependencies; "Dependencies" = $dependencies }
                }
                else {
                    $appInfo = Get-NavAppInfo -Path $_.FullName
                    return @{ "AppId" = $appInfo.AppId; "Publisher" = $appInfo.publisher; "Name" = $appInfo.name; "Version" = $appInfo.version; "PropagateDependencies" = $false; "Dependencies" = @() }
                }
            }
        } -ArgumentList $containerSymbolsFolder
    }
    $publishedApps = @()
    if ($customConfig.ServerInstance) {
        $publishedApps = Invoke-ScriptInBcContainer -containerName $containerName -ScriptBlock { Param($tenant)
            Get-NavAppInfo -ServerInstance $ServerInstance -tenant $tenant
            Get-NavAppInfo -ServerInstance $ServerInstance -symbolsOnly -ErrorAction SilentlyContinue
        } -ArgumentList $tenant | Where-Object { $_ -isnot [System.String] }
    }

    $applicationApp = $publishedApps | Where-Object { $_.publisher -eq "Microsoft" -and $_.name -eq "Application" }
    if ((-not $applicationApp) -and ($platformversion -le [System.Version]"26.0.0.0")) {
        # locate application version number in database if using SQLEXPRESS
        try {
            if (($customConfig.DatabaseServer -eq "localhost") -and ($customConfig.DatabaseInstance -eq "SQLEXPRESS")) {
                $appVersion = Invoke-ScriptInBcContainer -containerName $containerName -scriptblock { Param($databaseName)
                    (invoke-sqlcmd -ServerInstance 'localhost\SQLEXPRESS' -ErrorAction Stop -Query "SELECT [applicationversion] FROM [$databaseName].[dbo].[`$ndo`$dbproperty]").applicationVersion
                } -argumentList $customConfig.DatabaseName
                $publishedApps += @{ "Name" = "Application"; "Publisher" = "Microsoft"; "Version" = $appversion }
            }
        }
        catch {
            # ignore errors - use version number in app.json
        }
    }

    $sslVerificationDisabled = $false
    $serverInstance = $customConfig.ServerInstance
    $headers = @{}
    $useDefaultCredentials = $false
    $timeout = 100
    if ($bcAuthContext -and $environment) {
        $bcAuthContext = Renew-BcAuthContext -bcAuthContext $bcAuthContext
        $bcEnvironment = Get-BcEnvironments -bcAuthContext $bcAuthContext | Where-Object { $_.Name -eq $environment -and $_.Type -eq "Sandbox" }
        if (!$bcEnvironment) {
            throw "Environment $environment doesn't exist in the current context or it is not a Sandbox environment."
        }
        $publishedApps = Get-BcPublishedApps -bcAuthContext $bcAuthContext -environment $environment | Where-Object { $_.state -eq "installed" }
        $devServerUrl = "$($bcContainerHelperConfig.apiBaseUrl.TrimEnd('/'))/v2.0/$environment"
        $bearerAuthValue = "Bearer $($bcAuthContext.AccessToken)"
        $headers."Authorization" = $bearerAuthValue
    }
    elseif ($serverInstance -eq "") {
        if ($updateSymbols) {
            Write-Host -ForegroundColor Yellow "INFO: You have to specify AuthContext and Environment if you are compiling in a filesOnly container in order to download dependencies"
        }
        $devServerUrl = ""
    }
    else {
        if ($customConfig.DeveloperServicesSSLEnabled -eq "true") {
            $protocol = "https://"
        }
        else {
            $protocol = "http://"
        }

        $ip = Get-BcContainerIpAddress -containerName $containerName
        if ($ip) {
            $devServerUrl = "$($protocol)$($ip):$($customConfig.DeveloperServicesPort)/$ServerInstance"
        }
        else {
            $devServerUrl = "$($protocol)$($containerName):$($customConfig.DeveloperServicesPort)/$ServerInstance"
        }

        $timeout = 300000
        $sslVerificationDisabled = ($protocol -eq "https://")
        if ($customConfig.ClientServicesCredentialType -eq "Windows") {
            $useDefaultCredentials = $true
        }
        else {
            if (!($credential)) {
                throw "You need to specify credentials when you are not using Windows Authentication"
            }

            $pair = ("$($Credential.UserName):"+[System.Runtime.InteropServices.Marshal]::PtrToStringBSTR([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($credential.Password)))
            $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
            $base64 = [System.Convert]::ToBase64String($bytes)
            $basicAuthValue = "Basic $base64"
            $headers."Authorization" = $basicAuthValue
        }
    }

    $depidx = 0
    while ($depidx -lt $dependencies.Count) {
        $dependency = $dependencies[$depidx]
        Write-Host "Processing dependency $($dependency.Publisher)_$($dependency.Name)_$($dependency.Version) ($($dependency.AppId))"
        $existingApp = $existingApps | Where-Object {
            if ($platformversion -ge [System.Version]"19.0.0.0") {
                ((($dependency.appId -ne '' -and $_.AppId.ToString() -eq $dependency.appId) -or ($dependency.appId -eq '' -and $_.Name -eq $dependency.Name)) -and ([System.Version]$_.Version -ge [System.Version]$dependency.version))
            }
            else {
                (($_.Name -eq $dependency.name) -and ($_.Name -eq "Application" -or (($_.Publisher -eq $dependency.publisher) -and ([System.Version]$_.Version -ge [System.Version]$dependency.version))))
            }
        } | Sort-Object { [System.Version]$_.Version } -Descending | Select-Object -First 1
        $addDependencies = @()
        if ($existingApp) {
            Write-Host "Dependency App exists"
            if ($existingApp.ContainsKey('PropagateDependencies') -and $existingApp.PropagateDependencies -and $existingApp.ContainsKey('Dependencies')) {
                $addDependencies += $existingApp.Dependencies
            }
        }
        if ($updateSymbols -or !$existingApp) {
            $publisher = $dependency.publisher
            $name = $dependency.name
            $appId = $dependency.appId
            $version = $dependency.version
            $symbolsName = "$($publisher)_$($name)_$($version).app".Split([System.IO.Path]::GetInvalidFileNameChars()) -join ''
            $publishedApps | Where-Object { $_.publisher -eq $publisher -and $_.name -eq $name } | ForEach-Object {
                $symbolsName = "$($publisher)_$($name)_$($_.version).app".Split([System.IO.Path]::GetInvalidFileNameChars()) -join ''
            }
            if (($devServerUrl -eq "") -or ($headers -eq @{} -and !$useDefaultCredentials)) {
                Write-Host -ForegroundColor Yellow "WARNING: Unable to download symbols for $symbolsName"
            }
            else {
                $symbolsFile = Join-Path $appSymbolsFolder $symbolsName
                Write-Host "Downloading symbols: $symbolsName"

                $publisher = [uri]::EscapeDataString($publisher)
                $name = [uri]::EscapeDataString($name)
                if ($appId -and $platformversion -ge [System.Version]"20.0.0.0") {
                    $url = "$devServerUrl/dev/packages?appId=$($appId)&versionText=$($version)&tenant=$tenant"
                }
                else {
                    $url = "$devServerUrl/dev/packages?publisher=$($publisher)&appName=$($name)&versionText=$($version)&tenant=$tenant"
                }
                Write-Host "Url : $Url"
                try {
                    DownloadFileLow -sourceUrl $url -destinationFile $symbolsFile -timeout $timeout -useDefaultCredentials:$useDefaultCredentials -Headers $headers -skipCertificateCheck:$sslVerificationDisabled
                }
                catch {
                    $throw = $true
                    if ($customConfig.ServerInstance -ne '' -and $customConfig.ClientServicesCredentialType -eq "Windows") {
                        try {
                            Invoke-ScriptInBcContainer -containerName $containerName -scriptblock { Param($url, $symbolsFile)
                                $webClient = [System.Net.WebClient]::new()
                                $webClient.UseDefaultCredentials = $true
                                $webClient.DownloadFile($url, $symbolsFile)
                            } -argumentList $url, (Get-BcContainerPath -containerName $containerName -path $symbolsFile)
                            $throw = $false
                        }
                        catch {
                        }
                    }
                    if ($throw) {
                        throw "Error downloading symbols for $symbolsName. Error was: $($_.Exception.Message)"
                    }
                }
                if (Test-Path -Path $symbolsFile) {
                    $addDependencies = Invoke-ScriptInBcContainer -containerName $containerName -ScriptBlock { Param($symbolsFile, $platformversion)
                        # Wait for file to be accessible in container
                        While (-not (Test-Path $symbolsFile)) { Start-Sleep -Milliseconds 100 }

                        if ($platformversion.Major -ge 15) {
                            Add-Type -AssemblyName System.IO.Compression.FileSystem
                            Add-Type -AssemblyName System.Text.Encoding

                            try {
                                # Import types needed to invoke the compiler
                                $alcPath = 'C:\build\vsix\extension\bin'
                                $alToolExe = Join-Path $alcPath 'win32\altool.exe'
                                if (-not (Test-Path $alToolExe)) {
                                    $alToolExe = Join-Path $alcPath 'altool.exe'
                                }
                                $alToolExists = Test-Path -Path $alToolExe -PathType Leaf
                                if ($alToolExists) {
                                    $manifest = & "$alToolExe" GetPackageManifest "$symbolsFile" | ConvertFrom-Json
                                    if ($manifest.PSObject.Properties.Name -eq 'application' -and $manifest.application) {
                                        @{ "publisher" = "Microsoft"; "name" = "Application"; "appId" = 'c1335042-3002-4257-bf8a-75c898ccb1b8'; "version" = $manifest.Application }
                                    }
                                    if ($manifest.PSObject.Properties.Name -eq 'dependencies') {
                                        foreach ($dependency in $manifest.dependencies) {
                                            @{ "publisher" = $dependency.Publisher; "name" = $dependency.name; "appId" = $dependency.id; "Version" = $dependency.Version }
                                        }
                                    }
                                }
                                else {
                                    Add-Type -Path (Join-Path $alcPath Newtonsoft.Json.dll)
                                    Add-Type -Path (Join-Path $alcPath System.Collections.Immutable.dll)
                                    if (Test-Path (Join-Path $alcPath System.IO.Packaging.dll)) {
                                        Add-Type -Path (Join-Path $alcPath System.IO.Packaging.dll)
                                    }
                                    Add-Type -Path (Join-Path $alcPath Microsoft.Dynamics.Nav.CodeAnalysis.dll)

                                    $packageStream = [System.IO.File]::OpenRead($symbolsFile)
                                    $package = [Microsoft.Dynamics.Nav.CodeAnalysis.Packaging.NavAppPackageReader]::Create($PackageStream, $true)
                                    $manifest = $package.ReadNavAppManifest()

                                    if ($manifest.application) {
                                        @{ "publisher" = "Microsoft"; "name" = "Application"; "appId" = 'c1335042-3002-4257-bf8a-75c898ccb1b8'; "version" = $manifest.Application }
                                    }

                                    foreach ($dependency in $manifest.dependencies) {
                                        $appId = ''
                                        if ($dependency.psobject.Properties.name -eq 'appid') {
                                            $appId = $dependency.appid
                                        }
                                        elseif ($dependency.psobject.Properties.name -eq 'id') {
                                            $appId = $dependency.id
                                        }
                                        @{ "publisher" = $dependency.Publisher; "name" = $dependency.name; "appId" = $appId; "Version" = $dependency.Version }
                                    }
                                }
                            }
                            catch [System.Reflection.ReflectionTypeLoadException] {
                                if ($_.Exception.LoaderExceptions) {
                                    $_.Exception.LoaderExceptions | ForEach-Object {
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
                            }
                        }
                    } -ArgumentList (Get-BcContainerPath -containerName $containerName -path $symbolsFile), $platformversion
                }
            }
        }
        $addDependencies | ForEach-Object {
            $addDependency = $_
            $found = $false
            $dependencies | ForEach-Object {
                if ((($_.appId) -and ($_.appId -eq $addDependency.appId)) -or ($_.Publisher -eq $addDependency.Publisher -and $_.Name -eq $addDependency.Name)) {
                    $found = $true
                }
            }
            if (!$found) {
                Write-Host "Adding dependency to $($addDependency.Name) from $($addDependency.Publisher)"
                $dependencies += $addDependency
            }
        }
        $depidx++
    }

    $errorLogFilePath = ""
    if($generateErrorLog) {
        $errorLogFilePath = (Join-Path $containerOutputFolder $($appName -replace '.app$','.errorLog.json'))
    }

    $result = Invoke-ScriptInBcContainer -containerName $containerName -ScriptBlock { Param($appProjectFolder, $appSymbolsFolder, $appOutputFile, $EnableCodeCop, $EnableAppSourceCop, $EnablePerTenantExtensionCop, $EnableUICop, $CustomCodeCops, $rulesetFile, $enableExternalRulesets, $assemblyProbingPaths, $nowarn, $errorLogFilePath, $GenerateCrossReferences, $ReportSuppressedDiagnostics, $generateReportLayoutParam, $features, $preProcessorSymbols, $platformversion, $updateDependencies, $sourceRepositoryUrl, $sourceCommit, $buildBy, $buildUrl )

        if ($updateDependencies) {
            $appJsonFile = Join-Path $appProjectFolder 'app.json'
            $appJsonObject = [System.IO.File]::ReadAllLines($appJsonFile) | ConvertFrom-Json
            $changes = $false
            Write-Host "Enumerating Existing Apps"
            $existingApps = Get-ChildItem -Path (Join-Path $appSymbolsFolder '*.app') | ForEach-Object {
                $appInfo = Get-NavAppInfo -Path $_.FullName
                Write-Host "- FileName=$($_.Name), Id=$($appInfo.AppId), Publisher=$($appInfo.Publisher), Name=$($appInfo.Name), Version=$($appInfo.Version)"
                $appInfo
            }
            Write-Host "Modifying Dependencies"
            if (([bool]($appJsonObject.PSobject.Properties.name -eq "dependencies")) -and $appJsonObject.dependencies) {
                $appJsonObject.dependencies = @($appJsonObject.dependencies | ForEach-Object {
                    $dependency = $_
                    $dependencyAppId = "$(if ($dependency.PSObject.Properties.name -eq 'AppId') { $dependency.AppId } else { $dependency.Id })"
                    Write-Host "Dependency: Id=$dependencyAppId, Publisher=$($dependency.Publisher), Name=$($dependency.Name), Version=$($dependency.Version)"
                    $existingApps | Where-Object { "$($_.AppId)" -eq $dependencyAppId -and $_.Version -gt [System.Version]$dependency.Version } | ForEach-Object {
                        $dependency.Version = "$($_.Version)"
                        Write-Host "- Set dependency version to $($_.Version)"
                        $changes = $true
                    }
                    $dependency
                })
            }
            if (([bool]($appJsonObject.PSobject.Properties.name -eq "application")) -and $appJsonObject.application) {
                Write-Host "Application Dependency $($appJsonObject.application)"
                $existingApps | Where-Object { $_.Name -eq "Application" -and $_.Version -gt [System.Version]$appJsonObject.application } | ForEach-Object {
                    $appJsonObject.Application = "$($_.Version)"
                    Write-Host "- Set Application dependency to $($_.Version)"
                    $changes = $true
                }
            }
            if (([bool]($appJsonObject.PSobject.Properties.name -eq "platform")) -and $appJsonObject.platform) {
                Write-Host "Platform Dependency $($appJsonObject.platform)"
                $existingApps | Where-Object { $_.Name -eq "System" -and $_.Version -gt [System.Version]$appJsonObject.platform } | ForEach-Object {
                    $appJsonObject.platform = "$($_.Version)"
                    Write-Host "- Set Platform dependency to $($_.Version)"
                    $changes = $true
                }
            }
            if ($changes) {
                Write-Host "Updating app.json"
                $appJsonObject | ConvertTo-Json -depth 99 | Set-Content $appJsonFile -encoding UTF8
            }
        }

        $binPath = 'C:\build\vsix\extension\bin'
        $alcPath = Join-Path $binPath 'win32'
        if (-not (Test-Path $alcPath)) {
            $alcPath = $binPath
        }

        if (Test-Path -Path $appOutputFile -PathType Leaf) {
            Remove-Item -Path $appOutputFile -Force
        }

        Write-Host "Compiling..."
        Set-Location -Path $alcPath

        $alcItem = Get-Item -Path (Join-Path $alcPath 'alc.exe')
        [System.Version]$alcVersion = $alcItem.VersionInfo.FileVersion

        $alcParameters = @("/project:""$($appProjectFolder.TrimEnd('/\'))""", "/packagecachepath:""$($appSymbolsFolder.TrimEnd('/\'))""", "/out:""$appOutputFile""")
        if ($GenerateReportLayoutParam) {
            $alcParameters += @($GenerateReportLayoutParam)
        }

        # Microsoft.Dynamics.Nav.Analyzers.Common.dll needs to referenced first, as this is how the analyzers are loaded
        $analyzersPath = Join-Path $binPath 'Analyzers'
        if (-not (Test-Path $analyzersPath)) {
            $analyzersPath = $binPath
        }
        if ($EnableCodeCop -or $EnableAppSourceCop -or $EnablePerTenantExtensionCop -or $EnableUICop) {
            $analyzersCommonDLLPath = Join-Path $analyzersPath 'Microsoft.Dynamics.Nav.Analyzers.Common.dll'
            if (Test-Path $analyzersCommonDLLPath) {
                $alcParameters += @("/analyzer:$analyzersCommonDLLPath")
            }
        }

        if ($EnableCodeCop) {
            $alcParameters += @("/analyzer:$(Join-Path $analyzersPath 'Microsoft.Dynamics.Nav.CodeCop.dll')")
        }
        if ($EnableAppSourceCop) {
            $alcParameters += @("/analyzer:$(Join-Path $analyzersPath 'Microsoft.Dynamics.Nav.AppSourceCop.dll')")
        }
        if ($EnablePerTenantExtensionCop) {
            $alcParameters += @("/analyzer:$(Join-Path $analyzersPath 'Microsoft.Dynamics.Nav.PerTenantExtensionCop.dll')")
        }
        if ($EnableUICop) {
            $alcParameters += @("/analyzer:$(Join-Path $analyzersPath 'Microsoft.Dynamics.Nav.UICop.dll')")
        }

        if ($CustomCodeCops.Count -gt 0) {
            $CustomCodeCops | ForEach-Object {
                $analyzerFileName = $_
                if ($_ -like 'https://*') {
                    $analyzerFileName = Join-Path $analyzersPath $(Split-Path $_ -Leaf)
                    Download-File -SourceUrl $_ -destinationFile $analyzerFileName
                }
                $alcParameters += @("/analyzer:$analyzerFileName")
            }
        }

        if ($rulesetFile) {
            $alcParameters += @("/ruleset:$rulesetfile")
        }

        if ($enableExternalRulesets) {
            $alcParameters += @("/enableexternalrulesets")
        }

        if ($nowarn) {
            $alcParameters += @("/nowarn:$nowarn")
        }

        if ($errorLogFilePath) {
            $alcParameters += @("/errorLog:""$errorLogFilePath""")
        }

        if ($GenerateCrossReferences -and $platformversion.Major -ge 18) {
            $alcParameters += @("/generatecrossreferences")
        }

        if ($ReportSuppressedDiagnostics) {
            if ($alcVersion -ge [System.Version]"9.1.0.0") {
                $alcParameters += @("/reportsuppresseddiagnostics")
            }
            else {
                Write-Host -ForegroundColor Yellow "ReportSuppressedDiagnostics was specified, but the version of the AL Language Extension does not support this. Get-LatestAlLanguageExtensionUrl returns a location for the latest AL Language Extension"
            }
        }

        if ($alcVersion -ge [System.Version]"12.0.12.41479") {
            if ($sourceRepositoryUrl) {
                $alcParameters += @("/SourceRepositoryUrl:$sourceRepositoryUrl")
            }
            if ($sourceCommit) {
                $alcParameters += @("/SourceCommit:$sourceCommit")
            }
            if ($buildBy) {
                $alcParameters += @("/BuildBy:$buildBy")
            }
            if ($buildUrl) {
                $alcParameters += @("/BuildUrl:$buildUrl")
            }
        }

        if ($assemblyProbingPaths) {
            $alcParameters += @("/assemblyprobingpaths:$assemblyProbingPaths")
        }

        if ($features) {
            $alcParameters +=@("/features:$($features -join ',')")
        }

        $preprocessorSymbols | where-Object { $_ } | ForEach-Object { $alcParameters += @("/D:$_") }

        Write-Host ".\alc.exe $([string]::Join(' ', $alcParameters))"

        & .\alc.exe $alcParameters

        if ($lastexitcode -ne 0 -and $lastexitcode -ne -1073740791) {
            "App generation failed with exit code $lastexitcode"
        }
    } -ArgumentList $containerProjectFolder, $containerSymbolsFolder, (Join-Path $containerOutputFolder $appName), $EnableCodeCop, $EnableAppSourceCop, $EnablePerTenantExtensionCop, $EnableUICop, $CustomCodeCopFiles, $containerRulesetFile, $enableExternalRulesets, $assemblyProbingPaths, $nowarn, $errorLogFilePath, $GenerateCrossReferences, $ReportSuppressedDiagnostics, $GenerateReportLayoutParam, $features, $preProcessorSymbols, $platformversion, $updateDependencies, $sourceRepositoryUrl, $sourceCommit, $buildBy, $buildUrl

    if ($treatWarningsAsErrors) {
        $regexp = ($treatWarningsAsErrors | ForEach-Object { if ($_ -eq '*') { ".*" } else { $_ } }) -join '|'
        $result = $result | ForEach-Object { $_ -replace "^(.*)warning ($regexp):(.*)`$", '$1error $2:$3' }
    }

    $devOpsResult = ""
    if ($result) {
        $Parameters = @{
            "FailOn"           = $FailOn
            "AlcOutput"        = $result
            "DoNotWriteToHost" = $true
        }
        if ($gitHubActions) {
            $Parameters += @{
                "gitHubActions" = $true
            }
            if (-not $basePath) {
                $basePath = $ENV:GITHUB_WORKSPACE
            }
        }
        if ($basePath) {
            $Parameters += @{
                "basePath" = (Get-BcContainerPath -containerName $containerName -path $basePath)
            }
        }
        $devOpsResult = Convert-ALCOutputToAzureDevOps @Parameters
    }
    if ($AzureDevOps -or $gitHubActions) {
        $devOpsResult | ForEach-Object { $outputTo.Invoke($_) }
    }
    else {
        $result | ForEach-Object { $outputTo.Invoke($_) }
        if ($devOpsResult -like "*task.complete result=Failed*") {
            throw "App generation failed"
        }
    }

    $result | Where-Object { $_ -like "App generation failed*" } | ForEach-Object { throw $_ }

    $timespend = [Math]::Round([DateTime]::Now.Subtract($startTime).Totalseconds)
    $appFile = Join-Path $appOutputFolder $appName

    if (Test-Path -Path $appFile) {
        Write-Host "$appFile successfully created in $timespend seconds"
        if ($CopyAppToSymbolsFolder) {
            Copy-Item -Path $appFile -Destination $appSymbolsFolder -ErrorAction SilentlyContinue
            if (Test-Path -Path (Join-Path -Path $appSymbolsFolder -ChildPath $appName)) {
                Write-Host "$($appName) copied to $($appSymbolsFolder)"
                Invoke-ScriptInBcContainer -containerName $containerName -ScriptBlock { Param($appSymbolsFolder, $appName)
                    $appFile = Join-Path -Path $appSymbolsFolder -ChildPath $appName
                    while (-not (Test-Path -Path $appFile)) { Start-Sleep -Seconds 1 }
                } -ArgumentList $containerSymbolsFolder,"$($appName)"
            }
        }
    }
    else {
        throw "App generation failed"
    }
    $appFile
}
catch {
    TrackException -telemetryScope $telemetryScope -errorRecord $_
    throw
}
finally {
    TrackTrace -telemetryScope $telemetryScope
}
}
Set-Alias -Name Compile-AppInNavContainer -Value Compile-AppInBcContainer
Export-ModuleMember -Function Compile-AppInBcContainer -Alias Compile-AppInNavContainer

# SIG # Begin signature block
# MIInbgYJKoZIhvcNAQcCoIInXzCCJ1sCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCshB4AyKi2cG4L
# EybJI0rvT+QbZsL+pfuITB766VbI4qCCDMkwggYEMIID7KADAgECAhMzAAACHPrN
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
# hvcNAQkEMSIEIAvb3S7za07CtJLON3rkoArXS/qNPepoQndTQaW+kzEbMEIGCisG
# AQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEAaX3qMfALvGINTPfdfdO7
# Y0Zrwo0Bpsl+OcGEd6in+2KRMlwUf1l9gba8MACDAGZHxP19LsuED5UvJKuHYhsd
# KacEM3lAI1VHIL7RJor5Otk51MRshRQoTBjszUeAvKxD668RH4Hodg3yBSLmUG1M
# F5eFkVFVzhgKCbJvsp8odZNc3vUOR2lg8KneUmG+QiabYwWpYFxUeEB54sDfsRDb
# Jy2IIGC8AcwLcElMMo8D5uDF6nt4wZ/NdP95+YUvnQktzs4DRxN8KaiVle/+8eyz
# M1Ywgbp6WSJZA8+nJJb1uBn5SmrLrEDN+x1RajmG/ZnDbLI+FKKr31QkgBlZXYmm
# CaGCF60wghepBgorBgEEAYI3AwMBMYIXmTCCF5UGCSqGSIb3DQEHAqCCF4YwgheC
# AgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFFMIIB
# QQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCDWvasHW8Mq2LikoQ/m
# xctjaKVyiDKJ5efmvfE9dF/NfgIGaokHZTQBGBMyMDI2MDgyNzA2MjkzNy4zMTNa
# MASAAgH0oIHZpIHWMIHTMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0
# ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjo0MzFBLTA1RTAtRDk0NzElMCMG
# A1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaCCEfswggcoMIIFEKAD
# AgECAhMzAAACHUvAkoc4hX45AAEAAAIdMA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29m
# dCBUaW1lLVN0YW1wIFBDQSAyMDEwMB4XDTI1MDgxNDE4NDgzM1oXDTI2MTExMzE4
# NDgzM1owgdMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTAr
# BgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUG
# A1UECxMeblNoaWVsZCBUU1MgRVNOOjQzMUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxN
# aWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOC
# Ag8AMIICCgKCAgEAorSgaAA8oOl4ph574zw29egUN8DDepRHLX8FM1zHNJmXG6Kr
# SqUKwzcKafopuYdPTETTCvb9aJfESuAU0iGNUFI/D6R0kvdfpe2oPX+E3sbTQvGi
# 4JPH5qdIYUaJ45V/4bqe8eNvbWzpC+ZKjH193DeiI1XAI918JoQmBhlEXo/Ton17
# 21luZJgincsf5LjMY3jX84WyXUSX3dsS7h/7xVI+w1yjg7pa+0y3o/me2Tsv6UJU
# dSTQap5ORGSfCnclnP1z3IiiWIWr3Vo7aIPWsgJzq3m5GxpxUHCQk8qzUhk50y/u
# B+LGE3WIK2C77iy9iFsSfSLUnyMEzGRDW9mXHT4PH7Ozz6CHqQEiNvwcHqlvlCh1
# pHQh1NXQSAqOoVBs5mi6easf6yxWTfe5DrR79503r8pU6VqC2Y9XMRU4wH9QbYXY
# sIUZ33Jmndy22W1LBDAbxBPQHCBlncGDU3BgdhVUVLe80mggFO98FdkWho67w4kP
# dCTRkvdvkY8PrQYE/nQjHXCa0g7LcMttZb6ejMHfQ+tUWXv6+nZ4Ynkr2OkaxclF
# Cw4RIYNMWD26AWbQj/WEdzga18fKtw66L5gzXPza6jFBfPJeKE3H8QAuwpirmH4m
# s+5nUjNNQOmNgqJn0U1+3Yn7ClswD79YN0r3fdbYBMDApBZJpNlK7q7HXRsCAwEA
# AaOCAUkwggFFMB0GA1UdDgQWBBSEWfBxNEamZtXm8gl92Yq80jfxXTAfBgNVHSME
# GDAWgBSfpxVdAF5iXYP05dJlpxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1l
# LVN0YW1wJTIwUENBJTIwMjAxMCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsG
# AQUFBzAChlBodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01p
# Y3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMB
# Af8EAjAAMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDAN
# BgkqhkiG9w0BAQsFAAOCAgEAkdweB4yxvLspLKq0D+miyD4Q0EcxVFpNZuJxiR54
# gWRkeTDDuymNeB03JhlsBpbwSYJ5uZSgDBCvwHED2VL8lJpFlOprJzxsXWC2NTfA
# +O+PO5Fk5jw6LHh6jeBADDEdQAx3Hqi7Zm0JwvQ93z5f6dtxkm29WqOcHYXRXfAQ
# wy1hSrLXyfeblqR66jpP/9n0fCkWU4ggsUjQpQ2Ngj1DV09J4Y3y7p9Nd81+Xs6q
# Yo++7RKm8qiB/5NDeigOLjlAeFgiEXIRUJW+mJyqpQw+OORlaqcFjR8Hu0G+/7bM
# dek68YX+kPpDBk7Ue+I/xgiYJ1xcDRBn/vczLtN72+RIlD4UgXYLuBSCk//pDEPX
# 5z39Cr+rkc6E4Y28FPk4BhloAyvp628P4xfElQY8TcxraUbZShypocE6ny95D1K1
# BkltZmrHVKCxmglnuOlM15NKIrXFlXCzdqpCtIwQ417wNAVF/QDPvzzbumPdTi6f
# b0tLbScYobV6zvbBsMsKEME4Tj1b9oIXC8dybJq4nbboEXYpRwi1QAbpSNrn+PxG
# W9uf1q63FnMJu4gm3Oh63njW/iVf723quzyHrSijWMgY0HiRiHQi0Jyu0h8MdhRU
# p7mxbmLQckPiOFwAlIaUN/k725y/aLWpkRU6fqmLlEOyH5WpyLd23AYy9r8v+Qob
# a6swggdxMIIFWaADAgECAhMzAAAAFcXna54Cm0mZAAAAAAAVMA0GCSqGSIb3DQEB
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
# ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjo0MzFBLTA1RTAtRDk0NzElMCMG
# A1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIa
# AxUAuoO+BKbfXzqyfi9GLEdWHkCLeT+ggYMwgYCkfjB8MQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1T
# dGFtcCBQQ0EgMjAxMDANBgkqhkiG9w0BAQsFAAIFAO46HOUwIhgPMjAyNjA4Mjcw
# MjE4MTNaGA8yMDI2MDgyODAyMTgxM1owdDA6BgorBgEEAYRZCgQBMSwwKjAKAgUA
# 7joc5QIBADAHAgEAAgIGxDAHAgEAAgISlTAKAgUA7jtuZQIBADA2BgorBgEEAYRZ
# CgQCMSgwJjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0G
# CSqGSIb3DQEBCwUAA4IBAQCNeGSwjOU9wE6LtNQLE4hbwTODZ84uSX062AQvkwWb
# TYb2zoItRi4YDdQ+h4m69j7m6Ty2YIDb5rd7Mp2qspEmkW7VTKpUDvaAB51sbg9n
# hy5DnZ713T7+5+mPMKxaLc4OH+WwTpbLcHgiaVDJfgTWq21PPqoFsLmeWY3QHIoy
# 0AlxfM62DR3nBjQ0HPaMl1s7HZcWnOey0I9KJNTckgyj7kR0F531r3pYPoRNZKOK
# Y/yyvon/Mi5IOEE1evmTan3GdnrCZWwFfOqy0V1bfjwG5+DvKTOEvWH48QZhZblL
# TIB1u5ObltLLaX7052PZMqKKBMw179hA3MebELx+ykbvMYIEDTCCBAkCAQEwgZMw
# fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMd
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAIdS8CShziFfjkAAQAA
# Ah0wDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRAB
# BDAvBgkqhkiG9w0BCQQxIgQgLOByOXNn1Vnf11Yp9kJrTHFBvte02+rjX/NlMacg
# FLcwgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCCxtpXMXEiLJzrqM77ep4rT
# NwrMOj6gpWN9hZvpj5QFUTCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBD
# QSAyMDEwAhMzAAACHUvAkoc4hX45AAEAAAIdMCIEIBzVLmWX482vtVEWDkXWKs1x
# nK0jgFo634qHyC7UNSyhMA0GCSqGSIb3DQEBCwUABIICAIcZdyXl0DugeZ25Yzuz
# ye32zb43YiD/8wnFm0prKGC0Dn65jB+zVzNrxp58Xxwo5wOpgVTgQ0ZQh+lRwNIN
# 0Y5SVJFsaIBvea4/CatHtKzTZeCGPHKqfSDefwH3QkrmYng8DodtN/TnwjyM837d
# +1stST1hAUEcQzElaUVkafLuv0sF/spGYnPuzbTDIdzg/Sl2/SdyI6nXK+vCbYAp
# ZxLEMlxK7ceeLQlvJayMFuMzjxxtX1vm84F5I62lPYdemiTCU2WIbDEBsvVdjXir
# OAoCWtpeT7chlRwzWupju7HR+Qqpm67ZLN2AdDBk2RMALyJkSY/jtF9m9uXpNLD/
# xd6UbAYADXtuL/LtzGdxG1ViebJtQAMumwSgpqIxohn3p/LvmmV4SXMnOxfc4ijC
# JNkFg2RzKHeIR/5/lj25iHrSkyfqsw9eKDricm+ThfAnXEmgsogCupmmcfDAN24w
# yqyiQzggjGuw6dv/Ji/lAQiEgp3LYvBN2wLBlYDaZc897t38rICb9n9UBj4liaDP
# QnKSPj2Z0NMHkzGYYpBxC7lGAPmNGi37VGriaAAF12rtMsaaM4sFCEcvZgLv3GZ7
# 8rWwb+azjTyHxhXCGJiaEPZ6zyRv6xffXkRl0zrG4tSlPHNpU3nwSKBnQ2DYV4f4
# JQG498QolWiIWe9sIWrthO4v
# SIG # End signature block
