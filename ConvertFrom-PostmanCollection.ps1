[CmdletBinding(SupportsShouldProcess=$false)]
param
(
    [parameter(Mandatory=$true)]
    [string]$CollectionExportFile,
    [parameter(Mandatory=$true)]
    [string]$TargetPath
)

if (-not(Test-Path -Path "$CollectionExportFile"))
{
    Write-Warning "`'CollectionExportFile`' does not exist"
    Exit 4041
}

if (-not(Test-Path -Path "$TargetPath"))
{
    Write-Warning "`'TargetPath`' does not exist"
    Exit 4042
}

$data = Get-Content -Path $CollectionExportFile -Raw | ConvertFrom-Json

$CollectionName = $data.Info.Name

# $CollectionName 

$data.item | ForEach-Object {

    # create one file for each item

    $fileName = $CollectionName + "_" + $_.Name;
    $fileName = $fileName -Replace "\.","_"
    $fileName += ".http"
    $fileName = Join-Path -Path $TargetPath -ChildPath $fileName

    $content = "$($_.request.method) $($_.request.url.raw)`r`n"

    $_.request.header | ForEach-Object {

        if ($_.disabled -eq "true")
        {
            $content += "// "
        }

        $content += $_.key + "=" + $_.value + "`r`n"
    }

    if ($_.request.body -ne $null)
    {
        if ($_.request.body.mode -eq "raw")
        {
            if ($_.request.body.options.raw.language -eq "json")
            {
                $content +="content-type: application/json`r`n`r`n"
                $content += $_.request.body.raw
            }
        }
    }

    $content | Set-content -Path $fileName -Encoding UTF8

 #   Write-host $fileName -ForegroundColor DarkCyan
 #   $content
}

<# 
   .SYNOPSIS
   Takes and Export from a Postman collection and creates RFC 2616 http files
   
   .DESCRIPTION

   .PARAMETER -CollectionExportFile
    The path to the file to convert
   
   .PARAMETER -TargetPath
    The directory to save the new http files to.

   .EXAMPLE
   ConvertFrom-PostmanCollection.ps1 -CollectionExportFile C:\postman-collection-export.json -TargetPath $($env:USERPROFILE)\httpFiles
  
.NOTES
    Very early version
    Author:  Peter Hahndorf
    Created: August 28th, 2023
.LINK
    https://hahndorf.eu
    https://github.com/hahndorf/hacops

#>