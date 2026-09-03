#requires -Version 5.0

[NuGetFeed[]] $NuGetFeedCache = @()

# PROOF OF CONCEPT PREVIEW: This class holds the connection to a NuGet feed
class NuGetFeed {

    [string] $url
    [string] $token
    [string[]] $patterns
    [string[]] $fingerprints

    [string] $searchQueryServiceUrl
    [string] $packagePublishUrl
    [string] $packageBaseAddressUrl

    [hashtable] $orgType = @{}

    [hashtable] $searchResultsCache = @{}
    [int]       $searchResultsCacheRetentionPeriod
    [string]    $cacheFolder

    NuGetFeed([string] $nuGetServerUrl, [string] $nuGetToken, [string[]] $patterns, [string[]] $fingerprints, [int] $nuGetSearchResultsCacheRetentionPeriod, [string] $nuGetCacheFolder) {
        $this.url = $nuGetServerUrl
        $this.token = $nuGetToken
        $this.patterns = $patterns
        $this.fingerprints = $fingerprints
        $this.searchResultsCacheRetentionPeriod = $nuGetSearchResultsCacheRetentionPeriod
        $this.cacheFolder = $nugetCacheFolder

        # When trusting nuget.org, you should only trust packages signed by an author or packages matching a specific pattern (like using a registered prefix or a full name)
        if ($nuGetServerUrl -like 'https://api.nuget.org/*' -and $patterns.Contains('*') -and (!$fingerprints -or $fingerprints.Contains('*'))) {
            throw "Trusting all packages on nuget.org is not supported"
        }

        try {
            $prev = $global:ProgressPreference; $global:ProgressPreference = "SilentlyContinue"
            $capabilities = Invoke-RestMethod -UseBasicParsing -Method GET -Headers ($this.GetHeaders()) -Uri $this.url
            $global:ProgressPreference = $prev
            $this.searchQueryServiceUrl = $capabilities.resources | Where-Object { $_.'@type' -eq 'SearchQueryService' } | Select-Object -ExpandProperty '@id' | Select-Object -First 1
            if (!$this.searchQueryServiceUrl) {
                # Azure DevOps doesn't support SearchQueryService, but SearchQueryService/3.0.0-beta
                $this.searchQueryServiceUrl = $capabilities.resources | Where-Object { $_.'@type' -eq 'SearchQueryService/3.0.0-beta' } | Select-Object -ExpandProperty '@id' | Select-Object -First 1
            }
            $this.packagePublishUrl = $capabilities.resources | Where-Object { $_."@type" -eq 'PackagePublish/2.0.0' } | Select-Object -ExpandProperty '@id' | Select-Object -First 1
            $this.packageBaseAddressUrl = $capabilities.resources | Where-Object { $_."@type" -eq 'PackageBaseAddress/3.0.0' } | Select-Object -ExpandProperty '@id' | Select-Object -First 1
            if (!$this.searchQueryServiceUrl -or !$this.packagePublishUrl -or !$this.packageBaseAddressUrl) {
                Write-Host "Capabilities of NuGet server $($this.url) are not supported"
                $capabilities.resources | ForEach-Object { Write-Host "- $($_.'@type')"; Write-Host "-> $($_.'@id')" }
            }
            Write-Verbose "Capabilities of NuGet server $($this.url) are:"
            Write-Verbose "- SearchQueryService=$($this.searchQueryServiceUrl)"
            Write-Verbose "- PackagePublish=$($this.packagePublishUrl)"
            Write-Verbose "- PackageBaseAddress=$($this.packageBaseAddressUrl)"
        }
        catch {
            throw (GetExtendedErrorMessage $_)
        }
    }

    static [NuGetFeed] Create([string] $nuGetServerUrl, [string] $nuGetToken, [string[]] $patterns, [string[]] $fingerprints, [int] $nuGetSearchResultsCacheRetentionPeriod, [string] $nuGetCacheFolder) {
        $nuGetFeed = $script:NuGetFeedCache | Where-Object { $_.url -eq $nuGetServerUrl -and $_.token -eq $nuGetToken -and (-not (Compare-Object $_.patterns $patterns)) -and (-not (Compare-Object $_.fingerprints $fingerprints)) -and $_.searchResultsCacheRetentionPeriod -eq $nuGetSearchResultsCacheRetentionPeriod }
        if (!$nuGetFeed) {
            $nuGetFeed = [NuGetFeed]::new($nuGetServerUrl, $nuGetToken, $patterns, $fingerprints, $nuGetSearchResultsCacheRetentionPeriod, $nugetCacheFolder)
            $script:NuGetFeedCache += $nuGetFeed
        }
        return $nuGetFeed
    }

    [void] Dump([string] $message) {
        Write-Host $message
    }

    [hashtable] GetHeaders() {
        $headers = @{
            "Content-Type" = "application/json; charset=utf-8"
        }
        # nuget.org only support anonymous access
        if ($this.token -and $this.url -notlike 'https://api.nuget.org/*') {
            $headers += @{
                "Authorization" = "Basic $([Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("user:$($this.token)")))"
            }
        }
        return $headers
    }

    [bool] IsTrusted([string] $packageId) {
        return ($packageId -and ($this.patterns | Where-Object { $packageId -like $_ }))
    }

    [hashtable[]] Search([string] $packageName) {
        $useCache = $this.searchResultsCacheRetentionPeriod -gt 0
        $hasCache = $this.searchResultsCache.ContainsKey($packageName)
        if ($hasCache) {
            if ($useCache) {
                # Clear cache older than the retention period
                $clearCache = $this.searchResultsCache[$packageName].timestamp.AddSeconds($this.searchResultsCacheRetentionPeriod) -lt (Get-Date)
            } else {
                # Clear cache if we are not using it
                $clearCache = $true
            }
            if ($clearCache) {
                $this.searchResultsCache.Remove($packageName)
                $hasCache = $false
            }
        }

        $matching = @()
        if ($useCache -and $hasCache) { 
            Write-Host "Search package using cache"
            $matching = $this.searchResultsCache[$packageName].matching
        } 
        elseif ($this.searchQueryServiceUrl -match '^https://nuget\.(pkg\.github\.com|([^/]+)\.ghe\.com)/(.*)/query$') {
            # GitHub support for SearchQueryService is unstable and is not usable
            # use GitHub API instead
            # GitHub API unfortunately doesn't support filtering, so we need to filter ourselves
            if ($matches[2]) {
                # GitHub Enterprise Cloud with data residency (ghe.com)
                $apiUrl = "https://api.$($matches[2]).ghe.com"
            }
            else {
                $apiUrl = "https://api.github.com"
            }
            $organization = $matches[3]
            $headers = @{
                "Accept" = "application/vnd.github+json"
                "X-GitHub-Api-Version" = "2022-11-28"
            }
            if ($this.token) {
                $headers += @{
                    "Authorization" = "Bearer $($this.token)"
                }
            }
            if (-not $this.orgType.ContainsKey($organization)) {
                $orgMetadata = Invoke-RestMethod -Method GET -Headers $headers -Uri "$apiUrl/users/$organization"
                if ($orgMetadata.type -eq 'Organization') {
                    $this.orgType[$organization] = 'orgs'
                }
                else {
                    $this.orgType[$organization] = 'users'
                }
            }
            $cacheKey = "GitHubPackages:$($this.orgType[$organization])/$organization"
            if ($this.searchResultsCacheRetentionPeriod -gt 0 -and $this.searchResultsCache.ContainsKey($cacheKey)) {
                if ($this.searchResultsCache[$cacheKey].timestamp.AddSeconds($this.searchResultsCacheRetentionPeriod) -lt (Get-Date)) {
                    Write-Host "Cache expired, removing cache $cacheKey"
                    $this.searchResultsCache.Remove($cacheKey)
                }
                else {
                    Write-Host "Search available packages using cache $cacheKey"
                    $matching = $this.searchResultsCache[$cacheKey].matching
                    Write-Host "$($matching.Count) packages found"
                }
            }
            if (-not $matching) {
                $per_page = 50
                $queryUrl = "$apiUrl/$($this.orgType[$organization])/$organization/packages?package_type=nuget&per_page=$($per_page)&page="
                $page = 1
                $matching = @()
                while ($true) {
                    Write-Host -ForegroundColor Yellow "Search package using $queryUrl$page"
                    $result = Invoke-RestMethod -UseBasicParsing -Method GET -Headers $headers -Uri "$queryUrl$page"
                    Write-Host "$($result.Count) packages found"
                    if ($result.Count -eq 0) {
                        break
                    }
                    $matching += @($result)
                    if ($result.Count -ne $per_page) {
                        break
                    }
                    $page++
                }
                Write-Host "Total of $($matching.Count) packages found"
                $this.searchResultsCache[$cacheKey] = @{
                    matching = $matching
                    timestamp = (Get-Date)
                }
            }
            $matching = @($matching | Where-Object { $_.name -like "*$packageName*" -and $this.IsTrusted($_.name) } | Sort-Object { $_.name.replace('.symbols','') } | ForEach-Object { @{ "id" = $_.name; "versions" = @() } } )
        }
        else {
            # prerelase=true in order to find packages, which not yet has been published as prod
            $queryUrl = "$($this.searchQueryServiceUrl)?q=$packageName&take=50&prerelease=true"
            try {
                Write-Host -ForegroundColor Yellow "Search package using $queryUrl"
                $prev = $global:ProgressPreference; $global:ProgressPreference = "SilentlyContinue"
                $searchResult = Invoke-RestMethod -UseBasicParsing -Method GET -Headers ($this.GetHeaders()) -Uri $queryUrl
                $global:ProgressPreference = $prev
                # Check that the found pattern matches the package name and the trusted patterns
                $matching = @($searchResult.data | Where-Object { $_.id -like "*$($packageName)*" -and $this.IsTrusted($_.id) } | Sort-Object { $_.id.replace('.symbols','') } | ForEach-Object { @{ "id" = $_.id; "versions" = @($_.versions.version) } } )
            }
            catch {
                throw (GetExtendedErrorMessage $_)
            }
        }
        $exact = $matching | Where-Object { $_.id -eq $packageName -or $_.id -eq "$packageName.symbols" }
        if ($exact) {
            Write-Host "Exact match found for $packageName"
            $matching = $exact
        }
        else {
            Write-Host "$($matching.count) matching packages found"
        }

        if ($useCache -and !$hasCache) {
            # Cache the search results
            $this.searchResultsCache[$packageName] = @{
                matching = $matching
                timestamp = (Get-Date)
            }
        }

        return $matching | ForEach-Object { Write-Host "- $($_.id)"; $_ }
    }

    [string[]] GetVersions([hashtable] $package, [bool] $descending, [bool] $allowPrerelease) {
        if (!$this.IsTrusted($package.id)) {
            throw "Package $($package.id) is not trusted on $($this.url)"
        }
        if ($package.versions.count -eq 0) {
            $queryUrl = "$($this.packageBaseAddressUrl.TrimEnd('/'))/$($package.Id.ToLowerInvariant())/index.json"
            try {
                Write-Host -ForegroundColor Yellow "Get versions using $queryUrl"
                $prev = $global:ProgressPreference; $global:ProgressPreference = "SilentlyContinue"
                $versions = Invoke-RestMethod -UseBasicParsing -Method GET -Headers ($this.GetHeaders()) -Uri $queryUrl
                $global:ProgressPreference = $prev
            }
            catch {
                throw (GetExtendedErrorMessage $_)
            }
            $package.versions = @($versions.versions)
        }
        $versionsArr = $package.versions
        Write-Host "$($versionsArr.count) versions found"
        $versionsArr = @($versionsArr | Where-Object { $allowPrerelease -or !$_.Contains('-') } | Sort-Object { ($_ -replace '-.+$') -as [System.Version]  }, { "$($_)z" } -Descending:$descending | ForEach-Object { "$_" })
        Write-Host "First version is $($versionsArr[0])"
        Write-Host "Last version is $($versionsArr[$versionsArr.Count-1])"
        return $versionsArr
    }

    # Normalize name or publisher name to be used in nuget id
    static [string] Normalize([string] $name) {
        return $name -replace '[^a-zA-Z0-9_\-]',''
    }

    static [string] NormalizeVersionStr([string] $versionStr) {
        $idx = $versionStr.IndexOf('-')
        $version = [System.version]($versionStr.Split('-')[0])
        if ($version.Build -eq -1) { $version = [System.Version]::new($version.Major, $version.Minor, 0, 0) }
        if ($version.Revision -eq -1) { $version = [System.Version]::new($version.Major, $version.Minor, $version.Build, 0) }
        if ($idx -gt 0) {
            return "$version$($versionStr.Substring($idx))"
        }
        else {
            return "$version"
        }
    }

    static [Int32] CompareVersions([string] $version1, [string] $version2) {
        $version1 = [NuGetFeed]::NormalizeVersionStr($version1)
        $version2 = [NuGetFeed]::NormalizeVersionStr($version2)
        $ver1 = $version1 -replace '-.+$' -as [System.Version]
        $ver2 = $version2 -replace '-.+$' -as [System.Version]
        if ($ver1 -eq $ver2) {
            # add a 'z' to the version to make sure that 5.1.0 is greater than 5.1.0-beta
            # Tags are sorted alphabetically (alpha, beta, rc, etc.), even though this shouldn't matter
            # New prerelease versions will always have a new version number
            return [string]::Compare("$($version1)z", "$($version2)z")
        }
        elseif ($ver1 -gt $ver2) {
            return 1
        }
        else {
            return -1
        }
    }

    # Test if version is included in NuGet version range
    # https://learn.microsoft.com/en-us/nuget/concepts/package-versioning#version-ranges
    static [bool] IsVersionIncludedInRange([string] $versionStr, [string] $nuGetVersionRange) {
        $versionStr = [NuGetFeed]::NormalizeVersionStr($versionStr)
        $version = $versionStr -replace '-.+$' -as [System.Version]
        if ($nuGetVersionRange -match '^\s*([\[(]?)([\d\.]*)(,?)([\d\.]*)([\])]?)\s*$') {
            $inclFrom = $matches[1] -ne '('
            $range = $matches[3] -eq ','
            $inclTo = $matches[5] -eq ']'
            if ($matches[1] -eq '' -and $matches[5] -eq '') {
                $range = $true
            }
            if ($matches[2]) {
                $fromver = [System.Version]([NuGetFeed]::NormalizeVersionStr($matches[2]))
            }
            else {
                $fromver = [System.Version]::new(0,0,0,0)
                if ($inclFrom) {
                    Write-Host "Invalid NuGet version range $nuGetVersionRange"
                    return $false
                }
            }
            if ($matches[4]) {
                $tover = [System.Version]([NuGetFeed]::NormalizeVersionStr($matches[4]))
            }
            elseif ($range) {
                $tover = [System.Version]::new([int32]::MaxValue,[int32]::MaxValue,[int32]::MaxValue,[int32]::MaxValue)
                if ($inclTo) {
                    Write-Host "Invalid NuGet version range $nuGetVersionRange"
                    return $false
                }
            }
            else {
                $tover = $fromver
            }
            if (!$range -and (!$inclFrom -or !$inclTo)) {
                Write-Host "Invalid NuGet version range $nuGetVersionRange"
                return $false
            }
            if ($inclFrom) {
                if ($inclTo) {
                    return $version -ge $fromver -and $version -le $tover
                }
                else {
                    return $version -ge $fromver -and $version -lt $tover
                }
            }
            else {
                if ($inclTo) {
                    return $version -gt $fromver -and $version -le $tover
                }
                else {
                    return $version -gt $fromver -and $version -lt $tover
                }
            }
        }
        return $false
    }

    [string] FindPackageVersion([hashtable] $package, [string] $nuGetVersionRange, [string[]] $excludeVersions, [string] $select, [bool] $allowPrerelease) {
        $versions = $this.GetVersions($package, !($select -eq 'Earliest' -or $select -eq 'AllAscending'), $allowPrerelease)
        if ($excludeVersions) {
            Write-Host "Exclude versions: $($excludeVersions -join ', ')"
        }
        $versionList = @()
        foreach($version in $versions ) {
            if ($excludeVersions -contains $version) {
                continue
            }
            if (($select -eq 'Exact' -and [NuGetFeed]::NormalizeVersionStr($nuGetVersionRange) -eq [NuGetFeed]::NormalizeVersionStr($version)) -or ($select -ne 'Exact' -and [NuGetFeed]::IsVersionIncludedInRange($version, $nuGetVersionRange))) {
                if ($select -eq 'AllAscending' -or $select -eq 'AllDescending') {
                    Write-Host "Include $version"
                }
                elseif ($nuGetVersionRange -eq '0.0.0.0') {
                    Write-Host "$select version is $version"
                }
                else {
                    Write-Host "$select version matching '$nuGetVersionRange' is $version"
                }
                $versionList += @($version)
            }
        }
        return ($versionList -join ',')
    }

    # Download the specs for the package with id = packageId and version = version
    # The following properties are returned:
    # - id: the package id
    # - name: the package name (either title, description or id from the nuspec)
    # - version: the package version
    # - authors: the package authors
    # - dependencies: the package dependencies (id and version range)
    [PSCustomObject] DownloadPackageSpec([string] $packageId, [string] $version) {
        $nuSpecName = "$($packageId.ToLowerInvariant())/$($version.ToLowerInvariant()).json"
        $nuSpecFileName = Join-Path $this.cacheFolder $nuSpecName
        $nuSpecMutex = New-Object System.Threading.Mutex($false, $nuSpecName.Replace('/','_').Replace('\','_'))
        try {
            try {
                if (!$nuSpecMutex.WaitOne(1000)) {
                    Write-Host "Waiting for other process downloading nuspec '$($nuSpecName)'"
                    $nuSpecMutex.WaitOne() | Out-Null
                    Write-Host "Other process completed download"
                }
            }
            catch [System.Threading.AbandonedMutexException] {
               Write-Host "Other process terminated abnormally"
            }
            if (Test-Path $nuSpecFileName) {
                Write-Host "Using cached nuspec for $packageId version $version"
                (Get-Item $nuSpecFileName).LastWriteTime = Get-Date
                return (Get-Content -Path $nuSpecFileName | ConvertFrom-Json | ConvertTo-HashTable)
            }
            if (!$this.IsTrusted($packageId)) {
                throw "Package $packageId is not trusted on $($this.url)"
            }
            if ($this.packageBaseAddressUrl -like 'https://nuget.pkg.github.com/*' -or $this.packageBaseAddressUrl -like 'https://nuget.*.ghe.com/*') {
                $queryUrl = "$($this.packageBaseAddressUrl.SubString(0,$this.packageBaseAddressUrl.LastIndexOf('/')))/$($packageId.ToLowerInvariant())/$($version.ToLowerInvariant()).json"
                Write-Host "Download nuspec using $queryUrl"
                $response = Invoke-WebRequest -UseBasicParsing -Method GET -Headers ($this.GetHeaders()) -Uri $queryUrl
                $content = $response.Content | ConvertFrom-Json
                if (!($content.PSObject.Properties.Name -eq 'catalogEntry') -or ($null -eq $content.catalogEntry)) {
                    throw "Package $packageId version $version not found on"
                }
                $returnValue = @{
                    "id" = $content.catalogEntry.id
                    "name" = $content.catalogEntry.description
                    "version" = $content.catalogEntry.version
                    "authors" = $content.catalogEntry.authors
                    "dependencies" = $content.catalogEntry.dependencyGroups | ForEach-Object { $_.dependencies | ForEach-Object { @{"id" = $_.id; "version" = $_.range.replace(' ','') } } }
                }
            }
            else {
                $queryUrl = "$($this.packageBaseAddressUrl.TrimEnd('/'))/$($packageId.ToLowerInvariant())/$($version.ToLowerInvariant())/$($packageId.ToLowerInvariant()).nuspec"
                try {
                    Write-Host "Download nuspec using $queryUrl"
                    $prev = $global:ProgressPreference; $global:ProgressPreference = "SilentlyContinue"
                    $tmpFile = Join-Path ([System.IO.Path]::GetTempPath()) "$([GUID]::NewGuid().ToString()).nuspec"
                    Invoke-RestMethod -UseBasicParsing -Method GET -Headers ($this.GetHeaders()) -Uri $queryUrl -OutFile $tmpFile
                    $nuspec = [xml](Get-Content -Path $tmpfile -Encoding UTF8 -Raw)
                    Remove-Item -Path $tmpFile -Force
                    $global:ProgressPreference = $prev
                }
                catch {
                    throw (GetExtendedErrorMessage $_)
                }
                if ($nuspec.package.metadata.PSObject.Properties.Name -eq 'title') {
                    $appName = $nuspec.package.metadata.title
                }
                elseif ($nuspec.package.metadata.PSObject.Properties.Name -eq 'description') {
                    $appName = $nuspec.package.metadata.description
                }
                else {
                    $appName = $nuspec.package.metadata.id
                }
                if ($nuspec.package.metadata.PSObject.Properties.Name -eq 'Dependencies') {
                    $dependencies = @($nuspec.package.metadata.Dependencies.GetEnumerator() | ForEach-Object { @{"id" = $_.id; "version" = $_.version } })
                }
                else {
                    $dependencies = @()
                }
                $returnValue = @{
                    "id" = $nuspec.package.metadata.id
                    "name" = $appName
                    "version" = $nuspec.package.metadata.version
                    "authors" = $nuspec.package.metadata.authors
                    "dependencies" = $dependencies
                }
            }
            New-Item -Path $nuSpecFileName -ItemType File -Force -Value ($returnValue | ConvertTo-Json -Depth 99) | Out-Null
            return $returnValue
        }
        finally {
            $nuSpecMutex.ReleaseMutex()
        }
    }

    [string] DownloadPackage([string] $packageId, [string] $version) {
        $packageSubFolder = "$($packageId.ToLowerInvariant())/$($version.ToLowerInvariant())"
        $packageMutex = New-Object System.Threading.Mutex($false, $packageSubFolder.Replace('/','_').Replace('\','_'))
        try {
            try {
                if (!$packageMutex.WaitOne(1000)) {
                    Write-Host "Waiting for other process downloading package '$($packageSubFolder)'"
                    $packageMutex.WaitOne() | Out-Null
                    Write-Host "Other process completed download"
                }
            }
            catch [System.Threading.AbandonedMutexException] {
               Write-Host "Other process terminated abnormally"
            }

            if (!$this.IsTrusted($packageId)) {
                throw "Package $packageId is not trusted on $($this.url)"
            }
            $queryUrl = "$($this.packageBaseAddressUrl.TrimEnd('/'))/$($packageId.ToLowerInvariant())/$($version.ToLowerInvariant())/$($packageId.ToLowerInvariant()).$($version.ToLowerInvariant()).nupkg"
            $packageCacheFolder = Join-Path $this.cacheFolder $packageSubFolder
            if (test-Path $packageCacheFolder) {
                Write-Host "Using cached package for $packageId version $version"
                (Get-Item $packageCacheFolder).LastWriteTime = Get-Date
            }
            else {
                try {
                    Write-Host -ForegroundColor Green "Download package using $queryUrl"
                    $prev = $global:ProgressPreference; $global:ProgressPreference = "SilentlyContinue"
                    $filename = "$($packageCacheFolder).zip"
                    New-Item -Path $packageCacheFolder -ItemType Container | Out-Null
                    Invoke-RestMethod -UseBasicParsing -Method GET -Headers ($this.GetHeaders()) -Uri $queryUrl -OutFile $filename
                    if ($this.fingerprints) {
                        $arguments = @("nuget", "verify", $filename)
                        if ($this.fingerprints.Count -eq 1 -and $this.fingerprints[0] -eq '*') {
                            Write-Host "Verifying package using any certificate"
                        }
                        else {
                            Write-Host "Verifying package using $($this.fingerprints -join ', ')"
                            $arguments += @("--certificate-fingerprint $($this.fingerprints -join ' --certificate-fingerprint ')")
                        }
                        cmddo -command 'dotnet' -arguments $arguments -silent -messageIfCmdNotFound "dotnet not found. Please install it from https://dotnet.microsoft.com/download"
                    }
                    Expand-Archive -Path $filename -DestinationPath $packageCacheFolder -Force
                    $global:ProgressPreference = $prev
                    Write-Host "Package successfully downloaded"
                }
                catch {
                    if (Test-Path $packageCacheFolder) {
                        Remove-Item $packageCacheFolder -Recurse -Force
                    }
                    throw (GetExtendedErrorMessage $_)
                }
                finally {
                    if (Test-Path $filename) {
                        Remove-Item $filename -Force
                    }
                }
            }
            $tmpFolder = Join-Path ([System.IO.Path]::GetTempPath()) ([GUID]::NewGuid().ToString())
            New-Item -Path $tmpFolder -ItemType Container | Out-Null
            Copy-Item -Path (Join-Path $packageCacheFolder '*') -Destination $tmpFolder -Recurse -Force
            return $tmpFolder
        }
        finally {
            $packageMutex.ReleaseMutex()
        }
    }

    [void] PushPackage([string] $package) {
        if (!($this.token)) {
            throw "NuGet token is required to push packages"
        }
        Write-Host "Preparing NuGet Package for submission"
        $headers = $this.GetHeaders()
        $headers += @{
            "X-NuGet-ApiKey" = $this.token
            "X-NuGet-Client-Version" = "6.3.0"
        }
        $boundary = [System.Guid]::NewGuid().ToString();
        $LF = "`r`n";
        $tmpFile = Join-Path ([System.IO.Path]::GetTempPath()) ([GUID]::NewGuid().ToString())
        $fs = [System.IO.File]::OpenWrite($tmpFile)
        $fs | Add-Member -MemberType ScriptMethod -Name WriteBytes -Value { param($bytes) $this.Write($bytes, 0, $bytes.Length) }
        try {
            $fs.WriteBytes([System.Text.Encoding]::UTF8.GetBytes("--$boundary$LF"))
            $fs.WriteBytes([System.Text.Encoding]::UTF8.GetBytes("Content-Type: application/octet-stream$($LF)Content-Disposition: form-data; name=package; filename=""$([System.IO.Path]::GetFileName($package))""$($LF)$($LF)"))
            $fs.WriteBytes([System.IO.File]::ReadAllBytes($package))
            $fs.WriteBytes([System.Text.Encoding]::UTF8.GetBytes("$LF--$boundary--$LF"))
        } finally {
            $fs.Close()
        }
        
        Write-Host "Submitting NuGet package"
        try {
            Invoke-RestMethod -UseBasicParsing -Uri $this.packagePublishUrl -ContentType "multipart/form-data; boundary=$boundary" -Method Put -Headers $headers -inFile $tmpFile | Out-Host
            Write-Host -ForegroundColor Green "NuGet package successfully submitted"

            # Clear matching search results caches
            @( $this.searchResultsCache.Keys ) | 
                Where-Object { $package -like "*$($_)*" -or $_ -like 'GitHubPackages:*' } | 
                ForEach-Object { $this.searchResultsCache.Remove($_) }
        }
        catch [System.Net.WebException] {
            if ($_.Exception.Status -eq "ProtocolError" -and $_.Exception.Response -is [System.Net.HttpWebResponse]) {
                $response = [System.Net.HttpWebResponse]($_.Exception.Response)
                if ($response.StatusCode -eq [System.Net.HttpStatusCode]::Conflict) {
                    Write-Host -ForegroundColor Yellow "NuGet package already exists"
                }
                else {
                    throw (GetExtendedErrorMessage $_)
                }
            }
            else {
                throw (GetExtendedErrorMessage $_)
            }
        }
        catch {
            throw (GetExtendedErrorMessage $_)
        }
        finally {
            Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
        }
    
    }
}

# SIG # Begin signature block
# MIInSQYJKoZIhvcNAQcCoIInOjCCJzYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBXRc5Uzx9NacgE
# 3PbkDTTrosNRfs0q5haPmGiPJCNhwqCCDLowggX1MIID3aADAgECAhMzAAACHU0Z
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
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIGcOcL0d
# WK/dR2Fp180TPit5gidnJGIxIBXRqiqpHnCtMEIGCisGAQQBgjcCAQwxNDAyoBSA
# EgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20w
# DQYJKoZIhvcNAQEBBQAEggEAjdR2YB9lK2MzAk7PB+daPKQ5q4MHPPcMlVWNKal0
# p5ZgXtSi3bGRooMY+HY5UcdHXhMj5KTLagBVKmyyzjX6s9X6ad0XDYrbixirtSzm
# 2WlvcTLhHF5hGd2F3beUKp6lmlGVIUApXJh0OPgiJPtgxFFssB2T/fkje8z4aZQW
# MjN9n+G5/fN3KLauzhofM8ZrlYyZW2PiXdG4sLSBcfxiCGbT6xeGOXvDxH+dZq3X
# 0WG2w3c5g00Iad0OOhfm85yVP4hRCn6Ph1gpETgXJpmfuVF9xsAuteM5XNSgf6tE
# GIV7rsSta+5RaIxS91NEvDCpcyonw3XtBNb1J+f2h7fj6KGCF5cwgheTBgorBgEE
# AYI3AwMBMYIXgzCCF38GCSqGSIb3DQEHAqCCF3AwghdsAgEDMQ8wDQYJYIZIAWUD
# BAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGEWQoD
# ATAxMA0GCWCGSAFlAwQCAQUABCDoHXA+ccmQBfST6r14q/pMaeafHSDvSwLJKFKF
# WfedtwIGaoV0MGH+GBMyMDI2MDgyNzA2MjkzNC41MjZaMASAAgH0oIHRpIHOMIHL
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
# CyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCB6cujWzlYAb0ioTpRqoSWxfRak
# jMrrwVQJDO3r2puqSjCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EION7vyOl
# PA1VqlEp0QIVGlNd8S5YWBnKj97LuTWHSO2vMIGYMIGApH4wfDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgUENBIDIwMTACEzMAAAIgJOHm4Be5tI4AAQAAAiAwIgQgjiu1gfdt
# K/nOE0cUc+Y8+y8Y+ptu1I0ru0zk1hD/Vy8wDQYJKoZIhvcNAQELBQAEggIAFN+A
# dcD9Q3JLwLD2LwteSTFELtNg9rDBPeRFM+XYvddxgefCCJlPYG9bN9MmS+8OxPgA
# eAu/XQ0E6xPFuHWl0iPZBljAAgQiwDp8dRwi/q73wQ1ufHii5V+A3tuPewy+oV+l
# 9owYzDQZziD2+H6mpvHXe60S1bb6uj7KeWl4YewRP/Ub2dYXw97i07/jAjQMmh/u
# Yk10XJuAzH5wPvioYxEr4TbUXoyxkf4usOiEZ+ZaBSK55LwkJPywUQzH9yD2AcDt
# +lVVngH20hKliPUKBL+N0c63GhpwQHrfY1N0+J7pUyn/azp0gpDGfxfbhRlKcP4F
# Gz8e6d4+NuPsuJp90U1hchzCojOBsdK8yhBGUeOjpqTCeJV1yW2DzRDLC9qS9lzR
# klpzGiEkcgR2ZE2F2ADRMeXciv1WQfizJIu2KfDrDL2JoNEbEqBCMGZKe6pBzK4h
# 3xYtdm+iZWS60tzcVaxyqE+NdOZWRqjFpbyonm9mJiGs7B3SHPtD5UofXXIcfcQl
# h7BFRCLi6cpsWrp6YjypU9vM0JIcP4AjRluUraldHOXSjjzkekSxBf8+QBbtDr5O
# v334v31aPLQxHVN47BY2xQwnhgGiNvHbaIZsJdE2Y+aaOfF+tkpR/R26RG5v7eYC
# vnuwTsIKuA63uTy45Uic1GtV73o86l5Cj41QXus=
# SIG # End signature block
