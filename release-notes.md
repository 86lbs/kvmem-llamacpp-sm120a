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

### End-to-end verified

RTX 5070 Ti Laptop (12GB) / Win11 / driver 621.01:

- `--help`, `--list-devices` (CUDA0 12199 MiB, compute 12.0), `--kvmem-capabilities` : all OK
- **Inference** with `Qwen3.5-9B-Q4_K_M` (5.3 GB) + KVMem: `1+1` -> `2`
- **Long context**: 16039-token prompt, 7.3 s, correctly retrieved a needle buried mid-context

Working command:

```
llama-kvmem-server.exe -m Qwen3.5-9B-Q4_K_M.gguf -c 65536 --kvmem --kvmem-budget 16384 --kvmem-gen-reserve 2048 --kvmem-host-mib 8192 --kvmem-gpu-ratio 0.28 -ngl 99 -fa on --kv-dtype q8_0 --port 18080
```

### Known limitation (important)

**i-quant (IQ2/IQ3) produces garbage on sm_120a GPU** at this llama.cpp baseline.

| Model | CPU | GPU |
|---|---|---|
| 27B UD-IQ2_S (i-quant) | correct | `/////` garbage |
| 27B Q4_K_M (K-quant) | correct | correct |
| 9B Q4_K_M (K-quant) | - | correct |

Since a 27B model must be i-quant to fit 12 GB, **27B on 12 GB is not usable with this build**. Use a K-quant model <= 8 GB (9B Q4_K_M works), or wait for an upstream fix.

Also: KVMem requires `-fa on` (flash attention); `-fa off` is rejected.

### Notes

- Weights not included.
- Unofficial build. Upstream `kvmem` repo has an empty LICENSE file; binary for personal testing only. See NOTICE.md.
- **AI-generated** by DeepSeek Harness (build, docs and verification automated; human authorized and published).
