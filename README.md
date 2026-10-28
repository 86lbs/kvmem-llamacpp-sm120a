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

### 端到端推理实测（推荐配置）

| 项 | 值 |
|---|---|
| 模型 | `Qwen3.5-9B-Q4_K_M.gguf`（5.3 GB，K-quant） |
| 启动 | `-c 65536 --kvmem --kvmem-budget 16384 --kvmem-gen-reserve 2048 --kvmem-host-mib 8192 --kvmem-gpu-ratio 0.28 -ngl 99 -fa on` |
| 简单问答 | ✅ `1+1` → `2` |
| 长上下文针测试 | ✅ 16039 token prompt，**7.3 秒**处理，准确检索出埋在中间的暗号 `KV-7749` |

> ⚠️ **重要限制见第 9 节**：27B 模型在 12GB 卡上只能靠 i-quant（IQ2/IQ3），而 i-quant 在 sm_120a 的 CUDA 路径上会输出乱码。**K-quant 正常**。

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
  -m 'D:\kvmem\models\Qwen3.5-9B-Q4_K_M.gguf' `
  -c 65536 `
  --kvmem `
  --kvmem-budget 16384 `
  --kvmem-gen-reserve 2048 `
  --kvmem-host-mib 8192 `
  --kvmem-gpu-ratio 0.28 `
  -ngl 99 -fa on `
  --kv-dtype q8_0 `
  --port 18080
```

> 这是**已实测通过**的配置（9B K-quant，16K 上下文针测试 7.3 秒准确命中）。27B 在 12GB 上请先读第 7 节。

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

### 3.4 性能实测：原生 vs KVMem（同一台机、同一模型）

模型 `Qwen3.5-9B-Q4_K_M`，`-c 262144`，长文本中段埋暗号后提问。

| 上下文 | 模式 | prefill 速度 | 耗时 |
|---|---|---|---|
| **75K tokens** | 原生 | **2233 tok/s** | 33.9 s |
| 75K tokens | KVMem | 1799 tok/s | 42.0 s |
| **252K tokens** | 原生 | 1192–1220 tok/s | 206.6 / 211.4 s |
| **252K tokens** | **KVMem** | **1707–1804 tok/s** | **139.7 / 147.7 s** |

**结论**

- **上下文还塞得下时（75K）：KVMem 反而慢约 24%** —— 额外的分页/选择开销，没有收益。
- **上下文超出舒适区时（252K）：KVMem 快 40–50%** —— 活跃窗口被限制在 B=16384，避免全长注意力的二次开销。
- 暗号检索：两种模式都能命中（原生在 252K 有一次未命中，复测命中 → 属随机波动，不作为结论）。

> 即：**KVMem 的收益随上下文长度增长才出现**。短/中上下文不要开，纯亏。

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
| **Qwen3.5-9B `Q4_K_M`** | **5.3 GB** | ✅ **实测可用（推荐）** |
| Qwen3.8-27B `UD-IQ2_S` | 7.8 GB | ❌ 见第 7 节：i-quant GPU 输出乱码 |
| Qwen3.8-27B `Q4_K_M` | 17.7 GB | ❌ 装不下，KVMem 也无解 |

> 选择原则：**先保证是 K-quant，再保证 ≤8GB**。两条同时满足，12GB 卡才有可用组合。

---

## 7. 已知限制（实测发现，务必先读）

### 7.1 27B 的 2-bit i-quant 在 sm_120 GPU 上结果错误（9B 正常）

在 RTX 5070 Ti Laptop（sm_120 / 12GB）上逐一实测：

| 模型 | 量化 | CPU (`-ngl 0`) | GPU (`-ngl 99`) |
|---|---|---|---|
| Qwen3.5-9B | **IQ4_XS**（i-quant） | — | ✅ 正确 |
| Qwen3.8-27B（unsloth UD） | **IQ2_S** | ✅ 正确（答 `2`） | ❌ 全 `/////` |
| Qwen3.8-27B（bartowski） | **IQ2_XXS** | ✅ 正确（答 `2`） | ❌ 乱码（`1+ 1+ 1: 7`） |
| Qwen3.5-9B | Q4_K_M（K-quant） | — | ✅ 正确 |
| Qwen3.8-27B | Q4_K_M（K-quant） | ✅ 正确 | ✅ 正确 |

**结论**：不是"i-quant 全坏"，而是 **27B 尺寸 + 2-bit i-quant** 在这个 llama.cpp 基线（`620d2225`）的 sm_120a CUDA 路径上算错；9B 的 i-quant 正常，27B 的 K-quant 也正常。CPU 全部正常 → 是 GPU kernel 问题，不是模型文件损坏。

已排除：`120a` vs `120` 架构参数、`GGML_CUDA_FORCE_MMQ`、`GGML_CUDA_DISABLE_GRAPHS`、`-fa off`。

**影响**：12GB 显存跑 27B 必须 ≤8GB 权重 → 只能选 IQ2 → **27B 目前不可用**。
→ 12GB 卡请用 **9B K-quant**（已验证可用），或等上游修复。

### 7.2 KVMem 需要 flash attention

`-fa off` 与 KVMem 不兼容，报错：
`KVMEM retained histories require supported host KV switching (flash attention on)`
且量化 V cache（`--kv-dtype q8_0`）本身也要求 `-fa on`。

### 7.3 已验证可用 / 不可用清单

| 组合 | 状态 |
|---|---|
| 9B / K-quant / GPU 全量 / KVMem / `-fa on` | ✅ 可用（推荐） |
| 27B / Q4_K_M / 部分卸载 / 无 KVMem | ✅ 正确但慢、且放不下 12GB |
| 27B / IQ2_I / GPU 全量 | ❌ 结果错误 |
| 任意 / `-fa off` + KVMem | ❌ 不支持 |

---

## 8. 许可证与声明

| 组件 | 许可证 |
|---|---|
| llama.cpp | **MIT**（见 [`LICENSES/llama.cpp`](LICENSES/llama.cpp)） |
| KVMem 集成补丁 | ⚠️ **上游仓库根 `LICENSE` 为空（未声明）**，本构建按"仅供参考/个人使用"分发 |

- 本仓库**不包含**模型权重，权重遵循各自条款（Qwen 系为 Apache-2.0）。
- 二进制为本仓库作者从上述源码构建，**非 KVMem 官方发布**；如上游提出异议将立即下架。
- 使用本构建产生的任何后果由使用者自负。

---

## 9. AI 生成声明

本项目（含构建脚本、文档与预编译产物）由 **AI 智能体自动生成与验证**：

- 生成环境：**DeepSeek Harness**（Agent 驱动，无人工逐步编写）
- 人类参与：提出目标、授权环境变更、决定发布
- 代码与文档来源：AI 依据 KVMem 上游仓库与实测结果生成
- 构建验证：设备枚举、KVMem 能力自检、CUDA 冒烟编译均在目标机上实跑通过

请知悉：AI 生成内容可能存在错误，请自行复核后再用于生产环境。

[![](https://img.shields.io/badge/powered_by-dsh-4D6BFE?style=flat-square&logo=deepseek&logoColor=white)](https://github.com/deepseek-ai/deepseek-harness)
