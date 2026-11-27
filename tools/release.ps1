# One-shot release pipeline: build release HAP -> pack & sign .app -> verify.
#
# hvigor's assembleApp packs an UNSIGNED HAP, so building the .app directly always
# fails AGC review with 993. This script builds the signed HAP, then packs/signs
# the .app properly (prompts for the keystore password).
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\release.ps1
#
# Output:
#   dist\LockWarden-<version>-release-signed.app   (the file to upload)
#
# Options:
#   -ProfileFile <p>  default: <project>\Key\LockWardenRelease.p7b
#
# NOTE: keep this file ASCII-only.

param(
  [string]$ProfileFile = '',
  [string]$CerFile = '',
  [string]$Keystore = ''
)

$ErrorActionPreference = 'Continue'
$project = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Keystore)) { $Keystore = Join-Path $project 'Key\LockWarden.p12' }
if ([string]::IsNullOrWhiteSpace($CerFile)) { $CerFile = Join-Path $project 'Key\LockWarden.cer' }
if ([string]::IsNullOrWhiteSpace($ProfileFile)) { $ProfileFile = Join-Path $project 'Key\LockWardenRelease.p7b' }
if (-not (Test-Path $ProfileFile)) { Write-Host ('[release] profile missing: ' + $ProfileFile); exit 1 }

Write-Host ''
Write-Host '=== 1/2 build release HAP ==='
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $project 'tools\build.ps1') -Clean -Release
if ($LASTEXITCODE -ne 0) {
  Write-Host '[release] build failed, stop'
  exit 1
}

Write-Host ''
Write-Host '=== 2/2 pack + sign .app (keystore password will be asked) ==='
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $project 'tools\pack-app.ps1') -ProfileFile $ProfileFile -CerFile $CerFile -Keystore $Keystore
if ($LASTEXITCODE -ne 0) {
  Write-Host '[release] pack/sign failed, stop'
  exit 1
}

$appJson = Get-Content (Join-Path $project 'AppScope\app.json5') -Raw
$versionMatch = [regex]::Match($appJson, '"versionName"\s*:\s*"([^"]+)"')
$version = if ($versionMatch.Success) { $versionMatch.Groups[1].Value } else { 'unknown' }
$dist = Join-Path $project ("dist\LockWarden-" + $version + "-release-signed.app")
if (Test-Path $dist) {
  Write-Host ''
  Write-Host ('[release] ready to upload: ' + $dist)
  Write-Host ('[release] size: ' + (Get-Item $dist).Length + ' bytes')
} else {
  Write-Host '[release] dist package missing'
  exit 1
}
