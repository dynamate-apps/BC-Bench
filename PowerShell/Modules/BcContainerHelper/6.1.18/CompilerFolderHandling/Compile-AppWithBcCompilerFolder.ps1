<#
 .Synopsis
  Compile app without docker (used by Run-AlPipeline to compile apps without docker)
 .Description
 .Parameter compilerFolder
  Folder in which compiler and dlls can be found (created by New-BcCompilerFolder)
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
 .Parameter UpdateDependencies
  Update the dependency version numbers to the actual version number used during compilation
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
 .Parameter preProcessorSymbols
  PreProcessorSymbols to set when compiling the app.
 .Parameter generatecrossreferences
  Include this flag to generate cross references when compiling
 .Parameter reportSuppressedDiagnostics
  Set reportSuppressedDiagnostics flag on ALC when compiling to ignore pragma warning disables
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
  Compile-AppWithBcCompilerFolder -containerName test -credential $credential -appProjectFolder "C:\Users\freddyk\Documents\AL\Project1\Test"
 .Example
  Compile-AppWithBcCompilerFolder -containerName test -appProjectFolder "C:\Users\freddyk\Documents\AL\Test"
 .Example
  Compile-AppWithBcCompilerFolder -containerName test -appProjectFolder "C:\Users\freddyk\Documents\AL\Test" -outputTo { Param($line) if ($line -notlike "*sourcepath=C:\Users\freddyk\Documents\AL\Test\Org\*") { Write-Host $line } }
#>
function Compile-AppWithBcCompilerFolder {
    Param (
        [Parameter(Mandatory = $true)]
        [string] $compilerFolder,
        [Parameter(Mandatory = $true)]
        [string] $appProjectFolder,
        [Parameter(Mandatory = $false)]
        [string] $appOutputFolder = (Join-Path $appProjectFolder "output"),
        [Parameter(Mandatory = $false)]
        [string] $appSymbolsFolder = (Join-Path $appProjectFolder ".alpackages"),
        [Parameter(Mandatory = $false)]
        [string] $appName = "",
        [string] $basePath = "",
        [switch] $UpdateDependencies,
        [switch] $CopyAppToSymbolsFolder,
        [ValidateSet('Yes', 'No', 'NotSpecified')]
        [string] $GenerateReportLayout = 'NotSpecified',
        [switch] $AzureDevOps = $bcContainerHelperConfig.IsAzureDevOps,
        [switch] $gitHubActions = $bcContainerHelperConfig.IsGitHubActions,
        [switch] $EnableCodeCop,
        [switch] $EnableAppSourceCop,
        [switch] $EnablePerTenantExtensionCop,
        [switch] $EnableUICop,
        [ValidateSet('none', 'error', 'warning', 'newWarning')]
        [string] $FailOn = 'none',
        [Parameter(Mandatory = $false)]
        [string] $rulesetFile,
        [switch] $generateErrorLog,
        [switch] $enableExternalRulesets,
        [string[]] $CustomCodeCops = @(),
        [Parameter(Mandatory = $false)]
        [string] $nowarn,
        [string[]] $preProcessorSymbols = @(),
        [switch] $GenerateCrossReferences,
        [switch] $ReportSuppressedDiagnostics,
        [Parameter(Mandatory = $false)]
        [string] $assemblyProbingPaths,
        [Parameter(Mandatory = $false)]
        [ValidateSet('ExcludeGeneratedTranslations', 'GenerateCaptions', 'GenerateLockedTranslations', 'NoImplicitWith', 'TranslationFile', 'LcgTranslationFile')]
        [string[]] $features = @(),
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

        if (!(Test-Path $compilerFolder)) {
            throw "CompilerFolder doesn't exist"
        }

        $dllsPath = Join-Path $compilerFolder 'dlls'
        $symbolsPath = Join-Path $compilerFolder 'symbols'

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

        if (!(Test-Path $appOutputFolder -PathType Container)) {
            New-Item $appOutputFolder -ItemType Directory | Out-Null
        }

        Write-Host "Using Symbols Folder: $appSymbolsFolder"
        if (!(Test-Path -Path $appSymbolsFolder -PathType Container)) {
            New-Item -Path $appSymbolsFolder -ItemType Directory | Out-Null
        }

        $dependencies = @()

        if (([bool]($appJsonObject.PSobject.Properties.name -eq "application")) -and $appJsonObject.application) {
            AddTelemetryProperty -telemetryScope $telemetryScope -key "application" -value $appJsonObject.application
            $dependencies += @{"publisher" = "Microsoft"; "name" = "Application"; "appId" = 'c1335042-3002-4257-bf8a-75c898ccb1b8'; "version" = $appJsonObject.application }
        }

        if (([bool]($appJsonObject.PSobject.Properties.name -eq "platform")) -and $appJsonObject.platform) {
            AddTelemetryProperty -telemetryScope $telemetryScope -key "platform" -value $appJsonObject.platform
            $dependencies += @{"publisher" = "Microsoft"; "name" = "System"; "appId" = '8874ed3a-0643-4247-9ced-7a7002f7135d'; "version" = $appJsonObject.platform }
        }

        if (([bool]($appJsonObject.PSobject.Properties.name -eq "dependencies")) -and $appJsonObject.dependencies) {
            $appJsonObject.dependencies | ForEach-Object {
                $dep = $_
                try { $appId = $dep.id } catch { $appId = $dep.appId }
                $dependencies += @{ "publisher" = $dep.publisher; "name" = $dep.name; "appId" = $appId; "version" = $dep.version }
            }
        }

        Write-Host "Enumerating Apps in CompilerFolder $symbolsPath"
        $compilerFolderAppFiles = @(Get-ChildItem -Path (Join-Path $symbolsPath '*.app') | Select-Object -ExpandProperty FullName)
        $compilerFolderApps = @(GetAppInfo -AppFiles $compilerFolderAppFiles -compilerFolder $compilerFolder -cacheAppinfoPath (Join-Path $symbolsPath 'cache_AppInfo.json'))

        Write-Host "Enumerating Apps in Symbols Folder $appSymbolsFolder"
        $existingAppFiles = @(Get-ChildItem -Path (Join-Path $appSymbolsFolder '*.app') | Select-Object -ExpandProperty FullName)
        $existingApps = @(GetAppInfo -AppFiles $existingAppFiles -compilerFolder $compilerFolder -cacheAppinfoPath (Join-Path $appSymbolsFolder 'cache_AppInfo.json'))

        $depidx = 0
        while ($depidx -lt $dependencies.Count) {
            $dependency = $dependencies[$depidx]
            Write-Host "Processing dependency $($dependency.Publisher)_$($dependency.Name)_$($dependency.Version) ($($dependency.AppId))"
            $existingApp = $existingApps | Where-Object {
                ((($dependency.appId -ne '' -and $_.AppId -eq $dependency.appId) -or ($dependency.appId -eq '' -and $_.Name -eq $dependency.Name)) -and ([System.Version]$_.Version -ge [System.Version]$dependency.version))
            } | Sort-Object { [System.Version]$_.Version } -Descending | Select-Object -First 1
            $addDependencies = @()
            if ($existingApp) {
                Write-Host "Dependency App exists"
                if ($existingApp.ContainsKey('PropagateDependencies') -and $existingApp.PropagateDependencies -and $existingApp.ContainsKey('Dependencies')) {
                    $addDependencies += $existingApp.Dependencies
                }
            }
            else {
                Write-Host "Dependency App not found"
                $copyCompilerFolderApps = @($compilerFolderApps | Where-Object {
                        ((($dependency.appId -ne '' -and $_.AppId -eq $dependency.appId) -or ($dependency.appId -eq '' -and $_.Name -eq $dependency.Name)) -and ([System.Version]$_.Version -ge [System.Version]$dependency.version))
                    })
                $copyCompilerFolderApps | ForEach-Object {
                    $copyCompilerFolderApp = $_
                    $existingApps += $copyCompilerFolderApp
                    Write-Host "Copying $($copyCompilerFolderApp.path) to $appSymbolsFolder"
                    Copy-Item -Path $copyCompilerFolderApp.path -Destination $appSymbolsFolder -Force
                    if ($copyCompilerFolderApp.Application) {
                        if (!($dependencies | where-Object { $_.Name -eq 'Application' })) {
                            $dependencies += @{"publisher" = "Microsoft"; "name" = "Application"; "appId" = 'c1335042-3002-4257-bf8a-75c898ccb1b8'; "version" = $copyCompilerFolderApp.Application }
                        }
                    }
                    if (!($dependencies | where-Object { ($_.Name -eq "System") -and ($_.Publisher -eq "Microsoft") })) {
                        $dependencies += @{"publisher" = "Microsoft"; "name" = "System"; "appId" = '8874ed3a-0643-4247-9ced-7a7002f7135d'; "version" = $copyCompilerFolderApp.Platform }
                    }
                    $addDependencies += $copyCompilerFolderApp.Dependencies
                }
            }
            $addDependencies | ForEach-Object {
                $addDependency = $_
                try {
                    $appId = $addDependency.id
                }
                catch {
                    $appId = $addDependency.appid
                }
                $dependencyExists = $dependencies | Where-Object { $_.appId -eq $appId }
                if (-not $dependencyExists) {
                    Write-Host "Adding dependency to $($addDependency.Name) from $($addDependency.Publisher)"
                    $dependencies += @($compilerFolderApps | Where-Object { $_.appId -eq $appId })
                }
            }
            $depidx++
        }

        $systemSymbolsApp = @($existingApps | Where-Object { ($_.Name -eq "System") -and ($_.Publisher -eq "Microsoft") })
        if ($systemSymbolsApp.Count -ne 1) {
            if ($systemSymbolsApp.Count -eq 0) {
                throw "Unable to locate system symbols. No System.app file found in symbols folder: $appSymbolsFolder"
            }
            else {
                throw "Multiple system symbols found ($($systemSymbolsApp.Count) instances). Only one System.app is expected. Please cleanup the symbols folder: $appSymbolsFolder"
            }
        }
        $platformversion = $systemSymbolsApp.Version
        Write-Host "Platform version: $platformversion"

        $GenerateReportLayoutParam = ""
        if (($GenerateReportLayout -ne "NotSpecified") -and ($platformversion.Major -ge 14)) {
            if ($GenerateReportLayout -eq "Yes") {
                $GenerateReportLayoutParam = "/GenerateReportLayout+"
            }
            else {
                $GenerateReportLayoutParam = "/GenerateReportLayout-"
            }
        }

        if ($updateDependencies) {
            $appJsonFile = Join-Path $appProjectFolder 'app.json'
            $appJsonObject = [System.IO.File]::ReadAllLines($appJsonFile) | ConvertFrom-Json
            $changes = $false
            Write-Host "Modifying Dependencies"
            if (([bool]($appJsonObject.PSobject.Properties.name -eq "dependencies")) -and $appJsonObject.dependencies) {
                $appJsonObject.dependencies = @($appJsonObject.dependencies | ForEach-Object {
                        $dependency = $_
                        $dependencyAppId = "$(if ($dependency.PSObject.Properties.name -eq 'AppId') { $dependency.AppId } else { $dependency.Id })"
                        Write-Host "Dependency: Id=$dependencyAppId, Publisher=$($dependency.Publisher), Name=$($dependency.Name), Version=$($dependency.Version)"
                        $existingApps | Where-Object { $_.AppId -eq [System.Guid]$dependencyAppId -and $_.Version -gt [System.Version]$dependency.Version } | ForEach-Object {
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
                $existingApps | Where-Object { $_.Name -eq "System" -and $_.Version -gt [System.Version]$appJsonObject.platform -and $_.Publisher -eq "Microsoft" } | ForEach-Object {
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

        $probingPaths = @()
        if ($assemblyProbingPaths) {
            $probingPaths += @($assemblyProbingPaths)
        }
        $netpackagesPath = Join-Path $appProjectFolder ".netpackages"
        if (Test-Path $netpackagesPath) {
            $probingPaths += @($netpackagesPath)
        }
        if (Test-Path $dllsPath) {
            $probingPaths += @((Join-Path $dllsPath "Service"), (Join-Path $dllsPath "Mock Assemblies"))
        }

        $sharedFolder = Join-Path $dllsPath "shared"
        if (Test-Path $sharedFolder) {
            $probingPaths = @((Join-Path $dllsPath "OpenXML"), $sharedFolder) + $probingPaths
        }
        elseif ($isLinux -or $isMacOS) {
            $probingPaths = @((Join-Path $dllsPath "OpenXML")) + $probingPaths
        }
        elseif ($platformversion.Major -ge 22) {
            # Determine the correct .NET runtime version for assembly probing paths
            # If the artifact ships a manifest.json with a dotNetVersion, use the matching installed runtime
            $dotNetVersionForProbing = $dotNetRuntimeVersionInstalled
            $manifestFile = Join-Path $compilerFolder "manifest.json"
            if (Test-Path $manifestFile) {
                try {
                    $manifest = Get-Content $manifestFile -Encoding UTF8 | ConvertFrom-Json
                    if ($manifest.dotNetVersion) {
                        $requiredDotNetMajor = ([System.Version]$manifest.dotNetVersion).Major
                        $dotNetCorePath = 'C:\Program Files\dotnet\shared\Microsoft.NETCore.App'
                        if (Test-Path $dotNetCorePath) {
                            $matchingVersion = Get-ChildItem $dotNetCorePath | ForEach-Object {
                                try { [System.Version]$_.Name } catch {}
                            } | Where-Object { $_.Major -eq $requiredDotNetMajor } | Sort-Object -Descending | Select-Object -First 1
                            if ($matchingVersion -and (Test-Path "C:\Program Files\dotnet\shared\Microsoft.AspNetCore.App\$matchingVersion")) {
                                Write-Host "Using .NET $matchingVersion for assembly probing (artifact requires .NET $requiredDotNetMajor)"
                                $dotNetVersionForProbing = $matchingVersion
                            }
                        }
                    }
                }
                catch {
                    Write-Host "Warning: Could not read manifest.json from compiler folder: $($_.Exception.Message)"
                }
            }
            if ($dotNetVersionForProbing -ge [System.Version]$bcContainerHelperConfig.MinimumDotNetRuntimeVersionStr) {
                $probingPaths = @((Join-Path $dllsPath "OpenXML"), "C:\Program Files\dotnet\shared\Microsoft.NETCore.App\$dotNetVersionForProbing", "C:\Program Files\dotnet\shared\Microsoft.AspNetCore.App\$dotNetVersionForProbing") + $probingPaths
            }
            else {
                $probingPaths = @((Join-Path $dllsPath "OpenXML")) + $probingPaths
            }
        }
        else {
            $probingPaths = @((Join-Path $dllsPath "OpenXML"), 'C:\Windows\Microsoft.NET\Assembly') + $probingPaths
        }
        $assemblyProbingPaths = $probingPaths -join ','

        $appOutputFile = Join-Path $appOutputFolder $appName
        if (Test-Path -Path $appOutputFile -PathType Leaf) {
            Remove-Item -Path $appOutputFile -Force
        }

        Write-Host "Compiling..."
        $alcParameters = @()
        $binPath = Join-Path $compilerFolder 'compiler/extension/bin'

        $compilerPlatform = 'win32'
        switch ($true) {
            ($isLinux) { $compilerPlatform = 'linux' }
            ($isMacOS) { $compilerPlatform = 'darwin' }
        }
        $alcPath = Join-Path $binPath $compilerPlatform
        if (-not (Test-Path $alcPath)) {
            $alcPath = $binPath
        }

        $alcExe = 'alc.exe'
        $alcCmd = ".\$alcExe"
        if ($isLinux -or $isMacOS) {
            if ($alcPath -eq $binPath) {
                $alcCmd = "dotnet"
                $alcExe = 'alc.dll'
                $alcParameters += @((Join-Path $alcPath $alcExe))
                Write-Host "No $($compilerPlatform) version of alc found. Using dotnet to run alc.dll."
            }
            else {
                $alcExe = 'alc'
                $alcCmd = "./$alcExe"
            }
        }

        if (!(Test-Path -Path (Join-Path $alcPath $alcExe))) {
            $alcCmd = "dotnet"
            $alcExe = 'alc.dll'
            $alcParameters += @((Join-Path $alcPath $alcExe))
            Write-Host "No alc executable in $compilerPlatform. Using dotnet to run alc.dll."
        }
        $alcItem = Get-Item -Path (Join-Path $alcPath $alcExe)
        [System.Version]$alcVersion = $alcItem.VersionInfo.FileVersion

        $alcParameters += @("/project:""$($appProjectFolder.TrimEnd('/\'))""", "/packagecachepath:""$($appSymbolsFolder.TrimEnd('/\'))""", "/out:""$appOutputFile""")
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

        if ($generateErrorLog) {
            $errorLogFilePath = $appOutputFile -replace '.app$', '.errorLog.json'
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
            $alcParameters += @("/features:$($features -join ',')")
        }

        $preprocessorSymbols | where-Object { $_ } | ForEach-Object { $alcParameters += @("/D:$_") }

        Push-Location -Path $alcPath
        try {
            Write-Host "$alcCmd $([string]::Join(' ', $alcParameters))"
            $result = & $alcCmd $alcParameters
        }
        finally {
            Pop-Location
        }

        if ($lastexitcode -ne 0 -and $lastexitcode -ne -1073740791) {
            "App generation failed with exit code $lastexitcode"
        }

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
                    "basePath" = $basePath
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
Export-ModuleMember -Function Compile-AppWithBcCompilerFolder

# SIG # Begin signature block
# MIInbgYJKoZIhvcNAQcCoIInXzCCJ1sCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBenVo2XuqnqeEv
# FUw+iSKRqzgTp3cRRdcSvyYXOX3q7qCCDMkwggYEMIID7KADAgECAhMzAAACHPrN
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
# hvcNAQkEMSIEIBs5SvNhVVJCVNc8neYKQeh8PdMO92/jIt83/MtS513jMEIGCisG
# AQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEAvm87mIpGeRXunHkCSzTs
# scV6a6dJapFHGv51XQF46lc8JfglaKo3wBLuB6hF7rzl/GPcrtly0hALbJHzqkh9
# 5s37g12KbN1BK2gkgD/16KCXncgJr9eTPnlR1KuLk2p6K3uy6dbyS1/JFJiTWxe5
# Av0AIq/QcBmjm/eF+rZ6tlwpj1yRBC09nw1ZFdl2Yz/08HIO+43BMVFpyTWzQw/p
# r7AtdE5cUerfki0ftOB+zzgHwMbjYJ6Lcku1sZIAI5kVlcF7S4Enjdxp+0lHQ2/0
# 4UXULwh9j9dtgEWohVwcGk8ZDWNz4oqXNHYt3JZ3wwJgWLcdRM7JJ3kGIhZodwcr
# 9aGCF60wghepBgorBgEEAYI3AwMBMYIXmTCCF5UGCSqGSIb3DQEHAqCCF4YwgheC
# AgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFFMIIB
# QQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCBpdAqx61Cjzv4Mq5VB
# CvEZh+6gl2jOCXoND4w+ahLI5AIGaon9hnqeGBMyMDI2MDgyNzA2MjkzNS42NjNa
# MASAAgH0oIHZpIHWMIHTMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0
# ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjo2RjFBLTA1RTAtRDk0NzElMCMG
# A1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaCCEfswggcoMIIFEKAD
# AgECAhMzAAACHAlVFdfDWQfRAAEAAAIcMA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29m
# dCBUaW1lLVN0YW1wIFBDQSAyMDEwMB4XDTI1MDgxNDE4NDgzMVoXDTI2MTExMzE4
# NDgzMVowgdMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTAr
# BgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUG
# A1UECxMeblNoaWVsZCBUU1MgRVNOOjZGMUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxN
# aWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOC
# Ag8AMIICCgKCAgEAow0xEAUaFIyyLIXeFzeI8IKyBON2u0Dr02ISE5p9G5CUXfnF
# u2S0E1gWCMvDWpopX6lRxjmgnqaL3BtnWlBVTo8xUNRZu23ie4YBMAJB7Ut6mnqn
# HVwvDJxGO4TD3SnrCd+yg35B9QFejq3o4+OByvXjynaypZyukcQaLsKQvoxE8ElH
# H7zcOXEJWmU3rnXzaW/S4SH3OPhoUbTTcy6nUgKx5pRWiQ24UEPLYzcxGJjqjkz+
# GiCWGPFHDMdW86laWvmCslouQPsN2eBk8dxJcEZmW4l6p4TthoXcfexEA9YdYaMz
# 10aMhZNpdsNaDtDQUMDEC3k1D1My69MXSPlUmD9xFyDlkXiVa7BCEp3XcVtqTgzH
# Gwr28JD6oE7zEPYeuZOiuCBXTZSo/wk3tbDlsESbIPV6inYqrzxiMYqlxfCdzC3C
# imh9/NT/Lk9/aU+Iyyc9b3OaT0dZ8wgLaVDCGELRMrqyImdFHv0MudctzW/kPsV3
# Ja9ufpKWujEiN3CW//X8hFa9j5ImNeQzcMit3MoSaoGwnbiZJX1IyibIphlqccXF
# k4oTTSOQBsAUw8U0gwOnM5UJD8mBUBd65Np6NBkx2cviJ4I34GyXFCWyy5Ft1QsB
# YyVfAG3KOhCfPHQf8lQzJvLr57YW0bD/xVs4Ag4gTS6KZNyFEfX9jFdRlr0CAwEA
# AaOCAUkwggFFMB0GA1UdDgQWBBRa3mOCzB8u7zpvDh8MGKVYLCk7ZDAfBgNVHSME
# GDAWgBSfpxVdAF5iXYP05dJlpxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1l
# LVN0YW1wJTIwUENBJTIwMjAxMCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsG
# AQUFBzAChlBodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01p
# Y3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMB
# Af8EAjAAMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDAN
# BgkqhkiG9w0BAQsFAAOCAgEAklb6w/deaid3BujQCtWFBe0n9pkyRy+yyWEg70iD
# woJ5u0e0O+4GerNzdZb1zTPsHJ8EGMyo1K7ytL21+pmdFMTl19PC8OJ5Y2p+XKUQ
# y2dD+hggRMmJgDQsgbOCxHYeO+jg4t+vg61wUrovzzLkH3z0PJXXvoNuBj9Lda9C
# iNMd60451Kube99ArSf6ZMj3t0p4rFbgSazDs+8TJ+8KA5GVaYjPHj9rlMuI3Wjo
# hEc9apnQ6hMjMck3jlHZIwluVYeUQE0qjmApfMtTAEzbMUdY8sLTunL1GkbDSeKn
# 9O7llBGnNtyM1uM9Mdv1VyWh0z/IriQKIjntqqGyoF0HvDHOFZCyUDBPLflyiu7Y
# 1zQ/sPounsb96aBfQdq3h3LOn6t+m9EnNz/G6MzzWvpJk6YgTHTIqeQN/F/XpiPv
# bfek3nq/PYbL3au+kBfRUHiCFXSvt6lor0HC626vUmz9ZNPOxwEWLuccomxsy3Jw
# WH79vsM/7ARqoG5h6d6NahfaOuRP4XI9xtdH3Pa/NCLyQjxKXyLxzwQzjddkX2Ep
# TJnlypuhPmEdea59Uz2E303LxyXSnKBvGsAnyWYAfnejr3YAiL9YrN2l2dn198Rp
# A4DCm9QtZYiwC0q2fuUvui34PfPIUZByf7wHuuWu50hY9WLx1kOMI8xyo7AI6TaN
# rnIwggdxMIIFWaADAgECAhMzAAAAFcXna54Cm0mZAAAAAAAVMA0GCSqGSIb3DQEB
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
# ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjo2RjFBLTA1RTAtRDk0NzElMCMG
# A1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIa
# AxUAWmTiA01u5mxq/nVxiRJLMOskVGeggYMwgYCkfjB8MQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1T
# dGFtcCBQQ0EgMjAxMDANBgkqhkiG9w0BAQsFAAIFAO45wY8wIhgPMjAyNjA4MjYx
# OTQ4MzFaGA8yMDI2MDgyNzE5NDgzMVowdDA6BgorBgEEAYRZCgQBMSwwKjAKAgUA
# 7jnBjwIBADAHAgEAAgIVTjAHAgEAAgISQTAKAgUA7jsTDwIBADA2BgorBgEEAYRZ
# CgQCMSgwJjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0G
# CSqGSIb3DQEBCwUAA4IBAQAMXlB6rhulXfJhbX32ubzb74Oi0xbpYYZz+pgL/yMs
# 01JWjVCod6zECzaOA+bGPOvLGSe9QYOLfwqc9sIklIa7Ke7wECdL5W2y6mzpHfpd
# tSXwTbAzIuqoqaYGDvrLwUBmCmb3tnfvjqaUxnSoR6g1Q34+EVho8Q35qOVlLp7j
# tJnpbTkIxLsaIYppcDhJg35X9QormjxCqrUmdBskFhzBiDpAsP2TW3UcBaTU9SqH
# BABvtIr8a1cv+bd9DO0pqeoJ8k6Q256zYSBvWMh7+aobf6eHtAhQQZNVBl06NnPt
# C5+a4MUje0cQgTIRon9+08JWBIRIVNJ1+qdpA8EEKB+PMYIEDTCCBAkCAQEwgZMw
# fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMd
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAIcCVUV18NZB9EAAQAA
# AhwwDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRAB
# BDAvBgkqhkiG9w0BCQQxIgQgVifY2+xvQ/2nC7VavQA/1fzYB+I+iC1JP+3th48w
# fbswgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCCgIGkmNhdo7+KE7dWhI+E2
# Ctx2RLWoYvvJodCIciHHaDCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBD
# QSAyMDEwAhMzAAACHAlVFdfDWQfRAAEAAAIcMCIEIHcDs5/PWFaUJSCDKGzhm6xI
# 0EaTYRQDzURQUgMdwPZZMA0GCSqGSIb3DQEBCwUABIICAGotJJfTz9hG9y2rUHte
# RMFovc0P9rqRBgQlKjuyRG1V9DIQXOYzfUYwgsD3y2BhA10ZtvbKqLzQc3uNTIVO
# UMraQbjeXCW5niNjlvGQmr1VPMZ93G+xDBdACHkgajvz8PYUGDRHbbScB7nozEmx
# kM4d0okE7ynA6+uVtczzSasFibpD82jI6sh4s5Pdidu9AeP0pDzEy8ceFKibF5E7
# vnkYK65jxfaogshYNRr9rp5XHppQc139gPzpc0kVIj7s/2rvUBTmkQw1ULBN7qZ+
# 3pvnbFCEkrvECUq5mlO9T8neFdnoDeKsi53j4+TzaWmfmzyIWddcHOyC71NVsY5d
# QmiAaA+dwpV72r3J9MniVgWasD4lg/nYoiWIUa1amKsBXOhioQuvfAaDBFGnfMQ2
# k5yaTk8nRm4VrHmw15IcyZ7lJWALuW83xHBaeYpZooaPs4RP/vl4O9hOfHJ52yKC
# 85bAiqpp4Ik9SWaH2qHRUOWKiqzpg42pccPcEI02Z+AJ7OiCDZf3LkO9D6i4TrUE
# gR0tiP44UAS788xoleSoZqZBOsQN72ElyGRAqLknLQZAm+SoPltaQLI8tFAl5YlX
# WNETIPpkarpkcRVEnIzo6PAnEQBvnkoQWmCYs4QMGgc36ADYM9/I/+zMUZyTwr3z
# pkfKUaQtwrDpGA2aqV+STciw
# SIG # End signature block
