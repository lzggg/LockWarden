# Regenerate build-profile.json5 with your LOCAL signing credentials.
#
#   powershell -File tools\fix-signing.ps1            # inject credentials
#   powershell -File tools\fix-signing.ps1 -Restore   # strip them again before committing
#
# Why: build-profile.json5 is committed to a public repo, so it must never carry
# certs / keystore paths / passwords. Keep them in signing.local.json5 instead
# (git-ignored). Template: docs/signing.example.json5
#
# Keep this file ASCII-only: Windows PowerShell 5.1 reads BOM-less files as ANSI
# and non-ASCII comments can corrupt parsing.

param(
  [switch]$Restore,
  [string]$ConfigFile = 'signing.local.json5'
)

$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$profilePath = Join-Path $project 'build-profile.json5'
$configPath = if ([System.IO.Path]::IsPathRooted($ConfigFile)) { $ConfigFile } else { Join-Path $project $ConfigFile }

# JSON5 -> JSON: drop /* */ blocks and // line comments, then trailing commas.
function ConvertFrom-Json5([string]$text) {
  $t = [regex]::Replace($text, '(?s)/\*.*?\*/', '')
  $t = [regex]::Replace($t, '(?m)//.*$', '')
  $t = [regex]::Replace($t, ',(\s*[}\]])', '$1')
  return $t
}

function Assert-Material([string]$name, [object]$material) {
  if ($null -eq $material) { throw "[fix-signing] $name has no material block" }
  foreach ($field in 'certpath', 'keyAlias', 'keyPassword', 'profile', 'storeFile', 'storePassword') {
    $value = [string]$material.$field
    if ([string]::IsNullOrWhiteSpace($value)) { throw "[fix-signing] $name.material.$field is empty" }
    if ($value -match '<.*>') { throw "[fix-signing] $name.material.$field still holds a <placeholder> ($value)" }
  }
  foreach ($field in 'certpath', 'storeFile', 'profile') {
    $path = [string]$material.$field
    if (-not (Test-Path -LiteralPath $path)) { Write-Host "[fix-signing] warning: $field not found: $path" }
  }
}

# ConvertFrom-Json yields PSCustomObject trees; Format-Json walks hashtables.
function ConvertTo-Plain([object]$value) {
  if ($null -eq $value) { return $null }
  if ($value -is [System.Management.Automation.PSCustomObject]) {
    $map = [ordered]@{}
    foreach ($prop in $value.PSObject.Properties) { $map[$prop.Name] = ConvertTo-Plain $prop.Value }
    return $map
  }
  if ($value -is [string]) { return $value }
  if ($value -is [System.Collections.IEnumerable]) {
    return @(foreach ($item in $value) { ConvertTo-Plain $item })
  }
  return $value
}

# Pretty-printer: ConvertTo-Json in PowerShell 5.1 aligns colons and blows up
# small structures; this emits stable 2-space indented JSON5 that diffs well.
function Format-Json([object]$value, [int]$indent = 0) {
  $pad = ' ' * $indent
  $inner = ' ' * ($indent + 2)
  if ($null -eq $value) { return 'null' }
  if ($value -is [bool]) { if ($value) { return 'true' } else { return 'false' } }
  if ($value -is [string]) { return (ConvertTo-Json $value -Compress) }
  if ($value -is [System.Collections.IDictionary]) {
    if ($value.Count -eq 0) { return '{}' }
    $lines = foreach ($key in $value.Keys) {
      $inner + (ConvertTo-Json ([string]$key) -Compress) + ': ' + (Format-Json $value[$key] ($indent + 2))
    }
    return "{`n" + ($lines -join ",`n") + "`n$pad}"
  }
  if ($value -is [System.Collections.IEnumerable]) {
    $items = @($value)
    if ($items.Count -eq 0) { return '[]' }
    $lines = foreach ($item in $items) { $inner + (Format-Json $item ($indent + 2)) }
    return "[`n" + ($lines -join ",`n") + "`n$pad]"
  }
  return (ConvertTo-Json $value -Compress)
}

function Get-SigningNames([object]$configs) {
  return @(foreach ($cfg in @($configs)) { [string]$cfg['name'] })
}

function New-Product([string]$name, [object]$configs) {
  $p = [ordered]@{
    name                 = $name
    compatibleSdkVersion = '26.0.0'
    targetSdkVersion     = '26.0.0'
    runtimeOS            = 'HarmonyOS'
    buildOption          = [ordered]@{
      strictMode = [ordered]@{ caseSensitiveCheck = $true; useNormalizedOHMUrl = $true }
    }
  }
  if ((Get-SigningNames $configs) -contains $name) { $p['signingConfig'] = $name }
  return $p
}

# ---- load local credentials -------------------------------------------------

$signingConfigs = @()
if (-not $Restore) {
  if (-not (Test-Path -LiteralPath $configPath)) {
    throw "[fix-signing] missing $configPath - copy docs/signing.example.json5 to it and fill in your own values"
  }
  $parsed = (ConvertFrom-Json5 (Get-Content -LiteralPath $configPath -Raw)) | ConvertFrom-Json
  if ($null -eq $parsed.signingConfigs -or @($parsed.signingConfigs).Count -eq 0) {
    throw "[fix-signing] $configPath defines no signingConfigs"
  }
  foreach ($cfg in @($parsed.signingConfigs)) { Assert-Material $cfg.name $cfg.material }
  $signingConfigs = @(ConvertTo-Plain $parsed.signingConfigs)
}

# ---- emit -------------------------------------------------------------------

$doc = [ordered]@{
  app     = [ordered]@{
    signingConfigs = $signingConfigs
    products       = @((New-Product 'default' $signingConfigs), (New-Product 'release' $signingConfigs))
    buildModeSet   = @([ordered]@{ name = 'debug' }, [ordered]@{ name = 'release' })
  }
  modules = @([ordered]@{
      name    = 'entry'
      srcPath = './entry'
      targets = @([ordered]@{ name = 'default'; applyToProducts = @('default', 'release') })
    })
}

$header = @'
// Build profile for the HarmonyOS (Stage model) project.
//
// Signing material is NOT stored in this repo: certs, .p12 keystores and
// passwords are local credentials - leaking them lets anyone sign as you.
// Two ways to provide them locally:
//   1) DevEco Studio: File > Project Structure > Signing Configs, tick
//      "Automatically generate signature", Apply. The IDE writes this file.
//   2) Command line: copy docs/signing.example.json5 to signing.local.json5
//      (git-ignored), fill in your own paths/passwords, then run
//        powershell -File tools\fix-signing.ps1
//      and run it with -Restore before committing again.
//
// Regenerated by tools/fix-signing.ps1 - do not hand-edit signing values here.
'@

$json = $header + "`n" + (Format-Json $doc) + "`n"
[System.IO.File]::WriteAllText($profilePath, $json, (New-Object System.Text.UTF8Encoding($false)))

if ($Restore) {
  Write-Host '[fix-signing] build-profile.json5 restored: signing configs stripped (safe to commit)'
} else {
  Write-Host ('[fix-signing] build-profile.json5 written: signing configs = {0}' -f ((Get-SigningNames $signingConfigs) -join ', '))
}
Write-Host '[fix-signing] build (debug): tools\build.ps1 -Clean     build (store): tools\build.ps1 -Clean -Release -App'
