# One-shot release pipeline: build signed HAP + signed .app -> verify -> copy to dist.
#
# hvigor's plain assembleApp packs the unsigned HAP into LockWarden-release-signed.app.
# With buildOption.packOptions.appWithSignedPkg=true it also emits
# LockWarden-release-all-signed.app, which contains the signed HAP and is the file to upload.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\release.ps1
#
# Output:
#   dist\LockWarden-<version>-release-signed.app
#
# NOTE: keep this file ASCII-only.

param()

$ErrorActionPreference = 'Continue'
$DevEco = 'C:\Program Files\Huawei\DevEco Studio'
$project = Split-Path -Parent $PSScriptRoot

Write-Host ''
Write-Host '=== 1/3 build release .app ==='
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $project 'tools\build.ps1') -Clean -Release -App
if ($LASTEXITCODE -ne 0) {
  Write-Host '[release] build failed, stop'
  exit 1
}

$app = Join-Path $project 'build\outputs\release\LockWarden-release-all-signed.app'
if (-not (Test-Path $app)) {
  Write-Host ('[release] signed app missing: ' + $app)
  Write-Host '[release] check build-profile.json5 release buildOption.packOptions.appWithSignedPkg=true'
  exit 1
}

$appJson = Get-Content (Join-Path $project 'AppScope\app.json5') -Raw
$versionMatch = [regex]::Match($appJson, '"versionName"\s*:\s*"([^"]+)"')
$version = if ($versionMatch.Success) { $versionMatch.Groups[1].Value } else { 'unknown' }
$distDir = Join-Path $project 'dist'
New-Item -ItemType Directory -Force -Path $distDir | Out-Null
$dist = Join-Path $distDir ("LockWarden-" + $version + "-release-signed.app")
Copy-Item $app $dist -Force

Write-Host ''
Write-Host '=== 2/3 verify .app ==='
$java = Join-Path $DevEco 'jbr\bin\java.exe'
$jar = Join-Path $DevEco 'sdk\default\openharmony\toolchains\lib\hap-sign-tool.jar'
$tmpCert = Join-Path $env:TEMP 'lockwarden-release-cert.cer'
$tmpProfile = Join-Path $env:TEMP 'lockwarden-release-profile.p7b'
$verify = & $java -jar $jar verify-app -inFile $dist -inForm zip -outCertChain $tmpCert -outProfile $tmpProfile 2>&1
$verify | Select-String -Pattern 'verify-app' | ForEach-Object { $_.Line.Trim() }
Remove-Item $tmpCert, $tmpProfile -Force -ErrorAction SilentlyContinue
if (-not ($verify -match 'verify-app success')) {
  Write-Host '[release] verify failed, stop'
  exit 1
}

Write-Host ''
Write-Host '=== 3/3 done ==='
Write-Host ('[release] ready to upload: ' + $dist)
Write-Host ('[release] size: ' + (Get-Item $dist).Length + ' bytes')
