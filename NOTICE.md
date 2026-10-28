# NOTICE — 第三方组件与分发声明

本仓库分发的 `llama-kvmem-server.exe` 是**非官方构建**，由下述源码编译而来，不包含任何模型权重。

## 组件与许可证

| 组件 | 版本 / 提交 | 许可证 |
|---|---|---|
| llama.cpp | `620d2225cc436ab0b001e3200e590e3b286ef9ab` | **MIT** — 全文见 [`LICENSES/llama.cpp`](LICENSES/llama.cpp) |
| KVMem（集成框架 + 补丁） | `master`（`VERSION` = 0.19.0） | ⚠️ **上游根 `LICENSE` 为空文件，未声明许可证** |
| CUDA Runtime / cuBLAS | 13.2 | 随 NVIDIA CUDA EULA 分发，本仓库不重分发其二进制 |

## 关于 KVMem 许可证状态

在构建时点（2026-10-28），`kvmem/kvmem` 仓库根目录的 `LICENSE` 文件为 **0 字节**，即未声明任何许可证。
这意味着默认适用"保留所有权利"（all rights reserved）。

因此本仓库的定位是：

- **技术参考 + 可复现构建配方**（这部分的知识与脚本为本仓库作者原创）
- 预编译二进制**仅供个人测试与学习使用**，不得用于商业分发
- 如需在商业场景使用，请向 KVMem 上游作者取得授权
- **若上游作者提出异议，本仓库将立即下架二进制产物**

## AI 生成声明

本仓库全部内容——包括构建脚本、文档、以及预编译产物——由 **AI 智能体（DeepSeek Harness）** 自动生成、构建与验证。

- 人类角色：设定目标、授权系统环境变更、决定发布
- AI 角色：环境搭建、源码获取与打补丁、编译、验证、文档撰写
- 验证方式：在目标机（RTX 5070 Ti Laptop / sm_120 / CUDA 13.2）实跑
  `--help`、`--list-devices`、`--kvmem-capabilities` 三项检查并记录结果

AI 生成内容可能存在错误或过时信息。使用前请自行复核，尤其是许可证与安全相关部分。

---

[![](https://img.shields.io/badge/powered_by-dsh-4D6BFE?style=flat-square&logo=deepseek&logoColor=white)](https://github.com/deepseek-ai/deepseek-harness)
