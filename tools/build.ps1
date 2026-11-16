# Build the VaultWarden HarmonyOS client from the command line.
# Equivalent to DevEco Studio "Build Hap".
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools\build.ps1 [-Clean] [-Release] [-App]
#   -App builds a .app pack (needed when uploading to AppGallery Connect) instead of a HAP.
#
# NOTE: keep this file ASCII-only. Windows PowerShell 5.1 reads BOM-less files as ANSI,
# and non-ASCII comments can corrupt parsing.
param(
  [switch]$Clean,
  # Use -Release to build the release package (needs a release signing config for store upload)
  [switch]$Release,
  # Use -App to build the .app pack for AppGallery Connect upload
  [switch]$App
)

$DevEco = 'C:\Program Files\Huawei\DevEco Studio'
$nodeExe = Join-Path $DevEco 'tools\node\node.exe'
$hvigorw = Join-Path $DevEco 'tools\hvigor\bin\hvigorw.js'
$env:PATH = "$DevEco\jbr\bin;$DevEco\tools\node;$env:PATH"
$env:DEVECO_SDK_HOME = Join-Path $DevEco 'sdk'
$env:NODE_HOME = Join-Path $DevEco 'tools\node'

$project = Split-Path -Parent $PSScriptRoot
Set-Location $project
$log = Join-Path $project 'build.log'
$errLog = Join-Path $project 'build.err.log'

if ($Clean) {
  Write-Host '[build] cleaning previous outputs'
  Remove-Item -Recurse -Force (Join-Path $project 'entry\build') -ErrorAction SilentlyContinue
  Remove-Item -Recurse -Force (Join-Path $project 'build') -ErrorAction SilentlyContinue
}

# Quote every argument that may contain spaces; Start-Process does not quote for us.
$mode = if ($Release) { 'release' } else { 'debug' }
$task = if ($App) { 'assembleApp' } else { 'assembleHap' }
# assembleApp only exists in project mode; assembleHap works in module mode
$scope = if ($App) { 'project' } else { 'module' }
# -Release builds the product that uses the AppGallery release certificate,
# everything else uses the debug (auto-sign) product so hdc/DevEco can install it.
$product = if ($Release) { 'release' } else { 'default' }
$argLine = '"{0}" --mode {1} -p product={4} -p buildMode={2} {3} --no-daemon' -f $hvigorw, $scope, $mode, $task, $product

$proc = Start-Process -FilePath $nodeExe -ArgumentList $argLine -NoNewWindow -Wait -PassThru `
  -RedirectStandardOutput $log -RedirectStandardError $errLog
$code = $proc.ExitCode

$all = @()
if (Test-Path $log) { $all += Get-Content $log }
if (Test-Path $errLog) { $all += Get-Content $errLog }
$all | Where-Object { $_ -match 'ERROR|Error Message|COMPILE RESULT|BUILD (SUCCESSFUL|FAILED)' } |
  Select-Object -First 40 | ForEach-Object { Write-Host $_ }

$warn = @($all | Where-Object { $_ -match 'WARN' }).Count
Write-Host ''
Write-Host ("[build] hvigor exit code: {0}, warning lines: {1}" -f $code, $warn)
Write-Host ("[build] full log: {0}" -f $log)

$found = @()
$found += Get-ChildItem (Join-Path $project 'entry\build') -Filter '*.hap' -Recurse -ErrorAction SilentlyContinue
$found += Get-ChildItem (Join-Path $project 'build\outputs') -Filter '*.app' -Recurse -ErrorAction SilentlyContinue
if ($found.Count -gt 0) {
  foreach ($f in $found) { Write-Host ("[build] artifact: {0} ({1:N0} bytes)" -f $f.FullName, $f.Length) }
} else {
  Write-Host '[build] no HAP/APP found'
}
exit $code
