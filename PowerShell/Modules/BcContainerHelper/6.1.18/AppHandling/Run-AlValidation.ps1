<# 
 .Synopsis
  Run AL Validation
 .Description
  Run AL Validation
 .Parameter containerName
  Name of the validation container. Default is bcserver.
 .Parameter imageName
  If imageName is specified it will be used to build an image, which serves as a cache for faster container generation.
  Only speficy imagename if you are going to create multiple containers from the same artifacts.
 .Parameter credential
  These are the credentials used for the container. If not provided, the Run-AlValidation function will generate a random password and use that.
 .Parameter licenseFile
  License file to use for AL Validation
 .Parameter memoryLimit
  MemoryLimit is default set to 8Gb. This is fine for compiling small and medium size apps, but if your have a number of apps or your apps are large and complex, you might need to assign more memory.
 .Parameter installApps
  Array or comma separated list of 3rd party apps to install before validating apps
 .Parameter previousApps
  Array or comma separated list of previous version of apps to use for AppSourceCop validation and upgrade test
 .Parameter apps
  Array or comma separated list of apps to validate
 .Parameter ValidateVersion
  Full or partial version number. If specified, apps will also be validated against this version.
 .Parameter ValidateCurrent
  Include this switch if you want to also validate against current version of Business Central
 .Parameter ValidateNextMinor
  Include this switch if you want to also validate against next minor version of Business Central.
 .Parameter ValidateNextMajor
  Include this switch if you want to also validate against next major version of Business Central.
 .Parameter failOnError
  Include this switch if you want to fail on the first error instead of returning all errors to the caller
 .Parameter includeWarnings
  Include this switch if you want to include Warnings
 .Parameter doNotIgnoreInfos
  Include this switch if you don't want to ignore Infos (if you want to include Infos)
 .Parameter sasToken
  OBSOLETE - sasToken is no longer supported
 .Parameter countries
  Array or comma separated list of country codes to validate against
 .Parameter affixes
  Array or comma separated list of affixes to use for AppSourceCop validation
 .Parameter supportedCountries
  Array or comma separated list of supportedCountries to use for AppSourceCop validation
 .Parameter obsoleteTagMinAllowedMajorMinor
  Objects that are pending obsoletion with an obsolete tag version lower than the minimum set in the AppSourceCop.json file are not allowed. (AS0105)
 .Parameter vsixFile
  Specify a URL or path to a .vsix file in order to override the .vsix file in the image with this.
  Use Get-LatestAlLanguageExtensionUrl to get latest AL Language extension from Marketplace.
  Use Get-AlLanguageExtensionFromArtifacts -artifactUrl (Get-BCArtifactUrl -select NextMajor -accept_insiderEULA) to get latest insider .vsix
  Use . to specify that you want to use the AL Language extension from the container spun up for validation
  Default is to use the latest AL Language extension from Marketplace for non-insider containers and the Language extension in the container for insider containers
 .Parameter skipVerification
  Include this parameter to skip verification of code signing certificate. Note that you cannot request Microsoft to set this parameter when validating for AppSource.
 .Parameter skipUpgrade
  Include this parameter to skip upgrade. You can request Microsoft to set this when your previous app cannot install on the version we are validating for.
 .Parameter skipAppSourceCop
  Include this parameter to skip appSourceCop. You cannot request Microsoft to set this when running validation
 .Parameter skipConnectionTest
  Include this parameter to skip the connection test. If Connection Test fails in validation, Microsoft will execute manual validation.
 .Parameter throwOnError
  Include this switch if you want Run-AlValidation to throw an error with the validation results instead of returning them to the caller
 .Parameter useGenericImage
  Specify a private (or special) generic image to use for the Container OS.
 .Parameter multitenant
  Include this parameter to use a multitenant container for the validation tests. Default is to use single tenant as validation doesn't run tests.
 .Parameter DockerPull
  Override function parameter for docker pull
 .Parameter NewBcContainer
  Override function parameter for New-BcContainer
 .Parameter CompileAppInBcContainer
  Override function parameter for Compile-AppInBcContainer
 .Parameter GetBcContainerAppInfo
  Override function parameter for Get-BcContainerAppInfo
 .Parameter PublishBcContainerApp
  Override function parameter for Publish-BcContainerApp
 .Parameter RemoveBcContainer
  Override function parameter for Remove-BcContainer
#>
function Run-AlValidation {
Param(
    [string] $containerName = $bcContainerHelperConfig.defaultContainerName,
    [string] $imageName = "",
    [PSCredential] $credential,
    [string] $licenseFile,
    [string] $memoryLimit,
    $installApps = @(),
    $previousApps = @(),
    [Parameter(Mandatory=$true)]
    $apps,
    [string] $validateVersion = "",
    [switch] $validateCurrent,
    [switch] $validateNextMinor,
    [switch] $validateNextMajor,
    [switch] $failOnError,
    [switch] $includeWarnings,
    [switch] $doNotIgnoreInfos,
    [Obsolete("sasToken is no longer supported")]
    [string] $sasToken = "",
    [Parameter(Mandatory=$true)]
    $countries,
    $affixes = @(),
    $supportedCountries = @(),
    [string] $obsoleteTagMinAllowedMajorMinor = "",
    [string] $vsixFile = "",
    [switch] $skipVerification,
    [switch] $skipUpgrade,
    [switch] $skipAppSourceCop,
    [switch] $skipConnectionTest = $true,
    [switch] $throwOnError,
    [string] $useGenericImage = "",
    [switch] $multitenant,
    [scriptblock] $DockerPull,
    [scriptblock] $NewBcContainer,
    [scriptblock] $CompileAppInBcContainer,
    [scriptblock] $PublishBcContainerApp,
    [scriptblock] $GetBcContainerAppInfo,
    [scriptblock] $RemoveBcContainer
)

function DetermineArtifactsToUse {
    Param(
        [string] $version = "",
        [string] $select = "Current",
        [string[]] $countries = @("us"),
        [switch] $throw
    )

Write-Host -ForegroundColor Yellow @'
  _____       _                      _                         _   _  __           _       
 |  __ \     | |                    (_)                       | | (_)/ _|         | |      
 | |  | | ___| |_ ___ _ __ _ __ ___  _ _ __   ___    __ _ _ __| |_ _| |_ __ _  ___| |_ ___ 
 | |  | |/ _ \ __/ _ \ '__| '_ ` _ \| | '_ \ / _ \  / _` | '__| __| |  _/ _` |/ __| __/ __|
 | |__| |  __/ |_  __/ |  | | | | | | | | | |  __/ | (_| | |  | |_| | || (_| | (__| |_\__ \
 |_____/ \___|\__\___|_|  |_| |_| |_|_|_| |_|\___|  \__,_|_|   \__|_|_| \__,_|\___|\__|___/
                                                                                           
'@
    
    $minsto = 'bcartifacts'
    $minsel = $select
    if ($countries) {
        $minver = $null
        $countries | ForEach-Object {
            $url = Get-BCArtifactUrl -version $version -country $_ -select $select -accept_insiderEula | Select-Object -First 1
            if (!($url)) {
                Write-Host -ForegroundColor Yellow "WARNING: NextMajor artifacts doesn't exist for $_"
            }
            else {
                Write-Host "Found $($url.Split('?')[0])"
                if ($url) {
                    $ver = [Version]$url.Split('/')[4]
                    if ($minver -eq $null -or $ver -lt $minver) {
                        $minver = $ver
                        $minsto = (ReplaceCDN -sourceUrl $url.Split('/')[2] -useBlobUrl).Split('.')[0]
                        $minsel = "Latest"
                    }
                }
            }
        }
        if ($minver -eq $null) {
            if ($throw) {
                throw "Unable to locate artifacts"
            }
            return ""
        }
        else {
            $version = $minver.ToString()
        }
    }
    $artifactUrl = Get-BCArtifactUrl -storageAccount $minsto -version $version -country $countries[0] -select $minsel -accept_insiderEula | Select-Object -First 1
    if (!($artifactUrl)) {
        if ($throw) { throw "Unable to locate artifacts" }
    }
    Write-Host "Using $($artifactUrl.Split('?')[0])"
    $artifactUrl
}

function GetFilePath( [string] $path ) {
    if ($path -like "http://*" -or $path -like "https://*") {
        return $path
    }
    if (!(Test-Path $path -PathType Leaf)) {
        throw "Unable to locate app file: $path"
    }
    else {
        return (Get-Item -Path $path).FullName
    }
}

$telemetryScope = InitTelemetryScope -name $MyInvocation.InvocationName -parameterValues $PSBoundParameters -includeParameters @()
try {

'GetBcContainerAppInfo','PublishBcContainerApp','multitenant','SkipConnectionTest','skipUpgrade','ImageName','LicenseFile' | % {
    if ($PSBoundParameters.Keys.Contains($_)) {
        Write-Host -ForegroundColor Red "WARNING: Parameter $_ is no longer used in Run-AlValidation, please remove the parameter"
    }
}

if ($useGenericImage -eq "") {
    $useGenericImage = Get-BestGenericImageName -filesOnly
}

$warningsToShow = @()
$validationResult = @()

if ($memoryLimit -eq "") {
    $memoryLimit = "8G"
}

$assignPremiumPlan = $false
$tenant = "default"

if ($installApps                    -is [String]) { $installApps = @($installApps.Split(',').Trim() | Where-Object { $_ }) }
if ($previousApps                   -is [String]) { $previousApps = @($previousApps.Split(',').Trim() | Where-Object { $_ }) }
if ($apps                           -is [String]) { $apps = @($apps.Split(',').Trim()  | Where-Object { $_ }) }
if ($countries                      -is [String]) { $countries = @($countries.Split(',').Trim() | Where-Object { $_ }) }
if ($affixes                        -is [String]) { $affixes = @($affixes.Split(',').Trim() | Where-Object { $_ }) }
if ($supportedCountries             -is [String]) { $supportedCountries = @($supportedCountries.Split(',').Trim() | Where-Object { $_ }) }

$installApps = @($installApps | ForEach-Object { GetFilePath $_ })
$previousApps = @($previousApps | ForEach-Object { GetFilePath $_ })
$apps = @($apps | ForEach-Object { GetFilePath $_ })

$countries = @($countries | Where-Object { $_ } | ForEach-Object { getCountryCode -countryCode $_ })
$validateCountries = @($countries | ForEach-Object {
    $countryCode = $_
    if ($bcContainerHelperConfig.mapCountryCode.PSObject.Properties.Name -eq $countryCode) { 
        $bcContainerHelperConfig.mapCountryCode."$countryCode"
    }
    else {
        $countryCode
    }
} | Select-Object -Unique)
$supportedCountries = @($supportedCountries | Where-Object { $_ } | ForEach-Object { getCountryCode -countryCode $_ })

$latestAlLanguageUrl = Get-LatestAlLanguageExtensionUrl

Write-Host -ForegroundColor Yellow @'
  _____                               _                
 |  __ \                             | |               
 | |__) |_ _ _ __ __ _ _ __ ___   ___| |_ ___ _ __ ___ 
 |  ___/ _` | '__/ _` | '_ ` _ \ / _ \ __/ _ \ '__/ __|
 | |  | (_| | | | (_| | | | | | |  __/ |_  __/ |  \__ \
 |_|   \__,_|_|  \__,_|_| |_| |_|\___|\__\___|_|  |___/

'@
Write-Host -NoNewLine -ForegroundColor Yellow "Container name                  "; Write-Host $containerName
Write-Host -NoNewLine -ForegroundColor Yellow "Credential                      ";
if ($credential) {
    Write-Host "Specified"
}
else {
    $password = GetRandomPassword
    Write-Host "admin/$password"
    $credential= (New-Object pscredential 'admin', (ConvertTo-SecureString -String $password -AsPlainText -Force))
}
Write-Host -NoNewLine -ForegroundColor Yellow "MemoryLimit                     "; Write-Host $memoryLimit
Write-Host -NoNewLine -ForegroundColor Yellow "validateVersion                 "; Write-Host $validateVersion
Write-Host -NoNewLine -ForegroundColor Yellow "validateCurrent                 "; Write-Host $validateCurrent
Write-Host -NoNewLine -ForegroundColor Yellow "validateNextMinor               "; Write-Host $validateNextMinor
Write-Host -NoNewLine -ForegroundColor Yellow "validateNextMajor               "; Write-Host $validateNextMajor
Write-Host -NoNewLine -ForegroundColor Yellow "countries                       "; Write-Host ([string]::Join(',',$countries))
Write-Host -NoNewLine -ForegroundColor Yellow "validateCountries               "; Write-Host ([string]::Join(',',$validateCountries))
Write-Host -NoNewLine -ForegroundColor Yellow "affixes                         "; Write-Host ([string]::Join(',',$affixes))
Write-Host -NoNewLine -ForegroundColor Yellow "supportedCountries              "; Write-Host ([string]::Join(',',$supportedCountries))
Write-Host -NoNewLine -ForegroundColor Yellow "ObsoleteTagMinAllowedMajorMinor "; Write-Host $obsoleteTagMinAllowedMajorMinor
Write-Host -NoNewLine -ForegroundColor Yellow "vsixFile                        "; Write-Host $vsixFile

Write-Host -ForegroundColor Yellow "Install Apps"
if ($installApps) { $installApps | ForEach-Object { Write-Host "- $_" } } else { Write-Host "- None" }
Write-Host -ForegroundColor Yellow "Previous Apps"
if ($previousApps) { $previousApps | ForEach-Object { Write-Host "- $_" } } else { Write-Host "- None" }
Write-Host -ForegroundColor Yellow "Apps"
if ($apps) { $apps | ForEach-Object { Write-Host "- $_" } }  else { Write-Host "- None" }

if ($DockerPull) {
    Write-Host -ForegroundColor Yellow "DockerPull override"; Write-Host $DockerPull.ToString()
}
else {
    $DockerPull = { Param($imageName) docker pull $imageName --quiet }
}
if ($NewBcContainer) {
    Write-Host -ForegroundColor Yellow "NewBccontainer override"; Write-Host $NewBcContainer.ToString()
}
else {
    $NewBcContainer = { Param([Hashtable]$parameters) New-BcContainer @parameters; Invoke-ScriptInBcContainer $parameters.ContainerName -scriptblock { $progressPreference = 'SilentlyContinue' } }
}
if ($CompileAppInBcContainer) {
    Write-Host -ForegroundColor Yellow "CompileAppInBcContainer override"; Write-Host $CompileAppInBcContainer.ToString()
}
if ($RemoveBcContainer) {
    Write-Host -ForegroundColor Yellow "RemoveBcContainer override"; Write-Host $RemoveBcContainer.ToString()
}
else {
    $RemoveBcContainer = { Param([Hashtable]$parameters) Remove-BcContainer @parameters }
}

$vsixFile = DetermineVsixFile -vsixFile $vsixFile

$currentArtifactUrl = ""

if ("$validateVersion" -eq "" -and !$validateCurrent -and !$validateNextMinor -and !$validateNextMajor) {
$currentArtifactUrl = DetermineArtifactsToUse -countries $validateCountries -select Current
Write-Host -ForegroundColor Yellow @'
  _____       _                      _       _                   _                           _                       
 |  __ \     | |                    (_)     (_)                 | |                         | |                      
 | |  | | ___| |_ ___ _ __ _ __ ___  _ _ __  _ _ __   __ _    __| | ___ _ __   ___ _ __   __| | ___ _ __   ___ _   _ 
 | |  | |/ _ \ __/ _ \ '__| '_ ` _ \| | '_ \| | '_ \ / _` |  / _` |/ _ \ '_ \ / _ \ '_ \ / _` |/ _ \ '_ \ / __| | | |
 | |__| |  __/ |_  __/ |  | | | | | | | | | | | | | | (_| | | (_| |  __/ |_) |  __/ | | | (_| |  __/ | | | (__| |_| |
 |_____/ \___|\__\___|_|  |_| |_| |_|_|_| |_|_|_| |_|\__, |  \__,_|\___| .__/ \___|_| |_|\__,_|\___|_| |_|\___|\__, |
                                                      __/ |            | |                                      __/ |
                                                     |___/             |_|                                     |___/ 
'@

$validateCurrent = $true
$version = [System.Version]::new($currentArtifactUrl.Split('/')[4])
$currentVersion = "$($version.Major).$($version.Minor)"
$validateVersion = "17.0"

$tmpAppsFolder = Join-Path $bcContainerHelperConfig.hostHelperFolder ([Guid]::NewGuid().ToString())
@(CopyAppFilesToFolder -appFiles @($installApps+$apps) -folder $tmpAppsFolder) | % {
    $appFile = $_
    $version = GetApplicationDependency -appFile $appFile -minVersion $validateVersion
    if ([System.Version]$version -gt [System.Version]$validateVersion) {
        $version = [System.Version]::new($version)
        $validateVersion = "$($version.Major).$($version.Minor)"
    }
}
Remove-Item -Path $tmpAppsFolder -Recurse -Force
Write-Host "Validating against Current Version ($currentVersion)"
if ($validateVersion -eq $currentVersion) {
    $validateVersion = ""
}
else {
    Write-Host "Additionally validating against application dependency ($validateVersion)"
}
}

Measure-Command {

Write-Host -ForegroundColor Yellow @'

  _____       _ _ _                                          _        _                            
 |  __ \     | | (_)                                        (_)      (_)                           
 | |__) |   _| | |_ _ __   __ _    __ _  ___ _ __   ___ _ __ _  ___   _ _ __ ___   __ _  __ _  ___ 
 |  ___/ | | | | | | '_ \ / _` |  / _` |/ _ \ '_ \ / _ \ '__| |/ __| | | '_ ` _ \ / _` |/ _` |/ _ \
 | |   | |_| | | | | | | | (_| | | (_| |  __/ | | |  __/ |  | | (__  | | | | | | | (_| | (_| |  __/
 |_|    \__,_|_|_|_|_| |_|\__, |  \__, |\___|_| |_|\___|_|  |_|\___| |_|_| |_| |_|\__,_|\__, |\___|
                           __/ |   __/ |                                                 __/ |     
                          |___/   |___/                                                 |___/      

'@

Write-Host "Pulling $useGenericImage"

Invoke-Command -ScriptBlock $DockerPull -ArgumentList $useGenericImage
} | ForEach-Object { Write-Host -ForegroundColor Yellow "`nPulling generic image took $([int]$_.TotalSeconds) seconds" }

Measure-Command {

0..3 | ForEach-Object {

$artifactUrl = ""
$useVsix = ""
if ($_ -eq 0 -and $validateCurrent) {
    if ($currentArtifactUrl -eq "") {
        $currentArtifactUrl = DetermineArtifactsToUse -countries $validateCountries -select Current -throw
    }
    $artifactUrl = $currentArtifactUrl
    if ($vsixFile) {
        if ($vsixFile -ne ".") { $useVsix = $vsixFile }
    }
    else {
        $useVsix = $latestAlLanguageUrl
    }
}
elseif ($_ -eq 1 -and $validateVersion) {
    $artifactUrl = DetermineArtifactsToUse -version $validateVersion -countries $validateCountries -select Latest
}
elseif ($_ -eq 2 -and $validateNextMinor) {
    $artifactUrl = DetermineArtifactsToUse -countries $validateCountries -select NextMinor
}
elseif ($_ -eq 3 -and $validateNextMajor) {
    $artifactUrl = DetermineArtifactsToUse -countries $validateCountries -select NextMajor
}

if ($artifactUrl) {

$prevProgressPreference = $progressPreference
$progressPreference = 'SilentlyContinue'

$appPackagesFolder = Join-Path $bcContainerHelperConfig.hostHelperFolder ([Guid]::NewGuid().ToString())
New-Item $appPackagesFolder -ItemType Directory | Out-Null

try {

$validateCountries | % {
$validateCountry = $_

Write-Host -ForegroundColor Yellow @'

   _____                _   _                               _        _                 
  / ____|              | | (_)                             | |      (_)                
 | |     _ __ ___  __ _| |_ _ _ __   __ _    ___ ___  _ __ | |_ __ _ _ _ __   ___ _ __ 
 | |    | '__/ _ \/ _` | __| | '_ \ / _` |  / __/ _ \| '_ \| __/ _` | | '_ \ / _ \ '__|
 | |____| | |  __/ (_| | |_| | | | | (_| | | (__ (_) | | | | |_ (_| | | | | |  __/ |   
  \_____|_|  \___|\__,_|\__|_|_| |_|\__, |  \___\___/|_| |_|\__\__,_|_|_| |_|\___|_|   
                                     __/ |                                             
                                    |___/                                              

'@

Measure-Command {

    $artifactSegments = $artifactUrl.Split('?')[0].Split('/')
    $artifactUrl = $artifactUrl.Replace("/$($artifactSegments[4])/$($artifactSegments[5])","/$($artifactSegments[4])/$validateCountry")
    Write-Host -ForegroundColor Yellow "Creating container for country $validateCountry"

    $Parameters = @{
        "accept_eula" = $true
        "accept_insiderEula" = $true
        "containerName" = $containerName
        "artifactUrl" = $artifactUrl
        "useGenericImage" = $useGenericImage
        "Credential" = $credential
        "auth" = 'UserPassword'
        "updateHosts" = $true
        "vsixFile" = $useVsix
        "EnableTaskScheduler" = $true
        "AssignPremiumPlan" = $assignPremiumPlan
        "MemoryLimit" = $memoryLimit
        "FilesOnly" = $true
    }

    Invoke-Command -ScriptBlock $NewBcContainer -ArgumentList $Parameters

} | ForEach-Object { Write-Host -ForegroundColor Yellow "`nCreating container took $([int]$_.TotalSeconds) seconds" }

if ($installApps) {
    CopyAppFilesToFolder -appFiles $installApps -folder $appPackagesFolder | Out-Null
}

if (!$skipAppSourceCop) {
Write-Host -ForegroundColor Yellow @'
  _____                   _                                    _____                           _____            
 |  __ \                 (_)                 /\               / ____|                         / ____|           
 | |__) |   _ _ __  _ __  _ _ __   __ _     /  \   _ __  _ __| (___   ___  _   _ _ __ ___ ___| |     ___  _ __  
 |  _  / | | | '_ \| '_ \| | '_ \ / _` |   / /\ \ | '_ \| '_ \\___ \ / _ \| | | | '__/ __/ _ \ |    / _ \| '_ \ 
 | | \ \ |_| | | | | | | | | | | | (_| |  / ____ \| |_) | |_) |___) | (_) | |_| | | | (__  __/ |____ (_) | |_) |
 |_|  \_\__,_|_| |_|_| |_|_|_| |_|\__, | /_/    \_\ .__/| .__/_____/ \___/ \__,_|_|  \___\___|\_____\___/| .__/ 
                                   __/ |          | |   | |                                              | |    
                                  |___/           |_|   |_|                                              |_|    
'@
Measure-Command {
$parameters = @{
    "containerName" = $containerName
    "credential" = $credential
    "previousApps" = @($previousApps)
    "apps" = @($apps)
    "affixes" = $affixes
    "supportedCountries" = $supportedCountries
    "ObsoleteTagMinAllowedMajorMinor" = $ObsoleteTagMinAllowedMajorMinor
    "enableAppSourceCop" = $true
    "failOnError" = $failOnError
    "ignoreWarnings" = !$includeWarnings
    "doNotIgnoreInfos" = $doNotIgnoreInfos
    "appPackagesFolder" = $appPackagesFolder
    "skipVerification" = $skipVerification
}
if ($CompileAppInBcContainer) {
    $parameters += @{
        "CompileAppInBcContainer" = $CompileAppInBcContainer
    }
}
$validationResult += @(Run-AlCops @Parameters)

} | ForEach-Object { Write-Host -ForegroundColor Yellow "`nRunning AppSourceCop took $([int]$_.TotalSeconds) seconds" }

}

}

} catch {
    $err = "Unexpected error while validating app. Error is: $($_.Exception.Message)"
    $validationResult += $err
    Write-Host -ForegroundColor Red $err
    Write-Host -ForegroundColor Red $_.ScriptStackTrace

}
finally {
    $progressPreference = $prevProgressPreference
    Remove-Item -Path $appPackagesFolder -Recurse -Force
}

Write-Host -ForegroundColor Yellow @'

  _____                           _                _____            _        _                 
 |  __ \                         (_)              / ____|          | |      (_)                
 | |__) |___ _ __ ___   _____   ___ _ __   __ _  | |     ___  _ __ | |_ __ _ _ _ __   ___ _ __ 
 |  _  // _ \ '_ ` _ \ / _ \ \ / / | '_ \ / _` | | |    / _ \| '_ \| __/ _` | | '_ \ / _ \ '__|
 | | \ \  __/ | | | | | (_) \ V /| | | | | (_| | | |____ (_) | | | | |_ (_| | | | | |  __/ |   
 |_|  \_\___|_| |_| |_|\___/ \_/ |_|_| |_|\__, |  \_____\___/|_| |_|\__\__,_|_|_| |_|\___|_|   
                                           __/ |                                               
                                          |___/                                                

'@
Measure-Command {

    $Parameters = @{
        "containerName" = $containerName
    }
    Invoke-Command -ScriptBlock $RemoveBcContainer -ArgumentList $Parameters
   
} | ForEach-Object { Write-Host -ForegroundColor Yellow "`nRemoving container took $([int]$_.TotalSeconds) seconds" }

}

}

} | ForEach-Object { Write-Host -ForegroundColor Yellow "`nAL Validation finished in $([int]$_.TotalSeconds) seconds" }

if ($validationResult) {

Write-Host -ForegroundColor Red @'
 __      __   _ _     _       _   _               _____                _ _       
 \ \    / /  | (_)   | |     | | (_)             |  __ \              | | |      
  \ \  / /_ _| |_  __| | __ _| |_ _  ___  _ __   | |__) |___ ___ _   _| | |_ ___ 
   \ \/ / _` | | |/ _` |/ _` | __| |/ _ \| '_ \  |  _  // _ \ __| | | | | __/ __|
    \  / (_| | | | (_| | (_| | |_| | (_) | | | | | | \ \  __\__ \ |_| | | |_\__ \
     \/ \__,_|_|_|\__,_|\__,_|\__|_|\___/|_| |_| |_|  \_\___|___/\__,_|_|\__|___/

'@
$validationResult | Write-Host -ForegroundColor Red
Write-Host -ForegroundColor Red @'
  _____                          ___      __   _ _     _       _   _               ______    _ _                
 |  __ \                   /\   | \ \    / /  | (_)   | |     | | (_)             |  ____|  (_) |               
 | |__) |   _ _ __ ______ /  \  | |\ \  / /_ _| |_  __| | __ _| |_ _  ___  _ __   | |__ __ _ _| |_   _ _ __ ___ 
 |  _  / | | | '_ \______/ /\ \ | | \ \/ / _` | | |/ _` |/ _` | __| |/ _ \| '_ \  |  __/ _` | | | | | | '__/ _ \
 | | \ \ |_| | | | |    / ____ \| |  \  / (_| | | | (_| | (_| | |_| | (_) | | | | | | | (_| | | | |_| | | |  __/
 |_|  \_\__,_|_| |_|   /_/    \_\_|   \/ \__,_|_|_|\__,_|\__,_|\__|_|\___/|_| |_| |_|  \__,_|_|_|\__,_|_|  \___|

'@

AddTelemetryProperty -telemetryScope $telemetryScope -key "Validation" -value "Failure"
AddTelemetryProperty -telemetryScope $telemetryScope -key "Result" -value ($validationResult -join "`n")
if ($throwOnError) {
    throw ($validationResult -join "`n")
}
else {
    $validationResult
}

}
else {
Write-Host -ForegroundColor Green @'
  _____                          ___      __   _ _     _       _   _                _____                            
 |  __ \                   /\   | \ \    / /  | (_)   | |     | | (_)              / ____|                           
 | |__) |   _ _ __ ______ /  \  | |\ \  / /_ _| |_  __| | __ _| |_ _  ___  _ __   | (___  _   _  ___ ___ ___ ___ ___ 
 |  _  / | | | '_ \______/ /\ \ | | \ \/ / _` | | |/ _` |/ _` | __| |/ _ \| '_ \   \___ \| | | |/ __/ __/ _ \ __/ __|
 | | \ \ |_| | | | |    / ____ \| |  \  / (_| | | | (_| | (_| | |_| | (_) | | | |  ____) | |_| | (__ (__  __\__ \__ \
 |_|  \_\__,_|_| |_|   /_/    \_\_|   \/ \__,_|_|_|\__,_|\__,_|\__|_|\___/|_| |_| |_____/ \__,_|\___\___\___|___/___/
                                                                                                  
'@

AddTelemetryProperty -telemetryScope $telemetryScope -key "Validation" -value "Success"
}

if ($warningsToShow) {
    ($warningsToShow -join "`n") | Write-Host -ForegroundColor Yellow
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
Export-ModuleMember -Function Run-AlValidation

# SIG # Begin signature block
# MIInSQYJKoZIhvcNAQcCoIInOjCCJzYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCC5JtF02EbeLAgO
# EstRYO+9qrAXr/+0PVWy20NlsBjV7KCCDLowggX1MIID3aADAgECAhMzAAACHU0Z
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
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIALbCmvv
# uH4B+nFjf2vFd1dsJKZh/7HrqNY09luWz44yMEIGCisGAQQBgjcCAQwxNDAyoBSA
# EgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20w
# DQYJKoZIhvcNAQEBBQAEggEAEyJA2Gh02rPa10l0MRsnWresrbiQOt7APQGx2dSF
# LHIzL5WFFco3TPxkTucZ4bDdYXTuZeig6C144LWb22YwbLvLcu7/HYerYpK0haCN
# Go2wshr2N2U+9LDm9Ag02k8G8JYOj2q9iSvaFU/M06gCcJ7Zn39gNk9qgQyoKOxy
# Ga3kQuKyAPz65I6Luf/88MAo3jCyX7mStVeC+GHv3stDfObc07C4ana4rffHGgFO
# zi9Xz9uyE0RTg1aq0ikwGYXfOYSk18Nd6qLWI0Bp3lyY+YuEtfnMQl2qv+JONwfS
# KYbdU9VoY6/zlR39bGbMvmaJ8Rz55vhx+bMTyfoaZJTq1qGCF5cwgheTBgorBgEE
# AYI3AwMBMYIXgzCCF38GCSqGSIb3DQEHAqCCF3AwghdsAgEDMQ8wDQYJYIZIAWUD
# BAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGEWQoD
# ATAxMA0GCWCGSAFlAwQCAQUABCDvyz/lTK0JcisdK0KKy6ubWsDi7Pb/emq/sltY
# CLtKhAIGaoSS9arPGBMyMDI2MDgyNzA2MjkzNi41NzJaMASAAgH0oIHRpIHOMIHL
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxN
# aWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRT
# UyBFU046QTAwMC0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFNlcnZpY2WgghHtMIIHIDCCBQigAwIBAgITMwAAAiu7AFD/TTuaoQABAAAC
# KzANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAe
# Fw0yNjAyMTkxOTQwMTFaFw0yNzA1MTcxOTQwMTFaMIHLMQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmlj
# YSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046QTAwMC0wNUUw
# LUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIi
# MA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCX3mi6OD3syUqQm4QqgkrKPbcs
# K/Qx3fYctL8+VM1uOY3booi5GxwauTgQf6JFHITToxS7gjqKlK8OFLzL6UTl0jxE
# K5t6DuOcgJXdvutimoTlOS0C3kyITXBAXoj/gp6hRR9z6WRip1Ktkilb3dJXCjQq
# T9P2Cuujr+Vz8r+Z+jDl09ji/ic/4G34r3mVwjs//Gnx9Pu31V8rXFicNiAzxpub
# awpbd8pqfzlWT2vnG3kF9l6MiREbvJ3XHLUwHQsh0t/TrSFx/s/yCqpJWYJ6oClG
# 70tvsFH0aRP8wB4cP/CFa2ILvk26i3OcJBl+pqKjHTSBy9mvwTPEDlnzco0Nt8R6
# pSPTXZgBsscHhoKfC0WQmOzY2keXbAmRTcZMyXz5v/AJbmoI0y07Bazvt5NkXddG
# 9TErQWwtsFyIKrElDgWfHeCoTu1wu2ciD3dK72z3ca2gzoEDxT2j9BXIUKaiTzTd
# QPRsAMaO3dU0zaGwMMlwtSJyDh14YEgZoUu5vS8MugMqdrNjphyL65yKhjpAWbhY
# kIHO/0uZju95tP8zZNqXIRh4tdfWHJPATn9r+cxkyuh2x0VLdfx1lmK9X3NjH0Nt
# gAs5JB/wOlkyuudxmFTfWVyRrL37ispOZ8aPAFgvyR6cNTkGpkFo35JRjciNmZiU
# 4qT9Uty+V5gudFk1jwIDAQABo4IBSTCCAUUwHQYDVR0OBBYEFD4WjuQTUJbtbd3j
# mvZku0FZ2eU2MB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1Ud
# HwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3Js
# L01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggr
# BgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNv
# bS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIw
# MTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgw
# DgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUAA4ICAQDO/CKsciEM8kr1fqH4
# TlfT66ENoTjxXw810pyEq0PdrgLwfgT3x+1gz7CQHtUdevqMQ5qHyDLhm6pT911C
# YkGN+6g+MU7fMYTr6d3SxieJwBIoWkfR4g7SitGzMKU465KEYejfddoUgovC/xcR
# paALO5p3/A248ByhJiMttBQNDtsT/HaCFwRFCURby/f8c1kky8F8xkCXFz+/MtZ5
# d1lWFjwOI2geZHWq9XihDOgee5nS2koo5V6n8XG220UTevVf+pgmpIH71XKDVIYT
# GGZJs6yPlfJ2aXqw1ME4NR6okNsY3P1M31H6DMYRfJGNBNep595kXGh3YzA3cCiy
# g+jmJ58h/fTvjngIpuUFfODpDjFx0ic1YoLANxhCF3RhS9qYM7K40NEhKshYuaAk
# IG2XBKYig3r/0/b0sjvjBws55AYonMm3A8qcX/6k9Vfc0mv9dtonHuWGfA2b+qE2
# qpCnhzGbdDHq7iOSZEw01nNupAMf1c41k9IoTQ2z3iw6w4ZZoLOyg4TKMbp1krpT
# 4trip/y30Cv5khyqCDNqaXQpBkOYON8LgtoQ3amVOX7ix5jdrnx/vUxTUSigXvrW
# dL7Uk8kpmS0zto2Toy7aT5oBzCTvfj9iJ/BN/E1vhFBkhJCvZ7PVvsMSnTTmkx2F
# al2lVkztuAI44fD/uyLJdaMQSzCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkA
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
# T3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOkEwMDAtMDVFMC1E
# OTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEw
# BwYFKw4DAhoDFQAJrD90ykHpo/0AGb7lmwvsCtqROaCBgzCBgKR+MHwxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29m
# dCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBCwUAAgUA7jpEzzAiGA8y
# MDI2MDgyNzA1MDgzMVoYDzIwMjYwODI4MDUwODMxWjB3MD0GCisGAQQBhFkKBAEx
# LzAtMAoCBQDuOkTPAgEAMAoCAQACAgViAgH/MAcCAQACAhKRMAoCBQDuO5ZPAgEA
# MDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAI
# AgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBAA3gPX0/PBc8/0CVxjljfurwnCYA
# oJ7HVEyMGqBGRbYlGmx9mz+y2w2HEw07pDznusdpGBX0gq6qkxkUN53IFinvZgn5
# JM5MZrR24hnXWMzn3v1fCDmZ9D36W1fJIM/r8SkvNev2i+lJn6W5+GvWZRe0rNJx
# VW11NlML3mghte1h/QKUakBK3BB/RNP3XL87tYhCNeGWqP01aFcbSqJigpIUX76D
# YQ0Iwu0M6GrgAIlB+4WeCxwZyrsw8Bgo2oAvdZGDogjI+qqNKeZ+BbiCtjO2XiRv
# pyDdFDoJTwJP0W9AcZA/VXtqeD3myMoi3rvD8yltg79j3U8qdFqygw8G+LoxggQN
# MIIECQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQ
# MA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
# MSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAiu7
# AFD/TTuaoQABAAACKzANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0G
# CyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCB2QC39BpoV02vQyoUILV3sj9QJ
# ceiMAxGBDBEpuuMGSjCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EIHIOI/Q/
# kFftYA+M2OY+1Bx3ajBD6/WDAtPT2vFkv25SMIGYMIGApH4wfDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgUENBIDIwMTACEzMAAAIruwBQ/007mqEAAQAAAiswIgQgiNCWem7F
# TV2uF7kJIU90/NKjrdXqGBA1ZB7V9WXfluUwDQYJKoZIhvcNAQELBQAEggIAVgc/
# Uk047t9tZFsZU34bMV1S3uN7p4UV+5C7b6XwG/ndYcnUuWAeZ5t5aZKVxOPscgXv
# GJaUxtSMdArhFIstHcqnctSwTzAv6lH33myN5I4NE4MWawRG4uT5HfpINqdPfgmI
# WWqmGcCGXZyyr+OFFsaz/GLnudV143GZNsFW1gkVwSPPdtr2v+YJqyTPfIYH3u/z
# MT1ZPlCPIqGRc0Wv4U+GbdeLuN3lBIIwLi0jwwlW+qnZebEfn6B2USXZYyxvKUa3
# JPXxjZE3dHKiR1FfdHB/RHkz47CO24Thn7E0ejVBGu7TmVhvNtsdfIJytJDl2Gku
# dxHvUfCZiXbF5/sgyg4rBfP2qeLqmF7xh9zjvlwJQZCzOJs0OVq0XW/Hze5DYMK3
# HdiKHyjhGqpeYwLbgavctSl9Fz4kPg5cUIN9F2abmm7mnr9lv3xjn7WGuqajtpyI
# utTXHcdoSW2T+SCvZLNMv7BnbZTXJ5U87np2QJhliMEVWkSaQ4Ox+8CJRkhimfYg
# GkfQwrPEM+dHR3n1VCm3vKTXu6j8S2aXnUUvCeWqAA+/HYfeqaCIKll6kkG81eOb
# a5LXdfjUVXAUgMjh/q3/ULZUxfup17a07rH0NNIfNdKoKyahL8/rxXzEHyJjFdhm
# WXTN+y1yP7oZNy2wYAJyBYlf1twCM3YpmXL/H48=
# SIG # End signature block
