[CmdletBinding(SupportsShouldProcess=$true)]
[cmdletbinding(DefaultParameterSetName='all')]
param(
    [Parameter(Mandatory=$true,Position=0,ParameterSetName = "all")]
    [switch]$all,
    [Parameter(Mandatory=$true,Position=0,ParameterSetName = "cleanup")]
    [switch]$cleanup,
    [Parameter(Mandatory=$true,Position=0,ParameterSetName = "schedule")]
    [switch]$schedule,
    [ValidateSet("\LocalMachine\My","\LocalMachine\WebHosting")]
    [Parameter(Mandatory=$false,ParameterSetName = "all")]
    [Parameter(Mandatory=$false,ParameterSetName = "cleanup")]
    [string]$certStore = "\LocalMachine\My",
    [Parameter(Mandatory=$false,ParameterSetName = "all")]
    [int]$Days = 20,
    [Parameter(Mandatory=$false,ParameterSetName = "all")]
    [int]$MaxNumberOfCerts = 100,
    [Parameter(Mandatory=$false,ParameterSetName = "cleanup")]
    [Parameter(Mandatory=$false,ParameterSetName = "all")]
    [string]$theIssuer = "Let's Encrypt Authority",
    [Parameter(Mandatory=$false,ParameterSetName = "schedule")]
    [string]$User = $($env:UserDomain + "\" + $env:UserName),
    [Parameter(Mandatory=$false,ParameterSetName = "schedule")]
    [string]$TaskTime = "3:30",
    [Parameter(Mandatory=$false,ParameterSetName = "schedule")]
    [string]$TaskDay = "Sunday",
    [Parameter(Mandatory=$false,ParameterSetName = "schedule")]
    [string]$TaskPath = "\",
    [Parameter(Mandatory=$false,ParameterSetName = "schedule")]
    [string]$TaskName = ""
)

Begin{

    #Requires -Version 3.0
    #Requires -RunAsAdministrator
    #Requires -Modules WebAdministration,ACMESharp

    Import-Module WebAdministration
    . ".\update-certificate-http.ps1"

    Function Update-Cert([string]$domain,[string]$site)
    {
        if ($pscmdlet.ShouldProcess($site, "Update certificate for $domain")){
            # wait a little bit
            Start-Sleep -Seconds 1

            # create a unique alias
            [string]$alias = $domain -replace "\.",""
            $alias += (Get-Date).ToString("yyyyMMddhhmmss")    
            Update-Certificate-Http -alias $alias -domain "$domain" -websiteName "$site" -certPath $certStore
        }
    }

    Function UpdateAll()
    {
        $thresholdDate = (Get-Date).AddDays($Days)

        Write-Output "Looking for certificates issues by `'$theIssuer`' expiring before: $($thresholdDate.ToString("dd MMMM yyyy"))"

        # get all SSL bindings
        Get-ChildItem IIS:\SslBindings | Select -First $MaxNumberOfCerts | ForEach-Object {
 
            # we are only looking at ones with a hostname
            if ($_.Host -ne "")
            {             
                # get the name from the xPath, we could do a match regex instead, but this works
                $siteName = (Get-WebBinding -Protocol https -Port 443 -HostHeader $_.Host).ItemXPath      
                $siteName  = $siteName -replace "\/system.applicationHost\/sites\/site\[@name='",""     
                $siteName  = $siteName -replace "' and @id='\d+']",""

                # get the certificate for the binding
                $cert = Get-Item "Cert:$certStore\$($_.Thumbprint)"
      
                if ($cert.Issuer -match "$theIssuer")
                {               
                    [DateTime]$expires = $cert.notAfter

                    if ($expires -lt $thresholdDate)
                    {                
                        Update-Cert -domain "$($_.Host)" -site "$siteName"
                    }   
                }      
            }
        }        
    }

    Function CleanUp-Cert()
    {
        Get-ChildItem -Path Cert:$certStore | ForEach-Object {
            if ($_.Issuer -match "$theIssuer")
            {        
                $myCert = $_;

                $mySubject = $myCert.Subject
                $myThumb = $myCert.Thumbprint
                [DateTime]$myExpiry = $myCert.notAfter

                Write-Verbose "Looking at $mySubject ($($myThumb)) $myExpiry"
                # find one with the same subject but later expiry date
                   Get-ChildItem -Path Cert:$certStore |`
                    Where-Object {$_.Subject -eq $mySubject -and $_.Thumbprint -ne $myThumb } | ForEach-Object {

                        if ($_.Issuer -match "$theIssuer")
                        {   
                            [DateTime]$siblingExpires = $_.notAfter
                            if ($myExpiry -lt $siblingExpires)
                            {
                                Write-Verbose "   Found newer one: $mySubject ($($_.Thumbprint)) $siblingExpires"

                                # check SSL bindings
                                $inUse = Get-ChildItem IIS:\SslBindings | Where {$_.Thumbprint -eq $myThumb}
                                if ($inUse -eq $null)
                                {
                                    if ($pscmdlet.ShouldProcess("$mySubject ($myThumb)","Remove certificate")){
                                        $myCert | Remove-Item -Verbose
                                    }
                                }
                            }
                        }
                    }                                
            }
        }
    }

    Function Schedule-Me()
    {
        if ($TaskPath -notmatch "^\\")
        {
            Write-Warning "TaskPath has to start with a backslash."
            Exit 407
        }
        if ($TaskPath -notmatch "\\$")
        {
            Write-Warning "TaskPath has to end with a backslash."
            Exit 407
        }

        # get the script file currently executing
        $me = Get-Item -Path  $PSCommandPath

        # use the name if not already set
        if ($TaskName -eq "")
        {
            $TaskName = $me.BaseName
        }

        if ((get-scheduledtask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue) -ne $null)
        {
            Write-Warning "The task `'$TaskPath$TaskName`' already exists."
            Exit 408
        }

        # working directory should be the same as the script
        $ScriptDir = $me.Directory
        # add the required parameter
        $scriptName = $me.Name + " -all"

        # get the password for the user
        
        $ph = Read-Host "Please enter the password for: $User" -AsSecureString
        $password = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ph))

        $action = New-ScheduledTaskAction -Execute "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -Argument "-NoProfile -Command `"& {$ScriptDir\$ScriptName; exit `$LastExitCode}`"" -WorkingDirectory "$ScriptDir"
        
        $trigger = New-ScheduledTaskTrigger -Weekly -At "$TaskTime" -DaysOfWeek "$TaskDay"
        $settings = New-ScheduledTaskSettingsSet -Hidden -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -DisallowDemandStart

        if ($pscmdlet.ShouldProcess($scriptName, "Register-ScheduledTask $TaskName")){
            Register-ScheduledTask -TaskName "$TaskName" -TaskPath "$TaskPath" -Trigger $trigger `
                -Action $action -Settings $settings -User "$User" -RunLevel Highest -Password "$password"
        }
    }
}

Process 
{
    if ($all)     {UpdateAll}
    if ($schedule){Schedule-Me}
    if ($cleanup) {CleanUp-Cert}
}

<#
.SYNOPSIS
    Updates all Let's Encrypt certificates for IIS sites that a expiring in the next x days.
.DESCRIPTION
    Loops through all IIS SSL bindings to find certificates issued by Lets Encrypt that
    expire soon and tries to update them.
.PARAMETER all
    Specifies that all matching certificates should be updated.
.PARAMETER cleanup
    Removes all Let's Encrypt certificates that are no longer used in IIS and for each
    another certificate for the same hostname and a later expired date exists.
.PARAMETER certStore
    The certificate store in which your certs are stored
.PARAMETER Days
    Number of days before a certificate expires to be included in the update
.PARAMETER MaxNumberOfCerts
    Max number of certs to review. Set to 1 to update just one at a time. This include certificate that do not qualify.
.PARAMETER theIssuer
    String in the issuer field of the certificate.
.PARAMETER schedule
    Indicates to schedule this script in Windows task scheduler
.PARAMETER User
    The user name to run the task, defaults to the current user
.PARAMETER TaskTime
    The time to start the task
.PARAMETER TaskDay
    The weekday to run the task
.PARAMETER TaskPath
    The path within task scheduler, needs to start and end with a backslash
.PARAMETER TaskName
    The name of the task, defaults to the name of the script
.EXAMPLE
    Update-LECertificate.ps1 -all
    Updates all certificates that expire in the next 20 days
.EXAMPLE
    Update-LECertificate.ps1 -all -days 50
    Updates all certificates that expire in the next 50 days
.EXAMPLE
    Update-LECertificate.ps1 -all -whatif
    Shows all bindings that would be updated with a new certificate
.EXAMPLE
    Update-LECertificate.ps1 -schedule
    Schedules the script to run every Sunday morning at 3:30 am, using the current user
.EXAMPLE
    Update-LECertificate.ps1 -schedule -user joe -TaskName "UpdateCerts" -TaskPath "/adminStuff/" -TaskDay "Monday" -TaskTime "15:20"
    Schedules the script to run every Monday at 3:20 p.m., using user joe with the full name: adminStuff/UpdateCerts
.EXAMPLE
    Update-LECertificate.ps1 -cleanup -whatif
    Shows all certificates that would be removed when not using -whatif
.NOTES
    Tested on Windows Server 2012 R2
    Author:  Peter Hahndorf
    Created: September 21st, 2016
    Requires: AcmeSharp PowerShell Module, update-certificate-http.ps1 in the same directory, WebAdministration PowerShell Module    
.LINK
    https://peter.hahndorf.eu/blog/letsencryptoniis.html
    https://github.com/hahndorf/hacops
#>
