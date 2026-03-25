# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repository builds and packages [FAISS](https://github.com/facebookresearch/faiss) (Facebook AI Similarity Search) as distributable binaries for Linux and Windows. The FAISS source and vcpkg package manager are git submodules. Builds link against Intel MKL (via vcpkg) for optimized BLAS performance.

## Setup

Fresh clone requires submodules:
```bash
git clone --recurse-submodules <repo>
# or after cloning: git submodule update --init --recursive
```

## Key Commands

### Build (Linux)
```bash
./scripts/build.sh [optional_output_filename]
# Produces: faiss-linux.tar.zst (or specified filename)
# Output artifact unpacks to: dist/
```

vcpkg installs intel-mkl only on first run (skipped if `vcpkg/installed/x64-linux/lib` exists). Re-running the build script after the first time skips the vcpkg step.

### Build (Windows)
```powershell
.\scripts\build.ps1 [optional_output_filename]
# Produces: faiss-win64.7z
# Requires: Chocolatey (for 7zip-zstd), MSBuild / Visual Studio 2022
```

The Windows script patches `vcpkg/ports/intel-mkl/portfile.cmake` in-place before first install (replaces `ilp64`→`lp64`, `sequential`→`intel_thread`). This modifies a tracked file in the `vcpkg` submodule.

### Build and Run Demo
```bash
# dist/ must exist (run build.sh first)
./scripts/demo.sh && time ./build-demo/demo
```

The demo compiles `demo/demo_ivfpq_indexing.cpp` against the built `dist/` artifacts and runs an IVFPQ indexing benchmark on random 128D vectors. It also requires OpenMP at link time.

## Architecture

### Submodules
- `faiss/` — Facebook Research FAISS source (do not edit)
- `vcpkg/` — Microsoft vcpkg C++ package manager (do not edit)

### Build Flow
1. **vcpkg** bootstraps and installs `intel-mkl` (`x64-linux` or `x64-windows-static` triplet)
2. **CMake** configures the `faiss/` submodule with:
   - `BLA_VENDOR=Intel10_64lp` (static MKL linking)
   - Python and GPU support disabled
   - Shared library output
3. Install target copies artifacts to `dist/`
4. Post-processing: absolute MKL paths in `dist/share/faiss/faiss-targets.cmake` are rewritten to relative `${_IMPORT_PREFIX}/lib` paths (so the tarball is relocatable)
5. Archive packed with zstd compression (Linux) or 7z (Windows)

### Demo App
`demo/CMakeLists.txt` finds the FAISS package from `../dist` and links against it. The demo (`demo_ivfpq_indexing.cpp`) validates the build by training an IVFPQ index, inserting vectors, and querying nearest neighbors.

### CI/CD
`.github/workflows/build.yml` triggers on any git tag push, builds on Ubuntu 22.04 and Windows 2022, and uploads artifacts to AWS S3 (ap-northeast-1). Artifact filenames include the tag name: `faiss-linux-{tag}.tar.zst` and `faiss-win64-{tag}.7z`. Uses OIDC for AWS auth (requires `id-token: write` permission).

## Important Notes

- AVX512 is **disabled** by default (for generic CPU compatibility); see commit `ef7c228`
- The Windows build patches the intel-mkl vcpkg port to use `lp64` and `intel_thread` instead of `ilp64`/`sequential`
- Only `vcpkg/` is excluded from Claude's context via `.claudeignore` — `faiss/` is not excluded (but is a read-only submodule)
- `dist/` and `build/` directories are generated artifacts — do not commit them
