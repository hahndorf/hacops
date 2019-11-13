param (
    [Parameter(Mandatory=$true,Position=0,ParameterSetName = "site")]
    [string]$siteName,
    [Parameter(Mandatory=$true,Position=0,ParameterSetName = "server")]
    [switch]$server
)

Begin
{
    Function AddNewField ([string]$site,[string]$fieldName,[string]$source)
    {
        [string]$path = 'MACHINE/WEBROOT/APPHOST'

        if ($site -eq "")
        {
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
          Add-WebConfigurationProperty -pspath "$path" -filter "$filter" -name "." -value $value
          Write-Output "Added '$filter - $fieldName'"
        }
        else {
          Write-OutPut "'$filter - $fieldName' already exists"
        }
    }

    Function AddNewFields([string]$siteName)
    {
        AddNewField -site $siteName -fieldName "crypt-protocol"    -source "CRYPT_PROTOCOL"
        AddNewField -site $siteName -fieldName "crypt-cipher"      -source "CRYPT_CIPHER_ALG_ID"
        AddNewField -site $siteName -fieldName "crypt-hash"        -source "CRYPT_HASH_ALG_ID"
        AddNewField -site $siteName -fieldName "crypt-keyexchange" -source "CRYPT_KEYEXCHANGE_ALG_ID"
    }
}

Process{

     if ($server)
     {
          Write-Output "Changing Server level configuration'"
          AddNewFields -siteName ""
     }
     elseif ($siteName -ne "")
     {
        $site = Get-Website -name $siteName
        if ($null -ne $site)
        {
            Write-Output "Found site: '$($site.Name)'"
            AddNewFields -siteName "$($site.Name)"
        }
        else {
          Write-Warning "Site '$siteName' not found"
        }
     }
}