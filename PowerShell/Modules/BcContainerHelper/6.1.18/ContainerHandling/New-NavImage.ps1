<# 
 .Synopsis
  Create or refresh NAV/BC image
 .Description
  Creates a new image based on artifacts and a base image
  The function returns the imagename of the image created
 .Parameter artifactUrl
  Url for application artifact to use
 .Parameter platformArtifactUrl
  Url for platform artifact to use. Use this when you want to use a different platform than the one related to artifactUrl.
 .Parameter imageName
  Name of the image getting build. Default is myimage:<tag describing version>.
 .Parameter baseImage
  BaseImage to use. Default is using Get-BestGenericImage to get the best generic image to use.
 .Parameter databaseBackupPath
  Path to database backup to use in place of Cronus backup. By default database backup from manifest is used. This parameter can be used to override this and use your custom backup.
 .Parameter registryCredential
  Credentials for the registry for baseImage if you are using a private registry (incl. bcinsider)
 .Parameter isolation
  Isolation mode for the image build process (default is process if baseImage OS matches host OS)
 .Parameter memory
  Memory allocated for building image. 8G is default.
 .Parameter myScripts
  This allows you to specify a number of scripts you want to copy to the c:\run\my folder in the container (override functionality)
 .Parameter skipDatabase
  Adding this parameter creates an image without a database
 .Parameter filesOnly
  Include this switch to create a filesOnly container. A filesOnly container does not contain SQL Server, IIS or the ServiceTier, it only contains the files from BC in the same locations as a normal container.
  A FilesOnly container can be used to compile apps and it can be used as a proxy container for an online Business Central environment
 .Parameter multitenant
  Adding this parameter creates an image with multitenancy
 .Parameter addFontsFromPath
  Enumerate all fonts from this path or array of paths and install them in the container
 .Parameter runSandboxAsOnPrem
  This parameter will attempt to run sandbox artifacts as onprem (will only work with version 18 and later)
 .Parameter populateBuildFolder
  Adding this parameter causes the function to populate this folder with DOCKERFILE and other files needed to build the image instead of building the image
 .Parameter additionalLabels
  additionalLabels can contain an array of additional labels for the image
#>
function New-BcImage {
    Param (
        [Parameter(Mandatory=$true)]
        [string] $artifactUrl,
        [string] $platformArtifactUrl = "",
        [string] $imageName = "myimage",
        [string] $baseImage = "",
        [string] $databaseBackupPath = "",
        [PSCredential] $registryCredential,
        [ValidateSet('','process','hyperv')]
        [string] $isolation = "",
        [string] $memory = "",
        $myScripts = @(),
        [switch] $skipDatabase,
        [switch] $multitenant,
        [switch] $filesOnly,
        [string[]] $addFontsFromPath = @(""),
        [string] $licenseFile = "",
        [switch] $includeTestToolkit,
        [switch] $includeTestLibrariesOnly,
        [switch] $includeTestFrameworkOnly,
        [switch] $includePerformanceToolkit,
        [switch] $skipIfImageAlreadyExists,
        [switch] $runSandboxAsOnPrem,
        [string] $populateBuildFolder = "",
        [string[]] $additionalLabels = @(),
        $allImages
    )


function RoboCopyFiles {
    Param(
        [string] $source,
        [string] $destination,
        [string] $files = "*",
        [switch] $e
    )

    Write-Host $source
    if ($e) {
        RoboCopy "$source" "$destination" "$files" /e /NFL /NDL /NJH /NJS /nc /ns /np /mt /z /nooffload | Out-Null
        Get-ChildItem -Path $source -Filter $files -Recurse | ForEach-Object {
            $destPath = Join-Path $destination $_.FullName.Substring($source.Length)
            while (!(Test-Path $destPath)) {
                Write-Host "Waiting for $destPath to be available"
                Start-Sleep -Seconds 1
            }
        }
    }
    else {
        RoboCopy "$source" "$destination" "$files" /NFL /NDL /NJH /NJS /nc /ns /np /mt /z /nooffload | Out-Null
        Get-ChildItem -Path $source -Filter $files | ForEach-Object {
            $destPath = Join-Path $destination $_.FullName.Substring($source.Length)
            while (!(Test-Path $destPath)) {
                Write-Host "Waiting for $destPath to be available"
                Start-Sleep -Seconds 1
            }
        }
    }
}

$telemetryScope = InitTelemetryScope `
                    -name $MyInvocation.InvocationName `
                    -parameterValues $PSBoundParameters `
                    -includeParameters @("containerName","artifactUrl","platformArtifactUrl","isolation","imageName","baseImage","registryCredential","multitenant","filesOnly")
try {

    if ($memory -eq "") {
        $memory = "8G"
    }

    $imageName = $imageName.ToLowerInvariant()

    $myScripts | ForEach-Object {
        if ($_ -is [string]) {
            if ($_.StartsWith("https://", "OrdinalIgnoreCase") -or $_.StartsWith("http://", "OrdinalIgnoreCase")) {
            } elseif (!(Test-Path $_)) {
                throw "Script directory or file $_ does not exist"
            }
        } elseif ($_ -isnot [Hashtable]) {
            throw "Illegal value in myScripts"
        }
    }

    $os = (Get-CimInstance Win32_OperatingSystem)
    if ($os.OSType -ne 18 -or !$os.Version.StartsWith("10.0.")) {
        throw "Unknown Host Operating System"
    }
    $UBR = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name UBR).UBR
    
    $hostOsVersion = [System.Version]::Parse("$($os.Version).$UBR")
    $hostOs = "Unknown/Insider build"
    $bestGenericImageName = Get-BestGenericImageName -onlyMatchingBuilds -filesOnly:$filesOnly
    $isServerHost = $os.ProductType -eq 3

    if ("$baseImage" -eq "") {
        if ("$bestGenericImageName" -eq "") {
            $bestGenericImageName = Get-BestGenericImageName -filesOnly:$filesOnly
            Write-Host "WARNING: Unable to find matching generic image for your host OS. Using $bestGenericImageName"
        }
        $baseImage = $bestGenericImageName
    }

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
        $hostOs = "ltsc2019"
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
        $hostOs = "ltsc2016"
    }

    if ($platformArtifactUrl -and -not $artifactUrl) {
        throw "You have to specify artifactUrl when using platformArtifactUrl."
    }

    $artifactPaths = Download-Artifacts -artifactUrl $artifactUrl -platformArtifactUrl $platformArtifactUrl -includePlatform
    $appArtifactPath = $artifactPaths[0]
    $platformArtifactPath = $artifactPaths[1]

    $appManifestPath = Join-Path $appArtifactPath "manifest.json"
    $appManifest = Get-Content $appManifestPath | ConvertFrom-Json
    if (!$runSandboxAsOnPrem -and $appManifest.PSObject.Properties.name -eq "isBcSandbox") {
        if ($appManifest.isBcSandbox) {
            if (!($PSBoundParameters.ContainsKey('multitenant')) -and !$skipDatabase) {
                $multitenant = $bcContainerHelperConfig.sandboxContainersAreMultitenantByDefault
            }
        }
    }

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

    $dbstr = ""
    $mtstr = ""
    if (!$imageName.Contains(':')) {
        $appUri = [Uri]::new($artifactUrl)
        $imageName += ":$($appUri.AbsolutePath.ToLowerInvariant().Replace('/','-').TrimStart('-'))"
        if ($filesOnly) {
            $imageName += "-filesonly"
            $dbstr = " with files only"
        }
        else {
            if ($skipDatabase) {
                $imageName += "-nodb"
                $dbstr = " without database"
    
            }
            if ($multitenant) {
                $imageName += "-mt"
                $mtstr = " multitenant"
            }
        }
    }

    $imageName

    if ($populateBuildFolder -eq "") {
        $buildMutexName = "img-$imageName"
        $buildMutex = New-Object System.Threading.Mutex($false, $buildMutexName)
}
    try {
        try {
            if ($populateBuildFolder -eq "") {
                if (!$buildMutex.WaitOne(1000)) {
                    Write-Host "Waiting for other process building image $imageName"
                    $buildMutex.WaitOne() | Out-Null
                    Write-Host "Other process completed building"
                    $allImages = @()
                }
            }
        }
        catch [System.Threading.AbandonedMutexException] {
           Write-Host "Other process terminated abnormally"
        }

        $forceRebuild = $true
        if ($skipIfImageAlreadyExists) {
    
            if (-not ($allImages)) {
                Write-Host "Fetching all docker images"
                $allImages = @(docker images --format "{{.Repository}}:{{.Tag}}")
            }
    
            if ($allImages | Where-Object { $_ -eq $imageName }) {
                
                $forceRebuild = $false
    
                try {
                    Write-Host "Image $imageName already exists"
                    $inspect = docker inspect $imageName | ConvertFrom-Json
                    $labels = Get-BcContainerImageLabels -imageName $baseImage -registryCredential $registryCredential
            
                    $imageArtifactUrl = ($inspect.config.env | ? { $_ -like "artifactUrl=*" }).SubString(12).Split('?')[0]
                    if ((ReplaceCDN -sourceUrl $imageArtifactUrl -useBlobUrl) -ne (ReplaceCDN -sourceUrl $artifactUrl.Split('?')[0] -useBlobUrl)) {
                        Write-Host "Image $imageName was built with artifactUrl $imageArtifactUrl, should be $($artifactUrl.Split('?')[0])"
                        $forceRebuild = $true
                    }
                    if ($inspect.Config.Labels.version -ne $appManifest.Version) {
                        Write-Host "Image $imageName was built with version $($inspect.Config.Labels.version), should be $($appManifest.Version)"
                        $forceRebuild = $true
                    }
                    elseif ($inspect.Config.Labels.Country -ne $appManifest.Country) {
                        Write-Host "Image $imageName was built with country $($inspect.Config.Labels.country), should be $($appManifest.country)"
                        $forceRebuild = $true
                    }
                    elseif ($inspect.Config.Labels.osversion -ne $labels.osversion) {
                        Write-Host "Image $imageName was built for OS Version $($inspect.Config.Labels.osversion), should be $($labels.osversion)"
                        $forceRebuild = $true
                    }
                    elseif ($inspect.Config.Labels.tag -ne $labels.tag) {
                        Write-Host "Image $imageName has generic Tag $($inspect.Config.Labels.tag), should be $($labels.tag)"
                        $forceRebuild = $true
                    }
                   
                    if (($inspect.Config.Labels.PSObject.Properties.Name -eq "Multitenant") -and ($inspect.Config.Labels.Multitenant -eq "Y")) {
                        if (!$multitenant) {
                            Write-Host "Image $imageName was built multi tenant, should have been single tenant"
                            $forceRebuild = $true
                        }
                    }
                    else {
                        if ($multitenant) {
                            Write-Host "Image $imageName was built single tenant, should have been multi tenant"
                            $forceRebuild = $true
                        }
                    }
            
                    if (($inspect.Config.Labels.PSObject.Properties.Name -eq "SkipDatabase") -and ($inspect.Config.Labels.SkipDatabase -eq "Y")) {
                        if (!$skipdatabase) {
                            Write-Host "Image $imageName was built without a database, should have a database"
                            $forceRebuild = $true
                        }
                    }
                    else {
                        # Do not rebuild if database is there, just don't use it
                    }
                }
                catch {
                    Write-Host "Exception $($_.ToString())"
                    $forceRebuild = $true
                }
            }
        }
    
        if ($forceRebuild) {
    
            Write-Host "Building$mtstr image $imageName based on $baseImage with $($artifactUrl.Split('?')[0])$dbstr"
            $startTime = [DateTime]::Now
            
            if ($populateBuildFolder) {
                $genericTag = [Version]"1.0.2.15"
            }
            else {
                if ($baseImage -like 'mcr.microsoft.com/businesscentral:*') {
                    Write-Host "Pulling latest image $baseImage"
                    DockerDo -command pull -imageName $baseImage | Out-Null
                }
                else {
                    $baseImageExists = docker images --format "{{.Repository}}:{{.Tag}}" | Where-Object { $_ -eq "$baseImage" }
                    if (!($baseImageExists)) {
                        Write-Host "Pulling non-existing base image $baseImage"
                        DockerDo -command pull -imageName $baseImage | Out-Null
                    }
                }
            
                $genericTag = [Version](Get-BcContainerGenericTag -containerOrImageName $baseImage)
                Write-Host "Generic Tag: $genericTag"
                if ($genericTag -lt [Version]"0.1.0.16") {
                    throw "Generic tag must be at least 0.1.0.16. Cannot build image based on $genericTag"
                }
        
                $containerOsVersion = [Version](Get-BcContainerOsVersion -containerOrImageName $baseImage)
                $containerOs = GetContainerOs -containerOsVersion $containerOsVersion
                Write-Host "Container OS Version: $containerOsVersion ($containerOs)"
                Write-Host "Host OS Version: $hostOsVersion ($hostOs)"
            
                if (($hostOsVersion.Major -lt $containerOsversion.Major) -or 
                    ($hostOsVersion.Major -eq $containerOsversion.Major -and $hostOsVersion.Minor -lt $containerOsversion.Minor) -or 
                    ($hostOsVersion.Major -eq $containerOsversion.Major -and $hostOsVersion.Minor -eq $containerOsversion.Minor -and $hostOsVersion.Build -lt $containerOsversion.Build)) {
            
                    throw "The container operating system is newer than the host operating system, cannot use image"
                }

                $isolation = GetIsolationMode -hostOsVersion $hostOsVersion -containerOsVersion $containerOsVersion -useSSL $false -isolation $isolation
                Write-Host "Using $isolation isolation"
            }
            
            $downloadsPath = $bcContainerHelperConfig.bcartifactsCacheFolder
            if (!(Test-Path $downloadsPath)) {
                New-Item $downloadsPath -ItemType Directory | Out-Null
            }
        
            if ($populateBuildFolder) {
                $buildFolder = $populateBuildFolder
                if (Test-Path $buildFolder) {
                    throw "$populateBuildFolder already exists"
                }
                New-Item $buildFolder -ItemType Directory | Out-Null
            }
            else {
                do {
                    $buildFolder = Join-Path $bcContainerHelperConfig.bcartifactsCacheFolder ([System.IO.Path]::GetRandomFileName())
                }
                until (New-Item $buildFolder -ItemType Directory -ErrorAction SilentlyContinue)
            }
        
            try {
        
                $myFolder = Join-Path $buildFolder "my"
                new-Item -Path $myFolder -ItemType Directory | Out-Null

                $InstallDotNet = ""
                if ($genericTag -le [Version]"1.0.2.13" -and [Version]$appManifest.Version -ge [Version]"22.0.0.0") {
                    Write-Host "Patching SetupConfiguration.ps1 due to issue #2874"
                    $myscripts += @( "https://raw.githubusercontent.com/microsoft/nav-docker/main/generic/Run/210-new/SetupConfiguration.ps1" )
                    Write-Host "Patching prompt.ps1 due to issue #2891"
                    $myScripts += @( "https://raw.githubusercontent.com/microsoft/nav-docker/main/generic/Run/Prompt.ps1" )
                    $myScripts += @( "https://download.visualstudio.microsoft.com/download/pr/04389c24-12a9-4e0e-8498-31989f30bb22/141aef28265938153eefad0f2398a73b/dotnet-hosting-6.0.27-win.exe" )
                    Write-Host "Base image is generic image 1.0.2.13 or below, installing dotnet 6.0.27"
                    $InstallDotNet = 'RUN start-process -Wait -FilePath "c:\run\dotnet-hosting-6.0.27-win.exe" -ArgumentList /quiet'
                }

                if ($genericTag -le [Version]"1.0.2.14" -and [Version]$appManifest.Version -ge [Version]"24.0.0.0") {
                    $myScripts += @( "https://download.visualstudio.microsoft.com/download/pr/98ff0a08-a283-428f-8e54-19841d97154c/8c7d5f9600eadf264f04c82c813b7aab/dotnet-hosting-8.0.2-win.exe" )
                    $myScripts += @( "https://github.com/PowerShell/PowerShell/releases/download/v7.4.1/PowerShell-7.4.1-win-x64.msi" )
                    Write-Host "Base image is generic image 1.0.2.14 or below, installing dotnet 8.0.2"
                    $InstallDotNet = 'RUN start-process -Wait -FilePath "c:\run\dotnet-hosting-8.0.2-win.exe" -ArgumentList /quiet ; start-process -Wait -FilePath c:\run\powershell-7.4.1-win-x64.msi -ArgumentList /quiet'
                }

                if ($genericTag -ge [Version]"1.0.2.15" -and [Version]$appManifest.Version -ge [Version]"15.0.0.0" -and [Version]$appManifest.Version -lt [Version]"19.0.0.0") {
                    $myScripts += @( "https://download.microsoft.com/download/6/F/B/6FB4F9D2-699B-4A40-A674-B7FF41E0E4D2/DotNetCore.1.0.7_1.1.4-WindowsHosting.exe" )
                    Write-Host "Base image is generic image 1.0.2.15 or higher, installing ASP.NET Core 1.1"
                    $InstallDotNet = 'RUN start-process -Wait -FilePath "c:\run\DotNetCore.1.0.7_1.1.4-WindowsHosting.exe" -ArgumentList /quiet'
                }

                if ($genericTag -eq [Version]"1.0.2.15" -and [Version]$appManifest.Version -ge [Version]"24.0.0.0") {
                    $myScripts += @( 'https://raw.githubusercontent.com/microsoft/nav-docker/4b8870e6c023c399d309e389bf32fde44fcb1871/generic/Run/240/navinstall.ps1' )
                    Write-Host "Patching installer from generic image 1.0.2.15"
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
                    } else {
                        $hashtable = $_
                        $hashtable.Keys | ForEach-Object {
                            Set-Content -Path (Join-Path $myFolder $_) -Value $hashtable[$_]
                        }
                    }
                }
        
                $licenseFilePath = ""
                if ($licenseFile) {
                    if ($licensefile.StartsWith("https://", "OrdinalIgnoreCase") -or $licensefile.StartsWith("http://", "OrdinalIgnoreCase")) {
                        Write-Host "Using license file $($licenseFile.Split('?')[0])"
                        $ext = [System.IO.Path]::GetExtension($licenseFile.Split('?')[0])
                        $licenseFilePath = Join-Path $myFolder "license$ext"
                        Download-File -sourceUrl $licenseFile -destinationFile $licenseFilePath
                        if ((Get-Content $licenseFilePath -First 1) -ne "Microsoft Software License Information") {
                            Remove-Item -Path $licenseFilePath -Force
                            throw "Specified license file Uri isn't a direct download Uri"
                        }
                    }
                    else {
                        Write-Host "Using license file $licenseFile"
                        $licenseFilePath = $licenseFile
                    }
                }
                
                Write-Host "Files in $($myfolder):"
                get-childitem -Path $myfolder | ForEach-Object { Write-Host "- $($_.Name)" }
        
                $isBcSandbox = "N"
                if (!$runSandboxAsOnPrem -and $appManifest.PSObject.Properties.name -eq "isBcSandbox") {
                    if ($appManifest.isBcSandbox) {
                        $IsBcSandbox = "Y"
                    }
                }
        
                if (!$skipDatabase){
                    $database = $appManifest.database
                    $databasePath = Join-Path $appArtifactPath $database
                    if ($licenseFile -eq "") {
                        if ($appManifest.PSObject.Properties.name -eq "licenseFile") {
                            $licenseFilePath = $appManifest.licenseFile
                            if ($licenseFilePath) {
                                $licenseFilePath = Join-Path $appArtifactPath $licenseFilePath
                            }
                        }
                    }
                }
        
                $nav = ""
                if ($appManifest.PSObject.Properties.name -eq "Nav") {
                    $nav = $appManifest.Nav
                }
                $cu = ""
                if ($appManifest.PSObject.Properties.name -eq "Cu") {
                    $cu = $appManifest.Cu
                }
            
                $navDvdPath = Join-Path $buildFolder "NAVDVD"
                New-Item $navDvdPath -ItemType Directory | Out-Null
        
                Write-Host "Copying Platform Artifacts"
                RobocopyFiles -source "$platformArtifactPath" -destination "$navDvdPath" -e
        
                if (!$skipDatabase) {
                    $CommonData = "CommApp"
                    if ($appManifest.version -lt [Version]"27.0.33344.0")
                    {
                        $CommonData = "CommonAppData"
                    }

                    $dbPath = Join-Path $navDvdPath "SQLDemoDatabase\$CommonData\Microsoft\Microsoft Dynamics NAV\ver\Database"
                    New-Item $dbPath -ItemType Directory | Out-Null
                    if (($databaseBackupPath) -and (Test-Path $databaseBackupPath -PathType Leaf))
                    {
                        Write-Host "Using database backup from $databaseBackupPath"
                        $databasePath = $databaseBackupPath
                    }
                    Write-Host "Copying Database"
                    Copy-Item -path $databasePath -Destination $dbPath -Force
                    if ($licenseFilePath) {
                        Write-Host "Copying Licensefile"
                        Copy-Item -path $licenseFilePath -Destination "$dbPath\CRONUS.flf" -Force
                    }
                }
        
                "Installers", "ConfigurationPackages", "TestToolKit", "UpgradeToolKit", "Extensions", "Applications","Applications.*" | ForEach-Object {
                    $appSubFolder = Join-Path $appArtifactPath $_
                    if (Test-Path $appSubFolder -PathType Container) {
                        $appSubFolder = (Get-Item $appSubFolder).FullName
                        $name = [System.IO.Path]::GetFileName($appSubFolder)
                        $destFolder = Join-Path $navDvdPath $name
                        if (Test-Path $destFolder) {
                            Remove-Item -path $destFolder -Recurse -Force
                        }
                        Write-Host "Copying $name"
                        RoboCopyFiles -Source "$appSubFolder" -Destination "$destFolder" -e
                    }
                }
            
                if ($populateBuildFolder -eq "") {
                    docker images --format "{{.Repository}}:{{.Tag}}" | ForEach-Object { 
                        if ($_ -eq $imageName) 
                        {
                            docker rmi --no-prune $imageName -f | Out-Host
                        }
                    }
                }
        
                Write-Host $buildFolder
                
                $skipDatabaseLabel = ""
                if ($skipDatabase) {
                    $skipDatabaseLabel = "skipdatabase=""Y"" \`n      "
                }
        
                $multitenantLabel = ""
                $multitenantParameter = ""
                if ($multitenant) {
                    $multitenantLabel = "multitenant=""Y"" \`n      "
                    $multitenantParameter = " -multitenant"
                }
        
                $dockerFileAddFonts = ""
                if ($addFontsFromPath) {
                    $found = $false
                    $fontsFolder = Join-Path $buildFolder "Fonts"
                    New-Item $fontsFolder -ItemType Directory | Out-Null
                    $extensions = @(".fon", ".fnt", ".ttf", ".ttc", ".otf")
                    Get-ChildItem $addFontsFromPath -ErrorAction Ignore | ForEach-Object {
                        if ($extensions.Contains($_.Extension.ToLowerInvariant())) {
                            Copy-Item -Path $_.FullName -Destination $fontsFolder
                            $found = $true
                        }
                    }
                    if ($found) {
                        Write-Host "Adding fonts"
                        Copy-Item -Path (Join-Path $PSScriptRoot "..\AddFonts.ps1") -Destination $fontsFolder
                        $dockerFileAddFonts = "COPY Fonts /Fonts/`nRUN . C:\Fonts\AddFonts.ps1`n"
                    }
                }

                $TestToolkitParameter = ""
                if ($genericTag -ge [Version]"0.1.0.18") {
                    if ($includeTestToolkit) {
                        if (!($licenseFile) -and ($appManifest.version -lt [Version]"22.0.0.0")) {
                            Write-Host "Cannot include TestToolkit without a licensefile, please specify licensefile"
                        }
                        $TestToolkitParameter = " -includeTestToolkit"
                        if ($includeTestLibrariesOnly) {
                            $TestToolkitParameter += " -includeTestLibrariesOnly"
                        }
                        elseif ($includeTestFrameworkOnly) {
                            $TestToolkitParameter += " -includeTestFrameworkOnly"
                        }
                    }
                }
                if ($genericTag -ge [Version]"0.1.0.21") {
                    if ($includeTestToolkit) {
                        if ($includePerformanceToolkit) {
                            $TestToolkitParameter += " -includePerformanceToolkit"
                        }
                    }
                }
    
                $additionalLabelsStr = ""
                $additionalLabels | ForEach-Object {
                    $additionalLabelsStr += "$_ \`n      "
                }
@"
FROM $baseimage

ENV DatabaseServer=localhost DatabaseInstance=SQLEXPRESS DatabaseName=CRONUS IsBcSandbox=$isBcSandbox artifactUrl=$artifactUrl filesOnly=$filesOnly

COPY my /run/
COPY NAVDVD /NAVDVD/
$DockerFileAddFonts
$InstallDotNet

RUN \Run\start.ps1 -installOnly$multitenantParameter$TestToolkitParameter

LABEL legal="http://go.microsoft.com/fwlink/?LinkId=837447" \
      created="$([DateTime]::Now.ToUniversalTime().ToString("yyyyMMddHHmm"))" \
      nav="$nav" \
      cu="$cu" \
      $($skipDatabaseLabel)$($multitenantLabel)$($additionalLabelsStr)country="$($appManifest.Country)" \
      version="$($appmanifest.Version)" \
      platform="$($appManifest.Platform)"
"@ | Set-Content (Join-Path $buildFolder "DOCKERFILE")

                if ($populateBuildFolder) {
                    Write-Host "$populateBuildFolder populated, skipping build of image"
                }
                else {
                    if (!(DockerDo -command build -parameters @("--isolation=$isolation", "--memory $memory", "--no-cache", "--tag $imageName") -imageName $buildFolder)) {
                        throw "Docker Build didn't indicate success"
                    }
    
                    $timespend = [Math]::Round([DateTime]::Now.Subtract($startTime).Totalseconds)
                    Write-Host "Building image took $timespend seconds"
                }
            }
            finally {
                if ($populateBuildFolder -eq "") {
                    Remove-Item $buildFolder -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
    finally {
        if ($populateBuildFolder -eq "") {
            $buildMutex.ReleaseMutex()
        }
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
Set-Alias -Name New-NavImage -Value New-BcImage
Export-ModuleMember -Function New-BcImage -Alias New-NavImage

# SIG # Begin signature block
# MIInSQYJKoZIhvcNAQcCoIInOjCCJzYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCD8wJ8Lb83ymERy
# 6izpQ+uBsIRLNoJMnWERjtcyn5F2EaCCDLowggX1MIID3aADAgECAhMzAAACHU0Z
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
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIMKqpJpc
# O7XnJuYCvgzcWN43zdzF1/WYVqk86U9FoQFzMEIGCisGAQQBgjcCAQwxNDAyoBSA
# EgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20w
# DQYJKoZIhvcNAQEBBQAEggEAfIVgthUCpsFq61pmni9bDbXTf58OC3BbuYQvvy5t
# Q9xZDvWPGiHcIrFvKAVq8eFjHCR2Gr4dfNmgCwmaTtBk/hvdhcQBKYFEenTEYmGd
# Pyfm1tXI9Kqi2WkSjhpV150rjqTsq3rX35/cWu3Gp6246se0THyOTQ1Y3V86elkI
# LCVBRXcVB5TwNvM10PL9O2UwK2hEN5SS8gWDTTZM+b6Gb0tY1n/7vEbdpy9mqk/Q
# uYIwHqZf4MDLO+orkkMdx17+VXqKT0gRbTO55B2iy95qlhMXoG8WsvSCFJlBLQCd
# AOZwcgsIgJjd594tsYFXcbddnsQ6qMn70n1Io+5w5DKTtaGCF5cwgheTBgorBgEE
# AYI3AwMBMYIXgzCCF38GCSqGSIb3DQEHAqCCF3AwghdsAgEDMQ8wDQYJYIZIAWUD
# BAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGEWQoD
# ATAxMA0GCWCGSAFlAwQCAQUABCARbgns3Bz5gSysK4bkvf0PIyhh9pP80muflgiW
# BylAsgIGaoULU1OzGBMyMDI2MDgyNzA2MjkzNi4zMjJaMASAAgH0oIHRpIHOMIHL
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxN
# aWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRT
# UyBFU046N0YwMC0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFNlcnZpY2WgghHtMIIHIDCCBQigAwIBAgITMwAAAh6jrKRuOW98SQABAAAC
# HjANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAe
# Fw0yNjAyMTkxOTM5NDlaFw0yNzA1MTcxOTM5NDlaMIHLMQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmlj
# YSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046N0YwMC0wNUUw
# LUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIi
# MA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCl0TjtbDwsR7Fe8ac6ol5s1zht
# Tqd2AWpchQhLp9G5mmSM23N5fyQGCQ1D06rOA3PgXKF+76vXvOCs2VsLv1owj4mH
# EyEqiq8GJ5yC+/QNYRpZPA8e7OgekzDO6S/4vy/jTMYbp3rhuFiKKCzTWOQtdFcF
# +D0k369I7pm/E07SyNMGkuNd5lj5SJ91UqFuZfjMB6cQ2wh77mtiRUVdj53yjdNq
# j+GQl+Yaz29Bjrzn7U1ln+JpLlnb0xdGmZoIPKZbwBVcWtyL4uyhML7SSTmiOfWX
# U+g+yNl0CdoLGL8LtWHEi8FsuTPeSdSqmeMrvLaEmibTVTS4vQQY8NPnb6uI5y6i
# NV9vBFcm8LU/lDTjGTqPa7UBT4gdf5Jm3wYrfCFZ4P/j5MoqT0JONca50jt4TGI9
# 0SihXaDEYqk23S0IJZ3UkUpukDRTjK713BIykffxyBqMeQqfO0zvWfUx7BrmUpug
# Qcw99+DxLl2gf+uQEpRmnlbrVJ9dvW9ds4fqEPN2jG0QwF1PBSglNcV1SpqZKitQ
# gBGSwu/82AKztoCHwYRHRNwzwTVe/1KNTvmqAd4Uges4ywOH02haagT8wYY8OdWd
# jKn3k052w+kmc0UC0F+iVXTGZIMxvo9iBZQoXehzRtWJ/VOtKvCyS3csKzN7rStW
# JwjSWz6dtOf0l+ytLQIDAQABo4IBSTCCAUUwHQYDVR0OBBYEFOYKFprqBB0JZmJc
# FC4cPPmeF4JkMB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1Ud
# HwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3Js
# L01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggr
# BgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNv
# bS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIw
# MTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgw
# DgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUAA4ICAQCkoZB5NnJVFb5wKejR
# onk518a2TBNYpKcBMtfL6BS0ARaABOMGYLlPNuhI1HwmelP9hX3oq3TaEm/cDkkz
# NQAzDedPgoRI2R7+8poNSWvHXEAs7SZODm9x7KqlBkNZM9ex4XY1yNmVOAmWDjRr
# 7jKjaiQbntf7EC4GNikxGGaVWOjfYt3Q9X0r/Ks8KBlbzDR9zjA/TCctR4co1WpU
# 1ZRLFrB9bl8dRxsbnyT2qQ41E7dT12R30eIGUziEs5GN+26V/ovXOi20dJiM13hY
# Wvy1NNJAhkKOlLB1ONund6ffhPdUcHWsu8V+lR0aakMV64HqDbLumZrCNwUofVx3
# xMk8F4tCYJtQxLTywc30sZAD1S2sC1959x6KixA+p41FLUl8g64oHy3bfYnH5xd4
# JOBgQoaqndGjcctxr+8EknjhKyrgAzrTcKLJbUezgoye8brCLJ+y6PAoEjpXRkSY
# AU8wfQ3YWRck6ALwoV7Uin8+rpGQSbXhF6c1dTFakXmChClud4IADY/t6JRkJ+06
# FzL+jDd8KLV8Qj77JfiuTiPIG5G/xlnGoZFcX+yyBtDvzZE48d+Y+HYUd/cvhH1F
# Kl7AH+5AyotqJSFmvM/BuYRx2B20asVXilV2k2JbNO3LGCz3Q+dpElzwsfJrka1N
# /getma7fWpowsNvoIaEQvjad8TCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkA
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
# T3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjdGMDAtMDVFMC1E
# OTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEw
# BwYFKw4DAhoDFQCD/QNkKDIW4VIF7j3oi2qbrR0a/6CBgzCBgKR+MHwxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29m
# dCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBCwUAAgUA7joUfDAiGA8y
# MDI2MDgyNzAxNDIyMFoYDzIwMjYwODI4MDE0MjIwWjB3MD0GCisGAQQBhFkKBAEx
# LzAtMAoCBQDuOhR8AgEAMAoCAQACAht3AgH/MAcCAQACAhQfMAoCBQDuO2X8AgEA
# MDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAI
# AgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBAI/j3Y4O83yCKXCl+adiQPlktvOq
# NE4TGY5MvdHiz8CgPA385WLqhCMLHHMJG1z+/4hBpp3jM3Qnv2qxFNP9LkuxyT6P
# HM4jOrbuMqijFPjF86c9PsSSVJGZwptieK+NQeajG8j7pUGfyeEuiFwzQLOg+rNH
# WXogih4/OqN44az6r0MZjcp+25WPeFSuo7L5N/bhxCIPx+URIbb67MRzue/BnXVr
# 2zPkGvBjG7zt6nuj1OVKjh1ynvcDN3ztanuZ55Xof+8Ja4Qmh3M+NHhjk2KWYCum
# 2TmeqqBR0w6ZpuhEFbNKVIkESlb+ioeaYYznM/DAULUI06yBDv/2C574W+sxggQN
# MIIECQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQ
# MA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
# MSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAh6j
# rKRuOW98SQABAAACHjANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0G
# CyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCCgVi9lOykozHRYStnVTBTvKm+t
# kNBBY0OtRjUEAPq1PjCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EIC+BXWrz
# 9geMgM8Bvn8bqxHjhHXJ29EBizITIw0B9vOCMIGYMIGApH4wfDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgUENBIDIwMTACEzMAAAIeo6ykbjlvfEkAAQAAAh4wIgQgfXVSJWZ1
# zOMvWleoZz5FtNufpHJ99mo3bwhn37ZfIAkwDQYJKoZIhvcNAQELBQAEggIAPq3C
# tXc+Qf2YFkO86q7/Smh+/q9gKcMLUBm/KkKNMa24VqC9CNR6SruFf/d5KtFSsWKW
# h2Sx7AFVYBZ+Pu58ygcS5HqDAg3MNAQDMQx9lR4TzUHbJeUrCLhmpYCvKTI7Rndr
# eCEAAyb7SGVkIIm6vya1c2bFlsDSYRD8FtbTbq1bLvbecp9/IWUOZ57Oowa/8cin
# eqiQ9NY5xBcMt/3ksRm+c1TD4Xu5h7fs6SPVIPxzAUPBzNQL/NozawnH6EXWjb57
# fGHommyhx5lrWwxtIrhyFIqjve8Xyy/SEhtLApsR3TWXtjBtGg/fKYltcYF2lwUh
# HqppsNKMQZCdVDAy+rJz2MW4M8LLv+y9YJDqjry3Q41qfotU2A2LO5kzpRosV5Bk
# cui3jSfIiIHsTjxTqHaTEfsdMJHll5CEVKfxD80rsVU75jyKR69lI6Nl7Q/WzAqe
# TEgXNL56inERNb1Lnc1EzIb01oD7b7shgHUk7sSIuu1FzBU6O2uayE9mepSNxj5Y
# VzaxvX7D0210nKp92wNU/wl/BbhJXQ2K1A7ZOsAoNuXI/d4DSs88pvEc1CZvnfVZ
# 6vk1JMM0fNDijVvnZ53vNAVllMwM6PxW3frx3TDT7RMG79XTvtmkkkHoARFfX+6Q
# X+WMLBs5UoRO3FSQQNOYHDfiTAbNPcvhjn+Ui5c=
# SIG # End signature block
