[CmdletBinding(SupportsShouldProcess=$false)]
param
(
    [parameter(Mandatory=$true)]
    [string]$CollectionExportFile,
    [string]$TargetPath = "E:\news\http"
)

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

    Write-host $fileName -ForegroundColor DarkCyan
    $content
}