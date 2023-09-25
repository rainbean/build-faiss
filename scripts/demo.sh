#!/bin/bash

# abort on any error
set -e

# configure build and compile
echo "::group::Configure CMake and Build ..."
rm -fr build-demo
cmake -Bbuild-demo -Wno-dev demo

make -C build-demo -j4 demo
echo "::endgroup::"

