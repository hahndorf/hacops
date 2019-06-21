<#
.SYNOPSIS
    Changes the password of a local user
.DESCRIPTION
    This is different from 'net user username password', that resets the password and potentially destroys data
.PARAMETER userName
    The internal name of the user, if missing, the current user is assumed.
.PARAMETER oldPassword
    The old existing password for the user
.PARAMETER newPassword
    The new password

.EXAMPLE       
    Set-Password
    Sets a new password for the current user and prompts for the old and new passwords.   
.NOTES
    Author:  Peter Hahndorf
    Created: August 22nd, 2015 
    
.LINK
    https://github.com/hahndorf/Hacops
#>
param (
    [string]$userName = $($env:userName),
    [string]$oldPassword = "",
    [string]$newPassword = ""
)

Function PrintErrorMessage([int]$status)
{
    [int]$NERR_Success = 0;
    [int]$NERR_InvalidComputer = 2351;
    [int]$NERR_NotPrimary = 2226;
    [int]$NERR_PasswordTooShort = 2245;
    [int]$NERR_UserNotFound = 2221;
    [int]$ERROR_ACCESS_DENIED = 5;

    [int]$ERROR_INVALID_PASSWORD = 86;
    [int]$ERROR_INVALID_PASSWORDNAME = 1216;
    [int]$ERROR_NULL_LM_PASSWORD = 1304;

    [int]$ERROR_WRONG_PASSWORD = 1323;
    [int]$ERROR_ILL_FORMED_PASSWORD = 1324;
    [int]$ERROR_PASSWORD_RESTRICTION = 1325;
    [int]$ERROR_LOGON_FAILURE = 1326;

    [int]$ERROR_PASSWORD_EXPIRED = 1330;
    [int]$ERROR_NT_CROSS_ENCRYPTION_REQUIRED = 1386;
    [int]$ERROR_LM_CROSS_ENCRYPTION_REQUIRED = 1390;
    [int]$ERROR_NO_SUCH_DOMAIN = 1355;

    [int]$ERROR_CANT_ACCESS_DOMAIN_INFO = 1351;
           
    switch ($status)
    {
        $NERR_Success{
            Write-Host "The command completed successfully."
            break;}
        $ERROR_ACCESS_DENIED{
            Write-Host "The user does not have access to the requested information."
            break;}
        $NERR_InvalidComputer{
            Write-Host "The computer name is invalid."
            break;}
        $NERR_NotPrimary{
            Write-Host "The operation is allowed only on the primary domain controller of the domain."
            break;}
        $NERR_UserNotFound{
            Write-Host "The user name could not be found."
            break;}
        $NERR_PasswordTooShort{
            Write-Host "The password is shorter than required."
            break;}
        $ERROR_INVALID_PASSWORD{
            Write-Host "The specified network password is not correct."
            break;}
        $ERROR_INVALID_PASSWORDNAME{
            Write-Host "The format of the specified password is invalid."
            break;}
        $ERROR_NULL_LM_PASSWORD{
            Write-Host "The NT password is too complex to be converted to a LAN Manager password."
            break;}
        $ERROR_WRONG_PASSWORD{
            Write-Host "Unable to update the password. The value provided as the current password is incorrect."
            break;}
        $ERROR_ILL_FORMED_PASSWORD{
            Write-Host "Unable to update the password. The value provided for the new password contains values that are not allowed in passwords."
            break;}
        $ERROR_PASSWORD_RESTRICTION{
            Write-Host "Unable to update the password because a password update rule has been violated."
            break;}
        $ERROR_LOGON_FAILURE{
            Write-Host "Logon failure{ unknown user name or bad password."
            break;}
        $ERROR_PASSWORD_EXPIRED{
            Write-Host "Logon failure{ the specified account password has expired."
            break;}
        $ERROR_NT_CROSS_ENCRYPTION_REQUIRED{
            Write-Host "A cross-encrypted password is necessary to change a user password."
            break;}
        $ERROR_LM_CROSS_ENCRYPTION_REQUIRED{
            Write-Host "A cross-encrypted password is necessary to change this user password."
            break;}
        $ERROR_NO_SUCH_DOMAIN{
            Write-Host "The specified domain did not exist."
            break;}
            ERROR_CANT_ACCESS_DOMAIN_INFO{
            Write-Host "Configuration information could not be read from the domain controller, either because the machine is unavailable, or access has been denied."
            break;}
        default{
            Write-Host "Undocumented error code $status."
            break;}
    }
}


if ($oldPassword -eq "")
{
    $sOld = Read-Host 'Type in the old password' -AsSecureString

    $oldPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sOld))
}

if ($newPassword -eq "")
{
    $sNew1 = Read-Host 'Type the new password' -AsSecureString

    $newPassword1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sNew1))

    $sNew2 = Read-Host 'Re-type the new password' -AsSecureString

    $newPassword2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sNew2))

    if ($sNew1 -ne $sNew2)
    {
        Write-Warning "The new password don't match"
        exit 
    }
}


$MethodDefinition = @"
[DllImport("netapi32.dll", CharSet=CharSet.Unicode, CallingConvention=CallingConvention.StdCall,
SetLastError=true )]
public static extern uint NetUserChangePassword (
[MarshalAs(UnmanagedType.LPWStr)] string domainname,
[MarshalAs(UnmanagedType.LPWStr)] string username,
[MarshalAs(UnmanagedType.LPWStr)] string oldpassword,
[MarshalAs(UnmanagedType.LPWStr)] string newpassword
);
"@

try
{
    $NetAPI32 = Add-Type -MemberDefinition $MethodDefinition -Name 'NetAPI32' -Namespace 'Win32' -PassThru
    $result = $NetAPI32::NetUserChangePassword('.', $userName, $oldPassword, $newPassword)

    PrintErrorMessage -status $result
}
catch [System.Exception]
{
    Write-Host "Other exception"
}
              