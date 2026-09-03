function New-ALGoRepo {
    Param(
        [Parameter(Mandatory=$true)]
        $org,
        [Parameter(Mandatory=$true)]
        $repo,
        $branch = "main",
        [Parameter(Mandatory=$true)]
        [ValidateSet('PTE','AppSource')]
        $appType,
        [Parameter(Mandatory=$true)]
        [ValidateSet('public','private')]
        $accessControl,
        $algoBranch = 'main',
        $description = $repo,
        $apps = @(),
        [HashTable] $addRepoSettings = @{},
        [HashTable] $addProjectSettings = @{},
        $readme = "# $repo",
        [string] $keyVaultName,
        [switch] $useOrgSecrets,
        [HashTable] $secrets = @{},
        [switch] $additionalCountriesAlways,
        [switch] $openFolder,
        [switch] $openVSCode,
        [switch] $openBrowser,
        $tmpFolder = (Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString()))
    )

    # Well known AppIds
    $systemAppId = "63ca2fa4-4f03-4f2b-a480-172fef340d3f"
    $baseAppId = "437dbf0e-84ff-417a-965d-ed2bb9650972"
    $applicationAppId = "c1335042-3002-4257-bf8a-75c898ccb1b8"
    $permissionsMockAppId = "40860557-a18d-42ad-aecb-22b7dd80dc80"
    $testRunnerAppId = "23de40a6-dfe8-4f80-80db-d70f83ce8caf"
    $anyAppId = "e7320ebb-08b3-4406-b1ec-b4927d3e280b"
    $libraryAssertAppId = "dd0be2ea-f733-4d65-bb34-a28f4624fb14"
    $libraryVariableStorageAppId = "5095f467-0a01-4b99-99d1-9ff1237d286f"
    $systemApplicationTestLibraryAppId = "9856ae4f-d1a7-46ef-89bb-6ef056398228"
    $TestsTestLibrariesAppId = "5d86850b-0d76-4eca-bd7b-951ad998e997"
    $performanceToolkitAppId = "75f1590f-55c5-4501-ae63-bada5534e852"
    
    $performanceToolkitApps = @($performanceToolkitAppId)
    $testLibrariesApps = @($systemApplicationTestLibraryAppId, $TestsTestLibrariesAppId)
    $testFrameworkApps = @($anyAppId, $libraryAssertAppId, $libraryVariableStorageAppId) + $testLibrariesApps
    $testRunnerApps = @($permissionsMockAppId, $testRunnerAppId) + $performanceToolkitApps + $testLibrariesApps + $testFrameworkApps

    function SetSetting {
        Param(
            [PSCustomObject] $settings,
            [string] $name,
            $value
        )

        Write-Host "Set $name=$value"
        if ($settings.PSObject.Properties.Name -eq $name) {
            $settings."$name" = $value
        }
        else {
            $settings | Add-Member -MemberType NoteProperty -Name $name -Value $value
        }
    }

    function GetUniqueFolderName {
        Param(
            [string] $baseFolder,
            [string] $folderName
        )
    
        $i = 2
        $name = $folderName
        while (Test-Path (Join-Path $baseFolder $name)) {
            $name = "$folderName($i)"
            $i++
        }
        $name
    }

    function getfiles {
        Param(
            [string] $path
        )
    
        $tempdir = $false
        if ($path -like "https://*" -or $path -like "http://*") {
            $url = $path
            $path = Join-Path ([System.IO.Path]::GetTempPath()) "$([Guid]::NewGuid().ToString()).app"
            $tempdir = $true
            Download-File -sourceUrl $url -destinationFile $path
            if (!(Test-Path -Path $path)) {
                throw "could not download the file."
            }
        }
        expandfile -path $path
        if ($tempdir) {
            Remove-Item $path -Force -ErrorAction SilentlyContinue
        }
    }
    
    function expandfile {
        Param(
            [string] $path
        )

        if (Test-Path -Path $path -PathType Container) {
            $appFolders = @()
            if (Test-Path (Join-Path $path 'app.json')) {
                $appFolders += @($path)
            }
            Get-ChildItem $path -Recurse | Where-Object { $_.PSIsContainer -and (Test-Path -Path (Join-Path $_.FullName 'app.json')) } | ForEach-Object {
                if (!($appFolders -contains $_.Parent.FullName)) {
                    $appFolders += @($_.FullName)
                }
            }
            $appFolders | ForEach-Object {
                $newFolder = Join-Path ([System.IO.Path]::GetTempPath()) "$([Guid]::NewGuid().ToString())"
                write-Host "$_ -> $newFolder"
                Copy-Item -Path $_ -Destination $newFolder -Force -Recurse
                Write-Host "done"
                $newFolder
            }
            Get-ChildItem $path -include @("*.zip", "*.app") -Recurse | ForEach-Object {
                expandfile $_.FullName
            }
        }
        elseif (-not (Test-Path -Path $path -PathType Leaf)) {
            throw "Path $path does not exist"
        }    
        elseif ([string]::new([char[]](Get-Content $path @byteEncodingParam -TotalCount 2)) -eq "PK") {
            # .zip file
            $destinationPath = Join-Path ([System.IO.Path]::GetTempPath()) "$([Guid]::NewGuid().ToString())"
            Expand-7zipArchive -path $path -destinationPath $destinationPath
            $directoryInfo = Get-ChildItem $destinationPath | Measure-Object
            if ($directoryInfo.count -eq 0) {
                throw "The file is empty or malformed."
            }      
            expandfile -path $destinationPath
            Remove-Item -Path $destinationPath -Force -Recurse -ErrorAction SilentlyContinue
        }
        elseif ([string]::new([char[]](Get-Content $path @byteEncodingParam -TotalCount 4)) -eq "NAVX") {
            $destinationPath = Join-Path ([System.IO.Path]::GetTempPath()) "$([Guid]::NewGuid().ToString())"
            Extract-AppFileToFolder -appFilename $path -appFolder $destinationPath -generateAppJson
            $destinationPath        
        }
        else {
            throw "The provided file cannot be extracted. The url might be wrong or the file is malformed."
        }
    }

    try {
        invoke-git --version
    }
    catch {
        throw "You need to install Git (https://git-scm.com/) in order to use the AL-Go for GitHub setup function."
    }
    
    try {
        invoke-gh --version | Where-Object { $_ -like 'gh*' }
        invoke-gh auth status
    }
    catch {
        throw "You need to install GitHub CLI (https://cli.github.com/) in order to use the AL-Go for GitHub setup function."
    }

    try {
        $azModule = get-installedmodule -name az
        Write-Host "Az PS Module Version $($azModule.Version)"
        $context = Get-AzContext
        if (-not ($context)) {
            throw "You must run Login-AzAccount and Set-AzContext to select account and subscription"
        }
        Write-Host $context.Name
    }
    catch {
        throw "You need to install the Az PowerShell module Azure CLI (https://www.powershellgallery.com/packages/Az) in order to use the AL-Go for GitHub setup function."
    }

    if (Test-Path $tmpFolder) {
        throw "Specified folder already exists"
    }

    if ($addRepoSettings.ContainsKey('repoVersion')) {
        try {
            $version = [Version]"$($addRepoSettings.repoVersion).0.0"
        }
        catch {
            throw "addRepoSettings.repoVersion is not correctly formatted, needs to be major.minor"
        }
    }
    else {
        $version = [Version]"0.0.0.0"
    }

    if ($useOrgSecrets) {
        Write-Host -ForegroundColor Yellow "NOTE: You need to make sure your organization secrets are accessible from the repo here: https://github.com/organizations/$org/settings/secrets/actions"
    }
    elseif ($keyVaultName) {
        $keyvault = Get-AzKeyVault -name $keyVaultName -WarningAction SilentlyContinue
        $context = Get-AzContext
        if (-not ($keyVault)) {
            throw "KeyVault doesn't exist"
        }
    }

    New-Item -Path $tmpFolder -ItemType Directory | Out-Null
    Set-Location $tmpFolder

    $repository = "$org/$repo"
    invoke-gh repo create $repository --$accessControl --clone --description $description
    $folder = Join-Path $tmpFolder $repo
    Set-Location $folder

    Write-Host "Downloading and applying AL-Go-$AppType template"
    $templateUrl = "https://github.com/microsoft/AL-Go-$AppType/archive/refs/heads/$($algoBranch).zip"
    $tempZip = Join-Path ([System.IO.Path]::GetTempPath()) "$([Guid]::NewGuid().ToString()).zip"
    Download-File -sourceUrl $templateUrl -destinationFile $tempZip
    Expand-7zipArchive -Path $tempZip -DestinationPath $folder
    Remove-Item -Path $tempZip -Force
    Copy-Item -Path "AL-Go-$appType-$algoBranch\*" -Recurse -Destination . -Force
    Remove-Item -Path "AL-Go-$appType-$algoBranch" -Recurse -Force

    Write-Host "Committing and pushing template"
    invoke-git -silent add *
    invoke-git -silent commit --allow-empty -m 'template'
    invoke-git -silent branch -M $branch
    invoke-git -silent remote set-url origin "https://github.com/$repository.git"
    invoke-git -silent push --set-upstream origin $branch

    Write-Host "Reading Settings"
    $repoSettingsFile = Join-Path $folder ".github\AL-Go-Settings.json"
    $repoSettings = Get-Content $repoSettingsFile -Encoding UTF8 | ConvertFrom-Json

    $projectSettingsFile = Join-Path $folder ".AL-Go\Settings.json"
    $projectSettings = Get-Content $projectSettingsFile -Encoding UTF8 | ConvertFrom-Json

    Rename-Item -Path "al.code-workspace" -NewName "$repo.code-workspace"
    $workspaceFile = Join-Path $folder "$repo.code-workspace"
    $workspace = Get-Content $workspaceFile -Encoding UTF8 | ConvertFrom-Json

    if (-not $addProjectSettings.ContainsKey('VersioningStrategy')) {
        $addProjectSettings.VersioningStrategy = 16
    }

    [string[]] $additionalCountries = @()
    if ($addProjectSettings.ContainsKey('AdditionalCountries')) {
        $additionalCountries = [string[]] $addProjectSettings.AdditionalCountries
        if (!$additionalCountriesAlways) {
            $addProjectSettings.AdditionalCountries = @()
        }
    }

    if ($apps) {
        $apps | ForEach-Object {
            getfiles -path $_ | ForEach-Object {
                $appFolder = $_
                "?Content_Types?.xml", "MediaIdListing.xml", "navigation.xml", "NavxManifest.xml", "DocComments.xml", "SymbolReference.json" | ForEach-Object {
                    Remove-Item (Join-Path $appFolder $_) -Force -ErrorAction SilentlyContinue
                }
                $appJson = Get-Content (Join-Path $appFolder "app.json") -Encoding UTF8 | ConvertFrom-Json

                $ranges = @()
                if ($appJson.PSObject.Properties.Name -eq "idRanges") {
                    $ranges += $appJson.idRanges
                }
                if ($appJson.PSObject.Properties.Name -eq "idRange") {
                    $ranges += @($appJson.idRange)
                }
        
                $ttype = ""
                $ranges | Select-Object -First 1 | ForEach-Object {
                    if ($_.from -lt 100000 -and $_.to -lt 100000) {
                        $ttype = "PTE"
                    }
                    else {
                        $ttype = "AppSource App" 
                    }
                }
        
                if ($appJson.PSObject.Properties.Name -eq "dependencies") {
                    $appJson.dependencies | ForEach-Object {
                        if ($_.PSObject.Properties.Name -eq "AppId") {
                            $id = $_.AppId
                        }
                        else {
                            $id = $_.Id
                        }
                        if ($testRunnerApps.Contains($id)) { 
                            $ttype = "Test App"
                        }
                    }
                }

                if ($ttype -ne "Test App") {
                    Get-ChildItem -Path $appFolder -Filter "*.al" -Recurse | ForEach-Object {
                        $alContent = (Get-Content -Path $_.FullName -Encoding UTF8) -join "`n"
                        if ($alContent -like "*codeunit*subtype*=*test*[test]*") {
                            $ttype = "Test App"
                        }
                    }
                }

                if ($ttype -ne "Test App" -and $ttype -ne $AppType) {
                    Write-Host -ForegroundColor Yellow "You are adding a $ttype app into a $appType repository"
                }

                $orgfolderName = $appJson.name.Split([System.IO.Path]::getInvalidFileNameChars()) -join ""
                $folderName = GetUniqueFolderName -baseFolder $folder -folderName $orgfolderName
                if ($folderName -ne $orgfolderName) {
                    Write-Host -ForegroundColor Yellow "$orgFolderName already exists as a folder in the repo, using $folderName instead"
                }

                Move-Item -Path $appFolder -Destination $folder -Force
                Rename-Item -Path ([System.IO.Path]::GetFileName($appFolder)) -NewName $folderName
                $appFolder = Join-Path $folder $folderName

                Get-ChildItem $appFolder -Filter '*.*' -Recurse | ForEach-Object {
                    if ($_.Name.Contains('%20')) {
                        Rename-Item -Path $_.FullName -NewName $_.Name.Replace('%20', ' ')
                    }
                }

                if ($ttype -eq "Test App") {
                    $projectSettings.TestFolders += @($folderName)
                }
                else {
                    $projectSettings.AppFolders += @($folderName)
                }

                if (-not ($workspace.folders | Where-Object { $_.Path -eq $foldername })) {
                    $workspace.folders += @(@{ "path" = $foldername })
                }
            }
        }
    }

    Write-Host "Analyzing app version numbers"
    $maxVersionNumber = [Version]"0.0.0.0"
    $maxBuildNo = 0
    $projectSettings.AppFolders+$projectSettings.TestFolders | ForEach-Object {
        $appJsonFile = Join-Path $folder "$_\app.json"
        $appJson = Get-Content $appJsonFile -Encoding UTF8 | ConvertFrom-Json
        $appVersion = [Version]$appJson.Version
        if ($appVersion -gt $maxVersionNumber) {
            $maxVersionNumber = $appVersion
        }
        if ($appVersion.Build -ge $maxBuildNo) {
            $maxBuildNo = $appVersion.Build+1
        }
    }

    if (($addProjectSettings.VersioningStrategy -band 16) -eq 16) {
        if (-not $addRepoSettings.ContainsKey('repoVersion')) {
            $addRepoSettings.repoVersion = "$($maxVersionNumber.Major).$($maxVersionNumber.Minor+1)"
            $version = [Version]"$($addRepoSettings.repoVersion).0.0"
        }
        $projectSettings.AppFolders+$projectSettings.TestFolders | ForEach-Object {
            $appJsonFile = Join-Path $folder "$_\app.json"
            $appJson = Get-Content $appJsonFile -Encoding UTF8 | ConvertFrom-Json
            $appVersion = [Version]$appJson.Version
            if ([Version]$appJson.Version -gt $version) {
                Write-Host -ForegroundColor Yellow "WARNING: Version number of app in $_ was $($appJson.Version), will be set to $version, meaning that you will not be able to upgrade existing installations to this new version"
            }
            $appJson.Version = "$version"
            $appJson | ConvertTo-Json -Depth 99 | Set-Content $appJsonFile -Encoding UTF8
        }
    }
    else {
        $addRepoSettings.repoVersion = "1.0"
        if (($addProjectSettings.VersioningStrategy -band 15) -eq 0) {
            SetSetting -settings $repoSettings -name "RunNumberOffset" -value $maxBuildNo
        }
    }

    Write-Host "Updating Repo Settings"
    $addRepoSettings.Keys | ForEach-Object {
        Write-Host "- $_ = $($addRepoSettings."$_")"
        SetSetting -settings $repoSettings -name $_ -value $addRepoSettings."$_"
    }

    Write-Host "Updating Project Settings"
    $addProjectSettings.Keys | ForEach-Object {
        Write-Host "- $_ = $($addProjectSettings."$_")"
        SetSetting -settings $projectSettings -name $_ -value $addProjectSettings."$_"
    }

    $orgSecrets = @(invoke-gh -returnValue secret list --org $Org -ErrorAction SilentlyContinue)

    if ($keyVaultName) {
        if ($useOrgSecrets -and ($orgSecrets | Where-Object { $_ -like "AZURE_CREDENTIALS`t*" })) {
            SetSetting -settings $repoSettings -name "KeyVaultName" -value $keyvault.VaultName
        }
        else {
            if (!$secrets.Contains('AZURE_CREDENTIALS')) {
                $secrets.AZURE_CREDENTIALS = "$org/$repo"
            }
            if (!$secrets.AZURE_CREDENTIALS.StartsWith('{')) {
                Write-Host "Creating Service Principal for $($secrets.AZURE_CREDENTIALS) to access KeyVault $keyVaultName using get, list"
                $adsp = New-AzADServicePrincipal -DisplayName $secrets.AZURE_CREDENTIALS -Role reader -Scope "/subscriptions/$($context.Subscription.Id)/resourceGroups/$($keyvault.ResourceGroupName)/providers/Microsoft.KeyVault/vaults/$($keyvault.VaultName)"
                Set-AzKeyVaultAccessPolicy -VaultName $keyvault.VaultName -PermissionsToSecrets get,list -ObjectId $adsp.Id
                $authContext = @{
                    "clientId" = $adsp.AppId
                    "clientSecret" = $adsp.PasswordCredentials.secrettext
                    "subscriptionId" = $context.Subscription.Id
                    "tenantId" = $context.Tenant.Id
                    "KeyVaultName" = $keyvault.VaultName
                }
                $secrets.AZURE_CREDENTIALS = "$($authContext | ConvertTo-Json -Compress)"
            }
            if ($useOrgSecrets) {
                Write-Host "Creating organizational secret AZURE_CREDENTIALS with access to KeyVault"
                invoke-gh -silent secret set AZURE_CREDENTIALS --org $Org --body $secrets.AZURE_CREDENTIALS --visibility selected --repos $repo
            }
            else {
                Write-Host "Creating repository secret AZURE_CREDENTIALS with access to KeyVault"
                invoke-gh -silent secret set AZURE_CREDENTIALS --body $secrets.AZURE_CREDENTIALS
            }
        }
    }

    $secrets.Keys | ForEach-Object {
        $key = $_
        $value = $secrets."$key"
        if ($key -ne "AZURE_CREDENTIALS" -and ($value)) {
            if ($useOrgSecrets) {
                Write-Host "Creating organizational secret $key with value $value in $Org"
                invoke-gh -silent secret set $key --org $Org --body $value --visibility selected --repos $repo
            }
            else {
                Write-Host "Creating repository secret $key"
                invoke-gh -silent secret set $key --body $value
            }
        }
    }

    'NextMajor','NextMinor','Current' | ForEach-Object {
        $name = "$($_)Schedule"
        if ($addRepoSettings.ContainsKey($name)) {
            $value = $repoSettings."$name"
            $workflowFile = ".github\workflows\$_.yaml"
            $srcContent = (Get-Content -Path $workflowFile -Encoding UTF8 -Raw).Replace("`r", "").TrimEnd("`n").Replace("`n", "`r`n")
            if ($value) {
                SetSetting -settings $repoSettings -name $name -value $value
                $srcPattern = "on:`r`n  workflow_dispatch:`r`n"
                $replacePattern = "on:`r`n  schedule:`r`n  - cron: '$($value)'`r`n  workflow_dispatch:`r`n"
                $srcContent = $srcContent.Replace($srcPattern, $replacePattern)
                Set-Content -Path $workflowFile -Encoding UTF8 -Value $srcContent
            }
            if (!$additionalCountriesAlways -and $additionalCountries) {
                $workflowSettingsFile = Join-Path $folder ".github\$($srcContent.Split("`r")[0].Substring(6).Trim("'").Trim(' ')).settings.json"
                $workflowSettings = Get-Content $workflowSettingsFile -Encoding UTF8 | ConvertFrom-Json
                SetSetting -settings $workflowSettings -name "AdditionalCountries" -value $additionalCountries
                $workflowSettings | ConvertTo-Json -Depth 99 | Set-Content -Path $workflowSettingsFile -Encoding UTF8
            }
        }
    }

    Write-Host "Writing Settings"
    $repoSettings | ConvertTo-Json -Depth 99 | Set-Content -Path $repoSettingsFile -Encoding UTF8
    $projectSettings | ConvertTo-Json -Depth 99 | Set-Content -Path $projectSettingsFile -Encoding UTF8
    $workspace | ConvertTo-Json -Depth 99 | Set-Content -Path $workspaceFile -Encoding UTF8

    Write-Host "Setting README.md content"
    Set-Content -Path (Join-Path $folder "README.md") -Value $readme

    Write-Host "Pushing Changes"
    invoke-git -silent add *
    invoke-git -silent commit --allow-empty -m "initial commit"
    invoke-git -silent push

    Write-Host "https://github.com/$repository"
    if ($openBrowser) {
        Start-Process "https://github.com/$repository"
    }

    if ($openVSCode) {
        code "$tmpFolder\$repo\$repo.code-workspace"
    }
    elseif ($openFolder) {
        Start-Process "$tmpFolder\$repo"
    }
    else {
        $tmpFolder
    }
}
Export-ModuleMember -Function New-ALGoRepo

# SIG # Begin signature block
# MIInbgYJKoZIhvcNAQcCoIInXzCCJ1sCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDaKRvizXP9CUfC
# LeWynbEpMq1Md5EFDTn8TVZgQAg3baCCDMkwggYEMIID7KADAgECAhMzAAACHPrN
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
# hvcNAQkEMSIEIDC0h3woDitR/QFHAeGd01VXz3i4vNxRUuLF6Vutp+3xMEIGCisG
# AQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEACpVvyOYZtXsD41LTmpJ5
# gpgEdrcxT6MkDVJAEKpTpNEKSrQcPSWq5gk6O3RIe96/+RAsVLdY8lw96f2Csn8D
# m61xnm7nlM1qsH8Ojj9522zecip3+u+Z3N1L+S5+2nz2uTOCM3IhYsHBbPKM5aMw
# NT/Tkzztu0I8U22kuzsNY0yhLgblbI4DE/eHNa7jdkYhso2XklY61OqvZkjp6Vtk
# EZ4XbB0e/QFoA58SLD2d8e8vAqOkQFyrRZhF0CBBLcC8LIbsyRMCMnq5IlNbmWix
# 4JrjOk3KyB/lbS3GhuseJYdhAfHNQHMfcgoVfnZZR6L8qZZA7RqBCGb7tZMg+Zc6
# yaGCF60wghepBgorBgEEAYI3AwMBMYIXmTCCF5UGCSqGSIb3DQEHAqCCF4YwgheC
# AgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFFMIIB
# QQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCCOWI5/oMM6wWsXMugO
# gCuz9FqU7ycPjBYyMCyVe6XGEgIGaomzDM4nGBMyMDI2MDgyNzA2MjkzNi41MDFa
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
# dGFtcCBQQ0EgMjAxMDANBgkqhkiG9w0BAQsFAAIFAO46H9UwIhgPMjAyNjA4Mjcw
# MjMwNDVaGA8yMDI2MDgyODAyMzA0NVowdDA6BgorBgEEAYRZCgQBMSwwKjAKAgUA
# 7jof1QIBADAHAgEAAgITszAHAgEAAgISuTAKAgUA7jtxVQIBADA2BgorBgEEAYRZ
# CgQCMSgwJjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0G
# CSqGSIb3DQEBCwUAA4IBAQBEU2jxUxxrZde6txcqjj2OfnCfGTfxgpIJBh7Xl3gT
# cHOkOJMAjkqDPvB0FrTPyTj3H+NH5fug21DCj9kGnsHJanhyW2PWg3m2WleCpv00
# NcS4w1vL7nzrJkNeuG0qlQFo3gGzSdRC2DOtZtAVADwpvDEWlEJ8r05AIB7jeEif
# AYTG3pTdv+6m1S9Qz3u9z45tf+xn4hBCWyr2mmT2+HoAZkeaLd488xl8W3TZTkcf
# /3Zm+zvsoHFDl3donmPPxhDnGtyd/uJ8ECTz1xzsFRyIuYxDdhrtXbNbhl0PEEIW
# QH9Sgg7+MeJIzW0CXJv35FleyEu9tkxf0d3gsSdqhLIDMYIEDTCCBAkCAQEwgZMw
# fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMd
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAIb0LK4Amf3cs8AAQAA
# AhswDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRAB
# BDAvBgkqhkiG9w0BCQQxIgQgfwTXdYgPq+1tJ+qYX1LnGcVleyrCbnzi7po8wkX7
# dgEwgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCAwJRSVuD2jmMcQCFXdLuJA
# wDpUVNZ6bc6dfJU83Q2LgDCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBD
# QSAyMDEwAhMzAAACG9CyuAJn93LPAAEAAAIbMCIEILpX2zOE3yRmSrEbYyB6Qah4
# staWGvdg0j8vh4PpXwO4MA0GCSqGSIb3DQEBCwUABIICAFb1fW2XaLk/8Qmqmkbm
# 7urvJeDB+hOS2TrdMCWwk8rkPq1VROOuy/spEtar6XLDd+BHas9fQ1noAUlDe7RX
# /hIqFDzcHctv/Cn1ufPIGQ62z39xWz7qApu6hEhA/XDtRHz3WVqsg5BSph/v8F09
# ljiq/uAlKwaVbaabovpoFVyiWvFYIQ1g6VNfm24S1JbQHb6YxWRfwkB/SlC4ef11
# mkVGO6jjdqGCX4K0p64tWlI9976Afpv9zNot+ktrlvOKGs7PHRio5VThJ3MEzWbW
# RFpA1Hfe0Nj5C+JdgOaVdYvxOsKTcjQ1pARB5u0/wQnGHR4bSvCFPrIZcc8mY6vn
# Ywb9QPhvr3WnwmN8eVZDCHrbiNT4eqTNEkIWPwZCtKM/XqNM1SCwxJ0jdo8rhu7m
# 0vP/tnSb7PwK0Qn2oDpaHyv/fCRJyGh7899p80DXDDo0svZgMg0cYoi4X/L5TOlo
# CSxSx9xo5mCtcNrah0vySQILPgiLOADWN4i1F/+s20IjJlFmAh6rsAR8P2LyJXOq
# M8B8e/Oo5iPNvvmJo8NN+IpQdJOWZgqJVdc+wF1/9mlR1+zWt5NUusvQ6BCGZe7k
# 8KgOLNBNZdnCLUmDRL8n/rLGB3pGvt4Teg25YdYwD6UzRLwKVWFqlh1rsr6eMB7P
# aswwEXherSncjrjQQc/8aeDK
# SIG # End signature block
