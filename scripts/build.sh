#!/bin/bash

# abort on any error
set -e

export PATH="$PATH:/usr/local/cuda/bin"
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/cuda/lib64

# test if cuda installed
if ! command -v nvcc &> /dev/null
then
    echo "::group::Install CUDA, sudo permission required ..."
    wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb -O /tmp/cuda.deb
    sudo dpkg -i /tmp/cuda.deb
    sudo apt-get update
    sudo apt-get install -y cuda-toolkit-11-8
    echo "::endgroup::"
fi

# install required 3rd party libraries
if [ ! -d "./vcpkg/installed/x64-linux/lib" ]
then
    echo "::group::Install vcpkg libraries ..."
    ./vcpkg/bootstrap-vcpkg.sh
    ./vcpkg/vcpkg install intel-mkl --triplet x64-linux --clean-after-build
    echo "::endgroup::"
fi

# define MKL path
MKL_PATH=$PWD/vcpkg/installed/x64-linux/lib/intel64
MKL_LIBRARIES="-Wl,--start-group;${MKL_PATH}/libmkl_intel_lp64.a;${MKL_PATH}/libmkl_gnu_thread.a;${MKL_PATH}/libmkl_core.a;-Wl,--end-group -lpthread -ldl"
DIST_PATH=dist

# configure build and compile
echo "::group::Configure CMake and Build ..."
rm -fr build dist
cmake -Bbuild \
    -Wno-dev \
    -DCMAKE_INSTALL_PREFIX="${DIST_PATH}" \
    -DCMAKE_IGNORE_PREFIX_PATH="$HOME/mamba" \
    -DFAISS_ENABLE_PYTHON=OFF \
    -DBUILD_TESTING=OFF \
    -DMKL_LIBRARIES="${MKL_LIBRARIES}" \
    -DBLA_VENDOR=Intel10_64lp \
    -DFAISS_ENABLE_GPU=ON \
    -DFAISS_OPT_LEVEL=avx512 \
    faiss

cmake --build build -j 4 -t install
echo "::endgroup::"

# copy artifacts and change config
cp $MKL_PATH/libmkl_intel_lp64.a $DIST_PATH/lib
cp $MKL_PATH/libmkl_gnu_thread.a $DIST_PATH/lib
cp $MKL_PATH/libmkl_core.a $DIST_PATH/lib

# remap absolute path to relative dist path
sed -i "s@$MKL_PATH@\${_IMPORT_PREFIX}/lib@g" $DIST_PATH/share/faiss/faiss-targets.cmake

# pack binary
echo "::group::Pack artifacts ..."
TARGET=${1:-'faiss-linux.tar.zst'}
tar "-I zstd -3 -T4 --long=27" -cf $TARGET \
    -C $DIST_PATH $(cd $DIST_PATH; echo *)
echo "::endgroup::"
