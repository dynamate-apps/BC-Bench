<# 
 .Synopsis
  Cleans the Database in a BC Container
 .Description
  This function will remove existing base app from the database in a container, leaving the container without app
  You will have to publish a new base app before Business Central is useful
 .Parameter containerName
  Name of the container in which you want to clean the database
 .Parameter saveData
  Include the saveData switch if you want to save data while uninstalling apps
 .Parameter onlySaveBaseAppData
  Include the onlySaveBaseAppData switch if you want to only save data in the base application and not in other apps
 .Parameter doNotUnpublish
  Include the doNotUnpublish switch if you do not want to unpublish apps (only 15.x containers or later)
 .Parameter useNewDatabase
  Add this switch if you want to create a new and empty database in the container
  This switch (or useCleanDatabase) is needed when turning a C/AL container into an AL Container.
 .Parameter doNotCopyEntitlements
  Specify this parameter to avoid copying entitlements when using -useNewDatabase
 .Parameter copyTables
  Array of table names to copy from original database when using -useNewDatabase
 .Parameter companyName
  CompanyName when using -useNewDatabase. Default is My Company.
 .Parameter credential
  Credentials of the container super user if using NavUserPassword authentication
 .Parameter evaluationCompany
  Specifies whether the company that you want to create is an evaluation company when using -useNewDatabase
 .Example
  Clean-BcContainerDatabase -containerName test
#>
function Clean-BcContainerDatabase {
    Param (
        [string] $containerName = $bcContainerHelperConfig.defaultContainerName,
        [switch] $saveData,
        [Switch] $onlySaveBaseAppData,
        [switch] $doNotUnpublish,
        [switch] $useNewDatabase,
        [switch] $doNotCopyEntitlements,
        [Switch] $keepBaseApp,
        [string[]] $keepApps = @(),
        [string[]] $copyTables = @(),
        [string] $companyName = "My Company",
        [PSCredential] $credential,
        [switch] $evaluationCompany
    )

$telemetryScope = InitTelemetryScope -name $MyInvocation.InvocationName -parameterValues $PSBoundParameters -includeParameters @()
try {

    $platform = Get-BcContainerPlatformversion -containerOrImageName $containerName
    if ("$platform" -eq "") {
        $platform = (Get-BcContainerNavVersion -containerOrImageName $containerName).Split('-')[0]
    }
    [System.Version]$platformversion = $platform

    if ($platformversion.Major -lt 14) {
        throw "Container $containerName does not support the function Clean-BcContainerDatabase"
    }

    $myFolder = Join-Path $bcContainerHelperConfig.hostHelperFolder "Extensions\$containerName\my"
    $licenseFile = @(Get-Item "$myFolder\license.*")
    if ($licenseFile.Count -eq 0) {
        throw "Container must be started with a developer license to perform this operation."
    }
    elseif ($licenseFile.Count -lt 1) {
        throw "There can only be one license file in the my folder to perform this operation."
    }

    $customconfig = Get-BcContainerServerConfiguration -ContainerName $containerName

    if ($useNewDatabase) {
        if ($saveData) {
            throw "Cannot use SaveData with useNewDatabase."
        }
        if ($doNotUnpublish) {
            throw "Cannot use doNotUnpublish with useNewDatabase."
        }
        if ($customconfig.ClientServicesCredentialType -ne "Windows" -and !($credential)) {
            throw "You need to specify credentials if using useNewDatabase and authentication is not Windows"
        }

        if ($platformversion.Major -lt 15) {
            $SystemSymbolsFile = Join-Path $bcContainerHelperConfig.hostHelperFolder "Extensions\$containerName\system.app"
            $systemSymbols = Get-BcContainerAppInfo -containerName $containerName -symbolsOnly | Where-Object { $_.Name -eq "System" }
            Get-BcContainerApp -containerName $containerName -appName $SystemSymbols.Name -publisher $SystemSymbols.Publisher -appVersion $SystemSymbols.Version -appFile $SystemSymbolsFile -credential $credential
            $SystemApplicationFile = ""
        }
        else {
            if ($platformversion.Major -lt 27) {
                $SystemSymbolsFile = ":" + (Invoke-ScriptInBCContainer -containerName $containerName -scriptblock {
                    (Get-Item "C:\Program Files\Microsoft Dynamics NAV\*\AL Development Environment\System.app").FullName
                })
            }
            else {
                $SystemSymbolsFile = ""
            }
            $SystemApplicationFile = ":C:\Applications\System Application\Source\Microsoft_System Application.app"
        }

        if (!$doNotCopyEntitlements) {
            $copyTables += @("Entitlement", "Entitlement Set", "Membership Entitlement")
        }

        Invoke-ScriptInBCContainer -containerName $containerName -useSession $false -usePwsh $false -scriptblock { Param($platformVersion, $databaseName, $databaseServer, $databaseInstance, $copyTables, $multitenant)
        
            Write-Host "Stopping ServiceTier in order to replace database"
            Set-NavServerInstance -ServerInstance $ServerInstance -stop
        
            $databaseServerInstance = $databaseServer
            if ($databaseInstance) {
                $databaseServerInstance += "\$databaseInstance"
            }

            if (($platformVersion.Major -ge 15) -and ($platformVersion.Major -le 26)) {
                $dbproperties = Invoke-Sqlcmd -ServerInstance $databaseServerInstance -Query "SELECT [applicationversion],[applicationfamily] FROM [$databaseName].[dbo].[`$ndo`$dbproperty]"
            } elseif( $platformVersion.Major -ge 27) {
                $dbproperties = Invoke-Sqlcmd -ServerInstance $databaseServerInstance -Query "SELECT [applicationfamily] FROM [$databaseName].[dbo].[`$ndo`$dbproperty]"
            }

            if ($copyTables) {
                Copy-NavDatabase -sourceDatabaseName $databaseName -destinationDatabaseName "mytempdb" -DatabaseServer $databaseServer -databaseInstance $databaseInstance
            }
            Remove-NavDatabase -databasename $databaseName -databaseserver $databaseServer -databaseInstance $databaseInstance

            if ($multitenant) {
                Write-Host "Multitenant setup. Creating Single Tenant Database and switching to multitenancy later"
                Set-NavServerConfiguration -ServerInstance $ServerInstance -KeyName "Multitenant" -KeyValue "False" -WarningAction SilentlyContinue
                Set-NavServerConfiguration -ServerInstance $ServerInstance -KeyName "DatabaseName" -KeyValue "tenant" -WarningAction SilentlyContinue
                $databaseName = "tenant"

                Remove-NavDatabase -databasename "tenant" -databaseserver $databaseServer -databaseInstance $databaseInstance
                Remove-NavDatabase -databasename "default" -databaseserver $databaseServer -databaseInstance $databaseInstance
            }

            $CollationParam = @{}
            $collationFile = "c:\run\my\Collation.txt"
            if (!(Test-Path $collationfile)) {
                $collationFile = "c:\run\Collation.txt"
            }
            if (Test-Path $collationFile) {
                $Collation = Get-Content $collationFile
                $CollationParam = @{ "Collation" = $collation }
                Write-Host "Creating new database $databaseName on $databaseServerInstance with Collation $Collation"
            }
            else {
                Write-Host "Creating new database $databaseName on $databaseServerInstance with default Collation"
            }

            if (($platformVersion.Major -ge 15) -and ($platformVersion.Major -le 26)) {
                New-NAVApplicationDatabase -DatabaseServer $databaseServerInstance -DatabaseName $databaseName @CollationParam | Out-Null
                Invoke-Sqlcmd -ServerInstance $databaseServerInstance -Query "UPDATE [$databaseName].[dbo].[`$ndo`$dbproperty] SET [applicationfamily] = '$($dbproperties.applicationfamily)', [applicationversion] = '$($dbproperties.applicationversion)'"
            } elseif ($platformVersion.Major -ge 27) {
                # In 27.x and later applicationversion is removed from the dbproperty table
                New-NAVApplicationDatabase -DatabaseServer $databaseServerInstance -DatabaseName $databaseName @CollationParam | Out-Null
                Invoke-Sqlcmd -ServerInstance $databaseServerInstance -Query "UPDATE [$databaseName].[dbo].[`$ndo`$dbproperty] SET [applicationfamily] = '$($dbproperties.applicationfamily)'"
            } else {
                Create-NAVDatabase -databasename $databaseName -databaseserver $databaseServerInstance @CollationParam | Out-Null
            }

            if ($copyTables) {
                $copyTables | % {
                    Write-Host "Copying table [$_] from original database"

                    $fields = Invoke-Sqlcmd -ServerInstance $databaseServerInstance -database "mytempdb" -query "SELECT * FROM INFORMATION_SCHEMA.COLUMNS where TABLE_SCHEMA = 'dbo' AND TABLE_NAME = '$_'" | Where-Object { $_.Column_Name -ne "timestamp" } | % { """$($_.Column_Name)""" }

                    Invoke-Sqlcmd -ServerInstance $databaseServerInstance -Query "Delete From [$databaseName].[dbo].[$_]"
                    Invoke-Sqlcmd -ServerInstance $databaseServerInstance -Query "Insert Into [$databaseName].[dbo].[$_] ($($([String]::Join(',',$fields)))) Select $([String]::Join(',',$fields)) from [mytempdb].[dbo].[$_]"
                }
                Remove-NavDatabase -databaseName "mytempdb" -databaseserver $databaseServer -databaseInstance $databaseInstance
            }
            
            Write-Host "Starting Service Tier"
            Set-NavServerInstance -ServerInstance $ServerInstance -start
            
            Write-Host "Synchronizing"
            Sync-NavTenant -ServerInstance $ServerInstance -Force
        
        } -argumentList $platformVersion, $customconfig.DatabaseName, $customconfig.DatabaseServer, $customconfig.DatabaseInstance, $copyTables, ($customconfig.Multitenant -eq "True")
        
        Write-Host "Importing license file"
        Import-BcContainerLicense -containerName $containerName -licenseFile $licenseFile[0].FullName
        
        if ($SystemSymbolsFile) {
            Write-Host "Publishing System Symbols"
            Publish-BcContainerApp -containerName $containerName -appFile $SystemSymbolsFile -packageType SymbolsOnly -skipVerification -ignoreIfAppExists
        }

        Write-Host "Creating Company"
        New-CompanyInBcContainer -containerName $containerName -companyName $companyName -evaluationCompany:$evaluationCompany
        
        if ($SystemApplicationFile) {
            Write-Host "Publishing System Application"
            Publish-BcContainerApp -containerName $containerName -appFile $SystemApplicationFile -skipVerification -install -sync -ignoreIfAppExists
        }

        if ($customconfig.ClientServicesCredentialType -eq "Windows") {
            Write-Host "Creating user $($env:USERNAME)"
            Invoke-ScriptInBCContainer -containerName $containerName -scriptblock { Param($username)
                New-NavServerUser -ServerInstance $ServerInstance -WindowsAccount $username
                New-NavServerUserPermissionSet -ServerInstance $ServerInstance -WindowsAccount $username -PermissionSetId SUPER
            } -argumentList $env:USERNAME
        }
        else {
            Write-Host "Creating user $($credential.UserName)"
            New-BcContainerBcUser -containerName $containerName -Credential $credential -PermissionSetId SUPER -ChangePasswordAtNextLogOn:$false
        }

        if ($customconfig.Multitenant -eq "True") {
            
            Write-Host "Switching to multitenancy"
            Invoke-ScriptInBCContainer -containerName $containerName -scriptblock { Param($databaseName, $databaseServer, $databaseInstance)
                $databaseServerInstance = $databaseServer
                if ($databaseInstance) {
                    $databaseServerInstance += "\$databaseInstance"
                }

                Write-Host "Stopping ServiceTier"
                Set-NavServerInstance -ServerInstance $ServerInstance -stop

                Set-NavServerConfiguration -ServerInstance $ServerInstance -KeyName "DatabaseName" -KeyValue "$databaseName" -WarningAction SilentlyContinue
        
                Invoke-sqlcmd -serverinstance $databaseServerInstance -Database "tenant" -query 'CREATE USER "NT AUTHORITY\SYSTEM" FOR LOGIN "NT AUTHORITY\SYSTEM";'
                Export-NAVApplication -DatabaseServer $DatabaseServer -DatabaseInstance $DatabaseInstance -DatabaseName "tenant" -DestinationDatabaseName $databaseName -Force -ServiceAccount 'NT AUTHORITY\SYSTEM' | Out-Null
                Write-Host "Removing Application from tenant"
                Remove-NAVApplication -DatabaseServer $DatabaseServer -DatabaseInstance $DatabaseInstance -DatabaseName "tenant" -Force | Out-Null

                Set-NavServerConfiguration -ServerInstance $ServerInstance -KeyName "Multitenant" -KeyValue "True" -WarningAction SilentlyContinue
                Write-Host "Starting ServiceTier"

                Set-NavServerInstance -ServerInstance $ServerInstance -start

                Write-Host "Copying tenant to default db"
                Copy-NavDatabase -SourceDatabaseName "tenant" -DestinationDatabaseName "default"

                Write-Host "Mounting default tenant"
                Mount-NavDatabase -ServerInstance $ServerInstance -TenantId "default" -DatabaseName "default"

            } -argumentList $customconfig.DatabaseName, $customconfig.DatabaseServer, $customconfig.DatabaseInstance
        }

    }
    else {
        
        if (!$saveData) {
            Get-CompanyInBcContainer -containerName $containerName -tenant Default | % { Remove-CompanyInBcContainer -containerName $containerName -companyName $_.CompanyName -tenant Default }
        }

        $installedApps = Get-BcContainerAppInfo -containerName $containerName -tenantSpecificProperties -sort DependenciesLast | 
            Where-Object { (-not (($_.Name -eq "System Application") -or ($keepApps -contains $_.AppId) -or ($keepBaseApp -and ($_.Name -eq "BaseApp" -or $_.Name -eq "Base Application" -or $_.Name -eq "Application")))) }

        $installedApps | % {
            $app = $_
            Invoke-ScriptInBCContainer -containerName $containerName -scriptblock { Param($app, $SaveData, $onlySaveBaseAppData)
                if ($app.IsInstalled) {
                    Write-Host "Uninstalling $($app.Name)"
                    $tenant = "Default"
                    if ($app.Tenant)
                    {
                      $tenant = $app.Tenant
                    }
                    $doNotSaveData = (!$SaveData -or ($Name -ne "BaseApp" -and $Name -ne "Base Application" -and $onlySaveBaseAppData))
                    $app | Uninstall-NavApp -tenant $tenant -Force -doNotSaveData:$doNotSaveData
                    if ($doNotSaveData) {
                        Write-Host "Cleaning Schema from $($app.Name)"
                        $app | Sync-NAVApp -tenant $tenant -Mode Clean -Force
                    }
                }
            } -argumentList $app, $SaveData, $onlySaveBaseAppData
        }
    
        if ($platformversion.Major -eq 14) {
            Invoke-ScriptInBcContainer -containerName $containerName -scriptblock { Param ( $customConfig )
                
                if ($customConfig.databaseInstance) {
                    $databaseServerInstance = "$($customConfig.databaseServer)\$($customConfig.databaseInstance)"
                }
                else {
                    $databaseServerInstance = $customConfig.databaseServer
                }
        
                Write-Host "Removing C/AL Application Objects"
                Delete-NAVApplicationObject -DatabaseName $customConfig.databaseName -DatabaseServer $databaseServerInstance -Filter 'ID=1..1999999999' -SynchronizeSchemaChanges Force -Confirm:$false
    
            } -argumentList $customconfig
        }
        else {
            if (!$doNotUnpublish) {
                $installedApps | % {
                    $app = $_
                    Invoke-ScriptInBCContainer -containerName $containerName -scriptblock { Param($app)
                        if ($app.IsPublished) {
                            Write-Host "Unpublishing $($app.Name)"
                            $app | UnPublish-NavApp
                        }
                    } -argumentList $app
                }
            }
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
Export-ModuleMember -Function Clean-BcContainerDatabase


# SIG # Begin signature block
# MIInSQYJKoZIhvcNAQcCoIInOjCCJzYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCpUQD3APobspCb
# hR++I3R3yV2roPUSUuGDmcvX4tS8zqCCDLowggX1MIID3aADAgECAhMzAAACHU0Z
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
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIEvsWCQ2
# tFtVwzgwRld7g5JfZawUvgdKOoOtmgugMFNNMEIGCisGAQQBgjcCAQwxNDAyoBSA
# EgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20w
# DQYJKoZIhvcNAQEBBQAEggEAE6rwpPlW7JaFnbNDAv8TMj9HWYy5N2CK+u+iRCup
# WtejlJU13MCRtTIfMfGnWYEaWynC3/RYP9s4PQai4zMy6qVF0DgrDAtHa89aDiow
# pHgbo558xZGi2qU2aBypB0lUEFaD9fKh/aG2j5b8fZYZZOj5+kuB/mGkd67MFDOM
# CWcILkgLNrb2prkJu957A3fCtJv8SuaxPWmmykHcee6s9ycXM5cOiho5uZTwt1UV
# vp+TvjqnKkzjI8TCbck1VWlOzKEpVpOtr4XRjCulRGNFtLgYSshWgNd7TFIIMWud
# 8wZFaTShqpOOVJ3Gho1HGNVUGvXCItpeJvINwYnRHfmP6KGCF5cwgheTBgorBgEE
# AYI3AwMBMYIXgzCCF38GCSqGSIb3DQEHAqCCF3AwghdsAgEDMQ8wDQYJYIZIAWUD
# BAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGEWQoD
# ATAxMA0GCWCGSAFlAwQCAQUABCBMeiY6s22XyBhYTsA0wOga0q0xBFM3wC06QNuP
# 6OnZ+wIGaoWvWCkCGBMyMDI2MDgyNzA2MzAzOC42MzJaMASAAgH0oIHRpIHOMIHL
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxN
# aWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRT
# UyBFU046MzMwMy0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFNlcnZpY2WgghHtMIIHIDCCBQigAwIBAgITMwAAAiEzwDX70g8hpAABAAAC
# ITANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAe
# Fw0yNjAyMTkxOTM5NTRaFw0yNzA1MTcxOTM5NTRaMIHLMQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmlj
# YSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046MzMwMy0wNUUw
# LUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIi
# MA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDbcTACqU1YvRocyWL2PL9fyf/+
# ULs2qK7U1aZsRnDZSnlCr7K7jgA3eFCEJL5BZ7dUTC0DeZepf+ZC+7HEbB4IdzmJ
# fQAUDFFerqY5VTHmQvP2XA3lWSFj740idcGUHglP5H/PbCJU7GAHWP2HdcCjdx1l
# YAo0A+zLI7xwnTQeMyOXX212Eg4UmDPPJgxdTMw6WFVWsBPWRBi5gDixy2s+7R8A
# Dk5lbBBFDB5h0CjrNWIN7uCAzF5g7trrL8nXIKp10mj9RxhcGQ+tlht6VIvdygRV
# TUGdzFB2/nBvJqQ9kxxFltQST70fEdx4TyaKow/f5+BSh4z4/9f7NXIVVTLn/8kc
# JAfRqFmRrrFt3IKby7VrzmYuoQWD0lmNFtGQ57BrJkPrPFAPek1ALtcbb7FH3nQp
# vi8ngz/MFX/+cnmNFWFU29VVLmzB9XvLZxbYvkeett0mh5lfteeN2rEwUyrdrKuf
# z9h2S6pbate+C2h02CrXwSka0x6ezpTmGkIJLFt25ub/UYXNLdHdsxGD6EfckOIo
# JYsm4MS9F/vSqLNHK89I0vTLBngQEp6LIFkINanRT3PtNx3pNKRKJRALc6L6mhW4
# hL4aHL749qPfQ72t5qAMm5xiKYMgJ2WanidRLNuI251JIN7raaeA/2vb0XFkZcIb
# TR1pfQGsco4U0g5tjwIDAQABo4IBSTCCAUUwHQYDVR0OBBYEFOYjIs5qa6pfuquP
# yyK1FTr5QDCnMB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1Ud
# HwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3Js
# L01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggr
# BgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNv
# bS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIw
# MTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgw
# DgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUAA4ICAQA4I/3bkdnTxD2rFum3
# MF8xVKdEkohAObbePrQ+0fr5bRimjz9sVkKT/7gcj4OMcClSYG+IdX6Mp3EYsLHW
# fjvwfzFoeZE+yTbdBj/1VHZQRuCmw6QqeVCTbw2nnS7nBxnWd9oZXbPUpqEawH5D
# qXQaWFgR9A4KWVK/IvXVDMj1PlPCES1P3JonNbdhkkkz49rJuKOm5b7e/BH8loqA
# mXOXRc22yxWVTMWrEp4pslmv8eT7VoY8X/jdKYTPVEXsfmLbVFcqzMuB8vFGfUyW
# sWROS8wgq7lQYfWcYqh7NymoATX+wWYK3zWG7aRciPGUAzznXdf+aHtIWnQLNa5H
# FmSXkiak3fSuprWYZiHhuYjE16hroApcBHpm+8S/kNqhm9WjQX+2BxnYv+Jejy6l
# qTi8fLBLS069WXVw/ptf5IV+FtYl34GvVoeg31UoUmVVZe1SDUJkm9dDXc8l/qBD
# YiAIT2CCsPTyt9XA9JVuHxdP63n7ChvWAO/47QRuCDsUlFJoWwyBwl7jeYpaRVMt
# Qt0iuJMGGjgEaJX1Q/2j8sXURvTceLHDD9ipWt092ZDWMQciDRmhHNFOX1dnjBvk
# /k1UMcg997j5oYznAnSpJvlg/4BP3aVE0h/YH2KgsKbU4NXZHAjJXj2Slqo1C115
# CG6qBZaFkM8W6vPZCm5qnSezOjCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkA
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
# T3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjMzMDMtMDVFMC1E
# OTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEw
# BwYFKw4DAhoDFQALbEgZZnyYHXJ1DGb5fGjplXptuaCBgzCBgKR+MHwxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29m
# dCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBCwUAAgUA7joP5TAiGA8y
# MDI2MDgyNzAxMjI0NVoYDzIwMjYwODI4MDEyMjQ1WjB3MD0GCisGAQQBhFkKBAEx
# LzAtMAoCBQDuOg/lAgEAMAoCAQACAh2jAgH/MAcCAQACAhMoMAoCBQDuO2FlAgEA
# MDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAI
# AgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBAE4gU+/k2bmPh0bglHshDI5com2z
# CZNCQq/AQpj/SVSt6bjKRzQ1gIplHncHzX+tMrDsPRo9gxDcRtYu8cCvBggqyT8e
# MIZlJ+ctqmNnEHsWle5NZ4wUMSFDBaQONUPAbhzWXb5G2X4UjhgYOWBwBJzRFJZI
# cJoKUFQuBt9AIkpLDRdeKdnBQfNzhHF9FQV6xtmBfcWd1oPc3tcOl5JCPcIYJzx1
# VtOpc9PQTUz5aNj2JvjIz8R9ZdzMVos1T/iA+y7ClTbXgENNgoHdPJh5TXqWm0m8
# UuTGiBksC16QbemHyqDkfj6EXqub03vLSZbsD1yl+k//ZHy/0YFeAO7cfQAxggQN
# MIIECQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQ
# MA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
# MSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAiEz
# wDX70g8hpAABAAACITANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0G
# CyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCDJeV90JHlCaBxPeQFIKJNQ9fRo
# SFG3OgSh8/SlMYhOAjCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EIADvIQef
# FVUa4BJy8IZywMAvmGSKdUVqEmy9A++PCj1EMIGYMIGApH4wfDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgUENBIDIwMTACEzMAAAIhM8A1+9IPIaQAAQAAAiEwIgQgm8nw9j3q
# XjYmLOPid7coFoyn0arM9jVcaXkS4q5zrXAwDQYJKoZIhvcNAQELBQAEggIAdPWt
# VKNl/07Ys7E37usKIfZrZuh5faXhZuoO/m1HdMwbPx4x0K7JT8wUFi7lOwPOmHQq
# 9fjg03nWKvXg2gniT/+E5wRYehv8riJSdZ9X0xvIAlywNI3KgErrOq5eqamWypzi
# 5uOy2iiX+7l5YAFgfDy32q2HvmYYo08QTfus7z08PmopBQLPX9Fmc2YstwBnnLWp
# NyL3MU0N+GkQiaMRxGqlPyTuBaxQAi8Vpg+j6XcOyF4E3FxSKKSK0PrLiqaoqBa9
# zZ84lmt9Gbx87b9YsfftwJLABVmAeT1vOTPA2OCM5jxM7jMVrdfwCromJXaKkrr4
# XFy8qHqH0y9T77/rfz7RD3Ih50XSZnXCqPeR/jlDJdw3lBziiSUitRpkNDyNBxUe
# AHGG2hzUuUXhvj05MeRit0hBntLTOjh8/StlZk0e8FJoJL3gtWNaE63X7VgKF+AL
# sGiHdf+0Khxh/b9WJjDj7kfJBHQiOJ7Qse/VhFjB7YacU8P/+uOKf4CR3Nj0xU/5
# 2KgJnBCxPd8KzfoArB7c872V2P1/+2J+RVsFD6EiZxLx2NOHAtRszZMvVPWXH2Fc
# 7ATs2GIHUyEdsrileG1PF4ZRs3gdQ/Xr/VMgItvOOa1jWP0GHQ1LkeBV1acPuvAs
# qMnCNi3PymUTsIugklh52Nh1LenJIelq10pxtCM=
# SIG # End signature block
