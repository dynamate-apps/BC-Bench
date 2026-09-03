Param(
    [switch] $skipContainerHelperCheck,
    [string] $predefinedpw = 'P@ssw0rd'
)

# create script for running docker

$ErrorActionPreference = "stop"

function Select-Value {
    Param(
        [Parameter(Mandatory=$false)]
        [string] $title,
        [Parameter(Mandatory=$false)]
        [string] $description,
        [Parameter(Mandatory=$true)]
        $options,
        [Parameter(Mandatory=$false)]
        [string] $default = "",
        [Parameter(Mandatory=$true)]
        [string] $question,
        [switch] $doNotClearHost = ($host.name -ne "ConsoleHost"),
        [switch] $writeAnswer = ($host.name -ne "ConsoleHost"),
        [switch] $previousStep
    )

    if (!$doNotClearHost) {
        Clear-Host
    }

    if ($title) {
        Write-Host -ForegroundColor Yellow $title
        Write-Host
    }
    if ($description) {
        Write-Host $description
        Write-Host
    }
    $offset = 0
    $defaultChr = -1
    $keys = @()
    $values = @()

    $options.GetEnumerator() | ForEach-Object {
        Write-Host -ForegroundColor Yellow "$([char]($offset+97)) " -NoNewline
        $keys += @($_.Key)
        $values += @($_.Value)
        if ($_.Key -eq $default) {
            Write-Host -ForegroundColor Yellow $_.Value
            $defaultAnswer = $offset
        }
        else {
            Write-Host $_.Value
        }
        $offset++     
    }
    Write-Host
    if ($script:thisStep -lt 100) {
        if (($default) -and !$script:acceptDefaults) {
            Write-Host -ForegroundColor Yellow "!" -NoNewline
            Write-Host " accept default answers for the remaining questions"
        }
        if ($previousStep) {
            Write-Host -ForegroundColor Yellow "x" -NoNewline
            Write-Host " start over"
            Write-Host -ForegroundColor Yellow "z" -NoNewline
            Write-Host " go back"
        }
        if (($default) -or ($previousStep)) {
            Write-Host
        }
    }
    $answer = -1
    do {
        Write-Host "$question " -NoNewline
        if ($defaultAnswer -ge 0) {
            Write-Host "(default $([char]($defaultAnswer + 97))) " -NoNewline
        }
        if ($script:acceptDefaults -and $defaultAnswer -ge 0) {
            $selection = ""
        }
        else {
            $selection = (Read-Host).ToLowerInvariant()
        }
        if ($selection -eq "!" -and ($default)) {
            $selection = ""
            $script:acceptDefaults = $true
            Write-Host $defaultAnswer
        }
        if ($previousStep) {
            if ($selection -eq "x") {
                if ($writeAnswer) {
                    Write-Host
                    Write-Host -ForegroundColor Green "Start over selected"
                    Write-Host
                }
                $script:acceptDefaults = $false
                $script:wizardStep = 0
                $script:prevSteps = New-Object System.Collections.Stack
                $script:prevSteps.Push(1)
                return "Back"
            }
            if ($selection -eq "z") {
                if ($writeAnswer) {
                    Write-Host
                    Write-Host -ForegroundColor Green "Back selected"
                    Write-Host
                }
                $script:acceptDefaults = $false
                $script:wizardStep = $script:prevSteps.Pop()
                return "Back"
            }
        }
        if ($selection -eq "") {
            if ($defaultAnswer -ge 0) {
                $answer = $defaultAnswer
            }
            else {
                Write-Host -ForegroundColor Red "No default value exists. " -NoNewline
            }
        }
        else {
            if (($selection.Length -ne 1) -or (([int][char]($selection)) -lt 97 -or ([int][char]($selection)) -ge (97+$offset))) {
                Write-Host -ForegroundColor Red "Illegal answer. " -NoNewline
            }
            else {
                $answer = ([int][char]($selection))-97
            }
        }
        if ($answer -eq -1) {
            if ($offset -eq 2) {
                Write-Host -ForegroundColor Red "Please answer one letter, a or b"
            }
            else {
                Write-Host -ForegroundColor Red "Please answer one letter, from a to $([char]($offset+97-1))"
            }
        }
    } while ($answer -eq -1)

    if ($writeAnswer) {
        Write-Host
        Write-Host -ForegroundColor Green "$($values[$answer]) selected"
        Write-Host
    }
    $keys[$answer]
}

function Enter-Value {
    Param(
        [Parameter(Mandatory=$false)]
        [string] $title,
        [Parameter(Mandatory=$false)]
        [string] $description,
        [Parameter(Mandatory=$false)]
        $options,
        [Parameter(Mandatory=$false)]
        [string] $default = "",
        [Parameter(Mandatory=$true)]
        [string] $question,
        [switch] $doNotClearHost = ($host.name -ne "ConsoleHost"),
        [switch] $writeAnswer = ($host.name -ne "ConsoleHost"),
        [switch] $doNotConvertToLower,
        [switch] $previousStep
    )

    if (!$doNotClearHost) {
        Clear-Host
    }

    if ($title) {
        Write-Host -ForegroundColor Yellow $title
        Write-Host
    }
    if ($description) {
        Write-Host $description
        Write-Host
    }
    if ($script:thisStep -lt 100) {
        if (($default) -and !$script:acceptDefaults) {
            Write-Host -ForegroundColor Yellow "!" -NoNewline
            Write-Host " accept default answers for the remaining questions"
        }
        if ($previousStep) {
            Write-Host "Enter " -NoNewline
            Write-Host -ForegroundColor Yellow "x" -NoNewline
            Write-Host " to start over"
            Write-Host "Enter " -NoNewline
            Write-Host -ForegroundColor Yellow "z" -NoNewline
            Write-Host " to go back"
        }
        if (($default) -or ($previousStep)) {
            Write-Host
        }
    }
    $answer = ""
    do {
        Write-Host "$question " -NoNewline
        if ($options) {
            Write-Host "($([string]::Join(', ', $options))) " -NoNewline
        }
        if ($default) {
            Write-Host "(default $default) " -NoNewline
        }
        if ($script:acceptDefaults -and ($default)) {
            $selection = ""
            Write-Host $default
        }
        elseif ($doNotConvertToLower) {
            $selection = Read-Host
        }
        else {
            $selection = (Read-Host).ToLowerInvariant()
        }
        if ($selection -eq "!" -and ($default)) {
            $selection = ""
            $script:acceptDefaults = $true
        }
        if ($selection -eq "") {
            if ($default) {
                $answer = $default
            }
            else {
                Write-Host -ForegroundColor Red "No default value exists. "
            }
        }
        elseif ($selection -eq "x" -and $previousStep) {
            if ($writeAnswer) {
                Write-Host
                Write-Host -ForegroundColor Green "Exit selected"
                Write-Host
            }
            $script:acceptDefaults = $false
            $script:wizardStep = 0
            $script:prevSteps = New-Object System.Collections.Stack
            $script:prevSteps.Push(1)
            return "back"
        }
        elseif ($selection -eq "z" -and $previousStep) {
            if ($writeAnswer) {
                Write-Host
                Write-Host -ForegroundColor Green "Back selected"
                Write-Host
            }
            $script:acceptDefaults = $false
            $script:wizardStep = $script:prevSteps.Pop()
            return "back"
        }
        else {
            if ($options) {
                $answer = $options | Where-Object { $_ -eq $selection }
                if (-not ($answer)) {
                    $answer = $options | Where-Object { $_ -like "$selection*" }
                    if (-not ($answer)) {
                        Write-Host -ForegroundColor Red "Illegal answer. Please answer one of the options."
                    }
                    elseif ($answer -is [Array]) {
                        Write-Host -ForegroundColor Red "Multiple options match the answer. Please answer one of the options that matched the previous selection."
                        $options = $answer
                        $answer = $null
                    }
                }
            }
            else {
                $answer = $selection
            }
        }
    } while (-not ($answer))

    if ($writeAnswer) {
        Write-Host
        Write-Host -ForegroundColor Green "$answer selected"
        Write-Host
    }
    $answer
}

function randomchar([string]$str)
{
    $rnd = Get-Random -Maximum $str.length
    [string]$str[$rnd]
}

function Get-RandomPassword {
    $cons = 'bcdfghjklmnpqrstvwxz'
    $voc = 'aeiouy'
    $numbers = '0123456789'

    ((randomchar $cons).ToUpper() + `
     (randomchar $voc) + `
     (randomchar $cons) + `
     (randomchar $voc) + `
     (randomchar $numbers) + `
     (randomchar $numbers) + `
     (randomchar $numbers) + `
     (randomchar $numbers))
}

Clear-Host

$pshost = Get-Host
$pswindow = $pshost.UI.RawUI
$minWidth = 150

if (($pswindow.BufferSize) -and ($pswindow.WindowSize) -and ($pswindow.WindowSize.Width -lt $minWidth)) {
    $buffersize = $pswindow.BufferSize
    $buffersize.width = $minWidth
    try {
        $pswindow.buffersize = $buffersize
    }
    catch {}
    
    $newsize = $pswindow.windowsize
    $newsize.width = $minWidth
    try {
        $pswindow.windowsize = $newsize
    }
    catch {}
}

$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdministrator = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$randompw = Get-RandomPassword
$os = (Get-CimInstance Win32_OperatingSystem)
if ($os.OSType -ne 18 -or !$os.Version.StartsWith("10.0.")) {
    throw "Unknown Host Operating System"
}
$UBR = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name UBR).UBR
$hostOsVersion = [System.Version]::Parse("$($os.Version).$UBR")
$ErrorActionPreference = "STOP"

$script:wizardStep = 0
$script:acceptDefaults = $false

$Step = @{
    "BcContainerHelper"  = 0
    "AcceptEula"         = 1
    "Hosting"            = 2
    "Authentication"     = 3
    "ContainerName"      = 4
    "Version"            = 5
    "Version2"           = 7
    "Country"            = 8
    "TestToolkit"        = 9
    "PerformanceToolkit" = 10
    "PremiumPlan"        = 11
    "CreateTestUsers"    = 12
    "IncludeAL"          = 20
    "ExportAlSource"     = 21
    "IncludeCSIDE"       = 22
    "ExportCAlSource"    = 23
    "Vsix"               = 24
    "License"            = 30
    "Database"           = 31
    "Multitenant"        = 32
    "DNS"                = 35
    "SSL"                = 36
    "Isolation"          = 40
    "Memory"             = 41
    "SaveImage"          = 50
    "Special"            = 60
    "Final"              = 100
}

$script:prevSteps = New-Object System.Collections.Stack
$script:prevSteps.Push(1)

while ($script:wizardStep -le 100) {

$script:thisStep = $script:wizardStep
$script:wizardStep++

switch ($script:thisStep) {
$Step.BcContainerHelper {
Write-Host -ForegroundColor Yellow @'
  ____        _____            _        _                 _    _      _                 
 |  _ \      / ____|          | |      (_)               | |  | |    | |                
 | |_) | ___| |     ___  _ __ | |_ __ _ _ _ __   ___ _ __| |__| | ___| |_ __   ___ _ __ 
 |  _ < / __| |    / _ \| '_ \| __/ _` | | '_ \ / _ \ '__|  __  |/ _ \ | '_ \ / _ \ '__|
 | |_) | (__| |____ (_) | | | | |_ (_| | | | | |  __/ |  | |  | |  __/ | |_) |  __/ |   
 |____/ \___|\_____\___/|_| |_|\__\__,_|_|_| |_|\___|_|  |_|  |_|\___|_| .__/ \___|_|   
                                                                       | |              
                                                                       |_|              
'@
    if (!$skipContainerHelperCheck) {
        $module = Get-InstalledModule -Name "BcContainerHelper" -ErrorAction SilentlyContinue
        if (!($module)) {
            $module = Get-Module -Name "BcContainerHelper" -ErrorAction SilentlyContinue
        }
        if (!($module)) {
            Write-Host -ForegroundColor Red "This script has a dependency on the PowerShell module BcContainerHelper."
            Write-Host -ForegroundColor Red "See more here: https://www.powershellgallery.com/packages/bccontainerhelper"
            Write-Host -ForegroundColor Red "Use 'Install-Module BcContainerHelper -force' to install in PowerShell"
            return
        }
        elseif ($module.Version -eq "0.0") {
            Write-Host -ForegroundColor Green "You are running BcContainerHelper developer version"
            Write-Host
        }
        else {
            $myVersion = $module.Version.ToString()
            $prerelease = $myVersion.Contains("-preview")
            if ($prerelease) {
                $latestVersion = (Find-Module -Name bccontainerhelper -AllowPrerelease).Version
                $previewStr = "Prerelease version "
            }
            else {
                $latestVersion = (Find-Module -Name bccontainerhelper).Version
                $previewStr = ""
            }
            if ($latestVersion -eq $myVersion) {
                Write-Host -ForegroundColor Green "You are running BcContainerHelper $previewStr$myVersion (which is the latest version)"
            }
            else {
                Write-Host -ForegroundColor Yellow "You are running BcContainerHelper $previewStr$myVersion. A newer version ($latestVersion) exists, please consider updating."
            }
            Write-Host
        }
    }
}

$Step.AcceptEula {
    
    $acceptEula = Enter-Value `
        -title @'
                             _     ______      _       
     /\                     | |   |  ____|    | |      
    /  \   ___ ___ ___ _ __ | |_  | |__  _   _| | __ _ 
   / /\ \ / __/ __/ _ \ '_ \| __| |  __|| | | | |/ _` |
  / ____ \ (__ (__  __/ |_) | |_  | |____ |_| | | (_| |
 /_/    \_\___\___\___| .__/ \__| |______\__,_|_|\__,_|
                      | |                              
                      |_|                              
'@ `
        -Description "This script will generate a script, which can be used to run Business Central in Docker on your computer.`nYou will be asked a number of questions and the generated script should create a container, which matches your needs.`n`nIn order to run Business Central in Docker, you will need to accept the eula.`nThe supplemental license terms for running Business Central and NAV on Docker can be found here: https://go.microsoft.com/fwlink/?linkid=861843" `
        -options @("Y","N") `
        -question "Please enter Y if you accept the eula"
    if ($acceptEula -ne "Y") {
        Write-Host -ForegroundColor Red "Eula not accepted, aborting..."
        return
    }
    if ($script:wizardStep -eq $script:thisStep+1) {
        $script:prevSteps.Push($script:thisStep)
    }
}

$Step.Hosting {

    $hosting = Select-Value `
        -title @'
  _                     _    _____            _        _                                                             __      ____  __ 
 | |                   | |  / ____|          | |      (_)                                  /\                        \ \    / /  \/  |
 | |     ___   ___ __ _| | | |     ___  _ __ | |_ __ _ _ _ __   ___ _ __    ___  _ __     /  \   _____   _ _ __ ___   \ \  / /| \  / |
 | |    / _ \ / __/ _` | | | |    / _ \| '_ \| __/ _` | | '_ \ / _ \ '__|  / _ \| '__|   / /\ \ |_  / | | | '__/ _ \   \ \/ / | |\/| |
 | |____ (_) | (__ (_| | | | |____ (_) | | | | |_ (_| | | | | |  __/ |    | (_) | |     / ____ \ / /| |_| | | |  __/    \  /  | |  | |
 |______\___/ \___\__,_|_|  \_____\___/|_| |_|\__\__,_|_|_| |_|\___|_|     \___/|_|    /_/    \_\___|\__,_|_|  \___|     \/   |_|  |_|
                                                                                                                                      
'@ `
        -description "Specify where you want to host your Business Central container?`n`nSelecting Local will create a script that needs to run on a computer, which have Docker installed.`nSelecting Azure VM shows a Url with which you can create a VM. This requires an Azure Subscription." `
        -options ([ordered]@{"Local" = "Local docker container"; "AzureVM" = "Docker container in an Azure VM"}) `
        -question "Hosting" `
        -default "Local" `
        -previousStep
    if ($script:wizardStep -eq $script:thisStep+1) {
        $script:prevSteps.Push($script:thisStep)
    }
}

$Step.Authentication {
    if ($hosting -eq "Local") {

        $auth = Select-Value `
            -title @'
                _   _                _   _           _   _             
     /\        | | | |              | | (_)         | | (_)            
    /  \  _   _| |_| |__   ___ _ __ | |_ _  ___ __ _| |_ _  ___  _ __  
   / /\ \| | | | __| '_ \ / _ \ '_ \| __| |/ __/ _` | __| |/ _ \| '_ \ 
  / ____ \ |_| | |_| | | |  __/ | | | |_| | (__ (_| | |_| | (_) | | | |
 /_/    \_\__,_|\__|_| |_|\___|_| |_|\__|_|\___\__,_|\__|_|\___/|_| |_|

'@ `
            -description "Select desired authentication mechanism.`nSelecting predefined credentials means that the script will use hardcoded credentials.`n`nNote: When using Windows authentication, you need to use your Windows Credentials from the host computer and if the computer is domain joined, you will need to be connected to the domain while running the container. You cannot use containers with Windows authentication when offline." `
            -options ([ordered]@{"UserPassword" = "Username/Password authentication"; "Credential" = "Username/Password authentication (admin with predefined password - $predefinedpw)"; "Random" = "Username/Password authentication (admin with random password - $randompw)"; "Windows" = "Windows authentication"}) `
            -question "Authentication" `
            -default "Credential" `
            -previousStep
        if ($script:wizardStep -eq $script:thisStep+1) {
            $script:prevSteps.Push($script:thisStep)
        }
    }
    else {
        $auth = "UserPassword"
    }
}

$Step.ContainerName {
    if ($hosting -eq "Local") {

        $containerName = Enter-Value `
            -title @'
   _____            _        _                   _   _                      
  / ____|          | |      (_)                 | \ | |                     
 | |     ___  _ __ | |_ __ _ _ _ __   ___ _ __  |  \| | __ _ _ __ ___   ___ 
 | |    / _ \| '_ \| __/ _` | | '_ \ / _ \ '__| | . ` |/ _` | '_ ` _ \ / _ \
 | |____ (_) | | | | |_ (_| | | | | |  __/ |    | |\  | (_| | | | | | |  __/
  \_____\___/|_| |_|\__\__,_|_|_| |_|\___|_|    |_| \_|\__,_|_| |_| |_|\___|
                                                                            
'@ `
            -description "Enter the name of the container.`nContainer names are case sensitive and must start with a letter.`n`nNote: We recommend short lower case names as container names." `
            -question "Container name" `
            -default "bcserver" `
            -previousStep
        if ($script:wizardStep -eq $script:thisStep+1) {
            $script:prevSteps.Push($script:thisStep)
        }
    }
    else {
        $containerName = $bcContainerHelperConfig.defaultContainerName
    }
}

$Step.Version {

    if ($hosting -eq "local") { $back = 4 } else { $back = 2 }
    $predef = Select-Value `
        -title @'
 __      __           _             
 \ \    / /          (_)            
  \ \  / /__ _ __ ___ _  ___  _ __  
   \ \/ / _ \ '__/ __| |/ _ \| '_ \ 
    \  /  __/ |  \__ \ | (_) | | | |
     \/ \___|_|  |___/_|\___/|_| |_|

'@ `
        -description "What version of Business Central do you need?`nIf you are developing a Per Tenant Extension for a Business Central Saas tenant, you need a Business Central Sandbox environment" `
        -options ([ordered]@{
            "LatestSandbox" = "Latest Business Central Sandbox"
            "LatestOnPrem" = "Latest Business Central OnPrem"
            "Next Major" = "Insider Business Central Sandbox for Next Major release (you automatically accept the insider EULA (https://go.microsoft.com/fwlink/?linkid=2245051) by using this option)"
            "Next Minor" = "Insider Business Central Sandbox for Next Minor release (you automatically accept the insider EULA (https://go.microsoft.com/fwlink/?linkid=2245051) by using this option)"
            "SpecificSandbox" = "Specific Business Central Sandbox build (requires version number)"
            "SpecificOnPrem" = "Specific Business Central OnPrem build (requires version number)"
            "NAV2018" = "Specific NAV 2018 version"
            "NAV2017" = "Specific NAV 2017 version"
            "NAV2016" = "Specific NAV 2016 version"
        }) `
        -question "Version" `
        -default "LatestSandbox" `
        -writeAnswer `
        -previousStep
    if ($script:wizardStep -eq $script:thisStep+1) {
        $script:prevSteps.Push($script:thisStep)
    }
}

$Step.Version2 {

    $fullVersionNo = $false
    $select = "Latest"
    $storageAccount = "bcartifacts"
    $nav = ""
    if ($predef -like "latest*") {
        $type = $predef.Substring(6)
        $version = ''
    }
    elseif ($predef -like "Next*") {
        $type = "Sandbox"
        $version = ''
        $storageAccount = "bcinsider"
        if ($predef -eq "Next Minor") {
            $select = "SecondToLastMajor"
        }
    }
    elseif ($predef -like "NAV*") {
        $nav = $predef.Substring(3)
        $type = "Onprem"
        $ok = $false
        do {
            $cus = Get-NavArtifactUrl -nav $nav -country 'w1' -select All
            $cu = Enter-Value `
                -description "NAV $nav has $($cus.Count-1) released cumulative updates." `
                -question "Enter CU number (0 is rtm or leave blank for latest)" `
                -default "latest" `
                -doNotClearHost `
                -writeAnswer `
                -previousStep
            
            if ($cu -eq "back") {
                $ok = $true
            }
            else {
                $cuno = $cus.Count-1
                if ($cu -eq "latest" -or ([int]::TryParse($cu, [ref]$cuno) -and ($cuno -ge 0) -and ($cuno -lt $($cus.Count)))) {
                    $ok = $true
                    $version = $cus[$cuno].split('/')[4]
                }
            }
        } while (!$ok)
        if ($script:wizardStep -eq $script:thisStep+1) {
            $script:prevSteps.Push($script:thisStep)
        }
    }
    elseif ($predef -like "specific*") {
        $type = $predef.Substring(8)
        $ok = $false
        do {
            $version = Enter-Value `
                -description "Specify version number.`nIf you specify a full version number (like 15.4.41023.41345), you will get the closest version.`nIf multiple versions matches the entered value, you will be asked to select" `
                -question "Enter version number (format major[.minor[.build[.release]]])" `
                -doNotClearHost `
                -writeAnswer `
                -previousStep
            
            if ($version -eq "back") {
                $ok = $true
            }
            else {
                if ($version.indexOf('.') -eq -1) {
                    $verno = 0
                    $ok = [int32]::TryParse($version, [ref]$verno)
                    if (!$ok) {
                        Write-Host -ForegroundColor Red "Illegal version number"
                    }
                }
                else {
                    $verno = [Version]"0.0.0.0"
                    $ok = [Version]::TryParse($version, [ref]$verno)
                    if (!$ok) {
                        Write-Host -ForegroundColor Red "Illegal version number"
                    }
                    $fullVersionNo = $verno.Revision -ne -1
                }
    
                if ($ok) {

                    if ($fullVersionNo) {
                        $select = "Closest"
                        $artifactUrl = Get-BCArtifactUrl -type $type -version $version -country 'w1' -select 'Closest'
                        if ($artifactUrl) {
                            $foundVersion = $artifactUrl.split('/')[4]
                            if ($foundVersion -ne $version) {
                                Write-Host -ForegroundColor Yellow "The specific version doesn't exist, closest version is $foundVersion"
                            }
                        }
                    }
                    else {
                        $versions = @()
                        Get-BCArtifactUrl -type $type -version $version -country 'w1' -select All | ForEach-Object {
                            $versions += $_.Split('/')[4]
                        }
                        if ($versions.Count -eq 0) {
                            Write-Host -ForegroundColor Red "Unable to find a version matching the specified version"
                            $ok = $false
                        }
                        elseif ($versions.Count -gt 1) {
                            $version = Enter-Value `
                                -options $versions `
                                -question "Select specific version" `
                                -doNotClearHost `
                                -writeAnswer `
                                -previousStep
    
                            if ($version -eq "back") {
                                $ok = $true
                            }
                            else {
                                $fullVersionNo = $true
                            }
                        }
                    }
                }
            }
        } while (!$ok)
        if ($script:wizardStep -eq $script:thisStep+1) {
            $script:prevSteps.Push($script:thisStep)
        }
    }
}

$Step.Country {

    Write-Host "Analyzing artifacts"
    $versionno = $version
    if ($versionno -eq "") {
        $searchCountry = "us"
        if ($type -eq 'sandbox') { $searchCountry = "at" }
        $aurl = Get-BcArtifactUrl -storageAccount $storageAccount -type $type -country $searchCountry -select $select -accept_insiderEula
        $versionno = $aurl.split('/')[4]
    }
    $majorVersion = [int]($versionno.Split('.')[0])
    $countries = @()
    Get-BCArtifactUrl -storageAccount $storageAccount -type $type -version $versionno -select All -accept_insiderEula | ForEach-Object {
        $countries += $_.SubString($_.LastIndexOf('/')+1).Split('?')[0]
    }
    $description = ""
    if ($version -ne "") {
        $description += "Version $version selected`n`n"
    }
    else {
        $description += "Version $versionno identified`n`n"
    }
    if ($type -eq "Sandbox") {
        $default = "us"
        $description += "Please select which country version you want to use.`n`nNote: base is the onprem w1 demodata running in sandbox mode."
    }
    else {
        $default = "w1"
        $description += "Please select which country version you want to use.`n`nNote: NA contains US, CA and MX."
    }

 
    $country = Enter-Value `
        -title @'
   _____                  _              
  / ____|                | |             
 | |     ___  _   _ _ __ | |_ _ __ _   _ 
 | |    / _ \| | | | '_ \| __| '__| | | |
 | |____ (_) | |_| | | | | |_| |  | |_| |
  \_____\___/ \__,_|_| |_|\__|_|   \__, |
                                    __/ |
                                   |___/ 
'@ `
        -description $description `
        -options $countries `
        -default $default `
        -question "Country" `
        -previousStep
    if ($script:wizardStep -eq $script:thisStep+1) {
        $script:prevSteps.Push($script:thisStep)
    }
}

$Step.TestToolkit {

    if ($majorVersion -ge 18) {
        $licenseNote = "Full Test Toolkit requires a license in order to be used"
    }
    else {
        $licenseNote = "Test Libraries requires a license in order to be used"
    }

    $testtoolkit = Select-Value `
        -title @'
  _______       _     _______          _ _    _ _   
 |__   __|     | |   |__   __|        | | |  (_) |  
    | | ___ ___| |_     | | ___   ___ | | | ___| |_ 
    | |/ _ \ __| __|    | |/ _ \ / _ \| | |/ / | __|
    | |  __\__ \ |_     | | (_) | (_) | |   <| | |_ 
    |_|\___|___/\__|    |_|\___/ \___/|_|_|\_\_|\__|

'@ `
        -description "Do you need the test toolkit to be installed?`nThe Test Toolkit is needed in order to develop and run tests in the container.`n`nNote: $licenseNote" `
        -options ([ordered]@{"All" = "Full Test Toolkit (Test Framework, Test Libraries and Microsoft tests)"; "Libraries" = "Test Framework and Test Libraries"; "Framework" = "Test Framework"; "No" = "No Test Toolkit needed"}) `
        -question "Test Toolkit" `
        -default "No" `
        -previousStep
    if ($script:wizardStep -eq $script:thisStep+1) {
        $script:prevSteps.Push($script:thisStep)
    }
}

$Step.PerformanceToolkit {

    $performanceToolkit = "N"
    if ($majorVersion -ge 17 -and $testtoolkit -ne "No") {
        $performancetoolkit = Enter-Value `
            -title @'
  _____           __                                            _______          _ _    _ _   
 |  __ \         / _|                                          |__   __|        | | |  (_) |  
 | |__) |__ _ __| |_ ___  _ __ _ __ ___   __ _ _ __   ___ ___     | | ___   ___ | | | ___| |_ 
 |  ___/ _ \ '__|  _/ _ \| '__| '_ ` _ \ / _` | '_ \ / __/ _ \    | |/ _ \ / _ \| | |/ / | __|
 | |  |  __/ |  | || (_) | |  | | | | | | (_| | | | | (__  __/    | | (_) | (_) | |   <| | |_ 
 |_|   \___|_|  |_| \___/|_|  |_| |_| |_|\__,_|_| |_|\___\___|    |_|\___/ \___/|_|_|\_\_|\__|

'@ `
            -description "The Performance Toolkit ships with Business Central 17.0.`n`nDo you need the performance toolkit to be installed?`nThe Performance Toolkit is needed in order to develop and run performance tests in the container." `
            -options @("Y","N") `
            -question "Please enter Y if you want to install the performance toolkit" `
            -default "N" `
            -previousStep
        if ($script:wizardStep -eq $script:thisStep+1) {
            $script:prevSteps.Push($script:thisStep)
        }
    }
}

$Step.PremiumPlan {
    $assignPremiumPlan = "N"
    if ($type -eq "Sandbox") {
    
        if ($hosting -eq "local") { $back = 8 } else { $back = 7 }
        $assignPremiumPlan = Enter-Value `
            -title @'
  _____                    _                   _____  _             
 |  __ \                  (_)                 |  __ \| |            
 | |__) | __ ___ _ __ ___  _ _   _ _ __ ___   | |__) | | __ _ _ __  
 |  ___/ '__/ _ \ '_ ` _ \| | | | | '_ ` _ \  |  ___/| |/ _` | '_ \ 
 | |   | | |  __/ | | | | | | |_| | | | | | | | |    | | (_| | | | |
 |_|   |_|  \___|_| |_| |_|_|\__,_|_| |_| |_| |_|    |_|\__,_|_| |_|

'@ `
            -Description "When running sandbox, you can select to assign premium plan to the users." `
            -options @("Y","N") `
            -question "Please enter Y if you want to assign premium plan" `
            -default "N" `
            -previousStep
        if ($script:wizardStep -eq $script:thisStep+1) {
            $script:prevSteps.Push($script:thisStep)
        }
    }
}

$step.IncludeAL {
    $includeAL = "N"
    if ($hosting -eq 'local' -and $majorVersion -gt 14) {

        $includeAL = Enter-Value `
            -title @'
           _        ____                                          _____                 _                                  _   
     /\   | |      |  _ \                     /\                 |  __ \               | |                                | |  
    /  \  | |      | |_) | __ _ ___  ___     /  \   _ __  _ __   | |  | | _____   _____| | ___  _ __  _ __ ___   ___ _ __ | |_ 
   / /\ \ | |      |  _ < / _` / __|/ _ \   / /\ \ | '_ \| '_ \  | |  | |/ _ \ \ / / _ \ |/ _ \| '_ \| '_ ` _ \ / _ \ '_ \| __|
  / ____ \| |____  | |_) | (_| \__ \  __/  / ____ \| |_) | |_) | | |__| |  __/\ V /  __/ | (_) | |_) | | | | | |  __/ | | | |_ 
 /_/    \_\______| |____/ \__,_|___/\___| /_/    \_\ .__/| .__/  |_____/ \___| \_/ \___|_|\___/| .__/|_| |_| |_|\___|_| |_|\__|
                                                   | |   | |                                   | |                             
                                                   |_|   |_|                                   |_|                             
'@ `
            -Description "If you are going to perform base app development (modify and publish the base application), you will need to use an option called -includeAL.`n`nThis option is not needed if you are going to write extensions only." `
            -options @("Y","N") `
            -question "Please enter Y if you need to do base app development" `
            -default "N" `
            -previousStep
        if ($script:wizardStep -eq $script:thisStep+1) {
            $script:prevSteps.Push($script:thisStep)
        }
    }
}

$step.ExportAlSource {
    $exportAlSource = "N"
    if ($includeAL -eq "Y") {
       $exportALSource = Enter-Value `
            -title @'
  ______                       _              _        ____                                        
 |  ____|                     | |       /\   | |      |  _ \                     /\                
 | |__  __  ___ __   ___  _ __| |_     /  \  | |      | |_) | __ _ ___  ___     /  \   _ __  _ __  
 |  __| \ \/ / '_ \ / _ \| '__| __|   / /\ \ | |      |  _ < / _` / __|/ _ \   / /\ \ | '_ \| '_ \ 
 | |____ >  <| |_) | (_) | |  | |_   / ____ \| |____  | |_) | (_| \__ \  __/  / ____ \| |_) | |_) |
 |______/_/\_\ .__/ \___/|_|   \__| /_/    \_\______| |____/ \__,_|___/\___| /_/    \_\ .__/| .__/ 
             | |                                                                      | |   | |    
             |_|                                                                      |_|   |_|    
'@ `
            -Description "When specifying -includeAL, the default behavior is to export the AL source code as a project for you to modify, compile and publish.`nIf you already have a source code repository this is obviously not needed and can be avoided by specifying an option called -doNotExportObjectsToText.`n`nDo you want to export the Base App as an AL source code project?" `
            -options @("Y","N") `
            -question "Please enter Y if you want to export the base app AL source code" `
            -default "N" `
            -previousStep
        if ($script:wizardStep -eq $script:thisStep+1) {
            $script:prevSteps.Push($script:thisStep)
        }
    }
}

$step.IncludeCSIDE {
    $includeCSIDE = "N"

    if ($hosting -eq 'local' -and $majorVersion -le 14) {

        if ($majorVersion -lt 14) {
            $product = "NAV"
        }
        else {
            $product = "a version of Business Central"
        }
        $includeCSIDE = Enter-Value `
            -title @'
   _____     __     _        _____                 _                                  _   
  / ____|   / /\   | |      |  __ \               | |                                | |  
 | |       / /  \  | |      | |  | | _____   _____| | ___  _ __  _ __ ___   ___ _ __ | |_ 
 | |      / / /\ \ | |      | |  | |/ _ \ \ / / _ \ |/ _ \| '_ \| '_ ` _ \ / _ \ '_ \| __|
 | |____ / / ____ \| |____  | |__| |  __/\ V /  __/ | (_) | |_) | | | | | |  __/ | | | |_ 
  \_____/_/_/    \_\______| |_____/ \___| \_/ \___|_|\___/| .__/|_| |_| |_|\___|_| |_|\__|
                                                          | |                             
                                                          |_|                             
'@ `
            -Description "You are running $product, which includes the legacy Windows Client and legacy C/AL development.`nIf you are going to use the Windows Client or use C/AL development, you will need to use an option called -includeCSIDE." `
            -options @("Y","N") `
            -question "Please enter Y if you need CSIDE or Windows Client" `
            -default "N" `
            -previousStep
        if ($script:wizardStep -eq $script:thisStep+1) {
            $script:prevSteps.Push($script:thisStep)
        }
    }
}

$step.ExportCAlSource {
    $exportCAlSource = "N"
    if ($includeCSIDE -eq "Y") {
       $exportCAlSource = Enter-Value `
            -title @'
  ______                       _      _____     __     _        ____                                        
 |  ____|                     | |    / ____|   / /\   | |      |  _ \                     /\                
 | |__  __  ___ __   ___  _ __| |_  | |       / /  \  | |      | |_) | __ _ ___  ___     /  \   _ __  _ __  
 |  __| \ \/ / '_ \ / _ \| '__| __| | |      / / /\ \ | |      |  _ < / _` / __|/ _ \   / /\ \ | '_ \| '_ \ 
 | |____ >  <| |_) | (_) | |  | |_  | |____ / / ____ \| |____  | |_) | (_| \__ \  __/  / ____ \| |_) | |_) |
 |______/_/\_\ .__/ \___/|_|   \__|  \_____/_/_/    \_\______| |____/ \__,_|___/\___| /_/    \_\ .__/| .__/ 
             | |                                                                               | |   | |    
             |_|                                                                               |_|   |_|    
'@ `
            -Description "When specifying -includeCSIDE, the default behavior is to export the C/AL source code as text files.`nIf you already have a source code repository this is obviously not needed and can be avoided by specifying an option called -doNotExportObjectsToText.`n`nDo you want to export the C/AL base app as text files?" `
            -options @("Y","N") `
            -question "Please enter Y if you want to export the C/AL base app as text files" `
            -default "N" `
            -previousStep
        if ($script:wizardStep -eq $script:thisStep+1) {
            $script:prevSteps.Push($script:thisStep)
        }
    }
}

$Step.Vsix {

    $vsix = "N"
    if ($hosting -eq 'local' -and $majorVersion -gt 14) {
        $vsix = Enter-Value `
            -title @'
           _        _                                                ______      _                 _             
     /\   | |      | |                                              |  ____|    | |               (_)            
    /  \  | |      | |     __ _ _ __   __ _ _   _  __ _  __ _  ___  | |__  __  __ |_ ___ _ __  ___ _  ___  _ __  
   / /\ \ | |      | |    / _` | '_ \ / _` | | | |/ _` |/ _` |/ _ \ |  __| \ \/ / __/ _ \ '_ \/ __| |/ _ \| '_ \ 
  / ____ \| |____  | |____ (_| | | | | (_| | |_| | (_| | (_| |  __/ | |____ >  <| |_  __/ | | \__ \ | (_) | | | |
 /_/    \_\______| |______\__,_|_| |_|\__, |\__,_|\__,_|\__, |\___| |______/_/\_\\__\___|_| |_|___/_|\___/|_| |_|
                                       __/ |             __/ |                                                   
                                      |___/             |___/                                                    
'@ `
            -description "The AL language extension used in the container is normally the vsix file that comes with the version of Business Central selected.`n`nYou can select to use the latest shipped AL Language extension from the marketplace by specifying -vsixFile <url>." `
            -options @("Y","N") `
            -question "Please enter Y if you want to use the latest AL Language extension from the marketplace" `
            -default "N" `
            -previousStep
        if ($script:wizardStep -eq $script:thisStep+1) {
            $script:prevSteps.Push($script:thisStep)
        }
    }
}

$Step.CreateTestUsers {
    $createTestUsers = "N"
    if ($type -eq "Sandbox") {

        $createTestUsers = Enter-Value `
            -title @'
   _____                _         _______       _     _    _                   
  / ____|              | |       |__   __|     | |   | |  | |                  
 | |     _ __ ___  __ _| |_ ___     | | ___ ___| |_  | |  | |___  ___ _ __ ___ 
 | |    | '__/ _ \/ _` | __/ _ \    | |/ _ \ __| __| | |  | / __|/ _ \ '__/ __|
 | |____| | |  __/ (_| | |_  __/    | |  __\__ \ |_  | |__| \__ \  __/ |  \__ \
  \_____|_|  \___|\__,_|\__\___|    |_|\___|___/\__|  \____/|___/\___|_|  |___/

'@ `
            -Description "When running sandbox, you can select to add test users with special entitlements.`nThe users created are: ExternalAccountant, Premium, Essential, InternalAdmin, TeamMember and DelegatedAdmin.`n`nNote: This requires a license file to be specified." `
            -options @("Y","N") `
            -question "Please enter Y if you want to create test users" `
            -default "N" `
            -previousStep
        if ($script:wizardStep -eq $script:thisStep+1) {
            $script:prevSteps.Push($script:thisStep)
        }
    }
}

$Step.License {

    if ($majorVersion -ge 18) {
        $licenserequired = ($testtoolkit -eq "All" -or $createTestUsers -eq "Y" -or $exportCAlSource -eq "Y" -or $exportAlSource -eq "Y")
    }
    else {
        $licenserequired = ($testtoolkit -eq "All" -or $testtoolkit -eq "Libraries" -or $performanceToolkit -eq "Y" -or $createTestUsers -eq "Y" -or $exportCAlSource -eq "Y" -or $exportAlSource -eq "Y")
    }
    if ($licenserequired) {
        $description = "Please specify a license file url.`nDue to other selections, you need to specify a license file."
        $default = ""
    }
    else {
        $description = "Please specify a license file url.`nIf you do not specify a license file, you will use the default Cronus Demo License."
        $default = "blank"
    }
    if ($hosting -eq "Local") {
        $description += "`n`nThis can be a local file or a secure direct download url (see https://freddysblog.com/2017/02/26/create-a-secure-url-to-a-file/)"
    }
    else {
        $description += "`n`nThis needs to be a secure direct download url (see https://freddysblog.com/2017/02/26/create-a-secure-url-to-a-file/)"
    }
     
    $licenseFile = Enter-Value `
        -title @'
  _      _                         
 | |    (_)                        
 | |     _  ___ ___ _ __  ___  ___ 
 | |    | |/ __/ _ \ '_ \/ __|/ _ \
 | |____| | (__  __/ | | \__ \  __/
 |______|_|\___\___|_| |_|___/\___|

'@ `
        -description $description `
        -question "License File" `
        -default $default `
        -previousStep `
        -doNotConvertToLower
    if ($script:wizardStep -eq $script:thisStep+1) {
        $script:prevSteps.Push($script:thisStep)
    }
    
    if ($licenseFile -eq "blank") {
        $licenseFile = ""
    }
    else {
        $licenseFile = $licenseFile.Trim(@('"'))
    }
}

$Step.Database {
    if ($hosting -ne "Local") {
        $database = "default"
    }
    else {
        $database = Select-Value `
            -title @'
  _____        _        _                    
 |  __ \      | |      | |                   
 | |  | | __ _| |_ __ _| |__   __ _ ___  ___ 
 | |  | |/ _` | __/ _` | '_ \ / _` / __|/ _ \
 | |__| | (_| | |_ (_| | |_) | (_| \__ \  __/
 |_____/ \__,_|\__\__,_|_.__/ \__,_|___/\___|

'@ `
            -description "When running Business Central on Docker the default behavior is to run the Cronus Demo database inside the container, using the instance of SQLEXPRESS, which is installed there.`nYou can change the database by specifying a database backup or you can configure the container to connect to a database server (which might be on the host)." `
            -options ([ordered]@{"default" = "Use Cronus demo database on SQLEXPRESS inside the container"; "bakfile" = "Restore a database backup on SQLEXPRESS inside the container (must be the correct version)"; "connect" = "Connect to an existing database on a database server (which might be on the host)" }) `
            -question "Database" `
            -default "default" `
            -previousStep
        if ($script:wizardStep -eq $script:thisStep+1) {
            $script:prevSteps.Push($script:thisStep)
        }
    
        if ($database -eq "bakfile") {
            $bakFile = Enter-Value `
                -title "Database Backup" `
                -description "Please specify the full path and filename of the database backup (.bak file) you want to use.`n`nNote: The database backup must be from the same version as the version running in the container" `
                -question "Database Backup" `
                -previousStep
            $bakFile = $bakFile.Trim(@('"'))
        }
        elseif ($database -eq "connect") {
            $err = $false
            do {
                $params = @{}
                if ($err) {
                    $params = @{ "doNotClearHost" = $true }
                }
                $connectionString = Enter-Value @params `
                    -title "Database Connection String" `
                    -description "Please enter the connection string for your database connection.`n`nFormat: Server|Data Source=myServerName\myServerInstance;Database|Initial Catalog=myDataBase;User Id=myUsername;Password=myPassword`n`nNote: Specify localhost or . as myServerName if the database server is the host.`nNote: The connection string cannot use integrated security, it must include username and password." `
                    -question "Database Connection String" `
                    -doNotConvertToLower `
                    -previousStep
                if ($connectionString -eq "back") {
                    $err = $false
                }
                else {
                    $databaseServer = $connectionString.Split(';')   | Where-Object { $_ -like "Server=*" -or $_ -like "Data Source=*" } | % { $_.SubString($_.indexOf('=')+1) }
                    $databaseName = $connectionString.Split(';')     | Where-Object { $_ -like "Database=*" -or $_ -like "Initial Catalog=*" } | % { $_.SubString($_.indexOf('=')+1) }
                    $databaseUserName = $connectionString.Split(';') | Where-Object { $_ -like "User Id=*" } | % { $_.SubString($_.indexOf('=')+1) }
                    $databasePassword = $connectionString.Split(';')   | Where-Object { $_ -like "Password=*" } | % { $_.SubString($_.indexOf('=')+1) }
                
                    $err = !(($databaseServer) -and ($databaseName) -and ($databaseUserName) -and ($databasePassword))
                    if ($err) {
                        Write-Host -ForegroundColor Red "You need to specify a connection string, which contains all 4 elements described"
                        Write-Host
                    }
                }
            } while ($err)
            if ($connectionString -ne "back") {
                $idx = $databaseServer.IndexOf('\')
                if ($idx -ge 0) {
                    $databaseInstance = $databaseServer.Substring($idx+1)
                    $databaseServer = $databaseServer.Substring(0,$idx)
                }
                else {
                    $databaseInstance = ""
                }
                if ($databaseServer -eq "" -or $databaseServer -eq "." -or $databaseServer -eq "localhost") {
                    $databaseServer = "host.containerhelper.internal"
                }
                $databaseName = $databaseName.TrimStart('[').TrimEnd(']')
            }
        }
    }
}

$step.Multitenant {
    if ($database -ne "Connect" -and $hosting -eq 'local') {
        if ($type -eq "Sandbox") {
            $description = "You are running a sandbox container, which by default is multitenant.`nBy specifying -multitenant:`$false, you can switch the container to single tenancy."
            $default = "Y"
        }
        else {
            $description = "You are running an onprem container, which by default is singletenant.`nBy specifying -multitenant, you can switch the container to multitenant."
            $default = "N"
        }
        $multitenant = Enter-Value `
            -title @'
  __  __       _ _   _ _                         _   
 |  \/  |     | | | (_) |                       | |  
 | \  / |_   _| | |_ _| |_ ___ _ __   __ _ _ __ | |_ 
 | |\/| | | | | | __| | __/ _ \ '_ \ / _` | '_ \| __|
 | |  | | |_| | | |_| | |_  __/ | | | (_| | | | | |_ 
 |_|  |_|\__,_|_|\__|_|\__\___|_| |_|\__,_|_| |_|\__|

'@ `
            -description $description `
            -options @("Y","N") `
            -question "Please select Y if you want a multitenant container" `
            -default $default `
            -previousStep
        if ($script:wizardStep -eq $script:thisStep+1) {
            $script:prevSteps.Push($script:thisStep)
        }

        if ($multitenant -eq $default) {
            $multitenant = ""
        }
    }    
}

$Step.DNS {
    if ($hosting -eq "Local") {

        $options = [ordered]@{"default" = "Use default DNS settings (configured in Docker Daemon)"; "usegoogledns" = "Add Google public dns (8.8.8.8) as DNS to the container" }
        $hostDNS = @(Get-NetIPInterface | Where-Object { $_.ConnectionState -eq "Connected" -and $_.AddressFamily -eq "IPv4" } | ForEach-Object { Get-DnsClientServerAddress -AddressFamily IPv4 -InterfaceAlias $_.InterfaceAlias | ForEach-Object { $_.ServerAddresses } }) -join ','
        if ($hostDNS) {
            $options += @{ "usehostdns" = "Add your hosts DNS servers ($hostDNS) as DNS to the container" }
        }
        $dns = Select-Value `
            -title @'
  _____  _   _  _____ 
 |  __ \| \ | |/ ____|
 | |  | |  \| | (___  
 | |  | | . ` |\___ \ 
 | |__| | |\  |____) |
 |_____/|_| \_|_____/ 

'@ `
            -description "On some networks, default DNS resolution does not work inside a running container.`nWhen this is the case, you will see a warning during start saying:`n`nWARNING: DNS resolution not working from within the container.`n`nSome times, this can be fixed by choosing a different DNS server. Some times you have to reconfigure your network or antivirus settings to allow this." `
            -options $options `
            -question "Use DNS" `
            -default "default" `
            -previousStep
        if ($script:wizardStep -eq $script:thisStep+1) {
            $script:prevSteps.Push($script:thisStep)
        }
    }
}

$Step.SSL {
    if ($hosting -eq "Local") {

        $options = [ordered]@{"default" = "Do not use SSL (use http)"; "usessl" = "Use SSL (https) with self-signed certificate"; "usessl2" = "Use SSL (https) with self-signed certificate and install certificate on host computer" }
        $ssl = Select-Value `
            -title @'
   _____ _____ _      
  / ____/ ____| |     
 | (___| (___ | |     
  \___ \\___ \| |     
  ____) |___) | |____ 
 |_____/_____/|______|

'@ `
            -description "If your container is only used from host computer, you likely do not need to setup SSL. There are however functionality (like camera), which requires SSL and will not work if you haven't setup SSL.`nInstalling the self-signed certificate on the host might remove some of the insecure connection warnings from your browser." `
            -options $options `
            -question "Use SSL" `
            -default "default" `
            -previousStep
        if ($script:wizardStep -eq $script:thisStep+1) {
            $script:prevSteps.Push($script:thisStep)
        }
    }
}

$Step.Isolation {
    if ($hosting -eq "Local") {
        $description = "Containers can run in process isolation or hyperv isolation, see more here: https://docs.microsoft.com/en-us/virtualization/windowscontainers/manage-containers/hyperv-container`nIf not specified, the ContainerHelper will try to detect which isolation mode will work for your OS.`nIf your host OS is updated and a matching container OS is found, Process isolation will be favoured, else Hyper-V will be selected."
        $options = [ordered]@{"default" = "Allow the ContainerHelper to decide which isolation mode to use"; "process" = "Force Process isolation"; "hyperv" = "Force Hyper-V isolation" }
    
        $isolation = Select-Value `
            -title @'
  _____           _       _   _             
 |_   _|         | |     | | (_)            
   | |  ___  ___ | | __ _| |_ _  ___  _ __  
   | | / __|/ _ \| |/ _` | __| |/ _ \| '_ \ 
  _| |_\__ \ (_) | | (_| | |_| | (_) | | | |
 |_____|___/\___/|_|\__,_|\__|_|\___/|_| |_|

'@ `
            -description $description `
            -options $options `
            -question "Isolation" `
            -default "default" `
            -previousStep
        if ($script:wizardStep -eq $script:thisStep+1) {
            $script:prevSteps.Push($script:thisStep)
        }
    }
}

$Step.Memory {
    if ($hosting -eq "Local") {

        $demo = 4
        $development = 8
        if ($majorVersion -ge 16) {
            $newBaseApp = 16
        }
        elseif ($majorVersion -eq 15) {
            $newBaseApp = 12
        }
        else {
            $newBaseApp = 0
        }
    
        $description = "The amount of memory needed by the container depends on what you are going to use it for.`n`nTypical memory consumption for this version of Business Central are:`n- $($demo)G for demo/test usage of Business Central`n- $($demo)G-$($development)G for app development`n"
        if ($newBaseApp) {
            $description += "- $($newBaseApp)G for base app development`n"
        }
        $description += "`n`nWhen running Process isolation, the container will only use the actual amount of memory used by the processes running in the container from the host. Memory no longer needed by the processes in the container are given back to the host. You can set a limit to the amount of memory, the container is allowed to use. "
        $description += "(blank means no limit)"

        $description += "`n`nWhen running Hyper-V isolation, the container will pre-allocate the full amount of memory given to the container. "
        if ($hostOsVersion.Build -ge 17763) {
            $description += "Windows Server 2019 / Windows 10 1809 and later Windows versions are doing this by reserving the memory in the paging file and only using physical memory when needed. Memory no longer needed will be freed from physical memory again. "
            try {
                $CompSysResults = Get-CimInstance win32_computersystem -ComputerName $computer -Namespace 'root\cimv2'
                if ($CompSysResults.AutomaticManagedPagefile) {
                    $description += "Your paging file settings indicate that your paging file is automatically managed, you could consider changing this if you get problems with the size of the paging file. "
                }
            }
            catch {}
        }
        else {
            $description += "Windows Server 2016 and Windows 10 versions before 1809 is doing this by allocating the memory from the main memory pool. "
        }
        $description += "(blank will use ContainerHelper default which is 4G)"
    
        $memoryLimit = Enter-Value `
            -title @'
  __  __                                   _      _           _ _   
 |  \/  |                                 | |    (_)         (_) |  
 | \  / | ___ _ __ ___   ___  _ __ _   _  | |     _ _ __ ___  _| |_ 
 | |\/| |/ _ \ '_ ` _ \ / _ \| '__| | | | | |    | | '_ ` _ \| | __|
 | |  | |  __/ | | | | | (_) | |  | |_| | | |____| | | | | | | | |_ 
 |_|  |_|\___|_| |_| |_|\___/|_|   \__, | |______|_|_| |_| |_|_|\__|
                                    __/ |                           
                                   |___/                            
'@ `
            -description $description `
            -question "Specify the amount of memory the container is allowed to use?" `
            -default 'blank' `
            -previousStep
        if ($script:wizardStep -eq $script:thisStep+1) {
            $script:prevSteps.Push($script:thisStep)
        }
    
        if ($memoryLimit -eq "blank") {
            $memoryLimit = ""
        }
        else {
            $memoryLimit = "$($memoryLimit.ToLowerInvariant().Trim(' gb'))G"
        }
    }
}

$Step.SaveImage  {
    if ($hosting -eq "Local") {
        $imageName = Enter-Value `
            -title @'
   _____                   _                            
  / ____|                 (_)                           
 | (___   __ ___   _____   _ _ __ ___   __ _  __ _  ___ 
  \___ \ / _` \ \ / / _ \ | | '_ ` _ \ / _` |/ _` |/ _ \
  ____) | (_| |\ V /  __/ | | | | | | | (_| | (_| |  __/
 |_____/ \__,_| \_/ \___| |_|_| |_| |_|\__,_|\__, |\___|
                                              __/ |     
                                             |___/      
'@ `
            -description "If you are planning on running the same script multiple times, it will save time on subsequent runs to save the image`nThe ContainerHelper will automatically generate an image tag, matching the version number and country of the requested version and on every run it will check whether the image needs to be rebuild.`n`nRecommendation is to use a short name (like mybcimage) if you want to save the image." `
            -question "Image name (or blank to skip saving)" `
            -default "blank" `
            -previousStep
        if ($script:wizardStep -eq $script:thisStep+1) {
            $script:prevSteps.Push($script:thisStep)
        }
    }
}

$Step.Special {
    if ($hosting -eq "Local") {

        # TODO: Publish ports
    
        # TODO: Options like CheckHealth, Restart, Locale, TimeZoneId, Timeout
    
    }
   
}

#  ______ _             _ 
# |  ____(_)           | |
# | |__   _ _ __   __ _| |
# |  __| | | '_ \ / _` | |
# | |    | | | | | (_| | |
# |_|    |_|_| |_|\__,_|_|
#                         
$step.Final {
    $script:acceptDefaults = $false
    if ($hosting -eq "Local") {

        $parameters = @()
        $script = @()
    
        $script += "`$containerName = '$containerName'"
        if ($auth -eq "UserPassword") {
            $script += "`$credential = Get-Credential -Message 'Using UserPassword authentication. Please enter credentials for the container.'"
        }
        elseif ($auth -eq "Windows") {
            $script += "`$credential = Get-Credential -Message 'Using Windows authentication. Please enter your Windows credentials for the host computer.'"
        }
        else
        {
            if ($auth -eq "Credential") {
                $script += "`$password = '$predefinedpw'"
            }
            else {
                $script += "`$password = '$randompw'"
            }
            $script += "`$securePassword = ConvertTo-SecureString -String `$password -AsPlainText -Force"
            $script += "`$credential = New-Object pscredential 'admin', `$securePassword"
            $auth = "UserPassword"
        }
        $parameters += "-credential `$credential"
    
        $script += "`$auth = '$auth'"
        $parameters += "-auth `$auth"

        if ($nav) {
            if ($cu -eq "latest") {
                $script += "`$artifactUrl = Get-NavArtifactUrl -nav '$nav' -country '$country'"
            }
            else {
                $script += "`$artifactUrl = Get-NavArtifactUrl -nav '$nav' -cu '$cu' -country '$country'"
            }
        }
        elseif ($predef -like "Next*") {
            $script += "`$artifactUrl = Get-BcArtifactUrl -storageAccount '$storageAccount' -type '$type' -country '$country' -select '$select' -accept_insiderEula"
            $parameters += "-accept_insiderEula"
        }
        else {
            if ($version) {
                $script += "`$artifactUrl = Get-BcArtifactUrl -type '$type' -version '$version' -country '$country' -select '$select'"
            }
            else {
                $script += "`$artifactUrl = Get-BcArtifactUrl -type '$type' -country '$country' -select '$select'"
            }
        }
        $parameters += "-artifactUrl `$artifactUrl"
    
        if ($imageName -ne "blank") {
            $parameters += "-imageName '$($imageName.ToLowerInvariant())'"
        }
    
        if ($database -eq "bakfile") {
            $script += "`$bakFile = '$bakFile'"
            $parameters += "-bakFile `$bakFile"
        }
        elseif ($database -eq "connect") {
            $script += "`$databaseServer = '$databaseServer'"
            $script += "`$databaseInstance = '$databaseInstance'"
            $script += "`$databaseName = '$databaseName'"
            $script += "`$databaseUsername = '$databaseUsername'"
            $script += "`$databasePassword = '$databasePassword'"
            $script += "`$databaseSecurePassword = ConvertTo-SecureString -String `$databasePassword -AsPlainText -Force"
            $script += "`$databaseCredential = New-Object pscredential `$databaseUsername, `$databaseSecurePassword"
            $parameters += "-databaseServer `$databaseServer -databaseInstance `$databaseInstance -databaseName `$databaseName"
            $parameters += "-databaseCredential `$databaseCredential"
        }

        if ($multitenant -eq "Y") {
            $parameters += "-multitenant"
        }
        elseif ($multitenant -eq "N") {
            $parameters += "-multitenant:`$false"
        }
    
        if ($testtoolkit -ne "No") {
            $parameters += "-includeTestToolkit"
            if ($testtoolkit -eq "Framework") {
                $parameters += "-includeTestFrameworkOnly"
            }
            elseif ($testtoolkit -eq "Libraries") {
                $parameters += "-includeTestLibrariesOnly"
            }
            if ($performanceToolkit -eq "Y") {
                $parameters += "-includePerformanceToolkit"
            }
        }
    
        if ($assignPremiumPlan -eq "Y") {
            $parameters += "-assignPremiumPlan"
        }
    
        if ($licenseFile) {
            $script += "`$licenseFile = '$licenseFile'"
            $parameters += "-licenseFile `$licenseFile"
        }
    
        if ($dns -eq "usegoogledns") {
            $parameters += "-dns '8.8.8.8'"
        }
        elseif ($dns -eq "usehostdns") {
            $parameters += "-dns 'hostDNS'"
        }
    
        if ($ssl -eq "usessl") {
            $parameters += "-usessl"
        }
        elseif ($ssl -eq "usessl2") {
            $parameters += "-usessl -installCertificateOnHost"
        }

        if ($isolation -ne "default") {
            $parameters += "-isolation '$isolation'"
        }
        if ($memoryLimit) {
            $parameters += "-memoryLimit $memoryLimit"
        }
        if ($includeAL -eq "Y") {
            if ($exportAlSource -eq "Y") {
                $parameters += "-includeAL"
            }
            else {
                $parameters += "-includeAL -doNotExportObjectsToText"
            }
        }
        if ($includeCSIDE -eq "Y") {
            if ($exportCAlSource -eq "Y") {
                $parameters += "-includeCSIDE"
            }
            else {
                $parameters += "-includeCSIDE -doNotExportObjectsToText"
            }
        }
        if ($vsix -eq "Y") {
            $parameters += "-vsixFile (Get-LatestAlLanguageExtensionUrl)"
        }
    
        $script += "New-BcContainer ``"
        $script += "    -accept_eula ``"
        $script += "    -containerName `$containerName ``"
        $parameters | ForEach-Object { $script += "    $_ ``" }
        $script += "    -updateHosts"
    
        if ($createTestUsers -eq "Y") {
            if ($auth -eq "Windows") {
                $script += "Setup-BcContainerTestUsers -containerName `$containerName -Password `$credential.Password"
            }
            else {
                $script += "Setup-BcContainerTestUsers -containerName `$containerName -Password `$credential.Password -credential `$credential"
            }
        }
    
        $filename = Enter-Value `
            -title @'
  _____                       _____ _          _ _     _____           _       _   
 |  __ \                     / ____| |        | | |   / ____|         (_)     | |  
 | |__) |____      _____ _ __ (___ | |__   ___| | |  | (___   ___ _ __ _ _ __ | |_ 
 |  ___/ _ \ \ /\ / / _ \ '__\___ \| '_ \ / _ \ | |   \___ \ / __| '__| | '_ \| __|
 | |  | (_) \ V  V /  __/ |  ____) | | | |  __/ | |   ____) | (__| |  | | |_) | |_ 
 |_|   \___/ \_/\_/ \___|_| |_____/|_| |_|\___|_|_|  |_____/ \___|_|  |_| .__/ \__|
                                                                        | |        
                                                                        |_|        
'@ `
            -description "The below script will create a container with the requested settings:`n`n$([string]::Join("`n", $script))" `
            -question "Enter filename to save and edit script (or blank to skip saving)" `
            -default "blank"
    
        if ($filename -ne "blank") {
            $filename = $filename.Trim('"')
            if ($filename -notlike "*.ps1") {
                $filename += ".ps1"
            }
            if ($filename.indexOf('\') -eq -1) {
                $filename = Join-Path ([environment]::getfolderpath(“mydocuments”)) $filename
            }
            $script | Out-File $filename
            start -Verb Edit $filename
        }
        else {
            $executeScript = Enter-Value `
                -options @("Y","N") `
                -question "Execute Script" `
                -doNotClearHost
        
            if ($executeScript -eq "Y") {
                Invoke-Expression -Command ([string]::Join("`n", $script))
            }
        }
    }
    else {

        $emailforletsencrypt = Enter-Value `
            -title @'
                               __      ____  __     _____          _   _  __ _           _       
     /\                        \ \    / /  \/  |   / ____|        | | (_)/ _(_)         | |      
    /  \   _____   _ _ __ ___   \ \  / /| \  / |  | |     ___ _ __| |_ _| |_ _  ___ __ _| |_ ___ 
   / /\ \ |_  / | | | '__/ _ \   \ \/ / | |\/| |  | |    / _ \ '__| __| |  _| |/ __/ _` | __/ _ \
  / ____ \ / /| |_| | | |  __/    \  /  | |  | |  | |____  __/ |  | |_| | | | | (__ (_| | |_  __/
 /_/    \_\___|\__,_|_|  \___|     \/   |_|  |_|   \_____\___|_|   \__|_|_| |_|\___\__,_|\__\___|

'@ `
            -description "Your Azure VM can be secured by a Self-Signed Certificate, meaning that you need to install this certificate on any machine connecting to the VM.`nYou can also select to use LetsEncrypt by specifying an email address of the person accepting subscriber agreement for LetsEncrypt (https://letsencrypt.org/repository/).`n`nNote: The LetsEncrypt certificate needs to be renewed after 90 days." `
            -question "Contact EMail for LetsEncrypt (blank to use Self Signed)" `
            -default "blank"
    
        $artifactUrl = [Uri]::EscapeDataString("bcartifacts/$type/$version/$country/$select".ToLowerInvariant())
    
        $url = "http://aka.ms/getbc?accepteula=Yes&artifacturl=$artifactUrl"
        if ($licenseFile) {
            $url += "&licenseFileUri=$([Uri]::EscapeDataString($licenseFile))"
        }
        if ($testToolkit -ne "No") {
            $url += "&TestToolkit=$testToolkit"
        }
        if ($assignPremiumPlan -eq "Y") {
            $url += "&AssignPremiumPlan=Yes"
        }
        if ($createTestUsers -eq "Y") {
            $url += "&CreateTestUsers=Yes"
        }
        if ($emailforletsencrypt -ne "blank") {
            $url += "&contactemailforletsencrypt=$([Uri]::EscapeDataString($emailforletsencrypt))"
        }
    
        $launchUrl = Enter-Value `
            -title @'
                               __      ____  __    _    _ _____  _      
     /\                        \ \    / /  \/  |  | |  | |  __ \| |     
    /  \   _____   _ _ __ ___   \ \  / /| \  / |  | |  | | |__) | |     
   / /\ \ |_  / | | | '__/ _ \   \ \/ / | |\/| |  | |  | |  _  /| |     
  / ____ \ / /| |_| | | |  __/    \  /  | |  | |  | |__| | | \ \| |____ 
 /_/    \_\___|\__,_|_|  \___|     \/   |_|  |_|   \____/|_|  \_\______|
                                                                        
'@ `
            -description "The URL below will launch the Azure Portal with an ARM template, which will create your VM:`n`n$url" `
            -options @("Y","N") `
            -question "Launch Url"
    
        if ($launchUrl -eq "Y") {
            Start-Process $Url
        }
    }
}
}
}
# SIG # Begin signature block
# MIInSQYJKoZIhvcNAQcCoIInOjCCJzYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCC3tEBTIHXZ1d8j
# xuUVJrF+oWJEvdWRZTVCM6exV6DB46CCDLowggX1MIID3aADAgECAhMzAAACHU0Z
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
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIE927btd
# o3jdZf4wfirKrojUfw1/uIJ1hI7PPwqGHz7eMEIGCisGAQQBgjcCAQwxNDAyoBSA
# EgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20w
# DQYJKoZIhvcNAQEBBQAEggEAoEgzP67Esty33InBMFhPB+mv8mJeiOZByaV4H5F8
# yXgAFkuo1twB3DqjXbSD7gL8uucDx72wnzH1mAndR5k6U8xwHNIi1o+HqOLXE/Bb
# AgXE1tnwmo+7V4mJIM7zJmUC50VTIdeRDaWtnTAaRSnH+CW8zTu8G+aHgxZMSfUb
# 0ePIPo5yTDLwzSxPdRotlY+5F9CrV3r/XWMhdG8a/vkstpQqcJQeds6VJM8QaRMO
# TRuhrph7OcAA+DtQY4iyrnsT7Hgbdh0na9DoUzjf3h/tigQP4a64E0ufw4tYtWMX
# 5z6qM/F7k3mGoZ5nHZsnE1Reic2UPt5EDe47SUbKRH7KeqGCF5cwgheTBgorBgEE
# AYI3AwMBMYIXgzCCF38GCSqGSIb3DQEHAqCCF3AwghdsAgEDMQ8wDQYJYIZIAWUD
# BAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGEWQoD
# ATAxMA0GCWCGSAFlAwQCAQUABCD/xEFR36D29G7prywRTdOrKTOx+fdXixBCeAKS
# z4KMcQIGaoVY7GC0GBMyMDI2MDgyNzA2MjkzNS4yNjlaMASAAgH0oIHRpIHOMIHL
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxN
# aWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRT
# UyBFU046OTYwMC0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFNlcnZpY2WgghHtMIIHIDCCBQigAwIBAgITMwAAAiY1tD5nQ5P2HwABAAAC
# JjANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAe
# Fw0yNjAyMTkxOTQwMDJaFw0yNzA1MTcxOTQwMDJaMIHLMQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmlj
# YSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046OTYwMC0wNUUw
# LUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIi
# MA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC//w+ZZIL5RFFpVI8D3ZyuNu8I
# zcAEOD30OLYjh337rXjcrIlOSzpJc4ZeUxEyli6x6F6zm4NR8dbPb9diDp/hOUzH
# WGxiA1Z3RXKBb/4F/ojyvN43SEGWqSfVc3I3BlsYT35ecVAJ9kVf90YOv29tFjJB
# BZkYvrT/DwwyRLscOyP4p+9/lyJjD+ULs3YXBhVrfZ+MbQB+BYKLqRvBKbj/wR9a
# kNrMxQINoGaD5jZO/N/nSsmG2P1zv/cv4gSoMBnWeQIBkjd2I5w1DeXupp2vSiNm
# R5sA2ZkBK3yiQWaJvRxODlkfiyHk9Mkk/TrYTjmjPCbhe+uqhHNRy8UlbOvWsCq0
# tRtUykHv39DgqAfJNrE8OSt835rBzDprrcAhwmgfhoVi4AKeqwikY0nUa48K0Qy8
# 0XT4fiEA3ExEZNaRFo9Nq/GwbfgqKqGmc9xhKuRFcjtua4KHZvnAvpWgEFSOCkov
# Xs/BcLnkEHM9xZ8iUag5CyhNqXYYE/z0pcXdYaNIkQ68EWmuvLm7g9oofV2vOm5G
# VNoghnkWG6nGPo/JwEgmA9oSS0EfvFRMWPA/gpSvF3shArKHnaEpVSSi3DNbyiuY
# iEs9Ko0IkZc8xKFeQRaqGRxrB+2r/7B3X81Tps99KhFwg+wD87od22F2MUg1x7tw
# t3gaVnFk0IZIwUPCGwIDAQABo4IBSTCCAUUwHQYDVR0OBBYEFF3hn9fYJN2Y/Z9L
# VbBPIxAzXHsQMB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1Ud
# HwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3Js
# L01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggr
# BgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNv
# bS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIw
# MTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgw
# DgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUAA4ICAQA2Ux0tr9sYCjsq0FRy
# iVpx15OurNXv6Qk7iX+ArVPlz3w4tqjcTNm1dt3tTua2wJMpJhPH8n7UXhmT98d5
# Du44Ll4adnse4SQfVg3QL6aRkXHnJUn8y9iftB/Py22n9xnwPFfj3QlDOSgLuHle
# u97U0iH2ZaluYabWXJihdiYpK8cPHFlqZOAiot0+GD8dP+RMuvpxt/F2LmYelpoZ
# wriiFOUmlxEUV7xJHyZZlDquskeyuq01DTv91N4qM8cfPPhl/2pc4HeMf/nd2Hou
# ifJbDQFNd4WPhLzn0Sy3u1Zh3+S3tjQdqN+dyw60RaV+RXCoOLgFZ3MAg/GoDl+f
# vb5hy/1a71ctX8wEad1Pf6def2pqfl3wFc++hkF8DXXTZofJN4YVaN3InwbAGQDD
# kNK4lqecCixxmSKwidPynGeE5OtvNoK1pkLsm/i8F1RjGczZ/kSF2VDkqG866iQ+
# jVbGOQ6Du3eyyFcFKZoDJ4B5mEAS9aT2SKqllLeybOboH6r67siR5B/2Hnu7+KYu
# YZy0BEadtA6ngG4cnSR9JsrkhhsKmb11ujqwgJyNx92MsoGGwNgN1aI0QID8CsjC
# FwpfmMzlA44xHKYv3hmjxeqBS4uU5rQeiAnVgpJeaVGKm/lzPDtnppGV+7XhRp5b
# 1ZxT/Z7Xxc+I7H7/jCtQDZoaZTCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkA
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
# T3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjk2MDAtMDVFMC1E
# OTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEw
# BwYFKw4DAhoDFQCi/fMxFtkqr7XMXdsRyWU0lSKHZ6CBgzCBgKR+MHwxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29m
# dCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBCwUAAgUA7jm5ajAiGA8y
# MDI2MDgyNjE5MTM0NloYDzIwMjYwODI3MTkxMzQ2WjB3MD0GCisGAQQBhFkKBAEx
# LzAtMAoCBQDuOblqAgEAMAoCAQACAgVvAgH/MAcCAQACAhPyMAoCBQDuOwrqAgEA
# MDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAI
# AgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBAAX0FnCR88RCyazLOdZ+TTKQQmmE
# PwfeE/riH4Ie6ckR548QfN1iEqZ8M2baOA/tJcN5nFJnQA5QuVuKAFcdqDwB+E5g
# X3zQzV5EJCB2iKnpKTzhmL4eF8+wkUcWaKPnzfxiAYHJYiF+eRfj8wnTfsRwBG7h
# zxTXe/Wt5aijSji7H48XzIwvgrhVNq6sur2Q2iZwpqfjZWwbexV92jq+zEwXOXIY
# d5wIYDTcp0VwKyabxli8EjbtpgLxwONipKYJneG8ad+hgxdIp3GXKBQEE4PR9Aos
# Rb3d3fVWSRnv7sSAbTj2d04NG5SP+w5PwQXbUhbg1bPVDvIwYhZ5ExKKk+gxggQN
# MIIECQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQ
# MA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
# MSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAiY1
# tD5nQ5P2HwABAAACJjANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0G
# CyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCDmb2nm3OZJYZ3c78FRHB42SjKd
# X8zS1I68J5ecyOmAtTCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EIMwyXGFn
# TNsZRBrs6GN/BbV0okaNP3VBYqLFjUsFnbgqMIGYMIGApH4wfDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgUENBIDIwMTACEzMAAAImNbQ+Z0OT9h8AAQAAAiYwIgQg4RWuKsf4
# M+wbtxXql7QbH++jD59EOD9zWtx97APKemcwDQYJKoZIhvcNAQELBQAEggIAePlo
# zZYuYlv3cSGKRtzcQbhP2fp3Dp1AX5BvtEcdpZm3xYfWxw6v2N41Y0Y1JVanKF1W
# Ft3xuKqmrmpo3vcYImvCTGVPNQ7gFBm9WQaDto3RVUvbUtq146AoiUV4UFkJ8NZ2
# QyLqcQQeQV5SyrJrZHVgstntJgLo6Q0MQhozdeLx6LwsaFtuSkdKs7EhJpU4OkAP
# eAdNyG9YQJkxlNJZ/zHsM/dRjJBTZqegFR30nUSNRZSdyhhxfGWEwoAihHUmzBMg
# mU1f15fqNWjaWBT501rvIVZWX4a8DvkEUP9dW+p4l7d0eriBQ+ZYrsjBXRpEkevY
# DIIc9poOVVY5vtmadcPa6MN2FaT+KaowSgewRjLL3c18zU4lYFpD6TsSBctDfUJT
# Ss34TeXGuL8vKynlwQl4LJBZ5jCyU4xX+sB98ey8UBYrq+t/ISpGfqH9GC+izMaC
# tB3upo9DCiUdI/oJ8KOyuCbrkmSCZ3gv8FkYXhgeWzolxhIJHkue5OOYbmbs1Vpj
# V1kWar7XOnWQehuppFj2S53S/cdV1yhvHRyZq5iLi4ZDCvAH+9jiH7+Eu33JYg6R
# CPG85uWu6C8shBPY7iWqknvykhE0oHXwmt2UnxJZfBiYLBJ5nAGfoUrFxYRrWBWK
# FWRt70mppHS+TmrQQEflZGycpcafGQiGsFMUWtI=
# SIG # End signature block
