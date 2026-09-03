<# 
 .Synopsis
  Create or refresh a NAV/BC Container
 .Description
  Creates a new Container based on a Docker Image
  Adds shortcut on the desktop for Web Client and Container PowerShell prompt
 .Parameter accept_eula
  Switch, which you need to specify if you accept the eula for running NAV or Business Central on Docker containers (See https://go.microsoft.com/fwlink/?linkid=861843)
 .Parameter accept_insiderEula
  Switch, which you need to specify if you are going to create a container with an insider build of Business Central on Docker containers (See https://go.microsoft.com/fwlink/?linkid=2245051)
 .Parameter accept_outdated
  Specify accept_outdated to ignore error when running containers which are older than 90 days
 .Parameter containerName
  Name of the new Container (if the container already exists it will be replaced)
 .Parameter imageName
  Name of the image you want to use for your Container
 .Parameter artifactUrl
  Url for application artifact to use. If you also specify an ImageName, an image will be build (if it doesn't exist) using these artifacts and that will be run.
 .Parameter platformArtifactUrl
  Url for platform artifact to use. Use this when you want to use a different platform than the one related to artifactUrl.
 .Parameter dvdPath
  When you are spinning up a Generic image, you need to specify the DVD path
 .Parameter dvdCountry
  When you are spinning up a Generic image, you need to specify the country version (w1, dk, etc.) (default is w1)
 .Parameter dvdVersion
  When you are spinning up a Generic image, you can specify the version (default is the version of the executables)
 .Parameter dvdPlatform
  When you are spinning up a Generic image, you can specify the platform version (default is the version of the executables)
 .Parameter locale
  Optional locale for the container. Default is to deduct the locale from the country version of the container.
 .Parameter setServiceTierUserLocale
  Include this switch if you want to set the locale for the Service Tier User (NT AUTHORITY\SYSTEM)
 .Parameter licenseFile
  Path or Secure Url of the licenseFile you want to use
 .Parameter credential
  Username and Password for the Container
 .Parameter AuthenticationEmail
  AuthenticationEmail of the admin user
 .Parameter memoryLimit
  Memory limit for the container (default is unlimited for process isolation and 8G for HyperV isolation containers)
 .Parameter sqlMemoryLimit
  Memory limit for the SQL inside the container (default is no limit)
  Value can be specified as 50%, 1.5G, 1500M
 .Parameter isolation
  Isolation mode for the container (default is process isolation if host and container OS match)
 .Parameter databaseServer
  Name of database server when using external SQL Server (omit if using database inside the container)
 .Parameter databaseInstance
  Name of database instance when using external SQL Server (omit if using database inside the container)
 .Parameter databasePrefix
  Prefix of databases when using external SQL Server (omit if using database inside the container)
 .Parameter databaseName
  Name of database to connect to when using external SQL Server (omit if using database inside the container)
 .Parameter replaceExternalDatabases
  Include this switch to allow New-BcContainer to create/replace databases on the external SQL Server.
  This parameter is ignored unless databaseServer, databasePrefix and databaseName is specified
  This parameter uses Remove-BcDatabase and Restore-BcDatabaseFromArtifacts to remove and create the databases
  Access to the SQL Server on the host must be Windows Authentication
 .Parameter bakFile
  Path or Secure Url of a bakFile if you want to restore a database in the container
 .Parameter bakFolder
  A folder in which a backup of the database(s) will be placed after the container has been created and initialized
  If the folder already exists, then the database(s) in this folder will be restored and used.
 .Parameter databaseCredential
  Credentials for the database connection when using external SQL Server (omit if using database inside the container)
 .Parameter shortcuts
  Location where the Shortcuts will be placed. Can be either None, Desktop or StartMenu
 .Parameter updateHosts
  Include this switch if you want to update the hosts file with the IP address of the container
 .Parameter useSSL
  Include this switch if you want to use SSL (https) with a self-signed certificate
 .Parameter installCertificateOnHost
  Include this switch if you want to use SSL (https) with a self-signed certificate
 .Parameter includeCSide
  Include this switch if you want to have Windows Client and CSide development environment available on the host. This switch will also export all objects as txt for object handling functions unless doNotExportObjectsAsText is set.
 .Parameter includeAL
  Include this switch if you want to have all objects exported as al for code merging and comparing functions unless doNotExportObjectsAsText is set.
 .Parameter enableSymbolLoading
  Include this switch if you want to do development in both CSide and VS Code to have symbols automatically generated for your changes in CSide
 .Parameter enableTaskScheduler
  Include this switch if you want to do Enable the Task Scheduler
 .Parameter doNotExportObjectsToText
  Avoid exporting objects for baseline from the container (Saves time, but you will not be able to use the object handling functions without the baseline)
 .Parameter alwaysPull
  Always pull latest version of the docker image
 .Parameter forceRebuild
  Force a rebuild of the cached image even if the generic image or os hasn't changed
 .Parameter useBestContainerOS
  Use the best Container OS based on the Host OS. If the OS doesn't match, a better public generic image is selected.
 .Parameter useGenericImage
  Specify a private (or special) generic image to use for the Container OS.
 .Parameter assignPremiumPlan
  Assign Premium plan to admin user
 .Parameter filesOnly
  Include this switch to create a filesOnly container. A filesOnly container does not contain SQL Server, IIS or the ServiceTier, it only contains the files from BC in the same locations as a normal container.
  A FilesOnly container can be used to compile apps and it can be used as a proxy container for an online Business Central environment
 .Parameter multitenant
  Setup container for multitenancy by adding this switch
 .Parameter addFontsFromPath
  Enumerate all fonts from this path or array of paths and install them in the container
 .Parameter featureKeys
  Optional hashtable of featureKeys, which can be applied to the container database
 .Parameter clickonce
  Specify the clickonce switch if you want to have a clickonce version of the Windows Client created
 .Parameter includeTestToolkit
  Specify this parameter to add the test toolkit and the standard tests to the container
 .Parameter includeTestLibrariesOnly
  Specify this parameter to avoid including the standard tests when adding includeTestToolkit
 .Parameter includeTestFrameworkOnly
  Only import TestFramework (do not import Test Codeunits nor TestLibraries)
 .Parameter includePerformanceToolkit
  Include the performance toolkit app (only 17.x and later)
 .Parameter restart
  Define the restart option for the container
 .Parameter auth
  Set auth to Windows, NavUserPassword or AAD depending on which authentication mechanism your container should use
 .Parameter timeout
  Specify the number of seconds to wait for activity. Default is 1800 (30 min.). -1 means wait forever.
 .Parameter additionalParameters
  This allows you to transfer an additional number of parameters to the docker run
 .Parameter myscripts
  This allows you to specify a number of scripts you want to copy to the c:\run\my folder in the container (override functionality)
 .Parameter TimeZoneId
  This parameter specifies the timezone in which you want to start the Container.
 .Parameter WebClientPort
  Use this parameter to specify which port to use for the WebClient. Default is 80 if http and 443 if https.
 .Parameter FileSharePort
  Use this parameter to specify which port to use for the File Share. Default is 8080.
 .Parameter ManagementServicesPort
  Use this parameter to specify which port to use for Management Services. Default is 7045.
 .Parameter ClientServicesPort
  Use this parameter to specify which port to use for Client Services. Default is 7046.
 .Parameter SoapServicesPort
  Use this parameter to specify which port to use for Soap Web Services. Default is 7047.
 .Parameter ODataServicesPort
  Use this parameter to specify which port to use for OData Web Services. Default is 7048.
 .Parameter DeveloperServicesPort
  Use this parameter to specify which port to use for Developer Services. Default is 7049.
 .Parameter PublishPorts
  Use this parameter to specify the ports you want to publish on the host. Default is to NOT publish any ports.
  This parameter is necessary if you want to be able to connect to the container from outside the host.
 .Parameter PublicDnsName
  Use this parameter to specify which public dns name is pointing to this container.
  This parameter is necessary if you want to be able to connect to the container from outside the host.
 .Parameter network
  Use this parameter to override the default network settings in the container (corresponds to --network on docker run)
 .Parameter macAddress
  Use this parameter to override the default mac-address settings in the container (corresponds to --mac-address on docker run)
 .Parameter IP
  Use this parameter to override the default mac-address settings in the container (corresponds to --ip on docker run)
 .Parameter hostIP
  Use this parameter to set the default host IP address in the container
 .Parameter dns
  Use this parameter to override the default dns settings in the container (corresponds to --dns on docker run)
 .Parameter runTxt2AlInContainer
  Specify a foreign container in which you want to run the txt2al tool when using -includeAL
 .Parameter useTraefik
  Set the necessary options to make the container work behind a traefik proxy as explained here https://www.axians-infoma.com/techblog/running-multiple-nav-bc-containers-on-an-azure-vm/
 .Parameter useCleanDatabase
  Add this switch if you want to uninstall all extensions and remove the base app from the container
 .Parameter useNewDatabase
  Add this switch if you want to create a new and empty database in the container
 .Parameter runSandboxAsOnPrem
  This parameter will attempt to run sandbox artifacts as onprem (will only work with version 18 and later)
 .Parameter doNotCopyEntitlements
  Specify this parameter to avoid copying entitlements when using -useNewDatabase
 .Parameter copyTables
  Array of table names to copy from original database when using -useNewDatabase
 .Parameter dumpEventLog
  Add this switch if you want the container to dump new entries in the eventlog to the output (docker logs) every 2 seconds
 .Parameter doNotCheckHealth
  Add this switch if you want to avoid CPU usage on health check.
 .Parameter doNotUseRuntimePackages
  Include the doNotUseRuntimePackages switch if you do not want to cache and use the test apps as runtime packages (only 15.x containers)
 .Parameter finalizeDatabasesScriptBlock
  In this scriptblock you can install additional apps or import additional objects in your container.
  These apps/objects will be included in the backup if you specify bakFolder and this script will NOT run if a backup already exists in bakFolder.
 .Parameter vsixFile
  Specify a URL or path to a .vsix file in order to override the .vsix file in the image with this.
  Use Get-LatestAlLanguageExtensionUrl to get latest AL Language extension from Marketplace.
  Use Get-AlLanguageExtensionFromArtifacts -artifactUrl (Get-BCArtifactUrl -select NextMajor -accept_insiderEula) to get latest insider .vsix
 .Parameter sqlTimeout
  SQL Timeout for database restore operations
 .Parameter useSqlServerModule
  Switch, forces the use of the sqlserver module instead of the sqlps module. Default is to use the sqlps module. The default can be changed in the bcContainerHelperConfig file by setting "useSqlServerModule" = $false.
 .Example
  New-BcContainer -accept_eula -containerName test
 .Example
  New-BcContainer -accept_eula -containerName test -accept_insiderEula -artifactUrl (Get-BcArtifactUrl -accept_insiderEula -country dk -select NextMajor)
 .Example
  New-BcContainer -accept_eula -containerName test -multitenant
 .Example
  New-BcContainer -accept_eula -containerName test -memoryLimit 3G -artifactUrl (Get-NavArtifactUrl -nav 2017 -country w1) -updateHosts -imageName my
 .Example
  New-BcContainer -accept_eula -containerName test -artifactUrl (Get-BcArtifactUrl -type onprem -country dk) -myScripts @("c:\temp\AdditionalSetup.ps1") -AdditionalParameters @("-v c:\hostfolder:c:\containerfolder")
 .Example
  New-BcContainer -accept_eula -containerName test -credential (get-credential -credential $env:USERNAME) -licenseFile "https://www.dropbox.com/s/fhwfwjfjwhff/license.flf?dl=1" -artifactUrl (Get-BcArtifactUrl -country de)
#>
function New-BcContainer {
    Param (
        [switch] $accept_eula,
        [switch] $accept_insiderEula,
        [switch] $accept_outdated = $true,
        [string] $containerName = $bcContainerHelperConfig.defaultContainerName,
        [string] $imageName = "",
        [string] $artifactUrl = "", 
        [string] $platformArtifactUrl = "",
        [Alias('navDvdPath')]
        [string] $dvdPath = "", 
        [Alias('navDvdCountry')]
        [string] $dvdCountry = "",
        [Alias('navDvdVersion')]
        [string] $dvdVersion = "",
        [Alias('navDvdPlatform')]
        [string] $dvdPlatform = "",
        [string] $locale = "",
        [switch] $setServiceTierUserLocale,
        [string] $licenseFile = "",
        [PSCredential] $Credential = $null,
        [string] $authenticationEMail = "",
        [string] $AadTenant = "",
        [string] $AadAppId = "",
        [string] $AadAppIdUri = "",
        [string] $memoryLimit = "",
        [string] $sqlMemoryLimit = "",
        [ValidateSet('','process','hyperv')]
        [string] $isolation = "",
        [string] $databaseServer = "",
        [string] $databaseInstance = "",
        [string] $databasePrefix = "",
        [string] $databaseName = "",
        [switch] $replaceExternalDatabases,
        [string] $bakFile = "",
        [string] $bakFolder = "",
        [PSCredential] $databaseCredential = $null,
        [ValidateSet('None','Desktop','StartMenu','CommonStartMenu','CommonDesktop','DesktopFolder','CommonDesktopFolder')]
        [string] $shortcuts='Desktop',
        [switch] $updateHosts,
        [switch] $useSSL,
        [switch] $installCertificateOnHost,
        [switch] $includeAL,
        [string] $runTxt2AlInContainer = $containerName,
        [switch] $includeCSide,
        [switch] $enableSymbolLoading,
        [switch] $enableTaskScheduler,
        [switch] $doNotExportObjectsToText,
        [switch] $alwaysPull,
        [switch] $forceRebuild,
        [switch] $useBestContainerOS,
        [string] $useGenericImage,
        [switch] $assignPremiumPlan,
        [switch] $multitenant,
        [switch] $filesOnly,
        [string[]] $addFontsFromPath = @(""),
        [hashtable] $featureKeys = $null,
        [switch] $clickonce,
        [switch] $includeTestToolkit,
        [switch] $includeTestLibrariesOnly,
        [switch] $includeTestFrameworkOnly,
        [switch] $includePerformanceToolkit,
        [ValidateSet('no','on-failure','unless-stopped','always')]
        [string] $restart='unless-stopped',
        [ValidateSet('Windows','NavUserPassword','UserPassword','AAD')]
        [string] $auth='Windows',
        [int] $timeout = 1800,
        [int] $sqlTimeout = 300,
        [string[]] $additionalParameters = @(),
        $myScripts = @(),
        [string] $TimeZoneId = $null,
        [int] $WebClientPort,
        [int] $FileSharePort,
        [int] $ManagementServicesPort,
        [int] $ClientServicesPort,
        [int] $SoapServicesPort,
        [int] $ODataServicesPort,
        [int] $DeveloperServicesPort,
        [int[]] $PublishPorts = @(),
        [string] $PublicDnsName,
        [string] $network = "",
        [string] $hostIP = "",
        [string] $macAddress = "",
        [string] $IP = "",
        [string] $dns = "",
        [switch] $useTraefik,
        [switch] $useCleanDatabase,
        [switch] $useNewDatabase,
        [switch] $runSandboxAsOnPrem,
        [switch] $doNotCopyEntitlements,
        [string[]] $copyTables = @(),
        [switch] $dumpEventLog,
        [switch] $doNotCheckHealth,
        [switch] $doNotUseRuntimePackages = $true,
        [string] $vsixFile = "",
        [string] $applicationInsightsKey,
        [scriptblock] $finalizeDatabasesScriptBlock,
        [switch] $useSqlServerModule = $bcContainerHelperConfig.useSqlServerModule
    )

$telemetryScope = InitTelemetryScope `
                    -name $MyInvocation.InvocationName `
                    -parameterValues $PSBoundParameters `
                    -includeParameters @("containerName","artifactUrl","platformArtifactUrl","isolation","imageName","multitenant","filesOnly")
try {

    $defaultNewContainerParameters = $bcContainerHelperConfig.defaultNewContainerParameters
    if ($defaultNewContainerParameters -is [HashTable]) {
        $defaultNewContainerParameters.GetEnumerator() | ForEach-Object {
            if (!($PSBoundParameters.ContainsKey($_.Name))) {
                if ($_.Name -eq "Credential" -or $_.Name -eq "DatabaseCredential") {
                    Write-Host "Default parameter $($_.Name)"
                    Set-Variable -Name $_.Name -Value (New-Object pscredential -ArgumentList $_.Value.Username, ($_.Value.Password | ConvertTo-SecureString))
                }
                else {
                    Write-Host "Default parameter $($_.Name) = $($_.Value)"
                    Set-Variable -name $_.Name -Value $_.Value
                }
            }
            elseif ($_.Name -eq "AdditionalParameters") {
                Write-Host "Merging $($_.Name)"
                $additionalParameters = $_.Value + $additionalParameters
            }
            elseif ($_.Name -eq "MyScripts") {
                Write-Host "Merging $($_.Name)"
                $myScripts = $_.Value + $myScripts
            }
        }
    }
    elseif ($defaultNewContainerParameters -is [PSCustomObject]) {
        $defaultNewContainerParameters.PSObject.Properties | ForEach-Object {
            if (!($PSBoundParameters.ContainsKey($_.Name))) {
                if ($_.Name -eq "Credential" -or $_.Name -eq "DatabaseCredential") {
                    Write-Host "Default parameter $($_.Name)"
                    Set-Variable -Name $_.Name -Value (New-Object pscredential -ArgumentList $_.Value.Username, ($_.Value.Password | ConvertTo-SecureString))
                }
                else {
                    Write-Host "Default parameter $($_.Name) = $($_.Value)"
                    Set-Variable -name $_.Name -Value $_.Value
                }
            }
            elseif ($_.Name -eq "AdditionalParameters") {
                Write-Host "Merging $($_.Name)"
                $additionalParameters = $_.Value + $additionalParameters
            }
            elseif ($_.Name -eq "MyScripts") {
                Write-Host "Merging $($_.Name)"
                $myScripts = $_.Value + $myScripts
            }
        }        
    }

    if (!$accept_eula) {
        throw "You have to accept the eula (See https://go.microsoft.com/fwlink/?linkid=861843) by specifying the -accept_eula switch to the function"
    }

    if ($includePerformanceToolkit) {
        if (!$includeTestToolkit) {
            $includeTestToolkit = $true
            $includeTestFrameworkOnly = $true
        }
    }

    Check-BcContainerName -ContainerName $containerName
    $imageName = $imageName.ToLowerInvariant()

    if (!$useSSL) {
        try {
            $hsts = (New-Object System.Net.WebClient).DownloadString('https://hstspreload.com/api/v1/status/$containerName') | ConvertFrom-Json
            if (($hsts.chrome) -or ($hsts.firefox) -or ($hsts.tor)) {
                Write-Host -ForegroundColor Red "WARNING: '$containername' is in the HSTS preload list. You cannot use the container unless you use SSL and a trusted certificate.`nAdd -useSSL and -installCertificateOnHost to use a self signed certificate and install it in trusted root certifications on the host."
            }
        }
        catch {}
    }

    if ($imageName -like 'microsoft/dynamics-nav:*' -or $imageName -like 'microsoft/bcsandbox:*') {
        throw "ERROR: Images are no longer available on Docker hub. You should use artifacts instead of specific docker images."
    }

    if ($Credential -eq $null -or $credential -eq [System.Management.Automation.PSCredential]::Empty) {
        if ($filesOnly) {
            $credential = New-Object pscredential -ArgumentList 'admin', (ConvertTo-SecureString -String (GetRandomPassword) -AsPlainText -Force) 
        }
        elseif ($auth -eq "Windows") {
            $credential = get-credential -UserName $env:USERNAME -Message "Using Windows Authentication. Please enter your Windows credentials."
        } else {
            $credential = get-credential -Message "Using $auth Authentication. Please enter username/password for the Containter."
        }
        if ($Credential -eq $null -or $credential -eq [System.Management.Automation.PSCredential]::Empty) {
            throw "You have to specify credentials for your Container"
        }
    }

    if ($auth -eq "Windows") {
        if ($credential.Username.Contains('@')) {
            throw "You cannot use a Microsoft account, you need to use a local Windows user account (like $env:USERNAME)"
        }
        if ($credential.Username.Contains('\')) {
            throw "The username cannot contain domain information, you need to use a local Windows user account (like $env:USERNAME)"
        }
    }
    if ($auth -eq "AAD") {
        if ("$authenticationEMail" -eq "") {
            throw "When using AAD authentication, you have to specify AuthenticationEMail for the user: $($credential.UserName)"
        }
    }

    if ($auth -eq "UserPassword") {
        $auth = "NavUserPassword"
    }

    $myScripts | ForEach-Object {
        if ($_ -is [string]) {
            if ($_.StartsWith("https://", "OrdinalIgnoreCase") -or $_.StartsWith("http://", "OrdinalIgnoreCase")) {
            } elseif (!(Test-Path $_)) {
                throw "Script directory or file $_ does not exist"
            }
        } elseif ($_ -isnot [Hashtable] -and $_ -isnot [PSCustomObject]) {
            throw "Illegal value in myScripts"
        }
    }

    $os = (Get-CimInstance Win32_OperatingSystem)
    if ($os.OSType -ne 18 -or !$os.Version.StartsWith("10.0.")) {
        throw "Unknown Host Operating System"
    }

    $UBR = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name UBR).UBR
    
    $hostOsVersion = [System.Version]::Parse("$($os.Version).$UBR")
    $isServerHost = $os.ProductType -eq 3
    $hostOs = GetHostOs -hostOsVersion $hostOsVersion -isServerHost $isServerHost
    $bestGenericImageName = Get-BestGenericImageName -onlyMatchingBuilds -filesOnly:$filesOnly
    
    Write-Host "BcContainerHelper is version $BcContainerHelperVersion"
    if ($isAdministrator) {
        Write-Host "BcContainerHelper is running as administrator"
        Write-Host "HyperV is $(GetHypervState)"
    }
    else {
        Write-Host "BcContainerHelper is not running as administrator"
    }
    if ($isInsideContainer) {
        Write-Host "BcContainerHelper is running inside a Container"
    }
    Write-Host "Host is $($os.Caption) - $hostOsVersion"
    Write-Host "UsePsSession is $($bcContainerHelperConfig.usePsSession)"
    Write-Host "UsePwshForBc24 is $($bcContainerHelperConfig.usePwshForBc24)"
    Write-Host "UseWinRmSession is $($bcContainerHelperConfig.useWinRmSession)"
    Write-Host "UseSslForWinRmSession is $($bcContainerHelperConfig.useSslForWinRmSession)"

    $dockerProcess = (Get-Process "dockerd" -ErrorAction Ignore)
    if (!($dockerProcess)) {
        Write-Host -ForegroundColor Red "Dockerd process not found. Docker might not be started, not installed or not running Windows Containers. If Docker Desktop is already installed, open the system tray, right-click on the Docker icon, and select 'Switch to Windows containers...'"
    }

    # The Docker daemon might still be starting up (e.g. right after the host boots or on CI runners).
    # In that case the docker client responds, but the server properties are empty. Poll for a bounded
    # amount of time before giving up, so a transient "not yet ready" state doesn't fail the operation.
    $dockerOS = ""
    $dockerClientVersion = ""
    $dockerServerVersion = ""
    $dockerReadyTimeout = [DateTime]::Now.AddSeconds(120)
    while ($true) {
        try {
            $dockerVersion = "$(docker version -f "{{.Server.Os}}/{{.Client.Version}}/{{.Server.Version}}")"
        }
        catch {
            $dockerVersion = ""
        }
        $dockerOS = $dockerVersion.Split('/')[0]
        $dockerClientVersion = $dockerVersion.Split('/')[1]
        $dockerServerVersion = $dockerVersion.Split('/')[2]
        if ("$dockerOS" -ne "" -or [DateTime]::Now -ge $dockerReadyTimeout) {
            break
        }
        Write-Host "Docker service is not yet ready, waiting..."
        Start-Sleep -Seconds 2
    }

    if ("$dockerOS" -eq "") {
        throw "Docker service is not yet ready."
    }
    elseif ($dockerOS -ne "Windows") {
        throw "Docker is running $dockerOS containers, you need to switch to Windows containers."
   	}
    Write-Host "Docker Client Version is $dockerClientVersion"
    AddTelemetryProperty -telemetryScope $telemetryScope -key "dockerClientVersion" -value $dockerClientVersion

    Write-Host "Docker Server Version is $dockerServerVersion"
    AddTelemetryProperty -telemetryScope $telemetryScope -key "dockerServerVersion" -value $dockerServerVersion

    $doNotGetBestImageName = $false
    $skipDatabase = $false
    if ($bakFile -ne "" -or $databaseServer -ne "" -or $databaseInstance -ne "" -or "$databasePrefix$databaseName" -ne "") {
        $skipDatabase = $true
    }

    if ($imageName -eq "" -and $artifactUrl -eq "" -and $dvdPath -eq "") {
        throw "You have to specify artifactUrl or imageName when creating a new container."            
    }

    if ($platformArtifactUrl -and -not $artifactUrl) {
        throw "You have to specify artifactUrl when using platformArtifactUrl."
    }

    # Remove if it already exists
    Remove-BcContainer $containerName

    $createTenantAndUserInExternalDatabase = $false
    if ($artifactUrl) {
        # When using artifacts, you always use best container os - no need to replatform
        $useBestContainerOS = $false

        if ($artifactUrl -like 'https://bcinsider*') {
            if (!$accept_insiderEULA) {
                throw "You need to accept the insider EULA (https://go.microsoft.com/fwlink/?linkid=2245051) by specifying -accept_insiderEula"
            }
        }

        $artifactPaths = Download-Artifacts -artifactUrl $artifactUrl -platformArtifactUrl $platformArtifactUrl -includePlatform -forceRedirection:$alwaysPull
        $appArtifactPath = $artifactPaths[0]
        $platformArtifactPath = $artifactPaths[1]

        $appManifestPath = Join-Path $appArtifactPath "manifest.json"
        $appManifest = Get-Content $appManifestPath | ConvertFrom-Json

        if ($appManifest.version -like "21.0.*" -and $licenseFile -eq "") {
            Write-Host "The CRONUS Demo License shipped in Version 21.0 artifacts doesn't contain sufficient rights to all Test Libraries objects. Patching the license file."
            $country = $appManifest.Country.ToLowerInvariant()
            if (@('at','au','be','ca','ch','cz','de','dk','es','fi','fr','gb','in','is','it','mx','nl','no','nz','ru','se','us') -contains $country) {
                $licenseFile = "https://bcartifacts-exdbf9fwegejdqak.b02.azurefd.net/prerequisites/21demolicense/$country/3048953.bclicense"
            }
            else {
                $licenseFile = "https://bcartifacts-exdbf9fwegejdqak.b02.azurefd.net/prerequisites/21demolicense/w1/3048953.bclicense"
            }
        }

        if ($runSandboxAsOnPrem -and $appManifest.version -lt [Version]"18.0.0.0") {
            $runSandboxAsOnPrem = $false
            Write-Host -ForegroundColor Red "Cannot run sandbox artifacts before version 18 as onprem"
        }

        $bcstyle = "onprem"
        if (!$runSandboxAsOnPrem -and ($appManifest.PSObject.Properties.name -eq "isBcSandbox")) {
            if ($appManifest.isBcSandbox) {
                $bcstyle = "sandbox"
                if (!($PSBoundParameters.ContainsKey('multitenant')) -and !$skipDatabase) {
                    $multitenant = $bcContainerHelperConfig.sandboxContainersAreMultitenantByDefault
                }
            }
        }

        if ($databaseServer -ne "" -and $databasePrefix -ne "" -and $databaseName -ne "" -and $replaceExternalDatabases) {
            if ($bcstyle -eq "sandbox" -and (!($PSBoundParameters.ContainsKey('multitenant')))) {
                $multitenant = $bcContainerHelperConfig.sandboxContainersAreMultitenantByDefault
            }
            Remove-BcDatabase -databaseServer $databaseServer -databaseInstance $databaseInstance -databaseName "$($databasePrefix)%"
            Restore-BcDatabaseFromArtifacts -artifactUrl $artifactUrl -databaseServer $databaseServer -databaseInstance $databaseInstance -databasePrefix $databasePrefix -databaseName $databaseName -multitenant:$multitenant -bakFile $bakFile -useSqlServerModule:$useSqlServerModule.IsPresent -async
            $createTenantAndUserInExternalDatabase = $true
            $bakFile = ""
            $successFileName = Join-Path $bcContainerHelperConfig.containerHelperFolder "$($databasePrefix)databasescreated.txt"
            $myscripts += @( @{ "SetupDatabase.ps1" = "if (!(Test-Path ""$successFileName"")) { Write-Host 'Waiting for database creation to finish'; while (!(Test-Path ""$successFileName"")) { Start-Sleep -seconds 5 }; } Get-Content ""$successFileName"" | Out-Host; . 'c:\run\setupDatabase.ps1'" } ) `
        }
    }

    Write-Host "Fetching all docker images"
    $allImages = @(docker images --format "{{.Repository}}:{{.Tag}}")

    Write-Host "Fetching all docker volumes"
    $allVolumes = @(docker volume ls --format "{{.Mountpoint}}|{{.Name}}")

    if ($imageName -ne "") {

        if ($artifactUrl -eq "") {

            if ($imageName -like "mcr.microsoft.com/*") {
                Write-Host -ForegroundColor Red "WARNING: You are running specific Docker images from mcr.microsoft.com. These images will no longer be updated and will be removed on January 2nd 2021, you should switch to user Docker artifacts. See https://freddysblog.com/2020/07/05/july-updates-are-out-they-are-the-last-on-premises-docker-images/"
            }
            if ($imageName -like "bcinsider.azurecr.io/*") {
                Write-Host -ForegroundColor Red "WARNING: You are running specific Docker images from bcinsider.azurecr.io. These images will no longer be updated and will be removed on January 2nd 2021, you should switch to user Docker artifacts. See https://freddysblog.com/2020/07/05/july-updates-are-out-they-are-the-last-on-premises-docker-images/"
            }
        }
        else {
            Write-Host "ArtifactUrl and ImageName specified"

            $mtImage = $multitenant
            if ($useNewDatabase -or $useCleanDatabase) {
                $mtImage = $false
            }

            $imageName = New-Bcimage `
                -artifactUrl $artifactUrl `
                -platformArtifactUrl $platformArtifactUrl `
                -imageName $imagename `
                -isolation $isolation `
                -baseImage $useGenericImage `
                -memory $memoryLimit `
                -skipDatabase:$skipDatabase `
                -multitenant:$mtImage `
                -addFontsFromPath $addFontsFromPath `
                -licenseFile $licensefile `
                -includeTestToolkit:$includeTestToolkit `
                -includeTestFrameworkOnly:$includeTestFrameworkOnly `
                -includeTestLibrariesOnly:$includeTestLibrariesOnly `
                -includePerformanceToolkit:$includePerformanceToolkit `
                -skipIfImageAlreadyExists:(!$forceRebuild) `
                -runSandboxAsOnPrem:$runSandboxAsOnPrem `
                -allImages $allImages `
                -filesOnly:$filesOnly

            if (-not ($allImages | Where-Object { $_ -eq $imageName })) {
                $allImages += $imageName
            }

            $artifactUrl = ""
            $platformArtifactUrl = ""
            $alwaysPull = $false
            $useGenericImage = ""
            $doNotGetBestImageName = $true
        }
    }

    if (!($PSBoundParameters.ContainsKey('useTraefik'))) {
        $traefikForBcBasePath = "c:\programdata\bccontainerhelper\traefikforbc"
        if (Test-Path -Path (Join-Path $traefikForBcBasePath "traefik.txt") -PathType Leaf) {
            if (-not $PublicDnsName) {
                $wwwRootPath = Get-WWWRootPath
                if ($wwwRootPath) {
                    $hostNameTxtFile = Join-Path $wwwRootPath "hostname.txt"
                    if ((Test-Path $hostNameTxtFile) -and -not $PublicDnsName) {
                        $PublicDnsName = Get-Content -Path $hostNameTxtFile
                    }
                }
            }
            if ($publicDnsName) {
                Write-Host -ForegroundColor Yellow "WARNING: useTraefik not specified, but Traefik container was initialized, using Traefik. Specify -useTraefik:`$false if you do NOT want to use Traefik."
                $useTraefik = $true
            }
        }
    }

    if ($useTraefik) {
        $traefikForBcBasePath = "c:\programdata\bccontainerhelper\traefikforbc"
        if (-not (Test-Path -Path (Join-Path $traefikForBcBasePath "traefik.txt") -PathType Leaf)) {
            throw "Traefik container was not initialized. Please call Setup-TraefikContainerForBcContainers before using -useTraefik"
        }
        
        $forceHttpWithTraefik = $false
        if ((Get-Content (Join-Path $traefikForBcBasePath "config\traefik.toml") | Foreach-Object { $_ -match "^insecureSkipVerify = true$" } ) -notcontains $true) {
            $forceHttpWithTraefik = $true
        }

        if ($PublishPorts.Count -gt 0 -or
            $WebClientPort -or $FileSharePort -or $ManagementServicesPort -or 
            $SoapServicesPort -or $ODataServicesPort -or $DeveloperServicesPort) {
            throw "When using Traefik, all external communication comes in through port 443, so you can't change the ports"
        }

        if ($forceHttpWithTraefik) {
            Write-Host "Disabling SSL on the container as you have configured -forceHttpWithTraefik"
            $useSSL = $false
        } else {
            Write-Host "Enabling SSL as otherwise all clients will see mixed HTTP / HTTPS request, which will cause problems e.g. on the mobile and modern windows clients"
            $useSSL = $true
        }
        $wwwRootPath = Get-WWWRootPath
        if ($wwwRootPath) {
            $hostNameTxtFile = Join-Path $wwwRootPath "hostname.txt"
            if ((Test-Path $hostNameTxtFile) -and -not $PublicDnsName) {
                $PublicDnsName = Get-Content -Path $hostNameTxtFile
            }
        }
        if (-not $PublicDnsName) {
            throw "Using Traefik only makes sense if you allow external access, so you have to provide the public DNS name (param -PublicDnsName)"
        }
    }

    $parameters = @()
    $customNavSettings = @()
    $customWebSettings = @()

    $devCountry = $dvdCountry
    $navVersion = $dvdVersion
    $bcStyle = "onprem"

    $downloadsPath = $bcContainerHelperConfig.bcartifactsCacheFolder
    if (!(Test-Path $downloadsPath)) {
        New-Item $downloadsPath -ItemType Directory | Out-Null
    }

    if ($imageName -eq "") {
        if ($artifactUrl) {
            if ($useGenericImage) {
                $imageName = $useGenericImage
            }
            else {
                $imageName = Get-BestGenericImageName -filesOnly:$filesOnly
            }
        }
        elseif ("$dvdPath" -ne "") {
            if ($useGenericImage) {
                $imageName = $useGenericImage
            }
            else {
                $imageName = Get-BestGenericImageName -filesOnly:$filesOnly
            }
        } elseif (Test-BcContainer -containerName $bcContainerHelperConfig.defaultContainerName) {
            $artifactUrl = Get-BcContainerArtifactUrl -containerName $bcContainerHelperConfig.defaultContainerName
            if ($artifactUrl) {
                if ($useGenericImage) {
                    $imageName = $useGenericImage
                }
                else {
                    $imageName = Get-BestGenericImageName -filesOnly:$filesOnly
                }
            }
            else {
                $imageName = Get-BcContainerImageName -containerName $bcContainerHelperConfig.defaultContainerName
            }
        } else {
            throw "You have to specify artifactUrl or imageName when creating a new container."            
        }
        $bestImageName = $imageName
    }
    elseif ($doNotGetBestImageName) {
        $bestImageName = $imageName
    }
    else {
        if (!$imageName.Contains(':')) {
            $imageName += ":latest"
        }
    
        # Determine best container ImageName (append -ltsc2016 or -ltsc2019)
        $bestImageName = Get-BestBcContainerImageName -imageName $imageName
    
        if ($useBestContainerOS) {
            $imageName = $bestImageName
        }
    }
    
    $pullit = $alwaysPull
    if (!$alwaysPull) {

        $imageExists = $false
        $bestImageExists = $false
        $allImages | ForEach-Object {
            if ("$_" -eq "$imageName" -or "$_" -eq "$($imageName):latest") { $imageExists = $true }
            if ("$_" -eq "$bestImageName") { $bestImageExists = $true }
        }

        if ($bestImageExists) {
            $imageName = $bestImageName
            if ($artifactUrl) {
                $genericTagVersion = [Version](Get-BcContainerGenericTag -containerOrImageName $imageName)
                if ($genericTagVersion -lt [Version]$LatestGenericTagVersion) {
                    Write-Host "Existing generic image is version $genericTagVersion - pulling a newer image"
                    $pullit = $true
                }
            }
        } elseif ($imageExists) {
            Write-Host "NOTE: Add -alwaysPull or -useBestContainerOS if you want to use $bestImageName instead of $imageName."
        } else {
            $pullit = $true
        }
    }

    if ($pullit) {
        try {
            Write-Host "Pulling image $bestImageName"
            DockerDo -command pull -imageName $bestImageName | Out-Null
            $imageName = $bestImageName
        } catch {
            if ($imageName -eq $bestImageName) {
                throw
            }
            Write-Host "Pulling image $imageName"
            DockerDo -command pull -imageName $imageName | Out-Null
        }
    }

    Write-Host "Using image $imageName"
    $inspect = docker inspect $imageName | ConvertFrom-Json

    if ($sqlTimeout -ne 300) {
        $parameters += "--env sqlTimeout=$sqlTimeout"
    }

    if ($clickonce) {
        if ($useTraefik) {
            Write-Host "WARNING: ClickOnce doesn't work with traefik v1 (which is the one used in this version of ContainerHelper)"
        }
        $parameters += "--env clickonce=Y"
    }

    if ($applicationInsightsKey) {
        $parameters += "--env applicationInsightsInstrumentationKey=$applicationInsightsKey"
    }

    if ($WebClientPort) {
        $parameters += "--env WebClientPort=$WebClientPort"
    }

    if ($FileSharePort) {
        $parameters += "--env FileSharePort=$FileSharePort"
    }

    if ($ManagementServicesPort) {
        $parameters += "--env ManagementServicesPort=$ManagementServicesPort"
    }

    if ($ClientServicesPort) {
        $parameters += "--env ClientServicesPort=$ClientServicesPort"
    }

    if ($SoapServicesPort) {
        $parameters += "--env SoapServicesPort=$SoapServicesPort"
    }

    if ($ODataServicesPort) {
        $parameters += "--env ODataServicesPort=$ODataServicesPort"
    }

    if ($DeveloperServicesPort) {
        $parameters += "--env DeveloperServicesPort=$DeveloperServicesPort"
    }

    $networkSettings = @{}
    if ($bcContainerHelperConfig.mapNetworkSettings.PSObject.Properties.GetEnumerator() | Where-Object { $_.Name -eq $containerName }) {
        $networkSettings = $bcContainerHelperConfig.mapNetworkSettings."$containerName"
        if ($networkSettings -isnot [hashtable]) {
            $networkSettings = $networkSettings | ConvertTo-HashTable
        }
        if ($networkSettings.ContainsKey('dns') -and $dns -eq "") {
            $dns = $networkSettings.dns
        }
        if ($networkSettings.ContainsKey('network') -and $network -eq "") {
            $network = $networkSettings.network
        }
        if ($networkSettings.ContainsKey('ip') -and $ip -eq "") {
            $ip = $networkSettings.ip
        }
        if ($networkSettings.ContainsKey('macAddress') -and $macAddress -eq "") {
            $macAddress = $networkSettings.macAddress
        }
        if ($networkSettings.ContainsKey('hostIP') -and $hostIP -eq "") {
            $hostIP = $networkSettings.hostIP
        }
    }

    if ($dns -eq "hostDNS" -or ($bcContainerHelperConfig.AddHostDnsServersToNatContainers -and ($network -eq "NAT" -or $network -eq "") -and $dns -eq "")) {
        $dnsServers = @(Get-NetIPInterface | Where-Object { $_.ConnectionState -eq "Connected" -and $_.AddressFamily -eq "IPv4" } | ForEach-Object { Get-DnsClientServerAddress -AddressFamily IPv4 -InterfaceAlias $_.InterfaceAlias | ForEach-Object { $_.ServerAddresses } })
        Write-Host "Adding DNS Servers from host: $($dnsServers -join ', ')"
        $dns = $dnsServers -join ','
    }

    if ($dns) {
        $parameters += "--dns $($dns.Replace(',',' --dns '))"
    }

    if ($network) {
        $parameters += "--network $network"
        if ($network -ne "NAT" -and $hostIP -eq "") {
            $hostIP = (ipconfig | where-object { $_ –match "IPv4 Address" } | foreach-object{ $_.Split(":")[1] } | Where-Object { $_.Trim() -ne "" } ) | Select-Object -First 1
        }
    }

    if ($hostIP) {
        $parameters += "--env hostIP=$($hostIP.Trim())"
    }

    if ($macAddress) {
        $parameters += "--mac-address ""$macAddress"""
    }

    if ($IP) {
        $parameters += "--ip ""$IP"""
    }

    $publishPorts | ForEach-Object {
        Write-Host "Publishing port $_"
        $parameters += "--publish $($_):$($_)"
    }

    if ($publicDnsName) {
        Write-Host "PublicDnsName is $publicDnsName"
        $parameters += "--env PublicDnsName=$PublicDnsName"
    }

    if ($doNotCheckHealth) {
        Write-Host "Disabling Health Check (always report healthy)"
        $parameters += '--no-healthcheck'
    }

    $containerFolder = Join-Path $bcContainerHelperConfig.hostHelperFolder "Extensions\$containerName"
    Remove-Item -Path $containerFolder -Force -Recurse -ErrorAction Ignore
    New-Item -Path $containerFolder -ItemType Directory -ErrorAction Ignore | Out-Null

    if ($dvdPath.StartsWith("http://", [StringComparison]::OrdinalIgnoreCase) -or $dvdPath.StartsWith("https://", [StringComparison]::OrdinalIgnoreCase)) {
        $tempFolder = Join-Path $containerFolder "DVD"
        new-item -type directory -Path $tempFolder | Out-Null
        $tempFile = "$tempFolder.zip"
        Download-File -sourceUrl $dvdPath -destinationFile $tempFile
        Write-Host "Extracting DVD .zip file " -NoNewline
        Expand-7zipArchive -Path $tempFile -DestinationPath $tempFolder
        Remove-Item -Path $tempFile
        $dvdPath = $tempFolder
    }
    elseif ($dvdPath.EndsWith(".zip", [StringComparison]::OrdinalIgnoreCase)) {
        $temp = Join-Path $containerFolder "NAVDVD"
        new-item -type directory -Path $temp | Out-Null
        Write-Host "Extracting DVD .zip file " -NoNewline
        Expand-7zipArchive -Path $dvdPath -DestinationPath $temp
        $dvdPath = $temp
    }

    if ($artifactUrl) {
        $parameters += getVolumeMountParameter -volumes $allVolumes -hostPath $downloadsPath -containerPath "c:\dl"

        $artifactPaths = Download-Artifacts -artifactUrl $artifactUrl -platformArtifactUrl $platformArtifactUrl -includePlatform -forceRedirection:$alwaysPull
        $appArtifactPath = $artifactPaths[0]
        $platformArtifactPath = $artifactPaths[1]

        $appManifestPath = Join-Path $appArtifactPath "manifest.json"
        $appManifest = Get-Content $appManifestPath | ConvertFrom-Json

        if ($runSandboxAsOnPrem -and $appManifest.version -lt [Version]"18.0.0.0") {
            $runSandboxAsOnPrem = $false
            Write-Host -ForegroundColor Red "Cannot run sandbox artifacts before version 18 as onprem"
        }

        $bcstyle = "onprem"
        if (!$runSandboxAsOnPrem -and ($appManifest.PSObject.Properties.name -eq "isBcSandbox")) {
            if ($appManifest.isBcSandbox) {
                $bcstyle = "sandbox"
                if (!($PSBoundParameters.ContainsKey('multitenant')) -and !$skipDatabase) {
                    $multitenant = $bcContainerHelperConfig.sandboxContainersAreMultitenantByDefault
                }
            }
        }

        if ($appManifest.PSObject.Properties.name -eq "Nav") {
            $parameters += @("--label nav=$($appManifest.Nav)")
        }
        else {
            $parameters += @("--label nav=")
        }
        if ($appManifest.PSObject.Properties.name -eq "Cu") {
            $parameters += @("--label cu=$($appManifest.Cu)")
        }
        if ($bcStyle -eq "sandbox") {
            $parameters += @("--env isBcSandbox=Y")
        }
        else {
            $parameters += @("--env isBcSandbox=N")
        }

        # Copy manifest.json for use during compilation (.NET version resolution, etc.)
        $manifestSource = Join-Path $appArtifactPath "manifest.json"
        if (Test-Path $manifestSource) {
            Copy-Item -Path $manifestSource -Destination (Join-Path $containerFolder "manifest.json") -Force
        }

        $dvdVersion = $appmanifest.Version
        $dvdCountry = $appManifest.Country
        $dvdPlatform = $appManifest.Platform

        $devCountry = $dvdCountry
        $navVersion = "$dvdVersion-$dvdCountry"

        $parameters += @(
                       "--label version=$dvdVersion"
                       "--label platform=$dvdPlatform"
                       "--label country=$dvdCountry"
                       "--env artifactUrl=$artifactUrl"
                       "--env platformArtifactUrl=$platformArtifactUrl"
                       )
    }
    elseif ("$dvdPath" -ne "") {
        if ("$dvdVersion" -eq "" -and (Test-Path "$dvdPath\version.txt")) {
            $dvdVersion = Get-Content "$dvdPath\version.txt"
        }
        if ("$dvdPlatform" -eq "" -and (Test-Path "$dvdPath\platform.txt")) {
            $dvdPlatform = Get-Content "$dvdPath\platform.txt"
        }
        if ("$dvdCountry" -eq "" -and (Test-Path "$dvdPath\country.txt")) {
            $dvdCountry = Get-Content "$dvdPath\country.txt"
        }
        if ($dvdVersion) {
            $navVersion = $dvdVersion
        }
        else {
            $navversion = (Get-Item -Path "$dvdPath\ServiceTier\*\Microsoft Dynamics NAV\*\Service\Microsoft.Dynamics.Nav.Server.exe").VersionInfo.FileVersion
        }
        $navtag = Get-NavVersionFromVersionInfo -VersionInfo $navversion
        if ("$navtag" -eq "" -and "$dvdPlatform" -eq "") {
            $dvdPlatform = $navversion
        }
        if ($dvdCountry) {
            $devCountry = $dvdCountry
        }
        else {
            $devCountry = "w1"
        }

        $parameters += @(
                       "--label nav=$navtag",
                       "--label version=$navversion",
                       "--label country=$devCountry",
                       "--label cu="
                       )

        if ($dvdPlatform) {
            $parameters += @( "--label platform=$dvdPlatform" )
        }

        $navVersion += "-$devCountry"

    } elseif ($devCountry -eq "") {
        $devCountry = $inspect.Config.Labels.country
    }

    Write-Host "Creating Container $containerName"
    
    if ($navVersion -eq "") {
        if ($inspect.Config.Labels.psobject.Properties.Match('maintainer').Count -eq 0 -or $inspect.Config.Labels.maintainer -ne "Dynamics SMB") {
            throw "Container $imageName is not a NAV/BC container"
        }
        $navversion = "$($inspect.Config.Labels.version)-$($inspect.Config.Labels.country)"
        if ($inspect.Config.Env | Where-Object { $_ -eq "IsBcSandbox=Y" }) {
            $bcStyle = "sandbox"
        }
    }

    Write-Host "Style: $bcStyle"
    if ($multitenant) {
        Write-Host "Multitenant: Yes"
    }
    else {
        Write-Host "Multitenant: No"
    }

    $version = [System.Version]($navversion.split('-')[0])
    Write-Host "Version: $version"

    if ($dvdPlatform) {
        $platformVersion = $dvdPlatform
    }
    else {
        if ($inspect.Config.Labels.psobject.Properties.Name -eq 'platform') {
            $platformVersion = $inspect.Config.Labels.platform
        } else {
            $platformVersion = ""
        }
    }
    if ($platformversion) {
        Write-Host "Platform: $platformversion"
        AddTelemetryProperty -telemetryScope $telemetryScope -key "platformVersion" -value $platformVersion
    }

    $genericIsDev = ""
    if ($imageName -like "mcr.microsoft.com/businesscentral:*-dev") {
        $genericIsDev = "-dev"
    }
    $genericTag = [Version]"$($inspect.Config.Labels.tag)"
    Write-Host "Generic Tag: $genericTag$genericIsDev"
    AddTelemetryProperty -telemetryScope $telemetryScope -key "applicationVersion" -value $navVersion
    AddTelemetryProperty -telemetryScope $telemetryScope -key "country" -value $devCountry
    AddTelemetryProperty -telemetryScope $telemetryScope -key "style" -value $bcStyle
    AddTelemetryProperty -telemetryScope $telemetryScope -key "multitenant" -value $multitenant
    AddTelemetryProperty -telemetryScope $telemetryScope -key "genericTag" -value "$genericTag"

    $containerOsVersion = [Version]"$($inspect.Config.Labels.osversion)"
    $containerOs = GetContainerOs -containerOsVersion $containerOsVersion
    if ($containerOs -eq 'ltsc2016' -and !$useBestContainerOS -and $TimeZoneId -eq $null) {
        $timeZoneId = (Get-TimeZone).Id
    }
    Write-Host "Container OS Version: $containerOsVersion ($containerOs)"
    Write-Host "Host OS Version: $hostOsVersion ($hostOs)"

    AddTelemetryProperty -telemetryScope $telemetryScope -key "hostOs" -value $hostOs
    AddTelemetryProperty -telemetryScope $telemetryScope -key "hostOsVersion" -value $hostOsVersion
    AddTelemetryProperty -telemetryScope $telemetryScope -key "containerOs" -value $containerOs
    AddTelemetryProperty -telemetryScope $telemetryScope -key "containerOsVersion" -value $containerOsVersion

    if (($hostOsVersion.Major -lt $containerOsversion.Major) -or 
        ($hostOsVersion.Major -eq $containerOsversion.Major -and $hostOsVersion.Minor -lt $containerOsversion.Minor) -or 
        ($hostOsVersion.Major -eq $containerOsversion.Major -and $hostOsVersion.Minor -eq $containerOsversion.Minor -and $hostOsVersion.Build -lt $containerOsversion.Build)) {

        throw "The container operating system is newer than the host operating system, cannot use image"
    
    } elseif ("$useGenericImage" -eq "" -and
              ($hostOsVersion.Major -ne $containerOsversion.Major -or 
               $hostOsVersion.Minor -ne $containerOsversion.Minor -or 
               $hostOsVersion.Build -ne $containerOsversion.Build -or 
               $hostOsVersion.Revision -ne $containerOsversion.Revision)) {

        if ("$dvdPath" -eq "" -and $useBestContainerOS -and "$bestGenericImageName" -ne "") {
            
            # There is a generic image, which is better than the selected image
            Write-Host "A better Generic Container OS exists for your host ($bestGenericImageName)"
            $useGenericImage = $bestGenericImageName

        }
    }

    if ($useGenericImage -and $useGenericImage -ne $imageName) {

        if ("$dvdPath" -eq "" -and "$artifactUrl" -eq "") {
            # Extract files from image if not already done
            $dvdPath = Join-Path $bcContainerHelperConfig.hostHelperFolder "$($NavVersion)-Files"

            if (!(Test-Path "$dvdPath\allextracted")) {
                Extract-FilesFromBcContainerImage -imageName $imageName -path $dvdPath -force
                if (!(Test-Path "$dvdPath\allextracted")) {
                    throw "Couldn't extract content from image $image"
                }
            }

            $parameters += @(
                           "--label nav=$($inspect.Config.Labels.nav)",
                           "--label version=$($inspect.Config.Labels.version)",
                           "--label country=$($inspect.Config.Labels.country)",
                           "--label cu=$($inspect.Config.Labels.cu)"
                           )

            if ($inspect.Config.Labels.psobject.Properties.Name -eq 'platform') {
                $parameters += @( "--label platform=$($inspect.Config.Labels.platform)" )
            }
            if ($inspect.Config.Env | Where-Object { $_ -eq "IsBcSandbox=Y" }) {
                $parameters += @(" --env IsBcSandbox=Y" )
            }
        }

        $imageName = $useGenericImage
        Write-Host "Using generic image $imageName"

        if (!$alwaysPull) {
            $alwaysPull = $true
            $allImages | ForEach-Object {
                if ("$_" -eq "$imageName" -or "$_" -eq "$($imageName):latest") { $alwaysPull = $false }
            }
        }

        if ($alwaysPull) {
            Write-Host "Pulling image $imageName"
            DockerDo -command pull -imageName $imageName | Out-Null
        }

        $inspect = docker inspect $imageName | ConvertFrom-Json
        $useGenericImageTagVersion = [System.Version]"$($inspect.Config.Labels.tag)"

        if ($artifactUrl) {
            if ($useGenericImageTagVersion -lt [System.Version]"0.0.9.103") {
                Write-Host "Generic Tag is $useGenericImageTagVersion - pulling updated generic image to use artifacts"
                DockerDo -command pull -imageName $imageName | Out-Null
            }
        }

        $containerOsVersion = [Version]"$($inspect.Config.Labels.osversion)"
        $containerOs = GetContainerOs -containerOsVersion $containerOsVersion

        Write-Host "Generic Container OS Version: $containerOsVersion ($containerOs)"

        $genericTagVersion = [Version]"$($inspect.Config.Labels.tag)"
        Write-Host "Generic Tag of better generic: $genericTagVersion"
    }

    $isolation = GetIsolationMode -hostOsVersion $hostOsVersion -containerOsVersion $containerOsVersion -useSSL $useSSL -isolation $isolation
    Write-Host "Using $isolation isolation"

    if ($isolation -eq "process" -and !$isServerHost -and ($os.BuildNumber -eq 22621 -or $os.BuildNumber -eq 22631 -or $os.BuildNumber -eq 26100) -and $useSSL) {
        Write-Host -ForegroundColor Red "WARNING: Using SSL when running Windows 11 with process isolation might not work due to a bug in Windows 11. Please use HyperV isolation or disable SSL."
    }

    AddTelemetryProperty -telemetryScope $telemetryScope -key "isolation" -value $isolation


    if ("$locale" -eq "") {
        $locale = Get-LocaleFromCountry $devCountry
    }
    Write-Host "Using locale $locale"

    AddTelemetryProperty -telemetryScope $telemetryScope -key "locale" -value $locale

    if ($filesOnly -and $version.Major -lt 15) {
        throw "FilesOnly containers are not supported for version prior to 15"
    }

    if ((!$doNotExportObjectsToText) -and ($version -lt [System.Version]"8.0.0.0")) {
        throw "PowerShell Cmdlets to export objects as text are not included before NAV 2015, please specify -doNotExportObjectsToText."
    }

    if ($multitenant -and ($version -lt [System.Version]"7.1.0.0")) {
        throw "Multitenancy is not supported in NAV 2013"
    }

    if ($includeAL -and ($version.Major -lt 14)) {
        throw "IncludeAL is supported from Dynamics 365 Business Central Spring 2019 release (1904 / 14.x)"
    }

    if ($includeCSide -and ($version.Major -ge 15)) {
        throw "IncludeCSide is no longer supported in Dynamics 365 Business Central 2019 wave 2 release (1910 / 15.x)"
    }

    if ($enableSymbolLoading -and ($version.Major -ge 15)) {
        throw "EnableSymbolLoading is no longer needed in Dynamics 365 Business Central 2019 wave 2 release (1910 / 15.x)"
    }

    if ($bcContainerHelperConfig.UseVolumeForMyFolder) {
        $myVolumeName = "$containerName-my"
        if ($allVolumes | Where-Object { $_ -like "*|$myVolumeName" }) {
            throw "Fatal error, volume $myVolumeName already exists"
        }
        docker volume create $myVolumeName
        $myFolder = ((docker volume inspect $myVolumeName) | ConvertFrom-Json).MountPoint
        $allVolumes += "$myfolder|$myVolumeName"
    }
    else {
        $myFolder = Join-Path $containerFolder "my"
        New-Item -Path $myFolder -ItemType Directory -ErrorAction Ignore | Out-Null
    }

    if ($useTraefik) {
        Write-Host "Adding special CheckHealth.ps1 to enable Traefik support"
        $myscripts += (Join-Path $traefikForBcBasePath "my\CheckHealth.ps1")
    }

    if (-not $dumpEventLog) {
        Write-Host "Disabling the standard eventlog dump to container log every 2 seconds (use -dumpEventLog to enable)"
        Set-Content -Path (Join-Path $myFolder "MainLoop.ps1") -Value 'while ($true) { start-sleep -seconds 1 }'
    }

    $myScripts | ForEach-Object {
        if ($_ -is [string]) {
            if ($_.StartsWith("https://", "OrdinalIgnoreCase") -or $_.StartsWith("http://", "OrdinalIgnoreCase")) {
                $uri = [System.Uri]::new($_)
                $filename = [System.Uri]::UnescapeDataString($uri.Segments[$uri.Segments.Count-1])
                $destinationFile = Join-Path $myFolder $filename
                Download-File -sourceUrl $_ -destinationFile $destinationFile
                if ($destinationFile.EndsWith(".zip", "OrdinalIgnoreCase")) {
                    Write-Host "Extracting .zip file " -NoNewline
                    Expand-7zipArchive -Path $destinationFile -DestinationPath $myFolder
                    Remove-Item -Path $destinationFile -Force
                }
            } elseif (Test-Path $_ -PathType Container) {
                Copy-Item -Path "$_\*" -Destination $myFolder -Recurse -Force
            } else {
                if ($_.EndsWith(".zip", "OrdinalIgnoreCase")) {
                    Write-Host "Extracting .zip file " -NoNewline
                    Expand-7zipArchive -Path $_ -DestinationPath $myFolder
                } else {
                    Copy-Item -Path $_ -Destination $myFolder -Force
                }
            }
        }
        elseif ($_ -is [hashtable]) {
            $hashtable = $_
            $hashtable.Keys | ForEach-Object {
                Add-Content -Path (Join-Path $myFolder $_) -Value "`n$($hashtable[$_])`n"
            }
        }
        elseif ($_ -is [PSCustomObject]) {
            $psobj = $_
            $psobj.PSObject.Properties | ForEach-Object {
                Add-Content -Path (Join-Path $myFolder $_.Name) -Value "`n$($_.Value)`n"
            }
        }
    }
    
    $restoreBakFolder = $false
    if ($bakFolder) {
        if (!$bakFolder.Contains('\')) {
            $bakFolder = Join-Path $bcContainerHelperConfig.hostHelperFolder "$bcStyle-$($NavVersion)-bakFolders\$bakFolder"
        }
        if (Test-Path (Join-Path $bakFolder "*.bak")) {
            $restoreBakFolder = $true
            if (!$multitenant) {
                $bakFile = Join-Path $bakFolder "database.bak"
                $parameters += "--env bakfile=""$bakFile"""
            }
        }
    }

    if ($multitenant -and !($usecleandatabase -or $useNewDatabase -or $restoreBakFolder)) {
        $parameters += "--env multitenant=Y"
    }

    if ($bakFile -and !$restoreBakFolder) {
        if ($bakFile.StartsWith("http://", [StringComparison]::OrdinalIgnoreCase) -or $bakFile.StartsWith("https://", [StringComparison]::OrdinalIgnoreCase)) {
            $temp = Join-Path $containerFolder "database.bak"
            Download-File -sourceUrl $bakFile -destinationFile $temp
            $bakFile = $temp
        }
        if (!(Test-Path $bakFile)) {
            throw "Database backup $bakFile doesn't exist"
        }
        
        if (-not $bakFile.StartsWith($bcContainerHelperConfig.hostHelperFolder, [StringComparison]::OrdinalIgnoreCase)) {
            $containerBakFile = Join-Path $containerFolder "database.bak"
            Copy-Item -Path $bakFile -Destination $containerBakFile
            $bakFile = $containerBakFile
        }
        if ($bakFile.StartsWith($bcContainerHelperConfig.hostHelperFolder, [StringComparison]::OrdinalIgnoreCase)) {
            $bakFile = "$($bcContainerHelperConfig.containerHelperFolder)$($bakFile.Substring($bcContainerHelperConfig.hostHelperFolder.Length))"
        }
        $parameters += "--env bakfile=""$bakFile"""
    }

    $vsixFile = DetermineVsixFile -vsixFile $vsixFile

    if ($vsixFile) {
        $vsixUrl = $vsixFile
        if ($vsixUrl.StartsWith("https://", "OrdinalIgnoreCase") -or $vsixUrl.StartsWith("http://", "OrdinalIgnoreCase")) {
            $uri = [Uri]::new($vsixUrl)
            $vsixFile = "$containerFolder\$($uri.Segments[$uri.Segments.Count-1]).vsix"
            Download-File -sourceUrl $vsixUrl -destinationFile $vsixFile
        }
        elseif (Test-Path $vsixUrl -PathType Leaf) {
            $vsixFile = "$containerFolder\$([System.IO.Path]::GetFileName($vsixUrl))"
            Copy-Item -Path $vsixUrl -Destination $vsixFile
        }
        else {
            $vsixFile = ""
            throw "Unable to locate vsix file ($vsixUrl)"
        }
    }

    if (!$restoreBakFolder) {
        $ext = ''
        if ("$licensefile" -eq "") {
            if ($includeCSide -and !$doNotExportObjectsToText) {
                throw "You must specify a license file when creating a CSide Development container or use -doNotExportObjectsToText to avoid baseline generation."
            }
            if ($includeAL -and ($version.Major -eq 14)) {
                throw "You must specify a license file when creating a AL Development container with this version."
            }
            $containerlicenseFile = ""
        } elseif ($licensefile -like "https://*" -or $licensefile -like "http://*") {
            Write-Host "Using license file $($licenseFile.Split('?')[0])"
            $licensefileUri = $licensefile
            $ext = [System.IO.Path]::GetExtension($licenseFile.Split('?')[0])
            $licenseFile = "$myFolder\license$ext"
            Download-File -sourceUrl $licenseFileUri -destinationFile $licenseFile
            if ((Get-Content $licenseFile -First 1) -ne "Microsoft Software License Information") {
                Remove-Item -Path $licenseFile -Force
                throw "Specified license file Uri isn't a direct download Uri"
            }
            $containerLicenseFile = "c:\run\my\license$ext"
        } else {
            Write-Host "Using license file $licenseFile"
            $ext = [System.IO.Path]::GetExtension($licenseFile)
            Copy-Item -Path $licenseFile -Destination "$myFolder\license$ext" -Force
            $containerLicenseFile = "c:\run\my\license$ext"
        }
        $parameters += @( "--env licenseFile=""$containerLicenseFile""" )
        if ($ext -eq '.flf' -and $version.major -ge 22) {
            throw "The .flf license file format is not supported in Business Central version 22 and later."
        }
    }

    $parameters += @(
                    "--name $containerName",
                    "--hostname $containerName",
                    "--env auth=$auth"
                    "--env username=""$($credential.UserName)""",
                    "--env ExitOnError=N",
                    "--env locale=$locale",
                    "--env databaseServer=""$databaseServer""",
                    "--env databaseInstance=""$databaseInstance""",
                    (getVolumeMountParameter -volumes $allVolumes -hostPath $bcContainerHelperConfig.hostHelperFolder -containerPath $bcContainerHelperConfig.containerHelperFolder),
                    (getVolumeMountParameter -volumes $allVolumes -hostPath $myFolder -containerPath "C:\Run\my"),
                    "--isolation $isolation",
                    "--restart $restart"
                   )

    if ("$memoryLimit" -eq "" -and $isolation -eq "hyperv") {
        $memoryLimit = "8G"
    }

    $SqlServerMemoryLimit = 0
    if ($SqlMemoryLimit) {
        if ($SqlMemoryLimit.EndsWith('%')) {
            if ($memoryLimit -ne "") {
                if ($memoryLimit -like '*M') {
                    $mbytes = [int]($memoryLimit.TrimEnd('mM'))
                }
                else {
                    $mbytes = [int](1024*([double]($memoryLimit.TrimEnd('gG'))))
                }
                $sqlServerMemoryLimit = [int]($mbytes * ([int]$SqlMemoryLimit.TrimEnd('%')) / 100)
            }
        }
        else {
            if ($SqlMemoryLimit -like '*M') {
                $SqlServerMemoryLimit = [int]($SqlMemoryLimit.TrimEnd('mM'))
            }
            else {
                $SqlServerMemoryLimit = [int](1024*([double]($SqlMemoryLimit.TrimEnd('gG'))))
            }
        }
    }

    $parameters += "--env filesOnly=$filesOnly"

    if ($memoryLimit) {
        $parameters += "--memory $memoryLimit"
    }

    if ($version.Major -gt 11) {
        $parameters += "--env enableApiServices=Y"
    }

    if ("$databasePrefix$databaseName" -ne "") {
        $parameters += "--env databaseName=""$databasePrefix$databaseName"""
    }

    if ("$authenticationEMail" -ne "") {
        $parameters += "--env authenticationEMail=""$authenticationEMail"""
    }

    if ($AadAppId) {
        $customNavSettings += @("ValidAudiences=$AadAppId;https://api.businesscentral.dynamics.com", "DisableTokenSigningCertificateValidation=True", "ExtendedSecurityTokenLifetime=24", "ClientServicesCredentialType=NavUserPassword")
        if ($version.Major -ge 20) {
            $AadTenantId = $AadTenant
            if (!$AadTenantId) { $AadTenantId = "Common" }
            $customWebSettings += @("AadApplicationId=$AadAppId","AadAuthorityUri=https://login.microsoftonline.com/$AADTenantId")
            if ($version.Major -ge 25) {
                $customWebSettings += @("AadValidAudience=https://api.businesscentral.dynamics.com")
            }
        }
    }

    if ($AadTenant) {
        $parameters += "--env AadTenant=$AadTenant"
    }

    if ($AadAppIdUri) {
        $parameters += "--env AppIdUri=$AadAppIdUri"
    }

    if ($PSBoundParameters.ContainsKey('enableTaskScheduler')) {
        $customNavSettings += @("EnableTaskScheduler=$enableTaskScheduler")
    }

    if ($enableSymbolLoading -and $version.Major -ge 11 -and $version.Major -lt 15) {
        $parameters += "--env enableSymbolLoading=Y"
    }
    else {
        $enableSymbolLoading = $false
    }

    if ($IsInsideContainer) {
        ('
if (!$restartingInstance) {
    $cert = New-SelfSignedCertificate -DnsName "dontcare" -CertStoreLocation Cert:\LocalMachine\My
    winrm create winrm/config/Listener?Address=*+Transport=HTTPS (''@{Hostname="dontcare"; CertificateThumbprint="'' + $cert.Thumbprint + ''"}'')
    winrm set winrm/config/service/Auth ''@{Basic="true"}''
    Write-Host "Creating Container user $username"
    New-LocalUser -AccountNeverExpires -PasswordNeverExpires -FullName $username -Name '+$bcContainerHelperConfig.WinRmCredentials.UserName+' -Password (ConvertTo-SecureString -string "'+([System.Runtime.InteropServices.Marshal]::PtrToStringBSTR([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($bcContainerHelperConfig.WinRmCredentials.Password)))+'" -AsPlainText -force) | Out-Null
    Add-LocalGroupMember -Group administrators -Member '+$bcContainerHelperConfig.WinRmCredentials.UserName+'
}
') | Add-Content -Path "$myfolder\AdditionalSetup.ps1"
    }
    elseif ($bcContainerHelperConfig.useWinRmSession -ne 'never') {
        # UseWinRmSession is allow or always - add winrm configuration to container
        $winRmPassword = "Bc$((Get-CimInstance win32_ComputerSystemProduct).UUID)!"
        ('
if (!$restartingInstance) {
    Write-Host "Enable PSRemoting and setup user for winrm"
    Enable-PSRemoting | Out-Null
    Get-PSSessionConfiguration | Out-null
    pwsh.exe -Command "Enable-PSRemoting -WarningAction SilentlyContinue | Out-Null; Get-PSSessionConfiguration | Out-Null"
    $credential = New-Object PSCredential -ArgumentList "winrm", (ConvertTo-SecureString -string "'+$winRmPassword+'" -AsPlainText -force)
    New-LocalUser -AccountNeverExpires -PasswordNeverExpires -FullName $credential.UserName -Name $credential.UserName -Password $credential.Password | Out-Null
    Add-LocalGroupMember -Group administrators -Member $credential.UserName | Out-Null
    winrm set winrm/config/service/Auth ''@{Basic="true"}'' | Out-Null
}
') | Add-Content -Path "$myfolder\AdditionalSetup.ps1"
    if ($bccontainerHelperConfig.useSslForWinRmSession) {
        $additionalParameters += @("--expose 5986")
        ('
if (!$restartingInstance) {
    Write-Host "Creating self-signed certificate for winrm"
    $cert = New-SelfSignedCertificate -CertStoreLocation cert:\localmachine\my -DnsName $env:computername -NotBefore (get-date).AddDays(-1) -NotAfter (get-date).AddYears(5) -Provider "Microsoft RSA SChannel Cryptographic Provider" -KeyLength 2048
    winrm create winrm/config/Listener?Address=*+Transport=HTTPS ("@{Hostname=""$env:computername""; CertificateThumbprint=""$($cert.Thumbprint)""}") | Out-Null
}
') | Add-Content -Path "$myfolder\AdditionalSetup.ps1"
    }
    else {
        $additionalParameters += @("--expose 5985")
        ('
if (!$restartingInstance) {
    Write-Host "Allow unencrypted communication to container"
    winrm set winrm/config/service ''@{AllowUnencrypted="true"}'' | Out-Null
}
') | Add-Content -Path "$myfolder\AdditionalSetup.ps1"
    }

    if (-not $bccontainerHelperConfig.useSslForWinRmSession) {
        try {
            [xml]$conf = winrm get winrm/config/client -format:pretty
            $trustedHosts = @($conf.Client.TrustedHosts.Split(','))
            if (-not $trustedHosts) {
                $trustedHosts = @()
            }
            $isTrusted = $trustedHosts | Where-Object { $containerName -like $_ }
            if (!($isTrusted)) {
                if (!$isAdministrator) {
                    Write-Host "$containerName is not a trusted host. You need to get an administrator to add $containerName to the trusted winrm hosts on your machine"
                }
                else {
                    Write-Host "Adding $containerName to trusted hosts ($($trustedHosts -join ','))"
                    $trustedHosts += $containerName
                    winrm set winrm/config/client "@{TrustedHosts=""$($trustedHosts -join ',')""}" | Out-Null
                }
            }
            if ($conf.Client.AllowUnencrypted -eq 'false') {
                if (!$isAdministrator) {
                    Write-Host "Unencrypted communication is not allowed. You need to get an administrator to allow unencrypted communication"
                }
                else {
                    Write-Host "Allow unencrypted communication"
                    winrm set winrm/config/client '@{AllowUnencrypted="true"}' | Out-Null
                }
            }
        }
        catch {
            Write-Host "Unexpected error when checking winrm configuration, you might not be able to connect to the container using winrm unencrypted"
        }
    }
    }

    if ($includeCSide) {
        $programFilesFolder = Join-Path $containerFolder "Program Files"
        New-Item -Path $programFilesFolder -ItemType Directory -ErrorAction Ignore | Out-Null

        # Clear modified flag on all objects
        (@'
if ($restartingInstance -eq $false -and $databaseServer -eq "localhost" -and $databaseInstance -eq "SQLEXPRESS") {
    sqlcmd -S 'localhost\SQLEXPRESS' -d $DatabaseName -Q "update [dbo].[Object] SET [Modified] = 0" | Out-Null
}
'@) | Add-Content -Path "$myfolder\AdditionalSetup.ps1"

        if (Test-Path $programFilesFolder) {
            Remove-Item $programFilesFolder -Force -Recurse -ErrorAction Ignore
        }
        New-Item $programFilesFolder -ItemType Directory -ErrorAction Ignore | Out-Null
        
        if ($useTraefik) {
            $winclientServer = $containerName
        }
        else {
            $winclientServer = '$PublicDnsName'
        }

        ('
if (!(Test-Path "c:\navpfiles\*")) {
    Copy-Item -Path "C:\Program Files (x86)\Microsoft Dynamics NAV\*" -Destination "c:\navpfiles" -Recurse -Force -ErrorAction Ignore
    $destFolder = (Get-Item "c:\navpfiles\*\RoleTailored Client").FullName
    $ClientUserSettingsFileName = "$runPath\ClientUserSettings.config"
    [xml]$ClientUserSettings = Get-Content $clientUserSettingsFileName
    $clientUserSettings.SelectSingleNode("//configuration/appSettings/add[@key=""Server""]").value = "'+$winclientServer+'"
    $clientUserSettings.SelectSingleNode("//configuration/appSettings/add[@key=""ServerInstance""]").value=$ServerInstance
    if ($multitenant) {
        $clientUserSettings.SelectSingleNode("//configuration/appSettings/add[@key=""TenantId""]").value="$TenantId"
    }
    if ($clientUserSettings.SelectSingleNode("//appSettings/add[@key=""ServicesCertificateValidationEnabled""]") -ne $null) {
        $clientUserSettings.SelectSingleNode("//configuration/appSettings/add[@key=""ServicesCertificateValidationEnabled""]").value="false"
    }
    if ($clientUserSettings.SelectSingleNode("//appSettings/add[@key=""ClientServicesCertificateValidationEnabled""]") -ne $null) {
        $clientUserSettings.SelectSingleNode("//configuration/appSettings/add[@key=""ClientServicesCertificateValidationEnabled""]").value="false"
    }
    $clientUserSettings.SelectSingleNode("//configuration/appSettings/add[@key=""ClientServicesPort""]").value="$publicWinClientPort"
    $acsUri = "$federationLoginEndpoint"
    if ($acsUri -ne "") {
        if (!($acsUri.ToLowerInvariant().Contains("%26wreply="))) {
            $acsUri += "%26wreply=$publicWebBaseUrl"
        }
    }
    $clientUserSettings.SelectSingleNode("//configuration/appSettings/add[@key=""ACSUri""]").value = "$acsUri"
    $clientUserSettings.SelectSingleNode("//configuration/appSettings/add[@key=""DnsIdentity""]").value = "$dnsIdentity"
    $clientUserSettings.SelectSingleNode("//configuration/appSettings/add[@key=""ClientServicesCredentialType""]").value = "$Auth"
    $clientUserSettings.Save("$destFolder\ClientUserSettings.config")
}
') | Add-Content -Path "$myfolder\AdditionalSetup.ps1"
    }

    if ($assignPremiumPlan -and !$restoreBakFolder -and !$skipDatabase) {
        if (!(Test-Path -Path "$myfolder\SetupNavUsers.ps1")) {
            ('# Invoke default behavior
. "c:\run\SetupNavUsers.ps1"
') | Set-Content -Path "$myfolder\SetupNavUsers.ps1"
        }
     
        if ($version.Major -ge 15) {
            $userPlanTableName = 'User Plan$63ca2fa4-4f03-4f2b-a480-172fef340d3f'
        }
        else {
            $userPlanTableName = 'User Plan'
        }

        $fullUserLicenseType = "FullUser"
        if ($version.Major -ge 29) {
            $fullUserLicenseType = "Full User"
        }
        
        ('
Get-NavServerUser -serverInstance $ServerInstance -tenant default |? LicenseType -eq "'+$fullUserLicenseType+'" | ForEach-Object {
    $UserId = $_.UserSecurityId
    Write-Host "Assign Premium plan for $($_.Username)"
    $dbName = $DatabaseName
    if ($multitenant) {
        $dbName = $TenantId
    }
    $userPlanTableName = '''+$userPlanTableName+'''
    Invoke-Sqlcmd -ErrorAction Ignore -ServerInstance ''localhost\SQLEXPRESS'' -Query "USE [$DbName]
    INSERT INTO [dbo].[$userPlanTableName] ([Plan ID],[User Security ID]) VALUES (''{8e9002c0-a1d8-4465-b952-817d2948e6e2}'',''$userId'')"
}
') | Add-Content -Path "$myfolder\SetupNavUsers.ps1"
    }

    if ($useSSL) {
        $parameters += "--env useSSL=Y"
    } else {
        $parameters += "--env useSSL=N"
    }

    if ($includeCSide) {
        $parameters += "--volume ""$($programFilesFolder):C:\navpfiles"""
    }

    if ("$dvdPath" -ne "") {
        $parameters += getVolumeMountParameter -volumes $allVolumes -hostPath $dvdPath -containerPath "C:\NAVDVD"
    }

    if (!(Test-Path -Path "$myfolder\SetupVariables.ps1")) {
        ('# Invoke default behavior
. "c:\run\SetupVariables.ps1"
') | Set-Content -Path "$myfolder\SetupVariables.ps1"
    }
    if (!(Test-Path -Path "$myfolder\HelperFunctions.ps1")) {
        ('# Invoke default behavior
. "c:\run\HelperFunctions.ps1"
') | Set-Content -Path "$myfolder\HelperFunctions.ps1"
    }

    if ($version.Major -ge 24 -and $genericTag -eq [System.Version]"1.0.2.15") {
        Download-File -source "https://raw.githubusercontent.com/microsoft/nav-docker/98c0702dbd607580880a3c9248cd76591868447d/generic/Run/Prompt.ps1" -destinationFile (Join-Path $myFolder "Prompt.ps1")
    }

    if ($version.Major -ge 24 -and $genericTag -lt [System.Version]"1.0.2.17") {
        Download-File -source "https://raw.githubusercontent.com/microsoft/nav-docker/4123cbcd197df57a5d94fa15b976356c11f4bcac/generic/Run/240/navinstall.ps1" -destinationFile (Join-Path $myFolder "navinstall.ps1")
        Download-File -source "https://raw.githubusercontent.com/microsoft/nav-docker/4123cbcd197df57a5d94fa15b976356c11f4bcac/generic/Run/navstart.ps1" -destinationFile (Join-Path $myFolder "navstart.ps1")
    }

    if ($version.Major -ge 15 -and $version.Major -le 18 -and $genericTag -ge [System.Version]"1.0.2.15") {
        Write-Host "Patching container to install ASP.NET Core 1.1"
        Download-File -source "https://download.microsoft.com/download/6/F/B/6FB4F9D2-699B-4A40-A674-B7FF41E0E4D2/DotNetCore.1.0.7_1.1.4-WindowsHosting.exe" -destinationFile (Join-Path $myFolder "dotnetcore.exe")
        ('
if (!(dotnet --list-runtimes | Where-Object { $_ -like "Microsoft.NetCore.App 1.1.*" })) { Write-Host "Installing ASP.NET Core 1.1"; start-process -Wait -FilePath "c:\run\my\dotnetcore.exe" -ArgumentList /quiet }
') | Add-Content -Path "$myfolder\HelperFunctions.ps1"
    }

    if ($genericTag -lt [System.Version]"1.0.2.21") {
        @'
# Patch Microsoft.PowerShell.Archive to use en-US UI Culture (see https://github.com/PowerShell/Microsoft.PowerShell.Archive/pull/46)
$psarchiveModule = 'C:\Windows\System32\WindowsPowerShell\v1.0\Modules\Microsoft.PowerShell.Archive\Microsoft.PowerShell.Archive.psm1'
if (Test-Path $psarchiveModule) {
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule((whoami),'Modify', 'Allow')
    $acl = Get-Acl -Path $psarchiveModule; $acl.AddAccessRule($rule); Set-Acl -Path $psarchiveModule -AclObject $acl
    Set-Content -encoding utf8 -path $psarchiveModule -value (Get-Content -encoding utf8 -raw -path $psarchiveModule).Replace("`r`nImport-LocalizedData  LocalizedData -filename ArchiveResources`r`n","`r`nImport-LocalizedData LocalizedData -filename ArchiveResources -UICulture 'en-US'`r`n")
}
'@ | Add-Content -Path "$myfolder\SetupVariables.ps1"
    }

    if ($updateHosts) {
        Copy-Item -Path (Join-Path $PSScriptRoot "updatehosts.ps1") -Destination (Join-Path $myfolder "updatehosts.ps1") -Force
        $parameters += "--volume ""c:\windows\system32\drivers\etc:C:\driversetc"""
        ('
. (Join-Path $PSScriptRoot "updatehosts.ps1") -hostsFile "c:\driversetc\hosts" -theHostname "$hostname" -theIpAddress $ip
if ($multitenant) {
    $dotidx = $hostname.indexOf(".")
    if ($dotidx -eq -1) { $dotidx = $hostname.Length }
    Get-NavTenant -serverInstance $serverInstance | ForEach-Object {
        $tenantHostname = $hostname.insert($dotidx,"-$($_.Id)")
        . (Join-Path $PSScriptRoot "updatehosts.ps1") -hostsFile "c:\driversetc\hosts" -theHostname $tenantHostname -theIpAddress $ip
        . (Join-Path $PSScriptRoot "updatehosts.ps1") -hostsFile "c:\windows\system32\drivers\etc\hosts" -theHostname $tenantHostname -theIpAddress $ip
    }
}
') | Add-Content -Path "$myfolder\AdditionalOutput.ps1"

    ('
. (Join-Path $PSScriptRoot "updatehosts.ps1") -hostsFile "c:\driversetc\hosts"
') | Add-Content -Path "$myfolder\SetupVariables.ps1"

    }
    else {

        Copy-Item -Path (Join-Path $PSScriptRoot "updatehosts.ps1") -Destination (Join-Path $myfolder "updatecontainerhosts.ps1") -Force
        ('
if ($multitenant) {
    $dotidx = $hostname.indexOf(".")
    if ($dotidx -eq -1) { $dotidx = $hostname.Length }
    Get-NavTenant -serverInstance $serverInstance | ForEach-Object {
        $tenantHostname = $hostname.insert($dotidx,"-$($_.Id)")
        . (Join-Path $PSScriptRoot "updatecontainerhosts.ps1") -hostsFile "c:\windows\system32\drivers\etc\hosts" -theHostname $tenantHostname -theIpAddress "127.0.0.1"
    }
}
') | Add-Content -Path "$myfolder\AdditionalOutput.ps1"
    ('
. (Join-Path $PSScriptRoot "updatecontainerhosts.ps1")
') | Add-Content -Path "$myfolder\SetupVariables.ps1"

    }

    if ($useTraefik) {
        $restPart = "/$($containerName)rest" 
        $soapPart = "/$($containerName)soap"
        $devPart = "/$($containerName)dev"
        $snapPart = "/$($containerName)snap"
        $dlPart = "/$($containerName)dl"
        $webclientPart = "/$containerName"

        $baseUrl = "https://$publicDnsName"
        $restUrl = $baseUrl + $restPart
        $soapUrl = $baseUrl + $soapPart
        $webclientUrl = $baseUrl + $webclientPart
        $devUrl = $baseUrl + $devPart
        $snapUrl = $baseUrl + $snapPart
        $dlUrl = $baseUrl + $dlPart

        $customNavSettings += @("PublicODataBaseUrl=$restUrl/odata","PublicSOAPBaseUrl=$soapUrl/ws","PublicWebBaseUrl=$webclientUrl")

        if ($version.Major -ge 15) {
            if (Test-Path "$myfolder\serviceSettings.ps1") {
                . "$myfolder\serviceSettings.ps1"
            }
            else {
                $ServerInstance = "BC"
            }
        }
        else {
            $ServerInstance = "NAV"
        }

        $webclientRule="PathPrefix:$webclientPart"
        $soapRule="PathPrefix:$($soapPart);ReplacePathRegex: ^$($soapPart)(.*) /$ServerInstance`$1"
        $restRule="PathPrefix:$($restPart);ReplacePathRegex: ^$($restPart)(.*) /$ServerInstance`$1"
        $devRule="PathPrefix:$($devPart);ReplacePathRegex: ^$($devPart)(.*) /$ServerInstance`$1"
        $snapRule="PathPrefix:$($snapPart);ReplacePathRegex: ^$($snapPart)(.*) /$ServerInstance`$1"
        $dlRule="PathPrefixStrip:$($dlPart)"

        $webPort = "443"
        if ($forceHttpWithTraefik) {
            $webPort = "80"
        }
        $traefikProtocol = "https"
        if ($forceHttpWithTraefik) {
            $traefikProtocol = "http"
        }

        if ($bcContainerHelperConfig.TraefikUseDnsNameAsHostName) {
            $traefikHostname = $publicDnsName.Split(".")[0]
            $additionalParameters += @("--hostname $traefikHostname")
        }

        $additionalParameters += @("-e webserverinstance=$containerName",
                                   "-e publicdnsname=$publicDnsName", 
                                   "-l `"traefik.protocol=$traefikProtocol`"",
                                   "-l `"traefik.web.frontend.rule=$webclientRule`"", 
                                   "-l `"traefik.web.port=$webPort`"",
                                   "-l `"traefik.soap.frontend.rule=$soapRule`"", 
                                   "-l `"traefik.soap.port=7047`"",
                                   "-l `"traefik.rest.frontend.rule=$restRule`"", 
                                   "-l `"traefik.rest.port=7048`"",
                                   "-l `"traefik.dev.frontend.rule=$devRule`"", 
                                   "-l `"traefik.dev.port=7049`"",
                                   "-l `"traefik.snap.frontend.rule=$snapRule`"", 
                                   "-l `"traefik.snap.port=7083`"",
                                   "-l `"traefik.dl.frontend.rule=$dlRule`"", 
                                   "-l `"traefik.dl.port=8080`"",
                                   "-l `"traefik.dl.protocol=http`"",
                                   "-l `"traefik.enable=true`"",
                                   "-l `"traefik.frontend.entryPoints=https`""
        )

        ("
if (-not `$restartingInstance) {
    Add-Content -Path 'c:\run\ServiceSettings.ps1' -Value '`$WebServerInstance = ""$containerName""'
}
") | Add-Content -Path "$myfolder\AdditionalOutput.ps1"
    }

    $containerContainerFolder = Join-Path $bcContainerHelperConfig.ContainerHelperFolder "Extensions\$containerName"

    ("
if (-not `$restartingInstance) {
    if (Test-Path -Path ""$containerContainerFolder\*.vsix"") {
        Remove-Item -Path 'C:\Run\*.vsix'
        Copy-Item -Path ""$containerContainerFolder\*.vsix"" -Destination 'C:\Run' -force
        if (Test-Path 'C:\inetpub\wwwroot\http' -PathType Container) {
            Remove-Item -Path 'C:\inetpub\wwwroot\http\*.vsix'
            Copy-Item -Path ""$containerContainerFolder\*.vsix"" -Destination 'C:\inetpub\wwwroot\http' -force
        }
    }
    else {
        Copy-Item -Path 'C:\Run\*.vsix' -Destination ""$containerContainerFolder"" -force
    }
    Copy-Item -Path 'C:\Run\*.cer' -Destination ""$containerContainerFolder"" -force
}
") | Add-Content -Path "$myfolder\AdditionalOutput.ps1"

    if ($customNavSettings) {
        $customNavSettingsAdded = $false
        $cnt = $additionalParameters.Count-1
        if ($cnt -ge 0) {
            0..$cnt | ForEach-Object {
                $idx = $additionalParameters[$_].ToLowerInvariant().IndexOf('customnavsettings=')
                if ($idx -gt 0) {
                    $additionalParameters[$_] = "$($additionalParameters[$_]),$([string]::Join(',',$customNavSettings))"
                    $customNavSettingsAdded = $true
                }
            }
        }
        if (-not $customNavSettingsAdded) {
            $additionalParameters += @("--env customNavSettings=$([string]::Join(',',$customNavSettings))")
        }
    }

    if ($customWebSettings) {
        $customWebSettingsAdded = $false
        $cnt = $additionalParameters.Count-1
        if ($cnt -ge 0) {
            0..$cnt | ForEach-Object {
                $idx = $additionalParameters[$_].ToLowerInvariant().IndexOf('customwebsettings=')
                if ($idx -gt 0) {
                    $additionalParameters[$_] = "$($additionalParameters[$_]),$([string]::Join(',',$customWebSettings))"
                    $customWebSettingsAdded = $true
                }
            }
        }
        if (-not $customWebSettingsAdded) {
            $additionalParameters += @("--env customWebSettings=$([string]::Join(',',$customWebSettings))")
        }
    }

    #Write-Host "Parameters:"
    #$Parameters | ForEach-Object { if ($_) { Write-Host "$_" } }

    if ($additionalParameters) {
        Write-Host "Additional Parameters:"
        $additionalParameters | ForEach-Object { if ($_) { Write-Host "$_" } }
    }

    Write-Host "Files in $($myfolder):"
    get-childitem -Path $myfolder | ForEach-Object { Write-Host "- $($_.Name)" }

    Write-Host "Creating container $containerName from image $imageName"

    $sharedEncryptionKeyFile = ""
    $containerEncryptionKeyFile = Join-Path $myFolder "DynamicsNAV.key"
    $encryptionKeyExists = Test-Path $containerEncryptionKeyFile

    $passwordKeyFile = "$myfolder\aes.key"
    $passwordKey = New-Object Byte[] 16
    [Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($passwordKey)
    $containerPasswordKeyFile = "c:\run\my\aes.key"
    try {
        Set-Content -Path $passwordKeyFile -Value $passwordKey
        $encPassword = ConvertFrom-SecureString -SecureString $credential.Password -Key $passwordKey
        
        $parameters += @(
                         "--env securePassword=$encPassword",
                         "--env passwordKeyFile=""$containerPasswordKeyFile""",
                         "--env removePasswordKeyFile=Y"
                        )

        if ($databaseCredential -ne $null -and $databaseCredential -ne [System.Management.Automation.PSCredential]::Empty) {

            $encDatabasePassword = ConvertFrom-SecureString -SecureString $databaseCredential.Password -Key $passwordKey
            $parameters += @(
                             "--env databaseUsername=$($databaseCredential.UserName)",
                             "--env databaseSecurePassword=$encDatabasePassword"
                             "--env encryptionSecurePassword=$encDatabasePassword"
                            )

            if ("$databaseServer" -ne "" -and $bcContainerHelperConfig.useSharedEncryptionKeys -and !$encryptionKeyExists) {
                $sharedEncryptionKeyFile = Join-Path $bcContainerHelperConfig.hostHelperFolder "EncryptionKeys\$(-join [security.cryptography.sha256managed]::new().ComputeHash([Text.Encoding]::Utf8.GetBytes(([System.Runtime.InteropServices.Marshal]::PtrToStringBSTR([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($databaseCredential.Password))))).ForEach{$_.ToString("X2")})\DynamicsNAV-v$($version.Major).key"
                if (Test-Path $sharedEncryptionKeyFile) {
                    Write-Host "Using Shared Encryption Key file"
                    Copy-Item -Path $sharedEncryptionKeyFile -Destination $containerEncryptionKeyFile
                }
                elseif((Test-Path ($sharedEncryptionKeyFile | Split-Path -Parent)) -eq $false) {
                    New-Item -Path ($sharedEncryptionKeyFile | Split-Path -Parent) -ItemType Directory | Out-Null
                }
            }
        }
        
        $parameters += $additionalParameters
    
        # $parameters | Out-host

        if (!(DockerDo -accept_eula -accept_outdated:$accept_outdated -detach -imageName $imageName -parameters $parameters)) {
            return
        }
        Wait-BcContainerReady $containerName -timeout $timeout -startlog ""

        if ($filesOnly -and $vsixFile) {
            Invoke-ScriptInBcContainer -containerName $containerName -scriptBlock { Param($vsixFile)
                Remove-Item -Path 'C:\Run\*.vsix'
                Copy-Item -Path $vsixFile -Destination 'C:\Run' -force
            } -argumentList (Get-BcContainerPath -containerName $containerName -path $vsixFile)
        }

        if ($sharedEncryptionKeyFile -and !(Test-Path $sharedEncryptionKeyFile)) {
            Write-Host "Storing Container Encryption Key file"
            Copy-Item -Path $containerEncryptionKeyFile -Destination $sharedEncryptionKeyFile
        }
    } finally {
        Remove-Item -Path $passwordKeyFile -Force -ErrorAction Ignore
    }

    Write-Host "Reading CustomSettings.config from $containerName"
    $customConfig = Get-BcContainerServerConfiguration -ContainerName $containerName
    if ($customConfig.ServerInstance) {
        # Only if not -filesOnly

        if ($SqlServerMemoryLimit -and $customConfig.databaseServer -eq "localhost" -and $customConfig.databaseInstance -eq "SQLEXPRESS") {
            Write-Host "Set SQL Server memory limit to $SqlServerMemoryLimit MB"
            Invoke-ScriptInBCContainer -containerName $containerName -scriptblock { Param($SqlServerMemoryLimit)
                Invoke-Sqlcmd -ServerInstance 'localhost\SQLEXPRESS' -Query "USE master EXEC sp_configure 'show advanced options', 1 RECONFIGURE WITH OVERRIDE;"
                Invoke-Sqlcmd -ServerInstance 'localhost\SQLEXPRESS' -Query "USE master EXEC sp_configure 'max server memory', $SqlServerMemoryLimit RECONFIGURE WITH OVERRIDE;"
                Invoke-Sqlcmd -ServerInstance 'localhost\SQLEXPRESS' -Query "USE master EXEC sp_configure 'show advanced options', 0 RECONFIGURE WITH OVERRIDE;"
            } -argumentList ($SqlServerMemoryLimit)
        }
    
        if ($addFontsFromPath) {
            Add-FontsToBcContainer -containerName $containerName -path $addFontsFromPath
        }
    
        if ($featureKeys) {
            Set-BcContainerFeatureKeys -containerName $containerName -featureKeys $featureKeys
        }
    
        if ("$TimeZoneId" -ne "") {
            Write-Host "Set TimeZone in Container to $TimeZoneId"
            Invoke-ScriptInBcContainer -containerName $containerName -scriptblock { Param($TimeZoneId)
                $OldTimeZoneId = (Get-TimeZone).Id
                try { 
                    if ($OldTimeZoneId -ne $TimeZoneId) { 
                        Set-TimeZone -ID $TimeZoneId
                    }
                }
                catch {
                    Write-Host -ForegroundColor Yellow "WARNING: Unable to set TimeZone to $TimeZoneId, TimeZone is $OldTimeZoneId"
                }
            } -argumentList $TimeZoneId
        }
        if ($setServiceTierUserLocale) {
            Write-Host "Set locale for Service Tier User to $locale and restart Service Tier"
            docker exec --user "NT AUTHORITY\SYSTEM" $containerName powershell.exe "set-culture '$locale'; . 'c:\run\prompt.ps1' -silent; . 'c:\run\serviceSettings.ps1'; Set-NavServerInstance -ServerInstance `$serverInstance -restart"
        }
    
        if ($useSSL -and $installCertificateOnHost) {
            $certPath = Join-Path $containerFolder "certificate.cer"
            if (Test-Path $certPath) {
                try {
                    Write-Host "Importing certificate in host's certificate store"
                    if ($isPsCore) {
                        $params = @{ "FilePath" = "pwsh" }
                    }
                    else {
                        $params = @{ "FilePath"  = "powershell" }
                    }
                    if (!$isAdministrator) {
                        $params += @{ "Verb" = "runAs" }
                    }
                    $scriptblock = { 
                        Param($certPath, $containerFolder)
                        $cert = Import-Certificate -FilePath $certPath -CertStoreLocation "cert:\LocalMachine\Root"
                        if ($cert) {
                            Write-Host "Certificate with thumbprint $($cert.Thumbprint) imported successfully"
                            Set-Content -Path (Join-Path $containerFolder "thumbprint.txt") -Value "$($cert.Thumbprint)"
                        }
                    }
                    Start-Process @params -ArgumentList "-command & {$scriptBlock} -certPath '$certPath' -containerFolder '$containerFolder'" -Wait -PassThru | Out-Null
                }
                catch {
                    Write-Host -ForegroundColor Yellow "Unable to import certificate $certPath in Trusted Root Certification Authorities, you will need to do this manually"
                }
            }
        }
    
        if ($shortcuts -ne "None") {
                Write-Host "Creating Desktop Shortcuts for $containerName"
                $exePath = "C:\Program Files\Internet Explorer\iexplore.exe, 3"
                try {
                    $ProgramId = (Get-ItemProperty HKCU:\Software\Microsoft\windows\Shell\Associations\UrlAssociations\http\UserChoice).Progid
                    $key = "HKLM:\SOFTWARE\Classes\$ProgramId\shell\open\command"
                    $tempPath = (Get-ItemProperty -Path $key)."(default)" -replace " *--.*", ""
                    $tempPath = $tempPath.Replace("`"", "")
                    if ($tempPath -and (Test-Path $tempPath -PathType Leaf)) { $exePath = $tempPath }
                }
                catch {}

                if (-not [string]::IsNullOrEmpty($customConfig.PublicWebBaseUrl)) {
                    $webClientUrl = $customConfig.PublicWebBaseUrl
                    if ($multitenant) {
                        $webClientUrl += "?tenant=default"
                    }
                    New-DesktopShortcut -Name "$containerName Web Client" -TargetPath "$webClientUrl" -IconLocation $exePath -Shortcuts $shortcuts
                    if ($includeTestToolkit) {
                        if ($version -ge [Version]("15.0.35528.0")) {
                            $pageno = 130451
                        }
                        else {
                            $pageno = 130401
                        }
    
                        if ($webClientUrl.Contains('?')) {
                            $webClientUrl += "&page="
                        }
                        else {
                            $webClientUrl += "?page="
                        }
                        New-DesktopShortcut -Name "$containerName Test Tool" -TargetPath "$webClientUrl$pageno" -IconLocation $exePath -Shortcuts $shortcuts
                        if ($includePerformanceToolkit) {
                            New-DesktopShortcut -Name "$containerName Performance Tool" -TargetPath "$($webClientUrl)149000" -IconLocation $exePath -Shortcuts $shortcuts
                    }
                }
            }
            
            $vs = "Business Central"
            if ($version.Major -le 14) {
                $vs = "NAV"
            }
            $cmdPrompt = "/S /K ""prompt [$($containerName.ToUpperInvariant())] `$p`$g & echo Welcome to the $vs Container Command prompt & echo Microsoft Windows Version $($containerOsVersion.ToString())"
            $psPrompt = """function prompt {'[$($containerName.ToUpperInvariant())] PS '+`$executionContext.SessionState.Path.CurrentLocation+('>'*(`$nestedPromptLevel+1))+' '}; Write-Host 'Welcome to the $vs Container PowerShell prompt'; Write-Host 'Microsoft Windows Version $($containerOsVersion.ToString())'; "+'Write-Host "Windows PowerShell Version $($PSVersionTable.psversion.ToString())"; Write-Host; . "c:\run\prompt.ps1" -silent"'

            New-DesktopShortcut -Name "$containerName Command Prompt" -TargetPath "CMD.EXE" -Arguments "/C docker.exe exec -it $containerName cmd $cmdPrompt" -Shortcuts $shortcuts
            $psname = "PowerShell"
            if ($version.Major -ge 24) {
                New-DesktopShortcut -Name "$containerName $psname Prompt" -TargetPath "CMD.EXE" -Arguments "/C docker.exe exec -it $containerName pwsh -noexit -command $psPrompt" -Shortcuts $shortcuts
                $psname = "PS5"
            }
            New-DesktopShortcut -Name "$containerName $psname Prompt" -TargetPath "CMD.EXE" -Arguments "/C docker.exe exec -it $containerName powershell -noexit $psPrompt" -Shortcuts $shortcuts
        }

        if ($version -eq [System.Version]"14.10.40471.0") {
            Write-Host "Patching Microsoft.Dynamics.Nav.Ide.psm1 in container due to issue #859"
            $idepsm = Join-Path $containerFolder "14.10.40471.0-Patch-Microsoft.Dynamics.Nav.Ide.psm1"
            Download-File -sourceUrl 'https://bcartifacts-exdbf9fwegejdqak.b02.azurefd.net/patch/14.10.40471.0/Microsoft.Dynamics.Nav.Ide.psm1' -destinationFile $idepsm
            Invoke-ScriptInBcContainer -containerName $containerName -scriptblock { Param($idepsm)
                Copy-Item -Path $idepsm -Destination 'C:\Program Files (x86)\Microsoft Dynamics NAV\140\RoleTailored Client\Microsoft.Dynamics.Nav.Ide.psm1' -Force
            } -argumentList (Get-BcContainerPath -containerName $containerName -path $idepsm)
            Remove-BcContainerSession -containerName $containerName
        }
    
        if ((($version -eq [System.Version]"16.0.11240.12076") -or ($version -eq [System.Version]"16.0.11240.12085")) -and $devCountry -ne "W1") {
            $url = "https://bcartifacts-exdbf9fwegejdqak.b02.azurefd.net/patch/16.0.11240.12076/$($devCountry.ToUpper()).zip"
            Write-Host "Downloading new test apps for this version from $url"
            $zipName = Join-Path $containerFolder "16.0.11240.12076-$devCountry-Tests-Patch"
            Download-File -sourceUrl $url -destinationFile "$zipName.zip"
            Write-Host "Extracting new test apps for this version " -NoNewline
            Expand-7zipArchive -Path "$zipName.zip" -DestinationPath $zipname
            Write-Host "Patching .app files in C:\Applications\BaseApp\Test due to issue #925"
            Invoke-ScriptInBcContainer -containerName $containerName -scriptblock { Param($zipName, $devCountry)
                Copy-Item -Path (Join-Path $zipName "$devCountry\*.app") -Destination "c:\Applications\BaseApp\Test" -Force
            } -argumentList (Get-BcContainerPath -containerName $containerName -path $zipName), $devcountry
        }
    
        $sqlCredential = $databaseCredential
        if ($sqlCredential -eq $null -and $auth -eq "NavUserPassword") {
            $sqlCredential = New-Object System.Management.Automation.PSCredential ('sa', $credential.Password)
        }
    
        if ($restoreBakFolder) {
            if ($multitenant) {
                $dbs = Get-ChildItem -Path $bakFolder -Filter "*.bak"
                $tenants = $dbs | Where-Object { $_.Name -ne "app.bak" } | ForEach-Object { $_.BaseName }
                Invoke-ScriptInBcContainer -containerName $containerName -scriptblock {
                    Set-NAVServerConfiguration -ServerInstance $ServerInstance -KeyName "Multitenant" -KeyValue "true" -ApplyTo ConfigFile
                }
                Restore-DatabasesInBcContainer -containerName $containerName -bakFolder $bakFolder -tenant $tenants -sqlTimeout $sqlTimeout
            }
        }
        else {
            if ($enableSymbolLoading) {
                # Unpublish symbols when running hybrid development
                Invoke-ScriptInBcContainer -containerName $containerName -scriptblock {
                    # Unpublish only, when Apps when present
                    # Due to bug in 14.x - do NOT remove application symbols - they are used by some system functionality
                    #Get-NavAppInfo -ServerInstance $ServerInstance -Name "Application" -Publisher "Microsoft" -SymbolsOnly | Unpublish-NavApp
                    Get-NavAppInfo -ServerInstance $ServerInstance -Name "Test" -Publisher "Microsoft" -SymbolsOnly | Unpublish-NavApp
                }
            }
        
            if ($includeTestToolkit) {
                Import-TestToolkitToBcContainer `
                    -containerName $containerName `
                    -sqlCredential $sqlCredential `
                    -includeTestLibrariesOnly:$includeTestLibrariesOnly `
                    -includeTestFrameworkOnly:$includeTestFrameworkOnly `
                    -includePerformanceToolkit:$includePerformanceToolkit `
                    -doNotUseRuntimePackages:$doNotUseRuntimePackages
            }
        }
    
        if ($includeCSide) {
            $winClientFolder = (Get-Item "$programFilesFolder\*\RoleTailored Client").FullName
            New-DesktopShortcut -Name "$containerName Windows Client" -TargetPath "$WinClientFolder\Microsoft.Dynamics.Nav.Client.exe" -Arguments "-settings:ClientUserSettings.config" -Shortcuts $shortcuts
            New-DesktopShortcut -Name "$containerName WinClient Debugger" -TargetPath "$WinClientFolder\Microsoft.Dynamics.Nav.Client.exe" -Arguments "-settings:ClientUserSettings.config ""DynamicsNAV:////debug""" -Shortcuts $shortcuts
    
            $databaseInstance = $customConfig.DatabaseInstance
            $databaseName = $customConfig.DatabaseName
            $databaseServer = $customConfig.DatabaseServer
            if ($databaseServer -eq "host.containerhelper.internal") {
                $databaseServer = "localhost"
                if ($databaseInstance) {
                    $databaseServer += "\$databaseInstance"
                }
            } 
            elseif ($databaseServer -eq "localhost") {
                $databaseServer = "$containerName"
                if (("$databaseInstance" -ne "") -and ("$databaseInstance" -ne "SQLEXPRESS")) {
                    $databaseServer += "\$databaseInstance"
                }
            }
            else {
                if ($databaseInstance) {
                    $databaseServer += "\$databaseInstance"
                }
            }
    
            if ($auth -eq "Windows") {
                $ntauth="1"
            } else {
                $ntauth="0"
            }
            $csideParameters = "servername=$databaseServer, Database=$databaseName, ntauthentication=$ntauth, ID=$containerName"
    
            if ($enableSymbolLoading) {
                $csideParameters += ",generatesymbolreference=1"
            }
    
            New-DesktopShortcut -Name "$containerName CSIDE" -TargetPath "$WinClientFolder\finsql.exe" -Arguments "$csideParameters" -Shortcuts $shortcuts
        }
    
        if (($includeCSide -or $includeAL) -and !$doNotExportObjectsToText) {
    
            # Include oldsyntax only if IncludeCSide is specified
            # Include newsyntax if NAV Version is greater than NAV 2017
    
            if ($includeCSide) {
                $originalFolder = Join-Path $bcContainerHelperConfig.hostHelperFolder "Extensions\Original-$navversion"
                if (!(Test-Path $originalFolder)) {
                    # Export base objects
                    Export-NavContainerObjects -containerName $containerName `
                                               -objectsFolder $originalFolder `
                                               -filter "" `
                                               -sqlCredential $sqlCredential `
                                               -ExportTo 'txt folder'
                }
            }
    
            if ($version.Major -ge 15) {
                $alFolder = Join-Path $bcContainerHelperConfig.hostHelperFolder "Extensions\Original-$navversion-al"
                if (!(Test-Path $alFolder) -or (Get-ChildItem -Path $alFolder -Recurse | Measure-Object).Count -eq 0) {
                    if (!(Test-Path $alFolder)) {
                        New-Item $alFolder -ItemType Directory | Out-Null
                    }
                    if ($version -ge [Version]("15.0.35528.0")) {
                        Invoke-ScriptInBcContainer -containerName $containerName -scriptBlock { Param($alFolder, $country)
                            [Reflection.Assembly]::LoadWithPartialName("System.IO.Compression.Filesystem") | Out-Null
                            if (Test-Path "C:\Applications.$country") {
                                $baseAppSource = @(get-childitem -Path "C:\Applications.*\*.*" -recurse -filter "Base Application.Source.zip")
                            }
                            else {
                                $baseAppSource = @(get-childitem -Path "C:\Applications\*.*" -recurse -filter "Base Application.Source.zip")
                            }
                            if ($baseAppSource.Count -ne 1) {
                                throw "Unable to locate Base Application.Source.zip"
                            }
                            Write-Host "Extracting $($baseAppSource[0].FullName)"
                            [System.IO.Compression.ZipFile]::ExtractToDirectory($baseAppSource[0].FullName, $alFolder)
                        } -argumentList (Get-BCContainerPath -containerName $containerName -path $alFolder), $devCountry
                    }
                    else {
                        $appFile = Join-Path $bcContainerHelperConfig.hostHelperFolder "Extensions\BaseApp-$navVersion.app"
                        $appName = "Base Application"
                        if ($version -lt [Version]("15.0.35659.0")) {
                            $appName = "BaseApp"
                        }
                        Get-BcContainerApp -containerName $containerName `
                                            -publisher Microsoft `
                                            -appName $appName `
                                            -appFile $appFile `
                                            -credential $credential
        
                        $appFolder = Join-Path $bcContainerHelperConfig.hostHelperFolder "Extensions\BaseApp-$navVersion"
                        Extract-AppFileToFolder -appFilename $appFile -appFolder $appFolder
        
                        'layout','src','translations' | ForEach-Object {
                            if (Test-Path (Join-Path $appFolder $_)) {
                                Copy-Item -Path (Join-Path $appFolder $_) -Destination $alFolder -Recurse -Force
                            }
                        }
        
                        Remove-Item -Path $appFolder -Recurse -Force
                        Remove-Item -Path $appFile -Force
                    }
                }
            }
            elseif ($version.Major -gt 10) {
                $originalFolder = Join-Path $bcContainerHelperConfig.hostHelperFolder "Extensions\Original-$navversion-newsyntax"
                if (!(Test-Path $originalFolder)) {
                    # Export base objects as new syntax
                    Export-NavContainerObjects -containerName $containerName `
                                               -objectsFolder $originalFolder `
                                               -filter "" `
                                               -sqlCredential $sqlCredential `
                                               -ExportTo 'txt folder (new syntax)'
                }
                if ($version.Major -ge 14 -and $includeAL) {
                    $alFolder = Join-Path $bcContainerHelperConfig.hostHelperFolder "Extensions\Original-$navversion-al"
                    if ($runTxt2AlInContainer -ne $containerName) {
                        Write-Host "Using container $runTxt2AlInContainer to convert .txt to .al"
                        if (Test-Path $alFolder) {
                            Write-Host "Removing existing AL folder $alFolder"
                            Remove-Item -Path $alFolder -Recurse -Force
                        }
                    }
                    if (!(Test-Path $alFolder)) {
                        $dotNetAddInsPackage = Join-Path $bcContainerHelperConfig.hostHelperFolder "Extensions\$containerName\coredotnetaddins.al"
                        Copy-Item -Path (Join-Path $PSScriptRoot "..\ObjectHandling\coredotnetaddins.al") -Destination $dotNetAddInsPackage -Force
                        if ($runTxt2AlInContainer -ne $containerName) {
                            Write-Host "Using container $runTxt2AlInContainer to convert .txt to .al"
                        }
                        Convert-Txt2Al -containerName $runTxt2AlInContainer -myDeltaFolder $originalFolder -myAlFolder $alFolder -startId 50100 -dotNetAddInsPackage $dotNetAddInsPackage
                    }
                }
            }
        }
    }
    
    if ($Version.Major -ge 22) {
        Write-Host "Cleanup old dotnet core assemblies"
        Invoke-ScriptInBcContainer -containerName $containerName -scriptblock {
            Remove-Item -Path 'C:\Program Files\dotnet\shared\Microsoft.NETCore.App\1.0.*' -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path 'C:\Program Files\dotnet\shared\Microsoft.NETCore.App\1.1.*' -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path 'C:\Program Files\dotnet\shared\Microsoft.NETCore.App\5.0.*' -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path 'C:\Program Files\dotnet\shared\Microsoft.AspNetCore.App\5.0.*' -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    if ($Version.Major -ge 27) {
        Write-Host "Cleanup old dotnet core assemblies"
        Invoke-ScriptInBcContainer -containerName $containerName -scriptblock {
            Remove-Item -Path 'C:\Program Files\dotnet\shared\Microsoft.NETCore.App\6.0.*' -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path 'C:\Program Files\dotnet\shared\Microsoft.AspNetCore.App\6.0.*' -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    if ($includeAL) {
        $dotnetAssembliesFolder = Join-Path $containerFolder ".netPackages"
        New-Item -Path $dotnetAssembliesFolder -ItemType Directory -ErrorAction Ignore | Out-Null

        Write-Host "Creating .net Assembly Reference Folder"
        Invoke-ScriptInBcContainer -containerName $containerName -scriptblock { Param($dotnetAssembliesFolder, [System.Version] $Version)

            $serviceTierFolder = (Get-Item "C:\Program Files\Microsoft Dynamics NAV\*\Service").FullName

            $paths = @()
            if ($Version.Major -lt 22) {
                $paths += @('C:\Windows\assembly', 'C:\Windows\Microsoft.NET\assembly')
            }
            else {
                $paths += @('C:\Program Files\dotnet\Shared')
            }
            $paths += @($serviceTierFolder)

            $rtcFolder = "C:\Program Files (x86)\Microsoft Dynamics NAV\*\RoleTailored Client"
            if (Test-Path $rtcFolder -PathType Container) {
                $paths += (Get-Item $rtcFolder).FullName
            }
            $mockAssembliesPath = "C:\Test Assemblies\Mock Assemblies"
            if (Test-Path $mockAssembliesPath -PathType Container) {
                $paths += $mockAssembliesPath
            }
            if ($version.Major -lt 21) {
                $paths += "C:\Program Files (x86)\Open XML SDK"
            }

            $paths | ForEach-Object {
                Write-Host "Copying DLLs from $_ to assemblyProbingPath"
                if ($version.Major -ge 22) {
                    Copy-Item -Path $_ -filter '*.dll' -Destination $dotnetAssembliesFolder -Recurse -Force -ErrorAction SilentlyContinue
                }
                else {
                    $localPath = Join-Path $dotnetAssembliesFolder ([System.IO.Path]::GetFileName($_))
                    if (!(Test-Path $localPath)) {
                        New-Item -Path $localPath -ItemType Directory -Force | Out-Null
                    }
                    Get-ChildItem -Path $_ -Filter '*.dll' -Recurse | ForEach-Object {
                        if (!(Test-Path (Join-Path $localPath $_.Name))) {
                            Copy-Item -Path $_.FullName -Destination $localPath -Force -ErrorAction SilentlyContinue
                        }
                    }
                }
            }

            if ($version.Major -ge 22) {
                Write-Host "Removing dotnet Framework Assemblies"
                $dotnetServiceFolder = Join-Path $dotnetAssembliesFolder "Service"
                Remove-Item -Path (Join-Path $dotnetserviceFolder 'Management') -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -Path (Join-Path $dotnetserviceFolder 'SideServices') -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -Path (Join-Path $dotnetserviceFolder 'WindowsServiceInstaller') -Recurse -Force -ErrorAction SilentlyContinue
            }

            $serviceTierAddInsFolder = Join-Path $serviceTierFolder "Add-ins"
            if (!(Test-Path (Join-Path $serviceTierAddInsFolder "RTC"))) {
                if (Test-Path $RtcFolder -PathType Container) {
                    new-item -itemtype symboliclink -path $ServiceTierAddInsFolder -name "RTC" -value (Get-Item $RtcFolder).FullName | Out-Null
                }
            }

            if ($version.Major -eq 21) {
                Remove-Item -Path (Join-Path $dotnetAssembliesFolder 'assembly\DocumentFormat.OpenXml.dll') -Force -ErrorAction SilentlyContinue
            }
        } -argumentList (Get-BcContainerPath -containerName $containerName -path $dotnetAssembliesFolder), $version
    }

    if ($customConfig.ServerInstance) {
        # Only if not -filesOnly

        if (($useCleanDatabase -or $useNewDatabase) -and !$restoreBakFolder) {
            Clean-BcContainerDatabase -containerName $containerName -useNewDatabase:$useNewDatabase -credential $credential -doNotCopyEntitlements:$doNotCopyEntitlements -copyTables $copyTables
            if ($multitenant) {
                Write-Host "Switching to multitenant"
                
                Invoke-ScriptInBCContainer -containerName $containerName -scriptblock {
                
                    $customConfigFile = Join-Path (Get-Item "C:\Program Files\Microsoft Dynamics NAV\*\Service").FullName "CustomSettings.config"
                    [xml]$customConfig = [System.IO.File]::ReadAllText($customConfigFile)
                    $databaseServer = $customConfig.SelectSingleNode("//appSettings/add[@key='DatabaseServer']").Value
                    $databaseInstance = $customConfig.SelectSingleNode("//appSettings/add[@key='DatabaseInstance']").Value
                    $databaseName = $customConfig.SelectSingleNode("//appSettings/add[@key='DatabaseName']").Value
    
                    Set-NavserverInstance -ServerInstance $serverInstance -stop
                    Copy-NavDatabase -SourceDatabaseName $databaseName -DestinationDatabaseName "tenant"
                    Remove-NavDatabase -DatabaseName $databaseName
                    Write-Host "Exporting Application to $DatabaseName"
                    Invoke-sqlcmd -serverinstance "$DatabaseServer\$DatabaseInstance" -Database tenant -query 'CREATE USER "NT AUTHORITY\SYSTEM" FOR LOGIN "NT AUTHORITY\SYSTEM";'
                    Export-NAVApplication -DatabaseServer $DatabaseServer -DatabaseInstance $DatabaseInstance -DatabaseName "tenant" -DestinationDatabaseName $databaseName -Force -ServiceAccount 'NT AUTHORITY\SYSTEM' | Out-Null
                    Write-Host "Removing Application from tenant"
                    Remove-NAVApplication -DatabaseServer $DatabaseServer -DatabaseInstance $DatabaseInstance -DatabaseName "tenant" -Force | Out-Null
                    Set-NAVServerConfiguration -ServerInstance $ServerInstance -KeyName "Multitenant" -KeyValue "true" -ApplyTo ConfigFile
                    Set-NavserverInstance -ServerInstance $serverInstance -start
                }
                $allowAppDatabaseWrite = ($additionalparameters | Where-Object { $_ -like "*defaultTenantHasAllowAppDatabaseWrite=Y" }) -ne $null
                New-BcContainerTenant -containerName $containerName -tenantId default -allowAppDatabaseWrite:$allowAppDatabaseWrite
            }
        }
        elseif ($createTenantAndUserInExternalDatabase) {
            if ($multitenant) {
                $allowAppDatabaseWrite = ($additionalparameters | Where-Object { $_ -like "*defaultTenantHasAllowAppDatabaseWrite=Y" }) -ne $null
                New-NavContainerTenant `
                    -containerName $containerName `
                    -tenantId 'default' `
                    -sqlCredential $databaseCredential `
                    -sourceDatabase "$($databasePrefix)tenant" `
                    -destinationDatabase "$($databasePrefix)default" `
                    -allowAppDatabaseWrite:$allowAppDatabaseWrite
            }
            
            New-NavContainerNavUser `
                -containerName $containerName `
                -tenant 'default' `
                -Credential $credential `
                -PermissionSetId 'SUPER' `
                -ChangePasswordAtNextLogOn:$false
        }
    
        if (!$restoreBakFolder -and $finalizeDatabasesScriptBlock) {
            Invoke-Command -ScriptBlock $finalizeDatabasesScriptBlock
        }
    
        if ($bakFolder -and !$restoreBakFolder) {
            Backup-BcContainerDatabases -containerName $containerName -bakFolder $bakFolder
        }
    
        Write-Host -ForegroundColor Green "Container $containerName successfully created"
    
        if ($useTraefik) {
            Write-Host -ForegroundColor Yellow "Because of Traefik, the following URLs need to be used when accessing the container from outside your Docker host:"
            Write-Host "Web Client:        $webclientUrl"
            Write-Host "SOAP WebServices:  $soapUrl"
            Write-Host "OData WebServices: $restUrl"
            Write-Host "Dev Service:       $devUrl"
            Write-Host "Snapshot Service:  $snapUrl"
            Write-Host "File downloads:    $dlUrl"
        }

        if (!$doNotCheckHealth) {
            if (Invoke-ScriptInBcContainer -containerName $containerName -scriptblock {
                $result = $false
                try {
                    . c:\run\healthcheck.ps1
                    $result = ("$LASTEXITCODE" -eq "1")
                }
                catch {}
                $result
            }) {
                Write-Host "Health check returns False, restarting container"
                Restart-BcContainer $containerName
            }
        }
    
        Write-Host
        Write-Host "Use:"
        Write-Host -ForegroundColor Yellow -NoNewline "Get-BcContainerEventLog -containerName $containerName"
        Write-Host " to retrieve a snapshot of the event log from the container"
        Write-Host -ForegroundColor Yellow -NoNewline "Get-BcContainerDebugInfo -containerName $containerName"
        Write-Host  " to get debug information about the container"
        Write-Host -ForegroundColor Yellow -NoNewline "Enter-BcContainer -containerName $containerName"
        Write-Host " to open a PowerShell prompt inside the container"
        Write-Host -ForegroundColor Yellow -NoNewline "Remove-BcContainer -containerName $containerName"
        Write-Host " to remove the container again"
        Write-Host -ForegroundColor Yellow -NoNewline "docker logs $containerName"
        Write-Host " to retrieve information about URL's again"
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
Set-Alias -Name New-NavContainer -Value New-BcContainer
Export-ModuleMember -Function New-BcContainer -Alias New-NavContainer

# SIG # Begin signature block
# MIInRgYJKoZIhvcNAQcCoIInNzCCJzMCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBHEvBbp+p5XvzF
# kqGroqiwzQEAWghdqUueZSgggQltTaCCDLowggX1MIID3aADAgECAhMzAAACHU0Z
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
# 1cY2L4A7GTQG1h32HHAvfQESWP0xghniMIIZ3gIBATBuMFcxCzAJBgNVBAYTAlVT
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
# c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMjQCEzMAAAIdTRnITtcPV0gAAAAAAh0w
# DQYJYIZIAWUDBAIBBQCgga4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYK
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIK+B5LV3
# /5nfFIJvnv8sc9rOsIJJ6KstZ8PHpXhqHeT9MEIGCisGAQQBgjcCAQwxNDAyoBSA
# EgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20w
# DQYJKoZIhvcNAQEBBQAEggEAHEPPxL6paibKjdgYAdjCVL3iJehMI4pCoKht5NDy
# 6opSkOrcRqDL0lsRqQJTZtZI5N41Z7ORqhm9cL3HQ2tK0P4NCQjuWpntljGoRFWg
# tY6f51o719jUgL0BeJgkugzF8AXGrpRBkiZAH1qBsnCdRrNXQuM4225vf8XjkDya
# VOIhHkcbinnaE7qAzrlQTw7hpak+sX2mm393Abwlhs2us6GwCdpWftj+BnNsnre1
# Gwb4tpVqKPZLVT12XV+uKj0i/TBXThvC0pkr36nmFGBFsJ2wluOg45HWsnQhGaCt
# eAlXWbbvRJoZPqC+zwY/cZ96II/cUFOoUcZXhl7nGfxxB6GCF5QwgheQBgorBgEE
# AYI3AwMBMYIXgDCCF3wGCSqGSIb3DQEHAqCCF20wghdpAgEDMQ8wDQYJYIZIAWUD
# BAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGEWQoD
# ATAxMA0GCWCGSAFlAwQCAQUABCB311mtHdP/c4z71zK0vl1LwJNwYqCG1NRlfucT
# NmZVwwIGaoV1KK53GBMyMDI2MDkwMjA3NTU0NC44NjRaMASAAgH0oIHRpIHOMIHL
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxN
# aWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRT
# UyBFU046RjAwMi0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFNlcnZpY2WgghHqMIIHIDCCBQigAwIBAgITMwAAAiAk4ebgF7m0jgABAAAC
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
# VTNYs6FwZvKhggNNMIICNQIBATCB+aGB0aSBzjCByzELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFtZXJpY2Eg
# T3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOkYwMDItMDVFMC1E
# OTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEw
# BwYFKw4DAhoDFQCTGA9vpsJ6glqCLmI0rggGx4YEEqCBgzCBgKR+MHwxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29m
# dCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBCwUAAgUA7kG9pzAiGA8y
# MDI2MDkwMTIxMDk1OVoYDzIwMjYwOTAyMjEwOTU5WjB0MDoGCisGAQQBhFkKBAEx
# LDAqMAoCBQDuQb2nAgEAMAcCAQACAhkcMAcCAQACAhM0MAoCBQDuQw8nAgEAMDYG
# CisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAIAgEA
# AgMBhqAwDQYJKoZIhvcNAQELBQADggEBAJn+uI7LR4mkn/MHcV/K+iRBwXFV89VS
# J1K1FqDAIcG6DOyD0fWUUAn8HRUjvNgX/oTd1BDGmbrIm0Cna4dzaa6ZYW21ZAhn
# 6fDEtRJMGotc8JncxMDtAL2/ZeM2ckoW0YShEXTZypMgHqzwz4BKPvhhvwRLWpHD
# c7skXMDpQi/2/WEdxvX0ri6TDWZq5sUI8FydVeHPi2v22D6lQ/YBSYc0RX6ddKUU
# rXiCwNblAF9G7jwleOhT3B8wQcpstlVorZgcHZoRkU5oI4x+0gVgf1KWy17qX9Bk
# JJdUlKVwn/ojlP5l7QfJN2jXCnSZiYOKHUKUV1O6aPxWiL8XQk2KmHYxggQNMIIE
# CQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYw
# JAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAiAk4ebg
# F7m0jgABAAACIDANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0GCyqG
# SIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCDgvQN/2wqTmZDsvEpUBsyYGL5mOKN3
# jwNG/jxsgOOocjCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EION7vyOlPA1V
# qlEp0QIVGlNd8S5YWBnKj97LuTWHSO2vMIGYMIGApH4wfDELMAkGA1UEBhMCVVMx
# EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoT
# FU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUt
# U3RhbXAgUENBIDIwMTACEzMAAAIgJOHm4Be5tI4AAQAAAiAwIgQgbrTO7PYxNX/t
# jt3MNv6KYaV2+gNVGXNHJXeaCi72O+QwDQYJKoZIhvcNAQELBQAEggIAbCyQ158Z
# mn+m15PibnznW+bZ6UjNjJozER+/7Vvd2z5+OdF2RZvxRUDCYK0qaOHj2kFZONY/
# GgKmcH/ng0UD8m/VEjmzeJwwtw30A3F5pnDBXtgXlWIxq3Ov3AJNjpc8dlSqfc/1
# njVadfKAGx07it5xDZo9+x7iyQdiW+ZN6xj7rHkiE2psZJhweOpuCD883QYjfm8+
# Y5xBA6PWj7nEtHIMbIRKy6gAf3r0MXqYGsHI6pNTZobONo7dNwQsw7wmKT6vNWP4
# +3/PfUN3xeXqkd2iHp8easskBMegtmyDni0jHxAOyZCg+EbGBxWSFn7s3Y2/brTx
# s02aKo6HBDowaNDo4VK13mxoAWXFOjfEASiDtmN6vxp4SbC1hsiu4Bwdntod4eLQ
# dGGkARfAOez30p0dCwObm3A6G09wR7WhcHfpJtFvXQAAAzqEdpn8O2i/UHdwfox5
# /ZMhuH07fzImNhUBXFu3VlRmd5hhqqyqvCMsrQTly51Rco/jiMTsZDdLdDWx7cM+
# dvHcsq/e0SGn0uhiaQbo9rwKuLNmmnzq5OqhqXK5wvoq0s6gdCM5U65ePktREgX1
# w2bYwOVO0D4a3D1yUEQlKZxNtNDuULsoIrhI9nPHJFNsRPNfdmEydbxdw3Ts36Jx
# xtlJt/YCWD/uxzoFmlhWJOkVGoNfD7iKLhs=
# SIG # End signature block
