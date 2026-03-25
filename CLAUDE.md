# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repository builds and packages [FAISS](https://github.com/facebookresearch/faiss) (Facebook AI Similarity Search) as distributable binaries for Linux and Windows. The FAISS source and vcpkg package manager are git submodules. Builds link against Intel MKL (via vcpkg) for optimized BLAS performance.

## Key Commands

### Build (Linux)
```bash
./scripts/build.sh [optional_output_filename]
# Produces: faiss-linux.tar.zst (or specified filename)
# Output artifact unpacks to: dist/
```

### Build (Windows)
```powershell
.\scripts\build.ps1 [optional_output_filename]
# Produces: faiss-win64.7z
```

### Build and Run Demo
```bash
./scripts/build.sh && ./scripts/demo.sh && time ./build-demo/demo
```

The demo compiles `demo/demo_ivfpq_indexing.cpp` against the built `dist/` artifacts and runs an IVFPQ indexing benchmark on random 128D vectors.

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
`.github/workflows/build.yml` triggers on git tag pushes, builds on Ubuntu 22.04 and Windows 2022, and uploads artifacts to AWS S3.

## Important Notes

- AVX512 is **disabled** by default (for generic CPU compatibility); see commit `ef7c228`
- The Windows build patches the intel-mkl vcpkg port to use `lp64` and `intel_thread` instead of `ilp64`/`sequential`
- `faiss/` and `vcpkg/` are excluded from Claude's context via `.claudeignore`
- `dist/` and `build/` directories are generated artifacts — do not commit them
