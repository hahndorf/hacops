[CmdletBinding(SupportsShouldProcess=$true)]
param()

Process
{

    # change the connection string and your statement
    $ConnectionString = "Server=.;Database=master;Integrated Security=True;"

    # example of Azure database connection string:
    # Database=mydatabase;Data Source=tcp:myserver.database.windows.net,1433;Persist Security Info=False;User ID=username;Password=yourPassword;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
    
    # change the SQL statement you want to execute, use semicola to separate multiple statements.

$sql = @"

    SELECT TOP (20) [name],database_id,create_date,compatibility_level FROM master.sys.databases

"@

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
            Write-Output $result
        }

        $mySqlConnection.close()           
    }  
}

<#
.SYNOPSIS
   Single file script to run a SQL command against a SQL Server

   .DESCRIPTION
   Sometimes you need to run a SQL statement on a machine that has no tools installed.
   No SQL-Server tools, no Visual Studio.
   For this script, all you need Windows 7+ with no additional tools.

   If not already done, save this script into a file and open it in notepad.exe
   to edit the connection string and the SQL statement to execute.
      
   .EXAMPLE
   Invoke-SQL.ps1 

   No parameters are needed, you change the code in the script file itself.

   .EXAMPLE
   Invoke-SQL.ps1 -whatif

   Just tells you what it would do without executing the SQL.
#>