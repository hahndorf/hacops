[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$true,Position=0,ParameterSetName = "all")]
    [switch]$all,
    [ValidateSet("\LocalMachine\My","\LocalMachine\WebHosting")]
    [string]$certStore = "\LocalMachine\My",
    [int]$Days = 20,
    [int]$MaxNumberOfCerts = 100,
    [string]$theIssuer = "Let's Encrypt Authority"
)

Begin{

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
}

Process 
{
    if ($all)
    {
        UpdateAll
    }
}

<#
.SYNOPSIS
    Updates all Let's Encrypt certificates for IIS sites that a expiring in the next x days.
.DESCRIPTION
    Loops through all IIS SSL bindings to find certificates issued by Lets Encrypt that
    expire soon and tries to update them.
.PARAMETER all
    Specifies that all matching certificates should be updated.
.PARAMETER certStore
    The certificate store in which your certs are stored
.PARAMETER Days
    Number of days before a certificate expires to be included in the update
.PARAMETER MaxNumberOfCerts
    Max number of certs to update. Set to 1 to update just one at a time.
.PARAMETER theIssuer
    String in the issuer field of the certificate.
.EXAMPLE
    Update-LECertificate.ps1 -all
    Updates all certificates that expire in the next 20 days
.EXAMPLE
    Update-LECertificate.ps1 -all -days 50
    Updates all certificates that expire in the next 50 days
.EXAMPLE
    Update-LECertificate.ps1 -all -whatif
    Shows all bindings that would be updated with a new certificate
.NOTES
    Tested on Windows Server 2012 R2
    Author:  Peter Hahndorf
    Created: September 21st, 2016
    Requires: AcmeSharp PowerShell Module, update-certificate-http.ps1 in the same directory, WebAdministration PowerShell Module    
.LINK
    https://peter.hahndorf.eu/blog/letsencryptoniis.html
    https://github.com/hahndorf/hacops
#>
