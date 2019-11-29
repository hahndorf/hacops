param(
    [parameter(Mandatory=$False)]
    [string]$Source = "E:\news\stack"
)

Begin{

$insertSql = @"
INSERT INTO [dbo].[PostImport]
           ([Site]
           ,[PostType]
           ,[PostId]
           ,[RevisionGUID]
           ,[CreationDate]
           ,[IpAddress]
           ,[TheText])

 SELECT '{siteName}' as siteName, post.*
 FROM OPENROWSET (BULK '{fileName}', SINGLE_CLOB) as j
 CROSS APPLY OPENJSON(BulkColumn)
 WITH( [type] nvarchar(20), postId int, revisionGUID nvarchar(100), creationDate DateTime,
 ipAddress nvarchar(50),  text nvarchar(max)) AS post
"@

}

Process
{
    $qaDir = Join-Path $Source -ChildPath "qa"

    $files = Get-ChildItem -path "$qaDir" -Directory | Where-Object Name -ne "Global"
    
    $files | Select-Object -First 3 | ForEach-Object{

        $postHistory = Join-Path $_.FullName -ChildPath "PostHistory.json"

        if (Test-Path -Path $postHistory)
        {            
            $sql = $insertSql -replace "{siteName}",$_.Name
            $sql = $sql -replace "{fileName}",$postHistory
            
            $sql
        }
        else {
            Write-Output "$postHistory not found"
        }

    }
}