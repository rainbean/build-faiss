# param must be in the begin of PowerShell Script
param ($TARGET = "faiss-win64.7z")

# install 7zip ZSTD plugin
if (!(Get-Command 7z -errorAction SilentlyContinue)) {
    Write-Output "::group::Install 7-Zip ..."
    winget install --id 7zip-zstd -e --silent
    $env:PATH += ";C:\Program Files\7-Zip-Zstandard"
    Write-Output "::endgroup::"
}

$DIST_PATH = "$PWD\dist"

# faiss needs both BLAS and LAPACK. The vcpkg openblas port cannot supply them:
# it is configured with BUILD_WITHOUT_LAPACK=ON / NOFORTRAN=ON, and its
# dynamic-arch feature is unsupported on MSVC, which would pin the artifact to
# the CPU that built it. The upstream Windows release ships full LAPACK, an
# MSVC import library, and DYNAMIC_ARCH runtime CPU dispatch.
$OPENBLAS_VERSION = "0.3.34"
$DEPS_PATH = "$PWD\build-deps"
$OPENBLAS_ROOT = "$DEPS_PATH\OpenBLAS-${OPENBLAS_VERSION}-x64"
$BLAS_LIB_PATH = "$OPENBLAS_ROOT\lib"
$RUNTIME_DLL = "$OPENBLAS_ROOT\bin\libopenblas.dll"

if (!(Test-Path $OPENBLAS_ROOT)) {
    Write-Output "::group::Download OpenBLAS ${OPENBLAS_VERSION} ..."
    New-Item -ItemType Directory -Force $DEPS_PATH | Out-Null
    $zip = "$DEPS_PATH\OpenBLAS-${OPENBLAS_VERSION}-x64.zip"
    if (!(Test-Path $zip)) {
        # -x64 is the LP64 build; the -x64-64 asset is ILP64, which faiss cannot use
        $url = "https://github.com/OpenMathLib/OpenBLAS/releases/download/v${OPENBLAS_VERSION}/OpenBLAS-${OPENBLAS_VERSION}-x64.zip"
        Invoke-WebRequest -Uri $url -OutFile $zip
    }
    Expand-Archive $zip -DestinationPath $OPENBLAS_ROOT -Force
    Write-Output "::endgroup::"
}

# fail early and loudly if the OpenBLAS release layout changed
foreach ($file in @("$BLAS_LIB_PATH\libopenblas.lib", $RUNTIME_DLL)) {
    if (!(Test-Path $file)) {
        throw "OpenBLAS: expected file not found: $file"
    }
}

# configure build and compile
Write-Output "::group::Configure CMake and Build ..."
if (Test-Path build) {
    rm -r build
}
if (Test-Path dist) {
    rm -r $DIST_PATH
}
# BLA_VENDOR=OpenBLAS makes FindBLAS look for a library named openblas;
# CMAKE_PREFIX_PATH points it at the extracted release.
cmake -Bbuild `
    -G "Visual Studio 17 2022" -A "x64" `
    -Wno-dev `
    -DCMAKE_INSTALL_PREFIX="${DIST_PATH}" `
    -DFAISS_ENABLE_PYTHON=OFF `
    -DFAISS_ENABLE_GPU=OFF `
    -DBUILD_TESTING=OFF `
    -DBLA_VENDOR=OpenBLAS `
    -DCMAKE_PREFIX_PATH="${OPENBLAS_ROOT}" `
    -DBUILD_SHARED_LIBS=ON `
    faiss

cmake --build build --config Release --target install

Write-Output "::endgroup::"

Write-Output "::group::Pack artifacts ..."

# copy the BLAS runtime next to faiss.dll
cp $RUNTIME_DLL $DIST_PATH\bin

# remap absolute path to relative dist path
$DOUBLE_QUOTE_PATH = $BLAS_LIB_PATH.Replace('\', '\\')
$FAISS_CMAKE = "$DIST_PATH\share\faiss\faiss-targets.cmake"
(Get-content $FAISS_CMAKE) | Foreach-Object {
    $_.Replace("$DOUBLE_QUOTE_PATH", '${_IMPORT_PREFIX}\\lib')
} | Set-Content $FAISS_CMAKE

# copy license files into dist so they are included in the archive
cp LICENSE, THIRD-PARTY-NOTICES $DIST_PATH

# pack binary
Push-Location $DIST_PATH
7z a -mx=9 ..\$TARGET * | Out-Null
Pop-Location

Write-Output "::endgroup::"
