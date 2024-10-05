# HacoPs
Hahndorf's awesome collection of PowerShell scripts. 

Just a a bunch of random PowerShell scripts I wrote over time.

Nothing fancy here.

## Update-LECertificate.ps1

Meta script which uses some other PowerShell scripts and modules to update all Let's Encrypt certificates on a Windows Server.

## Set-NetworkProfileCategory.ps1

 In 'Network and Sharing Center' your networks are shown as 'Public', "Private' or 'Domain'
    You can change that with this script in all supported versions of Windows.
    

## New-DemoFtpSite.ps1

Shows how to set up IIS with a FTP site that uses IIS Manager Users
and a special account to run the FTP service.

## Invoke-SQL.ps1

Single file script to run a SQL command against a SQL Server

## Set-PathVariable.ps1

Correct way to add to the path environment variable on Windows systems. <a href="https://peter.hahndorf.eu/blog/AddingToPathVariable.html">Blog post</a>

## Disable-ServerDesktop.ps1

Changes Windows Server 2016 Full Installation to behave more like Server Core Installation

## Import-StackExchangeData.ps1

Imports Stack Exchange questions and answers from GDPR export into a SQL-Server database.

## Get-SysMonStats.ps1

Showing stats for Sysinternals Sysmon data <a href="https://peter.hahndorf.eu/blog/Some-stats-based-on-the-Sysint.html">Blog post</a>

## ConvertFrom-PostmanCollection.ps1

Takes an exported Postman collection Json file and converts the requests to RFC 2616 http files. This can help you during your migration from Postman to tools like VS Code REST Client.

## Set-Password.ps1

Changes the password of a local user.

This is different from 

```cmd
net user username password
```

that resets the password and potentially destroys data