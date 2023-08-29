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

Function Save-OneItem($item,[string]$Parent)
{

    $content = "// imported from Postman: $CollectionName"

    if (-not ([string]::IsNullOrEmpty($Parent)))
    {
        $parentPath = Join-Path -Path $CollectionPath -ChildPath $Parent

        $content += " - $Parent"

        if (-not(Test-Path -Path $parentPath))
        {
            New-Item -ItemType Directory -Path $parentPath | Out-Null
        }
    }
    else {
        $parentPath = $CollectionPath
    }

    $fileName =  $item.Name;

    $content += " - $fileName`r`n"

    $fileName = $fileName -Replace "\.","_"
    $fileName += ".http"
    $fileName = Join-Path -Path $parentPath -ChildPath $fileName

    $content += "$($item.request.method) $($item.request.url.raw)`r`n"

    $item.request.header | ForEach-Object {

        if ($_.disabled -eq "true")
        {
            $content += "// "
        }

        $content += $_.key + "=" + $_.value + "`r`n"
    }

    if ($item.request.body -ne $null)
    {
        if ($item.request.body.mode -eq "raw")
        {
            if ($item.request.body.options.raw.language -eq "json")
            {
                $content +="content-type: application/json`r`n`r`n"
                $content += $item.request.body.raw
            }
        }
        elseif ($item.request.body.mode -eq "urlencoded")
        {
            $content +="content-type: application/x-www-form-urlencoded`r`n`r`n"
            [int]$keyCount = 0
            $item.request.body.urlencoded | ForEach-Object {

                if ($_.disabled -ne "true")
                {
                    if ($keyCount -ne 0)
                    {
                        $content += "&"
                    }
                    
                    $content += "$($_.key)=$($_.value)`r`n"
                }
                $keyCount++
            }
        }
    }

   $content | Set-content -Path $fileName -Encoding UTF8

    Write-Verbose $fileName
}

$data = Get-Content -Path $CollectionExportFile -Raw -Encoding UTF8 | ConvertFrom-Json

$CollectionName = $data.Info.Name

$CollectionPath = Join-Path -Path $TargetPath -ChildPath $CollectionName

if (-not(Test-Path -Path $CollectionPath))
{
    New-Item -ItemType Directory -Path $CollectionPath | Out-Null
}

[int]$ItemCount = 0

$data.item | ForEach-Object {

    # create one file for each item
    
    if ($_.item -eq $null)
    {
        # is single request
        Save-OneItem -Item $_ -Parent ""
        $ItemCount++
    }
    else {
        # is container
        $containerName = $_.Name
        $_.item | ForEach-Object {
            Save-OneItem -Item $_ -Parent $containerName
            $ItemCount++
        }
    }
}

Write-Output "Created $ItemCount files under `'$TargetPath`'"

<# 
   .SYNOPSIS
   Takes and Export from a Postman collection and creates RFC 2616 http files
   
   .DESCRIPTION
    Very early version, just raw JSON supported, not authentication schemes

   .PARAMETER -CollectionExportFile
    The path to the file to convert
   
   .PARAMETER -TargetPath
    The directory to save the new http files to.

   .EXAMPLE
   ConvertFrom-PostmanCollection.ps1 -CollectionExportFile C:\postman-collection-export.json -TargetPath $($env:USERPROFILE)\httpFiles
  
.NOTES
    Author:  Peter Hahndorf
    Created: August 28th, 2023
.LINK
    https://hahndorf.eu
    https://github.com/hahndorf/hacops

#>