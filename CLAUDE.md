# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repository builds and packages [FAISS](https://github.com/facebookresearch/faiss) (Facebook AI Similarity Search) as distributable binaries for Linux (x86_64, arm64) and Windows (x64). The FAISS source is a git submodule. All platforms link against OpenBLAS for BLAS and LAPACK.

## Setup

Fresh clone requires the `faiss` submodule:
```bash
git clone --recurse-submodules <repo>
# or after cloning: git submodule update --init --recursive
```

## Key Commands

### Build (Linux)
```bash
./scripts/build.sh [optional_output_filename]
# Produces: faiss-linux-$(uname -m).tar.zst (or specified filename)
# Output artifact unpacks to: dist/
# Requires: libopenblas-openmp-dev (apt)
```

### Build (Windows)
```powershell
.\scripts\build.ps1 [optional_output_filename]
# Produces: faiss-win64.7z
# Requires: winget (for 7zip-zstd), MSBuild / Visual Studio 2022
```

On first run the script downloads the upstream OpenBLAS Windows release into
`build-deps/` and extracts it; later runs reuse it.

### Build and Run Demo
```bash
# dist/ must exist (run the build script first)
./scripts/demo.sh && time ./build-demo/demo          # Linux
.\scripts\demo.ps1                                   # Windows
```

`demo.sh`/`demo.ps1` build three executables against `dist/`:
- `demo` — IVFPQ indexing benchmark on random 128D vectors
- `test_cosine` — correctness check, gated in CI
- `bench_cosine` — offline speed comparison; reports train/add time and search QPS

## Architecture

### Submodules
- `faiss/` — Facebook Research FAISS source (do not edit)

### Build Flow
1. **OpenBLAS** is acquired: from the distro package on Linux, or downloaded from the upstream release into `build-deps/` on Windows
2. **CMake** configures the `faiss/` submodule with:
   - `BLA_VENDOR=OpenBLAS`
   - Python and GPU support disabled
   - Shared library output
3. Install target copies artifacts to `dist/`
4. The OpenBLAS runtime is copied next to `faiss.dll` / `libfaiss.so` so the artifact is self-contained
5. Post-processing: absolute BLAS paths in `dist/share/faiss/faiss-targets.cmake` are rewritten to relative `${_IMPORT_PREFIX}/lib` paths (so the archive is relocatable)
6. Archive packed with zstd compression (Linux) or 7z (Windows)

### Demo App
`demo/CMakeLists.txt` finds the FAISS package from `../dist` and links against it.

### CI/CD
`.github/workflows/build.yml` triggers on any git tag push, builds on Ubuntu 22.04 (x86_64 and arm64) and Windows 2022, runs `test_cosine`, and uploads artifacts to AWS S3 (ap-northeast-1). Artifact filenames include the tag name. Uses OIDC for AWS auth (requires `id-token: write` permission).

## Important Notes

- AVX512 is **disabled** by default (for generic CPU compatibility); see commit `ef7c228`
- The vcpkg `openblas` port is **not** usable here: it is built with `BUILD_WITHOUT_LAPACK=ON` / `NOFORTRAN=ON`, while FAISS requires LAPACK (`ssyev_`, `dsyev_`, `sgesvd_`, `dgesvd_`, `sgeqrf_`, `sorgqr_`). Its `dynamic-arch` feature is also unsupported on MSVC. The upstream OpenBLAS Windows release is used instead — it ships full LAPACK, an MSVC import library, and DYNAMIC_ARCH runtime CPU dispatch
- Use the `-x64` OpenBLAS release asset, not `-x64-64`: the latter is ILP64 (64-bit integer interface), which FAISS cannot use
- The Windows `libopenblas.dll` is a mingw-w64 build that statically links libgfortran and libwinpthread; see `THIRD-PARTY-NOTICES`
- BLAS choice affects index build (`train`/`add`) but not IVF search, which never calls BLAS
- `dist/`, `build/`, `build-demo/` and `build-deps/` are generated — do not commit them
