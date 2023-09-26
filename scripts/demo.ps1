# configure build and compile
echo "::group::Configure CMake and Build ..."
Remove-Item -LiteralPath "build-demo" -Force -Recurse
cmake -G "Visual Studio 16 2019" -A "x64" -Bbuild-demo -Wno-dev demo

cmake --build build-demo --config Release --target demo
echo "::endgroup::"

