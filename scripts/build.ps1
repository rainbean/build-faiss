# param must be in the begin of PowerShell Script
param ($TARGET = "faiss-win64.7z")

# install 7zip ZSTD plugin
if (!(choco list --lo --r -e 7zip-zstd)) {
    Write-Output "::group::Install 7Z-ZSTD plugin ..."
    choco install -y 7zip-zstd | Out-Null
    Write-Output "::endgroup::"
}

# install required 3rd party libraries
if (!(Test-Path .\vcpkg\installed\x64-windows-static)) {
    # refer to https://github.com/facebookresearch/faiss/issues/2641
    # replace MKL interface to LP
    $MKL_CMAKE = ".\vcpkg\ports\intel-mkl\portfile.cmake"
    (Get-content $MKL_CMAKE) | Foreach-Object {
        $_ -replace "ilp64", "lp64" -replace "sequential", "intel_thread" 
    } | Set-Content $MKL_CMAKE

    Write-Output "::group::Install vcpkg libraries ..."
    .\vcpkg\bootstrap-vcpkg.bat
    .\vcpkg\vcpkg install intel-mkl --triplet x64-windows-static --clean-after-build
    Write-Output "::endgroup::"
}

# define MKL path
$MKL_PATH = "$PWD\vcpkg\installed\x64-windows-static\lib\intel64"
$MKL_LIBRARIES = "${MKL_PATH}\mkl_intel_lp64.lib;${MKL_PATH}\mkl_intel_thread.lib;${MKL_PATH}\mkl_core.lib;${MKL_PATH}\libiomp5md.lib"
$DIST_PATH = "$PWD\dist"

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
    -DFAISS_ENABLE_PYTHON=OFF `
    -DFAISS_ENABLE_GPU=OFF `
    -DBUILD_TESTING=OFF `
    -DBLA_VENDOR=Intel10_64lp `
    -DMKL_LIBRARIES="${MKL_LIBRARIES}" `
    -DBUILD_SHARED_LIBS=ON `
    faiss

cmake --build build --config Release --target install

Write-Output "::endgroup::"

Write-Output "::group::Pack artifacts ..."

# copy artifacts and change config
cp $MKL_PATH\..\..\bin\libiomp5md.dll $DIST_PATH\bin

# remap absolute path to relative dist path
$DOUBLE_QUOTE_PATH =  $MKL_PATH.Replace('\', '\\')
$FAISS_CMAKE = "$DIST_PATH\share\faiss\faiss-targets.cmake"
(Get-content $FAISS_CMAKE) | Foreach-Object {
    $_.Replace("$DOUBLE_QUOTE_PATH", '${_IMPORT_PREFIX}\\lib')
} | Set-Content $FAISS_CMAKE

# pack binary
Push-Location $DIST_PATH
7z a -m0=bcj -m1=zstd ..\$TARGET * | Out-Null
Pop-Location

Write-Output "::endgroup::"
