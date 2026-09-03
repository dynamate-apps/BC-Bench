Param(
    [switch] $skipContainerHelperCheck = $true
)

# Single/Multi project

# Upload apps
# Starting version number






$ErrorActionPreference = "stop"

if ($true) {
function TestUrl {
    Param(
        [string] $url
    )

    if ($url -notlike "https://*") {
        return $false
    }
    else {
        try {
            (New-Object System.Net.WebClient).DownloadString($url) | Out-Null
            return $true
        }
        catch {
            return $false
        }
    }
}

function TestOrgName {
    Param(
        [string] $name
    )

    if ($name) {
        $true
    }
    else {
        Write-Host -ForegroundColor Red "Illegal organization name"
        $false
    }
}

function TestRepoName {
    Param(
        [string] $org,
        [string] $name
    )

    if ($name) {
        $true
    }
    else {
        Write-Host -ForegroundColor Red "Illegal repository name"
        $false
    }
}

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
    $cnt = 0
    if ($description) {
        $segments = $description.Split('|')
        $yellow = $false
        $segments | ForEach-Object {
            if ($yellow) {
                Write-Host -ForegroundColor Yellow -NoNewline "$cnt == $_"
                $cnt++
            }
            else {
                Write-Host -NoNewline $_
            }
            $yellow = !$yellow
        }
        Write-Host
        Write-Host
    }
    $offset = 0
    $defaultAnswer = -1
    $keys = @()
    $values = @()

    $options.GetEnumerator() | ForEach-Object {
        Write-Host -ForegroundColor Yellow "$([char]($offset+97)) " -NoNewline
        $keys += @($_.Key)
        $values += @($_.Value)
        if ($_.Key -eq $default) {
            $yellow = $true
            $_.Value.split("`n") | ForEach-Object {
                if ($yellow) {
                    Write-Host -ForegroundColor Yellow $_
                    $yellow = $false
                }
                else {
                    Write-Host $_
                }
            }
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
            if ($selection.Length -eq 1 -and $selection -ge "0" -and $selection -lt "$([Math]::Floor(($segments.Count-1)/2))") {
                $index = ([int]$selection)*2 + 1
                Write-Host -ForegroundColor Yellow "Launching $($segments[$index])"
                Start-Process $segments[$index]
                $answer = $null
            }
            elseif (($selection.Length -ne 1) -or (([int][char]($selection)) -lt 97 -or ([int][char]($selection)) -ge (97+$offset))) {
                Write-Host -ForegroundColor Red "Illegal answer. " -NoNewline
            }
            else {
                $answer = ([int][char]($selection))-97
            }
        }
        if ($answer -eq $null) {
            $answer = -1
        }
        elseif ($answer -eq -1) {
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
        Write-Host -ForegroundColor Green "`n$($values[$answer].Split("`n")[0]) selected"
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
        [switch] $previousStep,
        [scriptblock] $validate = { Param($answer) $answer }
    )

    if (!$doNotClearHost) {
        Clear-Host
    }

    if ($title) {
        Write-Host -ForegroundColor Yellow $title
        Write-Host
    }
    $cnt = 0
    if ($description) {
        $segments = $description.Split('|')
        $yellow = $false
        $segments | ForEach-Object {
            if ($yellow) {
                Write-Host -ForegroundColor Yellow -NoNewline "$cnt == $_"
                $cnt++
            }
            else {
                Write-Host -NoNewline $_
            }
            $yellow = !$yellow
        }
        Write-Host
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
            elseif ($selection.Length -eq 1 -and $selection -ge "0" -and $selection -lt "$([Math]::Floor(($segments.Count-1)/2))") {
                $index = ([int]$selection)*2 + 1
                Write-Host -ForegroundColor Yellow "Launching $($segments[$index])"
                Start-Process $segments[$index]
                $answer = $null
            }
            else {
                $answer = Invoke-Command $validate -argumentList $selection
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

}

. (Join-Path $PSScriptRoot "HelperFunctions.ps1")

# Ensure that PowerShell ISE starts conhost
ping | Out-Null

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
$ErrorActionPreference = "STOP"
Set-StrictMode -Version 2.0

$script:wizardStep = 0
$script:acceptDefaults = $false

$Step = @{
    "Intro"                      = 0
    "Org"                        = 1
    "Repo"                       = 2
    "AppType"                    = 3
    "AccessControl"              = 4
    "Country"                    = 5
    "AdditionalCountries"        = 6
    "AdditionalCountriesAlways"  = 7
    "VersioningStrategy"         = 10
    "VersioningMethod"           = 11
    "DependencyStrategy"         = 12
    "GenerateDependencyArtifact" = 13
    "ScheduledWorkflows"         = 14
    "GitHubRunner"               = 20
    "Secrets"                    = 30
    "AzureKeyVault"              = 31
    "DefineSecrets"              = 32
    "Doit"                       = 999
}

$orgSecrets = @()
$secrets = [ordered]@{
    "ghTokenWorkflow" = ""
    "AdminCenterApiCredentials" = ""
    "LicenseFileUrl" = ""
    "CodeSignCertificateUrl" = ""
    "CodeSignCertificatePassword" = ""
    "AZURE_CREDENTIALS" = ""
}

$settings = [ordered]@{
    "Org"                        = "BusinessCentralApps"
    "Repo"                       = "MyApp"
    "AppType"                    = "PTE"
    "AccessControl"              = "public"
    "Country"                    = "us"
    "AdditionalCountries"        = "none"
    "AdditionalCountriesAlways"  = "no"
    "VersioningStrategy"         = "same"
    "VersioningMethod"           = "0"
    "DependencyStrategy"         = "UpdateDependencies"
    "GenerateDependencyArtifact" = "Yes"
    "GitHubRunner"               = "windows-latest"
    "CurrentSchedule"            = "0 22 * * 0,1,2,3,4,5"
    "NextMajorSchedule"          = ""
    "NextMinorSchedule"          = ""
}

$script:prevSteps = New-Object System.Collections.Stack
$script:prevSteps.Push(1)

while ($script:wizardStep -le 1000) {

$script:thisStep = $script:wizardStep
$script:wizardStep++

switch ($script:thisStep) {

$Step.Intro {
    Write-Host -ForegroundColor Yellow @'
           _           _____          __              _____ _ _   _    _       _     
     /\   | |         / ____|        / _|            / ____(_) | | |  | |     | |    
    /  \  | |  ______| |  __  ___   | |_ ___  _ __  | |  __ _| |_| |__| |_   _| |__  
   / /\ \ | | |______| | |_ |/ _ \  |  _/ _ \| '__| | | |_ | | __|  __  | | | | '_ \ 
  / ____ \| |____    | |__| | (_) | | || (_) | |    | |__| | | |_| |  | | |_| | |_) |
 /_/    \_\______|    \_____|\___/  |_| \___/|_|     \_____|_|\__|_|  |_|\__,_|_.__/ 

'@

    try {
        invoke-git --version
    }
    catch {
        Write-Host -ForegroundColor Red "You need to install Git (https://git-scm.com/) in order to use the AL-Go for GitHub setup function."
    }
    
    try {
        invoke-gh --version | Where-Object { $_ -like 'gh*' }
        invoke-gh auth status
    }
    catch {
        Write-Host -ForegroundColor Red "You need to install GitHub CLI (https://cli.github.com/) in order to use the AL-Go for GitHub setup function."
    }
    
    try {
        $azModule = get-installedmodule -name az
        Write-Host "Az PS Module Version $($azModule.Version)"
        $azContext = Get-AzContext
        if (-not ($azContext)) {
            Write-Host -ForegroundColor Yellow "No Az Context selected, you can use Login-AzAccount, Connect-AzAccount and Set-AzContext to select account, tenant and subscription"
        }
        else {
            Write-Host "Az Context: $($azContext.Name)"
        }
    }
    catch {
        Write-Host -ForegroundColor Red "You need to install the Az PowerShell module Azure CLI (https://www.powershellgallery.com/packages/Az) in order to use the AL-Go for GitHub setup function."
    }

    $doit = Enter-Value `
            -title " " -doNotClearHost `
            -description "AL-Go for GitHub is plug-and-play DevOps. Easy to setup, easy to use.`n`nHaving said that, there are many ways to configure AL-Go for GitHub, this wizard takes you through many of the options and help you define the right settings.`n`nFirst thing you need to do, is to determine the structure of your repositories.`nThe recommendation is that apps, which are shipped together share the same repository with their test apps.`nIf you have ""common"" apps, which are used by multiple projects, we recommend that these are placed in a ""common"" repository.`nYou should start by setting up the repository for your ""common"" apps and after that, setup the repository with a dependency to the first repository." `
            -options @("Y","N") `
            -question "Please select Y to start the AL-Go for GitHub setup wizard"
    
    if ($doit -ne "Y") {
        Write-Host -ForegroundColor Red "Aborting..."
        return
    }
    if ($script:wizardStep -eq $script:thisStep+1) {
        $script:prevSteps.Push($script:thisStep)
    }
}

$Step.Org {
    
    $org = Enter-Value `
        -title @'
   ____                        _          _   _             
  / __ \                      (_)        | | (_)            
 | |  | |_ __ __ _  __ _ _ __  _ ______ _| |_ _  ___  _ __  
 | |  | | '__/ _` |/ _` | '_ \| |_  / _` | __| |/ _ \| '_ \ 
 | |__| | | | (_| | (_| | | | | |/ / (_| | |_| | (_) | | | |
  \____/|_|  \__, |\__,_|_| |_|_/___\__,_|\__|_|\___/|_| |_|
              __/ |                                         
             |___/                                          
'@ `
        -Description "Every GitHub user has a personal account and can be a member of any number of organizations. You can place your repository in a personal account or an organizational account. Microsoft recommends placing your repository in an organizational account in order to be able to share GitHub agents, secrets and other things between the repositories`n`nVisit |https://github.com/settings/organizations| to see which organizations you are part of`n`nUnder which organization do you want to place your repositories?" `
        -question "Please specify the name of your GitHub organization" `
        -previousStep `
        -default $settings.Org `
        -validate { Param($answer) 
            if (-not (TestOrgName -name $answer)) {
                $answer = $null
            }
            $answer
        }

    if ($script:wizardStep -eq $script:thisStep+1) {
        $script:prevSteps.Push($script:thisStep)
        $settings.Org = $org
    }
}

$Step.Repo {
    
    $repo = Enter-Value `
        -title @'
  _____                      _ _                   
 |  __ \                    (_) |                  
 | |__) |___ _ __   ___  ___ _| |_ ___  _ __ _   _ 
 |  _  // _ \ '_ \ / _ \/ __| | __/ _ \| '__| | | |
 | | \ \  __/ |_) | (_) \__ \ | || (_) | |  | |_| |
 |_|  \_\___| .__/ \___/|___/_|\__\___/|_|   \__, |
            | |                               __/ |
            |_|                              |___/ 
'@ `
        -Description "The repository name needs to be unique under the $($settings.Org) organization.`n`nVisit |https://github.com/orgs/$($settings.Org)/repositories| to see which repositories already exists.`n`nWhat is the name of the repository you want to create?" `
        -question "Please enter the name of your new repository" `
        -previousStep `
        -default $settings.Repo `
        -validate { Param($answer) 
            if (-not (TestRepoName -org $settings.Org -name $answer)) {
                $answer = $null
            }
            $answer
        }

    if ($script:wizardStep -eq $script:thisStep+1) {
        $script:prevSteps.Push($script:thisStep)
        $settings.Repo = $repo
    }
}

$Step.AppType {

    $appType = Select-Value `
        -title @'
                       _ _           _   _               _                    
     /\               | (_)         | | (_)             | |                   
    /  \   _ __  _ __ | |_  ___ __ _| |_ _  ___  _ __   | |_ _   _ _ __   ___ 
   / /\ \ | '_ \| '_ \| | |/ __/ _` | __| |/ _ \| '_ \  | __| | | | '_ \ / _ \
  / ____ \| |_) | |_) | | | (_| (_| | |_| | (_) | | | | | |_| |_| | |_) |  __/
 /_/    \_\ .__/| .__/|_|_|\___\__,_|\__|_|\___/|_| |_|  \__|\__, | .__/ \___|
          | |   | |                                           __/ | |         
          |_|   |_|                                          |___/|_|         
'@ `
        -Description "Please specify the type of application(s) which will reside in the $($settings.Org)/$($settings.repo) repository?" `
        -options ([ordered]@{"PTE" = "Per Tenant Extension"; "AppSource" = "AppSource App"}) `
        -question "Application type" `
        -previousStep `
        -default $settings.AppType
    if ($script:wizardStep -eq $script:thisStep+1) {
        $script:prevSteps.Push($script:thisStep)
        $settings.AppType = $appType
    }
}

$Step.AccessControl {

    $accessControl = Select-Value `
        -title @'
                                   _____            _             _ 
     /\                           / ____|          | |           | |
    /  \   ___ ___ ___  ___ ___  | |     ___  _ __ | |_ _ __ ___ | |
   / /\ \ / __/ __/ _ \/ __/ __| | |    / _ \| '_ \| __| '__/ _ \| |
  / ____ \ (_| (_|  __/\__ \__ \ | |___| (_) | | | | |_| | | (_) | |
 /_/    \_\___\___\___||___/___/  \_____\___/|_| |_|\__|_|  \___/|_|
                                                                    
'@ `
        -Description "Your repository can be public (Anyone on the internet can see this repository, you choose who can commit) or private (You choose who can see and commit to this repository).`nPublic repositories have unlimited free GitHub runners, access to GitHub environments feature, organizational secrets and more.`nFor private repositories you might need to purchase a higher plan to get access to these GitHub features.`n`nVisit |https://github.com/settings/billing/plans| to see personal account plans.`nVisit |https://github.com/organizations/$($settings.Org)/billing/plans| to see your organization plan.`n`nNote that Secrets in the organization or repository are (obviously) not accessible to the public.`n`nWhat access control should be used for the $($settings.Org)/$($settings.Repo) repository?" `
        -options ([ordered]@{"Public" = "Public"; "Private" = "Private"}) `
        -question "Application type" `
        -previousStep `
        -default $settings.AccessControl
    if ($script:wizardStep -eq $script:thisStep+1) {
        $script:prevSteps.Push($script:thisStep)
        $settings.AccessControl = $accessControl
    }
}

$Step.country {
    
    # TODO: Test Country
    
    $country = Enter-Value `
        -title @'
   _____                  _              
  / ____|                | |             
 | |     ___  _   _ _ __ | |_ _ __ _   _ 
 | |    / _ \| | | | '_ \| __| '__| | | |
 | |___| (_) | |_| | | | | |_| |  | |_| |
  \_____\___/ \__,_|_| |_|\__|_|   \__, |
                                    __/ |
                                   |___/ 
'@ `
        -Description "Please specify the country version of Business Central which should be used for your development process.`nThis country version will also be used as the main country when running the CI/CD workflow.`nYou can add additional countries later on which your app is tested." `
        -question "Specify country version of Business Central" `
        -previousStep `
        -default $settings.Country
    
    if ($script:wizardStep -eq $script:thisStep+1) {
        $script:prevSteps.Push($script:thisStep)
        $settings.Country = $country
    }
}

$Step.additionalCountries {

    # TODO: Test AdditionalCountries

    $additionalCountries = Enter-Value `
        -title @'
              _     _ _ _   _                   _                         _        _           
     /\      | |   | (_) | (_)                 | |                       | |      (_)          
    /  \   __| | __| |_| |_ _  ___  _ __   __ _| |   ___ ___  _   _ _ __ | |_ _ __ _  ___  ___ 
   / /\ \ / _` |/ _` | | __| |/ _ \| '_ \ / _` | |  / __/ _ \| | | | '_ \| __| '__| |/ _ \/ __|
  / ____ \ (_| | (_| | | |_| | (_) | | | | (_| | | | (_| (_) | |_| | | | | |_| |  | |  __/\__ \
 /_/    \_\__,_|\__,_|_|\__|_|\___/|_| |_|\__,_|_|  \___\___/ \__,_|_| |_|\__|_|  |_|\___||___/
                                                                                               
'@ `
        -Description "Please specify a comma separated list of additional countries supported by your app." `
        -question "Additional Countries (ex. dk,it,de - or none for no additional countries)" `
        -previousStep `
        -default $settings.additionalCountries
    
    if ($script:wizardStep -eq $script:thisStep+1) {
        $script:prevSteps.Push($script:thisStep)
        $settings.additionalCountries = $additionalCountries
        if ($additionalCountries -eq "none") {
            $script:wizardStep = $step.AdditionalCountriesAlways+1
        }
    }
}

$Step.additionalCountriesAlways {

    # TODO: Test AdditionalCountries

    $additionalCountriesAlways = Select-Value `
        -title @'
              _     _ _ _   _                   _    _____                  _        _                      _                        ___  
     /\      | |   | (_) | (_)                 | |  / ____|                | |      (_)               /\   | |                      |__ \ 
    /  \   __| | __| |_| |_ _  ___  _ __   __ _| | | |     ___  _   _ _ __ | |_ _ __ _  ___  ___     /  \  | |_      ____ _ _   _ ___  ) |
   / /\ \ / _` |/ _` | | __| |/ _ \| '_ \ / _` | | | |    / _ \| | | | '_ \| __| '__| |/ _ \/ __|   / /\ \ | \ \ /\ / / _` | | | / __|/ / 
  / ____ \ (_| | (_| | | |_| | (_) | | | | (_| | | | |___| (_) | |_| | | | | |_| |  | |  __/\__ \  / ____ \| |\ V  V / (_| | |_| \__ \_|  
 /_/    \_\__,_|\__,_|_|\__|_|\___/|_| |_|\__,_|_|  \_____\___/ \__,_|_| |_|\__|_|  |_|\___||___/ /_/    \_\_| \_/\_/ \__,_|\__, |___(_)  
                                                                                                                             __/ |        
                                                                                                                            |___/         
'@ `
        -Description "Typically, you will run the tests against additional countries when testing Current build, Next Minor or Next Major, but not in your CI/CD workflow, as this will delay checkin." `
        -question "Do you want to test additional countries during CI/CD as well" `
        -options ([ordered]@{"yes" = "Yes, always test against all countries"; "no" = "No, only test against additional countries for Current, Next Minor and next Major workflows" }) `
        -previousStep `
        -default $settings.additionalCountriesAlways
    
    if ($script:wizardStep -eq $script:thisStep+1) {
        $script:prevSteps.Push($script:thisStep)
        $settings.additionalCountriesAlways = $additionalCountriesAlways
    }
}

$Step.VersioningStrategy {

    $versioningStrategy = Select-Value `
        -title @'
 __      __           _             _                _____ _             _                   
 \ \    / /          (_)           (_)              / ____| |           | |                  
  \ \  / /__ _ __ ___ _  ___  _ __  _ _ __   __ _  | (___ | |_ _ __ __ _| |_ ___  __ _ _   _ 
   \ \/ / _ \ '__/ __| |/ _ \| '_ \| | '_ \ / _` |  \___ \| __| '__/ _` | __/ _ \/ _` | | | |
    \  /  __/ |  \__ \ | (_) | | | | | | | | (_| |  ____) | |_| | | (_| | ||  __/ (_| | |_| |
     \/ \___|_|  |___/_|\___/|_| |_|_|_| |_|\__, | |_____/ \__|_|  \__,_|\__\___|\__, |\__, |
                                             __/ |                                __/ | __/ |
                                            |___/                                |___/ |___/  
'@ `
        -Description "Versioning is an essential part developing your app and AL-Go for GitHub supports a number of different options.`nIf you have multiple apps in the repository, then every app has a version number, which is part of the filename (.app file).`nThe repository also has a version number, which becomes part of the filename for the collection of apps (.zip file), created by the build output.`n`nFirst, you need to determine whether you want all apps in the repository to have the same version number (same as the collection of apps), or you want apps to be individually versioned?`n`nIf apps are using the same version number, you can use a workflow to increase major.minor version numbers after a release.`nIndividually versioned apps requires manual interaction and increases the likelyhood of mistakes." `
        -options ([ordered]@{"same" = "Use same version number for all apps and for the collection of apps (recommended)"; "individual" = "Apps are individually versioned and the collection uses it's own version number"}) `
        -question "Versioning strategy" `
        -previousStep `
        -default $settings.versioningStrategy
    
    if ($script:wizardStep -eq $script:thisStep+1) {
        $script:prevSteps.Push($script:thisStep)
        $settings.VersioningStrategy = $versioningStrategy
    }
}

$Step.VersioningMethod {

    $versioningMethod = Select-Value `
        -title @'
 __      __           _             _               __  __      _   _               _ 
 \ \    / /          (_)           (_)             |  \/  |    | | | |             | |
  \ \  / /__ _ __ ___ _  ___  _ __  _ _ __   __ _  | \  / | ___| |_| |__   ___   __| |
   \ \/ / _ \ '__/ __| |/ _ \| '_ \| | '_ \ / _` | | |\/| |/ _ \ __| '_ \ / _ \ / _` |
    \  /  __/ |  \__ \ | (_) | | | | | | | | (_| | | |  | |  __/ |_| | | | (_) | (_| |
     \/ \___|_|  |___/_|\___/|_| |_|_|_| |_|\__, | |_|  |_|\___|\__|_| |_|\___/ \__,_|
                                             __/ |                                    
                                            |___/                                     
'@ `
        -Description "The format of version numbers are major.minor.build.release.`nWhen building apps in AL-Go for GitHub, the Major.Minor part of the version number are read from app.json and the build.release part are calculated.`n- GitHub RUN_NUMBER is an auto-incrementing number for each workflow. The RunNumberOffset setting can be used to offset the starting value.`n- GitHub RUN_ATTEMPT increases for every re-run of jobs.`n`nSelect the method used for calculating build and release part of your app:" `
        -options ([ordered]@{"0" = "Use GitHub RUN_NUMBER.RUN_ATTEMPT (recommended)"; "2" = "Use UTC datetime yyyyMMdd.hhmmss"}) `
        -question "Versioning method" `
        -previousStep `
        -default $settings.versioningMethod
    
    if ($script:wizardStep -eq $script:thisStep+1) {
        $script:prevSteps.Push($script:thisStep)
        $settings.VersioningMethod = $versioningMethod
    }
}

$Step.DependencyStrategy {

    $dependencyStrategy = Select-Value `
        -title @'
  _____                            _                          _____ _             _                   
 |  __ \                          | |                        / ____| |           | |                  
 | |  | | ___ _ __   ___ _ __   __| | ___ _ __   ___ _   _  | (___ | |_ _ __ __ _| |_ ___  __ _ _   _ 
 | |  | |/ _ \ '_ \ / _ \ '_ \ / _` |/ _ \ '_ \ / __| | | |  \___ \| __| '__/ _` | __/ _ \/ _` | | | |
 | |__| |  __/ |_) |  __/ | | | (_| |  __/ | | | (__| |_| |  ____) | |_| | | (_| | ||  __/ (_| | |_| |
 |_____/ \___| .__/ \___|_| |_|\__,_|\___|_| |_|\___|\__, | |_____/ \__|_|  \__,_|\__\___|\__, |\__, |
             | |                                      __/ |                                __/ | __/ |
             |_|                                     |___/                                |___/ |___/  
'@ `
        -Description "AL-Go for GitHub supports two ways of handling dependencies and selection of Business Central artifacts to use for builds." `
        -options ([ordered]@{"updateDependencies" = "Automatically Update Dependencies (recommended)`nUsing this strategy will analyze apps and determine the first available Business Central version, which is compatible with all apps.`nAll Apps will be build against this version and all dependencies (incl. external) will be updated to require at minimum the actual apps used for building the app.`nWhen using this strategy, your app might not be compatible with the latest version of Business Central if your application dependency is set to an older version.`n"; "manual" = "Manually Update Dependencies`nUsing this strategy will build your apps using the latest version of Business Central.`nDependencies in app.json are left as is, and you need to manually update your dependencies when you take advantage of new functionality.`nWhen using this strategy your app might indicate compatibility with older versions without actually being compatible." }) `
        -question "Dependency Strategy" `
        -previousStep `
        -default $settings.dependencyStrategy
    
    if ($script:wizardStep -eq $script:thisStep+1) {
        $script:prevSteps.Push($script:thisStep)
        $settings.dependencyStrategy = $dependencyStrategy
    }
}

$Step.generateDependencyArtifact {

    $generateDependencyArtifact = Select-Value `
        -title @'
   _____                           _         _____                            _                                       _   _  __           _   
  / ____|                         | |       |  __ \                          | |                           /\        | | (_)/ _|         | |  
 | |  __  ___ _ __   ___ _ __ __ _| |_ ___  | |  | | ___ _ __   ___ _ __   __| | ___ _ __   ___ _   _     /  \   _ __| |_ _| |_ __ _  ___| |_ 
 | | |_ |/ _ \ '_ \ / _ \ '__/ _` | __/ _ \ | |  | |/ _ \ '_ \ / _ \ '_ \ / _` |/ _ \ '_ \ / __| | | |   / /\ \ | '__| __| |  _/ _` |/ __| __|
 | |__| |  __/ | | |  __/ | | (_| | ||  __/ | |__| |  __/ |_) |  __/ | | | (_| |  __/ | | | (__| |_| |  / ____ \| |  | |_| | || (_| | (__| |_ 
  \_____|\___|_| |_|\___|_|  \__,_|\__\___| |_____/ \___| .__/ \___|_| |_|\__,_|\___|_| |_|\___|\__, | /_/    \_\_|   \__|_|_| \__,_|\___|\__|
                                                        | |                                      __/ |                                        
                                                        |_|                                     |___/                                         
'@ `
        -Description "When building your apps, AL-Go for GitHub can generate a build artifact with all external dependencies used for generating this build.`nThis artifact will contain all the apps you need to install before you can install the apps in this repository." `
        -options ([ordered]@{"yes" = "Yes, generate dependency artifact with every build (recommended)"; "no" = "No, do not generate dependency artifact with every build." }) `
        -question "Generate dependency artifact" `
        -previousStep `
        -default $settings.generateDependencyArtifact
    
    if ($script:wizardStep -eq $script:thisStep+1) {
        $script:prevSteps.Push($script:thisStep)
        $settings.generateDependencyArtifact = $generateDependencyArtifact
    }
}

$Step.scheduledWorkflows {

    $answer = Select-Value `
        -title @'
   _____      _              _       _          _                      _     __ _                   
  / ____|    | |            | |     | |        | |                    | |   / _| |                  
 | (___   ___| |__   ___  __| |_   _| | ___  __| | __      _____  _ __| | _| |_| | _____      _____ 
  \___ \ / __| '_ \ / _ \/ _` | | | | |/ _ \/ _` | \ \ /\ / / _ \| '__| |/ /  _| |/ _ \ \ /\ / / __|
  ____) | (__| | | |  __/ (_| | |_| | |  __/ (_| |  \ V  V / (_) | |  |   <| | | | (_) \ V  V /\__ \
 |_____/ \___|_| |_|\___|\__,_|\__,_|_|\___|\__,_|   \_/\_/ \___/|_|  |_|\_\_| |_|\___/ \_/\_/ |___/
                                                                                                    
                                                                                                    
'@ `
        -Description "AL-Go for GitHub includes three workflows, which typically are setup to run on a schedule.`n" `
        -options ([ordered]@{"Current" = "Test Current    : $($settings.CurrentSchedule)"; "NextMinor" = "Test Next Minor : $($settings.NextMinorSchedule)"; "NextMajor" = "Test Next Major : $($settings.NextMajorSchedule)"; "none" = "No further changes needed" }) `
        -question "Select schedule to change" `
        -previousStep `
        -default "none"

    if ($answer -eq "none") {
        if ($script:wizardStep -eq $script:thisStep+1) {
            $script:prevSteps.Push($script:thisStep)
        }
    }
    else {
        $script:wizardStep = $step.ScheduledWorkflows
        $var = "$($answer)Schedule"
        $crontabUrl = "https://crontab.guru/#$($settings."$var".Replace(" ","_"))"
        Write-Host "Launching $crontabUrl to assist editing the crontab value"
        Start-Process $crontabUrl
        $newCronTab = Read-Host "Please enter a new crontab value for the $answer schedule (enter none to remove schedule, leave blank to make no change)"
        if ($newCronTab -eq "none") {
            $settings."$var" = ""
        }
        elseif ($newCronTab -ne "") {
            $settings."$var" = $newCronTab
        }
    }
}

$Step.GitHubRunner {

    # TODO: Create build agent automatically

    $gitHubRunner = Enter-Value `
        -title @'
  ____        _ _     _                            _   
 |  _ \      (_) |   | |     /\                   | |  
 | |_) |_   _ _| | __| |    /  \   __ _  ___ _ __ | |_ 
 |  _ <| | | | | |/ _` |   / /\ \ / _` |/ _ \ '_ \| __|
 | |_) | |_| | | | (_| |  / ____ \ (_| |  __/ | | | |_ 
 |____/ \__,_|_|_|\__,_| /_/    \_\__, |\___|_| |_|\__|
                                   __/ |               
                                  |___/                
'@ `
        -Description "Using GitHub hosted runners (hosted build agents, ex. windows-latest) is free for public repositories.`nFor private repositories, you have a number of minutes for free every month and need to pay extra for more (see more here: |https://github.com/organizations/$($settings.Org)/billing/plans|).`n`nSelf-Hosted runners will typically be faster, as they will cache docker images and artifacts, but you will pay for the costs of running the machine.`nYou can read about self-hosted runners here: |https://docs.github.com/en/actions/hosting-your-own-runners/about-self-hosted-runners|`nYou can setup self-hosted runners yourself by visiting this url: |https://github.com/organizations/$($settings.Org)/settings/actions/runners/new|`nYou can setup an Azure VM with a number of agents automatically by visiting: |https://aka.ms/getbuildagent|" `
        -question "Specify the label of the agent to use (ex. self-hosted), or a number to open a url" `
        -previousStep `
        -default $settings.GitHubRunner
    
    if ($script:wizardStep -eq $script:thisStep+1) {
        $script:prevSteps.Push($script:thisStep)
        $settings.GitHubRunner = $gitHubRunner
    }
}

$Step.Secrets {

    $neededSecrets = "- GhTokenWorkflow - must be a valid personal access token with permissions to modify workflows, created from |https://github.com/settings/tokens|`n- [environment-]AuthContext - Authentication context for authenticating to specific environments (continuous deployment, publish to production)`n- AdminCenterApiCredentials - An AuthContext for accessing the Admin Center Api (creating development environments)`n- AZURE_CREDENTIALS - is used as a GitHub secret to provide access to an Azure KeyVault with your secrets`n"
    if ($appType -eq "AppSource") {
        $neededSecrets += "- LicenseFile - needs to contain a direct download URL for your Business Central license file`n- CodeSignCertificateUrl - direct download URL for Code Signing certificate`n- CodeSignCertificatePassword - pfx password for code signing certificate."
    }

    $orgSecrets = @(invoke-gh -returnValue secret list --org $settings.org -ErrorAction SilentlyContinue)

    $default = "OG"
    if ($orgSecrets | Where-Object { $_ -like "AZURE_CREDENTIALS`t*" }) {
        $default = "OA"
    }

    $useSecrets = Select-Value `
        -title @'
   _____                    _       
  / ____|                  | |      
 | (___   ___  ___ _ __ ___| |_ ___ 
  \___ \ / _ \/ __| '__/ _ \ __/ __|
  ____) |  __/ (__| | |  __/ |_\__ \
 |_____/ \___|\___|_|  \___|\__|___/
                                    
                                    
'@ `
        -Description "When working with AL-Go for GitHub, or any other DevOps tool really, you will need to store a number of secrets securely.`n`nSome of the secrets you might need for AL-Go for GitHub are:`n$($neededSecrets)`n`nNote that organizational secrets are NOT available for private repositories in free GitHub plans.`nAL-Go for GitHub supports 4 ways for storing secrets:" `
        -question "Note, that you can always override organizational secrets in a repository, just by creating a new secret with the same name.`n`nSpecify which option you want to use for your secrets" `
        -options ([ordered]@{"OG" = "Use GitHub secrets on the organization level and allow repositories to access them (recommended)"; "RG" = "Use GitHub Secrets in the individual repository"; "OA" = "Use an Azure KeyVault for your secrets and setup access to the keyvault on the organization level and allow repositories to access this"; "RA" = "Use an Azure KeyVault for your secrets and setup access to the keyvault in the repository" }) `
        -default $default `
        -previousStep

    if ($script:wizardStep -eq $script:thisStep+1) {
        $script:prevSteps.Push($script:thisStep)

        $useAzureKeyVault = $useSecrets -like "?A"
        $useOrgSecrets = $useSecrets -like "O?"
    
        if ($useAzureKeyVault) { 
            $script:wizardStep = $step.AzureKeyVault
        }
        else {
            $script:wizardStep = $step.DefineSecrets
        }
    }
}

$step.AzureKeyVault {
    $description = "You need to create your Azure KeyVault manually to ensure the right permissions and security model.`nAfter creating your KeyVault, please specify the name of your keyVault here.`nIf your Keyvault is not in the $($azContext.Subscription.Id) subscription, then you need to specify <subscriptionid>/<keyvaultname>"
    $defaultParam = @{}
    if ($orgSecrets | Where-Object { $_ -like "AZURE_CREDENTIALS`t*" }) {
        $description = "NOTE: An existing Org. GitHub Secret exists, which provides access to an Azure KeyVault. Please ensure that the new repository has access to this org. Github Secret.`n`nIf the existing KeyVault connection cannot be used, please create your Azure KeyVault manually to ensure the right permissions and security model.`nAfter creating your KeyVault, please specify the name of your keyVault here.`nIf your Keyvault is not in the $($azContext.Subscription.Id) subscription, then you need to specify <subscriptionid>/<keyvaultname>"
        $defaultParam += @{ "default" = "reuse existing Azure KeyVault connection" }
    }
    $keyVaultName = Enter-Value `
            -title @'
                                 _  __       __      __         _ _   
     /\                         | |/ /       \ \    / /        | | |  
    /  \    _____   _ _ __ ___  | ' / ___ _   \ \  / /_ _ _   _| | |_ 
   / /\ \  |_  / | | | '__/ _ \ |  < / _ \ | | \ \/ / _` | | | | | __|
  / ____ \  / /| |_| | | |  __/ | . \  __/ |_| |\  / (_| | |_| | | |_ 
 /_/    \_\/___|\__,_|_|  \___| |_|\_\___|\__, | \/ \__,_|\__,_|_|\__|
                                           __/ |                      
                                          |___/                       
'@ `
        -description $description `
        -question "Please specify the name of your KeyVault" `
        -previousStep @defaultParam

    if ($keyVaultName -eq "reuse existing Azure KeyVault connection") {
        $script:prevSteps.Push($script:thisStep)
        $script:wizardStep = $step.DefineSecrets+1
    }
    elseif ($keyVaultName -ne "back") {
        try {
            if (-not ($azContext)) {
                Write-Host "In order to use Azure KeyVault, you need to authenticate to your Azure Account"
                Login-AzAccount
                $azContext = Get-AzContext
            }
            if (-not ($azContext)) {
                throw "Not authenticated"
            }
            $subscriptionId = $azContext.Subscription.Id
            $segments = $keyVaultName.split('/')
            if ($segments.Count -eq 2) {
                $subscriptionId = $segments[0]
                $keyVaultName = $segments[1]
            }
            $keyVault = Get-AzKeyVault -VaultName $keyVaultName -SubscriptionId $subscriptionId -WarningAction SilentlyContinue
            Write-Host "KeyVault $($keyVault.VaultName) OK"
            $keyVaultSecrets = @()
            $secrets.Keys | ForEach-Object {
                if ($keyvault | Get-AzKeyVaultSecret -Name $_ -ErrorAction SilentlyContinue) {
                    $keyVaultSecrets += @($_)
                }
            }
        }
        catch {
            Write-Host -ForegroundColor Red "Unable to locate or access KeyVault. Error was $($_.Exception.Message)"
            $script:wizardStep = $step.AzureKeyVault
        }

        if ($script:wizardStep -eq $script:thisStep+1) {
            $script:prevSteps.Push($script:thisStep)
        }
    }
}

$Step.DefineSecrets {

    $definedKeys = ""
    $options = [ordered]@{ }
    $secrets.Keys | ForEach-Object {
        $secret = $_
        if ($secrets."$secret") {
            $definedKeys += "$secret : OK`n"
        }
        elseif ($orgSecrets | Where-Object { $_ -like "$($secret)`t*" }) {
            $definedKeys += "$secret : already defined in Org. GitHub Secrets`n"
        }
        elseif ($useSecrets -like "?A" -and $keyvaultSecrets.Contains($secret)) {
            $definedKeys += "$secret : already defined in Azure KeyVault`n"
        }
        else {
            $definedKeys += "$secret : undefined`n"
        }
        $options += @{ "$secret" = "$secret" }
    }
    $options += @{ "none" = "No further secrets to define" }

    $NoteStr = ""
    if ($UseSecrets -like "?A") {
        $NoteStr = "`nNote that the secrets you modify here, will NOT modify the values in your KeyVault, they will instead be added as GitHub Secrets, which takes precedence over KeyVault secrets"
    }

    $setSecret = Select-Value `
        -title @'
  _____        __ _               _____ _ _   _    _       _        _____                    _       
 |  __ \      / _(_)             / ____(_) | | |  | |     | |      / ____|                  | |      
 | |  | | ___| |_ _ _ __   ___  | |  __ _| |_| |__| |_   _| |__   | (___   ___  ___ _ __ ___| |_ ___ 
 | |  | |/ _ \  _| | '_ \ / _ \ | | |_ | | __|  __  | | | | '_ \   \___ \ / _ \/ __| '__/ _ \ __/ __|
 | |__| |  __/ | | | | | |  __/ | |__| | | |_| |  | | |_| | |_) |  ____) |  __/ (__| | |  __/ |_\__ \
 |_____/ \___|_| |_|_| |_|\___|  \_____|_|\__|_|  |_|\__,_|_.__/  |_____/ \___|\___|_|  \___|\__|___/
                                                                                                     
'@ `
        -Description "You can always add or update secrets later, but you can also provide some of the values here$NoteStr`n`n$definedKeys`nPlease select which secret you want to modify?" `
        -question "Select which secret you want to set? (or select a when you are done)" `
        -options $options `
        -default "none" `
        -previousStep

    if ($setSecret -eq "none") {
        if ($script:wizardStep -eq $script:thisStep+1) {
            $script:prevSteps.Push($script:thisStep)
        }
    }
    elseif ($setSecret -ne "back") {
        $script:wizardStep = $step.DefineSecrets
        Write-Host -ForegroundColor Yellow "`n$setSecret`n"
        switch ($setSecret) {
        "ghTokenWorkflow" {
            Write-Host "In order to run the Update AL-Go System files workflow, the ghTokenWorkflow secret needs to be defined.`nVisit the personal access tokens site for your account on GitHub and generate a new token with the workflow scope selected.`nNote that if you specify a PAT with an expiration date, you will have to update the token when it expires.`n`nYou can visit the Personal Access Tokens site on GitHub using this URL:`n`nhttps://github.com/settings/tokens`n"
            $secrets.ghTokenWorkflow = Read-Host "Please paste the Personal Access Token with workflow scope here"
        }
        "AdminCenterApiCredentials" {
            Write-Host "If you want to create an online development environment in AL-Go for GitHub, you can specify a secret called AdminCenterApiCredentials.`nAdminCenterApiCredentials needs to be a json object, containing the parameters to create a new BcAuthContext.`nThe secret will expire every 90 days and you can refresh the object by running the following snippet and pasting the new value into the secret:`n`n`$authContext = New-BcAuthContext -includeDeviceLogin`n@{""tenantID"" = `$authContext.TenantId; ""RefreshToken"" = `$authContext.RefreshToken } | ConvertTo-Json -Compress | Set-Clipboard`n`nIn order to create the secret you need to use your admin center credentials with a device login`n"
            $creds = Read-Host "Please paste your AdminCenterApiCredentials here or press ENTER to invoke device code flow. (enter none to skip this step)"
            if ($creds -ne "none") {
                try {
                    if ($creds -eq "") {
                        $authContext = New-BcAuthContext -includeDeviceLogin
                        if ($authContext) {
                            Write-Host "Connecting to Admin Center API"
                            Get-BcEnvironments -bcAuthContext $authContext | Out-Null
                            Write-Host "OK"
                            $secrets.AdminCenterApiCredentials = @{"tenantID" = $authContext.TenantId; "RefreshToken" = $authContext.RefreshToken } | ConvertTo-Json -Compress
                        }
                    }
                    else {
                        $parameters = $creds | ConvertFrom-Json | ConvertTo-HashTable
                        $authContext = New-BcAuthContext @parameters
                        if ($authContext) {
                            Write-Host "Connecting to Admin Center API"
                            Get-BcEnvironments -bcAuthContext $authContext | Out-Null
                            Write-Host "OK"
                            $secrets.AdminCenterApiCredentials = $creds
                        }
                    }
                }
                catch {
                    Write-Host -ForegroundColor Red "Illegal AdminCenterApiCredentials or credentials does not give access to admin center API. Error was $($_.Exception.Message)"
                }

            }
        }
        "LicenseFileUrl" {
            while ($true) {
                $secrets.LicenseFileUrl = Read-Host "Please enter a direct download URL for your license file"
                if (-not ($secrets.LicenseFileUrl)) { break }
                if (TestUrl $secrets.LicenseFileUrl) { break }
                Write-Host -ForegroundColor Red "Unable to reach the specified URL"
            }
        }
        "CodeSignCertificateUrl" {
            while ($true) {
                $secrets.CodeSignCertificateUrl = Read-Host "Please enter a direct download URL for your code signing certificate"
                if (-not ($secrets.CodeSignCertificateUrl)) { break }
                if (TestUrl $secrets.CodeSignCertificateUrl) { break }
                Write-Host -ForegroundColor Red "Unable to reach the specified URL"
            }
        }
        "CodeSignCertificatePassword" {
            $secrets.CodeSignCertificatePassword = Read-Host "Please enter the pfx password for your code signing certificate" -AsSecureString | Get-PlainText
        }
        "AZURE_CREDENTIALS" {
            Write-Host "AZURE_CREDENTIALS is a secret, which consists of a json construct, with a clientId and a clientSecret of a Service Principal, which gives access to an Azure KeyVault`nYou can follow the description here:`nhttps://docs.microsoft.com/en-us/azure/developer/github/github-key-vault`n`nTo create a service principal, which provides access - or you can specify a name and allow the wizard to create the Service Principal automatically.`n"
            if ($orgSecrets | Where-Object { $_ -like "$($setSecret)`t*" }) {
                Write-Host "An Org. GitHub Secret called AZURE_CREDENTIALS already exists.`nIf you create a new GitHub Secret for accessing the Azure KeyVault, this will be saved as a repository secret and thus take precedence over the Org. GitHub Secret.`n"
                $secrets.AZURE_CREDENTIALS = Read-Host "Please enter the AZURE_CREDENTIALS or the name of the Service Principal, which will be created (empty means do NOT create a new service principal - use the existing)"
            }
            else {
                $secrets.AZURE_CREDENTIALS = Read-Host "Please enter the AZURE_CREDENTIALS or the name of the Service Principal, which will be created (default is $($settings.org)/$($settings.repo))"
                if ($secrets.AZURE_CREDENTIALS -eq "") { $secrets.AZURE_CREDENTIALS = "$($settings.org)/$($settings.repo)" }
            }
        }
        }
    }
}


$Step.Doit {

    $secretsToSet = $secrets.Keys | Where-Object { $secrets."$_" }
    $secretsStr = ""
    if ($secretsToSet) {
        $secretsStr = "Secrets to set:`n$($secretsToSet | Out-String)"
    }

    $doit = Enter-Value `
           -title @'
   _____      _                 _____                      _ _                   
  / ____|    | |               |  __ \                    (_) |                  
 | (___   ___| |_ _   _ _ __   | |__) |___ _ __   ___  ___ _| |_ ___  _ __ _   _ 
  \___ \ / _ \ __| | | | '_ \  |  _  // _ \ '_ \ / _ \/ __| | __/ _ \| '__| | | |
  ____) |  __/ |_| |_| | |_) | | | \ \  __/ |_) | (_) \__ \ | || (_) | |  | |_| |
 |_____/ \___|\__|\__,_| .__/  |_|  \_\___| .__/ \___/|___/_|\__\___/|_|   \__, |
                       | |                | |                               __/ |
                       |_|                |_|                              |___/ 
'@ `
            -description "Please review the following settings and select Z to go back and modify things. Select Y to start setting up the repository.`nSettings:`n$($settings | Out-String)$secretsStr" `
            -options @("Y","N") `
            -question "Please select Y to start setting up the repository" `
            -previousStep

    if ($doit -eq "Y") {

        New-ALGoRepo `
            -org $settings.Org `
            -repo $settings.repo `
            -appType $settings.AppType `
            -accessControl $settings.AccessControl `
            -country $settings.country `
            -additionalCountries @($settings.additionalCountries.Split(',') | ForEach-Object { $_.Trim() }) `
            -additionalCountriesAlways:($settings.additionalCountriesAlways -eq "yes") `
            -versioningStrategy ([int]$settings.VersioningMethod+16*($settings.VersioningStrategy -eq "same")) `
            -updateDependencies:($settings.dependencyStrategy -eq "UpdateDependencies") `
            -generateDependencyArtifact:($settings.generateDependencyArtifact -eq "yes") `
            -gitHubRunner $settings.GitHubRunner `
            -currentschedule $settings.currentSchedule `
            -nextMinorSchedule $settings.NextMinorSchedule `
            -nextMajorSchedule $settings.NextMajorSchedule `
            -secrets $secrets
    }
}


}
}

# SIG # Begin signature block
# MIInSQYJKoZIhvcNAQcCoIInOjCCJzYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCTaErACAxcLSCK
# ie026vuN0H2H18ylewDlofNURtUrr6CCDLowggX1MIID3aADAgECAhMzAAACHU0Z
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
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIJSiUCRx
# czO2PkVh2c91ssjEFy7Tva/vfg/VoioZm+2CMEIGCisGAQQBgjcCAQwxNDAyoBSA
# EgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20w
# DQYJKoZIhvcNAQEBBQAEggEAoOQ7lTym5LafcuzrcRxPGCT6x2uqDVUIRbEYCq/x
# WYJBCtTkG5YI5MIEg03Ee6NPkwG6shRxl9EW0h6HWA+ASdUyNLo7ZkrE80upWrip
# 57ZErKiJIG5Blzpm7xf/gDZkyG4biWJ5BSPbExfcRMYpXXCgJE2FeEqJog7Jfd3j
# 6CNJDUrG+oCpj3PoJfoON9X2D78Vhf0vbSzifvP2oW63JQYy8X8MNNjVluHEsiVc
# wrRmFoQaFeSsr4+ZTl+pAATSHsoHH6FmVG1PXS7F+L7kgS7eQG4FWodUh004QQs0
# Fe+glmqY10TmKEH9ockcQ/YLWybuj2Ey99Oq0TnsiVt15aGCF5cwgheTBgorBgEE
# AYI3AwMBMYIXgzCCF38GCSqGSIb3DQEHAqCCF3AwghdsAgEDMQ8wDQYJYIZIAWUD
# BAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGEWQoD
# ATAxMA0GCWCGSAFlAwQCAQUABCC8R/jx330mWcRqqnSVOJ/F07s7njELrwSsatln
# +3aBggIGaoWNF3g6GBMyMDI2MDgyNzA2MjkzNi4wNzlaMASAAgH0oIHRpIHOMIHL
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxN
# aWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRT
# UyBFU046RTAwMi0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFNlcnZpY2WgghHtMIIHIDCCBQigAwIBAgITMwAAAikO1WQqtJfyGgABAAAC
# KTANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAe
# Fw0yNjAyMTkxOTQwMDdaFw0yNzA1MTcxOTQwMDdaMIHLMQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmlj
# YSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046RTAwMi0wNUUw
# LUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIi
# MA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCeItFq4z1oCYSmUZmpYDsbJWEu
# ++1bbc/Mz7Pa3I0ZX5EON+WirB0FvnGlyFRUylzO5TJXZfU8QFPOU95P1Y1OZ8J+
# quA5G+AWSBOr/48scl0s9RBpqgTMq/lbyqBz4CMmvVR2QevAgVp4a1hbmOm9G7YW
# ey68N5F5rSDYV0wMlg4Iy8YRuFgRN2eBpVXt9IvFaFmBnQLZfo22KZ3L8PWEHUhX
# U5dLOSZoTfqqQ/B+deW56ACMnnHjPxZu+szHhZMLUrMWTgs9J7Cn8DtelcKj9aM+
# 0Zq7tkSDHCrwo6eCSfw3clktXRRrdmsccal8RCDiNFFgZsypwF2aGAF6kg41+Ql+
# thXpnOMUH4mPCAJZWp0zDWowsK/Yo5jHL1pT/AgbL3FoAy4cbhOI4Pb1eQFG+jT7
# skS2F/b+ZACUA1EDZ830K+Bu0yw+FpSGy8tpd1szk3cUYjIpzIG4z3oFNmiSJN8Y
# dNd4SHsER5Dks5bxiKbpvmfrOA39jTb7EW2TT7ySWgJISfvTezuLmQsTVSzNsvap
# VlHhE2zBqDw409nvOtitCFbnhhXNfatzb2+Gf2tX2s6YBa151CC/8+emJvvegXbW
# NudzYt8cFRom0PZ+fJRhhBfdSqCqr8QeOGJ8VYlmxFXqx1SdDSkTCSgpsskGqZwh
# /6umA1g4L7zeGBNngQIDAQABo4IBSTCCAUUwHQYDVR0OBBYEFCdNRaSL9AW8QvaQ
# 21WjRAXKN4M7MB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1Ud
# HwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3Js
# L01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggr
# BgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNv
# bS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIw
# MTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgw
# DgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUAA4ICAQA9wc72lf/czDhp09T3
# PGAMOQhxl/x04jpE7t39FeqQSn2Up6DVzhgwnzCqY3NIhLtUaWrd7NxvrhZDca+J
# 4xzvrRQNPHeRQpnJVeHsyTu53gTBlUB1TRI6OnZt/AVmR9oMJ/NBOqB+d+SOb8Px
# 6zRgRwk62sFkOkB5lig/DMnYEeR/amW9Hdo8vXcKmaa/DbSOAHSdfZFt+iqMZfNl
# kEOn71/RAKTNv4Qpq/2FhcjMMmSkIhshBdBVB0VjmkwFfhVUf5TTuLJ9sDR4EyCv
# OZJ3B6g7Iw6WjQxycjwkfzsVMTpfusJ5SwdOHL8yGPWZOePjwa8ISXWs6kiVK/6S
# 0/JVb1LpxpyYKREQjnU/5OecKt2OXlHdwFWZrwAi98RPZa6EExcb/LGLf10tNHju
# 1eTlohY0jzNZQ0BDgSuMZgMU+8EEjtMQMIDnlPGEUON7LHXHH0KL0FA01PEWVZKr
# r/LUOuuDTNFzw543FPMp4gkCIFlKdRuciR1IXOk+Xse6rj9tJFYgVn+44BHou2XQ
# e5RX30ef3AQWa0mxyGDqJzGsV3X5+bNQeMV88iWulJPq5sgnGG9O/H1/HH4HsO9Z
# KGX/WrJpQmFuQrTOR49XjveaC0xaFmGsNg+RhbtD5qTkn+ISDvw0IJ/E/VXNdz/y
# Wgol6r507hT8sAMupnhkF2uw1DCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkA
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
# T3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOkUwMDItMDVFMC1E
# OTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEw
# BwYFKw4DAhoDFQC3v9iSO22xob7ZxN5dXCEq+9Iv/6CBgzCBgKR+MHwxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29m
# dCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBCwUAAgUA7jntmDAiGA8y
# MDI2MDgyNjIyNTYyNFoYDzIwMjYwODI3MjI1NjI0WjB3MD0GCisGAQQBhFkKBAEx
# LzAtMAoCBQDuOe2YAgEAMAoCAQACAhVEAgH/MAcCAQACAhI7MAoCBQDuOz8YAgEA
# MDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAI
# AgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBAE37w8gnup/iUyTB61NHJg3jt8I5
# 91NCcjyr/X49uDpqMPIoVuVq/yYlcL9AjQxM48KRtYYPm2QXoBhhPB5EvC6rqhDu
# Kso1stCsHt3qEDSdnY1fQZhyM7vNmNOaBlPae2wR6PF1WOSbHNU+q+ECALDEMRO9
# +wLNVtAhak5XJUK2Vk5cYk9DtNoC3ylwwBMGcA2iBgyftWiNgw+Zh8ElP1YdESyk
# DjrZgLJ/XY0gic89NoviKJtNC9rBibehJoNpNPpwrcjoXCP+4KbXu3AXmR9w25Y1
# KKLI0nresbT/J6wVc4yuxUxNh9FYJmyfIsI9j4mE5GIV4Z00RSYNRcQLaR4xggQN
# MIIECQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQ
# MA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
# MSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAikO
# 1WQqtJfyGgABAAACKTANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0G
# CyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCA9kH4po3+TbeH+OKZwtjPRUms7
# hheMx+qZ/k+xO/9X6DCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EILfKPfEi
# tvD/lSvEumxqPkkeOEtgkmKFEVMuel9oOrqSMIGYMIGApH4wfDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgUENBIDIwMTACEzMAAAIpDtVkKrSX8hoAAQAAAikwIgQgLetGcOD4
# k68sAgAitb2kO0u9U/IvhXEKvJHbDaj8L1EwDQYJKoZIhvcNAQELBQAEggIAW5ZQ
# pdwT24iYHbfAxfbAkj7/B+s7CplPnP2JU1KPccliwqDMotqkSiLrmbGkYKEQgCgg
# UdrRK3PsEUldF8YBFxm0/plVF1aX4anKJdXymKW5YrywqjTrIxzBMgRWOoHyvPUk
# Z8gvSIBT4GmyK8AJPwnUHZ7GYhdHR4xOSMjGvOLkN+fgKaQ/OiLmw2obA/NiWvzZ
# 2tx5aJ+Q2iMMeQky3CjBw+VK3Py9Zeq7Itp+Q3RfTMe2FESzFPL0IINyAVwAoXb5
# xMUwIKphHQxGjC6ztXiPbfq1MMs5sVDvwyouvqFsqrrRtRwLb3uRey87KQcmrCde
# dytshDEtsrq+W2Iw+YuY/ca37S3TbedAb7Hfnq4msdg0svfDtwUxipdd4fNtMCB7
# hUGHgZIWhXf7AyKbS7laP6SUeH2koqRxKls/zXf02+EQH0AJ+UNP1bHayTWkuET8
# 6w0OcS4IvDG6nOT809dXkL98M8dodK3x60bFMZaljGAAds2sSMY/NxLL3mo1Xnsg
# UiFwZVkKfxMv27gvDnaiEklz+4nBh6UQiMzbDuJSJBeL/u90Gs5X3SLOYqrT9G4o
# rYwpoGYyTmxPTszVZ+vhe/zX6ERaMuO3wd4jnVWb/LoUgWMsmqVe2eIzF6Awh7pc
# EvWGJwk2omZmGn2/D2XlNNMhVB7KD1ngAd+kFig=
# SIG # End signature block
