#!/usr/bin/env pwsh
# Run the GUT test suite headless and exit non-zero on failure.
# Usage: pwsh tools/test.ps1

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

$godot = Resolve-Godot
Write-Host "Running GUT with: $godot"

# Opt out of AiTraceWriter's dev-build default (A1, D21): without this, every test run
# that drives a real orchestration writes JSONL/Markdown trace files into this machine's
# real user:// data dir, forever (no retention policy yet). Tests that exercise the
# writer itself are unaffected — they construct their own, pointed at a scratch dir.
$env:OUTPOST_TEST_RUN = "1"

& $godot --headless --path $projectRoot `
    -s res://addons/gut/gut_cmdln.gd `
    -gconfig=res://tests/.gutconfig.json

exit $LASTEXITCODE
