param([string]$NewLocation = "E:\news")

Begin
{
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
        $myReg = new-object Win32Api.RawRegistry

        [string]$keyName = "SYSTEM\CurrentControlSet\Control\Session Manager\Environment";
        [string]$valueName = "Path";

        Return [Win32Api.RawRegistry]::GetUnExpandedValue($keyName,$valueName)    
    }

}

Process
{
    GetOldPath
}