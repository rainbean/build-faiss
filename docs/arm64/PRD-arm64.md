# PRD: FAISS ARM64 (aarch64) Build — Targeting Nvidia DGX Spark

## Context

The repository currently builds and distributes FAISS as pre-built binaries for Linux x86_64 and Windows x64. The Nvidia DGX Spark is an ARM64-based system (Grace CPU, aarch64 architecture). To deploy FAISS on DGX Spark without requiring users to build from source, we need a distributable `faiss-linux-arm64.tar.zst` artifact analogous to the existing Linux x64 artifact.

The central technical challenge is that **Intel MKL does not support ARM64**. The entire existing build chain — vcpkg triplet, CMake flags, linker flags — assumes MKL. A new BLAS backend must be chosen.

See [PLAN-arm64.md](PLAN-arm64.md) for the execution plan.

---

## Dependency Feasibility

### BLAS Backend: OpenBLAS vs ArmPL

Intel MKL is x86-only. Two viable replacements for ARM64:

#### OpenBLAS

| Dimension | Assessment |
|---|---|
| **Compatibility** | Universal — works on any aarch64 Linux, available in vcpkg (`openblas:arm64-linux`), `apt`, and Homebrew. No registration or license required. |
| **Porting effort** | Minimal. Swap `BLA_VENDOR=Intel10_64lp` → `BLA_VENDOR=OpenBLAS`, change vcpkg triplet to `arm64-linux`, drop MKL-specific linker flags. vcpkg handles the rest. ~20 lines of changes to `build.sh`. |
| **Runtime performance** | Good baseline. Supports NEON (128-bit SIMD) on aarch64. Does **not** use SVE (Scalable Vector Extension), which Neoverse V2 supports. Expected to be slower than ArmPL for large matrix ops by 2–4×. |

#### ArmPL (Arm Performance Libraries)

| Dimension | Assessment |
|---|---|
| **Compatibility** | DGX Spark-specific. ArmPL is pre-installed on DGX Spark at `/opt/arm/armpl_*/lib`. Free download from developer.arm.com but requires registration. **Not available in vcpkg or apt** — must be manually handled in the build script. |
| **Porting effort** | Moderate. No vcpkg integration — build script must locate ArmPL at a known path (or environment variable), set `BLA_VENDOR=Arm`, and pass `-DBLA_VENDOR=Arm -DLAPACK_LIBRARIES=...` to CMake. CI must either bundle ArmPL or install it from the Arm repo. |
| **Runtime performance** | Best on DGX Spark. ArmPL is tuned specifically for Neoverse V2 and uses SVE. FAISS is BLAS-heavy (matrix multiplications in IVF training, PQ encoding, exhaustive search). ArmPL can give 2–4× speedup vs OpenBLAS on Neoverse for large BLAS calls. Nvidia's DGX software stack ships ArmPL for this reason. |

#### Recommendation

| Use case | BLAS choice | Reason |
|---|---|---|
| Local dev / CI build | **OpenBLAS** | Zero friction, vcpkg-managed, portable |
| Production artifact for DGX Spark | **ArmPL** | Pre-installed on target, uses SVE, best perf |

The two-track approach — OpenBLAS for dev/CI portability, ArmPL for the DGX Spark release artifact — is the practical path. Implement OpenBLAS first to validate the build pipeline, then layer in ArmPL for the production artifact.

### vcpkg ARM64 Triplet

vcpkg has a community triplet `arm64-linux` (`vcpkg/triplets/community/arm64-linux.cmake`):
- `VCPKG_TARGET_ARCHITECTURE=arm64`
- `VCPKG_CRT_LINKAGE=dynamic`
- `VCPKG_LIBRARY_LINKAGE=dynamic`

`openblas` is available as a vcpkg port and should install under this triplet. ArmPL bypasses vcpkg entirely — it is found via CMake `FindBLAS` with the Arm vendor hint.

### FAISS CMake Changes Required

```diff
- -DBLA_VENDOR=Intel10_64lp
+ -DBLA_VENDOR=OpenBLAS          # or Arm for ArmPL build

- -DFAISS_MKL_LIBS="...mkl_intel_lp64;mkl_sequential;mkl_core..."
+ (removed)

- Linker flags: -Wl,--start-group ... -Wl,--end-group
+ (removed — MKL-specific, not needed for OpenBLAS or ArmPL)

- Path rewriting of absolute MKL paths in faiss-targets.cmake
+ (likely not needed — verify post-build)
```

AVX512 is already disabled (commit `ef7c228`) — ARM uses NEON/SVE instead. FAISS detects NEON at configure time; no manual flag needed.

### Feasibility Summary

| Dependency | x64 | ARM64 (OpenBLAS) | ARM64 (ArmPL/DGX Spark) |
|---|---|---|---|
| FAISS source | ✅ | ✅ aarch64 supported | ✅ |
| Intel MKL | ✅ vcpkg | ❌ x86-only | ❌ x86-only |
| OpenBLAS | — | ✅ vcpkg `arm64-linux` | fallback only |
| ArmPL | ❌ | ❌ | ✅ pre-installed on DGX Spark |
| OpenMP | ✅ | ✅ gcc/clang | ✅ |
| vcpkg bootstrap | ✅ | ✅ | ✅ |

---

## Cross-Compilation Strategy

### Mac M1/M2 (Apple Silicon) — First-class local dev option

> **Key insight**: M1/M2 IS aarch64. Docker on Apple Silicon runs `linux/arm64` containers **natively** using Apple's Hypervisor framework — no QEMU emulation, no performance penalty. This is fundamentally different from an x86 machine trying to emulate ARM64.

Options for local development on Apple Silicon:

| Option | Speed | Setup effort | Notes |
|---|---|---|---|
| **Docker Desktop / OrbStack** (`linux/arm64`) | Native | Low | Same `Dockerfile.arm64` used in CI. Recommended. OrbStack is faster and lighter than Docker Desktop. |
| **Lima** (`brew install lima`) | Native | Low | Free, lightweight Linux VM manager for macOS. Runs Ubuntu ARM64 VM. Good alternative if you want a persistent shell environment rather than container builds. |
| **UTM / Parallels** | Near-native | Medium | Full Ubuntu ARM64 VM. Useful for testing the final artifact end-to-end without a container abstraction. |
| **QEMU on x86** | 5–10× slower | Low | Only relevant if building on an Intel Mac or Linux x86 host. Not applicable for M1/M2. |

**Recommended local dev workflow on M1/M2**: Use Docker (or OrbStack) with `--platform linux/arm64`. The build runs at native speed. The same `Dockerfile.arm64` works on both M1/M2 (natively) and CI (natively on `ubuntu-22.04-arm` runner).

You can also **run and test the demo binary** inside the same container — OrbStack runs a real Linux aarch64 kernel, so the compiled ELF executable runs directly with no emulation.

### CI/CD: GitHub Actions Native ARM64 Runner

GitHub Actions offers hosted `ubuntu-22.04-arm` runners (generally available as of 2024):
- Runs natively on ARM64 hardware
- No QEMU, no emulation
- Standard runner billing at 2× minute multiplier vs x86 runners

### Environment Summary

| Environment | Strategy | QEMU needed? | Can run demo? |
|---|---|---|---|
| Mac M1/M2 (local) | Docker `--platform linux/arm64` | No — native | Yes |
| Linux x86 (local) | Docker `--platform linux/arm64` | Yes — emulation | Yes (slow) |
| GitHub Actions CI | `ubuntu-22.04-arm` runner | No — native | Yes |
| DGX Spark (production) | Native build or CI artifact | No | Yes |

---

## Performance Estimation — ArmPL vs MKL for FAISS Workloads

### FAISS Operations and BLAS Dependency

FAISS is not uniformly BLAS-bound. Operations split into two categories:

| Operation | Bottleneck | BLAS weight |
|---|---|---|
| Brute-force L2 / IP search (IndexFlat) | SGEMM — compute + bandwidth | Very high |
| IVF coarse search | SGEMM for distance matrix | High |
| PQ / IVFPQ training (k-means iterations) | SGEMM | High |
| HNSW search | Graph traversal, pointer chasing | None |
| PQ encoding at query time | Small matrix ops | Low |

For a typical IVFPQ workload, BLAS accounts for most of the wall-clock time in training and bulk search.

### Hardware Numbers

**DGX Spark — Grace CPU (Neoverse V2, 72 cores)**
- 256-bit SVE per core, 2 FMA pipelines
- FP32 throughput: ~50 GFLOPS/core → ~3.6 TFLOPS aggregate
- Memory bandwidth: ~480 GB/s (LPDDR5X)

**Typical Intel server used with FAISS (e.g. Xeon Gold 6448Y, 32 cores)**
- AVX-512 with 2× 512-bit FMA units
- FP32 throughput: ~4–5 TFLOPS aggregate
- Memory bandwidth: ~300 GB/s (DDR5)

### ArmPL on Grace vs MKL on Intel

| Workload | Estimate | Reason |
|---|---|---|
| Large-batch throughput search (QPS) | Grace/ArmPL **≥ Intel/MKL** | More cores + 60% more memory bandwidth; search is often bandwidth-bound at scale |
| Training (k-means, PQ) | **Within 10–20%** either direction | Both achieve near-peak SGEMM utilization; core count advantage balances IPC gap |
| Single-query latency | Intel/MKL **10–30% faster** | Higher single-core IPC and clock speed (~3.6 GHz boost vs ~3.1 GHz sustained on Grace) |
| Brute-force SGEMM (IndexFlat, large N) | Grace/ArmPL **competitive to better** | Bandwidth dominates at large N |

**Bottom line**: ArmPL on DGX Spark is not a regression from MKL. For throughput-oriented FAISS use (bulk indexing and batch queries), Grace/ArmPL is competitive with or faster than a comparable Intel socket. Single-query latency is the one area where Intel holds an edge.

### OpenBLAS on ARM64 vs MKL — The Real Gap

OpenBLAS does not use SVE on Neoverse V2 — it falls back to NEON (128-bit). ArmPL uses the full 256-bit SVE and is tuned for Neoverse V2's pipeline.

| Comparison | Gap |
|---|---|
| OpenBLAS vs ArmPL on Neoverse V2 | OpenBLAS is **2–4× slower** for large SGEMM |
| OpenBLAS (ARM64) vs MKL (Intel) | OpenBLAS is likely **3–5× slower** overall |

```
Performance tier for FAISS (rough estimate):

Intel/MKL (x86)      ██████████  100% (baseline)
ArmPL on DGX Spark   █████████░  90–110%  ← competitive, wins on throughput
OpenBLAS on ARM64    ███░░░░░░░  25–40%   ← dev/CI only, not production
```

**Conclusion**: OpenBLAS is adequate for validating correctness locally. It should not be used to judge production performance. The production artifact must link ArmPL to be a meaningful alternative to the existing MKL build.

---

## Risks

| Risk | Mitigation |
|---|---|
| vcpkg `arm64-linux` triplet for `openblas` not working | Fall back to `apt install libopenblas-dev` in Dockerfile |
| ArmPL path varies across DGX Spark OS versions | Accept `ARMPL_DIR` env var override in build script |
| GitHub ARM64 runner availability / cost | QEMU fallback on `ubuntu-22.04` for CI if needed |
| FAISS NEON path not enabled by default | Verify `FAISS_OPT_LEVEL` flag; set to `generic` initially |
| ArmPL license requires registration | OpenBLAS build is the default; ArmPL build is opt-in |
