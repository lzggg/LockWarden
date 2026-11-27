# Install the HAP on a device (tablet) and verify it launches.
# If the signing profile does not include this device, print what to do instead.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools\install_tablet.ps1 [-Device <serial>]

param(
  # 不传则自动取第一个非模拟器设备；也可显式指定 hdc 序列号
  [string]$Device = ''
)

$root = Split-Path -Parent $PSScriptRoot
$hdcExe = Join-Path 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains' 'hdc.exe'
if (-not $Device) {
  $Device = (& $hdcExe list targets 2>$null | Where-Object { $_ -and $_ -notmatch '^127\.0\.0\.1:' } | Select-Object -First 1)
}
if (-not $Device) { Write-Host '[install] 未找到已连接设备，请用 -Device <序列号> 指定'; exit 1 }
$hdc = Join-Path 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains' 'hdc.exe'
$hap = Join-Path $root 'entry\build\default\outputs\default\entry-default-signed.hap'
$bundle = 'com.example.lockwarden'

function Get-Udid([string]$dev) {
  $out = & $hdc -t $dev shell bm get -u 2>&1 | Out-String
  $m = [regex]::Match($out, '([0-9A-Fa-f]{32,})')
  if ($m.Success) { return $m.Groups[1].Value }
  return ''
}

function Get-ProfileIds {
  $dir = Join-Path $env:USERPROFILE '.ohos\config'
  $p7b = Get-ChildItem $dir -Filter '*.p7b' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $p7b) { return @() }
  $bytes = [System.IO.File]::ReadAllBytes($p7b.FullName)
  $text = [System.Text.Encoding]::GetEncoding('ISO-8859-1').GetString($bytes)
  $ids = [regex]::Matches($text, '"([0-9A-Fa-f]{16,})"') | ForEach-Object { $_.Groups[1].Value }
  Write-Host ("[profile] {0} ({1})" -f $p7b.Name, $p7b.LastWriteTime)
  return $ids
}

$udid = Get-Udid $Device
if (-not $udid) {
  Write-Host "[fail] cannot read device UDID; check 'hdc list targets'"
  exit 1
}
Write-Host ("[device] {0}  UDID: {1}" -f $Device, $udid)

$ids = Get-ProfileIds
if ($ids -notcontains $udid) {
  Write-Host ''
  Write-Host '[block] this device is not registered in the debug signing profile,'
  Write-Host '        so install will be rejected with code 9568423.'
  Write-Host '        In DevEco Studio: File > Project Structure > Signing Configs'
  Write-Host '        uncheck "Automatically generate signature", Apply,'
  Write-Host '        then check it again, Apply. DevEco registers connected devices.'
  Write-Host ''
  Write-Host ('        Or add this UDID in AGC manually: {0}' -f $udid)
  exit 2
}

if (-not (Test-Path $hap)) {
  Write-Host '[build] HAP not found, building'
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'build.ps1')
}

Write-Host '[install] installing to device'
& $hdc -t $Device install -r $hap
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host '[launch] starting ability'
& $hdc -t $Device shell aa force-stop $bundle | Out-Null
& $hdc -t $Device shell aa start -a EntryAbility -b $bundle
Start-Sleep -Seconds 5

$shot = '/data/local/tmp/tablet-launch.jpeg'
& $hdc -t $Device shell snapshot_display -f $shot | Out-Null
$local = Join-Path (Split-Path -Parent $root) 'docs\tablet-launch.jpeg'
& $hdc -t $Device file recv $shot $local | Out-Null
Write-Host ("[shot] {0}" -f $local)

Write-Host '[log] recent app errors (if any)'
& $hdc -t $Device shell hilog -x 2>&1 |
  Select-String -Pattern 'lockwarden' |
  Select-String -Pattern 'Error|error|Exception|crash' |
  Select-Object -Last 10 |
  ForEach-Object { $_.Line.Trim() }
