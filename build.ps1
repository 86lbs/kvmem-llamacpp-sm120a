#Requires -Version 5.1
<#
.SYNOPSIS
    Build llama-kvmem-server.exe for Windows (CUDA, sm_120a by default) from KVMem + llama.cpp sources.

.DESCRIPTION
    Reproducible build for the KVMem llama.cpp worker. Encodes the pitfalls discovered while
    building for RTX 50 series (sm_120a):
      - git submodule clone can hang in non-interactive contexts -> uses codeload tarball + git apply
      - prepare-backends.py needs a real python -> bypassed, patches applied directly
      - CUDA component installs may omit crt/nvvm -> preflight check with instructions

.PARAMETER RepoRoot
    Working directory for sources and build output. Created if missing.

.PARAMETER OutDir
    Where to copy the final exe. Defaults to <RepoRoot>\dist.

.PARAMETER LlamaCommit
    Pinned llama.cpp commit. Defaults to the commit used by KVMem master.

.PARAMETER CudaRoot
    CUDA toolkit root. Defaults to $env:CUDA_PATH or v13.2 default location.

.PARAMETER Arch
    CMAKE_CUDA_ARCHITECTURES value. Defaults to 120a (RTX 50 series).

.PARAMETER Jobs
    Parallel compile jobs. Defaults to 16.

.EXAMPLE
    .\build.ps1 -RepoRoot D:\build\kvmem
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = 'D:\build\kvmem',
    [string]$OutDir,
    [string]$LlamaCommit = '620d2225cc436ab0b001e3200e590e3b286ef9ab',
    [string]$CudaRoot,
    [string]$Arch = '120a',
    [int]$Jobs = 16
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Fail($msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }
function Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "  OK  $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "  WARN $msg" -ForegroundColor Yellow }

# ---------------------------------------------------------------- preflight
Step 'Preflight: CUDA toolkit'

if (-not $CudaRoot) {
    if ($env:CUDA_PATH) { $CudaRoot = $env:CUDA_PATH }
    else {
        $candidate = Get-ChildItem 'C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA' -Directory -ErrorAction SilentlyContinue |
                     Sort-Object Name -Descending | Select-Object -First 1
        if ($candidate) { $CudaRoot = $candidate.FullName }
    }
}
if (-not $CudaRoot -or -not (Test-Path $CudaRoot)) { Fail 'CUDA toolkit not found. Install CUDA 13.x and pass -CudaRoot.' }
Ok "CUDA: $CudaRoot"

$nvcc = Join-Path $CudaRoot 'bin\nvcc.exe'
if (-not (Test-Path $nvcc)) { Fail "nvcc missing: $nvcc (install the 'nvcc' component)" }
Ok 'nvcc present'

# The two components that silent/partial installs commonly miss.
$crtHeader = Join-Path $CudaRoot 'include\crt\host_config.h'
if (-not (Test-Path $crtHeader)) {
    Fail @'
Missing CUDA header component: include\crt\host_config.h
Fix by re-running the CUDA installer with the crt component, e.g.:
  cuda_13.x_windows.exe -s crt_13.x -n
(Do NOT hand-copy headers into include\crt - that causes C1014 include recursion.)
'@
}
Ok 'crt headers present'

$cicc = Join-Path $CudaRoot 'nvvm\bin\cicc.exe'
if (-not (Test-Path $cicc)) {
    Fail @'
Missing CUDA component: nvvm/bin/cicc.exe
Without it, CMake fails with "'CMakeCUDACompilerId.ptx' - system cannot find the path specified".
Fix by re-running the CUDA installer with the nvvm component, e.g.:
  cuda_13.x_windows.exe -s nvvm_13.x -n
'@
}
Ok 'nvvm (cicc) present'

$vcvars = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat'
if (-not (Test-Path $vcvars)) { Fail 'VS 2022 Build Tools not found (need C++ workload).' }
Ok 'MSVC build tools present'

$cmake = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
if (-not (Test-Path $cmake)) { $cmake = (Get-Command cmake -ErrorAction SilentlyContinue).Source }
if (-not $cmake) { Fail 'cmake not found.' }
Ok "cmake: $cmake"

# ---------------------------------------------------------------- sources
Step 'Fetch KVMem sources'
New-Item -ItemType Directory -Force -Path $RepoRoot | Out-Null
if (-not (Test-Path (Join-Path $RepoRoot 'VERSION'))) {
    git clone --depth 1 https://github.com/kvmem/kvmem.git $RepoRoot
    if ($LASTEXITCODE -ne 0) { Fail 'git clone failed. If it hangs, it is usually the pack transfer; retry in an interactive shell.' }
} else { Ok 'already cloned' }

Step "Fetch llama.cpp @ $LlamaCommit"
$llamaDir = Join-Path $RepoRoot 'backends\llamacpp'
if (-not (Test-Path (Join-Path $llamaDir 'CMakeLists.txt'))) {
    $tar = Join-Path $RepoRoot 'llama.tar.gz'
    curl.exe -L -o $tar "https://codeload.github.com/ggml-org/llama.cpp/tar.gz/$LlamaCommit" --silent --show-error
    if ($LASTEXITCODE -ne 0) { Fail 'tarball download failed' }
    New-Item -ItemType Directory -Force -Path $llamaDir | Out-Null
    tar.exe -xzf $tar -C $llamaDir --strip-components=1
    if ($LASTEXITCODE -ne 0) { Fail 'tarball extraction failed' }
    Remove-Item $tar -Force
    Ok 'extracted'
} else { Ok 'already present' }

Step 'Apply KVMem patches'
Push-Location $llamaDir
try {
    if (-not (Test-Path '.git')) {
        git init -q
        git add -A
        git -c user.email=build@local -c user.name=build commit -q -m base
    }
    foreach ($p in 'kvmem', 'pq2', 'ptq1', 'ptq1-performance', 'checkpoint-policy') {
        $patch = Join-Path $RepoRoot "backends\patches\llamacpp-$p.patch"
        if (-not (Test-Path $patch)) { Fail "patch missing: $patch" }
        git apply --whitespace=nowarn $patch
        if ($LASTEXITCODE -ne 0) { Fail "patch failed: $p (source tree may already be patched)" }
        git add -A
        git -c user.email=build@local -c user.name=build commit -q -m $p
        Ok $p
    }
} finally { Pop-Location }

# ---------------------------------------------------------------- build
Step 'Configure'
$buildDir = Join-Path $RepoRoot 'build-backends\llamacpp'
$cudaFwd = $CudaRoot.Replace('\', '/')
$cfg = @(
    '-S', $RepoRoot, '-B', $buildDir, '-G', 'Ninja',
    '-DCMAKE_BUILD_TYPE=Release',
    '-DKVMEM_BUILD_LLAMA=ON', '-DGGML_CUDA=ON', '-DGGML_CUDA_FA_QUANTS=all',
    '-DBUILD_SHARED_LIBS=OFF',
    "-DCMAKE_CUDA_ARCHITECTURES=$Arch",
    "-DCMAKE_CUDA_COMPILER=$cudaFwd/bin/nvcc.exe",
    "-DCUDAToolkit_ROOT=$cudaFwd"
) -join ' '
cmd.exe /c "call `"$vcvars`" >nul 2>&1 && `"$cmake`" $cfg"
if ($LASTEXITCODE -ne 0) { Fail 'cmake configure failed' }

Step "Build ($Jobs jobs)"
cmd.exe /c "call `"$vcvars`" >nul 2>&1 && `"$cmake`" --build `"$buildDir`" --parallel $Jobs --target llama-kvmem-server"
if ($LASTEXITCODE -ne 0) { Fail 'build failed' }

# ---------------------------------------------------------------- output
Step 'Collect artifacts'
$exe = Join-Path $buildDir 'bin\llama-kvmem-server.exe'
if (-not (Test-Path $exe)) { Fail "expected binary not found: $exe" }
if (-not $OutDir) { $OutDir = Join-Path $RepoRoot 'dist' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Copy-Item $exe $OutDir -Force

$hash = (Get-FileHash (Join-Path $OutDir 'llama-kvmem-server.exe') -Algorithm SHA256).Hash
$size = (Get-Item (Join-Path $OutDir 'llama-kvmem-server.exe')).Length
Ok "$OutDir\llama-kvmem-server.exe"
Write-Host "  size   : $size bytes"
Write-Host "  sha256 : $hash"
Write-Host "`nRun with CUDA bin on PATH (needs cublas64_*.dll):" -ForegroundColor Cyan
Write-Host "  `$env:PATH = `"$CudaRoot\bin;$CudaRoot\bin\x64;`$env:PATH`""
