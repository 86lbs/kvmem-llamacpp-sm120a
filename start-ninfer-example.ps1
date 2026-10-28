# KVMem NInfer 后端启动脚本（示例，按你的路径改）
#
# 前置：
#   1. 下载并解压官方包 kvmem-v0.19.0-rc1-ninfer-windows-rtx50-sm120a.zip（英文路径）
#   2. 下载 .ninfer 模型（12GB 卡建议 <=9GB 的量化档）
#
# 实测参考（RTX 5070 Ti Laptop 12GB / sm_120）：
#   Ternary-Bonsai-2-27B（8.87GB 三元量化）+ 本脚本参数
#   204K 上下文：prefill 883 tok/s，decode 43 tok/s，检索命中
param(
    [Parameter(Mandatory=$true)][string]$AppDir,   # 解压后的包根目录
    [Parameter(Mandatory=$true)][string]$Model,    # .ninfer 模型绝对路径
    [int]$Port = 18200,
    [int]$MaxContext = 204800,
    [int]$Budget = 2048,
    [int]$Reserve = 512,
    [int]$HostMiB = 16000,
    [int]$Device = 0
)

$ErrorActionPreference = 'Stop'
$worker = Join-Path $AppDir 'workers\ninfer\ninfer-kvmem-server.exe'
if (-not (Test-Path $worker)) { throw "找不到 worker: $worker" }
if (-not (Test-Path $Model))  { throw "找不到模型: $Model" }

Write-Host "worker : $worker"
Write-Host "model  : $Model"
Write-Host "context: $MaxContext  (B=$Budget R=$Reserve H=${HostMiB}MiB)"
Write-Host "API    : http://127.0.0.1:$Port/v1"
Write-Host ""

Push-Location (Join-Path $AppDir 'workers\ninfer')
try {
    & $worker $Model --device $Device --max-context $MaxContext `
        --kvmem --kvmem-budget $Budget --kvmem-gen-reserve $Reserve `
        --kvmem-host-mib $HostMiB --port $Port
} finally { Pop-Location }
