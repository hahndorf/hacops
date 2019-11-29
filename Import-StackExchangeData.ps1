[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true,ParameterSetName="Import")]
    [switch]$Import,
    [parameter(Mandatory=$true,ParameterSetName="Import")]
    [string]$Source,
    [parameter(Mandatory=$true,ParameterSetName="Setup")]
    [switch]$Setup,
    [string]$ConnectionString = "Server=.;Database=lab;Integrated Security=True;"
)

Begin{

# Script to import Stack Exchange Questions and answers into a SQL-Server database
# using the files from the Stack Exchange GDPR Export zip 
# not done yet

$insertSql = @"
INSERT INTO stack.PostImport
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

$setupSQL = @"

CREATE SCHEMA [stack] AUTHORIZATION [dbo];

CREATE TABLE [stack].[Questions](
	[Id] [int] IDENTITY(1,1) NOT NULL,
	[Site] [varchar](100) NOT NULL,
	[PostId] [int] NOT NULL,
    [CreationDate] [datetime] NOT NULL,
	[Title] [nvarchar](500) NULL,
	[Tags] [nvarchar](500) NULL,
	[Body] [nvarchar](max) NULL,
 CONSTRAINT [PK_Questions] PRIMARY KEY CLUSTERED ([Id] ASC));

 CREATE TABLE stack.PostImport(
	[Id] [int] IDENTITY(1,1) NOT NULL,
	[Site] [varchar](100) NOT NULL,
	[PostType] [varchar](50) NOT NULL,
	[PostId] [int] NOT NULL,
	[RevisionGUID] [varchar](100) NOT NULL,
	[CreationDate] [datetime] NOT NULL,
	[IpAddress] [nvarchar](50) NULL,
	[TheText] [nvarchar](max) NULL,
 CONSTRAINT [PK_PostImport] PRIMARY KEY CLUSTERED  ([Id] ASC));

"@

$processSQL = @"

INSERT INTO stack.Questions
           ([Site]
           ,[PostId]
           ,[CreationDate]
           ,[Title])
SELECT [Site]
      ,[PostId]
      ,[CreationDate]
      ,[TheText]
  FROM stack.PostImport
  where posttype = 'Initial Title';

  UPDATE q SET Tags = i.TheText
  FROM stack.PostImport i
  INNER JOIN stack.questions q
  ON i.Site = q.Site AND i.PostId = q.PostId
  where posttype = 'Initial Tags';

  UPDATE q SET Body = i.TheText
  FROM stack.PostImport i
  INNER JOIN stack.questions q
  ON i.Site = q.Site AND i.PostId = q.PostId
  where posttype = 'Initial Body'

  -- Update Body with latest body edit
  UPDATE q SET Body = s.TheText
  FROM 
(
SELECT i.TheText, i.[Site], i.PostId FROM stack.PostImport i
INNER JOIN
( SELECT MAX(CreationDate) As LastEdit, [Site], posttype, PostID 
FROM stack.PostImport 
GROUP BY [Site], posttype, PostID
HAVING posttype = 'Edit Body' ) As l
ON l.LastEdit = i.CreationDate AND l.[Site] = i.[Site] AND l.posttype = i.posttype AND l.PostID = i.PostId
) s
INNER JOIN stack.questions q
 ON s.Site = q.Site AND s.PostId = q.PostId  

"@

    $truncateImportTable = "TRUNCATE TABLE stack.PostImport;"

    [int]$script:recordCount = 0;

    Function RunSQL([string]$sql)
    {
        if ($PSCmdlet.ShouldProcess($sql,"Execute SQL Statement")) {

            $mySqlConnection = New-Object "System.Data.SqlClient.SqlConnection"
            $mySqlConnection.ConnectionString = $ConnectionString
            $mySqlConnection.Open()  
            $sqlCommand = $mySqlConnection.CreateCommand()
            $sqlCommand.CommandText = $sql

            # if the sql begins with SELECT, fill a data table
            if ($sql -match "^\s+select")
            {
                $sqlReader = $sqlCommand.ExecuteReader()

                $Datatable = New-Object System.Data.DataTable
                $DataTable.Load($SqlReader) 
                Write-Output $Datatable
            }
            else
            {
                # ExecuteNonQuery
                $result = $sqlCommand.ExecuteNonQuery()
                $script:recordCount += $result
            #    Write-Output $result
            }

            $mySqlConnection.close()  
        }
    }

    Function ImportFiles()
    {
        RunSQL -sql $truncateImportTable

        $qaDir = Join-Path $Source -ChildPath "qa"

        $files = Get-ChildItem -path "$qaDir" -Directory | Where-Object Name -ne "Global"
        [int]$siteCount = 1;
        
        $files | Select-Object -First 2000 | ForEach-Object{
    
            Write-Progress -Activity "Importing Stack Exchange Data" -percentcomplete ($siteCount/$files.count*100)  -Status  $_.Name # -CurrentOperation  
    
            $postHistory = Join-Path $_.FullName -ChildPath "PostHistory.json"
    
            Start-Sleep -Milliseconds 100
    
            if (Test-Path -Path $postHistory)
            {            
                $sql = $insertSql -replace "{siteName}",$_.Name
                $sql = $sql -replace "{fileName}",$postHistory
                
                RunSQL -sql $sql
            }
            else {
                Write-Verbose "$postHistory not found"
            }
            $siteCount++
        }
    }
}

Process
{
    if ($Import)
    {
        ImportFiles
        Write-Output "$($script:recordCount) records imported"
    }
    if ($Setup)
    {
        RunSQL -sql $sql "$setupSQL"
    }    
}