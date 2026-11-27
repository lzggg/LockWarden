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
# NOTE: keep this file ASCII-only.

$ErrorActionPreference = 'Continue'
$project = Split-Path -Parent $PSScriptRoot

Write-Host ''
Write-Host '=== 1/2 build release HAP ==='
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $project 'tools\build.ps1') -Clean -Release
if ($LASTEXITCODE -ne 0) {
  Write-Host '[release] build failed, stop'
  exit 1
}

Write-Host ''
Write-Host '=== 2/2 pack + sign .app (keystore password will be asked) ==='
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $project 'tools\pack-app.ps1')
if ($LASTEXITCODE -ne 0) {
  Write-Host '[release] pack/sign failed, stop'
  exit 1
}

$dist = Join-Path $project 'dist\LockWarden-1.1.0-release-signed.app'
if (Test-Path $dist) {
  Write-Host ''
  Write-Host ('[release] ready to upload: ' + $dist)
  Write-Host ('[release] size: ' + (Get-Item $dist).Length + ' bytes')
} else {
  Write-Host '[release] dist package missing'
  exit 1
}
