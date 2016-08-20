param(
    [Parameter(Mandatory=$true,Position=0,ParameterSetName = "PrepareServer")]
    [switch]$PrepareServer,
    [Parameter(Mandatory=$true,Position=0,ParameterSetName = "user")]
    [Parameter(Mandatory=$true,Position=0,ParameterSetName = "Site")]
    [string]$siteName,
    [Parameter(Mandatory=$false,Position=0,ParameterSetName = "Site")]
    [string]$siteRoot,
    [Parameter(Mandatory=$true,Position=0,ParameterSetName = "Site")]
    [ValidateSet("Modify","Read")]
    [string]$siteaccess,
    [Parameter(Mandatory=$true,Position=0,ParameterSetName = "user")]
    [string]$username,
    [Parameter(Mandatory=$true,Position=0,ParameterSetName = "user")]
    [string]$userpassword,
    [Parameter(Mandatory=$true,Position=0,ParameterSetName = "user")]
    [ValidateSet("Read,Write","Read")]
    [string]$useraccess
)

Begin
{
    [string]$FTPIdenityName = "FTPServiceAccount"

    Function Test-RegistryValue([String]$Path,[String]$Name){

      if (!(Test-Path $Path)) { return $false }
   
      $Key = Get-Item -LiteralPath $Path
      if ($Key.GetValue($Name, $null) -ne $null) {
          return $true
      } else {
          return $false
      }
    }

    Function Add-RegistryDWord([String]$Path,[String]$Name,[int32]$value){

        If (Test-RegistryValue $Path $Name)
        {
            Set-ItemProperty -Path $Path -Name $Name –Value $value
        }
        else
        {
            New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value $value 
        }
    }

    Function SetUpFeatures
    {       
         # enable FTP server, this will also install other IIS components
         Enable-WindowsOptionalFeature -Online -FeatureName IIS-FTPServer -All
         # we need PowerShell scripting for later tasks
         Enable-WindowsOptionalFeature -Online -FeatureName IIS-ManagementScriptingTools
         # for IIS Manager users, we need the IIS-ManagementService
         Enable-WindowsOptionalFeature -Online -FeatureName IIS-ManagementService -All
         # To change the identity of the FTP COM+ application we need this feature
         Enable-WindowsOptionalFeature -Online -FeatureName IIS-FTPExtensibility
         
         # show what we have now
         (Get-WindowsOptionalFeature –Online | Where {$_.FeatureName -match "^IIS-" -and $_.State -eq "Enabled"} | Sort FeatureName | Format-Table -Property FeatureName -HideTableHeaders | Out-String).Trim()
    }

    Function SetComPlusIdenity()
    {
        # by default the FTP service runs under NetworkService, it is better pratice to have it run 
        # under a specific account, we create one here and set it to be used by the service

        $Assembly = Add-Type -AssemblyName System.Web
        # generate a ramdom password
        # 14 chars is max for net user, fix?
        $password = [System.Web.Security.Membership]::GeneratePassword(14,2)

        # create a user, should only be in guests, that's enough
        & net user $FTPIdenityName $password /ADD /ACTIVE:YES /FULLNAME:"FTP Service Account" /EXPIRES:NEVER /Comment:"Account for running FTP Service COM+ application" /PASSWORDCHG:NO
        # in my tests the password never expired for this user, but better to check
        & net localgroup guests $FTPIdenityName /ADD 
        & net localgroup users $FTPIdenityName /DELETE 

        # now set the Identity for the FTP COM+ application
        $comAdmin = New-Object -comobject COMAdmin.COMAdminCatalog
        $apps = $comAdmin.GetCollection(“Applications”)
        $apps.Populate();

        # maybe this has a different name on non-English Windows 
        $ftpExApp = $apps | Where-Object {$_.Name -eq "Microsoft FTP Publishing Service Extensibility Host"}

        $ftpExApp.Value("Identity") ="$env:computername\$FTPIdenityName"
        $ftpExApp.Value("Password") = $password
        
        $saveChangesResult = $apps.SaveChanges()
        $saveChangesResult
    }

    Function SetFilePermission([string]$file,[string]$Right)
    {
        $Principal = $env:COMPUTERNAME + "\" + $FTPIdenityName
        Write-Output "Set permissions for $Principal on $file"
        $rule=new-object System.Security.AccessControl.FileSystemAccessRule ($Principal,$Right,"Allow") 
        $acl=get-acl $file
  
        #Add this access rule to the ACL 
        $acl.SetAccessRule($rule) 
   
        #Write the changes to the object 
        set-acl -Path $file -AclObject $acl
    }

    Function ConfigureServer()
    {
        Stop-Service -Name "wmSvc"
        Add-RegistryDWord -Path "HKLM:\SOFTWARE\Microsoft\WebManagement\Server" -Name RequiresWindowsCredentials -value 0
        Start-Service -Name "wmSvc"

        SetComPlusIdenity

        SetFilePermission -file "$env:SystemRoot\System32\inetsrv\config" -Right "Read"
        SetFilePermission -file "$env:SystemRoot\System32\inetsrv\config\administration.config" -Right "Read"
        SetFilePermission -file "$env:SystemRoot\System32\inetsrv\config\redirection.config" -Right "Read"
    }

    Function ConfigureSite
    {
        New-WebFtpSite -Name "$siteName" -Port 21 -PhysicalPath "$siteRoot"
        Add-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST'  -filter "system.applicationHost/sites/site[@name=`'$siteName`']/ftpServer/security/authentication/customAuthentication/providers" -name "." -value @{name='IisManagerAuth'}
        SetFilePermission -file "$siteRoot" -Right "$siteaccess" 
        
        # allow non-TLS, this is just okay for testing, never use plain text FTP
        Set-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST'  -filter "system.applicationHost/sites/site[@name='$siteName']/ftpServer/security/ssl" -name "controlChannelPolicy" -value "SslAllow"
        Set-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST'  -filter "system.applicationHost/sites/site[@name='$siteName']/ftpServer/security/ssl" -name "dataChannelPolicy" -value "SslAllow"                                                          
    }

    Function ConfigureUser()
    {
        # TODO: currently this throws errors if the user already exists in the system or in the site

        [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.Web.Management")  | Out-Null
        [Microsoft.Web.Management.Server.ManagementAuthentication]::CreateUser($username, $userpassword)        
        [Microsoft.Web.Management.Server.ManagementAuthorization]::Grant($username, $siteName, $FALSE)
        Add-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST' -location "$siteName" -filter "system.ftpServer/security/authorization" -name "." -value @{accessType='Allow';users="$username";permissions="$useraccess"}        
    }
}

Process 
{
    if ($PrepareServer)
    {
    #    SetupFeatures
        ConfigureServer
    }

    if ($siteName -ne "" -and $siteaccess -ne "")
    {
        ConfigureSite
    }

    if ($username -ne "")
    {
        ConfigureUser
    }
}

<#
.SYNOPSIS
    Set ups a IIS FTP server which uses IIS Manager users
.DESCRIPTION
    Perform three steps, configure server, site and user
    This is just a demo on how to do certain things, not intended for production use.
.EXAMPLE       
    New-DemoFtpSite.ps1 -PrepareServer
    Installs Windows IIS components and configures IIS to allow IIS Manager users
    Also runs the FTP service under a new user account
.EXAMPLE       
    New-DemoFtpSite.ps1 -siteName TestFTPSite -siteRoot "C:\ftproot" -SiteAccess "Modify"
    Creates a new FTP site and allows IIS Manager users 
.EXAMPLE       
    New-DemoFtpSite.ps1 -siteName TestFTPSite -user "susan" -userpassword "*******" -userAccess "Read"
    Adds a IIS manager user and allows access to the ftp site.
.NOTES
    Tested on Windows Server 2012 R2
    Author:  Peter Hahndorf
    Created: August 20th, 2016    
.LINK
    https://github.com/hahndorf/ 
#>
