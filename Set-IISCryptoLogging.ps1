[CmdletBinding(SupportsShouldProcess=$true)]
param (
    [Parameter(Mandatory=$true,Position=0,ParameterSetName = "site")]
    [string]$WebSite,
    [Parameter(Mandatory=$true,Position=0,ParameterSetName = "server")]
    [switch]$Server
)

Begin
{

    [string]$path = 'MACHINE/WEBROOT/APPHOST'

    Function GetLogFields( [string]$site){

      # shows the current settings

      if ($site -eq "")
      {
        [string]$filter = "system.applicationHost/sites/siteDefaults/logFile/customFields"
      }
      else {
        [string]$filter = "system.applicationHost/sites/site[@name='" + $site + "']/logFile/customFields"
      }

      Write-Output ""
      Write-Output "Data for: '$filter':"

      (Get-WebConfigurationProperty -pspath "$path" -filter "$filter" -name ".").Collection | Format-Table -Property logFieldName,sourceName,sourceType

    }

    Function AddNewField 
    {
      [CmdletBinding(SupportsShouldProcess=$true)]
      param(
        [string]$site,
        [string]$fieldName,
        [string]$source
      )
      
        [string]$target = "WebSite '$site'"

        if ($site -eq "")
        {
          $target = "Server"
          [string]$filter = "system.applicationHost/sites/siteDefaults/logFile/customFields"
        }
        else {
          [string]$filter = "system.applicationHost/sites/site[@name='" + $site + "']/logFile/customFields"
        }

        $value = @{}
        $value.logFieldName = $fieldName;
        $value.sourceName = $source
        $value.sourceType = "ServerVariable"

        $count = ((Get-WebConfigurationProperty -pspath "$path" -filter "$filter" -name ".").Collection | Where-Object logFieldName -eq $fieldName).count
        if ($count -eq 0)
        {
          if ($PSCmdlet.ShouldProcess($target,"adding custom log field '$fieldName'")) {
            Add-WebConfigurationProperty -pspath "$path" -filter "$filter" -name "." -value $value
            Write-Output "Added '$filter - $fieldName'"
          }
        }
        else {
          Write-OutPut "'$filter - $fieldName' already exists"
        }
    }

    Function AddNewFields([string]$siteName)
    {
        Write-Output ""
        AddNewField -site $siteName -fieldName "crypt-protocol"    -source "CRYPT_PROTOCOL"
        AddNewField -site $siteName -fieldName "crypt-cipher"      -source "CRYPT_CIPHER_ALG_ID"
        AddNewField -site $siteName -fieldName "crypt-hash"        -source "CRYPT_HASH_ALG_ID"
        AddNewField -site $siteName -fieldName "crypt-keyexchange" -source "CRYPT_KEYEXCHANGE_ALG_ID"
    }
}

Process{

     if ($Server)
     {
          Write-Output "Changing Server level configuration"
          AddNewFields -siteName ""
          GetLogFields -site ""
     }
     elseif ($WebSite -ne "")
     {
        $site = Get-Website -name $WebSite
        if ($null -ne $site)
        {
            Write-Output "Found WebSite: '$($site.Name)'"
            AddNewFields -siteName "$($site.Name)"
            GetLogFields -site $($site.Name)
        }
        else {
          Write-Warning "Site '$WebSite' not found"
        }
     }
}

<#
.SYNOPSIS
   Adds custom log fields to IIS Web Server

   .DESCRIPTION
   To see what TLS connection settings users are using when visiting your site
   newer IIS can log four additional fields in the http logs.
   This scripts adds these settings.

   .PARAMETER WebSite
    The name of the web site to add the settings to
   .PARAMETER Server
    To add the settings to the server level

   .EXAMPLE
   Set-IISCryptoLogging.ps1 -WebSite "Default Web Site"

   Add the settings for the default web site

   .EXAMPLE
   Invoke-SQL.ps1 -server -whatif

   Add the settings for the whole server, but just show what would be done

   .LINK
   https://www.microsoft.com/security/blog/2017/09/07/new-iis-functionality-to-help-identify-weak-tls-usage/

   .LINK
   https://github.com/hahndorf/hacops

   .NOTES
    Author:  Peter Hahndorf
    Created: November 14th, 2019

#>