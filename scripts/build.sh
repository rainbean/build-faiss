#!/bin/bash

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

MKL_PATH=$PWD/vcpkg/installed/x64-linux/lib/intel64
MKL_LIBRARIES="-Wl,--start-group;${MKL_PATH}/libmkl_intel_lp64.a;${MKL_PATH}/libmkl_gnu_thread.a;${MKL_PATH}/libmkl_core.a;-Wl,--end-group -ldl"

# configure build and compile
echo "::group::Configure CMake and Build ..."
rm -fr build
cmake -Bbuild \
    -Wno-dev \
    -DFAISS_ENABLE_PYTHON=OFF \
    -DFAISS_OPT_LEVEL=avx2 \
    -DFAISS_ENABLE_GPU=OFF \
    -DBLA_VENDOR=Intel10_64lp \
    -DMKL_LIBRARIES="${MKL_LIBRARIES}" \
    faiss

make -C build -j4 faiss
make -C build -j4 demo_ivfpq_indexing
echo "::endgroup::"

ls -lah build/faiss/libfaiss.a
ls -lah build/demos/demo_ivfpq_indexing
