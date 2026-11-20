# Pre-upload check for an AppGallery .app package.
#
# Rejects a package that would fail AGC review with 993 ("invalid profile"):
#   - outer .app signature missing/invalid
#   - inner HAP has no signing block (hvigor assembleApp packs an UNSIGNED hap)
#   - profile is not a release/app_gallery profile
#   - bundle name / version mismatch
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\check-app.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\check-app.ps1 -App <path>
#
# Exit code 0 = safe to upload, 1 = do not upload.
# NOTE: keep this file ASCII-only.

param(
  [string]$App = '',
  [string]$Bundle = 'com.example.lockwarden'
)

# java.exe logs to stderr; PowerShell treats that as a native error under 'Stop'.
$ErrorActionPreference = 'Continue'
$DevEco = 'C:\Program Files\Huawei\DevEco Studio'
$java = Join-Path $DevEco 'jbr\bin\java.exe'
$signTool = Join-Path $DevEco 'sdk\default\openharmony\toolchains\lib\hap-sign-tool.jar'
$project = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($App)) {
  $App = Join-Path $project 'dist\LockWarden-1.1.0-release-signed.app'
}
$work = Join-Path $project 'build\check'
New-Item -ItemType Directory -Force -Path $work | Out-Null
$fail = @()

function Ok([string]$text) { Write-Host ("  [OK]   " + $text) }
function Bad([string]$text) { Write-Host ("  [FAIL] " + $text); $script:fail += $text }

Write-Host ("checking: " + $App)
if (-not (Test-Path $App)) { Write-Host '  [FAIL] package not found'; exit 1 }
Write-Host ("size: " + (Get-Item $App).Length + " bytes")

# 1) outer .app signature
$cer = Join-Path $work 'app.cer'
$p7b = Join-Path $work 'app.p7b'
$out = (& $java -jar $signTool verify-app -inFile $App -outCertChain $cer -outProfile $p7b 2>&1 | Out-String)
if ($out -match 'verify-app success') { Ok 'outer .app signature' } else { Bad 'outer .app signature' }

# 2) inner HAP signature (the 993 trap)
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($App)
$hapNames = @()
foreach ($e in $zip.Entries) { if ($e.Name -like '*.hap') { $hapNames += $e.FullName } }
if ($hapNames.Count -eq 0) {
  $zip.Dispose()
  Bad 'package contains no HAP'
} else {
  foreach ($name in $hapNames) {
    $inner = Join-Path $work 'inner.hap'
    $entry = $zip.GetEntry($name)
    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $inner, $true)
    $outHap = (& $java -jar $signTool verify-app -inFile $inner -inForm zip -outCertChain (Join-Path $work 'hap.cer') -outProfile (Join-Path $work 'hap.p7b') 2>&1 | Out-String)
    if ($outHap -match 'Find Hap Signing Block success' -and $outHap -match 'Digest verify result: true') {
      Ok ("inner HAP signed: " + $name)
    } else {
      Bad ("inner HAP NOT signed: " + $name + " (upload would fail with 993)")
    }
  }
  $zip.Dispose()
}

# 3) profile type / issuer / bundle / version
if (Test-Path $p7b) {
  & $java -jar $signTool verify-profile -inFile $p7b -outFile (Join-Path $work 'profile.json') 2>&1 | Out-Null
  $p = Get-Content (Join-Path $work 'profile.json') -Raw | ConvertFrom-Json
  $c = $p.content
  if ($c.type -eq 'release') { Ok ('profile type: ' + $c.type) } else { Bad ('profile type is ' + $c.type) }
  if ($c.issuer -eq 'app_gallery') { Ok ('profile issuer: ' + $c.issuer) } else { Bad ('profile issuer is ' + $c.issuer) }
  if ($c.'bundle-info'.'bundle-name' -eq $Bundle) { Ok ('profile bundle: ' + $c.'bundle-info'.'bundle-name') } else { Bad ('profile bundle mismatch: ' + $c.'bundle-info'.'bundle-name') }
  $notAfter = [DateTimeOffset]::FromUnixTimeSeconds([int64]$c.validity.'not-after').LocalDateTime
  if ($notAfter -gt (Get-Date)) { Ok ('profile valid until: ' + $notAfter.ToString('yyyy-MM-dd')) } else { Bad ('profile expired: ' + $notAfter.ToString('yyyy-MM-dd')) }
} else {
  Bad 'profile not readable from package'
}

# 4) version info in pack.info (regex on raw text: avoids ConvertFrom-Json quirks)
$zip = [System.IO.Compression.ZipFile]::OpenRead($App)
$infoEntry = $zip.GetEntry('pack.info')
if ($infoEntry -ne $null) {
  $reader = New-Object System.IO.StreamReader($infoEntry.Open())
  $txt = $reader.ReadToEnd()
  $reader.Close()
  if ($txt -match '"bundleName"\s*:\s*"([^"]+)"') {
    $packBundle = $matches[1]
    if ($packBundle -eq $Bundle) { Ok ('pack.info bundle: ' + $packBundle) } else { Bad ('pack.info bundle mismatch: ' + $packBundle) }
  } else { Bad 'pack.info has no bundleName' }
  $vName = ''
  $vCode = ''
  if ($txt -match '"name"\s*:\s*"([0-9][^"]*)"') { $vName = $matches[1] }
  if ($txt -match '"code"\s*:\s*([0-9]+)') { $vCode = $matches[1] }
  if ($vName -ne '' -and $vCode -ne '') { Ok ('pack.info version: ' + $vName + ' / ' + $vCode) } else { Bad 'pack.info version not found' }
}
$zip.Dispose()

Write-Host ''
if ($fail.Count -gt 0) {
  Write-Host ('RESULT: DO NOT UPLOAD (' + $fail.Count + ' problem(s))')
  exit 1
}
Write-Host 'RESULT: OK to upload'
exit 0
