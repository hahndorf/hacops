param(
        [int32]$lastNEvents = [Int32]::MaxValue,
        [int32]$topNResults = 10
     )

Process{

   #Requires -RunAsAdministrator

   Write-Host "querying the sysmon event log, this may take a while, please be patient"

   $logRecords = Get-WinEvent -LogName Microsoft-Windows-Sysmon/Operational | Where-Object {$_.ID -eq "1"} | Select-Object -First $lastNEvents | Select-Object -Property Message

      $myArray = foreach($LogEntry in $logRecords)
      {         
         $pso = new-object psobject
         $LogEntry -match "Image: (.+)" | Out-Null
         $pso | add-member -membertype NoteProperty -Name Image -Value $matches[1] -passthru
         $LogEntry -match "ParentImage: (.+)" | Out-Null
         $pso | add-member -membertype NoteProperty -Name Parent -Value $matches[1] -passthru
         $LogEntry -match "IntegrityLevel: (.+)" | Out-Null
         $pso | add-member -membertype NoteProperty -Name IntegrityLevel -Value $matches[1] -passthru
      }

   Write-Host "Top Executables:" -ForegroundColor yellow

   $myArray | Group-Object -property Image -noelement | sort-object -property Count -Descending | Select-Object  -First $topNResults | Format-Table -AutoSize

   Write-Host "Top Parents:" -ForegroundColor yellow

   $myArray | Group-Object -property Parent -noelement | sort-object -property Count -Descending | Select-Object  -First $topNResults| Format-Table -AutoSize

   Write-Host "Integrity Levels:" -ForegroundColor yellow

   $myArray | Group-Object -property IntegrityLevel -noelement | sort-object -property Count -Descending

}

<#
.SYNOPSIS
    Simple script to show Process Starts bases on SysInternals Sysmon
.DESCRIPTION
    After having set up Sysmon, use this script to show the number of process starts.
    Run as elevated administrator
.PARAMETER lastNEvents
    Looking only at the last n event log entries, default is all
.PARAMETER topNResults
    Showing the top n programs.
.NOTES
    Tested on Windows 10 and Server 2016
    Author:  Peter Hahndorf
    Created: January 10th, 2015
.LINK
    https://github.com/hahndorf/hacops
    https://peter.hahndorf.eu/blog/Some-stats-based-on-the-Sysint.html
    https://docs.microsoft.com/en-gb/sysinternals/downloads/sysmon
#>