[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true)]
    [string]$NewLocation)

Begin
{

#requires –runasadministrator

$code = @"
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace Win32Api
{
    public class RawRegistry
    {
        [DllImport("advapi32", CharSet = CharSet.Auto)]
        public static extern int RegOpenKeyEx(UIntPtr hKey, string lpstrSubKey, UInt32 nReserved, UInt32 samDesired, ref UIntPtr phResult);

        [DllImport("advapi32", CharSet = CharSet.Auto)]
        public static extern int RegCloseKey(UIntPtr hKey);

        [DllImport("advapi32", CharSet = CharSet.Auto, EntryPoint = "RegQueryValueEx")]
        public static extern int RegQueryStringValueEx(UIntPtr hKey, string lpstrValueName, UIntPtr nReserved, ref UInt32 pValueType, string lpstrValueBuf, ref Int32 pValueBufSize);

        public static string GetUnExpandedValue(string keyName,string valueName)
        {
            UIntPtr HKLM = (UIntPtr)0x80000002;
            uint REG_KEY_READ = 0x00020019;

            UIntPtr xKey = (UIntPtr)0;
            int ret = RegOpenKeyEx(HKLM, keyName, 0, REG_KEY_READ, ref xKey);
            if (ret == 0)
            {
                UInt32 nValueType = 0;
                string stringValue = "";
                Int32 bufferSize = 0;

                // find out how the required size for the output buffer
                ret = RegQueryStringValueEx(xKey, valueName, (UIntPtr)0, ref nValueType, stringValue, ref bufferSize);

                // allocate output buffer
                StringBuilder buffer = new StringBuilder(bufferSize);
                buffer.Append((char)0, bufferSize);
                stringValue = buffer.ToString();

                // retrieve the unexpanded string value
                ret = RegQueryStringValueEx(xKey, valueName, (UIntPtr)0, ref nValueType, stringValue, ref bufferSize);
                ret = RegCloseKey(xKey);

                return stringValue;
            }
            else
            {
                throw new System.IO.IOException("Registry value not found, return value was: " + ret.ToString());
            }
        }        
    }
}
"@

    Function GetOldPath()
    {
        Add-Type -TypeDefinition $code
        $myReg = New-Object Win32Api.RawRegistry

        # Path variable location in the registry
        [string]$keyName = "SYSTEM\CurrentControlSet\Control\Session Manager\Environment";
        [string]$valueName = "Path";

        $theValue = [Win32Api.RawRegistry]::GetUnExpandedValue($keyName,$valueName)

        # filled up with NULL characters at the end, remove them
        Return ($theValue -replace "\x00+$","");
    }

}

Process
{
    # Win32API error codes
    $ERROR_SUCCESS = 0
    $ERROR_DUP_NAME = 34 
    $ERROR_INVALID_DATA = 13

    $NewLocation = $NewLocation.Trim();

    If ($NewLocation -eq "" -or $NewLocation -eq $null)
    {
        Exit $ERROR_INVALID_DATA
    }
   
    [string]$oldPath = GetOldPath
    $pattern = ";" + $NewLocation.Replace("\","\\") + ";"
    $RxInput = ";" + $oldPath + ";"

    Write-Verbose "Old Path: $oldPath"

    # check whether the new location is already in the path
    if (";$oldPath;" -match $pattern)
    {
        Write-Warning "New location is already in the path"
        Exit $ERROR_DUP_NAME
    }

    # build the new path, make sure we don't have double semicolons
    $newPath = $oldPath + ";" + $NewLocation
    $newPath = $newPath -replace ";;",""

    if ($pscmdlet.ShouldProcess("%Path%", "Add $NewLocation")){
        # add to the current session
        $env:path += ";$NewLocation"
        # save into registry
        [Environment]::SetEnvironmentVariable("Path", "$newPath", "Machine")

        Write-Output "The operation completed successfully."
    }

    # http://stackoverflow.com/questions/23813478/set-nested-expandable-environment-variable-with-powershell

    Exit $ERROR_SUCCESS        
}

<#
.SYNOPSIS
    Adds a new item to the machine path environment variable
.DESCRIPTION
    Most more popular methods to change the %path% actually break it.
.PARAMETER NewLocation
    The new directory location to add at the end of the path. Can be an variable itself.
.EXAMPLE
   Set-PathVariable.ps1 -NewLocation "%bin%"
   Adds the string "%bin%" to the path, when using it it is expanded.
.NOTES
    Tested on Windows 10 and Server 2016
    Author:  Peter Hahndorf
    Created: October 7th, 2016   
.LINK
    https://peter.hahndorf.eu
    https://github.com/hahndorf/hacops
#>