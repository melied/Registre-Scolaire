# Publie une Release GitHub avec le Setup joint (declenche les notifications de mise a jour)
# Usage : powershell -ExecutionPolicy Bypass -File Publish-Release.ps1 -Tag v1.3.0 [-Notes "..."]
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Tag, [string]$Notes = '', [string]$Repo = 'melied/Registre-Scolaire')
$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

Add-Type @'
using System; using System.Runtime.InteropServices;
public class CredMan {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  struct CRED { public int Flags; public int Type; public string Target; public int x1; public long x2; public int CredSize; public IntPtr Blob; public int x3; public int x4; public string x5; public string x6; public int x7; public int x8; }
  [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  static extern bool CredRead(string target, int type, int flags, out IntPtr cred);
  [DllImport("advapi32.dll")] static extern void CredFree(IntPtr cred);
  public static string[] ReadGitHub() {
    string[] targets = new string[]{"git:https://github.com", "git:https://api.github.com"};
    foreach (var t in targets) {
      IntPtr p;
      if (CredRead(t, 1, 0, out p)) {
        try {
          var c = (CRED)Marshal.PtrToStructure(p, typeof(CRED));
          string secret = Marshal.PtrToStringUni(c.Blob, c.CredSize/2);
          return new string[]{ "git-credential", secret };
        } finally { CredFree(p); }
      }
    }
    return null;
  }
}
'@
$cred = [CredMan]::ReadGitHub()
if (-not $cred) { Write-Host "No GitHub credential in Windows Credential Manager."; exit 2 }
$basic = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($cred[0] + ':' + $cred[1])))
$H = @{ Authorization = "Basic $basic"; Accept = 'application/vnd.github+json'; 'User-Agent' = 'RegistreScolaire-Publisher' }
$ver = $Tag.TrimStart('v','V')
$body = @{
  tag_name = 'v' + $ver; name = 'v' + $ver; draft = $false; prerelease = $false;
  body = $(if ($Notes) { $Notes } else { "Registre Scolaire v$ver" })
} | ConvertTo-Json
$rel = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases" -Method Post -Body $body -ContentType 'application/json' -Headers $H -TimeoutSec 60
$up = $rel.upload_url -replace '\{\?.*\}$',''
$asset = Join-Path $PSScriptRoot 'Setup_RegistreScolaire.exe'
if (-not (Test-Path $asset)) { throw "Setup introuvable : $asset" }
$upUrl = $up + '?name=' + [Uri]::EscapeDataString('Setup_RegistreScolaire.exe')
$upl = Invoke-RestMethod $upUrl -Method Post -InFile $asset -ContentType 'application/octet-stream' -Headers $H -TimeoutSec 300
Write-Host ("Release publiee : " + $rel.html_url)
Write-Host ("Asset : " + $upl.browser_download_url + " (" + $upl.size + " octets)")
