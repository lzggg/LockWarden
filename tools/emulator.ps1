# Start / stop HarmonyOS emulators WITHOUT a flashing cmd window.
#
# Emulator.exe is a console program, so a plain Start-Process pops up a black
# console. We launch it with -WindowStyle Hidden: the console stays hidden while
# the emulator's own GUI window still appears.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\emulator.ps1 -List
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\emulator.ps1 -Name "MatePad Pro 13"
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\emulator.ps1 -Name "MateBook Pro" -Headless
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\emulator.ps1 -Stop "MatePad Pro 13"
#
# NOTE: keep this file ASCII-only.

param(
  [string]$Name = '',
  [string]$Stop = '',
  [switch]$List,
  [switch]$Headless
)

$ErrorActionPreference = 'Continue'
$exe = 'C:\Program Files\Huawei\DevEco Studio\tools\emulator\Emulator.exe'
$instancePath = 'C:/Users/user/AppData/Local/Huawei/Emulator/deployed'
$imageRoot = 'C:/Users/user/AppData/Local/Huawei/Sdk'

if (-not (Test-Path $exe)) { Write-Host "emulator not found: $exe"; exit 1 }

if ($List -or ($Name -eq '' -and $Stop -eq '')) {
  & $exe -list
  exit 0
}

if ($Stop -ne '') {
  & $exe -stop $Stop
  Write-Host ("stopped: " + $Stop)
  exit 0
}

$argLine = '-start "' + $Name + '" -instancePath "' + $instancePath + '" -imageRoot "' + $imageRoot + '"'
if ($Headless) { $argLine += ' -noWindow' }

# -WindowStyle Hidden keeps the console window out of sight; the emulator GUI is separate.
Start-Process -FilePath $exe -ArgumentList $argLine -WindowStyle Hidden | Out-Null
Write-Host ("starting: " + $Name + $(if ($Headless) { ' (headless)' } else { '' }))
