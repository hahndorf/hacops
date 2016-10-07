[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [switch]$uac,
    [switch]$services,
    [switch]$shell,
    [switch]$features,
    [switch]$uacon,
    [switch]$removeDesktop,
    [ValidateSet("powershell","cmd","explorer")]
    [string]$ShellExecutable = "powershell"
)

# Work in Process

Begin{

    #Requires -Version 5.0
    #Requires -RunAsAdministrator
  
    [string[]] $FeatureNames = "Internet-Explorer-Optional-amd64","MediaPlayback","Microsoft-Windows-Printing-PrintToPDFServices-Package",`
"Microsoft-Windows-Printing-XPSServices-Package","Windows-Defender-Gui","MicrosoftWindowsPowerShellISE","Windows-Defender-Gui","SearchEngine-Client-Package"

    Function DisableService([string]$name)
    {
        Set-Service -Name $name -StartupType Disabled -Verbose
        Stop-Service -Name $name -Verbose
    }
    
    Function DisableServices()
    {
        # [string[]] $names = "AppInfo","BrokerInfrastructure","CDPSvc","CDPUserSvc_21e34","KeyIso","lfsvc","LicenseManager","NcbService","OneSyncSvc_21e34","PcaSvc","ShellHWDetection","StorSvc","Themes","tiledatamodelsvc","TrkWks","VaultSvc","Wcmsvc","WpnService","wudfsvc"

        [string[]] $names = "CDPSvc","CDPUserSvc_21e34","lfsvc","OneSyncSvc_21e34","PcaSvc","Themes"

        Foreach ($name in $names)
        {
           DisableService -name $name 
        }
    }

    Function SetShell()
    {
        Set-ItemProperty -path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -name shell -value "$ShellExecutable.exe" -Verbose
    }

    Function SetUAC([int]$value)
    {    
        Set-ItemProperty -path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -name EnableLUA -value $value -Verbose
        Write-Output "Reboot the server"
    }     
    
    Function RemoveFeature()
    {
        Foreach ($name in $FeatureNames)
        {
            if ($pscmdlet.ShouldProcess($name, "Disable-WindowsOptionalFeature")){
                 Disable-WindowsOptionalFeature -Online -FeatureName $name -NoRestart
            }           
        }      
        Get-WindowsOptionalFeature -Online | Where {$_.FeatureName -and $_.State -eq "Enabled"}  | Sort-Object FeatureName | Format-Table FeatureName
        Write-Output "`r`n==== Please reboot ===="

        # Server-Gui-Mgmt, 
        # Server-Shell did not work
    } 

    Function RebootServer()
    {
        if ($pscmdlet.ShouldProcess($env:COMPUTERNAME, "Reboot computer")){
            $message = "A reboot of the server is required, reboot now"
            $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Restart now."

            $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Dont' reboot now"

            $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)

            if ($host.ui.PromptForChoice("", $message, $options, 0) -eq 0)
            {
                Restart-Computer
            }
        }
    }
}

Process 
{
    if ($services) {DisableServices}
    if ($shell) {SetShell}
    if ($uac) {SetUAC -value 0}
    if ($uacon) {SetUAC -value 1}
    if ($features) {RemoveFeature}

    if ($removeDesktop)
    {
        DisableServices
        SetShell
        RemoveFeature
        SetUAC -value 0
    }

    RebootServer
      
    #  review C:\Windows\SystemApps
}

<#
.SYNOPSIS
    Changes Windows Server 2016 Full Installation to behave more like Server Core Installation
.DESCRIPTION
    In Server 2016 you can no longer move between a core, Min-Shell and full-shell, this
    script removes some features from the full install to make it more like Min-Shell in 2012 R2
.PARAMETER uac
    Turns off UAC, similar to core where it doesn't work at all.
.PARAMETER uacon
    Turns on UAC
.PARAMETER services
    Stopps and disables some services
.PARAMETER shell
    Changes the shell from Explorer to PowerShell or cmd
.PARAMETER features
    Removes a bunch of optional Windows components
.PARAMETER removeDesktop
    same as -services -features -uac -shell
    
.PARAMETER ShellExecutable
    Name of the executeable without .exe
.EXAMPLE
   Disable-ServerDesktop.ps1 -removeDesktop -whatif
   Shows what it would do
.NOTES
    Tested on Windows Server 2016
    Author:  Peter Hahndorf
    Created: October 4th, 2016   
.LINK
    https://peter.hahndorf.eu
    https://github.com/hahndorf/hacops
#>