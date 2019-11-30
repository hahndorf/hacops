[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true,ParameterSetName="Import")]
    [switch]$Import,
    [parameter(Mandatory=$true,ParameterSetName="Import")]
    [string]$Source,
    [parameter(Mandatory=$true,ParameterSetName="Setup")]
    [switch]$Setup,
    [parameter(Mandatory=$true,ParameterSetName="Process")]
    [switch]$Process,    
    [string]$ConnectionString = "Server=.;Database=StackExchange;Integrated Security=True;"
)



Begin{

# 
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

$setupSchema = "CREATE SCHEMA [stack] AUTHORIZATION [dbo]"

$setupSQL = @"

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
 
CREATE TABLE [stack].Answers(
	[Id] [int] IDENTITY(1,1) NOT NULL,
	[Site] [varchar](100) NOT NULL,
	[PostId] [int] NOT NULL,
	[CreationDate] [datetime] NOT NULL,
	[Body] [nvarchar](max) NULL,
 CONSTRAINT [PK_Answers] PRIMARY KEY CLUSTERED ([Id] ASC));

"@

$processSQL = @"

TRUNCATE TABLE stack.Questions;
TRUNCATE TABLE stack.Answers;

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
 ON s.Site = q.Site AND s.PostId = q.PostId; 

 -- Update Body with latest title edit
 UPDATE q SET Title = s.TheText
 FROM 
(
SELECT i.TheText, i.[Site], i.PostId FROM stack.PostImport i
INNER JOIN
( SELECT MAX(CreationDate) As LastEdit, [Site], posttype, PostID 
FROM stack.PostImport 
GROUP BY [Site], posttype, PostID
HAVING posttype = 'Edit Title' ) As l
ON l.LastEdit = i.CreationDate AND l.[Site] = i.[Site] AND l.posttype = i.posttype AND l.PostID = i.PostId
) s
INNER JOIN stack.questions q
ON s.Site = q.Site AND s.PostId = q.PostId;

-- Update Body with latest tags edit
UPDATE q SET Tags = s.TheText
FROM 
(
SELECT i.TheText, i.[Site], i.PostId FROM stack.PostImport i
INNER JOIN
( SELECT MAX(CreationDate) As LastEdit, [Site], posttype, PostID 
FROM stack.PostImport 
GROUP BY [Site], posttype, PostID
HAVING posttype = 'Edit Tags' ) As l
ON l.LastEdit = i.CreationDate AND l.[Site] = i.[Site] AND l.posttype = i.posttype AND l.PostID = i.PostId
) s
INNER JOIN stack.questions q
ON s.Site = q.Site AND s.PostId = q.PostId;

-- insert answers
INSERT INTO stack.Answers
           ([Site]
           ,[PostId]
           ,[CreationDate]
           ,[Body])

SELECT [Site],PostId,[CreationDate],TheText
  FROM stack.PostImport a
  WHERE a.PostType = 'Initial Body' AND a.id NOT IN
(
SELECT i.Id
  FROM stack.PostImport i
  INNER JOIN stack.Questions q
  ON i.[site] = q.[Site] AND i.PostId = q.PostId);

  -- Update answer Body with latest body edit
  UPDATE a SET Body = s.TheText
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
INNER JOIN stack.answers a
 ON s.Site = a.Site AND s.PostId = a.PostId; 

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

        if (!(Test-Path -Path $qaDir))
        {
            Write-Warning "`'$qaDir`' does not exist"
            exit 404
        }

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
        RunSQL -sql "$setupSchema"
        RunSQL -sql "$setupSQL"
        Write-Output "Schema and tables created"
    }
    if ($Process)
    {
        RunSQL -sql "$processSQL"
        Write-Output "Import data copied to stack.questions and stack.answers tables"
    }
}

<#
.SYNOPSIS
   Script to import Stack Exchange Questions and answers into a SQL-Server database

.DESCRIPTION
   After you downloaded all your Stack Exchange data via their GDPR Export feature
   unzip the file and perform three steps:

   Run this script on the SQL-Server itself and change the connection string parameter
   to an existing database. To use the default, manually create a database named StackExchange

   Then run -setup to create the tables needed to import the data.

   Run -import -source with the root of the unzip files to import the data into the stack.PostImport table

   Run -process to copy the imported data into the stack.questions and stack.answers tables

   Now you have the data in two tables and can use it.

   Currently you have your answers but you don't know the questions they answer.

   Importing and processing again will first delete all existing data, so to make permanent changes copy the data somewhere else.
      
.EXAMPLE
   Import-StackExchangeData.ps1 -setup

   Create the tables in the database specified in the -connectionstring

.EXAMPLE
   Import-StackExchangeData.ps1 -import -source "$env:UserProfile\desktop\GDPR-P20191127-123"

   Imports the questions and answers from all sites

.EXAMPLE
   Import-StackExchangeData.ps1 -process

   Copies the data into separate tables.

.NOTES
    Tested with SQL-Server 2017
    Author:  Peter Hahndorf
    Created: November 30th, 2019
.LINK
    https://peter.hahndorf.eu
    https://github.com/hahndorf/hacops

#>