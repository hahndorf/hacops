[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string]$username = "",
    [string]$password = "", 
    [int]$HighLightOverXPercent = 89
)

Begin
{

    # this directory that holds all the data files
    [string]$script:RootFolder = "$env:userProfile\Documents\Okc";

    [string]$DataFile = "OKC-RecentVisitors.json"

    [bool]$useProxy = $false

    if ($username -eq "")
    {
        Write-Output "Please provide a username"
        Exit 10
    }

    Function Test-RootDir()
    {
        if (!(Test-Path $script:RootFolder))
        {
            mkdir -Path $script:RootFolder
        }
    }

    Function Get-Password
    {
        if ($password -ne "")
        {
            $script:okc_password = $password 
        }
        else
        {
            # ask the user for the password
           $ph = Read-Host "Please enter your OKC password for `'$($username)`'" -AsSecureString
           $script:okc_password = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($ph)) 
        }
        
    }

   Test-RootDir

    [int]$CallDelay = 2000


    # the username for the site
    [string]$script:okc_user = $username;
    # variable for the user, leave this empty here
    [string]$script:okc_password = "";
    # the url of okc, keep this
    [string]$script:okc_url = "https://www.okcupid.com";

    # no need to change these
    [string]$script:UsersFolder = "$script:RootFolder\Users";
    [string]$script:LogsFolder  = "$script:RootFolder\Logs";

    [string]$script:oAuthAccesstoken = ""


    [string]$script:UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) (KHTML, like Gecko) Chrome/59.0.3071.115 Get-OkcData/1.0";

    $script:proxy = $null;
    if ($useProxy)
    {
        $script:proxy = "http://127.0.0.1:8888"
    }



    Function Invoke-OkcPage{
        [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="Low")]
        param([string]$url)

        $url = "$script:okc_url/" + $url

        Write-Verbose "Invoke-WebRequest for: $url"

        $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $headers.Add("accept", '*/*')
        $headers.Add("authorization", "Bearer $($script:oAuthAccesstoken)")
        $headers.Add("x-okcupid-platform","DESKTOP");

        if ($PSCmdlet.ShouldProcess($url,"Download Page Data")) {
            Start-Sleep -Milliseconds $CallDelay
            $response = Invoke-WebRequest -usebasicparsing -uri $url -Proxy $script:proxy  -Headers $headers `
                    -Method "GET" -UserAgent $script:UserAgent  -WebSession $script:okcsession            
        }

        return $response
    }

    Function Invoke-OkcApiCall{
        [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="Low")]
        param([string]$url,[string]$body,[switch]$NoOAuthToken,[switch]$post)

        $url = "$script:okc_url/" + $url

        if ($url -match "\?")
        {
            $url += "&okc_api=1"
        }
        else
        {
            $url += "?okc_api=1"
        }

        Write-Verbose "Invoke-WebRequest for: $url"

        $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $headers.Add("accept", 'application/json')
        if (!$NoOAuthToken)
        {
            $headers.Add("authorization", "Bearer $($script:oAuthAccesstoken)")
            $headers.Add("x-okcupid-platform","DESKTOP");
        }

        if ($PSCmdlet.ShouldProcess($url,"Download API Data")) {

            # wait between any call, don't overuse the API
            Start-Sleep -Milliseconds $CallDelay

            if ($post)
            {
                $response = Invoke-WebRequest -usebasicparsing -uri $url -Proxy $script:proxy  -Headers $headers `
                    -ContentType "application/x-www-form-urlencoded" -Method "POST" -Body "$body" -UserAgent $script:UserAgents -WebSession $script:okcsession
            }
            else {
            $response = Invoke-WebRequest -usebasicparsing -uri $url -Proxy $script:proxy  -Headers $headers `
                    -Method "GET" -UserAgent $script:UserAgent  -WebSession $script:okcsession
            }
        }

        Write-Debug -Message $response

        return $response     
    }

    Function Start-OkcSession()
    {
        Get-Password

        $url = "$script:okc_url/login"

        $body = "okc_api=1&username=$($script:okc_user)&password=$($script:okc_password)"

        Write-Verbose "Invoke-WebRequest for: $url"
     #   Write-Debug "with body: $body"

        $response = Invoke-WebRequest -usebasicparsing -uri $url -Proxy $script:proxy -Headers @{"accept"="application/json"} `
           -ContentType "application/x-www-form-urlencoded" -Method "POST" -Body "$body" -UserAgent $script:UserAgent -SessionVariable "okcSession"
      
        if ($response.StatusCode -eq 200)
        {    
            $jso = $response.Content | ConvertFrom-Json
            $script:oAuthAccesstoken = $jso.oauth_accesstoken;
            Write-Host "Authenticated as $($jso.screenname)";

            # save the session for later use
            $script:okcsession = $okcSession

            Write-Debug "Jason: $jso"
        }
        else
        {
            Write-Error "Problem: " + $response.StatusDescription
        }
    }

    Function Save_OkcResponse($response,[string]$file,[switch]$noOutput)
    {
        if ($PSCmdlet.ShouldProcess($file,"Saving API Data")) {
            if ($response.StatusCode -eq 200)
            {
                if (!$noOutput) {Write-Host "Saving data to $file";}
                $data = $response.Content | ConvertFrom-Json | ConvertTo-Json -Depth 4
                $data | Set-Content -Path $file -Encoding UTF8
            } 
            else
            {
                Write-Error "Problem: " + $response.StatusDescription
            }        
        }
    }

    Function Save_OkcTextResponse($response,[string]$file)
    {
        if ($PSCmdlet.ShouldProcess($file,"Saving Page Data")) {
            if ($response.StatusCode -eq 200)
            {
                Write-Host "Saving data to $file";
                $response.Content | Set-Content -Path $file -Encoding UTF8
            } 
            else
            {
                Write-Error "Problem: " + $response.StatusDescription
            }        
        }
    }

Function GetHtmlFooter()
{

    $theDate = $(Get-Date).ToString("dd-MMMM-yyyy HH:mm");

$footer = @"   
    <div class='filemeta'>Data processed: $theDate - $env:COMPUTERNAME</div> 
</body>
</html>
"@

    return $footer
}

Function GetHtmlTop([string]$htmlTitle,[string]$bodyFontSize,[string]$cssPath="../../")
{

$header = @"
<html>
<head>
    <title>$htmlTitle</title>
	<meta name="viewport" content="width=device-width, initial-scale=1.0" />
	<meta name="robots" content="noindex" />
	<meta name="description" content="OKC API Data" />
<style>

body 
{
    font-size:$bodyFontSize;
    font-family:'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
}

body div{
    margin:0;

}

h1, h2
{
    border-radius: 8px;
    color:white;
    background: #104DA1;
    padding-left: 6px;
    margin-bottom: 5px;
    
}


.number
{
    font-size: 1em;
    color:black;
    margin-right:0.5em;
}

.compUser,#profile,#summary
{
     background-color:#EEE;
     border: 3px #104DA1 solid;
     border-radius: 8px;
}

.compUser
{
     font-size: 1.1em;
     color:black;
     margin-left:1px;
     margin-top:3px;
     padding:6px;
}


.meta
{
    display: block;
    font-size: 0.8em;
    color:#AAA;
    margin-top:1em;
}





.filemeta
{
    display: block;
    font-size: 0.6em;
    color:#555;
    margin-top:2.0em;
    margin:5px;
}
.link
{
    font-size:0.7em;
}


  table{
    border-collapse: collapse;
    border: 1px solid black;
  }
  table th,td{
        border: 1px solid  #BBB;
       padding:2px;
  }
    
  table.recentvisits 
  {
    font-size: 1.3em;
  }

  table.recentvisits th,td{
       padding:5px;
  }

  table.recentvisits td:nth-child(4),table.recentvisits td:nth-child(5)
  {
      text-align:right;

  }

  tr.ninety td{
      background-color:#81FF68;
  }
  tr.eighty td{
      background-color:#FFDC44;
  }

 .bold
 {
     font-weight:bold;
 }

nav
{
    background-color:#ddd;
    padding:6px;
    border-radius: 8px;
    margin-top:4px;
}


</style>
</head>
"@

return  $header

    }



    Function Get-OkcVisitors()
    {
        $re = Invoke-OkcApiCall -url "visitors"
        Save_OkcResponse -response $re -file "$RootFolder\$DataFile"; 
    }

    [int]$script:VisitCount = 0;

    $recentList = New-Object 'System.Collections.Generic.dictionary[string,string]'
    $recentVisitors = New-Object System.Collections.ArrayList

    Function RecentTableHeader([string]$title)
    {
  #      $tabhead = "<h2>$title</h2>"
        $tabHead += "<table class=`"recentvisits`">"
        $tabHead += "<tr><th title='Time of the visit'>Time</th>"
        $tabHead += "<th title='Name'>Name</th>" 
        $tabHead += "<th title='Location'>Location</th>" 
        $tabHead += "<th title='Match percentage'>Match</th>"
        $tabHead += "<th title='The age of the person at the time of export'>Age</th>"           
                     
        $tabHead += "<th title='Boby type'>Body</th>"   
        $tabHead += "<th title='Education level'>Edu</th>"      
        $tabHead += "<th title='Not single or straight'>Remarks</th>" 
        $tabHead += "</tr>`r`n"
        $tabHead | Out-File -FilePath $TargetFile -Encoding ascii -Append         
    }


    Function ProcessRecentData([string]$TargetFile,[string]$title,$items)
    {
        $NineteenSeventy = New-Object -Type DateTime -ArgumentList 1970, 1, 1, 0, 0, 0, 0

        $html = RecentTableHeader -title "$title"
        $html | Out-File -FilePath $TargetFile -Encoding ascii -Append 

        $items | ForEach-Object {
              
           
            
            $bodytype = "-"
            if ($_.bodytype -ne $null)
            {
                $bodytype = $_.bodytype
            }

            $extra = "";
            If ($_.status -ne "Single")
            {
                $extra = $_status + ", "
            }
            If ($_.orientation -ne "Straight")
            {
                $extra += $_.orientation + ","
            }

            If ($_.Smoking -ne "No")
            {
                $extra += "Smokes" + ","
            }

            $names = $($_.DisplayName) + " (" + $_.username + ")"

            if ($($_.matchpercentage) -gt $HighLightOverXPercent)
            {
                $highMatchClass = " class='ninety'"
            }
            else
            {
                $highMatchClass = ""
            }
            
            $sent = $NineteenSeventy.AddSeconds($_.stalktime).ToString("dd-MMM HH:mm")

            $html = "<tr $highMatchClass>"
            $html += "<td>$sent</td><td class='bold'><a href=`"$($script:okc_url)/profile/$($_.username)`" target='_blank'>$names</a></td><td>$($_.location)</td>"
            $html += "<td class='bold'>$($_.matchpercentage)%</td><td>$($_.age)</td>"
            $html += "<td>$bodytype</td><td>$($_.Education)</td><td>$extra</td>"
            $html += "</tr>"
            $html | Out-File -FilePath $TargetFile -Encoding ascii -Append            
        }         
             
            "</table>" | Out-File -FilePath $TargetFile -Encoding ascii -Append 
    }  

  

    Function GetRecentVisitors([string]$sourceFile)
    {
        if (!(Test-Path $sourceFile)) {return}

        $NineteenSeventy = New-Object -Type DateTime -ArgumentList 1970, 1, 1, 0, 0, 0, 0    
        $visitors = Get-Content -Raw -Path $sourceFile | ConvertFrom-Json
                
        foreach ($m in $visitors.stalkers)
        {
            if (!$recentList.ContainsKey($m.stalk_time))
            {    
                $info = @{}
                $info.StalkTime=$m.stalk_time
                $info.UserName=$m.original_username

                $info.LookingFor=$m.lookingfor
                $info.BodyType=$m.bodytype
                $info.Status=$m.status
                $info.Orientation=$m.orientation

                $info.Location=$m.location
                $info.MatchPercentage=$m.match_percentage
                $info.IsFavorite=$m.is_favorite
                $info.Age=$m.age
                $info.Smoking=$m.smoking
                $info.Education=$m.education_level

                $info.DisplayName=$m.displayname

                $object = New-Object -TypeName PSObject -Prop $info                	
                $recentVisitors.Add($object) | Out-Null
            }
        }        
    }

    Function ProcessRecent()
    {
        $TargetFile = "$RootFolder\OKC-RecentVisitors.html"  

        $htmlTitle = "OKC Recent Visitors"

        $html = GetHtmlTop -htmlTitle $htmlTitle -bodyFontSize "1.1em" -cssPath "";
        $html += "<body><div><h1>$htmlTitle</h1>"        
        $html | Out-File -FilePath $TargetFile -Encoding ascii          

        $allusers = Get-ChildItem -Path "$RootFolder" -Filter "OKC-RecentVisitors.json" -File
        $userCount = 1;

        $allusers | Sort-Object LastWriteTime -Descending | ForEach-Object {

            Write-Progress -Activity "Creating Recent Visits from user data $per" -percentcomplete ($userCount/$allusers.count*100)  -Status  "Processing files" -CurrentOperation  $_.FullName

            GetRecentVisitors -sourceFile $_.FullName

         #   ProcessRecentFile -TargetFile $TargetFile -sourceFile $_.FullName
            $userCount++;
        }

        $data = $recentVisitors | Sort-Object StalkTime -Descending -Unique | Sort-Object StalkTime -Descending | Select-Object -First 20 
        ProcessRecentData -TargetFile $TargetFile -items $data -title "By time"

        "</div>" + $(GetHtmlFooter) | Out-File -FilePath $TargetFile -Encoding ascii -Append 

         Write-Output "$targetFile created"      
    }
   
}

Process
{
    Start-OkcSession
    Get-OkcVisitors
    ProcessRecent
}
