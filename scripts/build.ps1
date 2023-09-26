# param must be in the begin of PowerShell Script
param ($TARGET = "faiss-win64.7z")

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
rm -r build,dist
cmake -Bbuild `
    -G "Visual Studio 16 2019" -A "x64" `
    -Wno-dev `
    -DCMAKE_INSTALL_PREFIX="${DIST_PATH}" `
    -DFAISS_ENABLE_PYTHON=OFF `
    -DFAISS_ENABLE_GPU=OFF `
    -DBLA_VENDOR=Intel10_64lp `
    -DBUILD_TESTING=OFF `
    -DMKL_LIBRARIES="${MKL_LIBRARIES}" `
    faiss

cmake --build build --config Release --target install

Write-Output "::endgroup::"

# copy artifacts and change config
cp $MKL_PATH\mkl_intel_lp64.lib $DIST_PATH\lib
cp $MKL_PATH\mkl_intel_thread.lib $DIST_PATH\lib
cp $MKL_PATH\mkl_core.lib $DIST_PATH\lib
cp $MKL_PATH\libiomp5md.lib $DIST_PATH\lib
cp $MKL_PATH\libiomp5md.lib $DIST_PATH\lib
mkdir -p $DIST_PATH\bin
cp $MKL_PATH\..\..\bin\libiomp5md.dll $DIST_PATH\bin

# remap absolute path to relative dist path
$DOUBLE_QUOTE_PATH =  $MKL_PATH.Replace('\', '\\')
$FAISS_CMAKE = "$DIST_PATH\share\faiss\faiss-targets.cmake"
(Get-content $FAISS_CMAKE) | Foreach-Object {
    $_.Replace("$DOUBLE_QUOTE_PATH", '${_IMPORT_PREFIX}\\lib')
} | Set-Content $FAISS_CMAKE

# pack binary

Write-Output "::group::Pack artifacts ..."
# pack binary
Push-Location $DIST_PATH
7z a -m0=bcj -m1=zstd ..\$TARGET * | Out-Null
Pop-Location
Write-Output "::endgroup::"
