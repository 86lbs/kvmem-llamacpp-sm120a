# KVMem llama.cpp worker — Windows / RTX 50 (sm_120a) 预编译 + 可复现构建

[![](https://img.shields.io/badge/powered_by-dsh-4D6BFE?style=flat-square&logo=deepseek&logoColor=white)](https://github.com/deepseek-ai/deepseek-harness)

KVMem 官方 v0.19.0-rc1 只发布了 **NInfer 后端**的 Windows 包，llama.cpp 后端的预编译包停留在 `v0.18.0-llamacpp-rc1`，且只覆盖 **sm75 / sm70**（RTX 20 / V100）。
本仓库填补这个空缺：**为 RTX 50 系（sm_120a）构建可运行的 `llama-kvmem-server.exe`，并给出可复现的构建配方。**

> ⚠️ 非官方构建。由第三方（见下方 AI 声明）编译，与 KVMem 上游无隶属关系。

---

## 1. 这是什么

| 项 | 值 |
|---|---|
| 产物 | `llama-kvmem-server.exe` |
| 大小 | 82.9 MB（86,965,248 字节） |
| SHA256 | `71143A57F15D0F542BAC4A21C26C7B7F753F34796035137D1D2BF200AE25C24F` |
| 后端 | llama.cpp（KVMem 集成补丁版） |
| CUDA 架构 | **sm_120a**（RTX 50 系 / Blackwell） |
| 源码基线 | kvmem `master`（`VERSION` = 0.19.0）+ llama.cpp `620d2225cc436ab0b001e3200e590e3b286ef9ab` |
| 补丁 | 5 个：`kvmem → pq2 → ptq1 → ptq1-performance → checkpoint-policy` |

对外是 **OpenAI 兼容服务**：`/v1/chat/completions`、`/v1/responses`、`/v1/models`、`/props`、`/slots`、`/health`，自带聊天 UI。

---

## 2. 验证记录

构建机：**RTX 5070 Ti Laptop（12GB, sm_120）· Win11 26300 · 32GB RAM · 驱动 621.01 · CUDA 13.2.78**

| 检查 | 结果 |
|---|---|
| `--help` | ✅ 完整 KVMem 参数集（`--kvmem-budget` 等全部存在，证明补丁生效） |
| `--list-devices` | ✅ `CUDA0: NVIDIA GeForce RTX 5070 Ti Laptop GPU (12199 MiB, 11042 MiB free)`, compute 12.0 |
| `--kvmem-capabilities` | ✅ `{"backend":"llamacpp","query_scoring_revision":2,...}` |

> 推理链路需自备模型（见第 5 节），本仓库不附带权重。

---

## 3. 运行

### 3.1 依赖

- NVIDIA 驱动（支持 CUDA 12.8+；本构建用 13.2）
- **VC++ 2015–2022 x64 运行库**
- **CUDA 13.2 的 `cublas64_13.dll`**（必需，否则启动即失败）

```powershell
# 运行时把 CUDA bin 加进 PATH（推荐）
$env:PATH = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.2\bin;C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.2\bin\x64;$env:PATH"
```

### 3.2 启动（12GB 显存的保守配方）

```powershell
$env:PATH = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.2\bin;C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.2\bin\x64;$env:PATH"

.\llama-kvmem-server.exe `
  -m 'D:\kvmem\models\Qwen3.8-27B-UD-IQ2_S.gguf' `
  -c 32768 `
  --kvmem `
  --kvmem-budget 8192 `
  --kvmem-gen-reserve 1024 `
  --kvmem-host-mib 8192 `
  --kvmem-gpu-ratio 0.30 `
  -ngl 99 -fa on `
  --kv-dtype q8_0 `
  --port 18080
```

**关键参数说明**

| 参数 | 说明 |
|---|---|
| `--kvmem-gpu-ratio 0.30` | **12GB 卡必调**。默认 0.5 会按整卡比例给 KV 池，权重占 7–8GB 后必然 OOM；0.30 约 3.6GB 更稳 |
| `--kvmem-budget` | GPU 内驻留的"选中历史" token 数 |
| `--kvmem-gen-reserve` | 生成追加空间（循环复用，**不是**输出上限） |
| `--kvmem-host-mib` | 历史 KV 在内存的配额（长上下文真正吃的是内存） |
| `-ngl 99` | 权重必须全量进显存，KVMem 不解决权重显存 |

### 3.3 验证

```powershell
curl http://127.0.0.1:18080/health
curl http://127.0.0.1:18080/v1/models
curl http://127.0.0.1:18080/props     # 看 kvmem 预算
curl http://127.0.0.1:18080/stats     # 看换页/命中
```

浏览器访问 `http://127.0.0.1:18080/` 使用内置 UI。

---

## 4. 从源码复现

### 4.1 环境

| 组件 | 版本 |
|---|---|
| VS 2022 Build Tools（C++ 工作负载） | MSVC 14.44.35207 + Windows SDK 10.0.26100 |
| CMake | 3.31.6（VS 自带即可） |
| Ninja | 1.12.1 |
| CUDA Toolkit | **13.2.78**（需含 `crt` 与 `nvvm` 组件） |
| Python | 3.9+（仅 prepare 脚本用，可绕过） |

### 4.2 一条命令

```powershell
.\build.ps1 -RepoRoot D:\build\kvmem -OutDir .\dist
```

脚本会：下载 llama.cpp tarball（固定提交）→ 按序打 5 个补丁 → CMake 配置（`-DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=120a`）→ 构建 `llama-kvmem-server`。

### 4.3 手工步骤（等价）

```powershell
# 1) 浅克隆主仓库（后台任务里 git clone 容易卡，建议前台）
git clone --depth 1 https://github.com/kvmem/kvmem.git D:\build\kvmem

# 2) 取 llama.cpp 固定提交的 tar 包（比 git submodule 稳）
curl -L -o llama.tar.gz https://codeload.github.com/ggml-org/llama.cpp/tar.gz/620d2225cc436ab0b001e3200e590e3b286ef9ab
mkdir D:\build\kvmem\backends\llamacpp
tar -xzf llama.tar.gz -C D:\build\kvmem\backends\llamacpp --strip-components=1

# 3) 打补丁
cd D:\build\kvmem\backends\llamacpp
git init; git add -A; git -c user.email=x@x -c user.name=x commit -m base
foreach ($p in 'kvmem','pq2','ptq1','ptq1-performance','checkpoint-policy') {
  git apply --whitespace=nowarn "..\patches\llamacpp-$p.patch"
  git add -A; git -c user.email=x@x -c user.name=x commit -m $p
}

# 4) 配置 + 构建（VS x64 开发环境）
cmake -S D:\build\kvmem -B D:\build\kvmem\build-backends\llamacpp -G Ninja `
  -DCMAKE_BUILD_TYPE=Release -DKVMEM_BUILD_LLAMA=ON -DGGML_CUDA=ON `
  -DGGML_CUDA_FA_QUANTS=all -DBUILD_SHARED_LIBS=OFF `
  -DCMAKE_CUDA_ARCHITECTURES=120a `
  -DCMAKE_CUDA_COMPILER="C:/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v13.2/bin/nvcc.exe" `
  -DCUDAToolkit_ROOT="C:/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v13.2"
cmake --build D:\build\kvmem\build-backends\llamacpp --parallel 16 --target llama-kvmem-server
```

---

## 5. 踩坑清单（重要，能省几小时）

| # | 坑 | 现象 | 解法 |
|---|---|---|---|
| 1 | **CUDA 按组件静默安装会漏件** | `fatal error C1083: crt/host_config.h` | 补装 `crt_13.2` 组件 |
| 2 | 同上 | `cicc` 找不到 / `CMakeCUDACompilerId.ptx` 生成失败（"系统找不到指定的路径"） | 补装 `nvvm_13.2` 组件 |
| 3 | 手工补 `include\crt` 目录 | `C1014: 包含文件太多 深度=1024`（自引用递归） | 别手工拷贝，用官方组件 |
| 4 | 后台任务里 `git clone` | `tmp_pack` 0 字节、无 TCP 连接、无限挂起 | 改用 tarball + `git apply`，或前台执行 |
| 5 | `python` 是 Microsoft Store 占位别名 | `Python was not found` → prepare 脚本失败 | 绕过 prepare；真 Python 在 `%LOCALAPPDATA%\Programs\Python\Python3xx` |
| 6 | `cmake` 不在 `vcvars64.bat` 的 PATH | `'cmake' is not recognized` | 用 VS 自带 CMake 绝对路径 |
| 7 | winget 首次装包可能假死 | 5 分钟无输出 | 直接下官方安装包 |

> 第 1–3 条是 CUDA 13.x 按组件安装的连带问题，**NVIDIA 静默安装不会自动补齐 `crt` / `nvvm`**，是这个构建最大的隐藏门槛。

---

## 6. 模型选择（12GB 现实约束）

**KVMem 只虚拟化 KV，不减少权重显存。** 12GB 卡必须选 ≤8GB 的量化：

| 模型 | 权重 | 12GB 可用性 |
|---|---|---|
| Qwen3.8-27B `UD-IQ2_S` | 7.8 GB | ✅ 推荐（unsloth 动态量化） |
| Qwen3.8-27B `UD-IQ2_XXS` | 6.8 GB | ✅ 更保守 |
| Qwen3.8-27B `Q4_K_M` | 17.7 GB | ❌ 装不下，KVMem 也无解 |
| Qwen3.5 9B / 4B | 4–7 GB | ✅ 验证链路首选 |

---

## 7. 许可证与声明

| 组件 | 许可证 |
|---|---|
| llama.cpp | **MIT**（见 [`LICENSES/llama.cpp`](LICENSES/llama.cpp)） |
| KVMem 集成补丁 | ⚠️ **上游仓库根 `LICENSE` 为空（未声明）**，本构建按"仅供参考/个人使用"分发 |

- 本仓库**不包含**模型权重，权重遵循各自条款（Qwen 系为 Apache-2.0）。
- 二进制为本仓库作者从上述源码构建，**非 KVMem 官方发布**；如上游提出异议将立即下架。
- 使用本构建产生的任何后果由使用者自负。

---

## 8. AI 生成声明

本项目（含构建脚本、文档与预编译产物）由 **AI 智能体自动生成与验证**：

- 生成环境：**DeepSeek Harness**（Agent 驱动，无人工逐步编写）
- 人类参与：提出目标、授权环境变更、决定发布
- 代码与文档来源：AI 依据 KVMem 上游仓库与实测结果生成
- 构建验证：设备枚举、KVMem 能力自检、CUDA 冒烟编译均在目标机上实跑通过

请知悉：AI 生成内容可能存在错误，请自行复核后再用于生产环境。

[![](https://img.shields.io/badge/powered_by-dsh-4D6BFE?style=flat-square&logo=deepseek&logoColor=white)](https://github.com/deepseek-ai/deepseek-harness)
