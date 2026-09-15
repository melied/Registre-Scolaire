# Registre Scolaire - Mise a jour via PowerShell
# تحديث السجل المدرسي عبر باورشل : يتحقق من GitHub ويثبت أحدث نسخة مع الحفاظ على البيانات
# Usage : double-clic sur Update-RegistreScolaire.bat  |  powershell -ExecutionPolicy Bypass -File Update-RegistreScolaire.ps1 [-Silent]
[CmdletBinding()]
param([switch]$Silent)
$ErrorActionPreference = 'Stop'
$Repo = 'melied/Registre-Scolaire'
$Token = ''  # PAT lecture seule si depot prive, sinon vide
$RegKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\RegistreScolaire'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

function Ver-Cmp($a, $b) {
  $pa = @($a -split '\.' | ForEach-Object { if ($_ -match '^\d+$') { [int]$_ } else { 0 } })
  $pb = @($b -split '\.' | ForEach-Object { if ($_ -match '^\d+$') { [int]$_ } else { 0 } })
  $n = [Math]::Max($pa.Count, $pb.Count)
  for ($i = 0; $i -lt $n; $i++) {
    if ($i -lt $pa.Count) { $x = $pa[$i] } else { $x = 0 }
    if ($i -lt $pb.Count) { $y = $pb[$i] } else { $y = 0 }
    if ($x -gt $y) { return 1 }
    if ($x -lt $y) { return -1 }
  }
  return 0
}

function Msg($ar, $fr) { Write-Host "$ar"; Write-Host "$fr" }

try {
  Msg "== التحقق من التحديثات ==" "== Verification des mises a jour =="
  try {
    $H = @{Accept = 'application/vnd.github+json'; 'User-Agent' = 'RegistreScolaire-Updater' }
    if ($Token) { $H['Authorization'] = 'Bearer ' + $Token }
    $rel = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest" -TimeoutSec 25 -Headers $H
  } catch {
    $sc = 0
    try { $sc = [int]$_.Exception.Response.StatusCode } catch {}
    if ($sc -eq 404) { Msg "لا توجد نسخة منشورة بعد." "Aucune version publiee pour le moment."; exit 0 }
    throw
  }
  $latest = [string]$rel.tag_name
  if ($latest.StartsWith('v') -or $latest.StartsWith('V')) { $latest = $latest.Substring(1) }
  $latest = $latest.Trim()
  $inst = $null
  if (Test-Path $RegKey) { $inst = (Get-ItemProperty $RegKey).DisplayVersion }
  if (-not $inst) { $inst = '0.0.0'; Msg "البرنامج غير مثبت، سيتم تثبيت أحدث نسخة." "Programme non installe, installation de la derniere version." }
  Msg ("النسخة المثبتة : " + $inst) ("Version installee : " + $inst)
  Msg ("أحدث نسخة : " + $latest) ("Derniere version : " + $latest)
  if ((Ver-Cmp $latest $inst) -le 0) { Msg "التطبيق محدث، لا حاجة للتحديث." "Application a jour."; exit 0 }
  $asset = @($rel.assets | Where-Object { $_.name -like '*.exe' }) | Select-Object -First 1
  if (-not $asset) { $asset = @($rel.assets) | Select-Object -First 1 }
  if (-not $asset) { throw "no asset" }
  $tmp = Join-Path $env:TEMP $asset.name
  Msg ("تحميل : " + $asset.name) ("Telechargement : " + $asset.name)
  Invoke-WebRequest $asset.browser_download_url -OutFile $tmp -UseBasicParsing -TimeoutSec 300
  $size = (Get-Item $tmp).Length
  if ($size -lt 100000) { throw "download too small ($size)" }
  Msg "التثبيت الصامت جار (البيانات محفوظة)..." "Installation silencieuse (donnees conservees)..."
  $p = Start-Process -FilePath $tmp -ArgumentList '/SILENT' -Wait -PassThru
  if ($p.ExitCode -ne 0) { throw ("setup exit " + $p.ExitCode) }
  Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  Msg ("تم التحديث إلى " + $latest + " بنجاح.") ("Mise a jour vers " + $latest + " reussie.")
  exit 0
} catch {
  Msg "فشل التحديث، تحقق من الإنترنت." "Echec de la mise a jour, verifiez la connexion."
  Write-Host ("Detail: " + $_.Exception.Message)
  Write-Host "https://github.com/melied/Registre-Scolaire/releases"
  exit 1
} finally {
  if (-not $Silent) { Read-Host "Enter / إدخال" | Out-Null }
}
