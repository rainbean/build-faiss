# param must be in the begin of PowerShell Script
param ($TARGET = "faiss-win64.7z")

# install 7-Zip if not available
if (!(Get-Command 7z -errorAction SilentlyContinue)) {
    Write-Output "::group::Install 7-Zip ..."
    winget install --id 7zip.7zip -e --silent
    $env:PATH += ";C:\Program Files\7-Zip"
    Write-Output "::endgroup::"
}

# install required 3rd party libraries
# x64-windows (dynamic) includes LAPACK routines; x64-windows-static omits them
if (!(Test-Path .\vcpkg\installed\x64-windows\lib)) {
    Write-Output "::group::Install vcpkg libraries ..."
    .\vcpkg\bootstrap-vcpkg.bat
    .\vcpkg\vcpkg install openblas --triplet x64-windows --clean-after-build
    Write-Output "::endgroup::"
}

# OpenBLAS import lib; pass explicitly so CMake's FindBLAS/FindLAPACK resolves correctly
$OPENBLAS_LIB = "$PWD\vcpkg\installed\x64-windows\lib\openblas.lib"
$DIST_PATH = "$PWD\dist"
$VCPKG_TOOLCHAIN = "$PWD\vcpkg\scripts\buildsystems\vcpkg.cmake"

# configure build and compile
Write-Output "::group::Configure CMake and Build ..."
if (Test-Path build) {
    rm -r build
}
if (Test-Path dist) {
    rm -r $DIST_PATH
}
cmake -Bbuild `
    -G "Visual Studio 17 2022" -A "x64" `
    -Wno-dev `
    -DCMAKE_INSTALL_PREFIX="${DIST_PATH}" `
    -DCMAKE_TOOLCHAIN_FILE="${VCPKG_TOOLCHAIN}" `
    -DVCPKG_TARGET_TRIPLET="x64-windows" `
    -DFAISS_ENABLE_PYTHON=OFF `
    -DFAISS_ENABLE_GPU=OFF `
    -DBUILD_TESTING=OFF `
    -DBLA_VENDOR=OpenBLAS `
    -DBLAS_LIBRARIES="${OPENBLAS_LIB}" `
    -DLAPACK_LIBRARIES="${OPENBLAS_LIB}" `
    -DBUILD_SHARED_LIBS=ON `
    faiss

cmake --build build --config Release --target install

Write-Output "::endgroup::"

# bundle OpenBLAS DLL so the artifact is self-contained
Write-Output "::group::Bundle OpenBLAS ..."
$OPENBLAS_BIN = "$PWD\vcpkg\installed\x64-windows\bin"
Copy-Item "$OPENBLAS_BIN\openblas.dll" "$DIST_PATH\bin\"

# rewrite absolute vcpkg path in cmake targets to relative install prefix
$FAISS_CMAKE = "$DIST_PATH\share\faiss\faiss-targets.cmake"
$VCPKG_BIN_ESC = $OPENBLAS_BIN.Replace('\', '\\')
(Get-Content $FAISS_CMAKE) | ForEach-Object {
    $_ -replace [regex]::Escape($OPENBLAS_BIN), '${_IMPORT_PREFIX}/bin' `
       -replace $VCPKG_BIN_ESC, '${_IMPORT_PREFIX}/bin'
} | Set-Content $FAISS_CMAKE

Write-Output "::endgroup::"

Write-Output "::group::Pack artifacts ..."
Push-Location $DIST_PATH
7z a -mx=9 ..\$TARGET *
Pop-Location

Write-Output "::endgroup::"
