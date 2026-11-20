# Pack and sign the AppGallery .app from the signed release HAP.
#
# Why this exists: hvigor's `assembleApp` packs the UNSIGNED module HAP into the
# .app (only the outer .app gets a signature block). AGC rejects that with 993,
# so we build the signed HAP, put it into the app container ourselves and sign
# the container with the release certificate.
#
# Usage (interactive, prompts for the keystore password):
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\pack-app.ps1
#
# Options:
#   -NoSign        only build the unsigned app container (for inspection)
#   -Keystore <p>  default: %USERPROFILE%\LockWarden-keys\lockwarden.p12
#   -Alias <name>  default: LockWarden
#
# NOTE: keep this file ASCII-only (Windows PowerShell 5.1 reads BOM-less files as ANSI).

param(
  [switch]$NoSign,
  [string]$Keystore = (Join-Path $env:USERPROFILE 'LockWarden-keys\lockwarden.p12'),
  [string]$Alias = 'LockWarden',
  [string]$CerFile = (Join-Path $env:USERPROFILE 'LockWarden-keys\LockWarden.cer'),
  [string]$ProfileFile = (Join-Path $env:USERPROFILE 'LockWarden-keys\LockWardenRelease.p7b')
)

$ErrorActionPreference = 'Continue'
$DevEco = 'C:\Program Files\Huawei\DevEco Studio'
$java = Join-Path $DevEco 'jbr\bin\java.exe'
$signTool = Join-Path $DevEco 'sdk\default\openharmony\toolchains\lib\hap-sign-tool.jar'
$project = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $project 'build\outputs\release'
$work = Join-Path $project 'build\pack'
$hap = Join-Path $project 'entry\build\release\outputs\default\entry-default-signed.hap'

function Step([string]$text) { Write-Host ''; Write-Host ("[pack] " + $text) }

# 1) signed release HAP
if (-not (Test-Path $hap)) {
  Step 'release HAP missing, building it first'
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $project 'tools\build.ps1') -Clean -Release
  if (-not (Test-Path $hap)) { throw "build did not produce $hap" }
}
Step ("signed HAP: " + $hap + " (" + (Get-Item $hap).Length + " bytes)")

# 2) pac.json / pack.info: reuse the ones hvigor generated (from an existing .app if needed)
New-Item -ItemType Directory -Force -Path $work | Out-Null
$pac = Join-Path $work 'pac.json'
$packInfo = Join-Path $work 'pack.info'
if (-not (Test-Path $pac) -or -not (Test-Path $packInfo)) {
  $knownApp = Join-Path $outDir 'LockWarden-release-signed.app'
  if (-not (Test-Path $knownApp)) {
    $knownApp = Join-Path $project 'dist\LockWarden-1.1.0-release-signed.app'
  }
  if (-not (Test-Path $knownApp)) { throw 'no existing .app found to copy pac.json/pack.info from' }
  Add-Type -AssemblyName System.IO.Compression | Out-Null
  Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null
  $zip = [System.IO.Compression.ZipFile]::OpenRead($knownApp)
  try {
    foreach ($name in @('pac.json', 'pack.info')) {
      $entry = $zip.GetEntry($name)
      if ($entry -eq $null) { throw "existing .app has no $name" }
      $target = Join-Path $work $name
      [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true)
    }
  } finally { $zip.Dispose() }
}
Step ('pac.json + pack.info ready')

# 3) unsigned app container: pac.json + pack.info + signed HAP
$unsignedApp = Join-Path $work 'LockWarden-unsigned.app'
if (Test-Path $unsignedApp) { Remove-Item $unsignedApp -Force }
Add-Type -AssemblyName System.IO.Compression | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null
# string values: PowerShell converts them to the ZipArchiveMode/CompressionLevel enums,
# and this avoids TypeNotFound when the enum assembly is not loaded yet (Windows PowerShell 5.1)
$zip = [System.IO.Compression.ZipFile]::Open($unsignedApp, 'Create')
try {
  foreach ($src in @(@{ Path = $pac; Name = 'pac.json' }, @{ Path = $packInfo; Name = 'pack.info' }, @{ Path = $hap; Name = 'entry-default.hap' })) {
    [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $src.Path, $src.Name, 'Optimal')
  }
} finally { $zip.Dispose() }
Step ("unsigned app container: " + $unsignedApp + " (" + (Get-Item $unsignedApp).Length + " bytes)")

if ($NoSign) {
  Step 'NoSign given: stopping before app signing'
  exit 0
}

# 4) keystore password (never written to disk)
$secure = Read-Host -AsSecureString 'keystore password (lockwarden.p12)'
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try { $pwd = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }

# 5) sign the app container
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$signedApp = Join-Path $outDir 'LockWarden-release-signed.app'
if (Test-Path $signedApp) { Remove-Item $signedApp -Force }
Step 'signing .app'
$signLog = (& $java -jar $signTool sign-app `
  -keyAlias $Alias `
  -signAlg 'SHA256withECDSA' `
  -mode 'localSign' `
  -appCertFile $CerFile `
  -profileFile $ProfileFile `
  -inFile $unsignedApp `
  -outFile $signedApp `
  -keystoreFile $Keystore `
  -keystorePwd $pwd `
  -keyPwd $pwd 2>&1 | Out-String)
$signLog.Trim().Split("`n") | Select-String -Pattern 'sign-app success|ERROR' | ForEach-Object { Write-Host $_.Line }
if ($LASTEXITCODE -ne 0) { throw "sign-app failed with exit code $LASTEXITCODE" }

# 6) verify: outer app, inner hap, profile
$vc = Join-Path $work 'verify.cer'
$vp = Join-Path $work 'verify.p7b'
Step 'verify outer .app'
$out = (& $java -jar $signTool verify-app -inFile $signedApp -outCertChain $vc -outProfile $vp 2>&1 | Out-String)
$out | Select-String -Pattern 'verify-app success|verify-app failed|ERROR' | ForEach-Object { Write-Host $_.Line }
if (-not ($out -match 'verify-app success')) { throw 'outer .app verification failed' }

Step 'verify inner HAP (must contain a signature block)'
$inner = Join-Path $work 'inner-check.hap'
$zip = [System.IO.Compression.ZipFile]::OpenRead($signedApp)
try { [System.IO.Compression.ZipFileExtensions]::ExtractToFile($zip.GetEntry('entry-default.hap'), $inner, $true) } finally { $zip.Dispose() }
$outHap = (& $java -jar $signTool verify-app -inFile $inner -outCertChain (Join-Path $work 'inner.cer') -outProfile (Join-Path $work 'inner.p7b') 2>&1 | Out-String)
$outHap | Select-String -Pattern 'Digest verify result|verify-app success|verify-app failed|No Hap Signing Block' | ForEach-Object { Write-Host $_.Line }
if (-not ($outHap -match 'Digest verify result: true')) { throw 'inner HAP is not signed - do not upload' }

Step 'profile check'
& $java -jar $signTool verify-profile -inFile $vp -outFile (Join-Path $work 'profile.json') 2>&1 | Out-Null
Write-Host (Get-Content (Join-Path $work 'profile.json') -Raw | Select-String -Pattern '"type":"[a-z]+"|"issuer":"[^"]+"' -AllMatches | ForEach-Object { $_.Matches.Value })

# 7) publish to dist
$distApp = Join-Path $project 'dist\LockWarden-1.1.0-release-signed.app'
Copy-Item $signedApp $distApp -Force
Step ('done: ' + $distApp + ' (' + (Get-Item $distApp).Length + ' bytes)')
Write-Host ('[pack] sha256: ' + (Get-FileHash $distApp -Algorithm SHA256).Hash)

# 8) final gate: same checker used before uploading
$checker = Join-Path $project 'tools\check-app.ps1'
if (Test-Path $checker) {
  Step 'final pre-upload check'
  & powershell -NoProfile -ExecutionPolicy Bypass -File $checker -App $distApp
  if ($LASTEXITCODE -ne 0) { throw 'pre-upload check failed - do not upload' }
}
