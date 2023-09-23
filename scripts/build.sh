#!/bin/bash

# export PATH="$PATH:/usr/local/cuda/bin"
# export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/cuda/lib64

# abort on any error
set -e

# install required 3rd party libraries
if [ ! -d "./vcpkg/installed/x64-linux/lib" ]
then
    echo "::group::Install vcpkg libraries ..."
    ./vcpkg/bootstrap-vcpkg.sh
    ./vcpkg/vcpkg install intel-mkl --triplet x64-linux --clean-after-build
    echo "::endgroup::"
fi

export MKL_PATH=$PWD/vcpkg/installed/x64-linux/lib/intel64

# configure build and compile
echo "::group::Configure CMake and Build ..."
rm -fr build
cmake -Bbuild \
    -Wno-dev \
    -DFAISS_ENABLE_PYTHON=OFF \
    -DFAISS_OPT_LEVEL=avx2 \
    -DFAISS_ENABLE_GPU=OFF \
    -DBLA_VENDOR=Intel10_64lp \
    "-DMKL_LIBRARIES=-Wl,--start-group;${MKL_PATH}/libmkl_intel_lp64.a;${MKL_PATH}/libmkl_gnu_thread.a;${MKL_PATH}/libmkl_core.a;-Wl,--end-group -ldl" \
    faiss

make -C build -j4 faiss
make -C build -j4 demo_ivfpq_indexing
echo "::endgroup::"


