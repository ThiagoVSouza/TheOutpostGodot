# Build the outpost_llama GDExtension (M6): binds libllama in-process, because
# M2's subprocess+HTTP transport cannot ship on mobile (iOS forbids subprocesses,
# Android blocks exec from app data).
#
# Everything this produces is gitignored and reproducible: godot-cpp, the pinned
# llama.cpp headers, the generated import libs, and ~1.1 GiB of runtime DLLs.
# Run it once on a fresh clone, and again after changing gdextension/src.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools/setup_gdextension.ps1
#
# Requires: Visual Studio 2022 (MSVC x64), Python with scons, git, and a
# llama.cpp binary release at $LlamaDir. Godot is located via $env:GODOT or the
# known 4.7.1 path, matching tools/test.ps1.

[CmdletBinding()]
param(
    # The prebuilt llama.cpp release we link against. The headers are fetched at
    # the SAME commit: llama.h describes a C ABI, and a header from a different
    # build silently mismatches the DLL's struct layouts.
    [string]$LlamaDir = "C:/Tools/llama.cpp/b10042",
    [string]$LlamaCommit = "3f08ef2c5",
    [switch]$SkipGodotCpp
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$GdextDir = Join-Path $RepoRoot "gdextension"
$ThirdParty = Join-Path $GdextDir "thirdparty"
$LlamaInc = Join-Path $ThirdParty "llama/include"
$LlamaLib = Join-Path $ThirdParty "llama/lib"
$BuildTmp = Join-Path $GdextDir "build_tmp"
$AddonBin = Join-Path $RepoRoot "addons/outpost_llama/bin"

$Godot = $env:GODOT
if (-not $Godot) { $Godot = "C:/Tools/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe" }
if (-not (Test-Path $Godot)) { throw "Godot not found at '$Godot'. Set `$env:GODOT." }
if (-not (Test-Path $LlamaDir)) { throw "llama.cpp build not found at '$LlamaDir'." }

$VcVars = "C:/Program Files/Microsoft Visual Studio/2022/Community/VC/Auxiliary/Build/vcvars64.bat"
if (-not (Test-Path $VcVars)) { throw "MSVC not found at '$VcVars'." }

$Scons = (Get-Command scons -ErrorAction SilentlyContinue).Source
if (-not $Scons) {
    $Scons = Join-Path (& python -c "import sysconfig; print(sysconfig.get_path('scripts'))") "scons.exe"
}
if (-not (Test-Path $Scons)) { throw "scons not found. Install it with: pip install scons" }

function Invoke-MsvcTool([string]$CommandLine) {
    # vcvars64 must run in the same shell as the tool it configures, hence cmd /c.
    # It prints a harmless vswhere warning on this machine; only a non-zero exit matters.
    cmd /c "`"$VcVars`" >nul 2>&1 && $CommandLine"
    if ($LASTEXITCODE -ne 0) { throw "MSVC command failed ($LASTEXITCODE): $CommandLine" }
}

New-Item -ItemType Directory -Force -Path $ThirdParty, $LlamaLib, $BuildTmp, $AddonBin | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $LlamaInc "ggml/include") | Out-Null

# --- 1. godot-cpp, built against THIS Godot's own API dump -------------------
if (-not $SkipGodotCpp) {
    $GodotCpp = Join-Path $ThirdParty "godot-cpp"
    if (-not (Test-Path $GodotCpp)) {
        Write-Host "Cloning godot-cpp..." -ForegroundColor Cyan
        git clone --depth 1 https://github.com/godotengine/godot-cpp.git $GodotCpp
    }
    # Generating the API from the engine binary in hand is what keeps the
    # bindings honest: godot-cpp's checked-in extension_api.json tracks its own
    # branch, not necessarily the editor this project runs.
    Write-Host "Dumping extension_api.json from Godot..." -ForegroundColor Cyan
    Push-Location $ThirdParty
    try { & $Godot --headless --dump-extension-api | Out-Null } finally { Pop-Location }
    Copy-Item (Join-Path $ThirdParty "extension_api.json") $GodotCpp -Force

    foreach ($target in @("template_debug", "template_release")) {
        Write-Host "Building godot-cpp ($target)..." -ForegroundColor Cyan
        Push-Location $GodotCpp
        try {
            & $Scons platform=windows target=$target custom_api_file=extension_api.json -j8
            if ($LASTEXITCODE -ne 0) { throw "godot-cpp build failed ($target)" }
        } finally { Pop-Location }
    }
}

# --- 2. llama.cpp public headers, pinned to the DLL's commit ----------------
Write-Host "Fetching llama.cpp headers at $LlamaCommit..." -ForegroundColor Cyan
$RawBase = "https://raw.githubusercontent.com/ggml-org/llama.cpp/$LlamaCommit"
Invoke-WebRequest "$RawBase/include/llama.h" -OutFile (Join-Path $LlamaInc "llama.h")
foreach ($h in @("ggml.h", "ggml-backend.h", "ggml-cpu.h", "ggml-alloc.h", "ggml-opt.h", "gguf.h")) {
    Invoke-WebRequest "$RawBase/ggml/include/$h" -OutFile (Join-Path $LlamaInc "ggml/include/$h")
}

# --- 3. Import libs from the prebuilt DLLs ----------------------------------
# The llama.cpp Windows release ships DLLs but no .lib, so link stubs are
# generated from each DLL's own export table. Only plain C names are taken;
# llama.dll also exports ~20 mangled C++ internals that are not public API.
foreach ($dll in @("llama", "ggml", "ggml-base")) {
    Write-Host "Generating $dll.lib..." -ForegroundColor Cyan
    $dumpPath = Join-Path $BuildTmp "$dll.exports.txt"
    Invoke-MsvcTool "dumpbin /exports `"$LlamaDir/$dll.dll`" > `"$dumpPath`""

    $names = Get-Content $dumpPath | ForEach-Object {
        if ($_ -match '^\s*\d+\s+[0-9A-Fa-f]+\s+[0-9A-Fa-f]+\s+([A-Za-z_][A-Za-z0-9_]*)\s*$') { $matches[1] }
    }
    if (-not $names) { throw "No exports parsed from $dll.dll" }
    $defPath = Join-Path $BuildTmp "$dll.def"
    @("LIBRARY $dll", "EXPORTS") + $names | Set-Content -Encoding ASCII $defPath
    Invoke-MsvcTool "lib.exe /nologo /def:`"$defPath`" /out:`"$LlamaLib/$dll.lib`" /machine:x64"
}

# --- 4. Runtime DLLs beside the extension -----------------------------------
# ggml-cuda.dll and the CUDA runtime are optional: a machine without them still
# builds and runs, on CPU. Everything else is required.
Write-Host "Copying runtime DLLs..." -ForegroundColor Cyan
$required = @("llama.dll", "llama-common.dll", "mtmd.dll", "ggml.dll", "ggml-base.dll", "ggml-cpu-x64.dll")
$optional = @("ggml-cuda.dll", "cudart64_12.dll", "cublas64_12.dll", "cublasLt64_12.dll")
foreach ($dll in $required) {
    $src = Join-Path $LlamaDir $dll
    if (-not (Test-Path $src)) { throw "Required runtime DLL missing: $src" }
    Copy-Item $src $AddonBin -Force
}
foreach ($dll in $optional) {
    $src = Join-Path $LlamaDir $dll
    if (Test-Path $src) { Copy-Item $src $AddonBin -Force }
    else { Write-Host "  (no $dll - CPU-only build)" -ForegroundColor Yellow }
}

# --- 5. The extension itself ------------------------------------------------
foreach ($target in @("template_debug", "template_release")) {
    Write-Host "Building outpost_llama ($target)..." -ForegroundColor Cyan
    Push-Location $GdextDir
    try {
        & $Scons platform=windows target=$target -j8
        if ($LASTEXITCODE -ne 0) { throw "outpost_llama build failed ($target)" }
    } finally { Pop-Location }
}

Write-Host ""
Write-Host "Done. Verify with:" -ForegroundColor Green
Write-Host '  $env:OUTPOST_AI_BACKEND="in-process-llama"; $env:OUTPOST_MODEL_PROFILE="gemma_e2b_desktop_cuda"'
