# build-faiss

Builds and packages [FAISS](https://github.com/facebookresearch/faiss) as a self-contained binary artifact for Linux (x86_64 and ARM64) and Windows. Uses OpenBLAS for BLAS on all platforms. Artifacts are uploaded to S3 on tag push via GitHub Actions.

## Prerequisites

**Linux:** `libopenblas-dev`

```shell
sudo apt-get install -y libopenblas-dev
```

**Windows:** Visual Studio 2022 (MSBuild), vcpkg submodule (bootstrapped automatically by the build script)

## Build

```shell
# Linux (x86_64 or ARM64)
./scripts/build.sh [output.tar.zst]
# Produces: faiss-linux-x86_64.tar.zst  (or faiss-linux-aarch64.tar.zst on ARM64)
# Artifact unpacks to: dist/

# Windows
.\scripts\build.ps1 [output.7z]
# Produces: faiss-win64.7z
```

## Test and benchmark

Requires a completed build (`dist/` must exist).

```shell
# Build all tools (demo, test_cosine, bench_cosine)
./scripts/demo.sh

# Correctness test — IVF256,Flat inner-product, 672D, nprobe=32 (exits non-zero on failure)
./build-demo/test_cosine

# IVFPQ demo
time ./build-demo/demo

# Benchmark (optional --nprobe to tune)
./build-demo/bench_cosine
./build-demo/bench_cosine --nprobe 64
```

## CI

Triggered on any tag push. Builds on Ubuntu 22.04 (x86_64), Ubuntu 22.04 ARM64, and Windows 2022. The correctness test (`test_cosine`) runs after each build and gates the S3 artifact upload.
