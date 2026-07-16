#!/usr/bin/env pwsh
# Export an Android debug APK, and optionally install/launch it on a connected device.
# Requires the Android SDK, Godot Android export templates and the "Android" export
# preset (see the Android setup section of docs/initial_briefing.md).
# Usage: pwsh tools/export_android.ps1 [-Install] [-Run] [-Logcat]

param(
    [switch]$Install,
    [switch]$Run,
    [switch]$Logcat
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot

function Resolve-Godot {
    if ($env:GODOT -and (Test-Path $env:GODOT)) { return $env:GODOT }
    $known = "C:\Tools\Godot\4.7.1\Godot_v4.7.1-stable_win64_console.exe"
    if (Test-Path $known) { return $known }
    $cmd = Get-Command godot -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw "Godot executable not found. Set the GODOT env var to the console build."
}

function Resolve-Adb {
    if ($env:ADB -and (Test-Path $env:ADB)) { return $env:ADB }
    $cmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $known = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
    if (Test-Path $known) { return $known }
    throw "adb not found. Set the ADB env var or add platform-tools to PATH."
}

$appId = "com.ntxgames.outpost.godot"
$apk = Join-Path $projectRoot "build\android\the-outpost-debug.apk"
$godot = Resolve-Godot

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $apk) | Out-Null

Write-Host "Exporting Android debug APK with: $godot"
& $godot --headless --path $projectRoot --export-debug "Android" $apk
if ($LASTEXITCODE -ne 0) { throw "Godot export failed (exit $LASTEXITCODE)." }
if (-not (Test-Path $apk)) { throw "Export reported success but no APK was produced at $apk." }

$sizeMb = [math]::Round((Get-Item $apk).Length / 1MB, 2)
Write-Host "APK: $apk ($sizeMb MB)"

if (-not ($Install -or $Run -or $Logcat)) { exit 0 }

$adb = Resolve-Adb

# Godot shuts the adb server down when it exits (export/android/shutdown_adb_on_exit),
# so straight after an export the daemon is cold and needs a moment to see the device.
$devices = $null
foreach ($attempt in 1..5) {
    $devices = & $adb devices | Select-Object -Skip 1 | Where-Object { $_ -match "\sdevice$" }
    if ($devices) { break }
    Start-Sleep -Seconds 2
}
if (-not $devices) {
    throw "No authorized device found. Connect the phone, enable USB debugging and accept the prompt."
}

Write-Host "Installing on device..."
& $adb install -r $apk
if ($LASTEXITCODE -ne 0) { throw "adb install failed (exit $LASTEXITCODE)." }

if ($Run -or $Logcat) {
    & $adb shell monkey -p $appId -c android.intent.category.LAUNCHER 1 | Out-Null
    Write-Host "Launched $appId"
}

if ($Logcat) {
    Write-Host "Streaming logcat (Ctrl+C to stop)..."
    & $adb logcat -s godot:V GodotApp:V AndroidRuntime:E
}

exit 0
