# Execution Plan: FAISS ARM64 Build

See [PRD-arm64.md](PRD-arm64.md) for context, feasibility analysis, and performance estimates.

---

## Stage 1: Local Build with OpenBLAS (M1/M2 Mac)

Goal: validate the ARM64 build pipeline end-to-end using OpenBLAS before touching ArmPL or CI.

### New files to create

| File | Purpose |
|---|---|
| `scripts/build-arm64.sh` | ARM64 build script — OpenBLAS variant |
| `Dockerfile.arm64` | Reproducible build container (works on M1/M2 natively and CI) |

### `scripts/build-arm64.sh` — diff from `build.sh`

```diff
- TRIPLET="x64-linux"
+ TRIPLET="arm64-linux"

- cmake ... -DBLA_VENDOR=Intel10_64lp \
-           -DFAISS_MKL_LIBS="..." \
-           -DFAISS_MKL_INCLUDE_DIR="..." \
+ cmake ... -DBLA_VENDOR=OpenBLAS \

- # MKL linker flag block
- FAISS_MKL_LIBRARIES="-Wl,--start-group ... -Wl,--end-group"
+ # (removed)

- # Path rewriting block for faiss-targets.cmake
+ # (verify if needed — likely not required for OpenBLAS)
```

### `Dockerfile.arm64`

```dockerfile
FROM --platform=linux/arm64 ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    cmake ninja-build build-essential \
    curl zip unzip tar git pkg-config \
    python3 libopenblas-dev libgomp1
WORKDIR /workspace
COPY . .
RUN git submodule update --init --recursive
RUN ./scripts/build-arm64.sh faiss-linux-arm64.tar.zst
```

### Local test workflow (M1/M2 Mac)

```bash
# Install OrbStack (recommended) or Docker Desktop
brew install orbstack

# Build ARM64 artifact — runs at native speed on M1/M2, no QEMU
docker build --platform linux/arm64 \
  --output type=local,dest=./out \
  -f Dockerfile.arm64 .

# Verify the artifact is aarch64 ELF
file out/dist/lib/libfaiss.so
# expected: ELF 64-bit LSB shared object, ARM aarch64

# Run the demo inside the container
docker run --platform linux/arm64 --rm -it \
  -v $(pwd)/out/dist:/dist \
  ubuntu:22.04 bash -c "
    apt-get install -q -y libopenblas-dev cmake build-essential libgomp1
    cd /workspace && ./scripts/demo.sh && ./build-demo/demo
  "
```

### Verification checklist

- [x] `faiss-linux-arm64.tar.zst` produced without build errors
- [x] `file dist/lib/libfaiss.so` confirms `ARM aarch64`
- [x] Demo compiles and links against the built `dist/`
- [x] IVFPQ benchmark runs to completion and prints recall / QPS

---

## Stage 2: ArmPL Build — Dropped

ArmPL was evaluated on DGX Spark and showed ~5× faster IVFPQ training vs OpenBLAS. However it was ruled out as the distribution artifact for three reasons:

1. `libarmpl_lp64.so` is ~200 MB with no viable static linking path (not compiled with `-fPIC`)
2. Bundling is impractical; requiring it on targets adds a heavy deployment dependency
3. The ArmPL EULA is incompatible with MIT-licensed redistribution

**Decision**: OpenBLAS is the single BLAS backend for the ARM64 artifact. See PRD-arm64.md for the full rationale.

---

## Stage 3: GitHub Actions CI/CD

Goal: add `faiss-linux-arm64-{tag}.tar.zst` to the automated release pipeline.

### Extend `.github/workflows/build.yml`

Add a third matrix entry alongside the existing Linux x64 and Windows jobs:

```yaml
- os: ubuntu-22.04-arm
  arch: arm64
  artifact: faiss-linux-arm64
  build_script: ./scripts/build-arm64.sh
  output: faiss-linux-arm64.tar.zst
```

Full job considerations:
- Same disk-space cleanup as x64 job (`rm -rf /usr/share/dotnet` etc.)
- Same OIDC AWS auth — `id-token: write` already configured
- S3 artifact: `faiss-linux-arm64-{tag}.tar.zst` in same bucket (`ap-northeast-1`)
- If `ubuntu-22.04-arm` runner is unavailable, fallback: `ubuntu-22.04` with `docker buildx --platform linux/arm64`

### Verification checklist

- [x] Push a test tag; both `faiss-linux-{tag}.tar.zst` (x64) and `faiss-linux-arm64-{tag}.tar.zst` appear in S3
- [x] ARM64 CI job wall-clock time is acceptable (target: under 60 min)
- [x] No regressions in x64 or Windows jobs

---

## Files Summary

### Create

| File | Stage |
|---|---|
| `scripts/build-arm64.sh` | 1 |
| `Dockerfile.arm64` | 1 |

### Modify

| File | Change | Stage |
|---|---|---|
| `.github/workflows/build.yml` | Add `ubuntu-22.04-arm` matrix job | 3 |

### Reference (do not modify)

| File | Reason |
|---|---|
| `scripts/build.sh` | Template for ARM64 scripts |
| `vcpkg/triplets/community/arm64-linux.cmake` | Verify triplet settings |
| `faiss/CMakeLists.txt` | Confirm ARM64/NEON support and BLAS detection |
| `.github/workflows/build.yml` | Template for new CI job |
