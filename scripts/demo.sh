#!/usr/bin/env bash

# abort on any error
set -e

# configure build and compile all tools
echo "::group::Configure CMake and Build ..."
rm -fr build-demo
cmake -Bbuild-demo -Wno-dev demo
cmake --build build-demo -j "$(nproc)" -t demo test_cosine bench_cosine
echo "::endgroup::"
