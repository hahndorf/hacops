[CmdletBinding(SupportsShouldProcess=$true)]
param
(
    [parameter(Mandatory=$true,Position=0)]
    [string]$Path,
    [parameter(Mandatory=$false)]
    [string]$OutputPath
)

if (-not(Test-Path -Path "$Path"))
{
    Write-Warning "`'CollectionExportFile`' does not exist"
    Exit 4041
}

if ([string]::IsNullOrEmpty($OutputPath))
{
    $FileInfo = Get-Item -Path $Path

    $OutputPath = $fileInfo.Directory.FullName
}

if (-not(Test-Path -Path "$OutputPath"))
{
    Write-Warning "`'TargetPath`' does not exist"
    Exit 4042
}

$Script:variables = New-Object System.Collections.Generic.HashSet[string]

Function Add-Variable([string]$text)
{

    $text | Select-String -Pattern "{{[-_a-z0-1]+}}" -AllMatches | ForEach-Object {

        $key = $_.Matches.Value -replace "[{}]"
       
        $Script:variables.Add($key) | Out-Null
    }
}

Function Save-OneItem($item,[string]$Parent)
{

    $content = "// imported from Postman`r`n"
    $content += "//       Collection-Name: $CollectionName`r`n"
    
    if (-not ([string]::IsNullOrEmpty($Parent)))
    {
        $parentPath = Join-Path -Path $CollectionPath -ChildPath $Parent
        
        $content += "//                Parent: $Parent`r`n"
        
        if (-not(Test-Path -Path $parentPath))
        {
            New-Item -ItemType Directory -Path $parentPath | Out-Null
        }
    }
    else {
        $parentPath = $CollectionPath
    }
    
    $fileName =  $item.Name;
    
    $content += "//          Request-Name: $fileName`r`n//`r`n"

    $fileName = $fileName -Replace "\.","_"
    $fileName = $fileName -Replace "\/","_"
    $fileName = $fileName -Replace ":","_"
    $fileName = $fileName -Replace "=","_"
    $fileName = $fileName -Replace "\?","_"
    $fileName += "_$ItemCount"
    $fileName += ".http"
    $fileName = Join-Path -Path $parentPath -ChildPath $fileName

    $EnvfileName = Join-Path -Path $parentPath -ChildPath $fileName

    Add-Variable -text $item.request.url.raw

    $content += "$($item.request.method) $($item.request.url.raw)`r`n"

    $item.request.header | ForEach-Object {

        if ($_.disabled -eq "true")
        {
            $content += "// "
        }

        Add-Variable -text $_.value
        $content += $_.key + ":" + $_.value + "`r`n"
    }

    if ($item.request.body -ne $null)
    {
        if ($item.request.body.mode -eq "raw")
        {
            Add-Variable -text $item.request.body.raw
            if ($item.request.body.options.raw.language -eq "json")
            {
                $content +="content-type: application/json`r`n`r`n"
                $content += $item.request.body.raw
            }
            else {
                # assume XML, it doesn't say anywhere
                $content +="content-type: text/xml`r`n`r`n"
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
                    Add-Variable -text $_.value
                }
                $keyCount++
            }
        }
        elseif ($item.request.body.mode -eq "formdata")
        {
            [string]$guid = (New-Guid).Guid -replace "-",""
            [string]$boundary = "----WebKitFormBoundary$guid"

            $content +="content-type: multipart/form-data; boundary=$boundary`r`n`r`n"
            
            [int]$keyCount = 0
            $item.request.body.formdata | ForEach-Object {

                if ($_.disabled -ne "true")
                {
                    
                    if ($_.type -eq "text")
                    {
                        $content += "--$boundary`r`n"
                        $content += "Content-Disposition: form-data; name=`"text`"`r`n"
                        $content += "`r`n"
                        $content += "$($_.key)=$($_.value)`r`n"
                        Add-Variable -text $_.value
                    }
                    elseif ($_.type -eq "file")
                    {
                        $file = $_.src
                        Add-Variable -text $file
                        
                        $attachmentfileName = Split-Path -Path $file -Leaf

                        

                        $mimeType = "text/plain"

                        if ($file -match "png")
                        {
                            $mimeType = "image/png"
                        }
                        if ($file -match "jpeg|jpg")
                        {
                            $mimeType = "image/jpeg"
                        }

                        
                        $content += "--$boundary`r`n"
                        $content += "Content-Disposition: form-data; name=`"$($_.key)`"; filename=`"$($attachmentfileName)`"`r`n"
                        $content += "Content-Type: $mimeType`r`n"
                        $content += "`r`n"
                        
                        $content += "< $file`r`n"
                    } 
                }
                $keyCount++
            }
            $content += "--$($boundary)--`r`n"
        }
    }

    $content = $content -replace "{{","{{`$dotenv "

    if ($PSCmdlet.ShouldProcess($fileName,"Create file"))
    {
        $content | Set-content -Path "$fileName" -Encoding UTF8
    }

    Write-Verbose $fileName

}

$data = Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json

$CollectionName = $data.Info.Name

$CollectionPath = Join-Path -Path $OutputPath -ChildPath $CollectionName

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

# Write into .env File
[string]$envContent = ""
$Script:variables | ForEach-Object {
    $envContent += "$_=`r`n"
}

$dotEnvFile = Join-Path -Path $CollectionPath -ChildPath ".env"

$envContent | Set-content -Path "$dotEnvFile" -Encoding UTF8

Write-Output "Created $ItemCount files under `'$CollectionPath`'"



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
   ConvertFrom-PostmanCollection.ps1 -Path C:\PostmanExport\postman-collection-export.json
   Converts the ExportFile and saves the http files in the same directory in a subfolder with the name of the collection

   .EXAMPLE
   ConvertFrom-PostmanCollection.ps1 -Path C:\PostmanExport\postman-collection-export.json -OutputPath $($env:USERPROFILE)\httpFiles
   Converts the export file and saves the http files in the specified TargetPath

   .EXAMPLE
   Get-ChildItem C:\PostmanExport -Filter "*.json" -File | Foreach-Object { ConvertFrom-PostmanCollection.ps1 -Path $_.FullName }
   Until we support piping a collection of files, use this to convert a directory full of files.
  
.NOTES
    Author:  Peter Hahndorf
    Created: August 28th, 2023
.LINK
    https://hahndorf.eu
    https://github.com/hahndorf/hacops

#>