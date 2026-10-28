## KVMem llama.cpp worker - Windows / RTX 50 (sm_120a)

Built from `kvmem@master` (VERSION 0.19.0) + llama.cpp `620d2225` with all 5 KVMem integration patches.

| | |
|---|---|
| File | `llama-kvmem-server.exe` |
| Size | 82.9 MB (86,965,248 bytes) |
| SHA256 | `71143A57F15D0F542BAC4A21C26C7B7F753F34796035137D1D2BF200AE25C24F` |
| CUDA arch | sm_120a (RTX 50 / Blackwell) |
| Compiled with | MSVC 14.44 + CUDA 13.2.78 |

**Requires** `cublas64_13.dll` on PATH (CUDA 13.2 `bin`) + VC++ 2015-2022 x64 runtime.

### Verified end-to-end

RTX 5070 Ti Laptop (12GB) / Win11 / driver 621.01, model `Qwen3.5-9B-Q4_K_M`:

- `--help`, `--list-devices` (CUDA0 12199 MiB, compute 12.0), `--kvmem-capabilities` - OK
- 16K needle test: 7.3 s, correct retrieval
- **75K tokens**: native 2233 tok/s vs KVMem 1799 tok/s (KVMem slower - overhead)
- **252K tokens**: native 1192-1220 tok/s vs **KVMem 1707-1804 tok/s** (KVMem 40-50% faster)

KVMem only pays off beyond the context size where native attention degrades.

### Known limitation

**27B at 2-bit i-quant produces wrong output on sm_120 GPU** (CPU is correct):

| Model | CPU | GPU |
|---|---|---|
| 9B IQ4_XS (i-quant) | - | correct |
| 27B IQ2_S (unsloth UD) | correct | all `/////` |
| 27B IQ2_XXS (bartowski) | correct | garbled |
| 9B / 27B Q4_K_M (K-quant) | correct | correct |

Ruled out: `120` vs `120a` arch, `GGML_CUDA_FORCE_MMQ`, `GGML_CUDA_DISABLE_GRAPHS`, `-fa off`.
Since 12GB cards need <=8GB weights for 27B (= i-quant), **27B is not usable here**; use 9B K-quant.

KVMem also requires `-fa on`; `-fa off` is rejected.

### Notes

- Weights not included.
- Unofficial build. Upstream `kvmem` repo has an empty LICENSE file; binary for personal testing only.
- **AI-generated** by DeepSeek Harness (build, docs and verification automated; human authorized and published).
