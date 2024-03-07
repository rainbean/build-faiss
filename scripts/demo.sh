#!/bin/bash

# abort on any error
set -e

# configure build and compile
echo "::group::Configure CMake and Build ..."
rm -fr build-demo
cmake -Bbuild-demo -Wno-dev demo
cmake --build build-demo -j 4 -t demo
echo "::endgroup::"

